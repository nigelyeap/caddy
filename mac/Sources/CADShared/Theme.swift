import SwiftUI
import AppKit

// TOKEN LIST (read this before styling a screen)
//
// Look: calm and warm. Warm neutral surfaces, one blue accent, four soft tints used sparingly,
// round shapes, SF Rounded type, gentle depth. Every text pair below passes 4.5:1 in light and dark.
//
// Colour
//   Theme.accent, onAccent          the one accent (Caddy goggle blue) and the text on it
//   Theme.accentSoft, accentInk     a pale accent wash and the accent colour for text on panels
//   Theme.good, warn, bad           status. Always pair with an icon or words, never colour alone
//   Theme.badFill                   a red fill that keeps white text readable in dark mode too
//   Theme.background, panel, raised surfaces, back to front
//   Theme.ink, muted, line          text, secondary text, hairlines
//   Theme.shadow                    the soft card shadow colour
//   Theme.viewer, stageTop, stageBottom, focus, Overlay.*   unchanged
//
// Soft tints (Theme.Tint has .fill for backgrounds, .ink for icons and text on that fill, .edge for borders)
//   Theme.tintSize (sky), tintAdd (mint), tintCut (apricot), tintWords (lilac), tintSun (butter, for
//   praise and the mascot's moments), tintAccent (the accent as a tint)
//   Theme.tint(forGroup:) maps an Ideas group name ("Size", "Add", "Cut", "Words" and the extra groups)
//   Use one tint per group. Tints mark a group or a moment, they never carry meaning on their own.
//
// Shape and size
//   corner 18 (cards), cornerLarge 24 (big panels, sheets), buttonCorner 10 (buttons, fields, rows)
//   chips are capsules. bigButtonHeight 38, minHit 32, chipHeight 28
//
// Type: .themeFont(role). Roles: display (28), title, heading, body, button, bigButton, overlay, chip,
//   secondary, caption, mono. All SF Rounded except mono. Theme.rounded(size, weight) for one-off sizes.
//
// Views and styles
//   .card(padding:tint:)           panel with hairline and soft shadow, optional tint fill
//   .chip(tint:)                   a small static capsule label (a badge, not a button)
//   BigButtonStyle(.primary/.secondary/.destructive, compact:)
//   ChipButtonStyle(tint:)         tinted capsule chip button, tint optional
//   FriendlyProgressStyle(tint:)   rounded capsule bar for determinate progress
//
// Motion: Theme.motion(reduceMotion) for state changes, Theme.spring(reduceMotion) for small playful moves.
// Read accessibilityReduceMotion and accessibilityReduceTransparency and pass them in.

/// Design tokens. Do not rename existing tokens, other targets use them.
public enum Theme {
    // MARK: Colour. Each token has a light and a dark value.
    /// The one accent: a calm friendly blue taken from Caddy's goggles. The window root sets it as the
    /// SwiftUI tint, so native controls match.
    public static let accent = dynamic(0x2E63CF, 0x3D6FD9)
    public static let onAccent = Color.white
    /// The main button: warm gold with dark text (dark theme only look).
    public static let gold = hex(0xF2C94C)
    public static let goldEdge = hex(0xB8941F)
    public static let onGold = hex(0x2B2200)
    /// A pale accent wash for selected rows and soft highlights.
    public static let accentSoft = dynamic(0xE4ECFB, 0x26324A)
    /// The accent as a text colour on panels and on `accentSoft`.
    public static let accentInk = dynamic(0x2556B8, 0xA9C4FF)
    public static let good = dynamic(0x2C7A47, 0x5DBB7A)
    public static let warn = dynamic(0x8F6210, 0xD9A441)
    public static let bad = dynamic(0xB0352B, 0xF47A6F)
    /// Fill for destructive buttons. `bad` is too light in dark mode to carry white text.
    public static let badFill = dynamic(0xB0352B, 0xC0392F)
    public static let background = dynamic(0xFDFBF3, 0x1E1D1A)
    /// Soft butter strip behind the window toolbar.
    public static let header = dynamic(0xF8E9A8, 0x2B2819)
    public static let panel = dynamic(0xFFFFFF, 0x2A2824)
    public static let raised = dynamic(0xFBF6E2, 0x33312B)   // fields and wells inside a panel
    public static let ink = dynamic(0x23211F, 0xEDEAE6)
    public static let muted = dynamic(0x67625C, 0xA7A29C)
    public static let line = dynamic(0xEDE6CC, 0x3F3B2C)
    public static let shadow = Color(nsColor: NSColor(name: nil) { a in
        a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .black.withAlphaComponent(0.35) : nsHex(0x5A4630, 0.10)
    })
    public static let viewer = dynamic(0xECECEE, 0x19191B)
    /// The 3D stage backdrop fades from `stageTop` to `stageBottom`. The grid and shadow sit on `stageBottom`.
    public static let stageTop = dynamic(0xF6F6F8, 0x34363D)
    public static let stageBottom = dynamic(0xDCDCE0, 0x26282D)
    public static let focus = Color(nsColor: .keyboardFocusIndicatorColor)

    /// Overlay colours sit on live video, so they stay the same in both themes.
    public enum Overlay {
        public static let backing = Color.black.opacity(0.72)
        public static let text = Color.white
        public static let warning = hex(0xFFD36B)
        public static let good = hex(0x5DBB7A)
        public static let bad = hex(0xF0675B)
        public static let ringPartial = hex(0xD9A441)
    }

    // MARK: Soft tints
    /// A soft group colour. `fill` is a background, `ink` is for icons and text on that fill, `edge` is a border.
    public struct Tint: Sendable {
        public let fill: Color, ink: Color, edge: Color
        init(fill: (UInt32, UInt32), ink: (UInt32, UInt32), edge: (UInt32, UInt32)) {
            self.fill = Theme.dynamic(fill.0, fill.1)
            self.ink = Theme.dynamic(ink.0, ink.1)
            self.edge = Theme.dynamic(edge.0, edge.1)
        }
    }
    public static let tintSize = Tint(fill: (0xE4EEFB, 0x22314A), ink: (0x2556B0, 0xA9C8FF), edge: (0xC6D8F4, 0x34496B))
    public static let tintAdd = Tint(fill: (0xE0F3EA, 0x1F3A2E), ink: (0x22704A, 0x8FD9B1), edge: (0xBFE3D0, 0x2F5744))
    public static let tintCut = Tint(fill: (0xFCEBDD, 0x45301F), ink: (0x9A4A12, 0xF7BE8F), edge: (0xF2D2B8, 0x664630))
    public static let tintWords = Tint(fill: (0xEEE8FA, 0x352C4A), ink: (0x5B41A8, 0xCDBBFF), edge: (0xD8CDF2, 0x4D416B))
    public static let tintSun = Tint(fill: (0xFDF3D6, 0x3F3519), ink: (0x7F5B00, 0xF2D27A), edge: (0xF1DFA6, 0x5E5027))
    public static let tintAccent = Tint(fill: (0xE4ECFB, 0x26324A), ink: (0x2556B8, 0xA9C4FF), edge: (0xC6D6F4, 0x384B70))

    /// The tint for an Ideas group. Unknown groups get the accent tint.
    public static func tint(forGroup group: String) -> Tint {
        switch group {
        case "Size", "Reshape": tintSize
        case "Add", "Add parts", "Holders and stands": tintAdd
        case "Cut": tintCut
        case "Words", "Patterns": tintWords
        default: tintAccent
        }
    }

    // MARK: Shape and space
    public static let corner: CGFloat = 18          // panels and cards
    public static let cornerLarge: CGFloat = 24     // big panels and sheets
    public static let buttonCorner: CGFloat = 10    // buttons, fields, rows
    public static let gap: CGFloat = 12
    public static let screenMargin: CGFloat = 20
    public static let panelPadding: CGFloat = 16
    public static let bigButtonHeight: CGFloat = 38
    public static let minHit: CGFloat = 32
    public static let chipHeight: CGFloat = 28

    /// Spacing steps: 4, 8, 12, 16, 24, 32, 48.
    public enum Space {
        public static let xxs: CGFloat = 4, xs: CGFloat = 8, s: CGFloat = 12, m: CGFloat = 16
        public static let l: CGFloat = 24, xl: CGFloat = 32, xxl: CGFloat = 48
    }

    // MARK: Motion. Pass reduceMotion to turn it off.
    public static let motion = Animation.easeOut(duration: 0.18)
    public static func motion(_ reduceMotion: Bool) -> Animation? { reduceMotion ? nil : motion }
    /// A soft spring with a little bounce, for presses and small arrivals.
    public static func spring(_ reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.72)
    }

    // MARK: Helpers
    /// SF Rounded at a fixed size, for one-off display text. Prefer `.themeFont` so text size applies.
    public static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    public static func hex(_ v: UInt32, _ alpha: Double = 1) -> Color {
        Color(nsColor: nsHex(v, alpha))
    }
    public static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? nsHex(dark) : nsHex(light)
        })
    }
    static func nsHex(_ v: UInt32, _ alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
    }
}

// MARK: - Type scale

/// Text roles. SF Rounded, mono stays SF Mono. Sizes are at the Default text size.
public enum TextRole: Sendable {
    case display, title, heading, body, button, bigButton, overlay, chip, secondary, caption, mono

    var size: CGFloat {
        switch self {
        case .display: 28
        case .title: 21
        case .overlay: 17
        case .bigButton: 14
        case .heading, .body, .button: 13
        case .chip, .secondary: 12
        case .caption, .mono: 11
        }
    }
    var weight: Font.Weight {
        switch self {
        case .display, .title, .heading, .overlay, .bigButton: .semibold
        case .button, .chip: .medium
        default: .regular
        }
    }
    var design: Font.Design { self == .mono ? .monospaced : .rounded }
}

/// The text size setting. Raw values stay the same so saved settings carry over.
public enum TextSize: String, CaseIterable, Identifiable, Sendable {
    case large, larger, largest
    public var id: String { rawValue }
    public var scale: CGFloat { switch self { case .large: 1; case .larger: 1.2; case .largest: 1.4 } }
    public var label: String { switch self { case .large: "Default"; case .larger: "Large"; case .largest: "Extra large" } }
}

private struct TextScaleKey: EnvironmentKey { static let defaultValue: CGFloat = 1 }
public extension EnvironmentValues {
    /// Multiplies every themed font. Set once at the window root from the Text size menu.
    var textScale: CGFloat {
        get { self[TextScaleKey.self] }
        set { self[TextScaleKey.self] = newValue }
    }
}

private struct ThemedFont: ViewModifier {
    let role: TextRole
    @Environment(\.textScale) private var scale
    func body(content: Content) -> some View {
        content.font(.system(size: (role.size * scale).rounded(), weight: role.weight, design: role.design))
    }
}

private struct CardModifier: ViewModifier {
    let padding: CGFloat
    let tint: Theme.Tint?
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        content.padding(padding)
            .background(tint?.fill ?? Theme.panel, in: shape)
            .overlay(shape.strokeBorder(tint?.edge ?? Theme.line, lineWidth: 1))
            .shadow(color: Theme.shadow, radius: 10, x: 0, y: 3)
    }
}

public extension View {
    /// Use a role from the type scale. It follows the Text size setting.
    func themeFont(_ role: TextRole) -> some View { modifier(ThemedFont(role: role)) }

    /// A panel: solid fill, hairline border, round corners, a soft shadow. Pass a tint for a soft coloured card.
    func card(padding: CGFloat = Theme.panelPadding, tint: Theme.Tint? = nil) -> some View {
        modifier(CardModifier(padding: padding, tint: tint))
    }

    /// A small static capsule label, such as a count or a badge. Not a button.
    func chip(tint: Theme.Tint = Theme.tintAccent) -> some View {
        self.themeFont(.chip)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .foregroundStyle(tint.ink)
            .background(tint.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(tint.edge, lineWidth: 1))
    }
}

// MARK: - Buttons

/// Push buttons. Use `.primary` for at most one button per screen.
public struct BigButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary, destructive }
    let kind: Kind
    let compact: Bool
    public init(_ kind: Kind = .primary, compact: Bool = false) { self.kind = kind; self.compact = compact }

    public func makeBody(configuration: Configuration) -> some View {
        BigButtonBody(configuration: configuration, kind: kind, compact: compact)
    }

    private struct BigButtonBody: View {
        let configuration: Configuration
        let kind: Kind
        let compact: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.textScale) private var scale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
            let pressed = configuration.isPressed && enabled
            // The gold button sits on a solid darker edge and sinks onto it when pressed, like a toy key.
            // The edge is its own shape, so the label is never doubled the way a shadow would double it.
            let chunky = kind == .primary && enabled
            let depth: CGFloat = chunky ? 4 : 0
            let sink: CGFloat = pressed && !reduceMotion ? min(depth, 3) : 0
            configuration.label
                .themeFont(compact ? .button : .bigButton)
                .fontWeight(kind == .primary ? .bold : nil)
                .lineLimit(1)
                .padding(.horizontal, compact ? 12 : 18)
                .frame(minHeight: (compact ? Theme.minHit : Theme.bigButtonHeight) * scale)
                .foregroundStyle(foreground)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(kind == .secondary || !enabled ? Theme.line : .clear, lineWidth: 1))
                .overlay(shape.fill(Theme.ink.opacity(pressed ? 0.12 : hover && enabled ? 0.06 : 0)))
                .offset(y: sink)
                .background(shape.fill(Theme.goldEdge).offset(y: depth).opacity(chunky ? 1 : 0))
                .padding(.bottom, depth)
                .scaleEffect(pressed && !reduceMotion && !chunky ? 0.97 : 1)
                .animation(Theme.spring(reduceMotion), value: pressed)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hover = $0 }
        }
        var fill: Color {
            switch kind {
            // A resting main button goes quiet, so a screen never shows two gold buttons at once.
            case .primary: enabled ? Theme.gold : Theme.raised
            case .destructive: Theme.badFill
            case .secondary: Theme.panel
            }
        }
        var foreground: Color { kind == .secondary ? Theme.ink : kind == .primary ? (enabled ? Theme.onGold : Theme.ink) : Theme.onAccent }
    }
}

/// A small capsule button for quick actions in a row. With a tint it gets a soft group colour,
/// without one it stays quiet: raised fill and a hairline.
public struct ChipButtonStyle: ButtonStyle {
    let tint: Theme.Tint?
    public init(tint: Theme.Tint? = nil) { self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View { ChipBody(configuration: configuration, tint: tint) }
    private struct ChipBody: View {
        let configuration: Configuration
        let tint: Theme.Tint?
        @Environment(\.isEnabled) private var enabled
        @Environment(\.textScale) private var scale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false
        var body: some View {
            let pressed = configuration.isPressed && enabled
            configuration.label
                .themeFont(.chip)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: Theme.chipHeight * scale)
                // Text stays ink so it reads the same in every group. A Label's icon picks up the tint.
                .labelStyle(TintedIconLabel(icon: tint?.ink ?? Theme.muted))
                .foregroundStyle(Theme.ink)
                .background(tint?.fill ?? Theme.raised, in: Capsule())
                .overlay(Capsule().strokeBorder(tint?.edge ?? Theme.line, lineWidth: 1))
                .overlay(Capsule().fill(Theme.ink.opacity(pressed ? 0.12 : hover && enabled ? 0.06 : 0)))
                .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
                .animation(Theme.spring(reduceMotion), value: pressed)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(Capsule())
                .onHover { hover = $0 }
        }
    }
}

/// A big rounded tile: icon on top, short word below, with a solid darker edge like a toy button.
public struct TileButtonStyle: ButtonStyle {
    let tint: Theme.Tint
    public init(tint: Theme.Tint) { self.tint = tint }
    public func makeBody(configuration: Configuration) -> some View { TileBody(configuration: configuration, tint: tint) }
    private struct TileBody: View {
        let configuration: Configuration
        let tint: Theme.Tint
        @Environment(\.isEnabled) private var enabled
        @Environment(\.textScale) private var scale
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false
        var body: some View {
            let pressed = configuration.isPressed && enabled
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            let depth: CGFloat = 4
            // Face uses the tint's brighter edge colour, the toy edge underneath uses its darker fill.
            configuration.label
                .labelStyle(TileLabel(ink: tint.ink))
                .frame(maxWidth: .infinity, minHeight: 74 * scale)
                .padding(.vertical, 6).padding(.horizontal, 6)
                .background(tint.edge, in: shape)
                .overlay(shape.strokeBorder(Color.white.opacity(hover && enabled ? 0.22 : 0.08), lineWidth: 1))
                .offset(y: pressed && !reduceMotion ? 2 : 0)
                .background(shape.fill(tint.fill).overlay(shape.fill(Color.black.opacity(0.25))).offset(y: depth))
                .padding(.bottom, depth)
                .animation(Theme.spring(reduceMotion), value: pressed)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hover = $0 }
        }
    }
}

private struct TileLabel: LabelStyle {
    let ink: Color
    @Environment(\.textScale) private var scale
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 6) {
            configuration.icon.font(.system(size: 26 * scale, weight: .semibold)).foregroundStyle(ink)
            configuration.title.themeFont(.button).fontWeight(.semibold).foregroundStyle(ink)
                .lineLimit(2).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct TintedIconLabel: LabelStyle {
    let icon: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.foregroundStyle(icon)
            configuration.title
        }
    }
}

// MARK: - Progress

/// A rounded capsule bar for determinate progress. Indeterminate progress falls back to the system spinner.
public struct FriendlyProgressStyle: ProgressViewStyle {
    let tint: Color
    let height: CGFloat
    public init(tint: Color = Theme.accent, height: CGFloat = 8) { self.tint = tint; self.height = height }
    public func makeBody(configuration: Configuration) -> some View {
        ProgressBody(configuration: configuration, tint: tint, height: height)
    }
    private struct ProgressBody: View {
        let configuration: Configuration
        let tint: Color
        let height: CGFloat
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        var body: some View {
            if let f = configuration.fractionCompleted {
                VStack(alignment: .leading, spacing: 6) {
                    configuration.label
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.raised)
                            Capsule().strokeBorder(Theme.line, lineWidth: 1)
                            // Never thinner than a dot, so a start reads as started.
                            Capsule().fill(tint).frame(width: max(height, geo.size.width * min(max(f, 0), 1)))
                        }
                    }
                    .frame(height: height)
                    .animation(Theme.motion(reduceMotion), value: f)
                    configuration.currentValueLabel
                }
            } else {
                ProgressView(configuration).progressViewStyle(.circular).tint(tint)
            }
        }
    }
}
