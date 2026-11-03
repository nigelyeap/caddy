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
}
