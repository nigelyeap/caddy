import AVFoundation
import QuartzCore
import SwiftUI

/// What a hand drag drives, like a mouse press, drag and release. The app conforms.
/// Points are fractions of the stage, top-left origin.
@MainActor public protocol HandDragTarget: AnyObject {
    func handDragBegan(at point: CGPoint)
    /// `point` is where the hand is now. `fraction` is how far it moved since the last call, times
    /// `dragGain`, for turning the camera. Right and down are positive.
    func handDragged(to point: CGPoint, by fraction: CGVector)
    func handDragEnded()
    /// Above 1 moves closer.
    func handZoomed(by factor: CGFloat)
    /// A pinch held still for a second. Only sent while `wantsHold` is on.
    func handHeld()
    /// Two fingers swiped sideways: 1 right, -1 left. Switches tool.
    func handSwiped(_ direction: Int)
}

extension HandDragTarget {
    public func handSwiped(_ direction: Int) {}
}

/// Hand control for the stage: camera on and off, the current hand, and pinch drags sent to `target`.
/// Publishes every camera frame, so only small views should observe it.
@MainActor
public final class HandControl: ObservableObject {
    public enum Problem: Equatable { case notAllowed, noCamera, inUse }

    /// Turns the camera on or off. Starts off each launch, so the camera never comes on by surprise.
    @Published public var enabled = false {
        didSet { if enabled != oldValue { enabled ? start() : stop() } }
    }
    @Published public private(set) var state: HandState = .noHand
    @Published public private(set) var poses: [HandPose] = []
    /// The other hand's cursor while one hand turns the model. Drawn faint.
    @Published public private(set) var second: CGPoint?
    @Published public private(set) var problem: Problem?
    /// 0 to 1 while a still pinch fills up toward a hold. Stays 0 unless `wantsHold`.
    @Published public private(set) var holdProgress: Double = 0
    /// Something is waiting for a hold to confirm it, such as a drawn cut line.
    public var wantsHold = false
    /// What the camera bubble says for an open hand and for a pinch. The app sets them to match the tool.
    public var hints = (open: "Pinch and move to turn. Pinch with both hands to zoom.",
                        pinched: "Turning! Open your hand to let go.")

    public weak var target: HandDragTarget?
    /// Below 1 turns the model less than a mouse drag of the same size. Hands are less steady than mice.
    public var dragGain: CGFloat = 0.7
    /// Above 1 zooms more than the hands' gap changes. Hands only spread so far.
    public var zoomGain: CGFloat = 1.5

    private let tracker = HandTracker()
    private var recognizer = HandsRecognizer()

    public init() {
        tracker.onPoses = { [weak self] poses, time in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.receive(poses, at: time) } }
        }
    }

    var previewLayer: CALayer { tracker.previewLayer }

    private func start() {
        problem = nil
        Task {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            guard enabled else { return }
            do {
                try await tracker.start()
            } catch HandTracker.Failure.notAllowed {
                problem = .notAllowed
            } catch HandTracker.Failure.noCamera {
                problem = .noCamera
            } catch {
                problem = .inUse
            }
        }
    }

    private func stop() {
        tracker.stop()
        if case .pinched = state { target?.handDragEnded() }
        recognizer.reset()
        state = .noHand
        poses = []
        second = nil
        holdProgress = 0
    }

    private func receive(_ poses: [HandPose], at time: TimeInterval) {
        guard enabled else { return }
        self.poses = poses
        let (next, events, other) = recognizer.update(poses, at: time)
        if next != state { state = next }
        if other != second { second = other }
        let hold = wantsHold ? recognizer.one.holdProgress : 0
        if hold != holdProgress { holdProgress = hold }
        for event in events {
            switch event {
            case .pinchBegan(let p): target?.handDragBegan(at: p)
            case .pinchMoved(let d):
                target?.handDragged(to: next.point ?? .zero, by: CGVector(dx: d.dx * dragGain, dy: d.dy * dragGain))
            case .pinchEnded: target?.handDragEnded()
            case .pinchHeld: if wantsHold { target?.handHeld() }
            case .swiped(let d): target?.handSwiped(d)
            case .zoomed(let f): target?.handZoomed(by: pow(f, zoomGain))
            }
        }
    }
}
