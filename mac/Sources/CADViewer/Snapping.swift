import simd

/// A part's footprint on the floor: scene x and z, in mm.
struct SnapBox: Equatable {
    var min: SIMD2<Float>
    var max: SIMD2<Float>

    /// The low edge, the centre and the high edge along one axis.
    func marks(_ axis: Int) -> [Float] { [min[axis], (min[axis] + max[axis]) / 2, max[axis]] }
}

/// Lines up a dragged part with the others. Pure, so it is easy to test.
enum SnapSolver {
    /// The bed's two centre lines, as flat boxes. Their ends also line up with the bed edges.
    static let bedLines = [
        SnapBox(min: SIMD2(0, -ViewerScene.bedHalf), max: SIMD2(0, ViewerScene.bedHalf)),
        SnapBox(min: SIMD2(-ViewerScene.bedHalf, 0), max: SIMD2(ViewerScene.bedHalf, 0)),
    ]

    /// How far to nudge `moving` on each axis so an edge or centre lines up with an edge or centre of
    /// another box. Edge to opposite edge is the flush case. Nil means that axis did not snap.
    /// Each guide is a floor line from one point to another, showing what lined up.
    static func snap(moving m: SnapBox, others: [SnapBox], threshold: Float = 3)
        -> (dx: Float?, dy: Float?, guides: [(from: SIMD2<Float>, to: SIMD2<Float>)]) {
        func best(_ axis: Int) -> (d: Float, target: SnapBox, at: Float)? {
            var out: (d: Float, target: SnapBox, at: Float)?
            for o in others {
                for a in m.marks(axis) {
                    for b in o.marks(axis) where abs(b - a) <= threshold && abs(b - a) < abs(out?.d ?? .infinity) {
                        out = (b - a, o, b)
                    }
                }
            }
            return out
        }
        let bx = best(0), by = best(1)
        let moved = SnapBox(min: m.min + SIMD2(bx?.d ?? 0, by?.d ?? 0), max: m.max + SIMD2(bx?.d ?? 0, by?.d ?? 0))
        var guides: [(from: SIMD2<Float>, to: SIMD2<Float>)] = []
        // The line runs along the other axis, from the far end of one box to the far end of the other.
        if let bx {
            guides.append((SIMD2(bx.at, Swift.min(moved.min.y, bx.target.min.y)), SIMD2(bx.at, Swift.max(moved.max.y, bx.target.max.y))))
        }
        if let by {
            guides.append((SIMD2(Swift.min(moved.min.x, by.target.min.x), by.at), SIMD2(Swift.max(moved.max.x, by.target.max.x), by.at)))
        }
        return (bx?.d, by?.d, guides)
    }
}

/// The three size tags of a box: width (x), depth and height. Scene is y up, so depth is z.
enum SizeTags {
    /// Value in mm and where the tag sits, for a world box from `lo` to `hi`.
    static func tags(lo: SIMD3<Float>, hi: SIMD3<Float>) -> [(mm: Float, at: SIMD3<Float>)] {
        let c = (lo + hi) / 2
        return [
            (hi.x - lo.x, SIMD3(c.x, lo.y, hi.z)),   // along the front bottom edge
            (hi.z - lo.z, SIMD3(hi.x, lo.y, c.z)),   // along the right bottom edge
            (hi.y - lo.y, SIMD3(hi.x, c.y, hi.z)),   // up the front right edge
        ]
    }

    /// "40 mm" or "12.5 mm". One decimal at most.
    static func text(_ mm: Float) -> String {
        let r = (mm * 10).rounded() / 10
        return r == r.rounded() ? "\(Int(r)) mm" : String(format: "%.1f mm", r)
    }
}
