import AppKit
import SceneKit
import XCTest
import simd
@testable import CADViewer

/// Renders the stage to PNG files for a look by eye. Skipped unless CADDY_RENDER_DIR is set.
final class RenderCheckTests: XCTestCase {
    static func torus(major R: Float, minor r: Float, n: Int = 48, m: Int = 24) -> [ViewerSelfCheck.Tri] {
        func p(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let u = Float(i % n) / Float(n) * 2 * .pi, v = Float(j % m) / Float(m) * 2 * .pi
            return SIMD3((R + r * cos(v)) * cos(u), (R + r * cos(v)) * sin(u), r + r * sin(v))
        }
        var out = [ViewerSelfCheck.Tri]()
        for i in 0..<n { for j in 0..<m {
            out.append((p(i, j), p(i + 1, j), p(i + 1, j + 1)))
            out.append((p(i, j), p(i + 1, j + 1), p(i, j + 1)))
        } }
        return out
    }

    /// The live view feeds the last result back each frame, so sizing twice must change nothing.
    func testScreenSizedDoesNotGrowFrameToFrame() {
        var m = simd_float4x4(simd_quatf(angle: 0.6, axis: simd_normalize(SIMD3(1, 2, 3))))
        m.columns.3 = SIMD4(30, 40, 0, 1)
        let once = ViewerScene.screenSized(m, eye: .zero, perMM: 0.02)
        let twice = ViewerScene.screenSized(once, eye: .zero, perMM: 0.02)
        for i in 0..<3 {
            XCTAssertEqual(simd_length(SIMD3(once[i].x, once[i].y, once[i].z)), 1, accuracy: 1e-4)   // 50 mm away * 0.02
            XCTAssertEqual(simd_length(once[i] - twice[i]), 0, accuracy: 1e-5)
        }
        XCTAssertEqual(once.columns.3, m.columns.3)
    }

    /// A size tag is pushed straight out from the part's middle, clear of its own anchor, the same every frame.
    func testSizeTagPushesOutFromThePartAndDoesNotCreep() {
        let right = SIMD3<Float>(1, 0, 0), up = SIMD3<Float>(0, 1, 0), size = SIMD2<Float>(4, 1)
        let anchor = SIMD3<Float>(10, 0, 0)
        let p = ViewerScene.pushedOut(anchor, from: .zero, right: right, up: up, size: size)
        XCTAssertEqual(p.x, 10 + 2 + 0.2, accuracy: 1e-5)   // half the width plus a small gap
        XCTAssertEqual(p.y, 0, accuracy: 1e-5)
        let below = ViewerScene.pushedOut(SIMD3(0, -10, 0), from: .zero, right: right, up: up, size: size)
        XCTAssertEqual(below.y, -10 - 0.5 - 0.2, accuracy: 1e-5)   // half the height along the vertical
        // Seen end on, there is no way out, so it stays put.
        XCTAssertEqual(ViewerScene.pushedOut(SIMD3(0, 0, 5), from: .zero, right: right, up: up, size: size), SIMD3(0, 0, 5))
    }

    /// Rendering several frames leaves the tags beside the part and never lets them drift or grow.
    @MainActor func testSizeTagsHoldStillOverFrames() throws {
        let url = URL(fileURLWithPath: "/tmp/tagbox.stl")
        let s = ViewerScene()
        s.setParts([PartView(id: "a", url: url)], meshes: [url: try STLLoader.parse(data: ViewerSelfCheck.binarySTL(ViewerSelfCheck.boxTriangles(SIMD3(10, 20, 30))))])
        s.frame(animated: false)
        s.select("a")
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = s.scene
        r.pointOfView = s.cameraNode
        var clock = CACurrentMediaTime()
        func frame() { clock += 1.0 / 60; _ = r.snapshot(atTime: clock, with: CGSize(width: 200, height: 140), antialiasingMode: .none) }
        let tag = try XCTUnwrap(s.scene.rootNode.childNode(withName: "10 mm", recursively: true))
        frame(); frame()
        let at = tag.presentation.simdWorldPosition, scale = simd_length(tag.presentation.simdWorldTransform.columns.0)
        for _ in 0..<5 { frame() }
        XCTAssertEqual(simd_distance(tag.presentation.simdWorldPosition, at), 0, accuracy: 1e-3)
        XCTAssertEqual(simd_length(tag.presentation.simdWorldTransform.columns.0), scale, accuracy: 1e-3)
        XCTAssertGreaterThan(simd_distance(at, tag.simdWorldPosition), 0.5, "pushed off its anchor on the part edge")
    }

    /// Ruler numbers draw over the parts, so a part in front never hides them.
    @MainActor func testRulerNumbersDrawOverParts() throws {
        let s = ViewerScene()
        s.showRuler = true
        let n = try XCTUnwrap(s.scene.rootNode.childNode(withName: "50", recursively: true))
        XCTAssertEqual(n.geometry?.firstMaterial?.readsFromDepthBuffer, false)
    }

    /// Swapping a selected part's file keeps one outline, built from the new mesh.
    @MainActor func testOutlineFollowsSwappedMesh() throws {
        let a = URL(fileURLWithPath: "/tmp/a.stl"), b = URL(fileURLWithPath: "/tmp/b.stl")
        let s = ViewerScene()
        s.setParts([PartView(id: "d", url: a)], meshes: [a: try STLLoader.parse(data: ViewerSelfCheck.binarySTL(Self.torus(major: 20, minor: 8)))])
        s.select("d")
        s.setParts([PartView(id: "d", url: b, yawDegrees: 30)], meshes: [b: try STLLoader.parse(data: ViewerSelfCheck.binarySTL(Self.torus(major: 10, minor: 4)))])
        let mesh = s.parts["d"]!.childNodes.first!
        let outlines = mesh.childNodes.filter { $0.name == "outline" }
        XCTAssertEqual(outlines.count, 1)
        XCTAssertEqual(Float(outlines[0].geometry!.boundingBox.max.x), Float(mesh.geometry!.boundingBox.max.x), accuracy: 1e-3)
    }

    @MainActor func testRenderTagsOutlineAndRuler() throws {
        guard let dir = ProcessInfo.processInfo.environment["CADDY_RENDER_DIR"] else { throw XCTSkip("CADDY_RENDER_DIR not set") }
        let out = URL(fileURLWithPath: dir)
        // One renderer per scene that draws several frames, like the live view does, so anything that
        // builds up from frame to frame or caches shader values shows here too.
        var renderers: [ObjectIdentifier: SCNRenderer] = [:]
        var clock = CACurrentMediaTime()
        func save(_ s: ViewerScene, _ name: String) {
            let r = renderers[ObjectIdentifier(s)] ?? {
                let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
                r.scene = s.scene
                r.pointOfView = s.cameraNode
                s.scene.background.contents = NSColor(white: 0.93, alpha: 1)
                return r
            }()
            renderers[ObjectIdentifier(s)] = r
            var img = NSImage()
            for _ in 0..<5 {
                clock += 1.0 / 60
                img = r.snapshot(atTime: clock, with: CGSize(width: 1000, height: 700), antialiasingMode: .multisampling4X)
            }
            try? ModelExport.pngData(img)?.write(to: out.appendingPathComponent(name + ".png"))
        }
        let mugURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../Sources/CADApp/Resources/mug.stl").standardized
        let mug = try STLLoader.parse(url: mugURL)
        let big = try STLLoader.parse(data: ViewerSelfCheck.binarySTL(Self.torus(major: 20, minor: 8)))
        let half = try STLLoader.parse(data: ViewerSelfCheck.binarySTL(Self.torus(major: 10, minor: 4)))
        let bigURL = URL(fileURLWithPath: "/tmp/donut.stl"), halfURL = URL(fileURLWithPath: "/tmp/donut_half.stl")

        let s1 = ViewerScene()
        s1.setParts([PartView(id: "mug", url: mugURL)], meshes: [mugURL: mug])
        s1.frame(animated: false)
        s1.select("mug")
        s1.showRuler = true
        save(s1, "mug")
        s1.zoom(by: 0.4)
        save(s1, "mug_far")

        let s2 = ViewerScene()
        s2.setParts([PartView(id: "d", url: bigURL, x: 30, y: 20)], meshes: [bigURL: big])
        s2.frame(animated: false)
        s2.select("d")
        save(s2, "donut")
        s2.setParts([PartView(id: "d", url: halfURL, x: 30, y: 20, yawDegrees: 30)], meshes: [halfURL: half])
        save(s2, "donut_half")
    }
}
