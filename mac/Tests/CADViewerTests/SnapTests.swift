import XCTest
import simd
@testable import CADViewer

final class SnapTests: XCTestCase {
    func box(_ x0: Float, _ y0: Float, _ x1: Float, _ y1: Float) -> SnapBox { SnapBox(min: SIMD2(x0, y0), max: SIMD2(x1, y1)) }

    func testEdgesLineUpOnEachAxisOnTheirOwn() {
        // x: moving left edge 12 is 2 mm from the other's left edge 10. y: 40 mm away, no snap.
        let r = SnapSolver.snap(moving: box(12, 50, 22, 60), others: [box(10, 0, 30, 10)])
        XCTAssertEqual(r.dx ?? .nan, -2, accuracy: 1e-5)
        XCTAssertNil(r.dy)
        XCTAssertEqual(r.guides.count, 1)
        XCTAssertEqual(r.guides[0].from, SIMD2(10, 0))
        XCTAssertEqual(r.guides[0].to, SIMD2(10, 60))
    }

    func testFlushPicksTheClosestAndCentresCount() {
        // Moving right edge 28.5 meets the other's left edge 30: flush, 1.5 mm.
        // Its y centre 4.6 is 0.4 from the other's centre 5.
        let r = SnapSolver.snap(moving: box(18.5, -0.4, 28.5, 9.6), others: [box(30, 0, 50, 10)])
        XCTAssertEqual(r.dx ?? .nan, 1.5, accuracy: 1e-5)
        XCTAssertEqual(r.dy ?? .nan, 0.4, accuracy: 1e-5)
        XCTAssertEqual(r.guides.count, 2)
    }

    func testBedCentreLinesAndThreshold() {
        // Centre x at 2.5 snaps to the bed centre line. 3.5 does not.
        XCTAssertEqual(SnapSolver.snap(moving: box(-7.5, 40, 12.5, 50), others: SnapSolver.bedLines).dx ?? .nan, -2.5, accuracy: 1e-5)
        XCTAssertNil(SnapSolver.snap(moving: box(-6.5, 40, 13.5, 50), others: SnapSolver.bedLines).dx)
        XCTAssertNil(SnapSolver.snap(moving: box(40, 40, 50, 50), others: []).dx)
    }

    func testSizeTagsMatchTheBox() {
        let lo = SIMD3<Float>(-5, 0, -10), hi = SIMD3<Float>(5, 30, 10)
        let tags = SizeTags.tags(lo: lo, hi: hi)
        XCTAssertEqual(tags.map(\.mm), [10, 20, 30])   // width x, depth, height
        XCTAssertEqual(SizeTags.text(40), "40 mm")
        XCTAssertEqual(SizeTags.text(12.46), "12.5 mm")
        XCTAssertEqual(SizeTags.text(9.98), "10 mm")
    }

    func testDragSnapsInTheSceneAndTagsFollowTheSelection() {
        let url = URL(fileURLWithPath: "/tmp/box.stl")
        let box = try! STLLoader.parse(data: ViewerSelfCheck.binarySTL(ViewerSelfCheck.boxTriangles(SIMD3(10, 20, 30))))
        let s = ViewerScene()
        s.setParts([PartView(id: "a", url: url), PartView(id: "b", url: url, x: 60)], meshes: [url: box])
        // Box a spans x -5...5. Dropping b at 11.2 puts its left edge 1.2 from a's right edge: clicks flush at 10.
        s.dragPart("b", x: 11.2, z: 40, snap: true)
        XCTAssertEqual(s.position(of: "b")?.x ?? .nan, 10, accuracy: 1e-4)
        // At 12.25 the edge is 2.25 away, so the pull is half strength: 10 + 2.25 / 2.
        s.dragPart("b", x: 12.25, z: 40, snap: true)
        XCTAssertEqual(s.position(of: "b")?.x ?? .nan, 11.125, accuracy: 1e-4)
        s.dragPart("b", x: 11.7, z: 40, snap: false)
        XCTAssertEqual(s.position(of: "b")?.x ?? .nan, 12, accuracy: 1e-4, "no snap, just 1 mm steps")
        s.select("b")
        XCTAssertEqual(s.footprint("b").map { $0.max.x - $0.min.x } ?? .nan, 10, accuracy: 1e-4)
    }

    func testEaseClicksInsideAndFadesOut() {
        XCTAssertEqual(SnapSolver.ease(1.5), 1.5)       // inside the catch zone: all the way
        XCTAssertEqual(SnapSolver.ease(-1), -1)
        XCTAssertEqual(SnapSolver.ease(2.25), 1.125, accuracy: 1e-6)   // half way out: half the pull
        XCTAssertEqual(SnapSolver.ease(-2.25), -1.125, accuracy: 1e-6)
        XCTAssertEqual(SnapSolver.ease(3), 0)            // the edge: no pull, so no jump
        XCTAssertEqual(SnapSolver.ease(5), 0)
        // Dragging steadily past a line, the part never runs backwards.
        var last = -Float.infinity
        for i in 0...60 {
            let raw = Float(i) * 0.1 - 3    // from 3 mm before the line to 3 mm after
            let out = raw + SnapSolver.ease(-raw)
            XCTAssertGreaterThanOrEqual(out, last - 1e-5)
            last = out
        }
    }

    func testHeldLineWinsWhileInReach() {
        // Two lines 1 mm apart: the other box's left edge at 10 and a bed line at 11.
        let others = [box(10, 0, 30, 10), box(11, 100, 11, 120)]
        let moving = box(9.7, 50, 18, 60)   // left edge 9.7: 0.3 from 10, 1.3 from 11
        XCTAssertEqual(SnapSolver.snap(moving: moving, others: others).at.x, 10)
        // Holding 11 keeps it on 11 even though 10 is closer.
        let r = SnapSolver.snap(moving: moving, others: others, held: (11, nil))
        XCTAssertEqual(r.at.x, 11)
        XCTAssertEqual(r.dx ?? .nan, 1.3, accuracy: 1e-5)
        // Out of reach of the held line, it lets go and takes whatever is close: right edge 29 to 30.
        XCTAssertEqual(SnapSolver.snap(moving: box(25, 50, 29, 60), others: others, held: (11, nil)).at.x, 30)
    }
}
