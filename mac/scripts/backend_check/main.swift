// End to end check for CADBackend. Built and run by ../backend_check.sh.
// Starts the real server on a spare port with a FAKE key, hits every endpoint, then stops it.
import AppKit
import Foundation
import CADShared
@testable import CADBackend

setvbuf(stdout, nil, _IONBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}
func expectFailure(_ what: String, code: Int?, _ body: () async throws -> Void) async {
    do { try await body(); check(false, what + " (no error)") } catch let e as APIFailure {
        check(e.statusCode == code && !e.message.isEmpty, what + " -> \(e.statusCode.map(String.init) ?? "nil") \(e.message)")
    } catch { check(false, what + " -> \(error)") }
}
@MainActor func waitFor(_ s: BackendService, _ seconds: Double, _ cond: (BackendService.Phase) -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while Date() < end { if cond(s.phase) { return true }; try? await Task.sleep(for: .milliseconds(200)) }
    return cond(s.phase)
}

let port = Int(CommandLine.arguments.dropFirst().first ?? "8765")!
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("cad-backend-check-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tmp) }

// Key file parsing, fake values only.
check(BackendService.parseKey("ANTHROPIC_API_KEY=sk-fake-1\n") == "sk-fake-1", "parseKey plain")
check(BackendService.parseKey("# c\nexport ANTHROPIC_API_KEY = \"sk-fake-2\"\n") == "sk-fake-2", "parseKey export and quotes")
check(BackendService.parseKey("ANTHROPIC_API_KEY=sk-fake-3 # note") == "sk-fake-3", "parseKey trailing comment")
check(BackendService.parseKey("ANTHROPIC_API_KEY=\nOTHER=1") == nil, "parseKey empty")
check(BackendService.parseKey("ANTHROPIC_API_KEY_OLD=x") == nil, "parseKey ignores similar names")

// Connection failure maps to isConnectionLost.
do {
    _ = try await HTTPBackendAPI(baseURL: URL(string: "http://127.0.0.1:1")!).status()
    check(false, "dead port should fail")
} catch let e as APIFailure { check(e.isConnectionLost, "dead port -> isConnectionLost") }

let keyFile = tmp.appendingPathComponent("fake_key.txt")
try "ANTHROPIC_API_KEY=sk-ant-fake-for-tests\n".write(to: keyFile, atomically: true, encoding: .utf8)

// Main run without a key, so the canned example edits work.
let svc = BackendService(keyFile: tmp.appendingPathComponent("missing.txt"), preferredPort: port)
await svc.start()
check(svc.phase == .running, "service running (\(svc.phase))")
check(!svc.hasAPIKey, "hasAPIKey false without key file")
let api = svc.api

var s = try await api.status()
check(["stub", "real"].contains(s.engine), "status engine=\(s.engine)")
try await api.resetGuidance()
check(true, "guidance reset")

// A small real JPEG.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 48, bitsPerSample: 8, samplesPerPixel: 3,
                           hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let jpeg = rep.representation(using: .jpeg, properties: [:])!
let g = try await api.sendFrame(jpeg: jpeg)
check(g.coverage.sectors.count == 12, "frame -> 12 sectors, warnings=\(g.warnings.count)")
await expectFailure("frame not a JPEG", code: 400) { _ = try await api.sendFrame(jpeg: Data("nope".utf8)) }

// Upload an empty video, poll until ready.
let video = tmp.appendingPathComponent("sample.webm")
FileManager.default.createFile(atPath: video.path, contents: Data())
try await api.uploadScan(fileURL: video)
for _ in 0..<60 { s = try await api.status(); if s.status != .processing { break }; try await Task.sleep(for: .seconds(1)) }
check(s.status == .ready && s.sample && s.versions.count == 1, "upload video -> sample cup ready")

// Upload a real mesh, streamed from disk.
let mesh = tmp.appendingPathComponent("cup.stl")
try await api.downloadModel(to: mesh)
try await api.uploadScan(fileURL: mesh)
for _ in 0..<120 { s = try await api.status(); if s.status != .processing { break }; try await Task.sleep(for: .seconds(1)) }
check(s.status == .ready && !s.sample, "upload stl -> your scan ready (\(s.status) \(s.error ?? ""))")

s = try await api.edit(instruction: "make it 20 percent taller")
check(s.versions.count == 2 && s.versions.last?.instruction == "make it 20 percent taller", "edit canned")
await expectFailure("edit empty", code: 400) { _ = try await api.edit(instruction: "  ") }
s = try await api.undo()
check(s.versions.count == 1 && s.redo.count == 1, "undo")
s = try await api.redo()
check(s.versions.count == 2 && s.redo.isEmpty, "redo")

await expectFailure("free-text edit without key", code: 500) { _ = try await api.edit(instruction: "add a small handle on one side") }

// Download twice: second time replaces the file atomically.
let out = tmp.appendingPathComponent("model.stl")
try await api.downloadModel(to: out)
try await api.downloadModel(to: out)
let size = (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int) ?? 0
check(size > 84 && (size - 84) % 50 == 0, "download STL size \(size)")

// A second service reuses the healthy server.
let second = BackendService(keyFile: keyFile, preferredPort: port)
await second.start()
check(second.phase == .running && second.diagnostics.contains("already running"), "second service reuses server")
if !second.diagnostics.contains("already running") { print(second.phase, second.diagnostics.suffix(600)) }
second.stop()

// Kill the server behind the service's back. It must notice and restart.
let pkill = Process()
pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
pkill.arguments = ["-f", "uvicorn app:app --host 127.0.0.1 --port \(port)"]
try pkill.run(); pkill.waitUntilExit()
try await Task.sleep(for: .milliseconds(500))
_ = try? await api.status()
check(await waitFor(svc, 10) { $0 == .lostContact || $0 == .running }, "lost contact noticed (\(svc.phase))")
check(await waitFor(svc, 120) { $0 == .running }, "restarted (\(svc.phase))")
check(svc.diagnostics.contains("Restarting server"), "restart happened")
s = try await api.status()
check(s.status == .ready, "state survives restart")

svc.stop()
for _ in 0..<50 where !BackendService.canBind(port) { try await Task.sleep(for: .milliseconds(100)) }
check(BackendService.canBind(port), "port \(port) free after stop")

// Second server on the next port with the FAKE key. The key must arrive: a free-text edit tries Claude.
let keyed = BackendService(keyFile: keyFile, preferredPort: port + 1)
await keyed.start()
check(keyed.phase == .running && keyed.hasAPIKey, "keyed service running with hasAPIKey")
// Without a key this canned example works. With the fake key it goes to Claude and fails.
await expectFailure("canned edit fails with fake key, so the key arrived", code: 500) {
    _ = try await keyed.api.edit(instruction: "make it 20 percent taller")
}
check(!keyed.diagnostics.contains("sk-ant-fake"), "key never appears in server output")
keyed.stop()
for _ in 0..<50 where !BackendService.canBind(port + 1) { try await Task.sleep(for: .milliseconds(100)) }
check(BackendService.canBind(port + 1), "port \(port + 1) free after stop")

print("--- diagnostics tail ---")
print(svc.diagnostics.split(separator: "\n").suffix(8).joined(separator: "\n"))
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
