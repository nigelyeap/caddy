@preconcurrency import AVFoundation
import AppKit
import CADShared
import SwiftUI

// MARK: - Model

@MainActor
final class ScanModel: ObservableObject {
    enum Phase { case ready, recording, finishing }

    @Published var camera: CameraState = .checking
    @Published var phase: Phase = .ready
    @Published var guidance: GuidanceResult?
    @Published var gate = FrameGate()
    @Published var practiceMode = false
    @Published var recordStart: Date?
    @Published var emptyRecording = false
    @Published var cameras: [ScanCamera] = []
    @Published var selectedCamera: String?

    let api: BackendAPI
    let source: ScanSource
    private let usesSystemCamera: Bool
    private var frameTask: Task<Void, Never>?
    private var generation = 0
    private var lastAnnounced: String?
    private var lastAnnounceTime = Date.distantPast

    init(api: BackendAPI, source: ScanSource) {
        self.api = api
        self.source = source
        usesSystemCamera = source is CameraScanSource
    }

    var recording: Bool { phase != .ready }
    var chips: [ChipInfo] { GuidanceText.chips(guidance, recording: recording, stopped: gate.checksStopped) }
    var message: OverlayMessage? {
        if phase == .ready, emptyRecording { return OverlayMessage(text: GuidanceText.empty, tone: .warning) }
        return GuidanceText.message(guidance, recording: recording, gate: gate)
    }

    func appear() {
        source.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        Task {
            if let state = try? await api.status() { practiceMode = state.engine == "stub" }
        }
        checkCamera()
    }

    func disappear() {
        frameTask?.cancel()
        frameTask = nil
        if recording {
            let source = source
            Task { _ = try? await source.stopRecording() }
        }
        phase = .ready
        recordStart = nil
        source.stop()
    }

    func checkCamera() {
        let auth = usesSystemCamera ? AVCaptureDevice.authorizationStatus(for: .video) : .authorized
        let hasCamera = usesSystemCamera ? CameraScanSource.hasCamera : true
        camera = CameraState.from(auth: auth, hasCamera: hasCamera)
        if camera == .checking { Task { await startCamera() } }
    }

    func allowCamera() async {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        checkCamera()
    }

    private func startCamera() async {
        do {
            try await source.start()
            camera = .ready
            cameras = source.cameras
            selectedCamera = source.selectedCameraID
            startFrameLoop()
        } catch {
            camera = CameraState.from(error: error)
        }
    }

    func selectCamera(_ id: String) {
        guard id != selectedCamera, !recording else { return }
        Task {
            do {
                try await source.selectCamera(id: id)
                selectedCamera = source.selectedCameraID
            } catch {
                camera = CameraState.from(error: error)
            }
        }
    }

    private func handle(_ event: ScanSourceEvent) {
        switch event {
        case .camerasChanged:
            cameras = source.cameras
            selectedCamera = source.selectedCameraID
        case .stopped(let error):
            if recording {
                let source = source
                Task { _ = try? await source.stopRecording() }
            }
            phase = .ready
            recordStart = nil
            frameTask?.cancel()
            source.stop()
            camera = CameraState.from(error: error)
        }
    }

    // MARK: Guidance

    private func startFrameLoop() {
        frameTask?.cancel()
        let stream = source.frames()
        frameTask = Task { [weak self] in
            for await frame in stream {
                self?.consider(frame)
            }
        }
    }

    private func consider(_ frame: ScanFrame) {
        let now = ProcessInfo.processInfo.systemUptime
        guard gate.shouldSend(now: now) else { return }
        gate.didSend(now: now)
        let gen = generation
        let api = api
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<GuidanceResult, Error>
            if let jpeg = FrameEncoder.jpeg(frame.pixelBuffer) {
                do { result = .success(try await api.sendFrame(jpeg: jpeg)) } catch { result = .failure(error) }
            } else {
                result = .failure(APIFailure(message: "Could not make a picture from the camera frame."))
            }
            await self?.receive(result, generation: gen)
        }
    }

    private func receive(_ result: Result<GuidanceResult, Error>, generation gen: Int) {
        switch result {
        case .success(let g):
            gate.didAnswer()
            // A frame sent before Start may answer after the reset. Its coverage is stale.
            if gen == generation { apply(g) }
        case .failure(let error):
            gate.didFail(connectionLost: Self.isConnectionLost(error))
        }
        announceIfNeeded()
    }

    nonisolated static func isConnectionLost(_ error: Error) -> Bool {
        if let failure = error as? APIFailure { return failure.isConnectionLost }
        return error is URLError
    }

    private func apply(_ g: GuidanceResult) {
        if phase == .recording, let old = guidance {
            let doneBefore = old.coverage.sectors.filter { $0 >= 0.999 }.count
            let doneNow = g.coverage.sectors.filter { $0 >= 0.999 }.count
            if old.coverage.pct < 99.5, g.coverage.pct >= 99.5 {
                Self.play("Glass")
            } else if doneNow > doneBefore {
                Self.play("Tink")
            }
        }
        guidance = g
    }

    /// The shell's Sound toggle writes this key. Sound is on by default.
    static let soundKey = "soundEnabled"

    private static func play(_ name: String) {
        guard UserDefaults.standard.object(forKey: soundKey) as? Bool ?? true else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// VoiceOver hears a new message at most once every 3 seconds.
    private func announceIfNeeded() {
        guard let text = message?.text, text != lastAnnounced, Date().timeIntervalSince(lastAnnounceTime) >= 3 else { return }
        lastAnnounced = text
        lastAnnounceTime = Date()
        AccessibilityNotification.Announcement(text).post()
    }

    // MARK: Recording

    func startScan() async {
        guard camera == .ready, phase == .ready else { return }
        emptyRecording = false
        generation += 1
        guidance = nil
        do {
            try await api.resetGuidance()
        } catch {
            gate.didFail(connectionLost: Self.isConnectionLost(error))
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString).mov")
        do {
            try source.startRecording(to: url)
            recordStart = Date()
            phase = .recording
        } catch {
            emptyRecording = true
        }
    }

    /// Returns the movie, or nil when it was empty.
    func finishScan() async -> URL? {
        guard phase == .recording else { return nil }
        phase = .finishing
        defer {
            phase = .ready
            recordStart = nil
        }
        guard let url = try? await source.stopRecording(), await Self.hasVideo(url) else {
            emptyRecording = true
            return nil
        }
        return url
    }

    static func hasVideo(_ url: URL) async -> Bool {
        guard let duration = try? await AVURLAsset(url: url).load(.duration) else { return false }
        return duration.seconds >= 0.5
    }
}

// MARK: - View

/// The scan screen: live camera, Start and Finish, a REC timer and the guidance overlay.
public struct ScanView: View {
    @StateObject private var model: ScanModel
    private let onFinished: (URL) -> Void
    private let onSkip: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Uses the Mac's cameras, including an iPhone through Continuity Camera.
    public init(api: BackendAPI, onFinished: @escaping (URL) -> Void, onSkip: @escaping () -> Void) {
        self.init(api: api, optionalSource: nil, onFinished: onFinished, onSkip: onSkip)
    }

    /// Uses any source, for example `PreviewScanSource` in previews or a probe later.
    public init(api: BackendAPI, source: ScanSource, onFinished: @escaping (URL) -> Void, onSkip: @escaping () -> Void) {
        self.init(api: api, optionalSource: source, onFinished: onFinished, onSkip: onSkip)
    }

    private init(api: BackendAPI, optionalSource: ScanSource?, onFinished: @escaping (URL) -> Void, onSkip: @escaping () -> Void) {
        // The autoclosure runs once, so a camera session is only made for the first init.
        _model = StateObject(wrappedValue: ScanModel(api: api, source: optionalSource ?? CameraScanSource()))
        self.onFinished = onFinished
        self.onSkip = onSkip
    }

    public var body: some View {
        VStack(spacing: Theme.gap) {
            cameraArea
            controlBar
            if model.practiceMode {
                Label(GuidanceText.practice, systemImage: "info.circle")
                    .themeFont(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Theme.screenMargin)
        .onAppear { model.appear() }
        .onDisappear { model.disappear() }
        .animation(Theme.motion(reduceMotion), value: model.phase)
        .animation(Theme.motion(reduceMotion), value: model.message)
    }

    // MARK: Camera area

    private var cameraArea: some View {
        ZStack {
            Color.black
            if model.camera == .ready || model.camera == .checking {
                CameraPreview(layer: model.source.previewLayer)
                    .accessibilityLabel("Camera picture")
            }
            if model.camera == .ready {
                overlay
            } else if model.camera == .checking {
                VStack(spacing: Theme.Space.s) {
                    ProgressView().controlSize(.large).tint(Theme.Overlay.text)
                    Text("Waking up the camera…").themeFont(.secondary).foregroundStyle(Theme.Overlay.text)
                }
            } else if let card = model.camera.card {
                CameraStateCard(card: card, perform: perform)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var overlay: some View {
        ZStack {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                ForEach(GuidanceText.problems(model.chips)) { StatusChip($0.word, level: $0.level) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if model.recording {
                let c = model.guidance?.coverage
                CoverageRing(sectors: model.gate.checksStopped ? [] : (c?.sectors ?? []),
                             percent: c?.pct ?? 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .opacity(model.gate.checksStopped ? 0.5 : 1)
                    .transition(.opacity)
            }

            VStack(spacing: Theme.Space.s) {
                Spacer(minLength: 0)
                if let message = model.message {
                    WarningBar(message)
                        .frame(maxWidth: 600)
                        .id(message.text)
                        .transition(.opacity)
                }
                if !model.recording {
                    CoachCard().frame(maxWidth: 600).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity)

            if let start = model.recordStart {
                RecBadge(start: start)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .padding(Theme.Space.m)
    }

    // MARK: Controls

    private var controlBar: some View {
        HStack(spacing: Theme.Space.s) {
            Button {
                Task {
                    if model.recording {
                        if let url = await model.finishScan() { onFinished(url) }
                    } else {
                        await model.startScan()
                    }
                }
            } label: {
                Label(model.recording ? "Finish scan" : "Start scan",
                      systemImage: model.recording ? "stop.circle.fill" : "record.circle")
            }
            .buttonStyle(BigButtonStyle(model.recording ? .destructive : .primary))
            .keyboardShortcut(.space, modifiers: [])
            .disabled(model.camera != .ready || model.phase == .finishing)

            if !model.recording {
                Button("Use a sample or open a file", action: onSkip)
                    .buttonStyle(BigButtonStyle(.secondary))
                    .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            Spacer(minLength: 0)

            if model.cameras.count > 1 {
                Picker(selection: Binding(get: { model.selectedCamera ?? "" }, set: { model.selectCamera($0) })) {
                    ForEach(model.cameras) { Text($0.name).tag($0.id) }
                } label: {
                    Label("Camera", systemImage: "camera")
                }
                .pickerStyle(.menu)
                .themeFont(.secondary)
                .fixedSize()
                .disabled(model.recording)
                .help("Choose a camera. A nearby iPhone appears here through Continuity Camera.")
            }
        }
    }

    private func perform(_ action: CameraState.Action) {
        switch action {
        case .allowCamera: Task { await model.allowCamera() }
        case .openSettings: openURL(CameraState.settingsURL)
        case .tryAgain: model.checkCamera()
        case .useSample: onSkip()
        }
    }
}

// MARK: - Pieces

struct CameraStateCard: View {
    let card: CameraState.Card
    let perform: (CameraState.Action) -> Void

    private func title(_ action: CameraState.Action) -> String {
        switch action {
        case .allowCamera: return "Allow camera"
        case .openSettings: return "Open System Settings"
        case .tryAgain: return "Try again"
        case .useSample: return "Use the sample model"
        }
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: card.symbol)
                .themeFont(.title)
                .foregroundStyle(Theme.Overlay.text.opacity(0.85))
                .frame(width: 56, height: 56)
                .background(Circle().fill(Theme.Overlay.text.opacity(0.12)))
                .accessibilityHidden(true)
            Text(card.title)
                .themeFont(.heading)
                .multilineTextAlignment(.center)
            Text(card.text)
                .themeFont(.body)
                .foregroundStyle(Theme.Overlay.text.opacity(0.85))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Theme.Space.s) {
                ForEach(Array(card.actions.enumerated()), id: \.offset) { i, action in
                    Button(title(action)) { perform(action) }
                        .buttonStyle(BigButtonStyle(i == 0 ? .primary : .secondary, compact: true))
                }
            }
            .padding(.top, Theme.Space.xs)
        }
        .foregroundStyle(Theme.Overlay.text)
        .padding(Theme.Space.xl)
        .frame(maxWidth: 560)
    }
}

/// Hosts the source's preview layer.
struct CameraPreview: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> HostView {
        let view = HostView()
        view.hosted = layer
        return view
    }

    func updateNSView(_ view: HostView, context: Context) { view.hosted = layer }

    final class HostView: NSView {
        var hosted: CALayer? {
            didSet {
                guard oldValue !== hosted else { return }
                oldValue?.removeFromSuperlayer()
                wantsLayer = true
                if let hosted { layer?.addSublayer(hosted) }
                needsLayout = true
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}
