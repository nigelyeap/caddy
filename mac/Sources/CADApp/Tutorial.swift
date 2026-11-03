import SwiftUI
import CADShared

// The Caddiy tour: the step table, the rules that move it on, and the state that runs it.
// Steps move on when app state changes, so menu items and keyboard shortcuts count too.

enum TutorialScreen: Equatable, Sendable {
    case firstRun, scan, process, edit

    static func of(step: AppModel.Step, seenIntro: Bool) -> TutorialScreen {
        switch step {
        case .scan: seenIntro ? .scan : .firstRun
        case .cleanUp: .process
        case .edit: .edit
        }
    }
}

/// The app state the tour reads. Built fresh on every change and compared with the state when the step began.
struct TutorialSnapshot: Equatable {
    var screen: TutorialScreen = .firstRun
    var connected = true
    var versions = 0
    var redo = 0
    var isEditing = false
    var editBad = false
    var processFailed = false
    var orbitCount = 0
    /// False until the first status reply, so a saved model never flashes the welcome step first.
    var loaded = true
}

/// How a step moves on.
enum TutorialAdvance: Equatable {
    /// A Next button. Return presses it.
    case next
    /// Waits for the kid to change screen. The screen jump picks the next step.
    case leaveScreen
    case orbit, edit, undo

    var isAction: Bool { self != .next }

    func done(from a: TutorialSnapshot, to b: TutorialSnapshot) -> Bool {
        switch self {
        case .next, .leaveScreen: false
        case .orbit: b.orbitCount > a.orbitCount
        case .edit: b.versions > a.versions && !b.isEditing
        case .undo: b.redo > a.redo
        }
    }
}

/// Where the bubble goes when there is no hole.
enum BubbleSpot: Equatable { case auto, center }

struct TutorialStep {
    let id: String
    let screen: TutorialScreen
    let target: TutorialTarget?
    let line: String
    let pose: CaddiyView.Pose
    let advance: TutorialAdvance
    /// The menu or keyboard way to do the same thing.
    var hint: String? = nil
    var spot: BubbleSpot = .auto
    /// Button titles for the very first step.
    var nextTitle = "Next"
    var skipTitle = "Skip tour"
    /// False keeps clicks off the real control, so a look-only step never opens a save panel or a browser.
    var touchable = true
}

enum TutorialScript {
    static let steps: [TutorialStep] = [
        TutorialStep(id: "welcome", screen: .firstRun, target: nil,
                     line: "Hi, I am Caddiy! Want me to show you around?", pose: .hatching, advance: .next,
                     spot: .center, nextTitle: "Yes please", skipTitle: "No thanks"),
        TutorialStep(id: "startScanning", screen: .firstRun, target: .startScanning,
                     line: "Tap Start scanning to begin.", pose: .pointRight, advance: .leaveScreen),
        TutorialStep(id: "sample", screen: .scan, target: .sampleChip,
                     line: "The scanner is not here yet. Tap Use the sample model.",
                     pose: .pointRight, advance: .leaveScreen, hint: "Or press Shift Command S."),
        TutorialStep(id: "process", screen: .process, target: .processStatus,
                     line: "I am building your model. It takes a few seconds.", pose: .thinking, advance: .leaveScreen),
        TutorialStep(id: "viewer", screen: .edit, target: .viewer,
                     line: "Here is your model! Drag it to turn it around.", pose: .loveIt, advance: .orbit),
        TutorialStep(id: "viewerTools", screen: .edit, target: .viewerTools,
                     line: "These buttons spin it, add a grid and more. Try one!",
                     pose: .pointRight, advance: .next, hint: "Lost your model? Reset view brings it back."),
        TutorialStep(id: "taller", screen: .edit, target: .taller,
                     line: "Tap Taller to make it grow! You can type ideas too.", pose: .pointRight, advance: .edit,
                     hint: "Or use the Change menu."),
        TutorialStep(id: "undo", screen: .edit, target: .history,
                     line: "Every change goes in this list. Tap Undo to go back.", pose: .pointRight, advance: .undo,
                     hint: "Or press Command Z."),
        TutorialStep(id: "save", screen: .edit, target: .saveSTL,
                     line: "Save STL keeps your model for a 3D printer. Try it after the tour.",
                     pose: .idea, advance: .next, hint: "Or press Command S.", touchable: false),
        TutorialStep(id: "openIn", screen: .edit, target: .openIn,
                     line: "These open your model in Tinkercad or FreeCAD.", pose: .talking, advance: .next,
                     touchable: false),
        TutorialStep(id: "tips", screen: .edit, target: nil,
                     line: "More tips: Command Z undoes. The View menu changes text size.", pose: .idea, advance: .next,
                     hint: "Grown-ups can press Command comma for Settings.", spot: .center),
        TutorialStep(id: "done", screen: .edit, target: nil,
                     line: "You did it! Now go make something cool.", pose: .cheer, advance: .next,
                     spot: .center, nextTitle: "Done"),
    ]

    static func firstIndex(for screen: TutorialScreen) -> Int {
        steps.firstIndex { $0.screen == screen } ?? 0
    }

    /// "7", "viewer" or "off". Steps count from 1.
    static func index(forHarness value: String) -> Int? {
        if let n = Int(value), steps.indices.contains(n - 1) { return n - 1 }
        return steps.firstIndex { $0.id == value }
    }

    /// The line and pose to show now. Extra lines replace the main one for waits and failures.
    static func say(_ step: TutorialStep, entry: TutorialSnapshot, now: TutorialSnapshot,
                    elapsed: TimeInterval, nudge: Bool, hasHole: Bool) -> (line: String, pose: CaddiyView.Pose) {
        if !now.connected { return ("I lost my connection. Wait a moment.", .sleepy) }
        if step.advance == .edit {
            if now.isEditing {
                return elapsed > 15 ? ("This one takes a while. I am still going.", .thinking)
                                    : ("I am working on it. Hold on!", .thinking)
            }
            if now.editBad { return ("That did not work. Tap Taller again, or skip this step.", .sad) }
        }
        if nudge { return (hasHole ? "Tap the bright spot." : "Use the buttons in my bubble.", .pointRight) }
        if step.id == "process" && now.processFailed { return ("That did not work. Tap Back to scan or use the sample.", .sad) }
        if step.id == "process" && elapsed > 20 { return ("Still building. Thanks for waiting!", .thinking) }
        return (step.line, step.pose)
    }

    /// Every line the tour can say, for the copy checks.
    static var allLines: [String] {
        steps.flatMap { [$0.line] + ($0.hint.map { [$0] } ?? []) } + [
            "I lost my connection. Wait a moment.", "This one takes a while. I am still going.",
            "I am working on it. Hold on!", "That did not work. Tap Taller again, or skip this step.",
            "Tap the bright spot.", "Use the buttons in my bubble.", "Still building. Thanks for waiting!",
            "Leave the tour?", "You can come back from the Help menu.",
            "That did not work. Tap Back to scan or use the sample.",
        ]
    }
}

// MARK: Bubble placement

enum BubblePlacement {
    static let margin: CGFloat = 8
    static let gap: CGFloat = 10
    static let holePad: CGFloat = 4

    /// The bubble width for a text scale, capped so it fits beside the 3D view at the smallest window.
    static func width(scale: CGFloat, bounds: CGRect) -> CGFloat {
        min(300 * scale, 330, bounds.width - 2 * margin)
    }

    /// Right of the hole, then left, below, above. Each side must hold the whole bubble inside the bounds.
    /// A hole too big for any side gets the bubble in its own top trailing corner, so most of it stays clear.
    static func place(hole: CGRect?, size: CGSize, in bounds: CGRect, spot: BubbleSpot = .auto) -> CGRect {
        let inner = bounds.insetBy(dx: margin, dy: margin)
        func clampX(_ x: CGFloat) -> CGFloat { min(max(x, inner.minX), inner.maxX - size.width) }
        func clampY(_ y: CGFloat) -> CGFloat { min(max(y, inner.minY), inner.maxY - size.height) }
        guard let hole else {
            return CGRect(x: bounds.midX - size.width / 2, y: clampY(bounds.midY - size.height / 2),
                          width: size.width, height: size.height)
        }
        let h = hole.insetBy(dx: -holePad, dy: -holePad)
        let tries = [
            CGRect(x: h.maxX + gap, y: clampY(h.midY - size.height / 2), width: size.width, height: size.height),
            CGRect(x: h.minX - gap - size.width, y: clampY(h.midY - size.height / 2), width: size.width, height: size.height),
            CGRect(x: clampX(h.midX - size.width / 2), y: h.maxY + gap, width: size.width, height: size.height),
            CGRect(x: clampX(h.midX - size.width / 2), y: h.minY - gap - size.height, width: size.width, height: size.height),
        ]
        if let fit = tries.first(where: { inner.contains($0) && !$0.intersects(h) }) { return fit }
        // Big hole: sit inside its top trailing corner.
        let clip = h.intersection(inner)
        if clip.width >= size.width * 1.5 && clip.height >= size.height * 1.5 {
            return CGRect(x: clip.maxX - size.width - gap, y: clip.minY + gap, width: size.width, height: size.height)
        }
        // Otherwise the corner farthest from the hole.
        let corners = [
            CGPoint(x: inner.minX, y: inner.minY), CGPoint(x: inner.maxX - size.width, y: inner.minY),
            CGPoint(x: inner.minX, y: inner.maxY - size.height), CGPoint(x: inner.maxX - size.width, y: inner.maxY - size.height),
        ].map { CGRect(origin: $0, size: size) }
        func dist(_ r: CGRect) -> CGFloat { hypot(r.midX - h.midX, r.midY - h.midY) }
        return corners.max { dist($0) < dist($1) }!
    }

    /// The bubble may cover a big hole, but never more than a third of it.
    static func overlaps(_ bubble: CGRect, hole: CGRect?) -> Bool {
        guard let hole else { return false }
        let h = hole.insetBy(dx: -holePad, dy: -holePad)
        let cut = bubble.intersection(h)
        if cut.isNull || cut.width <= 0.5 || cut.height <= 0.5 { return false }
        return cut.width * cut.height > h.width * h.height / 3 || !(h.width >= bubble.width * 1.5 && h.height >= bubble.height * 1.5)
    }
}

// MARK: State

@MainActor
final class Tutorial: ObservableObject {
    enum Harness: Equatable { case normal, off, start(Int) }

    @Published private(set) var index: Int?
    @Published private(set) var entry = TutorialSnapshot()
    @Published private(set) var stepStarted = Date()
    /// True for two seconds after a click on the dim area.
    @Published private(set) var nudging = false
    let frames = TutorialFrames()

    let harness: Harness
    private var offered = false
    private var harnessStarted = false
    /// Set once the harness has moved the app to the right screen, so the tour does not start on the way there.
    private var harnessReady = false
    private var lastLog = ""
    private var lastSnapshot = TutorialSnapshot()
    private static let doneKey = "tutorialDone"

    init(environment env: [String: String] = ProcessInfo.processInfo.environment) {
        harness = Self.harness(from: env)
    }

    static func harness(from env: [String: String]) -> Harness {
        if let v = env["CADDIY_TUTORIAL"] {
            if v == "off" { return .off }
            if let i = TutorialScript.index(forHarness: v) { return .start(i) }
            return .off
        }
        // The old screenshot harness must not change, so any harness variable turns the tour off.
        if ["CADDIY_DEMO", "CADDIY_FIRSTRUN", "CADDIY_APPLY", "CADDIY_YAW"].contains(where: { env[$0] != nil }) { return .off }
        return .normal
    }

    /// The screen a harness step needs, so the app can get there first.
    static func harnessScreen(_ env: [String: String] = ProcessInfo.processInfo.environment) -> TutorialScreen? {
        if case .start(let i) = harness(from: env) { return TutorialScript.steps[i].screen }
        return nil
    }

    var isHarness: Bool { if case .start = harness { true } else { false } }
    var step: TutorialStep? { index.map { TutorialScript.steps[$0] } }
    var isOn: Bool { index != nil }
    private var done: Bool { UserDefaults.standard.bool(forKey: Self.doneKey) }

    // MARK: Driving

    /// Called on every app state change.
    func check(_ now: TutorialSnapshot) {
        lastSnapshot = now
        guard let i = index else { maybeStart(now); return }
        let step = TutorialScript.steps[i]
        if now.screen != step.screen {
            go(to: TutorialScript.firstIndex(for: now.screen), now)
            return
        }
        // Paused while the connection is gone. The entry state stays, so nothing is missed.
        guard now.connected else { return }
        if step.advance.done(from: entry, to: now) { go(to: i + 1, now) }
    }

    private func maybeStart(_ now: TutorialSnapshot) {
        switch harness {
        case .off: return
        case .start(let i):
            guard harnessReady, !harnessStarted, now.connected, TutorialScript.steps[i].screen == now.screen else { return }
            harnessStarted = true
            go(to: i, now)
        case .normal:
            // Offer the tour once, on the first-run screen of a fresh install.
            guard !offered, !done, now.connected, now.loaded, now.screen == .firstRun else { return }
            offered = true
            go(to: 0, now)
        }
    }

    func harnessPrepared() {
        harnessReady = true
        maybeStart(lastSnapshot)
    }

    /// Help menu: start at the first step for the screen on show.
    func startHere() {
        go(to: TutorialScript.firstIndex(for: lastSnapshot.screen), lastSnapshot)
    }

    func next() {
        guard let i = index else { return }
        go(to: i + 1, lastSnapshot)
    }

    func back() {
        guard let i = index, canGoBack else { return }
        go(to: i - 1, lastSnapshot)
    }

    var canGoBack: Bool {
        guard let i = index, i > 0 else { return false }
        return TutorialScript.steps[i - 1].screen == TutorialScript.steps[i].screen
    }

    /// Skip and finish both end the tour and mark it seen.
    func finish() {
        index = nil
        nudging = false
        entry = TutorialSnapshot()
        lastLog = ""
        if !isHarness { UserDefaults.standard.set(true, forKey: Self.doneKey) }
    }

    private var nudgeTask: Task<Void, Never>?

    func nudge() {
        nudging = true
        // A new click restarts the two seconds, so an old timer never cuts a fresh nudge short.
        nudgeTask?.cancel()
        nudgeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.nudging = false
        }
    }

    private func go(to i: Int, _ now: TutorialSnapshot) {
        guard TutorialScript.steps.indices.contains(i) else { finish(); return }
        index = i
        entry = now
        stepStarted = Date()
        nudging = false
    }

    /// Harness only: one stderr line per new layout.
    func log(hole: CGRect?, bubble: CGRect, bounds: CGRect) {
        guard isHarness, let i = index else { return }
        func s(_ r: CGRect?) -> String {
            guard let r else { return "none" }
            return "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width))x\(Int(r.height))"
        }
        let overlap = BubblePlacement.overlaps(bubble, hole: hole)
        let inBounds = bounds.insetBy(dx: -0.5, dy: -0.5).contains(bubble)
        var text = "tutorial step=\(i + 1) id=\(TutorialScript.steps[i].id) hole=\(s(hole)) bubble=\(s(bubble)) bounds=\(s(bounds)) overlap=\(overlap) inBounds=\(inBounds)"
        if !(ProcessInfo.processInfo.environment["CADDIY_TUTORIAL_DEBUG"] ?? "").isEmpty {
            text += " rects=" + frames.rects.map { "\($0.key.rawValue):\(s($0.value))" }.sorted().joined(separator: " ")
        }
        guard text != lastLog else { return }
        lastLog = text
        FileHandle.standardError.write(Data((text + "\n").utf8))
    }
}
