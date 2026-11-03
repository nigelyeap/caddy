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
    private var modelNode: SCNNode?
    private var material = SCNMaterial()

    private(set) var radius: Float = 50
    private(set) var center = SIMD3<Float>(0, 25, 0)
    private(set) var hasModel = false
    /// The model's eight box corners in world space, as it sits on screen now.
    var modelCorners: [SIMD3<Float>] {
        guard let n = modelNode?.presentation else { return [] }
        let (lo, hi) = n.boundingBox
        return [lo.x, hi.x].flatMap { x in [lo.y, hi.y].flatMap { y in [lo.z, hi.z].map { z in
            n.simdConvertPosition(SIMD3(Float(x), Float(y), Float(z)), to: nil) } } }
    }
    private(set) var gridStepMM: Double = 10
    private var gridFootprint: Float = 0
    private var isDark = false

    var wireframe = false { didSet { material.fillMode = wireframe ? .lines : .fill } }
    /// The studio look (gradient backdrop, fading grid). Off gives the earlier flat look, for comparing.
    var newStage = true { didSet { setAppearance(dark: isDark) } }
    var showGrid = true { didSet { gridNode.isHidden = !showGrid } }

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
        modelRoot.removeAction(forKey: "sweep")
        for child in modelRoot.childNodes where child !== modelNode { child.removeFromParentNode() }
        modelNode?.geometry?.materials = [material]
        modelNode?.castsShadow = true

        let oldRadius = radius
        let size = hi - lo
        radius = max(simd_length(size) / 2, 1)
        center = SIMD3(0, size.z / 2, 0)

        let old = modelNode
        modelNode = node
        hasModel = true
        modelRoot.addChildNode(node)
        rebuildGrid(footprint: max(size.x, size.y))
        fitShadow()

        if animate, let old {
            sweep(from: old, to: node, upward: !reverse)
        } else {
            old?.removeFromParentNode()
        }

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
        modelNode?.removeFromParentNode()
        modelNode = nil
        hasModel = false
    }

    /// Multiplies every SceneKit animation time. 1 normally. The harness sets it above 1 to slow things down.
    static let timeScale: Double = ProcessInfo.processInfo.environment["CADDIY_SLOWMO"].flatMap(Double.init) ?? 1

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
