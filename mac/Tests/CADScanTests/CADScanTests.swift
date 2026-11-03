import AVFoundation
import CADShared
import ImageIO
import SwiftUI
import XCTest
@testable import CADScan

final class FrameGateTests: XCTestCase {
    func testSendsOncePerSecondAndDropsWhileWaiting() {
        var gate = FrameGate()
        XCTAssertTrue(gate.shouldSend(now: 10))
        gate.didSend(now: 10)
        XCTAssertFalse(gate.shouldSend(now: 10.5), "in flight")
        XCTAssertFalse(gate.shouldSend(now: 12), "still in flight, so the frame is dropped")
        gate.didAnswer()
        XCTAssertTrue(gate.shouldSend(now: 12))
        gate.didSend(now: 12)
        gate.didAnswer()
        XCTAssertFalse(gate.shouldSend(now: 12.9), "less than a second")
        XCTAssertTrue(gate.shouldSend(now: 13.0))
    }

    func testChecksStopAfterThreeFailures() {
        var gate = FrameGate()
        for i in 0..<2 { gate.didSend(now: Double(i)); gate.didFail(connectionLost: false) }
        XCTAssertFalse(gate.checksStopped)
        gate.didSend(now: 3); gate.didFail(connectionLost: false)
        XCTAssertTrue(gate.checksStopped)
        XCTAssertFalse(gate.lostContact)
        gate.didSend(now: 4); gate.didAnswer()
        XCTAssertFalse(gate.checksStopped)
    }

    func testLostContactAtOnce() {
        var gate = FrameGate()
        gate.didSend(now: 0); gate.didFail(connectionLost: true)
        XCTAssertTrue(gate.lostContact)
        XCTAssertTrue(gate.checksStopped)
        XCTAssertEqual(GuidanceText.message(nil, recording: true, gate: gate)?.text, GuidanceText.lost)
        XCTAssertTrue(ScanModel.isConnectionLost(URLError(.cannotConnectToHost)))
        XCTAssertFalse(ScanModel.isConnectionLost(APIFailure(message: "bad frame")))
    }
}

final class TextAndStateTests: XCTestCase {
    func testClock() {
        XCTAssertEqual(RecClock.format(0), "0:00")
        XCTAssertEqual(RecClock.format(7.9), "0:07")
        XCTAssertEqual(RecClock.format(65), "1:05")
        XCTAssertEqual(RecClock.format(750), "12:30")
        XCTAssertEqual(RecClock.format(-3), "0:00")
    }

    func testPermissionMapping() {
        XCTAssertEqual(CameraState.from(auth: .notDetermined, hasCamera: true), .notDetermined)
        XCTAssertEqual(CameraState.from(auth: .denied, hasCamera: true), .denied)
        XCTAssertEqual(CameraState.from(auth: .restricted, hasCamera: true), .restricted)
        XCTAssertEqual(CameraState.from(auth: .authorized, hasCamera: false), .noCamera)
        XCTAssertEqual(CameraState.from(auth: .authorized, hasCamera: true), .checking)
        XCTAssertEqual(CameraState.from(error: ScanSourceError.inUse), .inUse)
        XCTAssertEqual(CameraState.from(error: ScanSourceError.noCamera), .noCamera)
        XCTAssertEqual(CameraState.from(error: ScanSourceError.disconnected), .disconnected)
        XCTAssertEqual(CameraState.from(error: ScanSourceError.notAllowed), .denied)

        XCTAssertEqual(CameraState.notDetermined.card?.title, "Camera access needed")
        XCTAssertEqual(CameraState.notDetermined.card?.actions, [.allowCamera])
        XCTAssertEqual(CameraState.denied.card, CameraState.restricted.card)
        XCTAssertEqual(CameraState.denied.card?.actions, [.openSettings, .useSample])
        XCTAssertEqual(CameraState.noCamera.card?.title, "No camera found")
        XCTAssertEqual(CameraState.inUse.card?.title, "Another app is using the camera")
        XCTAssertEqual(CameraState.disconnected.card?.actions, [.tryAgain])
        XCTAssertNil(CameraState.ready.card)
        XCTAssertEqual(CameraState.settingsURL.absoluteString,
                       "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    func testCopyStyle() {
        let states: [CameraState] = [.notDetermined, .denied, .noCamera, .inUse, .disconnected]
        let texts = states.compactMap(\.card).flatMap { [$0.title, $0.text] }
            + [GuidanceText.good, GuidanceText.nearlyDone, GuidanceText.stopped, GuidanceText.lost, GuidanceText.empty, GuidanceText.practice]
        for t in texts {
            XCTAssertFalse(t.contains("\u{2014}") || t.contains(";"), t)
        }
    }

    func testChipsAndMessages() {
        let gate = FrameGate()
        var g = PreviewBackendAPI.result(frame: 9)   // a "too fast" frame
        XCTAssertEqual(GuidanceText.chips(g, recording: false, stopped: false).map(\.id), ["focus", "light"])
        let chips = GuidanceText.chips(g, recording: true, stopped: false)
        XCTAssertEqual(chips.map(\.id), ["focus", "light", "tracking", "speed"])
        XCTAssertEqual(chips.last, ChipInfo(id: "speed", word: "Too fast", level: .bad))
        XCTAssertEqual(GuidanceText.message(g, recording: true, gate: gate)?.tone, .warning)
        XCTAssertNil(GuidanceText.message(g, recording: false, gate: gate), "speed does not matter before Start")
        XCTAssertTrue(GuidanceText.chips(g, recording: true, stopped: true).allSatisfy { $0.level == .neutral })
        XCTAssertEqual(GuidanceText.problems(chips).map(\.id), ["speed"], "only the problem chip shows")
        XCTAssertTrue(GuidanceText.problems(GuidanceText.chips(g, recording: true, stopped: true)).isEmpty)

        g = PreviewBackendAPI.result(frame: 20)
        XCTAssertEqual(GuidanceText.message(g, recording: true, gate: gate), OverlayMessage(text: GuidanceText.good, tone: .good))
        g = PreviewBackendAPI.result(frame: 36)
        XCTAssertEqual(g.coverage.pct, 100, accuracy: 0.01)
        XCTAssertEqual(GuidanceText.message(g, recording: true, gate: gate)?.tone, .done)
    }
}

final class SourceTests: XCTestCase {
    func testPreviewFramesAreDeterministic() throws {
        let source = PreviewScanSource(width: 320, height: 180)
        let a = try XCTUnwrap(source.frame(at: 17)), b = try XCTUnwrap(source.frame(at: 17))
        XCTAssertEqual(a.time, 17.0 / 15.0)
        XCTAssertEqual(FrameEncoder.jpeg(a.pixelBuffer), FrameEncoder.jpeg(b.pixelBuffer))
        XCTAssertNotEqual(FrameEncoder.jpeg(a.pixelBuffer), FrameEncoder.jpeg(try XCTUnwrap(source.frame(at: 40)).pixelBuffer))
    }

    func testJPEGIs640WideAndSmall() throws {
        let frame = try XCTUnwrap(PreviewScanSource(width: 1280, height: 720).frame(at: 3))
        let jpeg = try XCTUnwrap(FrameEncoder.jpeg(frame.pixelBuffer))
        let src = try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int, 640)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int, 360)
        XCTAssertLessThan(jpeg.count, 80_000)
        XCTAssertGreaterThan(jpeg.count, 2_000)
        // A small frame is not scaled up.
        let small = try XCTUnwrap(PreviewScanSource(width: 320, height: 180).frame(at: 0))
        let smallJPEG = try XCTUnwrap(FrameEncoder.jpeg(small.pixelBuffer))
        let smallProps = CGImageSourceCopyPropertiesAtIndex(CGImageSourceCreateWithData(smallJPEG as CFData, nil)!, 0, nil) as? [CFString: Any]
        XCTAssertEqual(smallProps?[kCGImagePropertyPixelWidth] as? Int, 320)
    }

    func testPreviewRecordsAMovie() async throws {
        let source = PreviewScanSource(fps: 20)
        try await source.start()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cadscan-test-\(UUID()).mov")
        try source.startRecording(to: url)
        try await Task.sleep(for: .seconds(1.5))
        let out = try await source.stopRecording()
        source.stop()
        let seconds = try await AVURLAsset(url: out).load(.duration).seconds
        XCTAssertGreaterThan(seconds, 1.0)
        let empty = await ScanModel.hasVideo(URL(fileURLWithPath: "/nonexistent.mov"))
        XCTAssertFalse(empty)
        try? FileManager.default.removeItem(at: out)
    }

    func testLiDARStubSaysNotReady() async {
        do {
            try await LiDARScanSource().start()
            XCTFail("stub should throw")
        } catch {
            XCTAssertEqual(CameraState.from(error: error), .inUse)
        }
    }
}

@MainActor
final class ScanModelTests: XCTestCase {
    func testFullScanWithPracticeClip() async throws {
        let api = PreviewBackendAPI()
        let model = ScanModel(api: api, source: PreviewScanSource(fps: 30))
        model.appear()
        try await waitFor { model.camera == .ready && model.guidance != nil }
        XCTAssertTrue(model.practiceMode)
        XCTAssertNil(model.message, "good light and focus, nothing to fix")

        await model.startScan()
        XCTAssertEqual(model.phase, .recording)
        let resets = await api.resets
        XCTAssertEqual(resets, 1)

        // 30 frames a second come in. About one a second may go to the service.
        try await Task.sleep(for: .seconds(2.6))
        let sent = await api.frames
        XCTAssertTrue((2...4).contains(sent), "sent \(sent)")
        XCTAssertEqual(model.chips.count, 4)

        let url = await model.finishScan()
        XCTAssertNotNil(url)
        XCTAssertEqual(model.phase, .ready)
        XCTAssertFalse(model.emptyRecording)

        await api.setFailNext(true)
        try await waitFor { model.gate.checksStopped }
        XCTAssertEqual(model.message?.text, GuidanceText.lost)
        model.disappear()
        if let url { try? FileManager.default.removeItem(at: url) }
    }

    private func waitFor(_ condition: @escaping () -> Bool, timeout: Double = 6) async throws {
        let end = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > end { XCTFail("timed out"); return }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

@MainActor
final class SnapshotTests: XCTestCase {
    /// Writes PNGs for a human to look at. Set CADSCAN_SNAPSHOT_DIR to turn it on.
    func testRenderOverlay() throws {
        guard let dir = ProcessInfo.processInfo.environment["CADSCAN_SNAPSHOT_DIR"] else { throw XCTSkip("no snapshot dir") }
        func save<V: View>(_ view: V, _ name: String) throws {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.cgImage)
            let url = URL(fileURLWithPath: dir).appendingPathComponent(name) as CFURL
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(dest, image, nil)
            XCTAssertTrue(CGImageDestinationFinalize(dest))
        }
        try save(OverlayGallery(), "overlay.png")
        for state in [CameraState.notDetermined, .denied, .inUse] {
            try save(ZStack { Color.black; CameraStateCard(card: state.card!, perform: { _ in }) }.frame(width: 900, height: 506),
                     "card-\(state).png")
        }
    }
}
