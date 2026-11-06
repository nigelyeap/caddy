import AppKit
import CADShared
import SwiftUI

/// The hand cursor over the stage. A ring for an open hand, a filled gold dot while pinching.
/// Put it on top of the stage. It never takes clicks.
public struct HandCursor: View {
    @ObservedObject private var hands: HandControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(hands: HandControl) { self.hands = hands }

    public var body: some View {
        GeometryReader { g in
            let at = { (p: CGPoint) in CGPoint(x: p.x * g.size.width, y: p.y * g.size.height) }
            if hands.enabled {
                if case .zooming(let a, let b) = hands.state {
                    // Both hands pinching: two gold dots joined by a line that stretches as they spread.
                    Path { $0.move(to: at(a)); $0.addLine(to: at(b)) }
                        .stroke(Theme.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 7]))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    pinchDot.position(at(a))
                    pinchDot.position(at(b))
                } else if let p = hands.state.point {
                    if let s = hands.second { ring.opacity(0.45).position(at(s)) }
                    mark
                        .position(at(p))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hands.state.isPinched)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var mark: some View {
        switch hands.state {
        case .pinched, .zooming:
            pinchDot
        case .paused:
            Image(systemName: "hand.raised.slash.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Overlay.text)
                .padding(7)
                .background(Theme.Overlay.backing, in: Circle())
        case .open, .noHand:
            ring
        }
    }

    private var pinchDot: some View {
        Circle().fill(Theme.gold)
            .frame(width: 22, height: 22)
            .overlay(Circle().strokeBorder(Theme.goldEdge, lineWidth: 2))
            .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
            // A ring fills around the dot while a still pinch counts toward a hold.
            .background(Circle().trim(from: 0, to: hands.holdProgress)
                .stroke(Theme.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 38, height: 38)
                .opacity(hands.holdProgress > 0 ? 1 : 0))
    }

    private var ring: some View {
        Circle().strokeBorder(Theme.Overlay.text, lineWidth: 3)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Color.black.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
    }
}

/// A small mirror of the camera with the hand drawn on it and one line saying what to do next.
public struct HandCameraBubble: View {
    @ObservedObject private var hands: HandControl

    public init(hands: HandControl) { self.hands = hands }

    public var body: some View {
        if hands.enabled {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                if hands.problem == nil {
                    ZStack {
                        CameraMirror(layer: hands.previewLayer)
                        HandSkeleton(poses: hands.poses, pinched: hands.state.isPinched)
                    }
                    .frame(width: 176, height: 176 / (hands.poses.first?.aspect ?? 4.0 / 3.0))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                    .accessibilityHidden(true)
                }
                Label(hint, systemImage: symbol)
                    .themeFont(.caption)
                    .foregroundStyle(hands.problem == nil ? Theme.Overlay.text : Theme.Overlay.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: 176, alignment: .leading)
            }
            .padding(Theme.Space.xs)
            .background(Theme.Overlay.backing, in: RoundedRectangle(cornerRadius: Theme.buttonCorner + 4, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var hint: String {
        switch hands.problem {
        case .notAllowed?: return "CADDY can't use the camera. Turn it on in System Settings, Privacy, Camera."
        case .noCamera?: return "I can't find a camera."
        case .inUse?: return "Another app is using the camera."
        case nil: break
        }
        switch hands.state {
        case .noHand: return "Hold up your hand so I can see it."
        case .open:
            if hands.poses.first?.isTwoFingers == true { return "Two fingers ready. Swipe sideways to change tool." }
            return hands.hints.open
        case .pinched: return hands.holdProgress > 0 ? "Hold still..." : hands.hints.pinched
        case .paused: return "Paused. Open your hand to go on."
        case .zooming: return "Zooming! Hands apart to come closer, together to back away."
        }
    }

    private var symbol: String {
        if hands.problem != nil { return "exclamationmark.triangle.fill" }
        switch hands.state {
        case .noHand: return "hand.raised"
        case .open: return "hand.point.up.left"
        case .pinched: return "hand.pinch.fill"
        case .paused: return "hand.raised.slash"
        case .zooming: return "arrow.up.left.and.arrow.down.right"
        }
    }
}

/// Turns hand control on and off. Matches the round view buttons.
public struct HandToggle: View {
    @ObservedObject private var hands: HandControl
    @State private var hover = false

    public init(hands: HandControl) { self.hands = hands }

    public var body: some View {
        Button { hands.enabled.toggle() } label: {
            Label("Hands", systemImage: hands.enabled ? "hand.raised.fill" : "hand.raised")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .foregroundStyle(hands.enabled ? Theme.onAccent : Theme.ink)
                .background(hands.enabled ? Theme.accent : hover ? Theme.ink.opacity(0.08) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .help("Turn the model with your hand in front of the camera")
        .accessibilityLabel("Hand control")
        .accessibilityValue(hands.enabled ? "On" : "Off")
        .accessibilityAddTraits(hands.enabled ? .isSelected : [])
    }
}

private struct HandSkeleton: View {
    let poses: [HandPose]
    let pinched: Bool

    var body: some View {
        Canvas { ctx, size in
            for pose in poses { draw(pose, in: &ctx, size: size) }
        }
    }

    private func draw(_ pose: HandPose, in ctx: inout GraphicsContext, size: CGSize) {
        func at(_ j: HandJoint) -> CGPoint? {
            pose.points[j].map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        }
        for chain in HandJoint.chains {
            var path = Path()
            for (i, p) in chain.compactMap(at).enumerated() {
                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
            }
            ctx.stroke(path, with: .color(.white.opacity(0.8)), lineWidth: 2)
        }
        for j in HandJoint.allCases {
            guard let p = at(j) else { continue }
            let tip = j == .thumbTip || j == .indexTip
            let r: CGFloat = tip ? 4 : 2.5
            let colour = tip ? (pinched ? Theme.gold : Theme.Overlay.good) : .white
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(colour))
        }
    }
}

/// The camera picture, flipped like a mirror so moving right moves right on screen.
private struct CameraMirror: NSViewRepresentable {
    let layer: CALayer

    func makeNSView(context: Context) -> NSView {
        let v = LayerHost()
        v.hosted = layer
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class LayerHost: NSView {
        var hosted: CALayer? {
            didSet {
                wantsLayer = true
                if let hosted { layer?.addSublayer(hosted) }
            }
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            // Bounds and position, not frame, because the layer carries a flip.
            hosted?.bounds = bounds
            hosted?.position = CGPoint(x: bounds.midX, y: bounds.midY)
            hosted?.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
            CATransaction.commit()
        }
    }
}

extension HandState {
    var isPinched: Bool {
        switch self {
        case .pinched, .zooming: true
        default: false
        }
    }
}
