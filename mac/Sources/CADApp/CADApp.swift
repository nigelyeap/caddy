import SwiftUI
import AppKit
import CADShared

@main
struct CADDIYApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var helper: Helper
    @StateObject private var model: AppModel
    @StateObject private var tutorial = Tutorial()
    @AppStorage("seenIntro") private var seenIntro = false

    init() {
        // integer(forKey:) also reads a launch argument such as `-helperPort 8766`, which arrives as text.
        let saved = UserDefaults.standard.integer(forKey: "helperPort")
        let port = saved > 0 ? saved : 8000
        let h = makeHelper(root: Self.projectRoot, port: port)
        _helper = StateObject(wrappedValue: h)
        _model = StateObject(wrappedValue: AppModel(api: h.api))
        // Start the helper from here so it never waits on a view. The short wait lets the window show first:
        // the first launch reads the project in ~/Documents, and macOS blocks that read until the privacy prompt is answered.
        // ponytail: fixed 0.6 s wait, switch to a window-did-appear signal if it ever races.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            await h.start()
        }
        // Stop the Python helper when the app quits.
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { h.stop() }
        }
    }

    /// The repo root. The packaged app uses its own server copy and ignores the rest.
    /// Otherwise CAD_TRAINING_ROOT wins, then the path build_app.sh writes into Info.plist.
    /// No file checks here: the project sits in ~/Documents, and touching it before the window exists
    /// would block launch behind the macOS privacy prompt. BackendService reports a wrong path itself.
    static var projectRoot: URL? {
        if let server = Helper.bundledServer { return server }
        if let p = ProcessInfo.processInfo.environment["CAD_TRAINING_ROOT"], !p.isEmpty { return URL(fileURLWithPath: p) }
        if let p = Bundle.main.object(forInfoDictionaryKey: "CADDIYProjectRoot") as? String, !p.isEmpty { return URL(fileURLWithPath: p) }
        return nil
    }

    /// Harness: CADDIY_TUTORIAL=<step> gets the app to that step's screen once the helper answers.
    @MainActor private func prepareTutorialHarness() async {
        guard let screen = Tutorial.harnessScreen(), case .start(let i) = tutorial.harness else { return }
        defer { tutorial.harnessPrepared() }
        while !model.connected { try? await Task.sleep(for: .milliseconds(300)) }
        // helperIsUp may still move to Edit for a saved model. Let it land first.
        try? await Task.sleep(for: .seconds(1.5))
        let demo = ProcessInfo.processInfo.environment["CADDIY_DEMO"] != nil
        switch screen {
        case .firstRun, .scan:
            seenIntro = screen == .scan
            if model.step != .scan { model.newScan() }
        case .process:
            seenIntro = true
            model.useSample()
        case .edit:
            seenIntro = true
            if !demo && !(model.step == .edit && model.hasModel) { model.useSample() }
            // Steps after Taller need a change to undo.
            let taller = TutorialScript.steps.firstIndex { $0.id == "taller" }!
            guard i > taller, let idea = Ideas.all.first(where: { $0.short == "Taller" }) else { return }
            while model.step != .edit || !model.hasModel { try? await Task.sleep(for: .milliseconds(300)) }
            if (model.state?.versions.count ?? 0) < 2 { model.send(idea.text) }
        }
    }

    var body: some Scene {
        Window("CADDIY", id: "main") {
            RootView(helper: helper, model: model, tutorial: tutorial)
                .frame(minWidth: 1024, minHeight: 700)
                .task { await prepareTutorialHarness() }
                .task {
                    // Harness: start from the first-run screen.
                    if ProcessInfo.processInfo.environment["CADDIY_FIRSTRUN"] != nil {
                        try? await Task.sleep(for: .seconds(3))
                        model.newScan()
                    }
                }
                .task {
                    // Harness: send this edit once the demo model is showing.
                    guard let t = ProcessInfo.processInfo.environment["CADDIY_APPLY"] else { return }
                    try? await Task.sleep(for: .seconds(16))
                    model.send(t)
                }
                .task {
                    // Harness: turn the model this many degrees once it has loaded.
                    guard let d = ProcessInfo.processInfo.environment["CADDIY_YAW"].flatMap(Double.init) else { return }
                    try? await Task.sleep(for: .seconds(14))
                    model.viewer.turn(degrees: d)
                }
                .onReceive(NotificationCenter.default.publisher(for: .openFromFinder)) { n in
                    if let url = n.object as? URL {
                        model.open(url)
                        // Harness runs replace whatever model the helper still holds without asking.
                        if ProcessInfo.processInfo.environment["CADDIY_DEMO"] != nil { model.confirmPendingFile() }
                    }
                }
        }
        .defaultSize(width: 1280, height: 800)
        .windowToolbarStyle(.unified)
        .commands { AppCommands(model: model, tutorial: tutorial) }

        Settings {
            SettingsView(helper: helper)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Opened from Finder or `open -g`, the window could stay behind other apps. Bring it forward once at launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        // Test harness: CADDIY_APPEARANCE=light|dark, CADDIY_DEMO=<path to a mesh to open once the helper is up>.
        let env = ProcessInfo.processInfo.environment
        switch env["CADDIY_APPEARANCE"] {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        let tourScreen = Tutorial.harnessScreen(env)
        // A tour harness run on an early screen must not have the demo model jump it to Edit.
        if let demo = env["CADDIY_DEMO"], !demo.isEmpty, tourScreen == nil || tourScreen == .edit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                NotificationCenter.default.post(name: .openFromFinder, object: URL(fileURLWithPath: demo))
            }
        }
        // Screenshot runs set CADDIY_BACKGROUND so the app never jumps in front of other work.
        let quiet = env["CADDIY_BACKGROUND"] != nil
        if !quiet { NSApp.activate(ignoringOtherApps: true) }
        // SwiftUI makes the window a moment after launch. macOS 14 may refuse to activate an app opened in the
        // background, so order the window in regardless.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for w in NSApp.windows where w.canBecomeMain {
                // Tour harness runs use the smallest window, the hardest case for the bubble.
                if tourScreen != nil { w.setContentSize(NSSize(width: 1024, height: 700)) }
                if quiet { w.orderBack(nil) } else { w.orderFrontRegardless(); w.makeKey() }
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { NotificationCenter.default.post(name: .openFromFinder, object: url) }
    }
}

extension Notification.Name {
    static let openFromFinder = Notification.Name("CADDIY.openFromFinder")
}

// MARK: Menus

struct AppCommands: Commands {
    @ObservedObject var model: AppModel
    @ObservedObject var tutorial: Tutorial
    @AppStorage("textSize") private var textSize = TextSize.large
    @AppStorage("seenIntro") private var seenIntro = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Scan") {
                if model.step == .edit && model.hasModel { model.confirmNewScan = true } else { model.newScan() }
            }
            .keyboardShortcut("n")
            .disabled(model.isEditing)
            Button("Open a Scan File…") { NotificationCenter.default.post(name: .openScanFile, object: nil) }
                .keyboardShortcut("o")
                .disabled(!model.connected || model.isEditing)
            Button("Use a Sample") { seenIntro = true; model.useSample() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!model.connected || model.isEditing || model.step == .cleanUp)
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save STL…") { NotificationCenter.default.post(name: .saveModel, object: nil) }
                .keyboardShortcut("s")
                .disabled(!model.canSave)
        }
        CommandGroup(replacing: .undoRedo) {
            // Typing in the change field keeps normal text undo. Everywhere else, undo changes the model.
            Button("Undo Change") {
                if let tv = textEditor, tv.undoManager?.canUndo == true { tv.undoManager?.undo() } else { model.undo() }
            }
            .keyboardShortcut("z")
            Button("Redo Change") {
                if let tv = textEditor, tv.undoManager?.canRedo == true { tv.undoManager?.redo() } else { model.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Change") {
            Button("Type a Change") { NotificationCenter.default.post(name: .focusChangeField, object: nil) }
                .keyboardShortcut("l")
                .disabled(model.step != .edit)
            Divider()
            ForEach(Ideas.groups + Ideas.moreGroups, id: \.self) { group in
                Menu(group) {
                    ForEach(Ideas.all.filter { $0.group == group }) { idea in
                        Button(idea.fill ? idea.label + "…" : idea.label) { model.pick(idea) }
                    }
                }
                .disabled(model.step != .edit || model.isEditing || !model.connected)
            }
        }
        CommandGroup(before: .toolbar) {
            Button("Reset View") { model.viewer.resetView() }.keyboardShortcut("0").disabled(model.step != .edit)
            Button("Switch Stage Look") { model.viewer.newStage.toggle() }
                .keyboardShortcut("l", modifiers: [.command, .shift]).disabled(model.step != .edit)
            Button("Zoom In") { model.viewer.zoom(by: 1.25) }.keyboardShortcut("+").disabled(model.step != .edit)
            Button("Zoom Out") { model.viewer.zoom(by: 0.8) }.keyboardShortcut("-").disabled(model.step != .edit)
            Divider()
        }
        CommandGroup(after: .toolbar) {
            Picker("Text Size", selection: $textSize) {
                ForEach(TextSize.allCases) { Text($0.label).tag($0) }
            }
            Divider()
        }
        CommandGroup(replacing: .appInfo) {
            Button("About CADDIY") { AboutWindow.show() }
        }
        CommandGroup(replacing: .help) {
            Button("Show Me Around") { tutorial.startHere() }
                .disabled(!model.connected || tutorial.isOn)
            Button("Show the Intro Again") { seenIntro = false; if model.step != .scan { model.backToScan() } }
                .disabled(model.step == .edit)
        }
    }

    private var textEditor: NSTextView? { NSApp.keyWindow?.firstResponder as? NSTextView }
}
