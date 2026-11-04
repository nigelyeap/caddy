import SwiftUI
import CADShared

/// A row of shapes a hand can pinch and carry onto the floor. Points are stage points, top-left origin.
enum HandPalette {
    static let shapes = Array(AddShelf.shapes.prefix(5))
    static let tile: CGFloat = 52
    static let gap: CGFloat = 10

    /// Tile centres: one row in the middle, a little above the view buttons.
    static func centres(in size: CGSize) -> [CGPoint] {
        let row = CGFloat(shapes.count) * tile + CGFloat(shapes.count - 1) * gap
        let y = size.height - 110
        return shapes.indices.map { i in
            CGPoint(x: (size.width - row) / 2 + tile / 2 + CGFloat(i) * (tile + gap), y: y)
        }
    }

    /// The shape under a stage fraction, if any.
    static func shape(at fraction: CGPoint, in size: CGSize) -> String? {
        let p = CGPoint(x: fraction.x * size.width, y: fraction.y * size.height)
        let half = tile / 2 + gap / 2
        return zip(shapes, centres(in: size)).first { abs($0.1.x - p.x) <= half && abs($0.1.y - p.y) <= half }?.0.name
    }
}

/// Where the hands go first. A pinch on a palette tile carries a shape. Everything else goes to the
/// viewer, which acts through the current tool. A held pinch confirms a drawn cut.
@MainActor
final class HandStage: ObservableObject {
    struct Carry: Equatable { var shape: String; var point: CGPoint }

    weak var model: AppModel?
    @Published private(set) var carrying: Carry?
    /// The stage size in points and whether the palette shows. The palette view keeps these current.
    var size: CGSize = .zero
    var paletteShown = false

    private var viewer: ViewerControl? { model?.viewer }

    func handDragBegan(at p: CGPoint) {
        if paletteShown, let s = HandPalette.shape(at: p, in: size) {
            carrying = Carry(shape: s, point: p)
        } else {
            viewer?.handDragBegan(at: p)
        }
    }

    func handDragged(to p: CGPoint, by fraction: CGVector) {
        if carrying != nil { carrying?.point = p } else { viewer?.handDragged(to: p, by: fraction) }
    }

    func handDragEnded() {
        guard let c = carrying else { viewer?.handDragEnded(); return }
        carrying = nil
        // Let go back over the palette: nothing added.
        guard HandPalette.shape(at: c.point, in: size) == nil, let model, let spot = model.viewer.floorSpot(at: c.point) else { return }
        Task { await model.add(c.shape, at: spot) }
    }

    func handZoomed(by factor: CGFloat) { viewer?.handZoomed(by: factor) }

    func handSwiped(_ direction: Int) { model?.cycleTool(direction) }

    func handHeld() {
        guard let model else { return }
        Task { await model.confirmCut() }
    }
}

/// The hand palette and the shape being carried. Shown only while hands are on and parts can change.
struct HandPaletteView: View {
    @ObservedObject var stage: HandStage
    @ObservedObject var hands: HandControls
    let shown: Bool

    var body: some View {
        GeometryReader { g in
            let on = shown && hands.enabled
            ZStack {
                if on {
                    let over = hands.state.point.flatMap { HandPalette.shape(at: $0, in: g.size) }
                    ForEach(Array(zip(HandPalette.shapes, HandPalette.centres(in: g.size))), id: \.0.name) { s, c in
                        tile(s.symbol, lit: over == s.name || stage.carrying?.shape == s.name)
                            .position(c)
                    }
                    if let c = stage.carrying, let s = HandPalette.shapes.first(where: { $0.name == c.shape }) {
                        tile(s.symbol, lit: true)
                            .opacity(0.8)
                            .position(x: c.point.x * g.size.width, y: c.point.y * g.size.height)
                    }
                }
            }
            .onAppear { stage.size = g.size; stage.paletteShown = on }
            .onChange(of: g.size) { _, s in stage.size = s }
            .onChange(of: on) { _, v in stage.paletteShown = v }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tile(_ symbol: String, lit: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Theme.tintAdd.ink)
            .frame(width: HandPalette.tile, height: HandPalette.tile)
            .background(Theme.tintAdd.fill, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .strokeBorder(lit ? Theme.gold : Theme.tintAdd.edge, lineWidth: lit ? 3 : 1))
    }
}
