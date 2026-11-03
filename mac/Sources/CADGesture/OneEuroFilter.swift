import Foundation

/// Smooths a jittery signal without making fast moves lag. Slow moves get heavy smoothing, fast moves light.
/// Casiez, Roussel and Vogel, "1€ Filter", CHI 2012. Values here are stage fractions, so beta is large.
struct OneEuroFilter {
    /// Cutoff in Hz when the hand is still. Lower is smoother but slower.
    var minCutoff = 1.5
    /// How fast the cutoff rises with speed. Higher follows quick moves more tightly.
    var beta = 5.0
    var derivativeCutoff = 1.0

    private var value: Double?
    private var speed = 0.0
    private var time: TimeInterval?

    init(minCutoff: Double = 1.5, beta: Double = 5.0) {
        self.minCutoff = minCutoff
        self.beta = beta
    }

    mutating func filter(_ x: Double, at t: TimeInterval) -> Double {
        guard let last = value, let lastTime = time, t > lastTime else {
            value = x; time = t
            return x
        }
        let dt = t - lastTime
        let a = Self.alpha(dt: dt, cutoff: derivativeCutoff)
        speed = a * ((x - last) / dt) + (1 - a) * speed
        let b = Self.alpha(dt: dt, cutoff: minCutoff + beta * abs(speed))
        let out = b * x + (1 - b) * last
        value = out; time = t
        return out
    }

    mutating func reset() { value = nil; speed = 0; time = nil }

    private static func alpha(dt: TimeInterval, cutoff: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        return 1 / (1 + tau / dt)
    }
}
