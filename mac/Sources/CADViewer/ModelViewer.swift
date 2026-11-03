import AppKit
import CADShared
import SceneKit
import SwiftUI

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
    /// Keeps turning until the kid touches the model. Off with Reduce Motion.
    @Published public var autoRotate = false { didSet { applySpin() } }
    /// Counts turns of the model for the Caddiy tour (one per drag).
    @Published public private(set) var orbitCount = 0

    lazy var stage = ViewerScene()
    weak var view: SCNView?
    private var loadedKey: LoadKey?
    private var spunOnce = false

    public init() {}

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

    private func stopAutoRotate() {
        stage.stopSpin()
        if autoRotate { autoRotate = false }
    }

    private func applySpin() {
        if autoRotate && !Self.reduceMotion { stage.startSpin(forever: true) } else { stage.stopSpin() }
    }

    // MARK: Loading

    struct LoadKey: Equatable { var url: URL?; var revision: Int }

    func load(_ key: LoadKey, highlight: Bool) async {
        guard key != loadedKey else { return }
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

    public var body: some View {
        ViewerContent(controller: external ?? own, key: .init(url: stlURL, revision: revision), highlight: highlightChange)
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

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        stage?.setAppearance(dark: dark)
    }

    private var countedDrag = false

    override func mouseDown(with event: NSEvent) {
        countedDrag = false
        window?.makeFirstResponder(self)
        controller?.userTouched()
        if event.clickCount == 2 { controller?.resetView() }
    }

    override func mouseDragged(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            stage?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY))
        } else {
            stage?.orbit(dYaw: Float(-event.deltaX) * 0.009, dPitch: Float(-event.deltaY) * 0.007)
            if !countedDrag { countedDrag = true; controller?.userOrbited() }
        }
    }

    override func rightMouseDown(with event: NSEvent) { controller?.userTouched() }
    override func rightMouseDragged(with event: NSEvent) { stage?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY)) }
    override func otherMouseDragged(with event: NSEvent) { stage?.pan(dx: Float(event.deltaX), dy: Float(event.deltaY)) }

    override func scrollWheel(with event: NSEvent) {
        controller?.userTouched()
        if event.hasPreciseScrollingDeltas {
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
