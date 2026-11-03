import Foundation
import CADShared

/// URLSession client for every endpoint in webapp/API.md.
public final class HTTPBackendAPI: BackendAPI, @unchecked Sendable {
    // The lock guards baseURL and onConnectionLost. BackendService may move the port after launch.
    private let lock = NSLock()
    private var _baseURL: URL
    private var _onConnectionLost: (@Sendable () -> Void)?
    private let session: URLSession

    static let normalTimeout: TimeInterval = 10
    static let editTimeout: TimeInterval = 150
    static let uploadTimeout: TimeInterval = 60

    public init(baseURL: URL = URL(string: "http://127.0.0.1:8000")!) {
        _baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.timeoutIntervalForResource = 600
        session = URLSession(configuration: config)
    }

    public var baseURL: URL {
        get { lock.withLock { _baseURL } }
        set { lock.withLock { _baseURL = newValue } }
    }

    /// Called on any connection failure. BackendService uses it to show "lost contact".
    public var onConnectionLost: (@Sendable () -> Void)? {
        get { lock.withLock { _onConnectionLost } }
        set { lock.withLock { _onConnectionLost = newValue } }
    }

    // MARK: BackendAPI

    public func status() async throws -> ModelState {
        try await json(request("GET", "/api/status"))
    }

    public func sendFrame(jpeg: Data) async throws -> GuidanceResult {
        var r = request("POST", "/api/guidance/frame")
        r.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        r.httpBody = jpeg
        return try await json(r)
    }

    public func resetGuidance() async throws {
        _ = try await data(request("POST", "/api/guidance/reset"))
    }

    public func uploadScan(fileURL: URL) async throws {
        // Build the multipart body in a temp file so a large video is streamed from disk.
        let boundary = "cad-\(UUID().uuidString)"
        let body = FileManager.default.temporaryDirectory.appendingPathComponent("cad-upload-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: body) }
        do {
            try writeMultipart(file: fileURL, boundary: boundary, to: body)
        } catch {
            throw APIFailure(message: "I could not read that file.", detail: error.localizedDescription)
        }
        var r = request("POST", "/api/scan", timeout: Self.uploadTimeout)
        r.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let (respData, resp) = try await perform { try await self.session.upload(for: r, fromFile: body) }
        try check(resp, respData)
    }

    public func edit(instruction: String) async throws -> ModelState {
        var r = request("POST", "/api/edit", timeout: Self.editTimeout)
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try JSONEncoder().encode(["instruction": instruction])
        return try await json(r)
    }

    public func undo() async throws -> ModelState { try await json(request("POST", "/api/undo")) }
    public func redo() async throws -> ModelState { try await json(request("POST", "/api/redo")) }

    public func downloadModel(to destination: URL) async throws {
        let r = request("GET", "/api/model.stl")
        let (tmp, resp) = try await perform { try await self.session.download(for: r) }
        defer { try? FileManager.default.removeItem(at: tmp) }
        try check(resp, (try? Data(contentsOf: tmp)) ?? Data())
        // Stage next to the destination so the final swap is a same-volume atomic rename.
        let fm = FileManager.default
        let staged = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).part")
        do {
            try fm.moveItem(at: tmp, to: staged)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: staged)
            } else {
                try fm.moveItem(at: staged, to: destination)
            }
        } catch {
            try? fm.removeItem(at: staged)
            throw APIFailure(message: "I could not save the model file.", detail: error.localizedDescription)
        }
    }

    // MARK: Plumbing

    private func request(_ method: String, _ path: String, timeout: TimeInterval = normalTimeout) -> URLRequest {
        var r = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: timeout)
        r.httpMethod = method
        return r
    }

    private func json<T: Decodable>(_ r: URLRequest) async throws -> T {
        let d = try await data(r)
        do {
            return try JSONDecoder().decode(T.self, from: d)
        } catch {
            throw APIFailure(message: "The app got an answer it did not understand.",
                             detail: "\(error)\n\(String(decoding: d.prefix(500), as: UTF8.self))")
        }
    }

    private func data(_ r: URLRequest) async throws -> Data {
        let (d, resp) = try await perform { try await self.session.data(for: r) }
        try check(resp, d)
        return d
    }

    /// Runs a URLSession call and turns transport errors into APIFailure.
    private func perform<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let e as URLError {
            if e.code == .cancelled { throw CancellationError() }
            if Self.lostCodes.contains(e.code) {
                onConnectionLost?()
                throw APIFailure(message: "Lost contact with the helper program. Trying again.",
                                 detail: e.localizedDescription, isConnectionLost: true)
            }
            throw APIFailure(message: "Something went wrong talking to the helper program.", detail: e.localizedDescription)
        }
    }

    static let lostCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .networkConnectionLost, .timedOut, .cannotFindHost,
        .notConnectedToInternet, .dnsLookupFailed, .badServerResponse,
    ]

    private func check(_ resp: URLResponse, _ body: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard http.statusCode >= 400 else { return }
        throw Self.failure(status: http.statusCode, body: body)
    }

    static func failure(status: Int, body: Data) -> APIFailure {
        struct Body: Decodable {
            struct Inner: Decodable { var message: String; var detail: String? }
            var detail: Inner
        }
        if let b = try? JSONDecoder().decode(Body.self, from: body) {
            return APIFailure(statusCode: status, message: b.detail.message, detail: b.detail.detail)
        }
        // FastAPI's own 422 has a list in detail. API.md says treat it as a client bug.
        return APIFailure(statusCode: status, message: "Something went wrong in the app.",
                          detail: "HTTP \(status): " + String(decoding: body.prefix(500), as: UTF8.self))
    }

    private func writeMultipart(file: URL, boundary: String, to out: URL) throws {
        let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
        let head = "--\(boundary)\r\nContent-Disposition: form-data; name=\"video\"; filename=\"\(name)\"\r\n"
            + "Content-Type: application/octet-stream\r\n\r\n"
        FileManager.default.createFile(atPath: out.path, contents: Data(head.utf8))
        let w = try FileHandle(forWritingTo: out)
        defer { try? w.close() }
        try w.seekToEnd()
        let r = try FileHandle(forReadingFrom: file)
        defer { try? r.close() }
        while let chunk = try r.read(upToCount: 1 << 20), !chunk.isEmpty {
            try w.write(contentsOf: chunk)
        }
        try w.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
