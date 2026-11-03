import SwiftUI
import AppKit
import CADShared

/// The Caddy tour on screen: a dim layer with a hole over the real control, and a speech bubble.
/// Clicks inside the hole reach the real control. Clicks on the dim layer get a gentle nudge.
struct TutorialOverlay: View {
    @ObservedObject var tutorial: Tutorial
    @ObservedObject var model: AppModel
    @ObservedObject var viewer: ViewerControl
    @ObservedObject var frames: TutorialFrames
    let seenIntro: Bool
    let textSize: TextSize

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var bubbleSize = CGSize(width: 300, height: 160)
    /// True while Caddy asks "Leave the tour?". CADDY_TUTORIAL_ASK=1 opens on it, for screenshots.
    @State private var askingLeave = ProcessInfo.processInfo.environment["CADDY_TUTORIAL_ASK"] != nil

    private var snapshot: TutorialSnapshot {
        TutorialSnapshot(
            screen: .of(step: model.step, seenIntro: seenIntro), connected: model.connected,
            versions: model.state?.versions.count ?? 0, redo: model.state?.redo.count ?? 0,
            isEditing: model.isEditing, editBad: model.note?.kind == .bad, processFailed: model.processing?.failure != nil,
            orbitCount: viewer.orbitCount, loaded: model.state != nil)
    }

    var body: some View {
        GeometryReader { geo in
            if let i = tutorial.index {
                let step = TutorialScript.steps[i]
                let bounds = CGRect(origin: .zero, size: geo.size)
                let hole = holeRect(step, origin: geo.frame(in: .global).origin, bounds: bounds)
                let width = BubblePlacement.width(scale: textSize.scale, bounds: bounds)
                let size = CGSize(width: width, height: bubbleSize.height)
                let rect = BubblePlacement.place(hole: hole, size: size, in: bounds, spot: step.spot)
                ZStack(alignment: .topLeading) {
                    dim(hole: hole, bounds: bounds, touchable: step.touchable)
                    if let hole {
                        RoundedRectangle(cornerRadius: Theme.corner + 2, style: .continuous)
                            .strokeBorder(Theme.accent, lineWidth: 3)
                            .frame(width: hole.width + 8, height: hole.height + 8)
                            .position(x: hole.midX, y: hole.midY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    bubble(index: i, step: step, hole: hole, bubble: rect)
                        .frame(width: width)
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { bubbleSize = $0 }
                        .position(x: rect.midX, y: rect.midY)
                }
                .onChange(of: LayoutLog(hole: hole, bubble: rect, bounds: bounds, measured: bubbleSize), initial: true) { _, l in
                    // Log once the bubble has its real height, so the line matches the screen.
                    if abs(l.measured.height - l.bubble.height) < 1 { tutorial.log(hole: l.hole, bubble: l.bubble, bounds: l.bounds) }
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(tutorial.isOn)
        .animation(Theme.motion(reduceMotion), value: tutorial.index)
        .onChange(of: snapshot, initial: true) { _, s in tutorial.check(s) }
        .onChange(of: tutorial.index) { old, _ in if old != nil { askingLeave = false }; announce() }
    }

    // MARK: Pieces

    /// The target in this view's space. Nil when it is missing or scrolled out of sight, so the bubble centres.
    private func holeRect(_ step: TutorialStep, origin: CGPoint, bounds: CGRect) -> CGRect? {
        guard let t = step.target, let r = frames.rects[t] else { return nil }
        let local = r.offsetBy(dx: -origin.x, dy: -origin.y)
        let seen = local.intersection(bounds)
        guard !seen.isNull, seen.width >= 8, seen.height >= 8 else { return nil }
        return seen
    }

    /// An untouchable step still shows the hole, but the dim layer takes the clicks in it too.
    private func dim(hole: CGRect?, bounds: CGRect, touchable: Bool) -> some View {
        var path = Path(bounds)
        if let hole {
            path.addRoundedRect(in: hole.insetBy(dx: -BubblePlacement.holePad, dy: -BubblePlacement.holePad),
                                cornerSize: CGSize(width: Theme.corner, height: Theme.corner))
        }
        return path
            .fill(Color.black.opacity(reduceTransparency ? 0.85 : 0.45), style: FillStyle(eoFill: true))
            .contentShape(touchable ? path : Path(bounds), eoFill: true)
            .onTapGesture { tutorial.nudge() }
            .accessibilityHidden(true)
    }

    private func bubble(index i: Int, step: TutorialStep, hole: CGRect?, bubble: CGRect) -> some View {
        // Caddy sits on the side nearest the hole and points at it.
        let holeLeft = hole.map { $0.midX < bubble.midX } ?? false
        return TimelineView(.periodic(from: tutorial.stepStarted, by: 1)) { ctx in
            let since = step.advance == .edit ? (model.editStartedAt ?? ctx.date) : tutorial.stepStarted
            let said = TutorialScript.say(step, entry: tutorial.entry, now: snapshot,
                                          elapsed: ctx.date.timeIntervalSince(since),
                                          nudge: tutorial.nudging, hasHole: hole != nil && step.touchable)
            let pose: CaddyView.Pose = askingLeave ? .thinking : said.pose == .pointRight && holeLeft ? .pointLeft : said.pose
            HStack(alignment: .top, spacing: Theme.Space.xs) {
                if holeLeft { caddy(pose) }
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    progress(i)
                    Text(askingLeave ? "Leave the tour?" : said.line)
                        .themeFont(.body).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = askingLeave ? "You can come back from the Help menu." : step.hint, model.connected {
                        Text(hint).themeFont(.caption).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if askingLeave { leaveButtons } else { buttons(i, step) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !holeLeft { caddy(pose) }
            }
        }
        .padding(Theme.Space.s)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.accent, lineWidth: 1.5))
        .shadow(color: Theme.shadow, radius: 12, y: 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Caddy tour")
        .accessibilityAddTraits(step.advance == .next ? .isModal : [])
        .modifier(DoItAction(step: step, perform: { perform(step) }))
    }

    private func caddy(_ pose: CaddyView.Pose) -> some View {
        // Caddy sits in a soft sunny circle, the same well the home screen uses.
        CaddyView(pose: pose, size: 44, idle: true)
            .padding(6)
            .background(Circle().fill(Theme.tintSun.fill))
            .overlay(Circle().strokeBorder(Theme.tintSun.edge, lineWidth: 1))
    }

    private func progress(_ i: Int) -> some View {
        let n = TutorialScript.steps.count
        return HStack(spacing: Theme.Space.xs) {
            Text("\(i + 1) of \(n)").themeFont(.caption).monospacedDigit().foregroundStyle(Theme.muted).fixedSize()
            GeometryReader { g in
                Capsule().fill(Theme.line)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(i + 1) / CGFloat(n))
                    }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(i + 1) of \(n)")
    }

    /// Escape on this question keeps the tour going, so a second press never ends it by accident.
    private var leaveButtons: some View {
        HStack(spacing: Theme.Space.xs) {
            Button("Leave") { tutorial.finish() }.buttonStyle(BigButtonStyle(.secondary, compact: true))
            Spacer(minLength: 0)
            Button("Keep going") { askingLeave = false }
                .buttonStyle(BigButtonStyle(.primary, compact: true))
                .keyboardShortcut(.cancelAction)
        }
    }

    @ViewBuilder private func buttons(_ i: Int, _ step: TutorialStep) -> some View {
        let isNext = step.advance == .next
        let row = Group {
            // The welcome step only offers the tour, so No thanks needs no question.
            Button(step.skipTitle) { if i == 0 { tutorial.finish() } else { askingLeave = true } }
                .buttonStyle(.link).themeFont(.caption).foregroundStyle(Theme.muted)
                .keyboardShortcut(.cancelAction)
            Spacer(minLength: 0)
            if isNext && tutorial.canGoBack {
                Button("Back") { tutorial.back() }.buttonStyle(BigButtonStyle(.secondary, compact: true))
            }
            if isNext {
                Button(step.nextTitle) { tutorial.next() }
                    .buttonStyle(BigButtonStyle(.primary, compact: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        VStack(alignment: .leading, spacing: Theme.Space.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xs) { row }
                VStack(alignment: .trailing, spacing: Theme.Space.xs) { row }
            }
            // A way past any action step, hidden while an edit runs so the kid waits for it.
            if step.advance.isAction && step.advance != .leaveScreen && !model.isEditing && model.connected {
                Button("Skip this step") { tutorial.next() }
                    .buttonStyle(.link).themeFont(.caption).foregroundStyle(Theme.muted)
            }
        }
    }

    // MARK: Actions

    /// VoiceOver "Do it" does the step's action for the kid.
    private func perform(_ step: TutorialStep) {
        switch step.advance {
        case .orbit: viewer.turn(degrees: 30)
        case .edit: if let t = Ideas.all.first(where: { $0.short == "Taller" }) { model.send(t.text) }
        case .undo: model.undo()
        case .next, .leaveScreen: break
        }
    }

    private func announce() {
        guard let step = tutorial.step else { return }
        let said = TutorialScript.say(step, entry: tutorial.entry, now: snapshot, elapsed: 0, nudge: false, hasHole: true)
        AccessibilityNotification.Announcement(said.line).post()
    }
}

private struct LayoutLog: Equatable {
    var hole: CGRect?
    var bubble: CGRect
    var bounds: CGRect
    var measured: CGSize
}

private struct DoItAction: ViewModifier {
    let step: TutorialStep
    let perform: () -> Void
    func body(content: Content) -> some View {
        if step.advance.isAction && step.advance != .leaveScreen {
            content.accessibilityAction(named: "Do it", perform)
        } else {
            content
        }
    }
}
