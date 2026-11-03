import SwiftUI
import AppKit
import CADShared

/// Caddy the mascot. One image per pose from Resources/Caddy.
/// Decorative: the text next to Caddy does the talking, so VoiceOver skips the picture unless a label is given.
struct CaddyView: View {
    enum Pose: String, CaseIterable {
        case hello, pointRight = "point_right", pointLeft, thinking, idea, cheer, loveIt = "love_it"
        case sleepy, sad, talking, hatching, logo = "logo_neutral"

        /// pointLeft is point_right mirrored.
        var file: String { self == .pointLeft ? Pose.pointRight.rawValue : rawValue }
    }

    var pose: Pose = .hello
    /// Side length in points, before the text size scale.
    var size: CGFloat = 64
    /// Set only where Caddy is the only thing that says something.
    var label: String? = nil
    /// A slow gentle bob with a slight sway. Off when Reduce Motion is on.
    var idle = false
    /// The hello pose waves once when it appears. Off when Reduce Motion is on.
    var wave = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var scale

    var body: some View {
        let side = size * scale
        Group {
            if let img = Self.image(pose) {
                Image(nsImage: img).resizable().interpolation(.high).antialiased(true)
            } else {
                Image(systemName: "bird").resizable().foregroundStyle(Theme.accent)
            }
        }
        .aspectRatio(contentMode: .fit)
        .scaleEffect(x: pose == .pointLeft ? -1 : 1, y: 1)
        .frame(width: side, height: side)
        .modifier(HelloWave(on: wave && pose == .hello && !reduceMotion))
        .modifier(IdleBob(on: idle && !reduceMotion))
        .accessibilityHidden(label == nil)
        .accessibilityLabel(label ?? "")
        .accessibilityAddTraits(.isImage)
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(_ pose: Pose) -> NSImage? {
        if let hit = cache[pose.file] { return hit }
        guard let url = Bundle.module.url(forResource: pose.file, withExtension: "png", subdirectory: "Caddy"),
              let img = NSImage(contentsOf: url) else { return nil }
        cache[pose.file] = img
        return img
    }
}

/// Caddy's speech bubble: gold with dark text.
struct CaddyBubble: View {
    let text: String
    var body: some View {
        Text(text)
            .themeFont(.secondary).fontWeight(.semibold).foregroundStyle(Theme.onGold)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .frame(maxWidth: 240)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Caddy as a button. A click makes him say a line for this moment in a bubble above him.
struct TalkingCaddy: View {
    let moment: CaddyMoment
    var pose: CaddyView.Pose = .hello
    var size: CGFloat = 64
    var idle = false
    /// Which way the bubble lines up with Caddy, so it stays inside the screen.
    var bubbleAlignment: Alignment = .top
    @State private var saying: CaddyLine?
    @State private var last: CaddyLine?
    @State private var hop = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var scale
    private var below: Bool { bubbleAlignment.vertical != .top }

    var body: some View {
        Button(action: talk) {
            // The pose follows the line. A plain swap, no cross fade.
            CaddyView(pose: saying?.pose ?? pose, size: size, idle: idle && saying == nil, wave: false)
                .transaction { $0.animation = nil }
                .offset(y: hop ? -6 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Above Caddy for .top, below him otherwise. A clear gap the size of Caddy pushes the bubble past him.
        .overlay(alignment: below ? Alignment(horizontal: bubbleAlignment.horizontal, vertical: .top)
                                  : Alignment(horizontal: bubbleAlignment.horizontal, vertical: .bottom)) {
            if let saying {
                VStack(alignment: bubbleAlignment.horizontal, spacing: 6) {
                    if below { Color.clear.frame(width: 1, height: size * scale) }
                    CaddyBubble(text: saying.text)
                    if !below { Color.clear.frame(width: 1, height: size * scale) }
                }
                // A fixed slot so a small Caddy does not squeeze the bubble into a thin column.
                .frame(width: 240, alignment: Alignment(horizontal: bubbleAlignment.horizontal, vertical: .center))
                .transition(reduceMotion ? .identity : .scale(scale: 0.7, anchor: below ? .top : .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        // The bubble draws over whatever sits next to Caddy.
        .zIndex(saying == nil ? 0 : 1)
        .help("Click Caddy for a tip")
        .accessibilityLabel("Caddy")
        .accessibilityHint("Says a tip")
        .task(id: saying) {
            // A line with a follow up hands over to it sooner, then the follow up clears as usual.
            guard let now = saying else { return }
            try? await Task.sleep(for: .seconds(now.then.isEmpty ? 4 : 2))
            guard !Task.isCancelled else { return }
            let next = now.then.first
            withAnimation(Theme.motion(reduceMotion)) { saying = next }
            if let next { AccessibilityNotification.Announcement(next.text).post() }
        }
    }

    private func talk() {
        let line = CaddyLines.pick(moment, after: last)
        last = line
        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.6)) { saying = line }
        AccessibilityNotification.Announcement(line.text).post()
        guard !reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { hop = false }
        }
    }
}

/// Three points up and down with a one degree sway, over three seconds. Nothing else moves.
private struct IdleBob: ViewModifier {
    let on: Bool
    @State private var up = false
    private let loop = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(on ? (up ? 1 : -1) : 0), anchor: .bottom)
            .offset(y: on && up ? -3 : 0)
            .onAppear { if on { withAnimation(loop) { up = true } } }
            .onChange(of: on) { _, now in
                if now { withAnimation(loop) { up = true } }
                else { withAnimation(nil) { up = false } }
            }
    }
}

/// One small two-swing wave from the bottom, once, on appear. Then still.
private struct HelloWave: ViewModifier {
    let on: Bool
    @State private var angle: Double = 0
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle), anchor: .bottom)
            .task {
                guard on else { return }
                try? await Task.sleep(for: .milliseconds(350))
                for a in [-6.0, 5, -3, 0] {
                    withAnimation(.easeInOut(duration: 0.18)) { angle = a }
                    try? await Task.sleep(for: .milliseconds(180))
                }
            }
    }
}
