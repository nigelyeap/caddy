import SwiftUI
import Combine
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

    // MARK: Parts state. All empty for a single model.

    /// A cut line the kid drew, waiting for "Cut here". The plane is in the part's own file frame.
    struct PendingCut: Equatable { let id: String; let point: [Double]; let normal: [Double] }
    /// Something for Caddy to say on the stage. `n` makes the same moment fire twice.
    struct CaddyCue: Equatable { let moment: CaddyMoment; let n: Int }

    /// The parts as the viewer shows them, with local copies of their files.
    @Published private(set) var partViews: [PartPlacement] = []
    /// Picked part ids, in the order picked. Two or more can be stuck together.
    @Published private(set) var selection: [String] = []
    @Published var tool: PartTool = .look {
        didSet {
            guard tool != oldValue else { return }
            viewer.tool = tool
            if tool != .cut { pendingCut = nil }
            if tool == .move { say(.move) } else if tool == .cut { say(.cutHint) }
            updateHandHints()
        }
    }
    @Published private(set) var pendingCut: PendingCut? {
        didSet {
            if pendingCut == nil { viewer.clearCutLine() }
            updateHandHints()
        }
    }
    /// A parts call is running. Kept apart from isEditing so a quick move does not dim the stage.
    @Published private(set) var isWorking = false
    @Published var splitDismissed = false
    @Published var showAddShelf = false
    @Published private(set) var cue: CaddyCue?
    private var cueCount = 0
    private var partFiles: [String: URL] = [:]
    private var selectionSink: AnyCancellable?

    private(set) var api: BackendAPI
    let viewer = ViewerControl()
    /// Turns the model with a hand in front of the camera. A plain let, so the camera's many updates
    /// redraw only the hand views and never the whole edit screen.
    let hands = HandControls()
    /// Where hand pinches go first: the add palette, then the viewer.
    let handStage = HandStage()
    private var pollTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var shownVersion: String?
    private var savedVersion: String?
    let builds: BuildLibrary

    init(api: BackendAPI, builds: BuildLibrary? = nil) {
        self.api = api
        self.builds = builds ?? BuildLibrary()
        // A click on the stage picks one part, unless it is already part of a bigger pick.
        selectionSink = viewer.$selectedPartID.sink { [weak self] id in
            guard let self else { return }
            guard let id else { self.selection = []; return }
            if !self.selection.contains(id) { self.selection = [id] }
        }
        viewer.onPartMoved = { [weak self] p in
            Task { await self?.partAction(.move(id: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yawDegrees), cue: nil) }
        }
        viewer.onCut = { [weak self] id, plane in self?.cutDrawn(id, plane) }
        viewer.onCutDropped = { [weak self] in self?.cancelCut() }
        handStage.model = self
        hands.target = handStage
        updateHandHints()
    }

    /// The camera bubble's words follow the tool, and a drawn cut waits for a held pinch.
    private func updateHandHints() {
        hands.wantsHold = pendingCut != nil
        hands.hints = if pendingCut != nil {
            ("Pinch and hold still to cut here.", "Keep still...")
        } else {
            switch tool {
            case .look: ("Pinch and move to turn. Pinch a shape to add it.", "Turning! Open your hand to let go.")
            case .move: ("Pinch a part and move to slide it. Pinch a tool button to switch.", "Moving! Open your hand to put it down.")
            case .turn: ("Pinch a part and move sideways to turn it.", "Turning the part! Open your hand to stop.")
            case .cut: ("Pinch and draw a line across a part.", "Drawing! Open your hand to finish the line.")
            }
        }
    }

    var isEditing: Bool { editStartedAt != nil }
    var hasModel: Bool { state?.status == .ready && !(state?.versions.isEmpty ?? true) }
    var canUndo: Bool { connected && !isEditing && (state?.versions.count ?? 0) > 1 && step == .edit }
    var canRedo: Bool { connected && !isEditing && !(state?.redo.isEmpty ?? true) && step == .edit }
    var canSave: Bool { connected && hasModel && step == .edit && !isEditing }

    var parts: [ModelPart] { state?.parts ?? [] }
    var putAway: [ModelPart] { state?.putAway ?? [] }
    var hasParts: Bool { !parts.isEmpty }
    /// The one picked part. Plain-language changes go to it.
    var selectedPart: ModelPart? { selection.count == 1 ? parts.first { $0.id == selection[0] } : nil }
    var canChangeParts: Bool { connected && hasModel && step == .edit && !isEditing && !isWorking }
    /// Right after a scan, before any change, offer to break it into pieces.
    var offerSplit: Bool { hasModel && !hasParts && !splitDismissed && state?.versions.count == 1 }

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
            note = Note(kind: .bad, text: "CADDY opens STL, PLY and OBJ files, turntable scan files (TXT or CSV), and videos. This file is a different type.",
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
        resetParts()
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

    /// The running change, so tests can wait for it.
    private(set) var editTask: Task<Void, Never>?

    func send(_ text: String) {
        let instruction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isEditing else { show(Note(kind: .info, text: "The last change is still running.")); return }
        guard !instruction.isEmpty else { show(Note(kind: .info, text: "Describe a change first, or pick a quick change.")); return }
        guard !isWorking else { show(Note(kind: .info, text: "One moment, I am still moving parts.")); return }
        var part: String?
        if hasParts {
            guard let p = selectedPart else {
                show(Note(kind: .info, text: "Pick a part first. Click it on the stage or in My parts."))
                say(.pickPart)
                return
            }
            part = p.id
        }
        note = nil
        editStartedAt = Date()
        editTask = Task {
            defer { editStartedAt = nil }
            do {
                state = try await api.edit(instruction: instruction, part: part)
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
    /// A build of parts is baked by the helper: one merged STL plus a sidecar, so it reopens as parts.
    @discardableResult func saveBuild(quiet: Bool = false) async -> Bool {
        guard hasModel else { return false }
        let last = state?.versions.last?.instruction ?? ""
        let words = last.isEmpty || last == "Your scan" ? "My scan" : String(last.prefix(30))
        let name = words.prefix(1).uppercased() + words.dropFirst()
        do {
            if hasParts {
                _ = try await api.parts(.bake(path: builds.newURL(name: name).path))
                builds.reload()
            } else {
                guard let stl = stlURL else { return false }
                try builds.save(stl, name: name)
            }
            savedVersion = shownVersion
            if !quiet { show(Note(kind: .good, text: "Saved to My builds."), fadeAfter: 6) }
            return true
        } catch {
            let f = error as? APIFailure
            show(Note(kind: .bad, text: f?.message ?? "The build could not be saved.", detail: f?.detail ?? "\(error)"))
            return false
        }
    }

    /// Back to the start screen. A build with unsaved changes goes into My builds first, so nothing is lost.
    func goHome() async {
        if hasModel && savedVersion != shownVersion { await saveBuild(quiet: true) }
        let kept = hasModel
        newScan()
        if kept { show(Note(kind: .good, text: "Your build is saved in My builds."), fadeAfter: 8) }
    }

    func openBuild(_ item: BuildLibrary.Item) async {
        guard !isEditing, !isWorking else { return }
        if hasModel && savedVersion != shownVersion { await saveBuild(quiet: true) }
        guard item.sidecar != nil else { upload(item.url, source: ScanFiles.source(item.url)); return }
        // A build of parts: the helper reads the sidecar and hands back the parts.
        pollTask?.cancel()
        processing = nil
        note = nil
        do {
            let s = try await api.parts(.open(path: item.url.path))
            resetParts()
            state = s
            await refreshModel(afterEdit: false)
            savedVersion = shownVersion
            step = .edit
        } catch {
            let f = error as? APIFailure
            show(Note(kind: .bad, text: f?.message ?? "That build would not open.", detail: f?.detail ?? "\(error)"))
        }
    }

    // MARK: Parts

    func split() async { await partAction(.split, cue: .split) }
    func add(_ shape: String) async {
        showAddShelf = false
        await partAction(.add(name: shape), cue: .added)
    }
    /// Adds a shape at a floor spot, STL x and y in mm. Hands drop shapes this way.
    func add(_ shape: String, at spot: SIMD2<Double>) async {
        await partAction(.add(name: shape, x: spot.x, y: spot.y), cue: .added)
    }
    /// Picks a tool from the left bar. A single model becomes one part first, so Move and Cut have something to work on.
    func chooseTool(_ t: PartTool) async {
        if t != .look { await wrapIfNeeded() }
        tool = t
    }
    /// Two-finger swipe from the camera: right goes to the next tool, left to the one before.
    func cycleTool(_ direction: Int) {
        guard canChangeParts, pendingCut == nil else { return }
        let all = PartTool.order
        let i = all.firstIndex(of: tool) ?? 0
        Task { await chooseTool(all[(i + direction + all.count) % all.count]) }
    }
    private func wrapIfNeeded() async {
        guard !hasParts, canChangeParts, await partAction(.wrap, cue: nil) else { return }
        if let only = parts.first { select(only.id) }
    }
    /// Turns the picked part about its own centre. Positive is clockwise seen from above.
    func turnSelected(_ degrees: Double) async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        var yaw = (p.yaw - degrees).truncatingRemainder(dividingBy: 360)
        if yaw < 0 { yaw += 360 }
        await partAction(.move(id: p.id, x: p.x, y: p.y, z: p.z, yaw: yaw), cue: nil)
    }
    /// Tips the picked part as seen on screen. Positive leans the top toward you, or to the right when `sideways`.
    /// Front/back turns about screen right. Sideways turns about the axis pointing into the screen (right plus 90).
    func tipSelected(_ degrees: Double, sideways: Bool = false) async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.tip(id: p.id, axis: screenAzimuth(sideways ? 90 : 0), degrees: degrees), cue: nil)
    }
    /// Stretches the picked part by these factors along x, y and z.
    func resizeSelected(sx: Double, sy: Double, sz: Double) async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.resize(id: p.id, sx: sx, sy: sy, sz: sz), cue: nil)
    }
    /// Flips the picked part as seen on screen. Left to right uses screen right, front to back uses right plus 90.
    func mirrorSelected(sideways: Bool) async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.mirror(id: p.id, axis: screenAzimuth(sideways ? 0 : 90)), cue: nil)
    }
    func layFlatSelected() async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.layFlat(id: p.id), cue: nil)
    }
    private func screenAzimuth(_ extra: Double) -> Double {
        (viewer.rightAzimuthDegrees + extra).truncatingRemainder(dividingBy: 360)
    }
    /// Width (x), depth (y) and height (z) of the picked part in mm. A single model gives its whole size.
    var selectedSize: SIMD3<Double>? {
        if let p = selectedPart, let url = partViews.first(where: { $0.id == p.id })?.url {
            return partSizeMM(url: url, yaw: p.yaw)
        }
        guard !hasParts, let stlURL else { return nil }
        return partSizeMM(url: stlURL, yaw: 0)
    }
    /// Raises the picked part by `mm` (negative lowers it). Never below the floor.
    func liftSelected(_ mm: Double) async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.move(id: p.id, x: p.x, y: p.y, z: max(0, p.z + mm), yaw: p.yaw), cue: nil)
    }
    func dropSelected() async {
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.move(id: p.id, x: p.x, y: p.y, z: 0, yaw: p.yaw), cue: nil)
    }
    func copySelected() async {
        await wrapIfNeeded()
        guard let p = selectedPart else { say(.pickPart); return }
        await partAction(.duplicate(id: p.id), cue: .copied)
    }
    func putAway(_ id: String) async { await partAction(.delete(id: id), cue: .putAway) }
    func bringBack(_ id: String) async { await partAction(.restore(id: id), cue: .added) }
    func joinSelected() async {
        guard selection.count >= 2 else { say(.pickPart); return }
        await partAction(.join(ids: selection), cue: .joined)
    }

    /// Picks a part from the My parts list. `adding` toggles it in a bigger pick, for Stick together.
    func select(_ id: String, adding: Bool = false) {
        if adding {
            if let i = selection.firstIndex(of: id) { selection.remove(at: i) } else { selection.append(id) }
        } else {
            selection = [id]
        }
        viewer.selectedPartID = selection.last
    }

    func cutDrawn(_ id: String, _ plane: CutPlaneValue) {
        func list(_ v: SIMD3<Float>) -> [Double] { [Double(v.x), Double(v.y), Double(v.z)] }
        select(id)
        pendingCut = PendingCut(id: id, point: list(plane.point), normal: list(plane.normal))
        say(.cutReady)
    }

    func confirmCut() async {
        guard let c = pendingCut else { return }
        pendingCut = nil
        await partAction(.cut(id: c.id, point: c.point, normal: c.normal), cue: .cut)
    }

    func cancelCut() { pendingCut = nil }

    /// Runs one parts call and shows the result. A move skips the busy check so a quick drag is never lost.
    @discardableResult func partAction(_ action: PartAction, cue moment: CaddyMoment?) async -> Bool {
        let isMove = if case .move = action { true } else { false }
        guard !isEditing, isMove || !isWorking else { return false }
        isWorking = true
        defer { isWorking = false }
        do {
            let s = try await api.parts(action)
            state = s
            await refreshModel(afterEdit: false)
            if let moment { say(moment) }
            if let n = s.note { show(Note(kind: .info, text: n), fadeAfter: 8) }
            return true
        } catch let f as APIFailure where f.isConnectionLost {
            return false
        } catch {
            let f = error as? APIFailure
            show(Note(kind: .bad, text: f?.message ?? "That did not work. Try again.", detail: f?.detail ?? "\(error)"))
            say(.partFailed)
            // ponytail: a refused move stays where it was dropped on screen until the next change reloads parts.
            if let s = try? await api.status() { state = s; await refreshModel(afterEdit: false) }
            return false
        }
    }

    private func say(_ moment: CaddyMoment) {
        cueCount += 1
        cue = CaddyCue(moment: moment, n: cueCount)
    }

    private func resetParts() {
        selection = []
        viewer.selectedPartID = nil
        pendingCut = nil
        splitDismissed = false
        showAddShelf = false
        tool = .look
        partViews = []
        for url in partFiles.values { try? FileManager.default.removeItem(at: url) }
        partFiles = [:]
    }

    /// Fetches any part files not yet on disk. Keeps the old list if a download fails.
    private func refreshParts() async {
        let list = parts
        guard !list.isEmpty else {
            if !partViews.isEmpty { partViews = [] }
            if !selection.isEmpty { selection = [] }
            return
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CADDY/parts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var views: [PartPlacement] = []
        for p in list {
            // ponytail: part file names are taken as never reused within one helper session.
            var url = partFiles[p.file]
            if url == nil {
                let fresh = dir.appendingPathComponent(UUID().uuidString + ".stl")
                guard (try? await api.downloadPart(file: p.file, to: fresh)) != nil else { return }
                partFiles[p.file] = fresh
                url = fresh
            }
            views.append(PartPlacement(id: p.id, url: url!, x: p.x, y: p.y, z: p.z, yawDegrees: p.yaw))
        }
        if views != partViews { partViews = views }
        let kept = selection.filter { id in list.contains { $0.id == id } }
        if kept != selection { selection = kept; viewer.selectedPartID = kept.last }
    }

    func newScan() {
        resetParts()
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
        await refreshParts()
        guard let last = state?.versions.last?.file else { return }
        // A move changes no version, so the part spots are part of what is on screen.
        let current = last + parts.map { "|\($0.file)@\($0.x),\($0.y),\($0.z),\($0.yaw)" }.joined()
        if current == shownVersion && stlURL != nil { return }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CADDY", isDirectory: true)
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
