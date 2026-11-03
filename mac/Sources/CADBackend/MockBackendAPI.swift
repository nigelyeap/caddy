import Foundation
import CADShared

/// Fake backend for previews and tests. Canned answers, optional delay and failure.
public actor MockBackendAPI: BackendAPI {
    public private(set) var state: ModelState
    public var delay: Duration
    /// When set, every call throws this.
    public var failure: APIFailure?
    private var frames = 0

    public init(ready: Bool = true, delay: Duration = .milliseconds(200), failure: APIFailure? = nil) {
        state = Self.decode(ready ? Self.readyJSON : Self.idleJSON)
        self.delay = delay
        self.failure = failure
    }

    public func setFailure(_ f: APIFailure?) { failure = f }
    public func setDelay(_ d: Duration) { delay = d }

    public func status() async throws -> ModelState { try await gate(); return state }

    public func sendFrame(jpeg: Data) async throws -> GuidanceResult {
        try await gate()
        frames += 1
        var g: GuidanceResult = Self.decode(Self.guidanceJSON)
        let filled = min(12, frames / 2)
        g.coverage.sectors = (0..<12).map { $0 < filled ? 1 : 0 }
        g.coverage.pct = Double(filled) / 12 * 100
        g.t = Double(frames)
        return g
    }

    public func resetGuidance() async throws { try await gate(); frames = 0 }

    public func uploadScan(fileURL: URL) async throws {
        try await gate()
        let ext = fileURL.pathExtension.lowercased()
        let mesh = ["stl", "ply", "obj", "txt", "csv"].contains(ext)
        state.status = .ready
        state.sample = !mesh
        state.versions = [Self.version("v0.stl", mesh ? "Your scan" : "Sample cup")]
        state.redo = []
        state.started = Date().timeIntervalSince1970
    }

    public func edit(instruction: String) async throws -> ModelState {
        try await gate()
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw APIFailure(statusCode: 400, message: "Type what you want to change.") }
        if state.versions.isEmpty { throw APIFailure(statusCode: 409, message: "There is no model yet. Scan something first.") }
        state.versions.append(Self.version("v\(state.versions.count).stl", text))
        state.redo = []
        return state
    }

    public func undo() async throws -> ModelState {
        try await gate()
        if state.versions.count > 1 { state.redo.append(state.versions.removeLast()) }
        return state
    }

    public func redo() async throws -> ModelState {
        try await gate()
        if let v = state.redo.popLast() { state.versions.append(v) }
        return state
    }

    /// Writes a single triangle binary STL.
    public func downloadModel(to destination: URL) async throws {
        try await gate()
        if state.versions.isEmpty { throw APIFailure(statusCode: 404, message: "There is no model yet. Scan something first.") }
        var d = Data(count: 80)
        var count = UInt32(1).littleEndian
        d.append(Data(bytes: &count, count: 4))
        for f: Float32 in [0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 10, 0] {
            var v = f.bitPattern.littleEndian
            d.append(Data(bytes: &v, count: 4))
        }
        d.append(Data(count: 2))
        try d.write(to: destination, options: .atomic)
    }

    private func gate() async throws {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
    }

    // ModelState and GuidanceResult have no public memberwise init, so build them from JSON.
    private static func version(_ file: String, _ instruction: String) -> ModelVersion {
        try! JSONDecoder().decode(ModelVersion.self, from: JSONEncoder().encode(["file": file, "instruction": instruction]))
    }

    private static func decode<T: Decodable>(_ s: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    static let idleJSON = #"{"status":"idle","error":null,"detail":null,"versions":[],"redo":[],"sample":false,"started":null,"engine":"stub"}"#
    static let readyJSON = #"{"status":"ready","error":null,"detail":null,"versions":[{"file":"v0.stl","instruction":"Sample cup"}],"redo":[],"sample":true,"started":null,"engine":"stub"}"#
    static let guidanceJSON = #"{"blur":{"score":212.4,"ok":true},"light":{"mean":121.0,"clipped_pct":0.4,"ok":true,"issue":null},"tracking":{"match_ratio":0.8,"ok":true},"speed":{"value":12.5,"ok":true},"coverage":{"sectors":[0,0,0,0,0,0,0,0,0,0,0,0],"pct":0},"warnings":[],"t":0}"#
}
