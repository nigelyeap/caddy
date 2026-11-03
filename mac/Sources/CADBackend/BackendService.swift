import AppKit
import Darwin
import Foundation
import CADShared

/// Starts, watches and stops the local Python server (webapp/app.py).
@MainActor
public final class BackendService: ObservableObject {
    public enum Phase: Equatable { case starting, running, lostContact, failed(String) }

    @Published public private(set) var phase: Phase = .starting
    /// True when a Claude key was found and handed to the server. False means only the example edits work.
    /// If an already running server was reused, this reflects the key file, not that server.
    @Published public private(set) var hasAPIKey = false
    public let api: BackendAPI

    /// Last lines of server output, for the teacher.
    public var diagnostics: String { logLines.joined(separator: "\n") }

    private let http: HTTPBackendAPI
    private let rootOverride: URL?
    private let keyFileOverride: URL?
    private let preferredPort: Int
    private var child: Process?
    private var keyPipe: Pipe?
    private var logLines: [String] = []
    private var partialLine = ""
    private var stopping = false
    private var restarts = 0
    private var pollTask: Task<Void, Never>?
    private var quitObserver: NSObjectProtocol?

    static let maxRestarts = 3
    static let startupTimeout: TimeInterval = 180   // the first `uv run` may install packages
    static let maxLogLines = 200

    /// The Python and packages that build_app.sh --bundle puts inside the app. Nil in a dev build.
    /// With it, the helper needs no uv and no project folder.
    nonisolated public static let bundledRuntime: URL? = {
        guard let r = Bundle.main.resourceURL?.appendingPathComponent("runtime") else { return nil }
        return FileManager.default.isExecutableFile(atPath: r.appendingPathComponent("python/bin/python3").path) ? r : nil
    }()
    /// Server code inside the packaged app, laid out like the project (webapp/, bench/).
    nonisolated public static var bundledServer: URL? {
        bundledRuntime.flatMap { _ in Bundle.main.resourceURL?.appendingPathComponent("server") }
    }
    /// ~/Library/Application Support/CADDIY. The packaged app keeps .env and saved models here.
    nonisolated public static var supportFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/CADDIY")
    }

    /// root defaults to the packaged server, else env CAD_TRAINING_ROOT, else ~/Documents/cad-training.
    /// keyFile defaults to supportFolder/.env when packaged, else root/.env. Tests pass a fake one.
    public init(root: URL? = nil, keyFile: URL? = nil, preferredPort: Int = 8000) {
        rootOverride = root
        keyFileOverride = keyFile
        self.preferredPort = preferredPort
        http = HTTPBackendAPI(baseURL: URL(string: "http://127.0.0.1:\(preferredPort)")!)
        api = http
        http.onConnectionLost = { [weak self] in
            Task { @MainActor in self?.connectionLost() }
        }
        quitObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    // MARK: Public

    public func start() async {
        stopping = false
        restarts = 0
        phase = .starting
        guard let (root, key) = await locate() else {
            phase = .failed("I could not find the CADDIY folder.")
            log("Set CAD_TRAINING_ROOT or put the project at ~/Documents/cad-training.")
            return
        }
        hasAPIKey = key != nil

        // Reuse a healthy server on the preferred port.
        http.baseURL = Self.url(preferredPort)
        if await healthy() {
            log("Using the server already running on port \(preferredPort).")
            phase = .running
            return
        }
        guard let port = Self.freePort(from: preferredPort) else {
            phase = .failed("No free port for the helper program.")
            return
        }
        http.baseURL = Self.url(port)
        await launchAndWait(root: root, port: port, key: key)
    }

    /// Stops the child server. Safe to call more than once. Blocks up to about 3 seconds.
    public func stop() {
        stopping = true
        pollTask?.cancel()
        pollTask = nil
        guard let p = child else { return }
        child = nil
        // Closing stdin makes the server shut itself down. SIGTERM covers uv as well.
        try? keyPipe?.fileHandleForWriting.close()
        keyPipe = nil
        if p.isRunning { p.terminate() }
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }

    // MARK: Launch

    private func launchAndWait(root: URL, port: Int, key: String?) async {
        let p = Process()
        let serve = ["uvicorn", "app:app", "--host", "127.0.0.1", "--port", String(port)]
        p.currentDirectoryURL = root.appendingPathComponent("webapp")
        var env = ProcessInfo.processInfo.environment
        if let runtime = Self.bundledRuntime {
            // Packaged app: its own Python, nothing from the user's shell.
            let python = runtime.appendingPathComponent("python/bin/python3")
            p.executableURL = python
            p.arguments = ["-m"] + serve
            for k in ["PYTHONHOME", "PYTHONPATH", "VIRTUAL_ENV", "PYTHONSTARTUP"] { env.removeValue(forKey: k) }
            env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
            env["CADDIY_PYTHON"] = python.path
            env["CADDIY_DATA_DIR"] = Self.supportFolder.appendingPathComponent("data").path
            env["PYTHONDONTWRITEBYTECODE"] = "1"   // the app is signed, so its folder must not change
            env["PYTHONNOUSERSITE"] = "1"
        } else {
            guard let uv = Self.findUV() else {
                phase = .failed("I could not find the uv program.")
                log("Install uv. Looked in /opt/homebrew/bin, ~/.local/bin, /usr/local/bin and PATH.")
                return
            }
            p.executableURL = uv
            p.arguments = ["run"] + serve
            // A GUI app has a short PATH. processing.py also calls `uv` by name.
            let extra = [uv.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
            env["PATH"] = (extra + [env["PATH"] ?? ""]).filter { !$0.isEmpty }.joined(separator: ":")
        }
        env["CAD_KEY_STDIN"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env.removeValue(forKey: "ANTHROPIC_API_KEY")   // the key only travels over stdin
        p.environment = env

        let input = Pipe()
        let output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        p.standardError = output
        output.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            let s = String(decoding: d, as: UTF8.self)
            Task { @MainActor in self?.append(s) }
        }
        p.terminationHandler = { [weak self] proc in
            let code = proc.terminationStatus
            Task { @MainActor in self?.childExited(proc, code: code) }
        }
        do {
            try p.run()
        } catch {
            phase = .failed("The helper program would not start.")
            log("Launch failed: \(error.localizedDescription)")
            return
        }
        child = p
        keyPipe = input
        log("Started server on port \(port), pid \(p.processIdentifier).")
        // First line is the key or empty. The pipe stays open: closing it tells the server to quit.
        try? input.fileHandleForWriting.write(contentsOf: Data(((key ?? "") + "\n").utf8))

        let deadline = Date().addingTimeInterval(Self.startupTimeout)
        while Date() < deadline {
            guard child === p, p.isRunning, !stopping else { return }
            if await healthy() {
                restarts = 0
                phase = .running
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        log("Server did not answer within \(Int(Self.startupTimeout)) s.")
        stop()
        stopping = false
        phase = .failed("The helper program did not start in time.")
    }

    private func childExited(_ p: Process, code: Int32) {
        log("Server exited with code \(code).")
        guard p === child, !stopping else { return }
        child = nil
        keyPipe = nil
        connectionLost()
    }

    /// Lost contact: poll every 3 s per API.md. Relaunch if our child is gone.
    private func connectionLost() {
        guard !stopping, pollTask == nil else { return }
        if case .failed = phase { return }
        phase = .lostContact
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if await self.healthy() {
                    self.phase = .running
                    self.restarts = 0
                    break
                }
                if self.child == nil || self.child?.isRunning == false {
                    self.restarts += 1
                    if self.restarts > Self.maxRestarts {
                        self.phase = .failed("The helper program keeps stopping.")
                        break
                    }
                    guard let (root, key) = await self.locate(),
                          let port = Self.freePort(from: self.preferredPort) else {
                        self.phase = .failed("The helper program could not restart.")
                        break
                    }
                    self.http.baseURL = Self.url(port)
                    self.hasAPIKey = key != nil
                    self.log("Restarting server (attempt \(self.restarts)).")
                    await self.launchAndWait(root: root, port: port, key: key)
                    if self.phase == .running { break }
                    if case .failed = self.phase { break }
                }
                try? await Task.sleep(for: .seconds(3))
            }
            self?.pollTask = nil
        }
    }

    private func healthy() async -> Bool {
        var r = URLRequest(url: http.baseURL.appendingPathComponent("/api/status"), timeoutInterval: 2)
        r.httpMethod = "GET"
        guard let (d, resp) = try? await URLSession.shared.data(for: r),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return (try? JSONDecoder().decode(ModelState.self, from: d)) != nil
    }

    // MARK: Log

    private func log(_ s: String) { append("[app] " + s + "\n") }

    private func append(_ s: String) {
        let parts = (partialLine + s).components(separatedBy: "\n")
        partialLine = parts.last ?? ""
        logLines.append(contentsOf: parts.dropLast())
        if logLines.count > Self.maxLogLines { logLines.removeFirst(logLines.count - Self.maxLogLines) }
    }

    // MARK: Helpers

    /// Finds the project and reads the key file off the main thread.
    /// The first touch of ~/Documents can block on the macOS privacy prompt, and the UI must keep drawing.
    private func locate() async -> (URL, String?)? {
        let rootOverride = rootOverride, keyFileOverride = keyFileOverride
        return await Task.detached(priority: .userInitiated) {
            guard let root = Self.projectRoot(rootOverride) else { return nil }
            let keyFolder = Self.bundledRuntime == nil ? root : Self.supportFolder
            return (root, Self.readKey(from: keyFileOverride ?? keyFolder.appendingPathComponent(".env")))
        }.value
    }

    nonisolated private static func projectRoot(_ rootOverride: URL?) -> URL? {
        let env = ProcessInfo.processInfo.environment["CAD_TRAINING_ROOT"]
        let root = rootOverride
            ?? bundledServer
            ?? env.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/cad-training")
        let app = root.appendingPathComponent("webapp/app.py")
        return FileManager.default.fileExists(atPath: app.path) ? root : nil
    }

    static func url(_ port: Int) -> URL { URL(string: "http://127.0.0.1:\(port)")! }

    static func findUV() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = ["/opt/homebrew/bin/uv", home + "/.local/bin/uv", "/usr/local/bin/uv"]
        paths += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/uv" }
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    /// Reads ANTHROPIC_API_KEY from a dotenv style file. Returns nil if missing or empty.
    nonisolated static func readKey(from file: URL) -> String? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        return parseKey(text)
    }

    nonisolated static func parseKey(_ text: String) -> String? {
        for raw in text.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") { line = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
            guard line.hasPrefix("ANTHROPIC_API_KEY") else { continue }
            let rest = line.dropFirst("ANTHROPIC_API_KEY".count).trimmingCharacters(in: .whitespaces)
            guard rest.hasPrefix("=") else { continue }
            var v = rest.dropFirst().trimmingCharacters(in: .whitespaces)
            if v.count >= 2, let q = v.first, q == "\"" || q == "'", v.last == q {
                v = String(v.dropFirst().dropLast())
            } else if let hash = v.range(of: " #") {
                v = String(v[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            // A newline inside the key would break the one line stdin protocol.
            v = v.filter { !$0.isNewline }
            return v.isEmpty ? nil : v
        }
        return nil
    }

    /// First port from `start` that we can bind on 127.0.0.1, trying ten ports.
    nonisolated static func freePort(from start: Int) -> Int? {
        (start..<start + 10).first(where: canBind)
    }

    nonisolated static func canBind(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        // Like uvicorn, ignore TIME_WAIT leftovers from a server that just stopped. A live listener still fails.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(UInt16(port).bigEndian)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }
}
