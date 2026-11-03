import SwiftUI

/// Real controls the Caddy tour can point at. Lives here so CADScan and CADViewer controls can be tagged too.
public enum TutorialTarget: String, CaseIterable, Sendable {
    case startScanning, sampleChip, processStatus
    case viewer, viewerTools, taller, history, saveSTL, openIn
}

/// Where each tagged control sits, in window coordinates (top left origin).
/// Global frames are used because preferences do not cross the AppKit views behind HSplitView.
@MainActor public final class TutorialFrames: ObservableObject {
    @Published public var rects: [TutorialTarget: CGRect] = [:]
    /// Which copy of a control wrote each rect, so an old copy going away never clears a new one.
    public var owners: [TutorialTarget: UUID] = [:]
    public init() {}
}

private struct TutorialFramesKey: EnvironmentKey { static let defaultValue: TutorialFrames? = nil }
private struct TutorialFocusKey: EnvironmentKey { static let defaultValue: TutorialTarget? = nil }

public extension EnvironmentValues {
    /// Set at the window root while the app runs. Nil in previews, so tags do nothing there.
    var tutorialFrames: TutorialFrames? {
        get { self[TutorialFramesKey.self] }
        set { self[TutorialFramesKey.self] = newValue }
    }
    /// The control the tour points at now, if any. Scroll views use it to bring that control into view.
    var tutorialFocus: TutorialTarget? {
        get { self[TutorialFocusKey.self] }
        set { self[TutorialFocusKey.self] = newValue }
    }
}

public extension View {
    /// Lets the Caddy tour find this control. Nil does nothing.
    func tutorialTarget(_ target: TutorialTarget?) -> some View { modifier(TutorialTag(target: target)) }
}

private struct TutorialTag: ViewModifier {
    let target: TutorialTarget?
    @Environment(\.tutorialFrames) private var frames
    @State private var token = UUID()

    private func store(_ r: CGRect, _ target: TutorialTarget, _ frames: TutorialFrames) {
        frames.owners[target] = token
        if frames.rects[target] != r { frames.rects[target] = r }
    }

    func body(content: Content) -> some View {
        if let target, let frames {
            content
                .id(target)
                // A GeometryReader, because onGeometryChange misses the resize when HSplitView sizes its panes.
                .background(GeometryReader { g in
                    let r = g.frame(in: .global)
                    Color.clear
                        .onAppear { store(r, target, frames) }
                        .onChange(of: r) { _, now in store(now, target, frames) }
                })
                // Only clear our own rect, so a new copy of the same control that appeared first keeps its frame.
                .onDisappear {
                    if frames.owners[target] == token { frames.rects[target] = nil; frames.owners[target] = nil }
                }
        } else {
            content
        }
    }
}

/// A vertical ScrollView that scrolls the control the tour points at into view.
public struct TutorialScrollView<Content: View>: View {
    @Environment(\.tutorialFocus) private var focus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView { content }
                .onAppear { scroll(proxy) }
                .onChange(of: focus) { _, _ in scroll(proxy) }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let focus else { return }
        // Scrolling to an id this view does not hold does nothing.
        withAnimation(Theme.motion(reduceMotion)) { proxy.scrollTo(focus, anchor: .center) }
    }
}
