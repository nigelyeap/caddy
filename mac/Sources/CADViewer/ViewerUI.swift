import AppKit
import CADShared
import SwiftUI

/// "40 × 40 × 48 mm" with a thing kids know of about the same size.
public struct SizeBadge: View {
    private let sizeMM: SIMD3<Double>?
    private let gridStepMM: Double

    public init(info: MeshInfo?, gridStepMM: Double = 10) {
        self.sizeMM = info?.sizeMM
        self.gridStepMM = gridStepMM
    }

    public var body: some View {
        if let s = sizeMM {
            // One line. The comparison and grid note show on hover and to VoiceOver.
            Label(Self.sizeText(s), systemImage: "ruler")
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .help("Width by depth by height. \(Self.comparison(s)). \(Self.gridHint(gridStepMM)).")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Size. \(Self.spoken(s)) \(Self.comparison(s)).")
        }
    }

    static func mm(_ v: Double) -> String { v >= 10 ? String(Int(v.rounded())) : String(format: "%.1f", v) }

    static func sizeText(_ s: SIMD3<Double>) -> String { "\(mm(s.x)) × \(mm(s.y)) × \(mm(s.z)) mm" }

    static func spoken(_ s: SIMD3<Double>) -> String {
        "\(mm(s.x)) wide, \(mm(s.y)) deep and \(mm(s.z)) tall, in millimetres."
    }

    static func gridHint(_ step: Double) -> String {
        step == 10 ? "Each floor square is 1 cm" : "Each floor square is \(Int(step / 10)) cm"
    }

    /// Things a kid has held, with their longest side in mm.
    private static let things: [(String, Double)] = [
        ("a pea", 8), ("a dice", 16), ("a grape", 25), ("a golf ball", 43), ("an egg", 60),
        ("a bank card", 86), ("a phone", 150), ("a pencil", 190), ("a ruler", 300),
    ]

    /// Picks the closest by ratio, so 40 mm reads "a golf ball" and 300 mm reads "a ruler".
    static func comparison(_ s: SIMD3<Double>) -> String {
        let longest = max(s.x, s.y, s.z)
        if longest < 5 { return "Smaller than a pea" }
        if longest > 450 { return "Bigger than a ruler" }
        let best = things.min { abs(log($0.1 / longest)) < abs(log($1.1 / longest)) }!
        return "About as big as \(best.0)"
    }
}

/// Reset view, see the lines, floor grid, spin, and save a picture.
public struct ViewerToolbar: View {
    @ObservedObject private var controller: ViewerController

    public init(controller: ViewerController) { self.controller = controller }

    public var body: some View {
        HStack(spacing: 2) {
            button("Reset view", "arrow.counterclockwise") { controller.resetView() }
            toggle("Show triangles", "cube.transparent", $controller.showWireframe)
            toggle("Floor grid", "squareshape.split.3x3", $controller.showGrid)
            toggle("Spin", "rotate.3d", $controller.autoRotate)
            button("Save picture", "camera") { _ = try? ModelExport.savePNG(controller.snapshot()) }
        }
        .padding(4)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line))
        .disabled(controller.info == nil)
        .tutorialTarget(.viewerTools)
    }

    private func button(_ title: String, _ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { ToolIcon(name: name, on: false) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
    }

    private func toggle(_ title: String, _ name: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: { ToolIcon(name: name, on: isOn.wrappedValue) }
            .buttonStyle(.plain)
            .help(title)
            .accessibilityLabel(title)
            .accessibilityValue(isOn.wrappedValue ? "On" : "Off")
            .accessibilityAddTraits(isOn.wrappedValue ? .isSelected : [])
    }
}

/// A round view button. Filled with the accent while its toggle is on, a soft wash on hover.
private struct ToolIcon: View {
    let name: String
    let on: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hover = false

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 14, weight: .medium))
            .frame(width: 34, height: 30)
            .foregroundStyle(on ? Theme.onAccent : Theme.ink)
            .background(on ? Theme.accent : hover && enabled ? Theme.ink.opacity(0.08) : .clear, in: Capsule())
            .opacity(enabled ? 1 : 0.4)
            .contentShape(Capsule())
            .onHover { hover = $0 }
    }
}
