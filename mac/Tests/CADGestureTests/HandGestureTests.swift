import CoreGraphics
import XCTest
@testable import CADGesture

/// A flat hand facing the camera, wrist at the bottom. `gap` is thumb tip to index tip over hand size.
/// `fist` curls the four fingers back past their knuckles. `at` moves the whole hand.
private func hand(gap: CGFloat = 1.0, fist: Bool = false, peace: Bool = false, apart: Bool = false, at c: CGPoint = CGPoint(x: 0.5, y: 0.5)) -> HandPose {
    let s: CGFloat = 0.2   // wrist to middle knuckle, in picture heights
    var p: [HandJoint: CGPoint] = [:]
    func put(_ j: HandJoint, _ x: CGFloat, _ y: CGFloat) { p[j] = CGPoint(x: c.x + x * s, y: c.y + y * s) }
    put(.wrist, 0, 0.5)
    put(.middleMCP, 0, -0.5)
    let knuckles: [(HandJoint, HandJoint, CGFloat)] = [(.indexMCP, .indexTip, -0.25), (.middleMCP, .middleTip, 0),
                                                       (.ringMCP, .ringTip, 0.2), (.littleMCP, .littleTip, 0.4)]
    for (k, tip, x) in knuckles {
        put(k, x, -0.5)
        let curled = fist || (peace && (k == .ringMCP || k == .littleMCP))
        // Together, the index tip sits right beside the middle tip. Apart is a spread peace sign.
        let tipX = (peace && k == .indexMCP) ? (apart ? -0.7 : -0.1) : x
        put(tip, tipX, curled ? 0.1 : -1.2)
    }
    // Thumb tip sits `gap` hand sizes left of the index tip.
    let index = p[.indexTip]!
    p[.thumbTip] = CGPoint(x: index.x - gap * s, y: index.y)
    return HandPose(points: p, aspect: 1)
}

final class HandPoseTests: XCTestCase {
    func testPinchRatioIsGapOverHandSize() {
        XCTAssertEqual(hand(gap: 0.1).pinchRatio!, 0.1, accuracy: 1e-6)
        XCTAssertEqual(hand(gap: 0.9).pinchRatio!, 0.9, accuracy: 1e-6)
    }

    func testRatioIgnoresHandSizeAndDistance() {
        var far = hand(gap: 0.3)
        far.points = far.points.mapValues { CGPoint(x: 0.5 + ($0.x - 0.5) * 0.4, y: 0.5 + ($0.y - 0.5) * 0.4) }
        XCTAssertEqual(far.pinchRatio!, 0.3, accuracy: 1e-6)
    }

    func testFist() {
        XCTAssertTrue(hand(fist: true).isFist)
        XCTAssertFalse(hand().isFist)
        XCTAssertFalse(hand(gap: 0.1).isFist, "a pinch with the other fingers out is not a fist")
    }

    func testAspectStretchesSideways() {
        var wide = hand(gap: 0.5)
        wide.aspect = 2
        // The thumb gap is sideways and the hand size upright, so only the gap doubles.
        XCTAssertEqual(wide.pinchRatio!, 1.0, accuracy: 1e-6)
    }
}

final class HandGestureRecognizerTests: XCTestCase {
    private var r = HandGestureRecognizer()
    private var t: TimeInterval = 100

    private func step(_ pose: HandPose?) -> (HandState, [HandEvent]) {
        t += 1.0 / 30
        return r.update(pose, at: t)
    }

    override func setUp() { r = HandGestureRecognizer(); t = 100 }

    func testOpenHandHoversWithoutEvents() {
        let (state, events) = step(hand())
        guard case .open = state else { return XCTFail("\(state)") }
        XCTAssertEqual(events, [])
    }

    func testPinchBeginsAndEndsWithHysteresis() {
        _ = step(hand(gap: 1))
        XCTAssertEqual(step(hand(gap: 0.1)).1.first.map(isBegan), true)
        // Between the two thresholds the pinch holds.
        XCTAssertFalse(step(hand(gap: 0.35)).1.contains(.pinchEnded))
        guard case .pinched = step(hand(gap: 0.35)).0 else { return XCTFail("should still be pinched") }
        XCTAssertEqual(step(hand(gap: 0.6)).1, [.pinchEnded])
        // And on the way back down it does not start again until under pinchOn.
        XCTAssertEqual(step(hand(gap: 0.35)).1, [])
    }

    func testDragSendsMovesInStageFractions() {
        _ = step(hand(gap: 0.1, at: CGPoint(x: 0.5, y: 0.5)))
        var moved = CGVector.zero
        for i in 1...30 {
            let x = 0.5 + CGFloat(i) * 0.005
            for e in step(hand(gap: 0.1, at: CGPoint(x: x, y: 0.5))).1 {
                if case .pinchMoved(let d) = e { moved.dx += d.dx; moved.dy += d.dy }
            }
        }
        // 0.15 of the picture is 0.15 / 0.7 of the stage, a little less because the filter lags.
        XCTAssertEqual(moved.dx, 0.15 / 0.7, accuracy: 0.04)
        XCTAssertEqual(moved.dy, 0, accuracy: 1e-6)
    }

    func testShortLossKeepsThePinchLongLossEndsIt() {
        _ = step(hand(gap: 0.1))
        guard case .pinched = step(nil).0 else { return XCTFail("one missed frame keeps the pinch") }
        var ended = false
        for _ in 0..<10 { ended = ended || step(nil).1.contains(.pinchEnded) }
        XCTAssertTrue(ended)
        XCTAssertEqual(step(nil).0, .noHand)
    }

    func testFistPausesAfterHoldAndEndsAPinch() {
        _ = step(hand(gap: 0.1))
        // Gap 0.3 sits between the thresholds, so only the fist can end this pinch.
        guard case .pinched = step(hand(gap: 0.3, fist: true)).0 else { return XCTFail("a fist needs to hold first") }
        var events: [HandEvent] = []
        var state = HandState.noHand
        for _ in 0..<8 {
            let s = step(hand(gap: 0.3, fist: true))
            state = s.0
            events += s.1
        }
        guard case .paused = state else { return XCTFail("\(state)") }
        XCTAssertTrue(events.contains(.pinchEnded))
    }

    func testStillPinchFillsUpThenHoldsOnce() {
        _ = step(hand(gap: 0.1))
        var held = 0
        var progress: [Double] = []
        for _ in 0..<45 {  // 1.5 seconds
            held += step(hand(gap: 0.1)).1.filter { $0 == .pinchHeld }.count
            progress.append(r.holdProgress)
        }
        XCTAssertEqual(held, 1)
        XCTAssertGreaterThan(progress[15], 0.4)
        XCTAssertEqual(progress.last, 0, "the ring empties once the hold fires")
    }

    func testMovingPinchNeverHolds() {
        _ = step(hand(gap: 0.1, at: CGPoint(x: 0.3, y: 0.5)))
        var held = false
        for i in 1...45 {
            let x = 0.3 + CGFloat(i) * 0.004
            held = held || step(hand(gap: 0.1, at: CGPoint(x: x, y: 0.5))).1.contains(.pinchHeld)
        }
        XCTAssertFalse(held)
    }

    func testBigJumpIsDropped() {
        _ = step(hand(gap: 0.1, at: CGPoint(x: 0.2, y: 0.5)))
        let events = step(hand(gap: 0.1, at: CGPoint(x: 0.8, y: 0.5))).1
        XCTAssertFalse(events.contains { if case .pinchMoved = $0 { true } else { false } })
    }

    func testReachMapsToTheWholeStage() {
        XCTAssertEqual(r.stagePoint(CGPoint(x: 0.15, y: 0.12)), CGPoint(x: 0, y: 0))
        XCTAssertEqual(r.stagePoint(CGPoint(x: 0.85, y: 0.82)).x, 1, accuracy: 1e-6)
        XCTAssertEqual(r.stagePoint(CGPoint(x: 0, y: 1)), CGPoint(x: 0, y: 1), "held inside the stage")
    }

    private func isBegan(_ e: HandEvent) -> Bool { if case .pinchBegan = e { true } else { false } }
}

final class TwoFingerSwipeTests: XCTestCase {
    private var r = HandGestureRecognizer()
    private var t: TimeInterval = 100

    private func sweep(from: CGFloat, to: CGFloat, frames: Int, peace: Bool = true) -> [HandEvent] {
        var all: [HandEvent] = []
        for i in 0...frames {
            t += 1.0 / 30
            let x = from + (to - from) * CGFloat(i) / CGFloat(frames)
            all += r.update(hand(peace: peace, at: CGPoint(x: x, y: 0.5)), at: t).1
        }
        return all
    }

    func testPeaceSignIsNotAFist() {
        XCTAssertTrue(hand(peace: true).isTwoFingers)
        XCTAssertFalse(hand(peace: true).isFist)
        XCTAssertFalse(hand().isTwoFingers)
        XCTAssertFalse(hand(peace: true, apart: true).isTwoFingers, "spread fingers must not switch tools")
    }

    func testSwipeRightAndLeft() {
        XCTAssertEqual(sweep(from: 0.3, to: 0.6, frames: 9), [.swiped(1)])
        t += 2
        XCTAssertEqual(sweep(from: 0.6, to: 0.3, frames: 9), [.swiped(-1)])
    }

    func testSwipeSurvivesBriefDropouts() {
        var all: [HandEvent] = []
        for i in 0...12 {
            t += 1.0 / 30
            let x = 0.3 + 0.3 * CGFloat(i) / 12
            // Every third frame the pose slips, like a real hand in motion.
            let pose = hand(peace: i % 3 != 2, at: CGPoint(x: x, y: 0.5))
            all += r.update(pose, at: t).1
        }
        XCTAssertEqual(all, [.swiped(1)])
    }

    func testOneWaveSwitchesOnce() {
        XCTAssertEqual(sweep(from: 0.2, to: 0.8, frames: 18).filter { $0 == .swiped(1) }.count, 1)
    }

    func testSlowDriftAndOpenHandDoNotSwipe() {
        XCTAssertEqual(sweep(from: 0.3, to: 0.6, frames: 60), [])
        XCTAssertEqual(sweep(from: 0.3, to: 0.6, frames: 9, peace: false), [])
    }
}

final class HandsRecognizerTests: XCTestCase {
    private var r = HandsRecognizer()
    private var t: TimeInterval = 100

    override func setUp() { r = HandsRecognizer(); t = 100 }

    private func step(_ poses: [HandPose]) -> (state: HandState, events: [HandEvent], second: CGPoint?) {
        t += 1.0 / 30
        return r.update(poses, at: t)
    }

    /// Total zoom over the events, above 1 for closer.
    private func zoom(_ events: [HandEvent]) -> CGFloat {
        events.reduce(1) { if case .zoomed(let f) = $1 { $0 * f } else { $0 } }
    }

    private func pair(gap: CGFloat, spread: CGFloat) -> [HandPose] {
        [hand(gap: gap, at: CGPoint(x: 0.5 - spread, y: 0.5)), hand(gap: gap, at: CGPoint(x: 0.5 + spread, y: 0.5))]
    }

    func testOneHandStillTurnsWithASecondOpenHandInView() {
        _ = step([hand(gap: 0.1, at: CGPoint(x: 0.3, y: 0.5)), hand(at: CGPoint(x: 0.7, y: 0.5))])
        let s = step([hand(gap: 0.1, at: CGPoint(x: 0.31, y: 0.5)), hand(at: CGPoint(x: 0.7, y: 0.5))])
        guard case .pinched = s.state else { return XCTFail("\(s.state)") }
        XCTAssertNotNil(s.second, "the open hand is drawn faint")
        XCTAssertTrue(s.events.contains { if case .pinchMoved = $0 { true } else { false } })
    }

    func testBothPinchingZoomsInWhenSpreadAndOutWhenClosed() {
        var all: [HandEvent] = []
        for i in 0..<20 { all += step(pair(gap: 0.1, spread: 0.15 + CGFloat(i) * 0.005)).events }
        guard case .zooming = step(pair(gap: 0.1, spread: 0.25)).state else { return XCTFail("should zoom") }
        XCTAssertGreaterThan(zoom(all), 1.2)
        all = []
        for i in 0..<20 { all += step(pair(gap: 0.1, spread: 0.25 - CGFloat(i) * 0.005)).events }
        XCTAssertLessThan(zoom(all), 0.85)
        XCTAssertFalse(all.contains { if case .pinchMoved = $0 { true } else { false } }, "no turning while zooming")
    }

    func testZoomEndsAnOpenDrag() {
        _ = step([hand(gap: 0.1, at: CGPoint(x: 0.35, y: 0.5)), hand(at: CGPoint(x: 0.65, y: 0.5))])
        let s = step(pair(gap: 0.1, spread: 0.15))
        XCTAssertTrue(s.events.contains(.pinchEnded))
    }

    func testHandStillPinchingAfterZoomMustOpenBeforeTurning() {
        for _ in 0..<5 { _ = step(pair(gap: 0.1, spread: 0.15)) }
        // The right hand lets go. The left still pinches but must not start turning.
        for i in 0..<5 {
            let s = step([hand(gap: 0.1, at: CGPoint(x: 0.35 + CGFloat(i) * 0.01, y: 0.5)), hand(at: CGPoint(x: 0.65, y: 0.5))])
            XCTAssertFalse(s.events.contains { if case .pinchBegan = $0 { true } else { false } })
        }
        _ = step([hand(at: CGPoint(x: 0.4, y: 0.5))])
        XCTAssertTrue(step([hand(gap: 0.1, at: CGPoint(x: 0.4, y: 0.5))]).events.contains { if case .pinchBegan = $0 { true } else { false } })
    }
}

final class OneEuroFilterTests: XCTestCase {
    func testSettlesOnAStillValue() {
        var f = OneEuroFilter()
        var out = 0.0
        _ = f.filter(0, at: 0)
        for i in 1...60 { out = f.filter(1, at: Double(i) / 30) }
        XCTAssertEqual(out, 1, accuracy: 0.01)
    }

    func testSmoothsJitter() {
        var f = OneEuroFilter()
        var spread = 0.0
        for i in 0..<90 {
            let noisy = 0.5 + (i.isMultiple(of: 2) ? 0.01 : -0.01)
            let out = f.filter(noisy, at: Double(i) / 30)
            if i > 30 { spread = max(spread, abs(out - 0.5)) }
        }
        XCTAssertLessThan(spread, 0.005, "the 0.01 wobble shrinks to under half")
    }
}
