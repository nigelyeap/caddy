import CoreGraphics
import simd

/// A flat plane: every point p with dot(p - point, normal) == 0. The normal is unit length.
public struct Plane: Equatable, Sendable {
    public var point: SIMD3<Float>
    public var normal: SIMD3<Float>

    public init(point: SIMD3<Float>, normal: SIMD3<Float>) {
        self.point = point
        self.normal = simd_normalize(normal)
    }

    /// Signed distance. Positive on the side the normal points to.
    public func distance(to p: SIMD3<Float>) -> Float { simd_dot(p - point, normal) }

    /// Where a ray meets the plane. Nil when the ray runs parallel or points away from it.
    public func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>) -> SIMD3<Float>? {
        let d = simd_dot(direction, normal)
        guard abs(d) > 1e-6 else { return nil }
        let t = simd_dot(point - origin, normal) / d
        return t >= 0 ? origin + direction * t : nil
    }

    /// The same plane seen from another frame. `m` maps points from the old frame into the new one.
    /// Normals move by the inverse transpose, so this stays right under non-uniform scale too.
    public func applying(_ m: simd_float4x4) -> Plane {
        let p = m * SIMD4(point, 1)
        let inv = m.inverse.transpose
        let n = inv * SIMD4(normal, 0)
        return Plane(point: SIMD3(p.x, p.y, p.z) / p.w, normal: SIMD3(n.x, n.y, n.z))
    }
}

/// The cut a kid draws: a straight stroke on screen becomes a flat slice straight away from the camera.
public enum CutPlane {
    /// The plane holds the camera eye and both stroke points, so on screen it shows as exactly the drawn
    /// line, extended. Pass stroke points already unprojected into the world (any depth works).
    /// Nil when the stroke is too short to give a direction.
    public static func make(eye: SIMD3<Float>, strokeA a: SIMD3<Float>, strokeB b: SIMD3<Float>) -> Plane? {
        let n = simd_cross(a - eye, b - eye)
        guard simd_length(n) > 1e-6 * max(simd_length(a - eye) * simd_length(b - eye), 1e-12) else { return nil }
        return Plane(point: eye, normal: n)
    }
}

/// Turning a part by dragging sideways, in 15 degree steps.
enum TurnSnap {
    static let step = 15.0
    /// Degrees of turn for each point dragged, the same rate the camera turns.
    static let degreesPerPoint = Double(OrbitSCNView.yawPerPoint) * 180 / .pi

    /// The yaw after dragging `draggedPoints` to the right from `start`, snapped and kept in 0..<360.
    /// Dragging right turns the part clockwise seen from above, like the camera.
    static func yaw(from start: Double, draggedPoints: CGFloat) -> Double {
        let raw = start - Double(draggedPoints) * degreesPerPoint
        let snapped = (raw / step).rounded() * step
        let wrapped = snapped.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}

/// A drawn cut line straightened to the nearest 15 degrees about its middle, keeping its length.
enum CutStroke {
    static func snapped(_ a: CGPoint, _ b: CGPoint, step: Double = 15) -> (CGPoint, CGPoint) {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        let half = hypot(dx, dy) / 2
        guard half > 0 else { return (a, b) }
        let s = step * .pi / 180
        let ang = (atan2(dy, dx) / s).rounded() * s
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let ox = CGFloat(cos(ang) * half), oy = CGFloat(sin(ang) * half)
        return (CGPoint(x: mid.x - ox, y: mid.y - oy), CGPoint(x: mid.x + ox, y: mid.y + oy))
    }
}
