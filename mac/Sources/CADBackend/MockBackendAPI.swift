import Foundation
import CADShared

/// Fake backend for previews and tests. Canned answers, optional delay and failure.
public actor MockBackendAPI: BackendAPI {
    public private(set) var state: ModelState
    public var delay: Duration
    /// When set, every call throws this.
    public var failure: APIFailure?
    private var frames = 0
    /// The part id the last edit was sent with, for tests.
    public private(set) var lastEditPart: String?
    /// Every parts call, in order, for tests.
    public private(set) var partCalls: [PartAction] = []
    private var nextID = 1
    /// Makes the next join refuse with a 400, like parts that do not touch.
    public var failNextJoin = false
    public func setFailNextJoin(_ on: Bool) { failNextJoin = on }

    public init(ready: Bool = true, delay: Duration = .milliseconds(200), failure: APIFailure? = nil) {
        state = Self.decode(ready ? Self.readyJSON : Self.idleJSON)
        self.delay = delay
        self.failure = failure
    }

    public func setFailure(_ f: APIFailure?) { failure = f }
    public func setDelay(_ d: Duration) { delay = d }

    public func status() async throws -> ModelState { try await gate(); return state }

    public func sendFrame(jpeg: Data) async throws -> GuidanceResult {
        try await gate()
        frames += 1
        var g: GuidanceResult = Self.decode(Self.guidanceJSON)
        let filled = min(12, frames / 2)
        g.coverage.sectors = (0..<12).map { $0 < filled ? 1 : 0 }
        g.coverage.pct = Double(filled) / 12 * 100
        g.t = Double(frames)
        return g
    }

    public func resetGuidance() async throws { try await gate(); frames = 0 }

    public func uploadScan(fileURL: URL) async throws {
        try await gate()
        let ext = fileURL.pathExtension.lowercased()
        let mesh = ["stl", "ply", "obj", "txt", "csv"].contains(ext)
        state.status = .ready
        state.sample = !mesh
        state.versions = [Self.version("v0.stl", mesh ? "Your scan" : "Sample cup")]
        state.redo = []
        state.parts = []
        state.putAway = []
        state.started = Date().timeIntervalSince1970
    }

    public func edit(instruction: String) async throws -> ModelState {
        try await edit(instruction: instruction, part: nil)
    }

    public func edit(instruction: String, part: String?) async throws -> ModelState {
        try await gate()
        lastEditPart = part
        if !state.parts.isEmpty && part == nil { throw APIFailure(statusCode: 400, message: "Pick a part first.") }
        if let part, let i = state.parts.firstIndex(where: { $0.id == part }) {
            state.parts[i].file = "\(part)-v\(state.versions.count).stl"
        }
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { throw APIFailure(statusCode: 400, message: "Type what you want to change.") }
        if state.versions.isEmpty { throw APIFailure(statusCode: 409, message: "There is no model yet. Scan something first.") }
        state.versions.append(Self.version("v\(state.versions.count).stl", text))
        state.redo = []
        return state
    }

    public func undo() async throws -> ModelState {
        try await gate()
        if state.versions.count > 1 { state.redo.append(state.versions.removeLast()) }
        return state
    }

    public func redo() async throws -> ModelState {
        try await gate()
        if let v = state.redo.popLast() { state.versions.append(v) }
        return state
    }

    /// A small stand-in for the real mesh work. Each change adds a history row like the helper does.
    public func parts(_ action: PartAction) async throws -> ModelState {
        try await gate()
        partCalls.append(action)
        state.note = nil
        func part(_ name: String, x: Double = 0) -> ModelPart {
            defer { nextID += 1 }
            return ModelPart(id: "p\(nextID)", name: name, file: "p\(nextID).stl", x: x)
        }
        func index(_ id: String) throws -> Int {
            guard let i = state.parts.firstIndex(where: { $0.id == id }) else {
                throw APIFailure(statusCode: 404, message: "I could not find that part.")
            }
            return i
        }
        var row = ""
        switch action {
        case .wrap:
            if state.parts.isEmpty { state.parts = [part("Model", x: 0)] }
            row = "Ready to move and cut"
        case .split:
            guard state.parts.isEmpty else { throw APIFailure(statusCode: 409, message: "This build is already in parts.") }
            state.parts = [part("Part 1", x: -20), part("Part 2", x: 20)]
            row = "Split into 2 parts"
        case let .move(id, x, y, z, yaw):
            let i = try index(id)
            state.parts[i].x = x; state.parts[i].y = y; state.parts[i].z = z; state.parts[i].yaw = yaw
            row = "Moved \(state.parts[i].name)"
        case let .tip(id, _, _):
            row = "Tipped \(state.parts[try index(id)].name)"
        case .resize(let id, _, _, _):
            row = "Resized \(state.parts[try index(id)].name)"
        case .mirror(let id, _):
            row = "Mirrored \(state.parts[try index(id)].name)"
        case .layFlat(let id):
            row = "Laid \(state.parts[try index(id)].name) flat"
        case .duplicate(let id):
            let old = state.parts[try index(id)]
            var copy = part(old.name + " 2", x: old.x + 20)
            copy.file = old.file
            state.parts.append(copy)
            row = "Copied \(old.name)"
        case .delete(let id):
            state.putAway.append(state.parts.remove(at: try index(id)))
            row = "Put away"
        case .restore(let id):
            guard let i = state.putAway.firstIndex(where: { $0.id == id }) else {
                throw APIFailure(statusCode: 404, message: "I could not find that part.")
            }
            state.parts.append(state.putAway.remove(at: i))
            row = "Brought back"
        case let .add(name, x, y):
            if state.parts.isEmpty, !state.versions.isEmpty { state.parts = [part("Model")] }
            var p = part(name.prefix(1).uppercased() + name.dropFirst(), x: x ?? 40)
            p.y = y ?? 0
            state.parts.append(p)
            row = "Added \(name)"
        case .join(let ids):
            guard ids.count >= 2 else { throw APIFailure(statusCode: 400, message: "Pick two parts to stick together.") }
            for id in ids { _ = try index(id) }
            if failNextJoin { failNextJoin = false; throw APIFailure(statusCode: 400, message: "Push them together so they touch, then join.") }
            state.parts.removeAll { ids.contains($0.id) }
            state.parts.append(part("Joined part"))
            row = "Stuck together"
        case .cut(let id, _, _):
            let old = state.parts.remove(at: try index(id))
            state.parts += [part(old.name + " A", x: old.x - 5), part(old.name + " B", x: old.x + 5)]
            row = "Cut \(old.name)"
        case .bake(let path):
            let url = URL(fileURLWithPath: path)
            try Self.triangleSTL().write(to: url, options: .atomic)
            guard !state.parts.isEmpty else { throw APIFailure(statusCode: 409, message: "There are no parts to save.") }
            let side = url.appendingPathExtension("parts")
            try FileManager.default.createDirectory(at: side, withIntermediateDirectories: true)
            try JSONEncoder().encode(["parts": state.parts, "putAway": state.putAway])
                .write(to: side.appendingPathComponent("parts.json"))
            return state
        case .open(let path):
            let side = URL(fileURLWithPath: path + ".parts/parts.json")
            guard let d = try? Data(contentsOf: side), let saved = try? JSONDecoder().decode([String: [ModelPart]].self, from: d),
                  let list = saved["parts"] else {
                throw APIFailure(statusCode: 400, message: "I could not open that build.")
            }
            state.status = .ready
            state.parts = list
            state.putAway = saved["putAway"] ?? []
            state.versions = [Self.version("v0.stl", "Your build")]
            state.redo = []
            return state
        }
        state.versions.append(Self.version("v\(state.versions.count).stl", row))
        state.redo = []
        return state
    }

    public func downloadPart(file: String, to destination: URL) async throws {
        try await gate()
        try Self.triangleSTL().write(to: destination, options: .atomic)
    }

    /// Writes a single triangle binary STL.
    public func downloadModel(to destination: URL) async throws {
        try await gate()
        if state.versions.isEmpty { throw APIFailure(statusCode: 404, message: "There is no model yet. Scan something first.") }
        try Self.triangleSTL().write(to: destination, options: .atomic)
    }

    static func triangleSTL() -> Data {
        var d = Data(count: 80)
        var count = UInt32(1).littleEndian
        d.append(Data(bytes: &count, count: 4))
        for f: Float32 in [0, 0, 1, 0, 0, 0, 10, 0, 0, 0, 10, 0] {
            var v = f.bitPattern.littleEndian
            d.append(Data(bytes: &v, count: 4))
        }
        d.append(Data(count: 2))
        return d
    }

    private func gate() async throws {
        try await Task.sleep(for: delay)
        if let failure { throw failure }
    }

    // ModelState and GuidanceResult have no public memberwise init, so build them from JSON.
    private static func version(_ file: String, _ instruction: String) -> ModelVersion {
        try! JSONDecoder().decode(ModelVersion.self, from: JSONEncoder().encode(["file": file, "instruction": instruction]))
    }

    private static func decode<T: Decodable>(_ s: String) -> T {
        try! JSONDecoder().decode(T.self, from: Data(s.utf8))
    }

    static let idleJSON = #"{"status":"idle","error":null,"detail":null,"versions":[],"redo":[],"sample":false,"started":null,"engine":"stub","parts":[],"putAway":[],"note":null}"#
    static let readyJSON = #"{"status":"ready","error":null,"detail":null,"versions":[{"file":"v0.stl","instruction":"Sample cup"}],"redo":[],"sample":true,"started":null,"engine":"stub","parts":[],"putAway":[],"note":null}"#
    static let guidanceJSON = #"{"blur":{"score":212.4,"ok":true},"light":{"mean":121.0,"clipped_pct":0.4,"ok":true,"issue":null},"tracking":{"match_ratio":0.8,"ok":true},"speed":{"value":12.5,"ok":true},"coverage":{"sectors":[0,0,0,0,0,0,0,0,0,0,0,0],"pct":0},"warnings":[],"t":0}"#
}
