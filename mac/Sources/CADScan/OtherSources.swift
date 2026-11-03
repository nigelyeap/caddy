import CoreGraphics
import CoreVideo
import Foundation
import os
import QuartzCore

/// A fake camera for Xcode previews and tests. It needs no camera and no permission.
/// It plays a looping synthetic clip of a box turning on a table, or a still image.
/// Frames and times depend only on the frame number, so runs repeat exactly.
public final class PreviewScanSource: ScanSource, @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let fps: Double
    private let still: CGImage?
    private let layer = CALayer()
    private let fanout = FrameFanout()
    private let queue = DispatchQueue(label: "cadscan.preview")
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    private var index = 0
    private var recorder: FrameRecorder?
    private var eventHandler: (@Sendable (ScanSourceEvent) -> Void)?

    public init(width: Int = 640, height: Int = 360, fps: Double = 15, still: CGImage? = nil) {
        self.width = width
        self.height = height
        self.fps = fps
        self.still = still
        layer.contentsGravity = .resizeAspectFill
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
        // Show the first frame at once so a static preview is not black.
        if let first = Self.image(index: 0, width: width, height: height, fps: fps, still: still) {
            layer.contents = first
        }
    }

    public var previewLayer: CALayer { layer }
    public var onEvent: (@Sendable (ScanSourceEvent) -> Void)? {
        get { lock.withLock { eventHandler } }
        set { lock.withLock { eventHandler = newValue } }
    }
    public var cameras: [ScanCamera] { [ScanCamera(id: "preview", name: "Practice clip")] }
    public var selectedCameraID: String? { "preview" }

    public func frames() -> AsyncStream<ScanFrame> { fanout.makeStream() }

    public func start() async throws {
        lock.withLock {
            guard timer == nil else { return }
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 1 / fps)
            t.setEventHandler { [weak self] in self?.tick() }
            timer = t
            t.resume()
        }
    }

    public func stop() {
        lock.withLock {
            timer?.cancel()
            timer = nil
        }
        fanout.finish()
    }

    /// Makes frame number `i`. Public so tests can check it.
    public func frame(at i: Int) -> ScanFrame? {
        guard let image = Self.image(index: i, width: width, height: height, fps: fps, still: still),
              let buffer = Self.pixelBuffer(from: image) else { return nil }
        return ScanFrame(pixelBuffer: buffer, time: Double(i) / fps)
    }

    private func tick() {
        let i = lock.withLock { () -> Int in defer { index += 1 }; return index }
        guard let image = Self.image(index: i, width: width, height: height, fps: fps, still: still),
              let buffer = Self.pixelBuffer(from: image) else { return }
        let time = Double(i) / fps
        lock.withLock { recorder }?.append(buffer, time: time)
        fanout.yield(ScanFrame(pixelBuffer: buffer, time: time))
        DispatchQueue.main.async { [layer] in
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.contents = image
            CATransaction.commit()
        }
    }

    public func startRecording(to url: URL) throws {
        let r = try FrameRecorder(url: url, width: width, height: height)
        lock.withLock { recorder = r }
    }

    public func stopRecording() async throws -> URL {
        let r = lock.withLock { () -> FrameRecorder? in defer { recorder = nil }; return recorder }
        guard let r else { throw ScanSourceError.notRecording }
        return try await r.finish()
    }

    // MARK: Drawing

    /// One lap every 12 seconds. A box with coloured sides sits on a table.
    static func image(index: Int, width: Int, height: Int, fps: Double, still: CGImage?) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        if let still {
            ctx.draw(still, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage()
        }
        // Wall and table.
        ctx.setFillColor(CGColor(red: 0.30, green: 0.33, blue: 0.38, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h * 0.45, width: w, height: h * 0.55))
        ctx.setFillColor(CGColor(red: 0.62, green: 0.48, blue: 0.34, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h * 0.45))
        // Wood grain lines give the tracker something to hold on to.
        ctx.setStrokeColor(CGColor(red: 0.50, green: 0.37, blue: 0.25, alpha: 1))
        ctx.setLineWidth(2)
        for k in 0..<12 {
            let y = h * 0.45 * CGFloat(k) / 12
            ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y + 6))
        }
        ctx.strokePath()

        // The box: four sides, two visible at a time, widths from the turn angle.
        let angle = Double(index) / fps / 12 * 2 * .pi
        let colors: [CGColor] = [
            CGColor(red: 0.90, green: 0.30, blue: 0.25, alpha: 1), CGColor(red: 0.25, green: 0.60, blue: 0.90, alpha: 1),
            CGColor(red: 0.95, green: 0.80, blue: 0.20, alpha: 1), CGColor(red: 0.30, green: 0.75, blue: 0.40, alpha: 1),
        ]
        let size = h * 0.42, cx = w / 2, base = h * 0.28
        var x = cx - size * 0.7
        for side in 0..<4 {
            let face = cos(angle + Double(side) * .pi / 2)
            guard face > 0 else { continue }
            let faceWidth = size * 1.4 * CGFloat(face) / CGFloat(abs(cos(angle)) + abs(sin(angle)))
            let rect = CGRect(x: x, y: base, width: faceWidth, height: size)
            ctx.setFillColor(colors[side]); ctx.fill(rect)
            ctx.setFillColor(CGColor(gray: 1, alpha: 0.8))
            ctx.fill(CGRect(x: rect.minX + rect.width * 0.3, y: rect.minY + size * 0.35, width: rect.width * 0.4, height: size * 0.3))
            x += faceWidth
        }
        return ctx.makeImage()
    }

    static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                                    kCVPixelBufferCGImageCompatibilityKey as String: true,
                                    kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pb else { return nil }
        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pb
    }
}

// MARK: - LiDAR probe (stub)

/// STUB. Not built yet. Every method throws `notReady`.
///
/// Planned: a handheld probe, or an iPhone, that streams colour frames, a LiDAR depth map
/// and an ARKit-style camera pose to this Mac. Before this can be written we need:
/// - Transport: USB, Wi-Fi or Multipeer Connectivity, and who starts the connection.
/// - Colour frames: size, pixel format, frame rate, and the lens intrinsics.
/// - Depth: size, units (metres Float32 or millimetres UInt16), confidence map, and how it lines up with colour.
/// - Pose: 4x4 camera to world, y up, camera looking along -z (ARKit). Confirm the probe uses the same.
/// - Clock: one shared timestamp for colour, depth and pose, in seconds.
/// - Recording: record on the probe and copy the file, or record here with `FrameRecorder`.
/// - Guidance API: `/api/guidance/frame` takes a JPEG only. Depth and pose need a new endpoint
///   or a multipart frame. Agree the shape with the guidance owner first.
/// - Haptics on the probe: a light tap per green segment and a success pattern at 100 percent.
/// - Camera picker: list the probe in `cameras` so it can be chosen like any camera.
public final class LiDARScanSource: ScanSource, @unchecked Sendable {
    private let layer = CALayer()
    public init() {}
    public var previewLayer: CALayer { layer }
    public var onEvent: (@Sendable (ScanSourceEvent) -> Void)?
    public func frames() -> AsyncStream<ScanFrame> { AsyncStream { $0.finish() } }
    public func start() async throws { throw ScanSourceError.notReady("The LiDAR probe is not supported yet.") }
    public func stop() {}
    public func startRecording(to url: URL) throws { throw ScanSourceError.notReady("The LiDAR probe is not supported yet.") }
    public func stopRecording() async throws -> URL { throw ScanSourceError.notReady("The LiDAR probe is not supported yet.") }
}
