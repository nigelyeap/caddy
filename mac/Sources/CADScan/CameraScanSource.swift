@preconcurrency import AVFoundation
import os
import QuartzCore

/// A Mac camera, a USB webcam, or an iPhone through Continuity Camera.
/// Frames come from AVCaptureVideoDataOutput. The movie comes from AVCaptureMovieFileOutput.
public final class CameraScanSource: NSObject, ScanSource, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let movieOutput = AVCaptureMovieFileOutput()
    private let sessionQueue = DispatchQueue(label: "cadscan.camera.session")
    private let frameQueue = DispatchQueue(label: "cadscan.camera.frames")
    private let fanout = FrameFanout()
    private let preview: AVCaptureVideoPreviewLayer
    private let state = OSAllocatedUnfairLock(initialState: LockedState())
    private var observers: [NSObjectProtocol] = []

    /// UserDefaults key for the chosen camera. The app's Settings writes the same key.
    public static let cameraDefaultsKey = "cameraID"

    private static var chosenID: String? {
        get { UserDefaults.standard.string(forKey: cameraDefaultsKey).flatMap { $0.isEmpty ? nil : $0 } }
        set { UserDefaults.standard.set(newValue ?? "", forKey: cameraDefaultsKey) }
    }

    private struct LockedState {
        var activeID: String?
        var recordDone: CheckedContinuation<URL, Error>?
        var onEvent: (@Sendable (ScanSourceEvent) -> Void)?
    }

    public override init() {
        preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil) { [weak self] _ in
            self?.emit(.camerasChanged)
        })
        observers.append(center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] note in
            guard let self else { return }
            self.emit(.camerasChanged)
            let gone = (note.object as? AVCaptureDevice)?.uniqueID
            if gone != nil, gone == self.state.withLock({ $0.activeID }) {
                self.emit(.stopped(.disconnected))
            }
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
            let code = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            self?.emit(.stopped(code == .deviceInUseByAnotherApplication ? .inUse : .disconnected))
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        session.stopRunning()
    }

    public var onEvent: (@Sendable (ScanSourceEvent) -> Void)? {
        get { state.withLock { $0.onEvent } }
        set { state.withLock { $0.onEvent = newValue } }
    }

    private func emit(_ event: ScanSourceEvent) {
        state.withLock { $0.onEvent }?(event)
    }

    public var previewLayer: CALayer { preview }

    public func frames() -> AsyncStream<ScanFrame> { fanout.makeStream() }

    // MARK: Cameras

    private static func discover() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video, position: .unspecified
        ).devices
    }

    /// True when the Mac sees at least one camera.
    public static var hasCamera: Bool { !discover().isEmpty }

    public var cameras: [ScanCamera] {
        Self.discover().map { ScanCamera(id: $0.uniqueID, name: $0.localizedName) }
    }

    public var selectedCameraID: String? { state.withLock { $0.activeID } ?? Self.chosenID }

    public func selectCamera(id: String) async throws {
        Self.chosenID = id
        if session.isRunning { try await start() }
    }

    // MARK: Start and stop

    public func start() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw ScanSourceError.notAllowed }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try self.configure()
                    if !self.session.isRunning { self.session.startRunning() }
                    // startRunning fails quietly. The usual cause is another app holding the camera.
                    if self.session.isRunning { cont.resume() } else { cont.resume(throwing: ScanSourceError.inUse) }
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private func configure() throws {
        let devices = Self.discover()
        let chosen = Self.chosenID
        guard let device = devices.first(where: { $0.uniqueID == chosen }) ?? AVCaptureDevice.systemPreferredCamera ?? devices.first
        else { throw ScanSourceError.noCamera }

        let current = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }.first
        if current?.device.uniqueID == device.uniqueID, session.isRunning { return }
        if device.isInUseByAnotherApplication { throw ScanSourceError.inUse }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        if let current { session.removeInput(current) }
        let input: AVCaptureDeviceInput
        do { input = try AVCaptureDeviceInput(device: device) } catch { throw ScanSourceError.inUse }
        guard session.canAddInput(input) else { throw ScanSourceError.inUse }
        session.addInput(input)
        state.withLock { $0.activeID = device.uniqueID }

        if session.outputs.isEmpty {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            videoOutput.setSampleBufferDelegate(self, queue: frameQueue)
            if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
            if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        }
    }

    public func stop() {
        sessionQueue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
            self.session.stopRunning()
        }
        state.withLock { $0.activeID = nil }
        fanout.finish()
    }

    // MARK: Recording

    public func startRecording(to url: URL) throws {
        guard session.isRunning, session.outputs.contains(movieOutput) else { throw ScanSourceError.notReady("The camera is not running.") }
        try? FileManager.default.removeItem(at: url)
        sessionQueue.async {
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    public func stopRecording() async throws -> URL {
        try await withCheckedThrowingContinuation { cont in
            state.withLock { $0.recordDone = cont }
            sessionQueue.async {
                if self.movieOutput.isRecording {
                    self.movieOutput.stopRecording()
                } else {
                    self.state.withLock { s -> CheckedContinuation<URL, Error>? in
                        defer { s.recordDone = nil }
                        return s.recordDone
                    }?.resume(throwing: ScanSourceError.notRecording)
                }
            }
        }
    }
}

extension CameraScanSource: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        fanout.yield(ScanFrame(pixelBuffer: buffer, time: time))
    }
}

extension CameraScanSource: AVCaptureFileOutputRecordingDelegate {
    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        let cont = state.withLock { s -> CheckedContinuation<URL, Error>? in
            defer { s.recordDone = nil }
            return s.recordDone
        }
        // AVFoundation can report an error even when the file is fine.
        let finishedOK = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
        if finishedOK {
            cont?.resume(returning: url)
        } else {
            cont?.resume(throwing: ScanSourceError.recordingFailed(error?.localizedDescription ?? "Recording failed."))
        }
    }
}
