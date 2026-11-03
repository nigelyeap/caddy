import SceneKit
import XCTest
import simd
@testable import CADViewer

final class CutPlaneTests: XCTestCase {
    func testPlaneHoldsEyeAndBothStrokePoints() {
        let eye = SIMD3<Float>(120, 80, 200)
        let a = SIMD3<Float>(-10, 5, 3), b = SIMD3<Float>(25, 40, -7)
        let plane = try! XCTUnwrap(CutPlane.make(eye: eye, strokeA: a, strokeB: b))
        for p in [eye, a, b] { XCTAssertEqual(plane.distance(to: p), 0, accuracy: 1e-3) }
        XCTAssertEqual(simd_length(plane.normal), 1, accuracy: 1e-5)
        // Any point further along the eye rays is on it too, so the depth of the stroke does not matter.
        XCTAssertEqual(plane.distance(to: eye + (b - eye) * 3.7), 0, accuracy: 1e-2)
    }

    func testStrokeAlongOneRayGivesNoPlane() {
        let eye = SIMD3<Float>(0, 0, 100)
        XCTAssertNil(CutPlane.make(eye: eye, strokeA: SIMD3(0, 0, 0), strokeB: SIMD3(0, 0, -50)))
        XCTAssertNil(CutPlane.make(eye: eye, strokeA: SIMD3(1, 2, 3), strokeB: SIMD3(1, 2, 3)))
    }

    func testApplyingATransformKeepsPointsOnThePlane() {
        let eye = SIMD3<Float>(50, 60, 70), a = SIMD3<Float>(1, 2, 3), b = SIMD3<Float>(-4, 9, 2)
        let plane = CutPlane.make(eye: eye, strokeA: a, strokeB: b)!
        var m = simd_float4x4(simd_quatf(angle: 0.7, axis: simd_normalize(SIMD3(1, 2, 3))))
        m = simd_float4x4(diagonal: SIMD4(2, 1, 0.5, 1)) * m
        m.columns.3 = SIMD4(10, -20, 30, 1)
        let moved = plane.applying(m)
        for p in [eye, a, b] {
            let q = m * SIMD4(p, 1)
            XCTAssertEqual(moved.distance(to: SIMD3(q.x, q.y, q.z)), 0, accuracy: 1e-2)
        }
        XCTAssertEqual(simd_length(moved.normal), 1, accuracy: 1e-5)
    }

    func testDragRayMeetsTheGrabPlane() {
        let plane = Plane(point: SIMD3(0, 10, 0), normal: SIMD3(0, 1, 0))
        let hit = plane.intersect(origin: SIMD3(5, 110, -3), direction: simd_normalize(SIMD3(1, -1, 0)))
        XCTAssertEqual(hit?.x ?? .nan, 105, accuracy: 1e-3)
        XCTAssertEqual(hit?.y ?? .nan, 10, accuracy: 1e-3)
        XCTAssertNil(plane.intersect(origin: SIMD3(0, 50, 0), direction: SIMD3(1, 0, 0)), "parallel")
        XCTAssertNil(plane.intersect(origin: SIMD3(0, 50, 0), direction: SIMD3(0, 1, 0)), "points away")
    }
}

final class PartSceneTests: XCTestCase {
    /// A 10 x 20 x 30 mm box with its corner at the origin, so seating has real work to do.
    let box = try! STLLoader.parse(data: ViewerSelfCheck.binarySTL(ViewerSelfCheck.boxTriangles(SIMD3(10, 20, 30))))
    let boxURL = URL(fileURLWithPath: "/tmp/box.stl")
    let ballURL = URL(fileURLWithPath: "/tmp/ball.stl")
    lazy var ball = try! STLLoader.parse(data: ViewerSelfCheck.binarySTL(ViewerSelfCheck.sphereTriangles(radius: 8, rings: 12, segments: 24)))

    func twoBoxes() -> ViewerScene {
        let s = ViewerScene()
        s.setParts([PartView(id: "a", url: boxURL), PartView(id: "b", url: boxURL, x: 60)], meshes: [boxURL: box])
        return s
    }

    func mesh(_ s: ViewerScene, _ id: String) -> SCNNode { s.parts[id]!.childNodes.first! }

    func testDuplicatesShareOneGeometryAndBoundsCoverBoth() {
        let s = twoBoxes()
        XCTAssertTrue(s.hasModel)
        XCTAssertTrue(s.isMultiPart)
        XCTAssertTrue(mesh(s, "a").geometry === mesh(s, "b").geometry)
        XCTAssertEqual(s.modelCorners.count, 16)
        // Box a spans x -5...5, box b 55...65, both 0...30 high.
        XCTAssertEqual(s.center.x, 30, accuracy: 1e-3)
        XCTAssertEqual(s.center.y, 15, accuracy: 1e-3)
        XCTAssertGreaterThan(s.radius, 35)
    }

    func testSeatPutsTheBottomCentreOnThePartOrigin() {
        let s = ViewerScene()
        s.setParts([PartView(id: "a", url: boxURL, x: 12, y: 7, z: 0)], meshes: [boxURL: box])
        let corners = ViewerScene.corners(of: mesh(s, "a"))
        let ys = corners.map(\.y), xs = corners.map(\.x), zs = corners.map(\.z)
        XCTAssertEqual(ys.min()!, 0, accuracy: 1e-3)
        XCTAssertEqual(ys.max()!, 30, accuracy: 1e-3)
        XCTAssertEqual((xs.min()! + xs.max()!) / 2, 12, accuracy: 1e-3)
        // STL y 7 is SceneKit z -7.
        XCTAssertEqual((zs.min()! + zs.max()!) / 2, -7, accuracy: 1e-3)
    }

    func testDiffAddsRemovesAndPrunesTheCache() {
        let s = twoBoxes()
        let keep = s.parts["a"]
        s.setParts([PartView(id: "a", url: boxURL, x: 5), PartView(id: "c", url: ballURL)], meshes: [ballURL: ball])
        XCTAssertTrue(s.parts["a"] === keep, "same id keeps its node")
        XCTAssertNil(s.parts["b"])
        XCTAssertNotNil(s.parts["c"])
        XCTAssertEqual(s.position(of: "a")?.x, 5)
        s.setParts([PartView(id: "c", url: ballURL)], meshes: [:])
        XCTAssertFalse(s.hasGeometry(for: boxURL), "unused files leave the cache")
        XCTAssertTrue(s.hasGeometry(for: ballURL))
    }

    func testPartIDWalksUpFromTheMesh() {
        let s = twoBoxes()
        XCTAssertEqual(s.partID(of: mesh(s, "b")), "b")
        XCTAssertNil(s.partID(of: SCNNode()))
    }

    func testAPartRestsOnTheFloorOrOnTopOfAnother() {
        let s = twoBoxes()
        XCTAssertEqual(s.restHeight(for: "b", x: 60, z: 0), 0, accuracy: 1e-3, "nothing under it")
        s.select("a")   // the outline must not count as something to stand on
        let p = s.movePart("b", x: 0.4, z: 0)
        XCTAssertEqual(p?.y ?? -1, 30, accuracy: 1e-3, "sits on box a, which is 30 mm high")
        XCTAssertEqual(p?.x, 0, "snapped to 1 mm")
        XCTAssertEqual(s.movePart("b", x: 40, z: 0)?.y ?? -1, 0, accuracy: 1e-3, "back on the floor")
        XCTAssertEqual(s.movePart("b", x: 900, z: -900), SIMD3(125, 0, -125), "kept on the 250 mm bed")
    }

    func testSelectionAddsAndClearsOneOutline() {
        let s = twoBoxes()
        s.select("a")
        XCTAssertNotNil(mesh(s, "a").childNode(withName: "outline", recursively: false))
        s.select("b")
        XCTAssertNil(mesh(s, "a").childNode(withName: "outline", recursively: false))
        XCTAssertNotNil(mesh(s, "b").childNode(withName: "outline", recursively: false))
        s.select(nil)
        XCTAssertNil(mesh(s, "b").childNode(withName: "outline", recursively: false))
        s.select("b")
        s.setParts([PartView(id: "a", url: boxURL)], meshes: [:])
        XCTAssertNil(s.selectedID, "a removed part is no longer selected")
    }

    func testOneModelPathStillWorksAndReplacesParts() {
        let s = twoBoxes()
        s.setModel(box, edit: false, animate: false)
        XCTAssertTrue(s.hasModel)
        XCTAssertFalse(s.isMultiPart)
        XCTAssertEqual(s.modelCorners.count, 8)
        XCTAssertEqual(s.center, SIMD3(0, 15, 0))
        s.setParts([PartView(id: "a", url: boxURL)], meshes: [boxURL: box])
        XCTAssertTrue(s.isMultiPart)
        XCTAssertEqual(s.parts.count, 1)
        s.clearModel()
        XCTAssertFalse(s.hasModel)
    }

    @MainActor
    func testCutPlaneArrivesInThePartsOwnFileFrame() {
        let c = ViewerController()
        c.stage.setParts([PartView(id: "a", url: boxURL, x: 40, yawDegrees: 90)], meshes: [boxURL: box])
        var got: Plane?
        c.onCut = { id, plane in XCTAssertEqual(id, "a"); got = plane }
        // An upright world cut through the part's centre, facing along world x.
        c.cut(partID: "a", worldPlane: Plane(point: SIMD3(40, 0, 0), normal: SIMD3(1, 0, 0)))
        let plane = try! XCTUnwrap(got)
        // The file's box spans 0...10, 0...20, 0...30, so its middle is (5, 10, 15).
        XCTAssertEqual(plane.distance(to: SIMD3(5, 10, 15)), 0, accuracy: 1e-3)
        // Turned 90 degrees, world x runs along the file's y.
        XCTAssertEqual(abs(plane.normal.y), 1, accuracy: 1e-4)
    }

    /// The tip axis the app sends must match what the camera shows, so "forward" leans the top toward you.
    @MainActor
    func testRightAzimuthMatchesTheCamera() {
        let c = ViewerController()
        // An STL point or direction, placed in the scene the way the viewer does it.
        func scene(_ v: SIMD3<Double>) -> SIMD3<Float> { PartView(id: "v", url: boxURL, x: v.x, y: v.y, z: v.z).scenePosition }
        func flat(_ v: SIMD3<Float>) -> SIMD3<Float> { simd_normalize(SIMD3(v.x, 0, v.z)) }
        // Tips STL up by +90 about the flat axis at `az`, the same way bench/parts.py does.
        func tippedUp(_ az: Double) -> SIMD3<Float> {
            let a = az * .pi / 180
            let q = simd_quatd(angle: .pi / 2, axis: SIMD3(cos(a), sin(a), 0))
            return scene(q.act(SIMD3(0, 0, 1)))
        }
        for dYaw: Float in [0, 1.3, -2.5] {
            c.stage.orbit(dYaw: dYaw, dPitch: 0)
            let right = flat(c.stage.cameraNode.simdWorldRight)
            let toViewer = flat(-c.stage.cameraNode.simdWorldFront)
            let az = c.rightAzimuthDegrees * .pi / 180
            XCTAssertEqual(simd_dot(scene(SIMD3(cos(az), sin(az), 0)), right), 1, accuracy: 1e-4)
            // Forward: +degrees about screen right leans the top toward the viewer.
            XCTAssertEqual(simd_dot(tippedUp(c.rightAzimuthDegrees), toViewer), 1, accuracy: 1e-4)
            // Right: +degrees about right plus 90 leans the top to screen right.
            XCTAssertEqual(simd_dot(tippedUp(c.rightAzimuthDegrees + 90), right), 1, accuracy: 1e-4)
        }
        // Default view: right is 35 degrees round, as ViewerScene.defaultYaw says.
        c.stage.frame(animated: false)
        XCTAssertEqual(c.rightAzimuthDegrees, 35, accuracy: 1e-3)
    }

    @MainActor
    func orbitView(_ c: ViewerController) -> OrbitSCNView {
        let v = OrbitSCNView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), options: nil)
        v.controller = c
        v.scene = c.stage.scene
        v.pointOfView = c.stage.cameraNode
        c.view = v
        return v
    }

    /// A hand drag of a tenth of the view turns the camera like a mouse drag of that many points.
    @MainActor
    func testHandDragTurnsLikeAMouseDrag() {
        let c = ViewerController()
        _ = orbitView(c)
        let before = c.stage.yaw, count = c.orbitCount
        c.handDragBegan(at: CGPoint(x: 0.5, y: 0.5))
        c.handDragged(to: CGPoint(x: 0.6, y: 0.5), by: CGVector(dx: 0.1, dy: 0))
        c.handDragged(to: CGPoint(x: 0.7, y: 0.5), by: CGVector(dx: 0.1, dy: 0))
        c.handDragEnded()
        XCTAssertEqual(c.stage.yaw - before, -2 * 40 * OrbitSCNView.yawPerPoint, accuracy: 1e-4)
        XCTAssertEqual(c.orbitCount, count + 1)
    }

    /// A cut stroke let go off every part, with nothing picked, tells the app to drop any cut still waiting.
    @MainActor
    func testCutStrokeOffEveryPartIsDropped() async throws {
        let c = ViewerController()
        let v = orbitView(c)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cut-box-\(UUID()).stl")
        try ViewerSelfCheck.binarySTL(ViewerSelfCheck.boxTriangles(SIMD3(10, 20, 30))).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await c.setParts([PartView(id: "a", url: url)])
        c.tool = .cut
        var dropped = 0, cuts = 0
        c.onCutDropped = { dropped += 1 }
        c.onCut = { _, _ in cuts += 1 }
        SCNTransaction.flush()
        XCTAssertNil(v.partID(at: CGPoint(x: 10, y: 10)))
        c.handDragBegan(at: CGPoint(x: 0.02, y: 0.9))
        c.handDragged(to: CGPoint(x: 0.3, y: 0.9), by: CGVector(dx: 0.28, dy: 0))
        c.handDragEnded()
        XCTAssertEqual(dropped, 1)
        XCTAssertEqual(cuts, 0)
    }

    /// A pinch goes down the mouse path, so in the Turn tool it turns the part under it in 15 degree steps.
    @MainActor
    func testHandPinchTurnsAPartInTheTurnTool() async throws {
        let c = ViewerController()
        let v = orbitView(c)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("turn-box-\(UUID()).stl")
        try ViewerSelfCheck.binarySTL(ViewerSelfCheck.boxTriangles(SIMD3(10, 20, 30))).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await c.setParts([PartView(id: "a", url: url)])
        c.tool = .turn
        var saved: PartView?
        c.onPartMoved = { saved = $0 }
        SCNTransaction.flush()  // the app renders a frame here, a test has to commit by hand
        // Aim at the part's middle, as a stage fraction (top-left origin).
        let mid = v.projectPoint(SCNVector3(c.stage.position(of: "a")! + SIMD3(0, 15, 0)))
        let at = CGPoint(x: mid.x / 400, y: 1 - mid.y / 300)
        c.handDragBegan(at: at)
        // 70 points right is about 36 degrees, so 30 degrees clockwise: yaw 330.
        c.handDragged(to: at, by: CGVector(dx: 70.0 / 400, dy: 0))
        c.handDragEnded()
        XCTAssertEqual(c.selectedPartID, "a")
        XCTAssertEqual(saved?.yawDegrees ?? -1, 330, accuracy: 1e-6)
    }

    func testStagePointFlipsToAViewPoint() {
        let p = ViewerController.viewPoint(CGPoint(x: 0.25, y: 0.1), in: CGSize(width: 400, height: 300))
        XCTAssertEqual(p, CGPoint(x: 100, y: 270))
    }

    func testBedSpotSnapsTo5mmAndStaysOnTheBed() {
        // Scene -z is STL +y.
        XCTAssertEqual(ViewerController.bedSpot(sceneX: 12.4, sceneZ: -33), SIMD2(10, 35))
        XCTAssertEqual(ViewerController.bedSpot(sceneX: 400, sceneZ: 400), SIMD2(125, -125))
    }

    func testTurnSnapsTo15DegreesAndWraps() {
        let perStep = CGFloat(15 / TurnSnap.degreesPerPoint)
        XCTAssertEqual(TurnSnap.yaw(from: 0, draggedPoints: 0.4 * perStep), 0)
        XCTAssertEqual(TurnSnap.yaw(from: 0, draggedPoints: perStep), 345)
        XCTAssertEqual(TurnSnap.yaw(from: 350, draggedPoints: -2 * perStep), 15)
    }

    func testCutStrokeSnapsTo15DegreesAboutItsMiddle() {
        let (a, b) = CutStroke.snapped(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 6))
        XCTAssertEqual(a.y, b.y, accuracy: 1e-9)
        XCTAssertEqual((a.x + b.x) / 2, 50, accuracy: 1e-9)
        XCTAssertEqual((a.y + b.y) / 2, 3, accuracy: 1e-9)
        XCTAssertEqual(b.x - a.x, hypot(100, 6), accuracy: 1e-9)
        let (c, d) = CutStroke.snapped(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 48))
        XCTAssertEqual(atan2(d.y - c.y, d.x - c.x) * 180 / .pi, 45, accuracy: 1e-9)
    }

    func testPartViewFrameRoundTrip() {
        var p = PartView(id: "a", url: boxURL, x: 1, y: 2, z: 3)
        XCTAssertEqual(p.scenePosition, SIMD3(1, 3, -2))
        p.setScenePosition(SIMD3(4, 5, 6))
        XCTAssertEqual([p.x, p.y, p.z], [4, -6, 5])
    }
}
