import CoreGraphics

/// The 21 hand points Vision finds. The same layout MediaPipe uses.
public enum HandJoint: CaseIterable, Sendable {
    case wrist
    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// The five chains out from the wrist, for drawing the hand.
    public static let chains: [[HandJoint]] = [
        [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip],
        [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip],
        [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip],
    ]
}

/// One hand in one camera frame.
public struct HandPose: Equatable, Sendable {
    /// 0 to 1 across the camera picture, top-left origin, flipped left to right like a mirror.
    public var points: [HandJoint: CGPoint]
    /// Picture width over height, so distances are measured in true proportions.
    public var aspect: CGFloat

    public init(points: [HandJoint: CGPoint], aspect: CGFloat) {
        self.points = points
        self.aspect = aspect
    }

    func distance(_ a: HandJoint, _ b: HandJoint) -> CGFloat? {
        guard let p = points[a], let q = points[b] else { return nil }
        return hypot((p.x - q.x) * aspect, p.y - q.y)
    }

    /// Wrist to middle knuckle. Other distances are divided by it, so small, big, near and far hands act the same.
    var size: CGFloat? { distance(.wrist, .middleMCP).flatMap { $0 > 0.01 ? $0 : nil } }

    /// Thumb tip to index tip over hand size. About 0.1 when touching, 0.8 or more when open.
    public var pinchRatio: CGFloat? {
        guard let s = size, let d = distance(.thumbTip, .indexTip) else { return nil }
        return d / s
    }

    /// Halfway between thumb tip and index tip. It barely moves as the fingers close, so a pinch does not nudge it.
    public var cursor: CGPoint? {
        guard let t = points[.thumbTip], let i = points[.indexTip] else { return nil }
        return CGPoint(x: (t.x + i.x) / 2, y: (t.y + i.y) / 2)
    }

    /// Numbers behind `isTwoFingers`, for the hand log: index, middle, ring, little reach, then tip gap.
    var twoFingerDebug: String {
        func reach(_ tip: HandJoint, _ knuckle: HandJoint) -> String {
            guard let t = distance(.wrist, tip), let k = distance(.wrist, knuckle), k > 0 else { return "-" }
            return String(format: "%.2f", t / k)
        }
        let gap = distance(.indexTip, .middleTip).flatMap { g in size.map { g / $0 } }
        return "reach i=\(reach(.indexTip, .indexMCP)) m=\(reach(.middleTip, .middleMCP)) r=\(reach(.ringTip, .ringMCP)) l=\(reach(.littleTip, .littleMCP)) gap=\(gap.map { String(format: "%.2f", $0) } ?? "-") palmx=\(points[.middleMCP].map { String(format: "%.2f", $0.x) } ?? "-")"
    }

    /// Index and middle fingers up and pressed together, ring and little fingers curled. The tool-switch pose.
    /// A spread "peace" sign does not count, so the switch only happens on purpose.
    public var isTwoFingers: Bool {
        func reach(_ tip: HandJoint, _ knuckle: HandJoint) -> CGFloat? {
            guard let t = distance(.wrist, tip), let k = distance(.wrist, knuckle), k > 0 else { return nil }
            return t / k
        }
        guard let i = reach(.indexTip, .indexMCP), let m = reach(.middleTip, .middleMCP),
              let r = reach(.ringTip, .ringMCP), let l = reach(.littleTip, .littleMCP) else { return false }
        guard let gap = distance(.indexTip, .middleTip), let s = size, gap / s < 0.36 else { return false }
        return i > 1.3 && m > 1.3 && r < 1.25 && l < 1.25
    }

    /// All four fingertips curled back to the palm, no further from the wrist than their knuckles.
    public var isFist: Bool {
        let fingers: [(HandJoint, HandJoint)] = [(.indexTip, .indexMCP), (.middleTip, .middleMCP),
                                                 (.ringTip, .ringMCP), (.littleTip, .littleMCP)]
        for (tip, knuckle) in fingers {
            guard let t = distance(.wrist, tip), let k = distance(.wrist, knuckle), t < k * 1.05 else { return false }
        }
        return true
    }
}
