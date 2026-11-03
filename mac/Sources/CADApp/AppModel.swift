import SwiftUI
import CADShared

/// The quick changes. Their text matches the canned scripts in bench/edit_cases.py, so they work with no key.
/// A `fill` idea only puts its words in the change field, because the kid has to finish them (a name, for example).
enum Ideas {
    struct Idea: Identifiable, Hashable {
        let group: String, short: String, label: String, symbol: String, text: String
        var fill = false
        var id: String { label }
    }
    /// Always shown. The rest sit behind More ideas so the panel stays short.
    static let groups = ["Size", "Add", "Cut", "Words"]
    static let moreGroups = ["Add parts", "Holders and stands", "Patterns", "Reshape"]

    /// Each group gets an icon for its header. Its soft colour comes from `Theme.tint(forGroup:)`.
    static func symbol(forGroup group: String) -> String {
        switch group {
        case "Size": "arrow.up.left.and.arrow.down.right"
        case "Add": "plus.square.on.square"
        case "Cut": "scissors"
        case "Words": "textformat"
        case "Add parts": "puzzlepiece"
        case "Holders and stands": "tray"
        case "Patterns": "circle.hexagongrid"
        default: "scribble.variable"
        }
    }

    static let all: [Idea] = [
        Idea(group: "Size", short: "Taller", label: "Make 20% taller", symbol: "arrow.up.and.down", text: "make it 20 percent taller"),
        Idea(group: "Size", short: "Half size", label: "Scale to half size", symbol: "arrow.down.right.and.arrow.up.left",
             text: "scale it down to half its size"),
        Idea(group: "Size", short: "Fit in a box", label: "Fit in a 40 by 30 by 20 mm box", symbol: "shippingbox",
             text: "make it fit in a box 40 by 30 by 20 mm"),
        Idea(group: "Add", short: "Base plate", label: "Add a base plate", symbol: "square.stack.3d.down.right",
             text: "add a flat base plate 3 mm thick that sticks out 5 mm on every side"),
        Idea(group: "Add", short: "Hole", label: "Add a centre hole", symbol: "circle.circle",
             text: "add a 6 mm hole straight down through the centre"),
        Idea(group: "Add", short: "Peg", label: "Add a peg on top", symbol: "cylinder",
             text: "add a round peg 10 mm wide and 15 mm tall on top, in the centre"),
        Idea(group: "Add", short: "Keyring loop", label: "Add a keyring loop", symbol: "key",
             text: "add a keyring loop on the right side"),
        Idea(group: "Cut", short: "Flat bottom", label: "Flatten the bottom", symbol: "rectangle.bottomhalf.filled",
             text: "cut the bottom 5 mm off so it sits flat"),
        Idea(group: "Cut", short: "Cut in half", label: "Cut in half", symbol: "scissors",
             text: "cut it in half and keep only the left half"),
        Idea(group: "Words", short: "Name on it", label: "Write your name on it", symbol: "textformat",
             text: "write this name on the front: ", fill: true),
        Idea(group: "Words", short: "Number 7", label: "Put the number 7 on top", symbol: "number",
             text: "put the number 7 on top"),
        Idea(group: "Words", short: "Carve HI", label: "Carve HI into the front", symbol: "pencil",
             text: "engrave HI on the front"),
        Idea(group: "Add parts", short: "Bunny ears", label: "Give it bunny ears", symbol: "hare", text: "give it bunny ears"),
        Idea(group: "Add parts", short: "Eyes", label: "Put two eyes on the front", symbol: "eyes",
             text: "put two eyes on the front"),
        Idea(group: "Add parts", short: "Wings", label: "Give it wings", symbol: "bird", text: "give it wings"),
        Idea(group: "Add parts", short: "Crown", label: "Give it a crown", symbol: "crown", text: "give it a crown"),
        Idea(group: "Add parts", short: "Donut hat", label: "Put a donut on its head", symbol: "smallcircle.filled.circle",
             text: "put a donut on its head"),
        Idea(group: "Add parts", short: "Arm", label: "Give it an arm on the right", symbol: "hand.raised",
             text: "give it an arm on the right"),
        Idea(group: "Add parts", short: "Star", label: "Put a star on top", symbol: "star", text: "put a star on top"),
        Idea(group: "Add parts", short: "Pyramid", label: "Put a pyramid on top", symbol: "pyramid",
             text: "put a pyramid on top"),
        Idea(group: "Holders and stands", short: "Hollow", label: "Make it hollow like a cup", symbol: "cup.and.saucer",
             text: "make it hollow inside"),
        Idea(group: "Holders and stands", short: "Lid", label: "Make a lid for it (a second part)",
             symbol: "rectangle.topthird.inset.filled", text: "make a lid for it"),
        Idea(group: "Holders and stands", short: "Handle", label: "Add a cup handle", symbol: "mug",
             text: "add a handle on the left like a cup"),
        Idea(group: "Holders and stands", short: "Coin slot", label: "Cut a coin slot in the top", symbol: "banknote",
             text: "cut a slot in the top so coins can go in"),
        Idea(group: "Holders and stands", short: "Round stand", label: "Put it on a round stand", symbol: "circle.bottomhalf.filled",
             text: "put it on a round stand"),
        Idea(group: "Holders and stands", short: "Legs", label: "Give it four little legs", symbol: "chair",
             text: "give it four little legs"),
        Idea(group: "Holders and stands", short: "Wall hanger", label: "Hang it on a nail on the wall", symbol: "pin",
             text: "make it so i can hang it on a nail on the wall"),
        Idea(group: "Patterns", short: "Carve heart", label: "Carve a heart into the top", symbol: "heart",
             text: "carve a heart into the top"),
        Idea(group: "Patterns", short: "Grooves", label: "Put grooves around it", symbol: "line.3.horizontal",
             text: "put grooves around it"),
        Idea(group: "Patterns", short: "Brick studs", label: "Put brick studs on top", symbol: "circle.grid.3x3",
             text: "put lego studs on top"),
        Idea(group: "Patterns", short: "Spikes", label: "Make the front spiky", symbol: "burst", text: "make the front spiky"),
        Idea(group: "Patterns", short: "Row of 3", label: "Make three in a row", symbol: "rectangle.split.3x1",
             text: "make three of them in a row"),
        Idea(group: "Patterns", short: "Mirror", label: "Make both sides match", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
             text: "make it symmetrical"),
        Idea(group: "Reshape", short: "Twist", label: "Twist it like a corkscrew", symbol: "tornado",
             text: "make it twist like a corkscrew"),
        Idea(group: "Reshape", short: "Pointy top", label: "Make the top narrower", symbol: "triangle",
             text: "make the top narrower like a cone"),
        Idea(group: "Reshape", short: "Chubby", label: "Make it chubby in the middle", symbol: "oval.portrait",
             text: "make it chubby in the middle"),
        Idea(group: "Reshape", short: "Smooth edges", label: "Round off the sharp edges", symbol: "app",
             text: "round off the sharp edges"),
        Idea(group: "Reshape", short: "Stronger", label: "Make thin bits stronger", symbol: "dumbbell",
             text: "make it stronger, the thin bits keep snapping"),
    ]
}

/// Files a kid can open or drop on the window.
enum ScanFiles {
    static let meshes = ["stl", "ply", "obj"]
    /// Turntable scanner SD card files: lines of x,y,z. The helper turns them into a mesh.
    static let turntable = ["txt", "csv"]
    static let videos = ["mov", "mp4", "m4v", "webm"]
    static func accepts(_ url: URL) -> Bool { (meshes + turntable + videos).contains(url.pathExtension.lowercased()) }
    /// Meshes and turntable files both arrive as a finished shape, so the processing screen treats them the same.
    static func source(_ url: URL) -> AppModel.Processing.Source {
        (meshes + turntable).contains(url.pathExtension.lowercased()) ? .mesh : .video
    }
}

/// A status message on the edit panel, or on the processing screen.
struct Note: Equatable {
    enum Kind { case good, bad, info }
    var kind: Kind
    var text: String
    var detail: String?
}

/// App-wide banner under the toolbar.
enum BannerKind: Equatable {
    case lostContact, modelLost, noInternet

    var text: String {
        switch self {
        case .lostContact: "Lost contact with the helper. Trying again."
        case .modelLost: "The app restarted and the model was lost. Scan again or use a sample model."
        case .noInternet: "Claude needs the internet. The example changes still work."
        }
    }
    var symbol: String {
        switch self {
        case .lostContact: "bolt.horizontal.circle"
        case .modelLost: "exclamationmark.triangle"
        case .noInternet: "wifi.slash"
        }
    }
    var isError: Bool { self == .lostContact }
}

@MainActor
final class AppModel: ObservableObject {
    enum Step: Int, CaseIterable { case scan, cleanUp, edit
        var title: String { ["Scan", "Process", "Edit"][rawValue] }
    }

    /// What the processing screen shows.
    struct Processing: Equatable {
        enum Stage: Int { case sending, building, ready }
        enum Source { case sample, video, mesh }
        var source: Source
        var stage: Stage = .sending
        var startedAt = Date()
        var failure: Note?
    }

    @Published var step: Step = .scan
    @Published private(set) var state: ModelState?
    @Published var processing: Processing?
    @Published private(set) var editStartedAt: Date?
    @Published var note: Note?
    @Published var banner: BannerKind?
    @Published private(set) var stlURL: URL?
    @Published private(set) var revision = 0
    @Published private(set) var lastChangeWasEdit = false
    @Published var connected = false
    /// Set when a file arrives while a model is open. The window asks before clearing it.
    @Published var pendingFile: URL?
    @Published var confirmNewScan = false
    @Published var draft = ""

    private(set) var api: BackendAPI
    let viewer = ViewerControl()
    private var pollTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var shownVersion: String?
    private var savedVersion: String?
    let builds = BuildLibrary()

    init(api: BackendAPI) { self.api = api }

    var isEditing: Bool { editStartedAt != nil }
    var hasModel: Bool { state?.status == .ready && !(state?.versions.isEmpty ?? true) }
    var canUndo: Bool { connected && !isEditing && (state?.versions.count ?? 0) > 1 && step == .edit }
    var canRedo: Bool { connected && !isEditing && !(state?.redo.isEmpty ?? true) && step == .edit }
    var canSave: Bool { connected && hasModel && step == .edit && !isEditing }

    // MARK: Helper life

    /// Called when the helper first answers, or answers again after lost contact.
    func helperIsUp(firstTime: Bool) async {
        connected = true
        if banner == .lostContact { banner = nil }
        guard let s = try? await api.status() else { return }
        state = s
        if firstTime {
            if s.status == .ready, !s.versions.isEmpty {
                step = .edit
                await refreshModel(afterEdit: false)
            } else if s.status == .processing {
                // A scan was still running when the app last closed. Keep watching it.
                processing = Processing(source: s.sample ? .sample : .video, stage: .building,
                                        startedAt: s.started.map { Date(timeIntervalSince1970: $0) } ?? Date())
                step = .cleanUp
                poll()
            }
            return
        }
        // Came back after lost contact. If the model is gone while we show it, go back to Scan.
        if step == .edit && s.status != .ready {
            step = .scan
            banner = .modelLost
            stlURL = nil
        } else if step == .edit {
            await refreshModel(afterEdit: false)
        }
    }

    func helperLost() {
        connected = false
        banner = .lostContact
    }

    // MARK: Scan

    func useSample() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sample.mov")
        FileManager.default.createFile(atPath: url.path, contents: Data())
        upload(url, source: .sample, deleteAfter: true)
    }

    func open(_ url: URL) {
        guard ScanFiles.accepts(url) else {
            note = Note(kind: .bad, text: "CADDIY opens STL, PLY and OBJ files, turntable scan files (TXT or CSV), and videos. This file is a different type.",
                        detail: url.lastPathComponent)
            return
        }
        if step == .edit && hasModel { pendingFile = url; return }
        upload(url, source: ScanFiles.source(url))
    }

    func confirmPendingFile() {
        guard let url = pendingFile else { return }
        pendingFile = nil
        upload(url, source: ScanFiles.source(url))
    }

    func scanFinished(_ video: URL) {
        let size = (try? video.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0 else {
            try? FileManager.default.removeItem(at: video)
            note = Note(kind: .bad, text: "The recording was empty. Start the scan again.")
            return
        }
        upload(video, source: .video, deleteAfter: true)
    }

    func backToScan() {
        pollTask?.cancel()
        processing = nil
        note = nil
        step = .scan
    }

    /// `deleteAfter` is for files the app made itself (camera recordings, the sample stand-in). Never for a kid's own file.
    private func upload(_ url: URL, source: Processing.Source, deleteAfter: Bool = false) {
        pollTask?.cancel()
        note = nil
        if banner == .modelLost { banner = nil }
        processing = Processing(source: source)
        step = .cleanUp
        lastChangeWasEdit = false
        pollTask = Task {
            defer { if deleteAfter { try? FileManager.default.removeItem(at: url) } }
            do {
                try await api.uploadScan(fileURL: url)
                processing?.stage = .building
                poll()
            } catch {
                fail(error)
            }
        }
    }

    private func poll() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                if let s = try? await api.status() {
                    state = s
                    switch s.status {
                    case .ready:
                        await refreshModel(afterEdit: false)
                        processing?.stage = .ready
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled, processing != nil {
                            processing = nil
                            step = .edit
                        }
                        return
                    case .error:
                        // The helper's error is a kid-sized reason (for example a turntable file with no points).
                        let why = s.error ?? "The scan could not be turned into a model."
                        processing?.failure = Note(kind: .bad, text: "\(why) Scan again, or use the sample model.",
                                                   detail: s.detail)
                        return
                    case .idle:
                        processing?.failure = Note(kind: .bad, text: "The helper lost the scan. Scan again, or use the sample model.")
                        return
                    case .processing: break
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func fail(_ error: Error) {
        let f = error as? APIFailure
        processing?.failure = Note(kind: .bad, text: f?.message ?? "The scan could not be sent to the helper.",
                                   detail: f?.detail ?? "\(error)")
    }

    // MARK: Edit

    /// A quick change: send it, or for a fill idea put the words in the field and put the cursor at the end.
    func pick(_ idea: Ideas.Idea) {
        draft = idea.text
        guard idea.fill else { send(idea.text); return }
        NotificationCenter.default.post(name: .focusChangeField, object: nil)
        DispatchQueue.main.async { (NSApp.keyWindow?.firstResponder as? NSTextView)?.moveToEndOfDocument(nil) }
    }

    func send(_ text: String) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isEditing else { show(Note(kind: .info, text: "The last change is still running.")); return }
        guard !instruction.isEmpty else { show(Note(kind: .info, text: "Describe a change first, or pick a quick change.")); return }
        note = nil
        editStartedAt = Date()
        Task {
            defer { editStartedAt = nil }
            do {
                state = try await api.edit(instruction: instruction)
                draft = ""
                await refreshModel(afterEdit: true)
                show(Note(kind: .good, text: "Change applied. Check the model, then save it."), fadeAfter: 6)
                if banner == .noInternet { banner = nil }
            } catch let f as APIFailure where f.isConnectionLost {
                // The banner takes over. Status tells us later if the edit landed.
            } catch let f as APIFailure {
                let canned = Ideas.all.contains { $0.text == instruction }
                let raw = (f.detail ?? "").lowercased()
                if !canned && (raw.contains("connection") || raw.contains("network")) { banner = .noInternet }
                show(Note(kind: .bad, text: f.message, detail: f.detail))
                if let s = try? await api.status() { state = s }
            } catch let e as URLError where e.code == .timedOut {
                show(Note(kind: .bad, text: "Claude is taking too long. Check the history before you try again.",
                          detail: "\(e)"))
            } catch {
                show(Note(kind: .bad, text: "That change did not work. Try wording it differently.", detail: "\(error)"))
            }
        }
    }

    func undo() { step { try await $0.undo() } }
    func redo() { step { try await $0.redo() } }

    private func step(_ call: @escaping (BackendAPI) async throws -> ModelState) {
        guard !isEditing else { return }
        Task {
            do {
                state = try await call(api)
                note = nil
                await refreshModel(afterEdit: false)
            } catch let f as APIFailure where !f.isConnectionLost {
                show(Note(kind: .bad, text: f.message, detail: f.detail))
            } catch {}
        }
    }

    /// Keeps the current build in My builds. `quiet` skips the thank-you note.
    @discardableResult func saveBuild(quiet: Bool = false) -> Bool {
        guard let stl = stlURL, hasModel else { return false }
        let last = state?.versions.last?.instruction ?? ""
        let words = last.isEmpty || last == "Your scan" ? "My scan" : String(last.prefix(30))
        do {
            try builds.save(stl, name: words.prefix(1).uppercased() + words.dropFirst())
            savedVersion = shownVersion
            if !quiet { show(Note(kind: .good, text: "Saved to My builds."), fadeAfter: 6) }
            return true
        } catch {
            show(Note(kind: .bad, text: "The build could not be saved.", detail: "\(error)"))
            return false
        }
    }

    /// Back to the start screen. A build with unsaved changes goes into My builds first, so nothing is lost.
    func goHome() {
        if hasModel && savedVersion != shownVersion { saveBuild(quiet: true) }
        let kept = hasModel
        newScan()
        if kept { show(Note(kind: .good, text: "Your build is saved in My builds."), fadeAfter: 8) }
    }

    func openBuild(_ item: BuildLibrary.Item) {
        guard !isEditing else { return }
        if hasModel && savedVersion != shownVersion { saveBuild(quiet: true) }
        upload(item.url, source: ScanFiles.source(item.url))
    }

    func newScan() {
        confirmNewScan = false
        stlURL = nil
        state = nil
        note = nil
        draft = ""
        step = .scan
    }

    func save() {
        guard let stl = stlURL else { return }
        do {
            guard let out = try saveModelCopy(stl) else { return }
            show(Note(kind: .good, text: "Saved \(out.lastPathComponent)."), fadeAfter: 8)
        } catch {
            show(Note(kind: .bad, text: "The file could not be saved. Try another folder.",
                      detail: "\(error)"))
        }
    }

    // MARK: Model file

    /// Downloads the current version to a local file the viewer can read. Skips it when nothing changed.
    private func refreshModel(afterEdit: Bool) async {
        guard let current = state?.versions.last?.file else { return }
        if current == shownVersion && stlURL != nil { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CADDIY", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("model-\(revision + 1).stl")
        do {
            try await api.downloadModel(to: url)
            if let old = stlURL { try? FileManager.default.removeItem(at: old) }
            shownVersion = current
            lastChangeWasEdit = afterEdit
            revision += 1
            stlURL = url
        } catch {}
    }

    private func show(_ n: Note, fadeAfter seconds: Double? = nil) {
        noteTask?.cancel()
        note = n
        guard let seconds else { return }
        noteTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled, note == n { note = nil }
        }
    }
}
