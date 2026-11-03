import CADShared
import XCTest
@testable import CADApp

final class BubblePlacementTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1024, height: 700)

    /// Bubble sizes at Default, Large and Extra large text.
    var sizes: [CGSize] {
        [(1.0, 150.0), (1.2, 190.0), (1.4, 250.0)].map {
            CGSize(width: BubblePlacement.width(scale: $0.0, bounds: bounds), height: $0.1)
        }
    }

    func testSmallHolesAnywhereKeepTheBubbleInsideAndClear() {
        for size in sizes {
            for x in stride(from: 10.0, through: 980, by: 30) {
                for y in stride(from: 10.0, through: 660, by: 30) {
                    let hole = CGRect(x: x, y: y, width: 34, height: 28)
                    let r = BubblePlacement.place(hole: hole, size: size, in: bounds)
                    XCTAssertTrue(bounds.contains(r), "out of bounds for \(hole) at \(size)")
                    XCTAssertFalse(BubblePlacement.overlaps(r, hole: hole), "covers \(hole) at \(size)")
                }
            }
        }
    }

    func testAppSizedHoles() {
        // Shapes like the real targets at 1024 by 700: the viewer, the inspector list, a wide field.
        let holes = [
            CGRect(x: 0, y: 0, width: 640, height: 700),     // viewer
            CGRect(x: 670, y: 260, width: 340, height: 220), // history
            CGRect(x: 670, y: 40, width: 340, height: 60),   // change field
            CGRect(x: 20, y: 20, width: 740, height: 420),   // camera area
            CGRect(x: 760, y: 620, width: 250, height: 40),  // open in and save
        ]
        for size in sizes {
            for hole in holes {
                let r = BubblePlacement.place(hole: hole, size: size, in: bounds)
                XCTAssertTrue(bounds.contains(r), "out of bounds for \(hole) at \(size)")
                XCTAssertFalse(BubblePlacement.overlaps(r, hole: hole), "covers \(hole) at \(size)")
            }
        }
    }

    func testNoHoleSpots() {
        let size = sizes[2]
        let c = BubblePlacement.place(hole: nil, size: size, in: bounds, spot: .center)
        XCTAssertEqual(c.midX, bounds.midX, accuracy: 0.5)
        XCTAssertTrue(bounds.contains(c))
    }

    func testWidthFitsBesideTheViewer() {
        XCTAssertLessThanOrEqual(BubblePlacement.width(scale: 1.4, bounds: bounds), 330)
        XCTAssertEqual(BubblePlacement.width(scale: 1, bounds: bounds), 300)
    }
}

final class TutorialCopyTests: XCTestCase {
    func testLinesAreShortAndPlain() {
        let banned = ["\u{2014}", "\u{2013}", ";", "not just", "That said", "Notably", "Importantly", "Ultimately"]
        for line in TutorialScript.allLines {
            for b in banned { XCTAssertFalse(line.contains(b), "\(b) in: \(line)") }
            let sentences = line.split(whereSeparator: { ".!?".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            XCTAssertLessThanOrEqual(sentences.count, 2, line)
            for s in sentences {
                XCTAssertLessThanOrEqual(s.split(separator: " ").count, 12, "too long: \(s)")
            }
        }
    }

    func testIdsAreUniqueAndHarnessFindsThem() {
        let ids = TutorialScript.steps.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(TutorialScript.index(forHarness: "1"), 0)
        XCTAssertEqual(TutorialScript.index(forHarness: "taller"), ids.firstIndex(of: "taller"))
        XCTAssertNil(TutorialScript.index(forHarness: "999"))
    }

    func testTourIsShortAndInOrder() {
        let ids = TutorialScript.steps.map(\.id)
        XCTAssertTrue((10...12).contains(ids.count), "\(ids.count) steps")
        let order = ["welcome", "sample", "viewer", "taller", "undo", "save", "openIn", "done"]
        XCTAssertEqual(ids.filter(order.contains), order)
    }

    func testLookOnlyStepsNeverRunTheRealAction() {
        for id in ["save", "openIn"] {
            let step = TutorialScript.steps.first { $0.id == id }!
            XCTAssertEqual(step.advance, .next, id)
            XCTAssertFalse(step.touchable, "\(id) must not let clicks reach the real button")
        }
    }
}

@MainActor
final class TutorialFlowTests: XCTestCase {
    func edit(_ change: (inout TutorialSnapshot) -> Void) -> TutorialSnapshot {
        var s = TutorialSnapshot(screen: .edit)
        change(&s)
        return s
    }

    func testAdvanceRules() {
        let a = TutorialSnapshot(screen: .edit, versions: 1)
        XCTAssertTrue(TutorialAdvance.orbit.done(from: a, to: edit { $0.orbitCount = 1 }))
        XCTAssertFalse(TutorialAdvance.edit.done(from: a, to: edit { $0.versions = 2; $0.isEditing = true }),
                       "waits until the edit has finished")
        XCTAssertTrue(TutorialAdvance.edit.done(from: a, to: edit { $0.versions = 2 }))
        XCTAssertFalse(TutorialAdvance.edit.done(from: a, to: edit { $0.versions = 1; $0.editBad = true }),
                       "a failed edit keeps the step")
        XCTAssertTrue(TutorialAdvance.undo.done(from: a, to: edit { $0.redo = 1 }))
        XCTAssertFalse(TutorialAdvance.next.done(from: a, to: edit { $0.orbitCount = 1 }))
    }

    func testHarnessEnvironment() {
        XCTAssertEqual(Tutorial.harness(from: [:]), .normal)
        XCTAssertEqual(Tutorial.harness(from: ["CADDIY_DEMO": "/x.stl"]), .off)
        XCTAssertEqual(Tutorial.harness(from: ["CADDIY_TUTORIAL": "off"]), .off)
        XCTAssertEqual(Tutorial.harness(from: ["CADDIY_TUTORIAL": "3", "CADDIY_DEMO": "/x.stl"]), .start(2))
    }

    func testStepsMoveOnFromState() {
        let t = Tutorial(environment: ["CADDIY_TUTORIAL": "viewer"])
        t.harnessPrepared()
        let viewer = TutorialScript.index(forHarness: "viewer")!
        t.check(TutorialSnapshot(screen: .scan))
        XCTAssertNil(t.index, "waits for its own screen")
        let base = TutorialSnapshot(screen: .edit, versions: 1)
        t.check(base)
        XCTAssertEqual(t.index, viewer)
        var s = base
        s.orbitCount = 1
        t.check(s)
        XCTAssertEqual(t.step?.id, "viewerTools")
    }

    func testPausesWhileDisconnected() {
        let t = Tutorial(environment: ["CADDIY_TUTORIAL": "viewer"])
        t.harnessPrepared()
        let base = TutorialSnapshot(screen: .edit, versions: 1)
        t.check(base)
        var s = base
        s.connected = false
        s.orbitCount = 1
        t.check(s)
        XCTAssertEqual(t.step?.id, "viewer")
        s.connected = true
        t.check(s)
        XCTAssertEqual(t.step?.id, "viewerTools", "resumes and sees the change")
    }

    func testScreenJumpGoesToThatScreensFirstStep() {
        let t = Tutorial(environment: ["CADDIY_TUTORIAL": "startScanning"])
        t.harnessPrepared()
        t.check(TutorialSnapshot(screen: .firstRun))
        XCTAssertEqual(t.step?.id, "startScanning")
        t.check(TutorialSnapshot(screen: .process))
        XCTAssertEqual(t.step?.id, "process")
        t.check(TutorialSnapshot(screen: .edit, versions: 1))
        XCTAssertEqual(t.step?.id, "viewer")
        t.check(TutorialSnapshot(screen: .scan))
        XCTAssertEqual(t.step?.id, "sample")
        XCTAssertFalse(t.canGoBack, "the step before is on another screen")
    }

    func testFinishEndsTheTour() {
        let t = Tutorial(environment: ["CADDIY_TUTORIAL": "tips"])
        t.harnessPrepared()
        t.check(TutorialSnapshot(screen: .edit))
        t.next()
        XCTAssertEqual(t.step?.id, "done")
        t.next()
        XCTAssertNil(t.index)
    }

    func testNoWelcomeBeforeTheSavedModelLoads() {
        let t = Tutorial(environment: [:])
        t.check(TutorialSnapshot(screen: .firstRun, loaded: false))
        XCTAssertNil(t.index, "waits for the first status reply")
        t.check(TutorialSnapshot(screen: .edit, versions: 1))
        XCTAssertNil(t.index, "a saved model skips the offer")
    }

    func testLinesForWaitsAndFailures() {
        let taller = TutorialScript.steps.first { $0.id == "taller" }!
        let a = TutorialSnapshot(screen: .edit, versions: 1)
        var s = a
        s.isEditing = true
        XCTAssertEqual(TutorialScript.say(taller, entry: a, now: s, elapsed: 20, nudge: false, hasHole: true).pose, .thinking)
        s.isEditing = false
        s.editBad = true
        XCTAssertEqual(TutorialScript.say(taller, entry: a, now: s, elapsed: 0, nudge: false, hasHole: true).pose, .sad)
        s.connected = false
        XCTAssertEqual(TutorialScript.say(taller, entry: a, now: s, elapsed: 0, nudge: false, hasHole: true).pose, .sleepy)
        // A failed scan must not keep saying "building".
        let process = TutorialScript.steps.first { $0.id == "process" }!
        let failed = TutorialSnapshot(screen: .process, processFailed: true)
        XCTAssertEqual(TutorialScript.say(process, entry: a, now: failed, elapsed: 30, nudge: false, hasHole: true).pose, .sad)
    }
}
