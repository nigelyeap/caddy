import AppKit
import CADShared
import SceneKit
import SwiftUI
import simd

/// The SceneKit stage: studio lights, floor shadow, grid, model and an orbit camera rig.
/// SceneKit units are mm. SceneKit is y up, so the model node turns the STL's z up into y up.
/// Main thread only.
final class ViewerScene {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    // Orbit rig: target -> yaw -> pitch -> camera at +z distance.
    private let targetNode = SCNNode()
    private let yawNode = SCNNode()
    private let pitchNode = SCNNode()
    private let keyLight = SCNNode()
    private let modelRoot = SCNNode()
    private let gridNode = SCNNode()
    /// Snap lines while a part is dragged, the size tags and the bed ruler. None of them can be picked.
    private let guideNode = SCNNode(), tagNode = SCNNode(), rulerNode = SCNNode(), cutLineNode = SCNNode()
    /// Top level nodes under `modelRoot`, by part id. `setModel` keeps its one node under `singleID`.
    /// A multi part entry is a container (bottom centre, yaw) holding one mesh child in the STL frame.
    private(set) var parts: [String: SCNNode] = [:]
    private var modelNode: SCNNode? { parts[Self.singleID] }
    static let singleID = "__single__"
    /// Geometry by file URL, so duplicates share one mesh. Holds the seat offset too.
    private var geometryCache: [URL: (geometry: SCNGeometry, offset: SIMD3<Float>)] = [:]
    private(set) var selectedID: String?
    private var material = SCNMaterial()

    private(set) var radius: Float = 50
    private(set) var center = SIMD3<Float>(0, 25, 0)
    var hasModel: Bool { !parts.isEmpty }
    /// True when the scene came from `setParts`, so picking and moving apply.
    var isMultiPart: Bool { !parts.isEmpty && modelNode == nil }
    /// Every part's eight box corners in world space, as they sit on screen now.
    var modelCorners: [SIMD3<Float>] { parts.values.flatMap { Self.corners(of: meshNode($0).presentation) } }

    static func corners(of n: SCNNode) -> [SIMD3<Float>] {
        let (lo, hi) = n.boundingBox
        return [lo.x, hi.x].flatMap { x in [lo.y, hi.y].flatMap { y in [lo.z, hi.z].map { z in
            n.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil) } } }
    }

    /// The node that holds the geometry: the part itself for `setModel`, the child for a container.
    private func meshNode(_ part: SCNNode) -> SCNNode { part.geometry != nil ? part : (part.childNodes.first ?? part) }
    private(set) var gridStepMM: Double = 10
    private var gridFootprint: Float = 0
    private var isDark = false

    var wireframe = false { didSet { material.fillMode = wireframe ? .lines : .fill } }
    /// The studio look (gradient backdrop, fading grid). Off gives the earlier flat look, for comparing.
    var newStage = true { didSet { setAppearance(dark: isDark) } }
    var showGrid = true { didSet { gridNode.isHidden = !showGrid } }
    /// Width, depth and height tags on the selected part, or the only part.
    var showSizes = true { didSet { refreshSizeTags() } }
    /// A mm ruler along the front and left of the bed, and one standing up at the back corner.
    var showRuler = false { didSet { rebuildRuler() } }

    static let defaultYaw: Float = 35 * .pi / 180
    static let defaultPitch: Float = -24 * .pi / 180
    private static let fov: CGFloat = 32

    init() {
        let camera = SCNCamera()
        camera.fieldOfView = Self.fov
        camera.automaticallyAdjustsZRange = true
        camera.wantsHDR = false
        cameraNode.camera = camera
        scene.rootNode.addChildNode(targetNode)
        targetNode.addChildNode(yawNode)
        yawNode.addChildNode(pitchNode)
        pitchNode.addChildNode(cameraNode)
        yawNode.eulerAngles.y = CGFloat(Self.defaultYaw)
        pitchNode.eulerAngles.x = CGFloat(Self.defaultPitch)

        // Studio lights ride on the yaw node, so the side you look at is always lit well.
        let key = SCNLight()
        key.type = .directional
        key.intensity = 780
        key.castsShadow = true
        // Forward, so the floor shadow is drawn with alpha onto the clear scene over the SwiftUI stage.
        // Deferred shadows multiply the frame and vanish on a clear background.
        key.shadowMode = .forward
        key.shadowSampleCount = 16
        key.shadowRadius = 6
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowColor = NSColor(white: 0, alpha: 0.28)
        key.automaticallyAdjustsShadowProjection = false
        keyLight.light = key
        keyLight.eulerAngles = SCNVector3(-50 * CGFloat.pi / 180, -35 * CGFloat.pi / 180, 0)
        yawNode.addChildNode(keyLight)

        func light(_ intensity: CGFloat, pitch: CGFloat, yaw: CGFloat) {
            let l = SCNLight(); l.type = .directional; l.intensity = intensity
            let n = SCNNode(); n.light = l
            n.eulerAngles = SCNVector3(pitch * .pi / 180, yaw * .pi / 180, 0)
            yawNode.addChildNode(n)
        }
        light(420, pitch: -15, yaw: 55)      // fill from the other side
        light(520, pitch: -30, yaw: 170)     // rim from behind
        let ambient = SCNLight(); ambient.type = .ambient; ambient.intensity = 300
        let ambientNode = SCNNode(); ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        // Floor that only shows the shadow, so the background stays clean.
        let floor = SCNFloor()
        floor.reflectivity = 0
        let floorMat = SCNMaterial()
        floorMat.lightingModel = .shadowOnly
        floor.materials = [floorMat]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        scene.rootNode.addChildNode(gridNode)
        scene.rootNode.addChildNode(modelRoot)
        for n in [guideNode, tagNode, rulerNode, cutLineNode] {
            n.categoryBitMask = Self.outlineCategory
            n.castsShadow = false
            scene.rootNode.addChildNode(n)
        }
        material = Self.makeMaterial()
        setAppearance(dark: false)
        frame(animated: false)
    }

    private static func makeMaterial() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        // A soft warm clay, like modelling clay on a desk. Warm on the cool stage, so the shape reads at a glance.
        // It is a 3D material, not a UI colour, so it is not a Theme token.
        m.diffuse.contents = Self.clay
        m.roughness.contents = 0.62
        m.metalness.contents = 0.0
        m.emission.contents = NSColor.black
        m.isDoubleSided = true   // scans often have holes, show the inside instead of nothing
        return m
    }

    /// About 0xC79A80. Mid tone, so lit and shadowed sides both keep detail in light and dark.
    static let clay = NSColor(srgbRed: 0.78, green: 0.60, blue: 0.50, alpha: 1)

    // MARK: Theme

    /// The stage: a cool, faintly blue studio sweep. Light and dark values, top and bottom of the gradient.
    private enum Stage {
        static let top = Theme.dynamic(0xF5F7FB, 0x2D313A)
        static let bottom = Theme.dynamic(0xDCE2EA, 0x15171C)
    }

    func setAppearance(dark: Bool) {
        isDark = dark
        // The new stage is drawn by SwiftUI behind a clear scene. Pictures get the gradient in snapshot().
        scene.background.contents = newStage ? nil : resolve(Theme.viewer)
        rebuildGridIfNeeded()
        rebuildRuler()
        keyLight.light?.shadowColor = NSColor(white: 0, alpha: dark ? 0.45 : 0.28)
    }

    private var gridColor: NSColor {
        guard newStage else { return resolve(Theme.line) }
        // A step off the floor colour, so the grid reads as a quiet ruler, not a cage.
        let floor = resolve(Stage.bottom)
        return (isDark ? floor.blended(withFraction: 0.3, of: .white) : floor.blended(withFraction: 0.2, of: .black)) ?? floor
    }

    /// Vertical gradient so the model sits in a lit space, not on a flat grey.
    private func backdrop() -> NSImage {
        let top = resolve(Stage.top), bottom = resolve(Stage.bottom)
        let img = NSImage(size: NSSize(width: 8, height: 512))
        img.lockFocus()
        NSGradient(starting: top, ending: bottom)?.draw(in: NSRect(x: 0, y: 0, width: 8, height: 512), angle: -90)
        img.unlockFocus()
        return img
    }

    /// SceneKit needs a fixed colour, so read the Theme token for the current light or dark look.
    private func resolve(_ color: Color) -> NSColor {
        var out = NSColor(color)
        NSAppearance(named: isDark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            out = NSColor(color).usingColorSpace(.sRGB) ?? out
        }
        return out
    }

    // MARK: Model

    /// Swaps in a new mesh. `edit` keeps the kid's camera angle and zoom, scaled to the new size.
    func setModel(_ mesh: STLLoader.Mesh, edit: Bool, animate: Bool, reverse: Bool = false) {
        let geometry = STLLoader.makeGeometry(mesh)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        // STL z up to SceneKit y up: (x, y, z) -> (x, z, -y).
        node.eulerAngles.x = -.pi / 2
        let lo = mesh.boundsMin, hi = mesh.boundsMax
        let c = (lo + hi) / 2
        node.simdPosition = SIMD3(-c.x, -lo.z, c.y)

        // A sweep still running (quick undo/redo) would never remove its old mesh once replaced, so finish it now.
        // Any multi part scene goes too, since this is the one model path.
        modelRoot.removeAction(forKey: "sweep")
        let old = modelNode
        for child in modelRoot.childNodes where child !== old { child.removeFromParentNode() }
        old?.geometry?.materials = [material]
        old?.castsShadow = true
        geometryCache = [:]
        selectedID = nil

        let oldRadius = radius
        let size = hi - lo
        radius = max(simd_length(size) / 2, 1)
        center = SIMD3(0, size.z / 2, 0)

        node.name = Self.singleID
        parts = [Self.singleID: node]
        modelRoot.addChildNode(node)
        rebuildGrid(footprint: max(size.x, size.y))
        fitShadow()

        if animate, let old {
            sweep(from: old, to: node, upward: !reverse)
        } else {
            old?.removeFromParentNode()
        }

        refreshSizeTags()
        if edit {
            let scale = radius / oldRadius
            move(animated: animate, duration: 0.5) {
                self.targetNode.simdPosition = self.center
                self.cameraNode.simdPosition.z = self.clampDistance(self.cameraNode.simdPosition.z * scale)
            }
        } else {
            frame(animated: animate)
        }
    }

    func clearModel() {
        parts.values.forEach { $0.removeFromParentNode() }
        parts = [:]
        geometryCache = [:]
        selectedID = nil
        refreshSizeTags()
    }

    // MARK: Parts

    func hasGeometry(for url: URL) -> Bool { geometryCache[url] != nil }

    /// Shows a build of many parts. Diffs by id: new ids are added, gone ids removed, the rest re-placed.
    /// `meshes` only needs the files not cached yet. A part whose mesh is missing is skipped.
    /// The camera stays put; call `frame` for a fresh view.
    // ponytail: no add pop, remove fade or per part sweep yet. Add them when this is wired into the app.
    func setParts(_ list: [PartView], meshes: [URL: STLLoader.Mesh]) {
        modelRoot.removeAction(forKey: "sweep")
        if modelNode != nil { clearModel() }
        for child in modelRoot.childNodes where !parts.values.contains(where: { $0 === child }) { child.removeFromParentNode() }

        for (url, mesh) in meshes where geometryCache[url] == nil {
            let g = STLLoader.makeGeometry(mesh)
            g.materials = [material]
            let lo = mesh.boundsMin, hi = mesh.boundsMax, c = (lo + hi) / 2
            geometryCache[url] = (g, SIMD3(-c.x, -lo.z, c.y))
        }

        var reselect = false
        let wanted = Set(list.map(\.id))
        for (id, node) in parts where !wanted.contains(id) {
            node.removeFromParentNode()
            parts[id] = nil
        }
        for p in list {
            guard let cached = geometryCache[p.url] else { continue }
            let container: SCNNode
            if let existing = parts[p.id] {
                container = existing
            } else {
                container = SCNNode()
                container.name = p.id
                container.addChildNode(SCNNode())
                modelRoot.addChildNode(container)
                parts[p.id] = container
            }
            let mesh = meshNode(container)
            if mesh.geometry !== cached.geometry {
                mesh.geometry = cached.geometry
                // STL z up to SceneKit y up, then seat the file's bottom centre on the container origin.
                mesh.eulerAngles.x = -.pi / 2
                mesh.simdPosition = cached.offset
                if selectedID == p.id { reselect = true }
            }
            container.simdPosition = p.scenePosition
            container.eulerAngles.y = CGFloat(p.yawDegrees * .pi / 180)
        }
        let used = Set(list.map(\.url))
        geometryCache = geometryCache.filter { used.contains($0.key) }
        // The outline is rebuilt from the new mesh once every part has its final place and turn.
        if let s = selectedID, reselect || parts[s] == nil { select(parts[s] == nil ? nil : s) }
        fitBounds()
        refreshSizeTags()
    }

    /// Radius, centre, grid and shadow cover every part. Leaves the camera alone.
    func fitBounds() {
        let pts = parts.values.flatMap { Self.corners(of: meshNode($0)) }
        guard var lo = pts.first else { return }
        var hi = lo
        for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        radius = max(simd_length(hi - lo) / 2, 1)
        center = (lo + hi) / 2
        // The grid is centred on the origin, so it has to reach the part furthest out.
        rebuildGrid(footprint: 2 * max(abs(lo.x), abs(hi.x), abs(lo.z), abs(hi.z)))
        fitShadow()
    }

    /// The part id a hit node belongs to, walking up to the top level node.
    func partID(of node: SCNNode) -> String? {
        var n: SCNNode? = node
        while let cur = n, cur.parent !== modelRoot { n = cur.parent }
        guard let top = n, let id = top.name, parts[id] === top else { return nil }
        return id
    }

    func position(of id: String) -> SIMD3<Float>? { parts[id]?.simdPosition }

    /// Hit tests aimed at parts skip the selection outline, which sits on this bit.
    static let outlineCategory = 2

    /// How high a part at (x, z) should sit: on top of the highest other part under its bottom centre,
    /// or on the floor.
    // ponytail: one ray at the bottom centre. A part hanging over an edge can sink into its neighbour.
    // Cast a few rays across the footprint if kids notice.
    func restHeight(for id: String, x: Float, z: Float) -> Float {
        // Hit tests read the committed tree. Commit now so a part added this frame counts.
        SCNTransaction.flush()
        let hits = modelRoot.hitTestWithSegment(from: SCNVector3(x, 100_000, z), to: SCNVector3(x, -1, z),
                                                options: [SCNHitTestOption.searchMode.rawValue: SCNHitTestSearchMode.all.rawValue,
                                                          SCNHitTestOption.categoryBitMask.rawValue: 1,
                                                          SCNHitTestOption.backFaceCulling.rawValue: false])
        return hits.filter { partID(of: $0.node) != id }.map { Float($0.worldCoordinates.y) }.max() ?? 0
    }

    /// The print bed is 250 mm, so a part's centre stays within 125 mm of the middle.
    static let bedHalf: Float = 125

    /// Slides a part to (x, z), snapped to 1 mm and kept on the bed, resting on whatever is below.
    /// `exact` skips the 1 mm rounding on an axis that already lined up with something.
    /// Returns where it ended up.
    @discardableResult
    func movePart(_ id: String, x: Float, z: Float, exact: (x: Bool, z: Bool) = (false, false)) -> SIMD3<Float>? {
        guard let node = parts[id] else { return nil }
        let x = min(max(exact.x ? x : x.rounded(), -Self.bedHalf), Self.bedHalf)
        let z = min(max(exact.z ? z : z.rounded(), -Self.bedHalf), Self.bedHalf)
        let p = SIMD3(x, restHeight(for: id, x: x, z: z), z)
        node.simdPosition = p
        refreshSizeTags()
        return p
    }

    /// A part's box on the floor, scene x and z, where it sits now.
    func footprint(_ id: String) -> SnapBox? {
        guard let node = parts[id] else { return nil }
        let pts = Self.corners(of: meshNode(node))
        guard let first = pts.first else { return nil }
        var lo = SIMD2(first.x, first.z), hi = lo
        for p in pts { lo = simd_min(lo, SIMD2(p.x, p.z)); hi = simd_max(hi, SIMD2(p.x, p.z)) }
        return SnapBox(min: lo, max: hi)
    }

    /// Like `movePart`, but first lines the part up with the other parts and the bed centre lines
    /// when it comes within 3 mm, and draws a guide line for each axis that lined up.
    func dragPart(_ id: String, x: Float, z: Float, snap: Bool) {
        guard snap, let node = parts[id], let box = footprint(id) else {
            showGuides([])
            movePart(id, x: x, z: z)
            return
        }
        let shift = SIMD2(x - node.simdPosition.x, z - node.simdPosition.z)
        let others = parts.filter { $0.key != id && !$0.value.isHidden }.keys.compactMap(footprint) + SnapSolver.bedLines
        let r = SnapSolver.snap(moving: SnapBox(min: box.min + shift, max: box.max + shift), others: others)
        showGuides(r.guides)
        movePart(id, x: x + (r.dx ?? 0), z: z + (r.dy ?? 0), exact: (r.dx != nil, r.dy != nil))
    }

    /// Thin accent lines just above the floor. An empty list clears them.
    func showGuides(_ guides: [(from: SIMD2<Float>, to: SIMD2<Float>)]) {
        let pts = guides.flatMap { [SIMD3($0.from.x, 0.2, $0.from.y), SIMD3($0.to.x, 0.2, $0.to.y)] }
        guideNode.geometry = pts.isEmpty ? nil : lines(pts, color: resolve(Theme.accent), onTop: true)
    }

    /// A part's turn about the upright axis, in degrees, same sign as `PartView.yawDegrees`.
    func yawDegrees(of id: String) -> Double? { parts[id].map { Double($0.eulerAngles.y) * 180 / .pi } }

    /// Turns a part in place to `yawDegrees`. Only the preview: the app saves it on release.
    func turnPart(_ id: String, yawDegrees: Double) {
        parts[id]?.eulerAngles.y = CGFloat(yawDegrees * .pi / 180)
        refreshSizeTags()
    }

    /// A thick cut coloured line between two world points, drawn over the parts. Nil clears it.
    func showCutLine(_ ends: (SIMD3<Float>, SIMD3<Float>)?) {
        cutLineNode.childNodes.forEach { $0.removeFromParentNode() }
        guard let (a, b) = ends, simd_distance(a, b) > 0.01 else { return }
        let bar = SCNCylinder(radius: CGFloat(max(simd_distance(a, b) * 0.012, 0.4)), height: CGFloat(simd_distance(a, b)))
        bar.materials = [overlayMaterial(resolve(Theme.tintCut.ink), onTop: true)]
        let n = SCNNode(geometry: bar)
        n.simdPosition = (a + b) / 2
        n.simdOrientation = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(b - a))
        n.categoryBitMask = Self.outlineCategory
        n.renderingOrder = 10
        cutLineNode.addChildNode(n)
    }

    /// Raises or lowers a part by `dy` mm, never below the floor. Used by Shift drag.
    func liftPart(_ id: String, by dy: Float) {
        guard let node = parts[id] else { return }
        node.simdPosition.y = min(max(node.simdPosition.y + dy, 0), 250)
        refreshSizeTags()
    }

    // MARK: Size tags and ruler

    /// Plain lines, two points each. `onTop` draws them over the parts, so they never hide.
    private func lines(_ pts: [SIMD3<Float>], color: NSColor, onTop: Bool) -> SCNGeometry {
        let el = SCNGeometryElement(indices: (0..<UInt32(pts.count)).map { $0 }, primitiveType: .line)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: pts.map { SCNVector3($0) })], elements: [el])
        g.materials = [overlayMaterial(color, onTop: onTop)]
        return g
    }

    private func overlayMaterial(_ contents: Any, onTop: Bool) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = contents
        m.isDoubleSided = true
        m.readsFromDepthBuffer = !onTop
        m.writesToDepthBuffer = false
        return m
    }

    /// A flat card showing `text` that always turns to face the camera. It keeps the same size on screen:
    /// `perMM` is its height in mm for each mm the camera is away. `push` moves it across the screen away
    /// from `tagCentre`, so a size tag sits beside the part instead of on it.
    private func label(_ text: String, perMM: Float, ink: NSColor, pill: NSColor?, onTop: Bool, push: Bool = false) -> SCNNode {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 24, weight: .semibold)
        let str = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: ink])
        let t = str.size()
        let w = ceil(t.width + (pill == nil ? 4 : 22)), h = ceil(t.height + 10)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w * 2), pixelsHigh: Int(h * 2), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: w, height: h)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let pill {
            let path = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: w - 2, height: h - 2), xRadius: h / 2 - 1, yRadius: h / 2 - 1)
            pill.setFill(); path.fill()
            NSColor(white: 0, alpha: 0.18).setStroke(); path.stroke()
        }
        str.draw(at: NSPoint(x: (w - t.width) / 2, y: (h - t.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        let plane = SCNPlane(width: w / h, height: 1)
        plane.materials = [overlayMaterial(rep.cgImage as Any, onTop: onTop)]
        let n = SCNNode(geometry: plane)
        n.name = text
        n.castsShadow = false
        n.categoryBitMask = Self.outlineCategory
        n.renderingOrder = onTop ? 20 : 0
        let cam = cameraNode
        let aspect = Float(w / h)
        n.constraints = [SCNBillboardConstraint(), SCNTransformConstraint(inWorldSpace: true) { [weak self, weak n] _, m in
            let eye = cam.presentation.simdWorldPosition
            var t = simd_float4x4(m)
            guard push, let n, let centre = self?.tagCentre else { return SCNMatrix4(Self.screenSized(t, eye: eye, perMM: perMM)) }
            // Start from the node's own spot, never last frame's pushed one, so the push cannot creep.
            let anchor = n.simdWorldPosition
            t.columns.3 = SIMD4(anchor, 1)
            t = Self.screenSized(t, eye: eye, perMM: perMM)
            let s = simd_distance(anchor, eye) * perMM
            let p = Self.pushedOut(anchor, from: centre, right: cam.presentation.simdWorldRight,
                                   up: cam.presentation.simdWorldUp, size: SIMD2(s * aspect, s))
            t.columns.3 = SIMD4(p, 1)
            return SCNMatrix4(t)
        }]
        return n
    }

    /// Moves a card at `anchor` across the screen, straight away from `centre`, by its own half size along
    /// that way plus a small gap. `right` and `up` are the camera's, `size` the card's width and height in mm.
    static func pushedOut(_ anchor: SIMD3<Float>, from centre: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
                          size: SIMD2<Float>) -> SIMD3<Float> {
        let d = anchor - centre
        let flat = SIMD2(simd_dot(d, right), simd_dot(d, up))
        guard simd_length(flat) > 1e-3 else { return anchor }
        let dir = simd_normalize(flat)
        let push = (abs(dir.x) * size.x + abs(dir.y) * size.y) / 2 + size.y * 0.2
        return anchor + (right * dir.x + up * dir.y) * push
    }

    /// Scales a card to `perMM` times its distance from the eye. The live view feeds the last result
    /// back in each frame, so the axes are set to that length, never multiplied, or the card grows
    /// every frame until it fills the screen.
    static func screenSized(_ m: simd_float4x4, eye: SIMD3<Float>, perMM: Float) -> simd_float4x4 {
        var w = m
        let s = simd_distance(SIMD3(w.columns.3.x, w.columns.3.y, w.columns.3.z), eye) * perMM
        for i in 0..<3 {
            let c = SIMD3(w[i].x, w[i].y, w[i].z), len = simd_length(c)
            if len > 0 { w[i] = SIMD4(c / len * s, 0) }
        }
        return w
    }

    /// Size tag height per mm of camera distance. About 22 points tall in a 700 point high view.
    private static let tagScale: Float = 0.02
    /// Ruler numbers, smaller than the tags. About 15 points tall in a 700 point high view.
    private static let rulerScale: Float = 0.012

    /// The middle of the part the size tags are on. They are pushed away from it on screen.
    private var tagCentre: SIMD3<Float>?

    /// Puts the three size tags on the selected part, or the only part. Called whenever it moves.
    func refreshSizeTags() {
        let id = selectedID ?? (parts.count == 1 ? parts.keys.first : nil)
        guard showSizes, let id, let part = parts[id] else {
            tagNode.childNodes.forEach { $0.removeFromParentNode() }
            return
        }
        let pts = Self.corners(of: meshNode(part))
        var lo = pts[0], hi = pts[0]
        for p in pts { lo = simd_min(lo, p); hi = simd_max(hi, p) }
        let tags = SizeTags.tags(lo: lo, hi: hi)
        tagCentre = (lo + hi) / 2
        if tagNode.childNodes.count != tags.count { tagNode.childNodes.forEach { $0.removeFromParentNode() } }
        for (i, t) in tags.enumerated() {
            let text = SizeTags.text(t.mm)
            var n = i < tagNode.childNodes.count ? tagNode.childNodes[i] : nil
            if n?.name != text {
                let fresh = label(text, perMM: Self.tagScale, ink: NSColor(white: 0.12, alpha: 1), pill: NSColor(white: 0.97, alpha: 0.95), onTop: true, push: true)
                if let n { tagNode.replaceChildNode(n, with: fresh) } else { tagNode.addChildNode(fresh) }
                n = fresh
            }
            n?.simdPosition = t.at
        }
    }

    /// Ticks every 10 mm, a longer tick and a number every 50 mm, 0 at the front left corner.
    private func rebuildRuler() {
        rulerNode.childNodes.forEach { $0.removeFromParentNode() }
        rulerNode.geometry = nil
        guard showRuler else { return }
        let h = Self.bedHalf, y: Float = 0.06
        var pts: [SIMD3<Float>] = [SIMD3(-h, y, h), SIMD3(h, y, h), SIMD3(-h, y, h), SIMD3(-h, y, -h), SIMD3(-h, 0, -h), SIMD3(-h, 250, -h)]
        let ink = resolve(Theme.muted)
        for mm in stride(from: 0, through: 250, by: 10) {
            let o = Float(mm), big = mm % 50 == 0, len: Float = big ? 6 : 3
            pts += [SIMD3(-h + o, y, h), SIMD3(-h + o, y, h + len)]   // front edge, outward
            pts += [SIMD3(-h, y, h - o), SIMD3(-h - len, y, h - o)]   // left edge, outward
            pts += [SIMD3(-h, o, -h), SIMD3(-h - len, o, -h)]         // standing up at the back left corner
            guard big else { continue }
            // The upright ruler skips its 0, which would sit on top of the floor's 250 at that corner.
            let spots = [SIMD3(-h + o, y, h + 12), SIMD3(-h - 12, y, h - o)] + (mm == 0 ? [] : [SIMD3(-h - 14, o, -h)])
            for at in spots {
                // Drawn over the parts so a part never hides a number. Below the size tags, which win.
                let n = label("\(mm)", perMM: Self.rulerScale, ink: ink, pill: nil, onTop: true)
                n.renderingOrder = 15
                n.simdPosition = at
                rulerNode.addChildNode(n)
            }
        }
        rulerNode.geometry = lines(pts, color: gridColor, onTop: false)
    }

    private lazy var outlineMaterial: SCNMaterial = {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = resolve(Theme.gold)
        // Draw only the back faces of a slightly fattened copy, so a rim shows around the part.
        m.cullMode = .front
        m.shaderModifiers = [.geometry: """
        #pragma arguments
        float outlinePerMM;
        float3 outlineCentre;
        #pragma body
        // Push away from the part's centre, not along the normal. Hard edges have split normals, and
        // pushing along those tears the rim open at every box corner.
        // Never push down. The geometry frame is the STL one, z up. A rim pushed under the floor showed
        // on the lit side only, so the outline looked shifted to one side.
        float3 away = _geometry.position.xyz - outlineCentre;
        away.z = max(away.z, 0.0);
        // Grow with camera distance, so the rim is the same few points wide at any zoom and part size.
        float depth = abs((scn_node.modelViewTransform * _geometry.position).z);
        _geometry.position.xyz += (length(away) > 1e-4 ? normalize(away) : _geometry.normal) * depth * outlinePerMM;
        """]
        return m
    }()

    /// Gold outline on one part, or none. The outline is a child copy of the mesh pushed outward a little.
    // ponytail: pushing from the centre is rough on deep hollows like a mug's inside. A screen space
    // outline pass fixes it if it looks bad on real scans.
    func select(_ id: String?) {
        for node in parts.values { meshNode(node).childNode(withName: "outline", recursively: false)?.removeFromParentNode() }
        selectedID = id
        refreshSizeTags()
        guard let id, let part = parts[id], let g = meshNode(part).geometry?.copy() as? SCNGeometry else { return }
        let m = outlineMaterial.copy() as! SCNMaterial
        // The geometry's own box. The node's box also counts its children, which can include an old outline.
        let (lo, hi) = g.boundingBox
        // About 5 points in a 700 point high view, like `tagScale`.
        m.setValue(Float(0.004), forKey: "outlinePerMM")
        m.setValue(SCNVector3((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2), forKey: "outlineCentre")
        g.materials = [m]
        let outline = SCNNode(geometry: g)
        outline.name = "outline"
        outline.castsShadow = false
        outline.categoryBitMask = Self.outlineCategory
        meshNode(part).addChildNode(outline)
    }

    /// Multiplies every SceneKit animation time. 1 normally. The harness sets it above 1 to slow things down.
    static let timeScale: Double = ProcessInfo.processInfo.environment["CADDY_SLOWMO"].flatMap(Double.init) ?? 1

    private static let sweepShader = """
    #pragma arguments
    float plane;
    float dir;
    float keepNew;
    float band;
    #pragma body
    float3 wp = (scn_frame.inverseViewTransform * float4(_surface.position, 1.0)).xyz;
    float s = (wp.y - plane) * dir;
    if (keepNew > 0.5 ? s > 0.0 : s <= 0.0) { discard_fragment(); }
    // A soft warm light just behind the plane on the new shape, fading out over one band.
    float g = keepNew > 0.5 ? saturate(1.0 + s / band) : 0.0;
    _output.color.rgb = mix(_output.color.rgb, float3(1.0, 0.97, 0.9), g * g * 0.45);
    """

    /// A plane of height sweeps through the model. The new shape shows behind it, the old shape ahead of it.
    /// The old mesh stays opaque and keeps casting the shadow until the end, so the model never vanishes.
    private func sweep(from old: SCNNode, to new: SCNNode, upward: Bool) {
        let top = Float(max(old.boundingBox.max.z - old.boundingBox.min.z, new.boundingBox.max.z - new.boundingBox.min.z)) + 1
        let band = max(top * 0.08, 1)
        func clipped(_ keepNew: Float) -> SCNMaterial {
            let m = material.copy() as! SCNMaterial
            m.shaderModifiers = [.fragment: Self.sweepShader]
            m.setValue(upward ? 1.0 : -1.0, forKey: "dir")
            m.setValue(keepNew, forKey: "keepNew")
            m.setValue(band, forKey: "band")
            return m
        }
        let oldMat = clipped(0), newMat = clipped(1)
        old.geometry?.materials = [oldMat]
        new.geometry?.materials = [newMat]
        new.castsShadow = false
        // The plane ends one band past the model, so the glow has faded before the plain material swaps back.
        let from: Float = upward ? -1 : top, to: Float = upward ? top + band : -1 - band
        let duration = 0.6 * Self.timeScale
        func set(_ p: Float) { oldMat.setValue(p, forKey: "plane"); newMat.setValue(p, forKey: "plane") }
        set(from)
        let run = SCNAction.customAction(duration: duration) { _, t in
            let k = Float(min(t / CGFloat(duration), 1))
            set(from + (to - from) * k * (2 - k))   // ease out
        }
        modelRoot.runAction(run, forKey: "sweep") { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                new.geometry?.materials = [self.material]
                new.castsShadow = true
                old.removeFromParentNode()
            }
        }
    }

    private func fitShadow() {
        guard let l = keyLight.light else { return }
        l.orthographicScale = CGFloat(radius * 1.6)
        l.zNear = 1
        l.zFar = CGFloat(radius * 12)
        // Back the light up along its own axis so the shadow box covers the model.
        let front = keyLight.simdOrientation.act(SIMD3<Float>(0, 0, -1))
        keyLight.simdPosition = -front * (radius * 5)
    }

    /// Lines every 10 mm so the floor doubles as a ruler. Bigger steps for big models.
    private func rebuildGridIfNeeded() { if gridFootprint > 0 { rebuildGrid(footprint: gridFootprint) } }

    private func rebuildGrid(footprint: Float) {
        gridFootprint = footprint
        let extent = max(footprint * 1.6, 60)
        var step: Float = 10
        if extent / step > 60 { step = 50 }
        if extent / step > 60 { step = 100 }
        gridStepMM = Double(step)
        let half = (extent / 2 / step).rounded(.up) * step
        var pts = [SIMD3<Float>]()
        var x = -half
        while x <= half + 0.01 {
            pts += [SIMD3(x, 0.05, -half), SIMD3(x, 0.05, half), SIMD3(-half, 0.05, x), SIMD3(half, 0.05, x)]
            x += step
        }
        let src = SCNGeometrySource(data: pts.withUnsafeBytes { Data($0) }, semantic: .vertex, vectorCount: pts.count,
                                    usesFloatComponents: true, componentsPerVector: 3, bytesPerComponent: 4,
                                    dataOffset: 0, dataStride: MemoryLayout<SIMD3<Float>>.stride)
        // Lines fade out toward the edge of the floor, so the grid has no hard border.
        // Opaque colours that blend into the floor colour: alpha blending barely showed on the light stage.
        // SceneKit reads vertex colours as linear, so undo the sRGB curve or every line shows too light.
        func rgb(_ c: NSColor) -> SIMD3<Float> {
            let c = c.usingColorSpace(.sRGB) ?? c
            func lin(_ v: CGFloat) -> Float { Float(v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)) }
            return SIMD3(lin(c.redComponent), lin(c.greenComponent), lin(c.blueComponent))
        }
        let floorRGB = rgb(resolve(Stage.bottom))
        let lineRGB = rgb(gridColor)
        let cols = pts.map { p -> SIMD4<Float> in
            let t = min(max(simd_length(SIMD2(p.x, p.z)) / (half * 1.05), 0), 1)
            let c = simd_mix(lineRGB, floorRGB, SIMD3(repeating: newStage ? t * t : 0))
            return SIMD4(c.x, c.y, c.z, 1)
        }
        let colSrc = SCNGeometrySource(data: cols.withUnsafeBytes { Data($0) }, semantic: .color, vectorCount: cols.count,
                                       usesFloatComponents: true, componentsPerVector: 4, bytesPerComponent: 4,
                                       dataOffset: 0, dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let idx = (0..<UInt32(pts.count)).map { $0 }
        let el = SCNGeometryElement(data: idx.withUnsafeBytes { Data($0) }, primitiveType: .line,
                                    primitiveCount: pts.count / 2, bytesPerIndex: 4)
        let g = SCNGeometry(sources: [src, colSrc], elements: [el])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.writesToDepthBuffer = false
        g.materials = [m]
        gridNode.geometry = g
        gridNode.renderingOrder = -1
    }

    // MARK: Camera

    private var fitDistance: Float {
        radius / sin(Float(Self.fov) * .pi / 360) * 1.12
    }

    private func clampDistance(_ d: Float) -> Float {
        min(max(d, radius * 1.1), fitDistance * 6)
    }

    private func move(animated: Bool, duration: Double = 0.6, _ change: @escaping () -> Void) {
        if !animated { change(); return }
        SCNTransaction.begin()
        SCNTransaction.animationDuration = duration * Self.timeScale
        SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        change()
        SCNTransaction.commit()
    }

    /// Default three quarter view that fits the whole model.
    func frame(animated: Bool) {
        // Take the shortest way round to the default angle.
        let y = Float(yawNode.eulerAngles.y)
        let twoPi = 2 * Float.pi
        yawNode.eulerAngles.y = CGFloat(Self.defaultYaw + remainder(y - Self.defaultYaw, twoPi))
        move(animated: animated) {
            self.targetNode.simdPosition = self.center
            self.yawNode.eulerAngles.y = CGFloat(Self.defaultYaw)
            self.pitchNode.eulerAngles.x = CGFloat(Self.defaultPitch)
            self.cameraNode.simdPosition = SIMD3(0, 0, self.fitDistance)
        }
    }

    var yaw: Float { Float(yawNode.eulerAngles.y) }

    func orbit(dYaw: Float, dPitch: Float, animated: Bool = false) {
        let pitch = min(max(Float(pitchNode.eulerAngles.x) + dPitch, -85 * .pi / 180), 12 * .pi / 180)
        move(animated: animated, duration: 0.3) {
            self.yawNode.eulerAngles.y += CGFloat(dYaw)
            self.pitchNode.eulerAngles.x = CGFloat(pitch)
        }
    }

    /// factor above 1 moves closer.
    func zoom(by factor: Float, animated: Bool = false) {
        guard factor > 0 else { return }
        let d = clampDistance(cameraNode.simdPosition.z / factor)
        move(animated: animated, duration: 0.25) { self.cameraNode.simdPosition.z = d }
    }

    /// Screen points, scaled so the model follows the fingers.
    func pan(dx: Float, dy: Float) {
        let k = cameraNode.simdPosition.z * 0.0018
        let right = cameraNode.simdWorldRight, up = cameraNode.simdWorldUp
        var t = targetNode.simdPosition - right * dx * k + up * dy * k
        // Keep the model somewhere on screen.
        let off = t - center
        let limit = radius * 2
        if simd_length(off) > limit { t = center + simd_normalize(off) * limit }
        targetNode.simdPosition = t
    }

    // MARK: Turn

    private let spinKey = "spin"

    /// One slow turn when `forever` is false.
    func startSpin(forever: Bool) {
        stopSpin()
        let turn = SCNAction.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 18)
        turn.timingMode = .linear
        yawNode.runAction(forever ? .repeatForever(turn) : turn, forKey: spinKey)
    }

    func stopSpin() { yawNode.removeAction(forKey: spinKey) }

    // MARK: Picture

    /// Renders the current view off screen. Works with or without a window.
    func snapshot(size: CGSize) -> NSImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = cameraNode
        renderer.autoenablesDefaultLighting = false
        let live = scene.background.contents
        if newStage { scene.background.contents = backdrop() }
        defer { scene.background.contents = live }
        return renderer.snapshot(atTime: CACurrentMediaTime(), with: size, antialiasingMode: .multisampling4X)
    }
}
