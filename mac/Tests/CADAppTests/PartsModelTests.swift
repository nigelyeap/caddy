import XCTest
import CADShared
import CADBackend
@testable import CADApp

@MainActor final class PartsModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("parts-\(UUID().uuidString)")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: dir) }

    private func ready() async -> (AppModel, MockBackendAPI) {
        let api = MockBackendAPI(delay: .zero)
        let model = AppModel(api: api, builds: BuildLibrary(dir: dir))
        await model.helperIsUp(firstTime: true)
        XCTAssertTrue(model.hasModel)
        return (model, api)
    }

    func testDecodingWithAndWithoutParts() throws {
        let old = #"{"status":"ready","error":null,"detail":null,"versions":[],"redo":[],"sample":false,"started":null,"engine":"stub"}"#
        let s = try JSONDecoder().decode(ModelState.self, from: Data(old.utf8))
        XCTAssertEqual(s.parts, [])
        XCTAssertNil(s.note)
        let new = #"{"status":"ready","error":null,"detail":null,"versions":[],"redo":[],"sample":false,"started":null,"engine":"stub","parts":[{"id":"a","name":"Cup","file":"p1.stl","x":1,"y":2,"z":0,"yaw":90}],"putAway":[],"note":"It is one piece"}"#
        let t = try JSONDecoder().decode(ModelState.self, from: Data(new.utf8))
        XCTAssertEqual(t.parts.first?.yaw, 90)
        XCTAssertEqual(t.note, "It is one piece")
    }

    func testToolsWorkOnASingleModel() async {
        let (m, _) = await ready()
        XCTAssertFalse(m.hasParts)
        await m.chooseTool(.look)
        XCTAssertFalse(m.hasParts)
        await m.chooseTool(.move)
        XCTAssertEqual(m.parts.count, 1)
        XCTAssertEqual(m.tool, .move)
        XCTAssertNotNil(m.selectedPart)
        await m.copySelected()
        XCTAssertEqual(m.parts.count, 2)
    }

    func testTurnAndLift() async {
        let (m, _) = await ready()
        await m.split()
        m.select(m.parts[0].id)
        await m.turnSelected(90)
        XCTAssertEqual(m.parts[0].yaw, 270)
        await m.turnSelected(-90)
        XCTAssertEqual(m.parts[0].yaw, 0)
        await m.liftSelected(10)
        XCTAssertEqual(m.parts[0].z, 10)
        await m.liftSelected(-30)
        XCTAssertEqual(m.parts[0].z, 0)
        await m.liftSelected(8)
        await m.dropSelected()
        XCTAssertEqual(m.parts[0].z, 0)
    }

    /// A hand drops a shape at a floor spot. The palette hit test finds the tile under the hand.
    func testHandAddsAShapeWhereItIsDropped() async {
        let (m, _) = await ready()
        await m.add("cube", at: SIMD2(-60, 35))
        XCTAssertEqual(m.parts.last.map { [$0.x, $0.y] }, [-60, 35])

        let size = CGSize(width: 800, height: 600)
        let c = HandPalette.centres(in: size)
        XCTAssertEqual(HandPalette.shape(at: CGPoint(x: c[1].x / 800, y: c[1].y / 600), in: size), "ball")
        XCTAssertNil(HandPalette.shape(at: CGPoint(x: 0.5, y: 0.2), in: size))
    }

    /// A drawn cut waits for a held pinch, and the hand hints follow the tool.
    func testHandHintsFollowTheToolAndCutWaitsForAHold() async {
        let (m, _) = await ready()
        await m.chooseTool(.turn)
        XCTAssertTrue(m.hands.hints.open.contains("turn"))
        XCTAssertFalse(m.hands.wantsHold)
        await m.chooseTool(.cut)
        m.cutDrawn(m.parts[0].id, CutPlaneValue(point: .zero, normal: SIMD3(1, 0, 0)))
        XCTAssertTrue(m.hands.wantsHold)
        m.cancelCut()
        XCTAssertFalse(m.hands.wantsHold)
    }

    func testTipBothAxesOnSingleModel() async {
        let (m, api) = await ready()
        XCTAssertFalse(m.hasParts)
        await m.tipSelected(90)
        XCTAssertEqual(m.parts.count, 1)
        let id = m.parts[0].id
        var calls = await api.partCalls
        // Front/back tips about screen right, so the sent axis is the viewer's right azimuth.
        let right = m.viewer.rightAzimuthDegrees
        XCTAssertEqual(calls.last, .tip(id: id, axis: right, degrees: 90))
        let before = m.state?.versions.count
        await m.tipSelected(-90, sideways: true)
        calls = await api.partCalls
        XCTAssertEqual(calls.last, .tip(id: id, axis: (right + 90).truncatingRemainder(dividingBy: 360), degrees: -90))
        XCTAssertEqual(m.state?.versions.count, (before ?? 0) + 1)
    }

    /// Each of resize, mirror and lay flat wraps a single model first, then adds exactly one version.
    func testResizeMirrorLayFlatWrapThenAddOneVersion() async {
        let jobs: [(String, (AppModel) async -> Void)] = [
            ("Resized", { await $0.resizeSelected(sx: 2, sy: 2, sz: 2) }),
            ("Mirrored", { await $0.mirrorSelected(sideways: true) }),
            ("Laid", { await $0.layFlatSelected() }),
        ]
        for (word, job) in jobs {
            let (m, api) = await ready()
            XCTAssertNil(m.selectedPart)
            let start = m.state?.versions.count ?? 0
            await job(m)
            let calls = await api.partCalls
            XCTAssertEqual(calls.count, 2, word)
            XCTAssertEqual(calls.first, .wrap, word)
            XCTAssertEqual(m.state?.versions.count, start + 2, word)
            await job(m)
            XCTAssertEqual(m.state?.versions.count, start + 3, word)
            XCTAssertTrue(m.state?.versions.last?.instruction.hasPrefix(word) ?? false, word)
        }
    }

    func testMirrorDirectionsUseDifferentAxes() async {
        let (m, api) = await ready()
        await m.mirrorSelected(sideways: true)
        let id = m.parts[0].id
        let right = m.viewer.rightAzimuthDegrees
        var calls = await api.partCalls
        XCTAssertEqual(calls.last, .mirror(id: id, axis: right))
        await m.mirrorSelected(sideways: false)
        calls = await api.partCalls
        XCTAssertEqual(calls.last, .mirror(id: id, axis: (right + 90).truncatingRemainder(dividingBy: 360)))
    }

    func testResizeSendsFactorsAndNeedsPick() async {
        let (m, api) = await ready()
        await m.split()
        let before = await api.partCalls.count
        await m.resizeSelected(sx: 2, sy: 1, sz: 0.5)
        await m.mirrorSelected(sideways: false)
        await m.layFlatSelected()
        XCTAssertEqual(m.cue?.moment, .pickPart)
        let after = await api.partCalls.count
        XCTAssertEqual(after, before, "nothing picked sends nothing")
        let id = m.parts[0].id
        m.select(id)
        await m.resizeSelected(sx: 2, sy: 1, sz: 0.5)
        let last = await api.partCalls.last
        XCTAssertEqual(last, .resize(id: id, sx: 2, sy: 1, sz: 0.5))
    }

    func testSelectedSizeReadsPartFile() async {
        let (m, _) = await ready()
        await m.split()
        m.select(m.parts[0].id)
        // The mock part is one triangle 10 mm by 10 mm, flat on the floor.
        let s = try! XCTUnwrap(m.selectedSize)
        XCTAssertEqual(s.x, 10, accuracy: 0.001)
        XCTAssertEqual(s.y, 10, accuracy: 0.001)
        XCTAssertEqual(s.z, 0, accuracy: 0.001)
    }

    func testSplitAddCopyPutAwayBringBack() async {
        let (m, _) = await ready()
        XCTAssertTrue(m.offerSplit)
        await m.split()
        XCTAssertEqual(m.parts.count, 2)
        XCTAssertEqual(m.partViews.count, 2)
        XCTAssertFalse(m.offerSplit)
        await m.add("cube")
        XCTAssertEqual(m.parts.last?.name, "Cube")
        m.select(m.parts[0].id)
        await m.copySelected()
        XCTAssertEqual(m.parts.count, 4)
        XCTAssertEqual(m.parts.last?.x, m.parts[0].x + 20)
        let gone = m.parts[1].id
        await m.putAway(gone)
        XCTAssertEqual(m.putAway.map(\.id), [gone])
        await m.bringBack(gone)
        XCTAssertTrue(m.putAway.isEmpty)
        XCTAssertEqual(m.parts.count, 4)
        XCTAssertEqual(m.cue?.moment, .added)
    }

    func testJoinAndRefusal() async {
        let (m, api) = await ready()
        await m.split()
        m.select(m.parts[0].id)
        m.select(m.parts[1].id, adding: true)
        XCTAssertEqual(m.selection.count, 2)
        await api.setFailNextJoin(true)
        await m.joinSelected()
        XCTAssertEqual(m.parts.count, 2)
        XCTAssertEqual(m.note?.text, "Push them together so they touch, then join.")
        await m.joinSelected()
        XCTAssertEqual(m.parts.map(\.name), ["Joined part"])
    }

    func testCutNeedsConfirm() async {
        let (m, api) = await ready()
        await m.split()
        let id = m.parts[0].id
        m.cutDrawn(id, CutPlaneValue(point: .zero, normal: SIMD3(0, 0, 1)))
        XCTAssertEqual(m.pendingCut?.normal, [0, 0, 1])
        let before = await api.partCalls.count
        XCTAssertEqual(before, 1, "drawing alone cuts nothing")
        await m.confirmCut()
        XCTAssertNil(m.pendingCut)
        XCTAssertEqual(m.parts.count, 3)
    }

    /// A new stroke dropped off every part takes the waiting cut and its "Cut here" bar with it.
    func testDroppedStrokeClearsTheWaitingCut() async {
        let (m, _) = await ready()
        await m.split()
        m.cutDrawn(m.parts[0].id, CutPlaneValue(point: .zero, normal: SIMD3(0, 0, 1)))
        XCTAssertNotNil(m.pendingCut)
        m.viewer.onCutDropped?()
        XCTAssertNil(m.pendingCut)
    }

    func testSendNeedsPickedPart() async {
        let (m, api) = await ready()
        await m.split()
        m.send("make it taller")
        XCTAssertEqual(m.note?.text, "Pick a part first. Click it on the stage or in My parts.")
        XCTAssertNil(m.editTask)
        let id = m.parts[1].id
        m.select(id)
        m.send("make it taller")
        await m.editTask?.value
        let sent = await api.lastEditPart
        XCTAssertEqual(sent, id)
    }

    func testSingleModelSendHasNoPart() async {
        let (m, api) = await ready()
        m.send("make it taller")
        await m.editTask?.value
        let sent = await api.lastEditPart
        XCTAssertNil(sent)
    }

    func testBakeThenOpenAsParts() async {
        let (m, _) = await ready()
        await m.split()
        let ok = await m.saveBuild(quiet: true)
        XCTAssertTrue(ok)
        let item = try! XCTUnwrap(m.builds.items.first)
        XCTAssertNotNil(item.sidecar)
        m.newScan()
        XCTAssertFalse(m.hasParts)
        await m.openBuild(item)
        XCTAssertEqual(m.parts.count, 2)
        XCTAssertEqual(m.step, .edit)
    }

    func testSingleSaveCopiesSTL() async {
        let (m, _) = await ready()
        let ok = await m.saveBuild(quiet: true)
        XCTAssertTrue(ok)
        let item = try! XCTUnwrap(m.builds.items.first)
        XCTAssertNil(item.sidecar)
    }
}
