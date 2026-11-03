import AppKit
import CADShared
import SceneKit
import SwiftUI
import simd

/// Drives one viewer: loading, toggles, camera moves and pictures.
/// Pass the same controller to `ModelViewer`, `ViewerToolbar` and `SizeBadge`.
@MainActor
public final class ViewerController: ObservableObject {
    public enum Phase: Equatable {
        case empty
        case loading
        case ready
        case failed(message: String, detail: String)
    }

    @Published public private(set) var phase: Phase = .empty
    @Published public private(set) var info: MeshInfo?
    /// How far the size moved after the last change, in mm (x, y, z). Nil when under 0.5 mm or after a while.
    @Published public private(set) var sizeDelta: SIMD3<Double>?
    private var deltaTask: Task<Void, Never>?
    /// Size of one floor square in mm. Usually 10.
    @Published public private(set) var gridStepMM: Double = 10
    /// Seconds the last load took, file read to first frame ready.
    @Published public private(set) var lastLoadSeconds: Double?

    @Published public var showWireframe = false { didSet { stage.wireframe = showWireframe } }
    @Published public var newStage = true { didSet { stage.newStage = newStage } }
    @Published public var showGrid = true { didSet { stage.showGrid = showGrid } }
    /// Width, depth and height tags on the selected part, or on the only part.
    @Published public var showSizes = true { didSet { stage.showSizes = showSizes } }
    /// A mm ruler along the edges of the print bed.
    @Published public var showRuler = false { didSet { stage.showRuler = showRuler } }
    /// Lines a dragged part up with the others when it gets close. Holding Command while dragging skips it.
    @Published public var snapEnabled = true
    /// Keeps turning until the kid touches the model. Off with Reduce Motion.
    @Published public var autoRotate = false { didSet { applySpin() } }
    /// Counts turns of the model for the Caddy tour (one per drag).
    @Published public private(set) var orbitCount = 0

    lazy var stage = ViewerScene()
    weak var view: SCNView?
    private var loadedKey: LoadKey?
    private var spunOnce = false

    // MARK: Parts (prototype, not wired into the app screens yet)

    public enum Tool: Sendable { case look, move, cut, turn }
    /// Look orbits on any drag. Move slides a grabbed part and orbits on empty floor. Cut draws a cut line.
    /// Turn spins a grabbed part about its upright axis in 15 degree steps and orbits on empty floor.
    /// Picking and the Move and Cut tools only act on a build loaded with `parts`.
    @Published public var tool: Tool = .look
    @Published public var selectedPartID: String? {
        didSet { if stage.selectedID != selectedPartID { stage.select(selectedPartID) } }
    }
    /// The parts as last loaded, with any drags applied.
    @Published public private(set) var parts: [PartView] = []
    /// Called on mouse up after a drag really moved a part. The transform is in the STL frame.
    public var onPartMoved: ((PartView) -> Void)?
    /// Called when a cut stroke is let go over a part, or with a part selected. The plane is in that
    /// part's own STL file frame, ready for the server.
    public var onCut: ((_ partID: String, _ plane: Plane) -> Void)?
    /// Called when a cut stroke is let go without making a cut, so a cut still waiting goes with its line.
    public var onCutDropped: (() -> Void)?

    public init() {}

    /// Shows a build of many parts. Files already shown are not read again.
    public func setParts(_ list: [PartView]) async {
        await load(LoadKey(url: nil, revision: loadedKey?.revision ?? 0, parts: list), highlight: false)
    }

    func partTurned(_ id: String, to yawDegrees: Double) {
        guard let i = parts.firstIndex(where: { $0.id == id }) else { return }
        parts[i].yawDegrees = yawDegrees
        onPartMoved?(parts[i])
    }

    func partMoved(_ id: String, to p: SIMD3<Float>) {
        guard let i = parts.firstIndex(where: { $0.id == id }) else { return }
        parts[i].setScenePosition(p)
        stage.fitBounds()
        onPartMoved?(parts[i])
    }

    func cut(partID: String, worldPlane: Plane) {
        guard let node = stage.parts[partID] else { return }
        // The mesh child's frame is the STL file's own frame (z up, file coordinates).
        let mesh = node.geometry != nil ? node : (node.childNodes.first ?? node)
        onCut?(partID, worldPlane.applying(mesh.simdWorldTransform.inverse))
    }

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: Camera

    public func resetView() {
        stopAutoRotate()
        stage.frame(animated: !Self.reduceMotion)
    }

    /// Positive turns the model to the right.
    public func turn(degrees: Double) {
        orbitCount += 1
        stopAutoRotate()
        stage.orbit(dYaw: Float(-degrees * .pi / 180), dPitch: 0, animated: !Self.reduceMotion)
    }

    /// Which way screen right points on the floor, in degrees round from the STL x axis toward y.
    /// The camera's yaw turns its right from scene x (cos t, 0, -sin t), which is STL (cos t, sin t, 0).
    public var rightAzimuthDegrees: Double {
        let d = Double(stage.yaw) * 180 / .pi
        let r = d.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Positive tilts the top towards you.
    public func tilt(degrees: Double) {
        orbitCount += 1
        stopAutoRotate()
        stage.orbit(dYaw: 0, dPitch: Float(-degrees * .pi / 180), animated: !Self.reduceMotion)
    }

    /// Above 1 moves closer. Use 1.25 for Cmd plus and 0.8 for Cmd minus.
    public func zoom(by factor: Double) {
        stopAutoRotate()
        stage.zoom(by: Float(factor), animated: !Self.reduceMotion)
    }

    /// A picture of what the viewer shows now, at twice the view size for crisp prints.
    public func snapshot() -> NSImage {
        let size = view.map { CGSize(width: $0.bounds.width * 2, height: $0.bounds.height * 2) } ?? .zero
        return stage.snapshot(size: size.width > 0 ? size : CGSize(width: 1600, height: 1000))
    }

    /// Where the model sits on screen, as a rect in top-left view points, so overlays can step aside.
    /// Uses the projected bounding box, so it errs a little on the side of "covered".
    public func modelRect() -> CGRect? {
        guard let v = view, stage.hasModel, v.bounds.width > 0 else { return nil }
        let pts = stage.modelCorners.map { v.projectPoint(SCNVector3($0)) }
        guard let x0 = pts.map(\.x).min(), let x1 = pts.map(\.x).max(),
              let y0 = pts.map(\.y).min(), let y1 = pts.map(\.y).max() else { return nil }
        return CGRect(x: x0, y: v.bounds.height - y1, width: x1 - x0, height: y1 - y0)
    }

    func userTouched() { stopAutoRotate() }
    func userOrbited() { orbitCount += 1 }

    // MARK: Hand control

    // A pinch goes down the same press, drag and release path as the mouse, so it acts through the tool.
    private var orbitView: OrbitSCNView? { view as? OrbitSCNView }
    /// Where the pinch is now, in view points.
    private var handPoint: CGPoint = .zero

    /// A stage fraction (top-left origin) as a SceneKit view point (bottom-left origin).
    nonisolated static func viewPoint(_ p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }

    /// A pinch starting at a stage point. Acts like a mouse press there.
    public func handDragBegan(at point: CGPoint) {
        guard let v = orbitView else { return }
        handPoint = Self.viewPoint(point, in: v.bounds.size)
        v.press(at: handPoint)
    }

    /// The hand moved to `point`. `fraction` of the view, right and down positive, turns the camera like
    /// a mouse drag of the same length. Parts and cut lines follow `point` itself.
    public func handDragged(to point: CGPoint, by fraction: CGVector) {
        guard let v = orbitView else { return }
        handPoint = Self.viewPoint(point, in: v.bounds.size)
        v.drag(to: handPoint, by: CGVector(dx: fraction.dx * v.bounds.width, dy: fraction.dy * v.bounds.height))
    }

    public func handDragEnded() { orbitView?.release(at: handPoint) }

    /// A held pinch does nothing in the viewer itself. The app confirms a cut with it.
    public func handHeld() {}

    /// Takes the drawn cut line off the stage, once the cut is done or dropped.
    public func clearCutLine() { stage.showCutLine(nil) }

    /// Where a stage point lands on the floor, as STL x and y in mm, snapped to 5 mm and kept on the bed.
    /// Nil when it points above the horizon.
    public func floorSpot(at point: CGPoint) -> SIMD2<Double>? {
        guard let v = orbitView else { return nil }
        let r = v.ray(Self.viewPoint(point, in: v.bounds.size))
        guard let hit = Plane(point: .zero, normal: SIMD3(0, 1, 0)).intersect(origin: r.origin, direction: r.direction) else { return nil }
        return Self.bedSpot(sceneX: Double(hit.x), sceneZ: Double(hit.z))
    }

    /// Scene floor x and z to STL x and y, snapped to `step` mm and kept on the bed.
    nonisolated static func bedSpot(sceneX: Double, sceneZ: Double, step: Double = 5) -> SIMD2<Double> {
        let half = Double(ViewerScene.bedHalf)
        func snap(_ v: Double) -> Double { min(max((v / step).rounded() * step, -half), half) }
        return SIMD2(snap(sceneX), snap(-sceneZ))
    }

    /// Above 1 moves closer.
    public func handZoomed(by factor: CGFloat) {
        userTouched()
        stage.zoom(by: Float(factor))
    }

    private func stopAutoRotate() {
        stage.stopSpin()
        if autoRotate { autoRotate = false }
    }

    private func applySpin() {
        if autoRotate && !Self.reduceMotion { stage.startSpin(forever: true) } else { stage.stopSpin() }
    }

    // MARK: Loading

    struct LoadKey: Equatable { var url: URL?; var revision: Int; var parts: [PartView]? = nil }

    func load(_ key: LoadKey, highlight: Bool) async {
        guard key != loadedKey else { return }
        if let list = key.parts { return await loadParts(list, key) }
        guard let url = key.url else {
            stage.clearModel(); info = nil; phase = .empty; loadedKey = key
            return
        }
        // Keep showing the old model while the new one loads.
        if !stage.hasModel { phase = .loading }
        let started = CFAbsoluteTimeGetCurrent()
        do {
            let mesh = try await STLLoader.load(url: url)
            if Task.isCancelled { return }
            // Any reload while a shape is showing is treated as an edit, so the camera stays put.
            let isEdit = stage.hasModel
            let calm = Self.reduceMotion
            stage.setModel(mesh, edit: isEdit, animate: !calm && stage.hasModel, reverse: !(highlight && isEdit))
            loadedKey = key
            if isEdit, let before = info?.sizeMM {
                let d = mesh.info.sizeMM - before
                sizeDelta = max(abs(d.x), abs(d.y), abs(d.z)) >= 0.5 ? d : nil
                deltaTask?.cancel()
                deltaTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(8))
                    if !Task.isCancelled { self?.sizeDelta = nil }
                }
            }
            info = mesh.info
            gridStepMM = stage.gridStepMM
            phase = .ready
            lastLoadSeconds = CFAbsoluteTimeGetCurrent() - started
            if autoRotate {
                applySpin()
            } else if !spunOnce && !calm {
                // One slow turn on first open, as the spec asks.
                spunOnce = true
                stage.startSpin(forever: false)
            }
        } catch is CancellationError {
            return
        } catch let e as STLError {
            fail(e.errorDescription ?? "", e.teacherDetail, key)
        } catch {
            fail("The shape file could not be opened.", error.localizedDescription, key)
        }
    }

    private func loadParts(_ list: [PartView], _ key: LoadKey) async {
        if !stage.hasModel { phase = .loading }
        do {
            var meshes = [URL: STLLoader.Mesh]()
            for url in Set(list.map(\.url)) where !stage.hasGeometry(for: url) {
                meshes[url] = try await STLLoader.load(url: url)
            }
            if Task.isCancelled { return }
            let first = !stage.isMultiPart
            stage.setParts(list, meshes: meshes)
            if first { stage.frame(animated: false) }
            parts = list
            if let s = selectedPartID, stage.parts[s] == nil { selectedPartID = nil }
            // ponytail: no size badge for a build. Add the whole build's or the selected part's size when wired in.
            info = nil
            loadedKey = key
            gridStepMM = stage.gridStepMM
            phase = .ready
        } catch is CancellationError {
            return
        } catch let e as STLError {
            fail(e.errorDescription ?? "", e.teacherDetail, key)
        } catch {
            fail("The shape file could not be opened.", error.localizedDescription, key)
        }
    }

    private func fail(_ message: String, _ detail: String, _ key: LoadKey) {
        loadedKey = key
        phase = .failed(message: message, detail: detail)
    }
}

/// The 3D view of the kid's model. Bump `revision` to reload the same file after an edit.
public struct ModelViewer: View {
    private let stlURL: URL?
    private let revision: Int
    private let highlightChange: Bool
    private let external: ViewerController?
    @StateObject private var own = ViewerController()

    public init(stlURL: URL?, revision: Int, highlightChange: Bool = true, controller: ViewerController? = nil) {
        self.stlURL = stlURL
        self.revision = revision
        self.highlightChange = highlightChange
        self.external = controller
    }

    /// A build of many parts. Pass a controller to pick a tool and hear about moves and cuts.
    public init(parts: [PartView], controller: ViewerController? = nil) {
        self.stlURL = nil
        self.revision = 0
        self.highlightChange = false
        self.external = controller
        self.parts = parts
    }

    private var parts: [PartView]?

    public var body: some View {
        ViewerContent(controller: external ?? own, key: .init(url: stlURL, revision: revision, parts: parts), highlight: highlightChange)
    }
}

/// One part of a build: its mesh file and where its bottom centre sits.
/// Millimetres in the STL frame (z up). Yaw in degrees about z.
public struct PartView: Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var url: URL
    public var x: Double
    public var y: Double
    public var z: Double
    public var yawDegrees: Double

    public init(id: String, url: URL, x: Double = 0, y: Double = 0, z: Double = 0, yawDegrees: Double = 0) {
        self.id = id; self.url = url; self.x = x; self.y = y; self.z = z; self.yawDegrees = yawDegrees
    }

    /// STL (x, y, z) is SceneKit (x, z, -y).
    var scenePosition: SIMD3<Float> { SIMD3(Float(x), Float(z), Float(-y)) }

    mutating func setScenePosition(_ p: SIMD3<Float>) {
        x = Double(p.x); y = Double(-p.z); z = Double(p.y)
    }
}

private struct ViewerContent: View {
    @ObservedObject var controller: ViewerController
    let key: ViewerController.LoadKey
    let highlight: Bool

    var body: some View {
        ZStack {
            // The scene draws on clear, so the stage gradient and confetti sit behind the model.
            if controller.newStage { StageBackdrop() }
            SceneHost(controller: controller)
            switch controller.phase {
            case .empty:
                Label("No shape yet", systemImage: "cube.transparent")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.muted)
            case .loading:
                ProgressView("Loading your shape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
            case .failed(let message, let detail):
                VStack(spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.bad)
                    Text(detail).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            case .ready:
                EmptyView()
            }
        }
        .task(id: key) { await controller.load(key, highlight: highlight) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityText: String {
        guard let s = controller.info?.sizeMM else { return "3D view. No shape yet." }
        return "3D model. \(SizeBadge.spoken(s))"
    }
}

/// The stage: a cool blue-grey fade with a few faint confetti shapes in the corners. Static, so Reduce
/// Motion has nothing to stop. Reduce Transparency hides the see-through confetti.
private struct StageBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// x, y as fractions of the stage, size in points, 0 for a dot and an angle for a square, colour.
    private static let bits: [(CGFloat, CGFloat, CGFloat, Double, Color)] = [
        (0.05, 0.16, 7, 0, Theme.gold), (0.11, 0.08, 9, 20, Theme.tintSize.ink), (0.17, 0.19, 5, 0, Theme.tintAdd.ink),
        (0.94, 0.07, 8, 0, Theme.tintCut.ink), (0.89, 0.15, 10, 35, Theme.gold), (0.97, 0.22, 5, 0, Theme.tintWords.ink),
        (0.04, 0.83, 9, 15, Theme.tintWords.ink), (0.09, 0.93, 6, 0, Theme.gold), (0.15, 0.86, 4, 0, Theme.tintSize.ink),
        (0.96, 0.62, 6, 0, Theme.tintAdd.ink), (0.93, 0.70, 9, 50, Theme.tintCut.ink), (0.98, 0.76, 5, 0, Theme.gold),
    ]

    var body: some View {
        LinearGradient(colors: [Theme.stageTop, Theme.stageBottom], startPoint: .top, endPoint: .bottom)
            .overlay {
                if !reduceTransparency {
                    Canvas { ctx, size in
                        for (x, y, d, angle, color) in Self.bits {
                            let rect = CGRect(x: -d / 2, y: -d / 2, width: d, height: d)
                            var c = ctx
                            c.translateBy(x: x * size.width, y: y * size.height)
                            c.rotate(by: .degrees(angle))
                            let path = angle == 0 ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5)
                            c.fill(path, with: .color(color.opacity(0.5)))
                        }
                    }
                }
            }
            .accessibilityHidden(true)
    }
}

private struct SceneHost: NSViewRepresentable {
    let controller: ViewerController

    func makeNSView(context: Context) -> OrbitSCNView {
        let v = OrbitSCNView(frame: .zero, options: nil)
        v.controller = controller
        v.scene = controller.stage.scene
        v.pointOfView = controller.stage.cameraNode
        v.antialiasingMode = .multisampling4X
        v.allowsCameraControl = false
        v.autoenablesDefaultLighting = false
        v.preferredFramesPerSecond = 60
        v.backgroundColor = .clear
        controller.view = v
        v.viewDidChangeEffectiveAppearance()
        return v
    }

    func updateNSView(_ nsView: OrbitSCNView, context: Context) {}
}

/// Mouse, trackpad and keyboard handling for the orbit camera.
final class OrbitSCNView: SCNView {
    weak var controller: ViewerController?
    private var stage: ViewerScene? { controller?.stage }

    /// Radians of turn per point of drag. Hand control uses the same.
    static let yawPerPoint: Float = 0.009
    /// Radians of tilt per point of drag. Hand control uses the same.
    static let pitchPerPoint: Float = 0.007

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        stage?.setAppearance(dark: dark)
    }

    private var countedDrag = false
    /// What the press landed on: a part id, or nil for empty floor. Only set for a multi part build.
    private var downPart: String?
    private var downPoint: CGPoint = .zero
    private var dragged = false
    /// A part being slid: the height of the grab plane and the offset from the grab point to its origin.
    private var grab: (id: String, height: Float, offset: SIMD2<Float>)?
    private var movedPart = false
    /// A part being turned: its yaw at the press, in degrees, and the sideways drag so far in points.
    private var turnGrab: (id: String, start: Double, dragged: CGFloat)?

    private var multiPart: Bool { stage?.isMultiPart ?? false }
    private var tool: ViewerController.Tool { controller?.tool ?? .look }

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    /// The closest part under a view point.
    func partID(at p: CGPoint) -> String? {
        guard let stage else { return nil }
        let hits = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 1])
        return hits.lazy.compactMap { stage.partID(of: $0.node) }.first
    }

    private func worldHit(_ p: CGPoint) -> SIMD3<Float>? {
        guard let stage else { return nil }
        let hits = hitTest(p, options: [.searchMode: SCNHitTestSearchMode.closest.rawValue, .categoryBitMask: 1])
        return hits.first { stage.partID(of: $0.node) != nil }.map { SIMD3<Float>($0.worldCoordinates) }
    }

    /// The mouse ray in world space, from the near plane out.
    func ray(_ p: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let a = SIMD3<Float>(unprojectPoint(SCNVector3(p.x, p.y, 0)))
        let b = SIMD3<Float>(unprojectPoint(SCNVector3(p.x, p.y, 1)))
        return (a, simd_normalize(b - a))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { controller?.resetView() }
        press(at: point(event))
    }

    override func mouseUp(with event: NSEvent) { release(at: point(event)) }

    override func mouseDragged(with event: NSEvent) {
        let f = event.modifierFlags
        drag(to: point(event), by: CGVector(dx: event.deltaX, dy: event.deltaY),
             lift: f.contains(.shift), noSnap: f.contains(.command), pan: f.contains(.option))
    }

    // MARK: Press, drag, release. The mouse and a hand pinch both come through here.

    /// `p` is a view point, bottom-left origin.
    func press(at p: CGPoint) {
        countedDrag = false
        dragged = false
        movedPart = false
        grab = nil
        turnGrab = nil
        controller?.userTouched()

        guard multiPart, let stage else { return }
        downPoint = p
        downPart = partID(at: p)
        if tool == .move, let id = downPart, let hit = worldHit(p), let pos = stage.position(of: id) {
            controller?.selectedPartID = id
            grab = (id, hit.y, SIMD2(pos.x - hit.x, pos.z - hit.z))
        } else if tool == .turn, let id = downPart, let yaw = stage.yawDegrees(of: id) {
            controller?.selectedPartID = id
            turnGrab = (id, yaw, 0)
        }
    }

    /// `d` is how far it moved in points, right and down positive, like `NSEvent.deltaX` and `deltaY`.
    /// `lift` raises or lowers a grabbed part, `noSnap` skips lining up, `pan` slides the view.
    func drag(to p: CGPoint, by d: CGVector, lift: Bool = false, noSnap: Bool = false, pan: Bool = false) {
        dragged = true
        if multiPart, let t = turnGrab, let stage {
            turnGrab?.dragged += d.dx
            let yaw = TurnSnap.yaw(from: t.start, draggedPoints: t.dragged + d.dx)
            if stage.yawDegrees(of: t.id).map({ abs($0 - yaw) > 0.01 }) ?? false {
                stage.turnPart(t.id, yawDegrees: yaw)
                movedPart = true
            }
            return
        }
        if multiPart, let g = grab, let stage {
            if lift {  // Shift drag lifts the part up or down
                stage.liftPart(g.id, by: Float(-d.dy) * 0.5)
                movedPart = true
                return
            }
            let r = ray(p)
            let floorPlane = Plane(point: SIMD3(0, g.height, 0), normal: SIMD3(0, 1, 0))
            if let hit = floorPlane.intersect(origin: r.origin, direction: r.direction) {
                let snap = (controller?.snapEnabled ?? false) && !noSnap
                stage.dragPart(g.id, x: hit.x + g.offset.x, z: hit.z + g.offset.y, snap: snap)
                movedPart = true
            }
            return
        }
        if multiPart && tool == .cut {
            let (a, b) = CutStroke.snapped(downPoint, p)
            stage?.showCutLine(cutLine(a, b))
            return
        }
        if pan {
            stage?.pan(dx: Float(d.dx), dy: Float(d.dy))
        } else {
            stage?.orbit(dYaw: Float(-d.dx) * Self.yawPerPoint, dPitch: Float(-d.dy) * Self.pitchPerPoint)
            if !countedDrag { countedDrag = true; controller?.userOrbited() }
        }
    }

    func release(at p: CGPoint) {
        guard multiPart, let stage else { return }
        stage.showGuides([])
        if let t = turnGrab, movedPart, let yaw = stage.yawDegrees(of: t.id) {
            // Snap again: the node keeps the angle as a Float, a hair off the step.
            controller?.partTurned(t.id, to: TurnSnap.yaw(from: yaw, draggedPoints: 0))
        } else if let g = grab, movedPart, let pos = stage.position(of: g.id) {
            controller?.partMoved(g.id, to: pos)
        } else if tool == .cut, dragged {
            // The drag already swapped the stage line for this stroke. A stroke too short or off every
            // part drops it, and any cut still waiting, so the line and the "Cut here" bar always agree.
            if hypot(p.x - downPoint.x, p.y - downPoint.y) <= 8 || !finishCut(to: p) {
                stage.showCutLine(nil)
                controller?.onCutDropped?()
            }
        } else if !dragged {
            // A click selects the part under it in every tool. A click on the floor clears the selection.
            controller?.selectedPartID = downPart
        }
        grab = nil
        turnGrab = nil
    }

    /// The stroke snapped to 15 degree steps, so a wobbly line gives a clean cut. True when it made a cut.
    /// The line stays on the stage until the app clears it.
    private func finishCut(to end: CGPoint) -> Bool {
        guard let c = controller else { return false }
        let (a, b) = CutStroke.snapped(downPoint, end)
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        guard let id = partID(at: mid) ?? c.selectedPartID else { return false }
        let eye = pointOfView?.presentation.simdWorldPosition ?? .zero
        let (wa, wb) = cutLine(a, b)
        guard let plane = CutPlane.make(eye: eye, strokeA: wa, strokeB: wb) else { return false }
        stage?.showCutLine((wa, wb))
        c.cut(partID: id, worldPlane: plane)
        return true
    }

    /// The stroke's ends in the world, at the depth of the part under it (or the model's middle), so
    /// the drawn line stays on the part when the view turns.
    private func cutLine(_ a: CGPoint, _ b: CGPoint) -> (SIMD3<Float>, SIMD3<Float>) {
        let mid = CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        let centre = (partID(at: mid) ?? downPart).flatMap { stage?.position(of: $0) } ?? stage?.center ?? .zero
        let z = projectPoint(SCNVector3(centre)).z
        return (SIMD3<Float>(unprojectPoint(SCNVector3(a.x, a.y, z))), SIMD3<Float>(unprojectPoint(SCNVector3(b.x, b.y, z))))
    }

    override func rightMouseDown(with event: NSEvent) { controller?.userTouched() }
    override func rightMouseDragged(with event: NSEvent) { stage?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY)) }
    override func otherMouseDragged(with event: NSEvent) { stage?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY)) }

    override func scrollWheel(with event: NSEvent) {
        controller?.userTouched()
        if event.hasPreciseScrollingDeltas && multiPart && tool != .look {
            // In Move and Cut a one finger drag is busy, so two fingers turn the view instead of sliding it.
            stage?.orbit(dYaw: Float(-event.scrollingDeltaX) * Self.yawPerPoint, dPitch: Float(-event.scrollingDeltaY) * Self.pitchPerPoint)
            if event.phase == .began { controller?.userOrbited() }
        } else if event.hasPreciseScrollingDeltas {
            // Two fingers on a trackpad slide the model around.
            stage?.pan(dx: Float(event.scrollingDeltaX), dy: Float(-event.scrollingDeltaY))
        } else {
            // A mouse wheel zooms.
            stage?.zoom(by: Float(pow(1.08, event.scrollingDeltaY)))
        }
    }

    override func magnify(with event: NSEvent) {
        controller?.userTouched()
        stage?.zoom(by: Float(1 + event.magnification))
    }

    override func rotate(with event: NSEvent) {
        controller?.userTouched()
        controller?.userOrbited()
        stage?.orbit(dYaw: Float(-event.rotation) * .pi / 180, dPitch: 0)
    }

    override func keyDown(with event: NSEvent) {
        guard let c = controller else { return super.keyDown(with: event) }
        switch event.specialKey {
        case .leftArrow?: c.turn(degrees: -15)
        case .rightArrow?: c.turn(degrees: 15)
        case .upArrow?: c.tilt(degrees: 10)
        case .downArrow?: c.tilt(degrees: -10)
        default:
            switch event.charactersIgnoringModifiers {
            case "+", "=": c.zoom(by: 1.25)
            case "-": c.zoom(by: 0.8)
            default: super.keyDown(with: event)
            }
        }
    }
}
