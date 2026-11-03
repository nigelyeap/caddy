import Foundation

// Mirrors webapp/API.md. Keep names and shapes in sync with that file.

public struct ModelVersion: Codable, Hashable, Sendable {
    public var file: String
    public var instruction: String
}

public struct ModelState: Codable, Equatable, Sendable {
    public enum Status: String, Codable, Sendable { case idle, processing, ready, error }
    public var status: Status
    public var error: String?
    public var detail: String?
    public var versions: [ModelVersion]
    public var redo: [ModelVersion]
    public var sample: Bool
    public var started: Double?
    public var engine: String
    /// Empty means one model, the old way. Two or more means a build of parts.
    public var parts: [ModelPart]
    /// Parts the kid put away. They can come back.
    public var putAway: [ModelPart]
    /// A short friendly line from the helper, for example after a split.
    public var note: String?

    enum CodingKeys: String, CodingKey { case status, error, detail, versions, redo, sample, started, engine, parts, putAway, note }

    // Older helpers send no parts, so those keys are optional.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        versions = try c.decode([ModelVersion].self, forKey: .versions)
        redo = try c.decode([ModelVersion].self, forKey: .redo)
        sample = try c.decode(Bool.self, forKey: .sample)
        started = try c.decodeIfPresent(Double.self, forKey: .started)
        engine = try c.decode(String.self, forKey: .engine)
        parts = try c.decodeIfPresent([ModelPart].self, forKey: .parts) ?? []
        putAway = try c.decodeIfPresent([ModelPart].self, forKey: .putAway) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }
}

/// One part of a build. Millimetres and degrees, in the STL frame (z up).
public struct ModelPart: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var file: String
    public var x: Double
    public var y: Double
    public var z: Double
    public var yaw: Double
    public init(id: String, name: String, file: String, x: Double = 0, y: Double = 0, z: Double = 0, yaw: Double = 0) {
        self.id = id; self.name = name; self.file = file; self.x = x; self.y = y; self.z = z; self.yaw = yaw
    }
}

/// Everything the parts routes do. Each one answers with the full ModelState.
public enum PartAction: Sendable, Equatable {
    case split
    /// Turns a single model into one part. Does nothing if it already is parts.
    case wrap
    case move(id: String, x: Double, y: Double, z: Double, yaw: Double)
    /// Tips the part about a flat axis at `axis` degrees round from the STL x axis (90 is the y axis).
    /// Positive turns by the right hand rule about that axis. Rewrites its mesh.
    case tip(id: String, axis: Double, degrees: Double)
    /// Stretches the part along each world axis by these factors (0.05 to 20). Keeps its x, y, z.
    case resize(id: String, sx: Double, sy: Double, sz: Double)
    /// Flips the part across the upright plane facing `axis` degrees round from the STL x axis.
    case mirror(id: String, axis: Double)
    /// Turns the part onto its best flat side.
    case layFlat(id: String)
    case duplicate(id: String)
    case delete(id: String)
    case restore(id: String)
    /// A library shape. Without x and y (STL mm) it goes to the right of the other parts.
    case add(name: String, x: Double? = nil, y: Double? = nil)
    case join(ids: [String])
    /// The plane is in that part's own file frame.
    case cut(id: String, point: [Double], normal: [Double])
    /// Writes the merged STL at path plus a .parts sidecar.
    case bake(path: String)
    case open(path: String)
}

public struct GuidanceResult: Codable, Equatable, Sendable {
    public struct Blur: Codable, Equatable, Sendable { public var score: Double; public var ok: Bool }
    public struct Light: Codable, Equatable, Sendable {
        public var mean: Double; public var clipped_pct: Double; public var ok: Bool; public var issue: String?
    }
    public struct Tracking: Codable, Equatable, Sendable { public var match_ratio: Double; public var ok: Bool }
    public struct Speed: Codable, Equatable, Sendable { public var value: Double; public var ok: Bool }
    public struct Coverage: Codable, Equatable, Sendable {
        public var sectors: [Double]   // 12 values 0...1, clockwise from the top
        public var pct: Double         // 0...100
    }
    public var blur: Blur
    public var light: Light
    public var tracking: Tracking
    public var speed: Speed
    public var coverage: Coverage
    public var warnings: [String]
    public var t: Double
}

/// Error body from the server: {"detail": {"message", "detail"}}.
public struct APIFailure: Error, Sendable, LocalizedError {
    public var statusCode: Int?
    public var message: String          // plain words for the kid
    public var detail: String?          // raw text for the teacher
    public var isConnectionLost: Bool   // server unreachable, show the "lost contact" state
    public init(statusCode: Int? = nil, message: String, detail: String? = nil, isConnectionLost: Bool = false) {
        self.statusCode = statusCode; self.message = message; self.detail = detail; self.isConnectionLost = isConnectionLost
    }
    public var errorDescription: String? { message }
}

/// The only way UI modules talk to the Python service. CADBackend implements it.
/// Tests and previews can supply a fake.
public protocol BackendAPI: Sendable {
    func status() async throws -> ModelState
    func sendFrame(jpeg: Data) async throws -> GuidanceResult
    func resetGuidance() async throws
    /// Uploads a mesh (.stl .ply .obj) or a video file. Returns once the server accepted it, then poll status().
    func uploadScan(fileURL: URL) async throws
    /// Blocks until the edit finishes, often 5 to 40 seconds.
    func edit(instruction: String) async throws -> ModelState
    func undo() async throws -> ModelState
    func redo() async throws -> ModelState
    /// Downloads the current model as binary STL to destination.
    func downloadModel(to destination: URL) async throws
    /// `part` is the id of the part to change in a build. Nil changes the one model.
    func edit(instruction: String, part: String?) async throws -> ModelState
    func parts(_ action: PartAction) async throws -> ModelState
    /// Downloads one part file (GET /api/part/{file}) to destination.
    func downloadPart(file: String, to destination: URL) async throws
}

/// Fakes that predate parts keep working: they act like an old helper.
public extension BackendAPI {
    func edit(instruction: String, part: String?) async throws -> ModelState { try await edit(instruction: instruction) }
    func parts(_ action: PartAction) async throws -> ModelState {
        throw APIFailure(message: "This helper cannot do parts yet.")
    }
    func downloadPart(file: String, to destination: URL) async throws {
        throw APIFailure(message: "This helper cannot do parts yet.")
    }
}
