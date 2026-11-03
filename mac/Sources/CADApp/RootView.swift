import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CADShared

struct RootView: View {
    @ObservedObject var helper: Helper
    @ObservedObject var model: AppModel
    @ObservedObject var tutorial: Tutorial
    @FocusState private var editFocused: Bool
    @AppStorage("seenIntro") private var seenIntro = false
    @AppStorage("textSize") private var textSize = TextSize.large
    @AppStorage("teacherMode") private var teacherMode = false
    @AppStorage("soundEnabled") private var soundOn = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var everConnected = false
    @State private var dropTargeted = false
    @State private var showTeacherInfo = false
    @State private var showSkipChoice = false

    private var phase: HelperPhase { helperPhase(helper) }

    var body: some View {
        VStack(spacing: 0) {
            if let b = model.banner {
                BannerView(kind: b).transition(.move(edge: .top).combined(with: .opacity))
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.background)
        // The golden-brown header is drawn over the top safe area, under the transparent window toolbar,
        // so it shows the exact colour whatever each screen paints behind the toolbar.
        .overlay(alignment: .top) {
            GeometryReader { g in
                Theme.header
                    .overlay(alignment: .bottom) { Theme.line.frame(height: 1) }
                    .frame(height: g.safeAreaInsets.top)
                    .offset(y: -g.safeAreaInsets.top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        // Native controls (toggles, pickers, focus rings in fields) share the app accent.
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay {
            // Never over the launch screen. The tour waits until the helper has answered once.
            if everConnected {
                TutorialOverlay(tutorial: tutorial, model: model, viewer: model.viewer, frames: tutorial.frames,
                                seenIntro: seenIntro, textSize: textSize)
            }
        }
        .environment(\.tutorialFrames, tutorial.frames)
        .environment(\.tutorialFocus, tutorial.step?.target)
        .animation(Theme.motion(reduceMotion), value: model.banner)
        .environment(\.textScale, textSize.scale)
        .toolbar { toolbar }
        .toolbarBackground(.hidden, for: .windowToolbar)
        // In full screen the toolbar moves to its own window, which the overlay header cannot reach.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { tintFullScreenToolbar() }
        }
        .task { try? await Task.sleep(for: .seconds(1)); tintFullScreenToolbar() }
        .navigationTitle("")
        .overlay { if dropTargeted { dropHint } }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, everConnected else { return false }
            model.open(url)
            return true
        } isTargeted: { dropTargeted = $0 && everConnected }
        .confirmationDialog("Start a new scan? The current model will be cleared.", isPresented: $model.confirmNewScan) {
            Button("Start new scan", role: .destructive) { seenIntro = true; model.newScan() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Open this file? The current model will be cleared.",
                            isPresented: Binding(get: { model.pendingFile != nil }, set: { if !$0 { model.pendingFile = nil } })) {
            Button("Open it", role: .destructive) { model.confirmPendingFile() }
            Button("Cancel", role: .cancel) { model.pendingFile = nil }
        }
        .confirmationDialog("Skip the camera scan?", isPresented: $showSkipChoice) {
            Button("Use the sample model") { model.useSample() }
            Button("Open a scan file…") { openPanel() }
            Button("Scan from turntable…") { openTurntablePanel() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The sample model is ready to edit. A scan file can be an STL, PLY or OBJ file, a video, or a turntable scan.")
        }
        .onChange(of: phase) { _, p in phaseChanged(p) }
        .onChange(of: model.step) { _, s in if s == .edit && !tutorial.isOn { editFocused = true } }
        // Each tour step frees Return for the bubble's Next button, so it never sends an empty change.
        .onChange(of: tutorial.index) { _, i in if i != nil { editFocused = false } }
        .onReceive(NotificationCenter.default.publisher(for: .focusChangeField)) { _ in editFocused = true }
        .onReceive(NotificationCenter.default.publisher(for: .saveModel)) { _ in save() }
        .onReceive(NotificationCenter.default.publisher(for: .openScanFile)) { _ in openPanel() }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        Group {
            if !everConnected {
                LaunchView(failure: failureText, diagnostics: helper.diagnostics) { Task { await helper.start() } }
            } else {
                switch model.step {
                case .scan:
                    if !seenIntro {
                        FirstRunView(start: { seenIntro = true }, sample: { seenIntro = true; model.useSample() },
                                     tutorialOn: tutorial.isOn)
                    } else {
                        scanStep
                    }
                case .cleanUp:
                    if let p = model.processing {
                        ProcessingView(processing: p, back: model.backToScan, sample: model.useSample)
                    }
                case .edit:
                    EditScreen(model: model, focus: $editFocused, save: save)
                }
            }
        }
        .transition(.opacity)
        .animation(Theme.motion(reduceMotion), value: model.step)
        .animation(Theme.motion(reduceMotion), value: seenIntro)
        .animation(Theme.motion(reduceMotion), value: everConnected)
    }

    private var scanStep: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                // During the tour the scan area plays a practice clip and its buttons rest.
                let practice = tutorial.step?.screen == .scan
                ScanStep(api: model.api, onFinished: model.scanFinished, onSkip: { showSkipChoice = true },
                         practice: practice)
                    .disabled(!model.connected || practice)
                if let n = model.note {
                    NoteView(note: n).frame(maxWidth: 640).padding(.horizontal, Theme.screenMargin).padding(.bottom, Theme.Space.s)
                }
            }
            .frame(maxWidth: .infinity)
            Divider()
            ScanSidePanel(builds: model.builds, openBuild: { item in Task { await model.openBuild(item) } },
                          openFile: openPanel, sample: model.useSample,
                          openTurntable: openTurntablePanel, turntableSample: openTurntableSample)
                .frame(width: 280 * textSize.scale)
                .disabled(!model.connected)
        }
    }

    private var failureText: String? {
        if case .failed(let why) = phase { return why }
        return nil
    }

    private var dropHint: some View {
        ZStack {
            Theme.accent.opacity(0.06)
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 7]))
                .padding(Theme.Space.s)
            Label("Drop to open this file", systemImage: "tray.and.arrow.down.fill")
                .themeFont(.heading).foregroundStyle(Theme.ink)
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, Theme.Space.l).padding(.vertical, Theme.Space.s)
                .card(padding: 0, tint: Theme.tintAccent)
        }
        .allowsHitTesting(false)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        // Next to the window title, so the trailing buttons keep their own space.
        ToolbarItem(placement: .navigation) {
            HStack(spacing: Theme.Space.s) {
                HStack(spacing: 6) {
                    CaddiyView(pose: .logo, size: 24, wave: false)
                    Text("CADDIY").font(Theme.rounded(15, .heavy)).foregroundStyle(Theme.gold)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("CADDIY")
                if everConnected {
                    Theme.line.frame(width: 1, height: 16)
                    StepIndicator(current: model.step)
                    if model.step == .edit {
                        Button { Task { await model.goHome() } } label: { Label("Home", systemImage: "house.fill") }
                            .buttonStyle(ChipButtonStyle(tint: Theme.tintSun))
                            .help("Back to the start. Your build is saved in My builds.")
                            .disabled(model.isEditing)
                    }
                }
            }
            .padding(.leading, Theme.Space.xs)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if teacherMode {
                Button("Diagnostics", systemImage: "info.circle") { showTeacherInfo.toggle() }
                    .popover(isPresented: $showTeacherInfo) { teacherInfo }
            }
            Button { soundOn.toggle() } label: {
                Label(soundOn ? "Sound on" : "Sound off", systemImage: soundOn ? "speaker.wave.2" : "speaker.slash")
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(soundOn ? "Sound is on. Click to turn it off." : "Sound is off. Click to turn it on.")
            Menu {
                Picker("Text size", selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            } label: {
                Label("Text size", systemImage: "textformat.size")
            }
            .help("Text size")
        }
    }

    private var teacherInfo: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Diagnostics").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow { Text("Helper").foregroundStyle(.secondary); Text(phaseText) }
                GridRow { Text("Guidance").foregroundStyle(.secondary); Text(model.state?.engine == "stub" ? "Practice (stub)" : "Real") }
                GridRow { Text("Claude key").foregroundStyle(.secondary); Text(helper.hasAPIKey ? "Found" : "Not set, examples only") }
                GridRow { Text("Versions").foregroundStyle(.secondary); Text("\(model.state?.versions.count ?? 0)") }
            }
            .font(.callout)
            Text(helper.diagnostics.isEmpty ? "No helper output yet." : helper.diagnostics)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .frame(width: 520, height: 220, alignment: .topLeading)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(16)
    }

    private var phaseText: String {
        switch phase {
        case .starting: "Starting"
        case .running: "Running"
        case .lostContact: "Lost contact"
        case .failed(let s): "Failed: \(s)"
        }
    }

    // MARK: Actions

    /// Paints the separate full-screen toolbar window in the header colour by turning off its blur.
    private func tintFullScreenToolbar() {
        func effects(_ v: NSView) -> [NSVisualEffectView] {
            ((v as? NSVisualEffectView).map { [$0] } ?? []) + v.subviews.flatMap(effects)
        }
        let tag = NSUserInterfaceItemIdentifier("caddiyHeader")
        for w in NSApp.windows where String(describing: type(of: w)).contains("FullScreen") {
            guard let root = w.contentView?.superview ?? w.contentView else { continue }
            for e in effects(root) where !e.subviews.contains(where: { $0.identifier == tag }) {
                // A flat colour layer at the back of the blur, under the toolbar items.
                let fill = NSView(frame: e.bounds)
                fill.identifier = tag
                fill.autoresizingMask = [.width, .height]
                fill.wantsLayer = true
                fill.layer?.backgroundColor = NSColor(Theme.header).cgColor
                e.addSubview(fill, positioned: .below, relativeTo: nil)
            }
        }
    }

    private func phaseChanged(_ p: HelperPhase) {
        switch p {
        case .running:
            let first = !everConnected
            everConnected = true
            Task { await model.helperIsUp(firstTime: first) }
        case .lostContact:
            model.helperLost()
        case .starting, .failed:
            if everConnected { model.helperLost() }
        }
    }

    private func save() {
        guard model.canSave else { return }
        model.save()
    }

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = (ScanFiles.meshes + ScanFiles.videos).compactMap { UTType(filenameExtension: $0) }
            + turntableTypes
        panel.message = "Choose an STL, PLY or OBJ file, a video of the object, or a turntable scan file."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.open(url)
        }
    }

    /// txt and csv from the turntable SD card. Falls back to the system types if the lookup fails.
    private var turntableTypes: [UTType] {
        zip(ScanFiles.turntable, [UTType.plainText, .commaSeparatedText]).map { UTType(filenameExtension: $0) ?? $1 }
    }

    private func openTurntablePanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = turntableTypes
        panel.message = "Pick the scan file from the SD card. It is usually called scan_001.txt."
        panel.prompt = "Open scan"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.open(url)
        }
    }

    /// A bundled cylinder scan. model.open never deletes the file, so the bundle copy is safe.
    private func openTurntableSample() {
        guard let url = Bundle.module.url(forResource: "turntable_sample", withExtension: "txt") else { return }
        model.open(url)
    }
}

extension Notification.Name {
    static let focusChangeField = Notification.Name("CADDIY.focusChangeField")
    static let saveModel = Notification.Name("CADDIY.saveModel")
    static let openScanFile = Notification.Name("CADDIY.openScanFile")
}
