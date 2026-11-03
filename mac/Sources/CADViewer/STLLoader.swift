import Foundation
import SceneKit
import simd

/// Facts about a model, read from the STL file. Sizes are in mm with z up.
public struct MeshInfo: Equatable, Sendable {
    /// Width (x), depth (y) and height (z) of the bounding box.
    public var sizeMM: SIMD3<Double>
    public var triangleCount: Int
    /// Only set when the mesh is watertight. An open mesh has no real volume.
    public var volumeMM3: Double?
    /// Every edge is shared by exactly two triangles.
    public var isWatertight: Bool

    public init(sizeMM: SIMD3<Double>, triangleCount: Int, volumeMM3: Double?, isWatertight: Bool) {
        self.sizeMM = sizeMM
        self.triangleCount = triangleCount
        self.volumeMM3 = volumeMM3
        self.isWatertight = isWatertight
    }
}

/// Why a file could not be read. `errorDescription` is written for kids.
public enum STLError: Error, Equatable, Sendable, LocalizedError {
    case unreadable(String)
    case empty
    case notSTL
    case truncated(expected: Int, actual: Int)
    case noTriangles
    case tooLarge(triangles: Int)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The shape file could not be opened."
        case .empty: return "The shape file is empty."
        case .notSTL: return "This file is not an STL shape file."
        case .truncated: return "The shape file is cut short. Try saving it again."
        case .noTriangles: return "The shape file has no shape in it."
        case .tooLarge: return "This shape is too big for the viewer."
        }
    }

    /// Raw text for the teacher.
    public var teacherDetail: String {
        switch self {
        case .unreadable(let why): return "Read failed: \(why)"
        case .empty: return "File has 0 bytes."
        case .notSTL: return "No binary STL header that matches the file size, and no 'solid' ASCII header."
        case .truncated(let e, let a): return "Binary STL header says \(e) bytes, file has \(a)."
        case .noTriangles: return "No valid triangles after skipping NaN and infinite values."
        case .tooLarge(let n): return "\(n) triangles. Limit is \(STLLoader.maxTriangles)."
        }
    }
}

/// Reads binary and ASCII STL. Pure Swift, safe to call off the main thread.
public enum STLLoader {
    public static let maxTriangles = 12_000_000
    /// Faces meeting at a sharper angle than this keep a hard edge. Softer joins are smoothed.
    public static let creaseAngleDegrees: Float = 40

    /// A welded, render-ready mesh in STL coordinates (mm, z up).
    public struct Mesh: Sendable {
        public var positions: [SIMD3<Float>]
        public var normals: [SIMD3<Float>]
        public var indices: [UInt32]
        public var boundsMin: SIMD3<Float>
        public var boundsMax: SIMD3<Float>
        public var info: MeshInfo
    }

    /// Loads off the main thread.
    public static func load(url: URL) async throws -> Mesh {
        try await Task.detached(priority: .userInitiated) { try parse(url: url) }.value
    }

    public static func parse(url: URL) throws -> Mesh {
        let data: Data
        do { data = try Data(contentsOf: url, options: .mappedIfSafe) } catch {
            throw STLError.unreadable(error.localizedDescription)
        }
        return try parse(data: data)
    }

    public static func parse(data: Data) throws -> Mesh {
        let corners = try readCorners(data)
        return try build(corners)
    }

    /// Reads only the facts, for callers that do not render.
    public static func info(url: URL) async throws -> MeshInfo { try await load(url: url).info }

    // MARK: Reading

    /// Three corners per triangle. Triangles with NaN or infinite values are dropped.
    static func readCorners(_ data: Data) throws -> [SIMD3<Float>] {
        if data.isEmpty { throw STLError.empty }
        if data.count >= 84 {
            let n = Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 80, as: UInt32.self) }.littleEndian)
            let expected = 84 + 50 * n
            // Exact size match wins, even when the header starts with "solid".
            if n > 0 && data.count == expected { return try readBinary(data, count: n) }
            if !looksASCII(data) {
                if n > 0 && data.count > expected { return try readBinary(data, count: n) }
                if n > 0 && n <= maxTriangles * 2 { throw STLError.truncated(expected: expected, actual: data.count) }
                throw STLError.notSTL
            }
        } else if !looksASCII(data) {
            throw STLError.notSTL
        }
        return try readASCII(data)
    }

    private static func looksASCII(_ data: Data) -> Bool {
        let head = data.prefix(512)
        guard let start = head.firstIndex(where: { !($0 == 32 || $0 == 9 || $0 == 10 || $0 == 13) }) else { return false }
        return head[start...].starts(with: Array("solid".utf8))
    }

    private static func readBinary(_ data: Data, count n: Int) throws -> [SIMD3<Float>] {
        if n > maxTriangles { throw STLError.tooLarge(triangles: n) }
        var out = [SIMD3<Float>]()
        out.reserveCapacity(n * 3)
        data.withUnsafeBytes { raw in
            for t in 0..<n {
                let base = 84 + t * 50 + 12   // skip the stored normal, we compute our own
                func v(_ k: Int) -> SIMD3<Float> {
                    let o = base + k * 12
                    return SIMD3(Float(bitPattern: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self).littleEndian),
                                 Float(bitPattern: raw.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self).littleEndian),
                                 Float(bitPattern: raw.loadUnaligned(fromByteOffset: o + 8, as: UInt32.self).littleEndian))
                }
                let a = v(0), b = v(1), c = v(2)
                if isFinite(a) && isFinite(b) && isFinite(c) {
                    out.append(a); out.append(b); out.append(c)
                }
            }
        }
        return out
    }

    /// Finds every "vertex x y z" line. Groups of three make a triangle. Tolerant of odd spacing and case.
    private static func readASCII(_ data: Data) throws -> [SIMD3<Float>] {
        var bytes = [UInt8](data)
        bytes.append(0)   // strtof needs a terminator
        var out = [SIMD3<Float>]()
        out.reserveCapacity(bytes.count / 40)
        var pending = [SIMD3<Float>]()
        var ok = true
        bytes.withUnsafeMutableBufferPointer { buf in
            let p = buf.baseAddress!
            let end = buf.count - 1
            var i = 0
            while i < end {
                // Match "vertex" at a word start.
                if (p[i] | 0x20) == UInt8(ascii: "v"), i + 6 <= end,
                   (i == 0 || p[i - 1] <= 32),
                   (p[i + 1] | 0x20) == UInt8(ascii: "e"), (p[i + 2] | 0x20) == UInt8(ascii: "r"),
                   (p[i + 3] | 0x20) == UInt8(ascii: "t"), (p[i + 4] | 0x20) == UInt8(ascii: "e"),
                   (p[i + 5] | 0x20) == UInt8(ascii: "x") {
                    var cursor = UnsafeMutablePointer<CChar>(OpaquePointer(p + i + 6))
                    var xyz = SIMD3<Float>()
                    for k in 0..<3 {
                        var next: UnsafeMutablePointer<CChar>? = nil
                        xyz[k] = strtof(cursor, &next)
                        guard let n = next, n != cursor else { ok = false; return }
                        cursor = n
                    }
                    pending.append(xyz)
                    if pending.count == 3 {
                        if isFinite(pending[0]) && isFinite(pending[1]) && isFinite(pending[2]) { out += pending }
                        pending.removeAll(keepingCapacity: true)
                        if out.count > maxTriangles * 3 { return }
                    }
                    i = UnsafeMutablePointer<UInt8>(OpaquePointer(cursor)) - p
                } else {
                    i += 1
                }
            }
        }
        if out.count > maxTriangles * 3 { throw STLError.tooLarge(triangles: out.count / 3) }
        if !ok && out.isEmpty { throw STLError.notSTL }
        return out
    }

    @inline(__always) private static func isFinite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    // MARK: Welding, normals, facts

    static func build(_ corners: [SIMD3<Float>]) throws -> Mesh {
        let triCount = corners.count / 3
        if triCount == 0 { throw STLError.noTriangles }

        // 1. Weld exact duplicate positions.
        var lookup = [SIMD3<Float>: UInt32](minimumCapacity: corners.count / 2)
        var points = [SIMD3<Float>]()
        points.reserveCapacity(corners.count / 2)
        var tri = [UInt32](repeating: 0, count: corners.count)
        for (i, c) in corners.enumerated() {
            if let k = lookup[c] { tri[i] = k } else {
                let k = UInt32(points.count)
                lookup[c] = k
                points.append(c)
                tri[i] = k
            }
        }
        lookup = [:]

        // 2. Face normals (length is twice the area), bounds and signed volume.
        var faceN = [SIMD3<Float>](repeating: .zero, count: triCount)
        var faceU = [SIMD3<Float>](repeating: .zero, count: triCount)
        var volume6 = 0.0
        var lo = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var hi = -lo
        for p in points { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        for f in 0..<triCount {
            let a = points[Int(tri[3 * f])], b = points[Int(tri[3 * f + 1])], c = points[Int(tri[3 * f + 2])]
            let n = simd_cross(b - a, c - a)
            faceN[f] = n
            let len = simd_length(n)
            faceU[f] = len > 0 ? n / len : .zero
            let ad = SIMD3<Double>(a), bd = SIMD3<Double>(b), cd = SIMD3<Double>(c)
            volume6 += simd_dot(ad, simd_cross(bd, cd))
        }

        // 3. Watertight: every edge used by exactly two faces, once in each direction.
        // The second rule means the faces agree on inside and outside, so the volume is right.
        // Key: low point (31 bits), high point (31 bits), direction (1 bit). Corners are capped at 36M.
        var edges = [UInt64]()
        edges.reserveCapacity(corners.count)
        for f in 0..<triCount {
            for k in 0..<3 {
                let u = tri[3 * f + k], w = tri[3 * f + (k + 1) % 3]
                edges.append(UInt64(min(u, w)) << 33 | UInt64(max(u, w)) << 1 | (u < w ? 1 : 0))
            }
        }
        edges.sort()
        var watertight = edges.count % 2 == 0
        var i = 0
        while watertight && i < edges.count {
            let a = edges[i], b = edges[i + 1]
            // A pair must share the edge, run opposite ways, and not be followed by a third use.
            if a >> 1 != b >> 1 || a == b || (i + 2 < edges.count && edges[i + 2] >> 1 == a >> 1) { watertight = false }
            i += 2
        }
        edges = []

        // 4. Faces around each point (compressed lists).
        var start = [Int32](repeating: 0, count: points.count + 1)
        for v in tri { start[Int(v) + 1] += 1 }
        for i in 0..<points.count { start[i + 1] += start[i] }
        var fill = start
        var around = [Int32](repeating: 0, count: tri.count)
        for (i, v) in tri.enumerated() {
            around[Int(fill[Int(v)])] = Int32(i / 3)
            fill[Int(v)] += 1
        }
        fill = []

        // 5. Per corner normal: sum of neighbour faces within the crease angle. Then share equal corners.
        let cosCrease = cos(creaseAngleDegrees * .pi / 180)
        var outPos = [SIMD3<Float>](), outNrm = [SIMD3<Float>]()
        outPos.reserveCapacity(points.count + points.count / 4)
        outNrm.reserveCapacity(points.count + points.count / 4)
        var head = [Int32](repeating: -1, count: points.count)   // first output vertex for a point
        var next = [Int32]()                                     // next output vertex for the same point
        next.reserveCapacity(points.count + points.count / 4)
        var indices = [UInt32](repeating: 0, count: tri.count)
        for i in 0..<tri.count {
            let v = Int(tri[i]), f = i / 3
            let mine = faceU[f]
            var n = SIMD3<Float>.zero
            for j in Int(start[v])..<Int(start[v + 1]) {
                let g = Int(around[j])
                if simd_dot(faceU[g], mine) >= cosCrease { n += faceN[g] }
            }
            let len = simd_length(n)
            n = len > 0 ? n / len : (simd_length(mine) > 0 ? mine : SIMD3(0, 0, 1))
            var k = head[v]
            while k >= 0 {
                if simd_dot(outNrm[Int(k)], n) > 0.9995 { break }
                k = next[Int(k)]
            }
            if k < 0 {
                k = Int32(outPos.count)
                outPos.append(points[v]); outNrm.append(n)
                next.append(head[v]); head[v] = k
            }
            indices[i] = UInt32(k)
        }

        let size = SIMD3<Double>(hi - lo)
        let info = MeshInfo(sizeMM: size, triangleCount: triCount,
                            volumeMM3: watertight ? abs(volume6) / 6 : nil, isWatertight: watertight)
        return Mesh(positions: outPos, normals: outNrm, indices: indices, boundsMin: lo, boundsMax: hi, info: info)
    }

    // MARK: SceneKit

    /// Wraps the arrays without repacking. SIMD3<Float> has a 16 byte stride.
    public static func makeGeometry(_ mesh: Mesh) -> SCNGeometry {
        let stride = MemoryLayout<SIMD3<Float>>.stride
        let pos = mesh.positions.withUnsafeBytes { Data($0) }
        let nrm = mesh.normals.withUnsafeBytes { Data($0) }
        let idx = mesh.indices.withUnsafeBytes { Data($0) }
        let vs = SCNGeometrySource(data: pos, semantic: .vertex, vectorCount: mesh.positions.count,
                                   usesFloatComponents: true, componentsPerVector: 3,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
        let ns = SCNGeometrySource(data: nrm, semantic: .normal, vectorCount: mesh.normals.count,
                                   usesFloatComponents: true, componentsPerVector: 3,
                                   bytesPerComponent: 4, dataOffset: 0, dataStride: stride)
        let el = SCNGeometryElement(data: idx, primitiveType: .triangles,
                                    primitiveCount: mesh.indices.count / 3, bytesPerIndex: 4)
        return SCNGeometry(sources: [vs, ns], elements: [el])
    }
}
