import CoreGraphics
import Foundation

/// What the hand is doing now. Points are fractions of the stage, top-left origin.
public enum HandState: Equatable, Sendable {
    case noHand
    /// Open hand. The cursor follows and nothing changes.
    case open(CGPoint)
    /// Thumb and index touching. Acts like a held mouse button.
    case pinched(CGPoint)
    /// A fist. Hand control ignores the hand so the kid can rest or talk.
    case paused(CGPoint)
    /// Both hands pinching. Pulling them apart moves closer.
    case zooming(CGPoint, CGPoint)

    public var point: CGPoint? {
        switch self {
        case .noHand: nil
        case .open(let p), .pinched(let p), .paused(let p): p
        case .zooming(let a, let b): CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
    }
}

/// A pinch acts like a mouse: down, drag, up.
public enum HandEvent: Equatable, Sendable {
    case pinchBegan(CGPoint)
    /// How far the cursor moved since the last event, in stage fractions. Right and down are positive.
    case pinchMoved(CGVector)
    case pinchEnded
    /// The pinch stayed still for `holdTime` since it began. Fires once, like pressing a button to confirm.
    case pinchHeld
    /// Change in the gap between two pinching hands since the last event. Above 1 moves closer.
    case zoomed(CGFloat)
    /// Two fingers up and swiped sideways. 1 is right on screen, -1 is left.
    case swiped(Int)
}

/// Turns a stream of hand poses into hand states and pinch events. No camera, so tests can drive it.
public struct HandGestureRecognizer {
    /// A pinch starts under this ratio and ends over the larger one, so it never flickers at the edge.
    public var pinchOn: CGFloat = 0.28
    public var pinchOff: CGFloat = 0.42
    /// The part of the camera picture that maps to the whole stage, so kids reach the stage edges
    /// without their hand leaving the picture.
    public var reach = CGRect(x: 0.15, y: 0.12, width: 0.7, height: 0.7)
    /// A hand lost for less than this keeps its pinch. Vision misses the odd frame.
    public var lostGrace: TimeInterval = 0.25
    /// A fist must hold this long to pause, so fingers passing through a fist shape do not count.
    public var fistHold: TimeInterval = 0.2
    /// A bigger jump in one frame is a tracking glitch and is left out of the drag.
    public var maxStep: CGFloat = 0.15
    /// A pinch kept still this long counts as a hold.
    public var holdTime: TimeInterval = 1.0
    /// How far a held pinch may drift from where it began, in stage fractions, and still be still.
    public var holdSlack: CGFloat = 0.03
    /// A two-finger swipe must cover this much of the picture width within `swipeTime`, mostly sideways.
    public var swipeDistance: CGFloat = 0.2
    public var swipeTime: TimeInterval = 0.5
    /// After a swipe, the next one waits this long, so one wave does not switch twice.
    public var swipeCooldown: TimeInterval = 0.9
    /// 0 to 1 while a still pinch fills up toward a hold, else 0.
    public private(set) var holdProgress: Double = 0

    private var fx = OneEuroFilter(), fy = OneEuroFilter()
    private var pinched = false
    private var last: CGPoint?
    private var lastSeen: TimeInterval?
    private var fistSince: TimeInterval?
    private var swipePath: [(time: TimeInterval, point: CGPoint)] = []
    private var swipedAt: TimeInterval = -.infinity
    /// Where and when the pinch began. Nil once it moved or was held.
    private var holdFrom: (point: CGPoint, time: TimeInterval)?
    /// Set after a two-hand zoom. A new pinch waits until the hand opens, so the hand still
    /// pinching from the zoom does not start turning the model.
    var waitForOpen = false

    public init() {}

    public mutating func reset() {
        fx.reset(); fy.reset()
        pinched = false; last = nil; lastSeen = nil; fistSince = nil; waitForOpen = false
        holdFrom = nil; holdProgress = 0; swipePath = []
    }

    /// Where the cursor was last frame, in stage fractions.
    var lastPoint: CGPoint? { last }

    /// Stops at once, ending a pinch if one is held.
    mutating func cancel() -> [HandEvent] {
        let events: [HandEvent] = pinched ? [.pinchEnded] : []
        reset()
        return events
    }

    /// Pass nil when no hand is seen. Times are seconds and must go up.
    public mutating func update(_ pose: HandPose?, at time: TimeInterval) -> (HandState, [HandEvent]) {
        guard let pose, let raw = pose.cursor, let ratio = pose.pinchRatio else { return lost(at: time) }
        lastSeen = time
        holdProgress = 0
        let m = stagePoint(raw)
        let p = CGPoint(x: fx.filter(m.x, at: time), y: fy.filter(m.y, at: time))
        var events: [HandEvent] = []
        defer { last = p }

        if pose.isFist { fistSince = fistSince ?? time } else { fistSince = nil }
        if let since = fistSince, time - since >= fistHold {
            if pinched { pinched = false; holdFrom = nil; events.append(.pinchEnded) }
            return (.paused(p), events)
        }

        if !pinched, ratio > pinchOff, pose.isTwoFingers, let palm = pose.points[.middleMCP] {
            if let dir = trackSwipe(palm, aspect: pose.aspect, at: time) { events.append(.swiped(dir)) }
        } else {
            swipePath = []
        }

        if waitForOpen, ratio > pinchOff { waitForOpen = false }
        if pinched, ratio > pinchOff {
            pinched = false
            holdFrom = nil
            events.append(.pinchEnded)
        } else if !pinched, !waitForOpen, ratio < pinchOn {
            pinched = true
            holdFrom = (p, time)
            events.append(.pinchBegan(p))
        } else if pinched, let l = last {
            let d = CGVector(dx: p.x - l.x, dy: p.y - l.y)
            let step = hypot(d.dx, d.dy)
            if step > 0, step < maxStep { events.append(.pinchMoved(d)) }
            if let h = holdFrom {
                if hypot(p.x - h.point.x, p.y - h.point.y) > holdSlack {
                    holdFrom = nil
                } else if time - h.time >= holdTime {
                    holdFrom = nil
                    events.append(.pinchHeld)
                } else {
                    holdProgress = (time - h.time) / holdTime
                }
            }
        }
        return (pinched ? .pinched(p) : .open(p), events)
    }

    /// Keeps the last `swipeTime` of the palm and reports a quick sideways sweep: 1 right, -1 left.
    private mutating func trackSwipe(_ palm: CGPoint, aspect: CGFloat, at time: TimeInterval) -> Int? {
        swipePath.append((time, palm))
        swipePath.removeAll { time - $0.time > swipeTime }
        guard time - swipedAt >= swipeCooldown, let first = swipePath.first else { return nil }
        let dx = (palm.x - first.point.x) * aspect, dy = palm.y - first.point.y
        guard abs(dx) >= swipeDistance, abs(dy) < abs(dx) * 0.6 else { return nil }
        swipedAt = time
        swipePath = []
        return dx > 0 ? 1 : -1
    }

    private mutating func lost(at time: TimeInterval) -> (HandState, [HandEvent]) {
        if pinched, let seen = lastSeen, time - seen < lostGrace, let l = last { return (.pinched(l), []) }
        let events: [HandEvent] = pinched ? [.pinchEnded] : []
        reset()
        return (.noHand, events)
    }

    /// Camera point to stage point through `reach`, held inside the stage.
    func stagePoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - reach.minX) / reach.width, 0), 1),
                y: min(max((p.y - reach.minY) / reach.height, 0), 1))
    }
}

/// One pinching hand turns the model, two pinching hands zoom. The one-hand part is `one`.
public struct HandsRecognizer {
    public var one = HandGestureRecognizer()
    /// A bigger change in one frame is a tracking glitch and is left out of the zoom.
    public var maxZoomStep: CGFloat = 0.15

    /// Pinch held, per hand, left then right on screen. Same thresholds as `one`.
    private var sidePinched = [false, false]
    private var zooming = false
    private var gap = OneEuroFilter(minCutoff: 1.0, beta: 2.0)
    private var lastGap: CGFloat?

    public init() {}

    public mutating func reset() {
        one.reset()
        sidePinched = [false, false]; zooming = false; gap.reset(); lastGap = nil
    }

    /// Up to two hands per frame. `second` is the other hand's cursor while one hand acts, for drawing.
    public mutating func update(_ poses: [HandPose], at time: TimeInterval) -> (state: HandState, events: [HandEvent], second: CGPoint?) {
        // Sorted left to right, so each hand keeps its slot from frame to frame. Hands rarely cross.
        let hands = poses.filter { $0.cursor != nil && $0.pinchRatio != nil }.prefix(2).sorted { $0.cursor!.x < $1.cursor!.x }
        if hands.count == 2 {
            for (i, h) in hands.enumerated() {
                let r = h.pinchRatio!
                if sidePinched[i] { sidePinched[i] = r <= one.pinchOff } else { sidePinched[i] = r < one.pinchOn && !h.isFist }
            }
        } else {
            sidePinched = [false, false]
        }

        if hands.count == 2, sidePinched[0], sidePinched[1] {
            var events: [HandEvent] = []
            if !zooming {
                events = one.cancel()
                zooming = true
                gap.reset(); lastGap = nil
            }
            let a = hands[0].cursor!, b = hands[1].cursor!
            let g = gap.filter(hypot((a.x - b.x) * hands[0].aspect, a.y - b.y), at: time)
            if let l = lastGap, l > 0.02 {
                let f = g / l
                if f != 1, abs(f - 1) < maxZoomStep { events.append(.zoomed(f)) }
            }
            lastGap = g
            return (.zooming(one.stagePoint(a), one.stagePoint(b)), events, nil)
        }
        if zooming {
            zooming = false
            lastGap = nil
            one.waitForOpen = true
        }

        // One hand acts. With two in view, the one nearest the cursor keeps it.
        var pick = 0
        if hands.count == 2, let last = one.lastPoint {
            let d = hands.map { h -> CGFloat in let p = one.stagePoint(h.cursor!); return hypot(p.x - last.x, p.y - last.y) }
            pick = d[1] < d[0] ? 1 : 0
        }
        let (state, events) = one.update(hands.isEmpty ? nil : hands[pick], at: time)
        let second = hands.count == 2 ? one.stagePoint(hands[1 - pick].cursor!) : nil
        return (state, events, second)
    }
}
