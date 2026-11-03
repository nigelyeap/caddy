@preconcurrency import AVFoundation
import CoreVideo
import os
import QuartzCore
import simd

/// One picture from a scan source.
public struct ScanFrame: @unchecked Sendable {
    public let pixelBuffer: CVPixelBuffer
    /// Capture time in seconds, on the source's own clock.
    public let time: TimeInterval
    /// Depth map from LiDAR, if the source has one. Metres (Float32) or millimetres (UInt16).
    public let depth: CVPixelBuffer?
    /// Camera to world, ARKit style: y up, camera looks along -z.
    public let pose: simd_float4x4?

    public init(pixelBuffer: CVPixelBuffer, time: TimeInterval, depth: CVPixelBuffer? = nil, pose: simd_float4x4? = nil) {
        self.pixelBuffer = pixelBuffer
        self.time = time
        self.depth = depth
        self.pose = pose
    }
}

public struct ScanCamera: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public enum ScanSourceError: Error, Equatable, Sendable {
    case notAllowed
    case noCamera
    case inUse
    case disconnected
    case notRecording
    case notReady(String)
    case recordingFailed(String)
}

public enum ScanSourceEvent: Sendable {
    /// A camera was plugged in or removed. Read `cameras` again.
    case camerasChanged
    /// The picture stopped on its own, for example a cable came out.
    case stopped(ScanSourceError)
}

/// Anything that can feed the scan screen: a Mac or iPhone camera today, a LiDAR probe later.
public protocol ScanSource: AnyObject, Sendable {
    /// Shows the live picture. The scan view hosts this layer.
    var previewLayer: CALayer { get }
    /// A fresh stream of frames. Only the newest stream gets frames.
    /// It holds one waiting frame, so a slow reader skips old frames.
    func frames() -> AsyncStream<ScanFrame>
    func start() async throws
    func stop()
    /// Starts writing a movie to `url`. Replaces any file already there.
    func startRecording(to url: URL) throws
    /// Finishes the movie and returns its URL.
    func stopRecording() async throws -> URL
    var cameras: [ScanCamera] { get }
    var selectedCameraID: String? { get }
    func selectCamera(id: String) async throws
    /// Called on any thread.
    var onEvent: (@Sendable (ScanSourceEvent) -> Void)? { get set }
}

public extension ScanSource {
    var cameras: [ScanCamera] { [] }
    var selectedCameraID: String? { nil }
    func selectCamera(id: String) async throws {}
}

/// Hands frames to the newest AsyncStream. Thread safe.
final class FrameFanout: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock<AsyncStream<ScanFrame>.Continuation?>(initialState: nil)

    func makeStream() -> AsyncStream<ScanFrame> {
        let (stream, cont) = AsyncStream.makeStream(of: ScanFrame.self, bufferingPolicy: .bufferingNewest(1))
        let old = lock.withLock { state -> AsyncStream<ScanFrame>.Continuation? in
            defer { state = cont }
            return state
        }
        old?.finish()
        return stream
    }

    func yield(_ frame: ScanFrame) {
        lock.withLock { $0 }?.yield(frame)
    }

    func finish() {
        lock.withLock { state -> AsyncStream<ScanFrame>.Continuation? in
            defer { state = nil }
            return state
        }?.finish()
    }
}

/// Writes pixel buffers to an H.264 .mov with AVAssetWriter.
/// Used by sources that do not have a capture session, like the preview and the LiDAR probe.
final class FrameRecorder: @unchecked Sendable {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let lock = NSLock()
    private var firstTime: TimeInterval?
    private var lastTime: TimeInterval = -1
    let url: URL

    init(url: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: url)
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        guard writer.canAdd(input) else { throw ScanSourceError.recordingFailed("Writer refused the video input.") }
        writer.add(input)
        guard writer.startWriting() else {
            throw ScanSourceError.recordingFailed(writer.error?.localizedDescription ?? "Writer did not start.")
        }
    }

    func append(_ buffer: CVPixelBuffer, time: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        if firstTime == nil {
            firstTime = time
            writer.startSession(atSourceTime: .zero)
        }
        let t = time - (firstTime ?? time)
        guard t > lastTime, input.isReadyForMoreMediaData else { return }
        if adaptor.append(buffer, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600)) {
            lastTime = t
        }
    }

    func finish() async throws -> URL {
        let started: Bool = lock.withLock {
            input.markAsFinished()
            return firstTime != nil
        }
        guard started else {
            writer.cancelWriting()
            throw ScanSourceError.recordingFailed("No frames were recorded.")
        }
        await writer.finishWriting()
        if writer.status != .completed {
            throw ScanSourceError.recordingFailed(writer.error?.localizedDescription ?? "Writer did not finish.")
        }
        return url
    }
}
