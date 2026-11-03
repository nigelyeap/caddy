import CADShared
import SwiftUI

// Overlay parts drawn on live video. Colours come from Theme.Overlay and type from themeFont.

// MARK: - Coverage ring

/// 12 segments, clockwise from the top. Each value is 0 to 1.
/// A muted track, filled in one accent colour as each side is covered.
/// Pass `lower` and `upper` when the guidance service sends `coverage.rings` (needs a pose).
public struct CoverageRing: View {
    public var sectors: [Double]
    public var percent: Double
    public var lower: [Double]?
    public var upper: [Double]?
    public var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var textScale

    public init(sectors: [Double], percent: Double, lower: [Double]? = nil, upper: [Double]? = nil, size: CGFloat = 160) {
        self.sectors = sectors
        self.percent = percent
        self.lower = lower
        self.upper = upper
        self.size = size
    }

    private var doneCount: Int { sectors.filter { $0 >= 0.999 }.count }
    private var complete: Bool { percent >= 99.5 }

    public var body: some View {
        let size = self.size * textScale
        let main = size * 0.06
        let band = size * 0.035
        let pad = Theme.Space.xs
        // Radii are to the middle of each stroke. Lower ring outside, upper ring inside, like looking down on a dome.
        let rLower = size / 2 - pad - band / 2
        let rMain = size / 2 - pad - (lower != nil ? band + Theme.Space.xxs : 0) - main / 2
        let rUpper = rMain - main / 2 - Theme.Space.xxs - band / 2
        let inner = (upper != nil ? rUpper - band / 2 : rMain - main / 2) * 2

        VStack(spacing: Theme.Space.xs) {
            ZStack {
                Circle().fill(Theme.Overlay.backing)
                if let lower { Track(values: lower, radius: rLower, width: band) }
                Track(values: sectors, radius: rMain, width: main)
                if let upper { Track(values: upper, radius: rUpper, width: band) }
                VStack(spacing: 2) {
                    // The seal and the words say "done", so the finish never rests on the green alone.
                    if complete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: size * 0.16, weight: .semibold))
                            .foregroundStyle(Theme.Overlay.good)
                    }
                    Text("\(Int(percent.rounded()))%")
                        .monospacedDigit()
                        .themeFont(.heading)
                        .foregroundStyle(Theme.Overlay.text)
                        .contentTransition(.numericText(value: percent))
                    Text(complete ? "all done" : "done")
                        .themeFont(.caption)
                        .foregroundStyle(Theme.Overlay.text.opacity(0.8))
                }
                .frame(width: inner * 0.85)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                // A soft one-time sparkle when every side is done. Never with Reduce Motion.
                if complete && !reduceMotion { Sparkles(size: size) }
            }
            .frame(width: size, height: size)
            Text(cheer)
                .themeFont(.secondary)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Overlay.text)
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, Theme.Space.xxs)
                .background(Capsule().fill(Theme.Overlay.backing))
                .id(cheer)
                .transition(.opacity)
        }
        .animation(Theme.motion(reduceMotion), value: sectors)
        .animation(Theme.motion(reduceMotion), value: percent)
        .animation(Theme.motion(reduceMotion), value: cheer)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(percent.rounded())) percent done. \(doneCount) of 12 sides. \(cheer).")
    }

    /// A short cheer under the ring that grows with the scan.
    private var cheer: String {
        switch percent {
        case _ where complete: "Every side!"
        case ..<25: "Good start"
        case ..<50: "Keep going"
        case ..<80: "Over halfway"
        default: "Nearly there"
        }
    }

    /// Little stars that float out once and fade. Shown only when motion is allowed.
    private struct Sparkles: View {
        let size: CGFloat
        @State private var go = false
        var body: some View {
            ZStack {
                ForEach(0..<8, id: \.self) { i in
                    let a = Double(i) / 8 * 2 * .pi - .pi / 8
                    let r = size * (go ? 0.58 : 0.38)
                    Image(systemName: i.isMultiple(of: 2) ? "sparkle" : "star.fill")
                        .font(.system(size: size * (i.isMultiple(of: 2) ? 0.1 : 0.07)))
                        .foregroundStyle(i.isMultiple(of: 2) ? Theme.Overlay.warning : Theme.Overlay.good)
                        .offset(x: cos(a) * r, y: sin(a) * r)
                        .scaleEffect(go ? 1.1 : 0.4)
                        .opacity(go ? 0 : 1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onAppear { withAnimation(.easeOut(duration: 1.4)) { go = true } }
        }
    }

    /// One ring of 12 segments with small clear gaps.
    private struct Track: View {
        let values: [Double]
        let radius: CGFloat
        let width: CGFloat

        var body: some View {
            let gapDeg = Double(3 / radius) * 180 / .pi
            ZStack {
                ForEach(0..<12, id: \.self) { i in
                    let v = min(1, max(0, i < values.count ? values[i] : 0))
                    let start = Double(i) * 30 + gapDeg / 2
                    let span = 30 - gapDeg
                    SegmentArc(start: start, span: span, fill: 1, radius: radius)
                        .stroke(Theme.Overlay.text.opacity(0.18), lineWidth: width)
                    SegmentArc(start: start, span: span, fill: v, radius: radius)
                        .stroke(Theme.Overlay.good, lineWidth: width)
                }
            }
        }
    }
}

/// Part of a ring segment. `start` and `span` are degrees clockwise from the top.
/// `fill` animates, so a segment grows along the ring.
struct SegmentArc: Shape {
    var start: Double
    var span: Double
    var fill: Double
    var radius: CGFloat

    var animatableData: Double {
        get { fill }
        set { fill = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard fill > 0.001 else { return p }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        p.addArc(center: c, radius: radius, startAngle: .degrees(start - 90),
                 endAngle: .degrees(start - 90 + span * min(1, fill)), clockwise: false)
        return p
    }
}

// MARK: - Status chip

/// A small capsule with a symbol and a word. Colour is never the only signal.
public struct StatusChip: View {
    public var word: String
    public var level: ChipLevel

    public init(_ word: String, level: ChipLevel) {
        self.word = word
        self.level = level
    }

    private var tint: Color {
        switch level {
        case .good: return Theme.Overlay.good
        case .bad: return Theme.Overlay.bad
        case .neutral: return Theme.Overlay.text.opacity(0.6)
        }
    }

    private var symbol: String {
        switch level {
        case .good: return "checkmark.circle.fill"
        case .bad: return "exclamationmark.circle.fill"
        case .neutral: return "minus.circle"
        }
    }

    public var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(word).foregroundStyle(Theme.Overlay.text)
        }
        .themeFont(.secondary)
        .fontWeight(.medium)
        .padding(.horizontal, Theme.Space.s)
        .padding(.vertical, Theme.Space.xxs + 2)
        .background(Capsule().fill(Theme.Overlay.backing))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level == .neutral ? "\(word), not checked" : word)
    }
}

// MARK: - Warning bar

/// The main message under the video: a problem to fix, progress, or a note that checks stopped.
public struct WarningBar: View {
    public var message: OverlayMessage

    public init(_ message: OverlayMessage) { self.message = message }

    private var tint: Color {
        switch message.tone {
        case .warning: return Theme.Overlay.warning
        case .good, .done: return Theme.Overlay.good
        case .neutral: return Theme.Overlay.text.opacity(0.7)
        }
    }

    private var symbol: String {
        switch message.tone {
        case .warning: return "exclamationmark.triangle.fill"
        case .good: return "checkmark.circle.fill"
        case .done: return "checkmark.seal.fill"
        case .neutral: return "wifi.exclamationmark"
        }
    }

    public var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(message.text)
                .foregroundStyle(Theme.Overlay.text)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .themeFont(.body)
        .fontWeight(.medium)
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.s)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.Overlay.backing))
        // A soft edge in the tone colour. The icon and the words carry the meaning.
        .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
            .strokeBorder(tint.opacity(message.tone == .neutral ? 0 : 0.6), lineWidth: 1.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - REC badge

struct RecBadge: View {
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: start, by: 0.5)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(start)
            let dotOn = reduceMotion || Int(elapsed * 2) % 2 == 0
            HStack(spacing: Theme.Space.xs) {
                Circle().fill(Theme.Overlay.bad).frame(width: 10, height: 10).opacity(dotOn ? 1 : 0.3)
                Text("Filming")
                Text(RecClock.format(elapsed)).monospacedDigit()
            }
            .themeFont(.secondary)
            .fontWeight(.medium)
            .foregroundStyle(Theme.Overlay.text)
            .padding(.horizontal, Theme.Space.s)
            .padding(.vertical, Theme.Space.xxs + 2)
            .background(Capsule().fill(Theme.Overlay.backing))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Filming, \(Int(elapsed)) seconds")
        }
    }
}

// MARK: - Coach card

struct CoachCard: View {
    @Environment(\.textScale) private var scale
    private let steps = [
        "Put your object in the middle of a table.",
        "Walk slowly all the way around it.",
        "Press Start scan. Press Finish scan when you're done.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text("Ready? Here's how").themeFont(.heading)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.xs) {
                    Text("\(i + 1)")
                        .monospacedDigit()
                        .themeFont(.secondary).fontWeight(.semibold)
                        .frame(width: 20 * scale, height: 20 * scale)
                        .background(Circle().fill(Theme.Overlay.text.opacity(0.16)))
                    Text(step).themeFont(.body)
                }
            }
            Text("Things that are not shiny work best. Shiny or see-through things are hard to scan.")
                .themeFont(.secondary)
                .foregroundStyle(Theme.Overlay.text.opacity(0.8))
                .padding(.top, Theme.Space.xxs)
        }
        .foregroundStyle(Theme.Overlay.text)
        .padding(Theme.Space.m)
        .background(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).fill(Theme.Overlay.backing))
        .accessibilityElement(children: .combine)
    }
}
