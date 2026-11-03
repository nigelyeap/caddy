import AppKit
import Foundation
import simd

/// Assertion checks for the loader and the scene. Run it from `scripts/viewer_check.sh`.
/// Returns false and lists the failures when something is wrong.
public enum ViewerSelfCheck {
    /// - Parameters:
    ///   - files: STL files to load and time.
    ///   - pictureDirectory: if set, renders a PNG of each file there, for a look by eye.
    @MainActor
    public static func run(files: [URL] = [], pictureDirectory: URL? = nil, log: (String) -> Void = { print($0) }) -> Bool {
        var failures = [String]()
        func check(_ ok: Bool, _ what: String) {
            log((ok ? "ok    " : "FAIL  ") + what)
            if !ok { failures.append(what) }
        }
        func near(_ a: Double, _ b: Double, _ tol: Double = 1e-3) -> Bool { abs(a - b) <= tol * max(1, abs(b)) }

        // A 10 x 20 x 30 mm box: watertight, volume 6000, sharp edges keep 24 vertices.
        let box = boxTriangles(SIMD3(10, 20, 30))
        if let m = try? STLLoader.parse(data: binarySTL(box)) {
            check(m.info.triangleCount == 12, "binary box has 12 triangles")
            check(m.info.isWatertight, "binary box is watertight")
            check(near(m.info.volumeMM3 ?? 0, 6000), "binary box volume is 6000 mm3 (got \(m.info.volumeMM3 ?? -1))")
            check(m.info.sizeMM == SIMD3(10, 20, 30), "binary box size is 10 x 20 x 30")
            check(m.positions.count == 24, "box keeps hard edges, 24 vertices (got \(m.positions.count))")
        } else { check(false, "binary box parses") }

        if let m = try? STLLoader.parse(data: asciiSTL(box)) {
            check(m.info.triangleCount == 12 && m.info.isWatertight, "ASCII box parses and is watertight")
        } else { check(false, "ASCII box parses") }

        // Binary file whose header starts with "solid", as some exporters write.
        var solidHeader = binarySTL(box)
        solidHeader.replaceSubrange(0..<5, with: Array("solid".utf8))
        check((try? STLLoader.parse(data: solidHeader))?.info.triangleCount == 12, "binary file with a 'solid' header still reads as binary")

        // Open box: no volume.
        let open = Array(box.dropLast())
        if let m = try? STLLoader.parse(data: binarySTL(open)) {
            check(!m.info.isWatertight && m.info.volumeMM3 == nil, "open box is not watertight and has no volume")
        } else { check(false, "open box parses") }

        // Closed box with one face flipped: inside and outside disagree, so no trusted volume.
        var flipped = box
        flipped[0] = (box[0].0, box[0].2, box[0].1)
        check((try? STLLoader.parse(data: binarySTL(flipped)))?.info.isWatertight == false, "box with a flipped face is not watertight")

        // A sphere should be smooth: welded so each point has one normal.
        let sphere = sphereTriangles(radius: 20, rings: 24, segments: 48)
        if let m = try? STLLoader.parse(data: binarySTL(sphere)) {
            let points = 24 * 48 - 48 + 2
            check(m.positions.count == points, "sphere is welded and smooth, \(points) vertices (got \(m.positions.count))")
            check(m.info.isWatertight, "sphere is watertight")
            check(abs((m.info.volumeMM3 ?? 0) / (4.0 / 3 * .pi * 8000) - 1) < 0.02, "sphere volume within 2 percent")
        } else { check(false, "sphere parses") }

        // Bad files give typed errors and never crash.
        func err(_ d: Data) -> STLError? { do { _ = try STLLoader.parse(data: d); return nil } catch { return error as? STLError } }
        check(err(Data()) == .empty, "empty file gives .empty")
        check(err(Data("hello there, this is not a shape".utf8)) == .notSTL, "text file gives .notSTL")
        check(err(binarySTL(box).prefix(300)).map { if case .truncated = $0 { return true } else { return false } } ?? false,
              "cut short binary gives .truncated")
        check(err(Data("solid x\nendsolid x\n".utf8)) == .noTriangles, "ASCII with no facets gives .noTriangles")
        check(err(Data(repeating: 0, count: 84)) == .notSTL, "binary header with zero triangles gives .notSTL")
        var nan = binarySTL([(SIMD3(.nan, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0))])
        check(err(nan) == .noTriangles, "only NaN triangles gives .noTriangles")
        nan = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
        _ = err(nan)
        check(true, "random bytes do not crash")
        check(err(Data("solid x\n facet normal 0 0 1\n outer loop\n vertex 1 2\n".utf8)) != nil, "broken ASCII number does not crash")
        let huge = { var d = Data(count: 84); d.replaceSubrange(80..<84, with: withUnsafeBytes(of: UInt32(50_000_000).littleEndian) { Data($0) }); return d }()
        check(err(huge) != nil, "header claiming 50 million triangles is refused")

        // Speed on about 1 million triangles.
        let big = sphereTriangles(radius: 60, rings: 708, segments: 708)
        let bigData = binarySTL(big)
        let t0 = CFAbsoluteTimeGetCurrent()
        let bigMesh = try? STLLoader.parse(data: bigData)
        let dt = CFAbsoluteTimeGetCurrent() - t0
        check(bigMesh?.info.isWatertight == true, String(format: "%d triangle sphere parses in %.2f s", big.count, dt))
        if let bigMesh {
            let t1 = CFAbsoluteTimeGetCurrent()
            let stage = ViewerScene()
            stage.setModel(bigMesh, edit: false, animate: false)
            _ = stage.snapshot(size: CGSize(width: 800, height: 500))
            log(String(format: "info  1M triangle geometry plus first render: %.2f s", CFAbsoluteTimeGetCurrent() - t1))
        }

        for url in files {
            let t = CFAbsoluteTimeGetCurrent()
            do {
                let m = try STLLoader.parse(url: url)
                let i = m.info
                check(true, String(format: "%@: %d tris, %.1f x %.1f x %.1f mm, watertight %@, volume %@, %.3f s",
                                   url.lastPathComponent, i.triangleCount, i.sizeMM.x, i.sizeMM.y, i.sizeMM.z,
                                   i.isWatertight ? "yes" : "no", i.volumeMM3.map { String(format: "%.0f mm3", $0) } ?? "n/a",
                                   CFAbsoluteTimeGetCurrent() - t))
                if let dir = pictureDirectory {
                    let stage = ViewerScene()
                    stage.setModel(m, edit: false, animate: false)
                    let png = ModelExport.pngData(stage.snapshot(size: CGSize(width: 1200, height: 750)))
                    let out = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".png")
                    try png?.write(to: out)
                    check(png != nil, "rendered \(out.lastPathComponent)")
                }
            } catch {
                let e = error as? STLError
                log("info  \(url.lastPathComponent): \(e?.errorDescription ?? "") \(e?.teacherDetail ?? "\(error)")")
            }
        }

        log(failures.isEmpty ? "All viewer checks passed." : "\(failures.count) viewer checks failed.")
        return failures.isEmpty
    }

    // MARK: Test meshes

    typealias Tri = (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)

    static func binarySTL(_ tris: [Tri]) -> Data {
        var d = Data(count: 80)
        d.reserveCapacity(84 + tris.count * 50)
        withUnsafeBytes(of: UInt32(tris.count).littleEndian) { d.append(contentsOf: $0) }
        var rec = [Float](repeating: 0, count: 12)
        for t in tris {
            rec.replaceSubrange(3..<12, with: [t.0.x, t.0.y, t.0.z, t.1.x, t.1.y, t.1.z, t.2.x, t.2.y, t.2.z])
            rec.withUnsafeBytes { d.append(contentsOf: $0) }
            d.append(contentsOf: [0, 0])
        }
        return d
    }

    static func asciiSTL(_ tris: [Tri]) -> Data {
        var s = "solid test\n"
        for t in tris {
            s += "  facet normal 0 0 0\n    outer loop\n"
            for v in [t.0, t.1, t.2] { s += "      vertex \(v.x) \(v.y) \(v.z)\n" }
            s += "    endloop\n  endfacet\n"
        }
        return Data((s + "endsolid test\n").utf8)
    }

    static func boxTriangles(_ s: SIMD3<Float>) -> [Tri] {
        let p = (0..<8).map { i in SIMD3<Float>(i & 1 == 0 ? 0 : s.x, i & 2 == 0 ? 0 : s.y, i & 4 == 0 ? 0 : s.z) }
        let quads = [(0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)]
        return quads.flatMap { q in [(p[q.0], p[q.1], p[q.2]), (p[q.0], p[q.2], p[q.3])] }
    }

    /// UV sphere sitting on z = 0. Triangle count is 2 * segments * (rings - 1).
    static func sphereTriangles(radius r: Float, rings: Int, segments: Int) -> [Tri] {
        func pt(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let th = Float(i) / Float(rings) * .pi
            let ph = Float(j % segments) / Float(segments) * 2 * .pi
            if i == 0 { return SIMD3(0, 0, 2 * r) }
            if i == rings { return SIMD3(0, 0, 0) }
            return SIMD3(r * sin(th) * cos(ph), r * sin(th) * sin(ph), r + r * cos(th))
        }
        var out = [Tri]()
        out.reserveCapacity(2 * segments * rings)
        for i in 0..<rings {
            for j in 0..<segments {
                let a = pt(i, j), b = pt(i + 1, j), c = pt(i + 1, j + 1), d = pt(i, j + 1)
                if i != 0 { out.append((a, b, d)) }
                if i != rings - 1 { out.append((b, c, d)) }
            }
        }
        return out
    }
}
