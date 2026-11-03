@preconcurrency import AVFoundation
import Vision

/// The Mac camera plus Vision hand pose. Runs its own capture session, apart from the scan camera.
final class HandTracker: NSObject, @unchecked Sendable {
    enum Failure: Error { case notAllowed, noCamera, inUse }

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "cadgesture.session")
    private let frameQueue = DispatchQueue(label: "cadgesture.frames")
    private let request: VNDetectHumanHandPoseRequest = {
        let r = VNDetectHumanHandPoseRequest()
        r.maximumHandCount = 2
        return r
    }()
    let previewLayer: AVCaptureVideoPreviewLayer

    /// Called on the frame queue for every frame with the hands seen, up to two. Set it before `start()`.
    var onPoses: (@Sendable ([HandPose], TimeInterval) -> Void)?

    override init() {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resize
        super.init()
    }

    deinit { session.stopRunning() }

    func start() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw Failure.notAllowed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure()
                    if !self.session.isRunning { self.session.startRunning() }
                    if self.session.isRunning { cont.resume() } else { cont.resume(throwing: Failure.inUse) }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { self.session.stopRunning() }
    }

    private func configure() throws {
        guard session.inputs.isEmpty else { return }
        let found = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified
        ).devices
        // The Mac's own camera faces the kid. An iPhone or webcam is more likely pointed at the object.
        guard let device = found.first(where: { $0.deviceType == .builtInWideAngleCamera })
            ?? AVCaptureDevice.systemPreferredCamera ?? found.first
        else { throw Failure.noCamera }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        // Small frames are plenty for a hand and keep Vision fast.
        if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
        } else if session.canSetSessionPreset(.medium) {
            session.sessionPreset = .medium
        }
        guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else { throw Failure.inUse }
        session.addInput(input)
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: frameQueue)
        if session.canAddOutput(output) { session.addOutput(output) }
    }

    /// Vision points are bottom-left origin and not mirrored. HandPose wants top-left and mirrored.
    static func pose(from observation: VNHumanHandPoseObservation, aspect: CGFloat) -> HandPose? {
        guard let found = try? observation.recognizedPoints(.all) else { return nil }
        var points: [HandJoint: CGPoint] = [:]
        for joint in HandJoint.allCases {
            if let p = found[joint.visionName], p.confidence > 0.3 {
                points[joint] = CGPoint(x: 1 - p.location.x, y: 1 - p.location.y)
            }
        }
        let pose = HandPose(points: points, aspect: aspect)
        return pose.cursor != nil && pose.pinchRatio != nil ? pose : nil
    }
}

extension HandTracker: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let aspect = CGFloat(CVPixelBufferGetWidth(buffer)) / CGFloat(max(CVPixelBufferGetHeight(buffer), 1))
        var poses: [HandPose] = []
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
        if (try? handler.perform([request])) != nil {
            poses = (request.results ?? []).compactMap { Self.pose(from: $0, aspect: aspect) }
        }
        onPoses?(poses, time)
    }
}

private extension HandJoint {
    var visionName: VNHumanHandPoseObservation.JointName {
        switch self {
        case .wrist: .wrist
        case .thumbCMC: .thumbCMC
        case .thumbMP: .thumbMP
        case .thumbIP: .thumbIP
        case .thumbTip: .thumbTip
        case .indexMCP: .indexMCP
        case .indexPIP: .indexPIP
        case .indexDIP: .indexDIP
        case .indexTip: .indexTip
        case .middleMCP: .middleMCP
        case .middlePIP: .middlePIP
        case .middleDIP: .middleDIP
        case .middleTip: .middleTip
        case .ringMCP: .ringMCP
        case .ringPIP: .ringPIP
        case .ringDIP: .ringDIP
        case .ringTip: .ringTip
        case .littleMCP: .littleMCP
        case .littlePIP: .littlePIP
        case .littleDIP: .littleDIP
        case .littleTip: .littleTip
        }
    }
}
