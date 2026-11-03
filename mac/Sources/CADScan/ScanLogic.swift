@preconcurrency import AVFoundation
import CADShared
import CoreImage
import Foundation

// Plain rules with no UI, so tests can check them.

/// Decides when to send a frame to the guidance service and tracks whether it still answers.
public struct FrameGate: Equatable, Sendable {
    public var interval: TimeInterval = 1.0
    public private(set) var inFlight = false
    public private(set) var lastSent: TimeInterval?
    public private(set) var failuresInARow = 0
    public private(set) var lostContact = false
    /// Three failed frames in a row, or the service cannot be reached.
    public var checksStopped: Bool { lostContact || failuresInARow >= 3 }

    public init(interval: TimeInterval = 1.0) { self.interval = interval }

    /// True when the last frame has answered and a second has passed.
    public func shouldSend(now: TimeInterval) -> Bool {
        guard !inFlight else { return false }
        guard let lastSent else { return true }
        return now - lastSent >= interval
    }

    public mutating func didSend(now: TimeInterval) {
        inFlight = true
        lastSent = now
    }

    public mutating func didAnswer() {
        inFlight = false
        failuresInARow = 0
        lostContact = false
    }

    public mutating func didFail(connectionLost: Bool) {
        inFlight = false
        failuresInARow += 1
        if connectionLost { lostContact = true }
    }
}

public enum FrameEncoder {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// JPEG about `width` pixels wide. Never scales up.
    public static func jpeg(_ buffer: CVPixelBuffer, width: CGFloat = 640, quality: CGFloat = 0.7) -> Data? {
        var image = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, width / image.extent.width)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale), highQualityDownsample: true)
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return context.jpegRepresentation(of: image, colorSpace: space,
                                          options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality])
    }
}

public enum RecClock {
    /// 0:07, 1:05, 12:30.
    public static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Every camera situation the scan screen can be in.
public enum CameraState: Equatable, Sendable {
    case checking, notDetermined, denied, restricted, noCamera, inUse, disconnected, ready

    public static func from(auth: AVAuthorizationStatus, hasCamera: Bool) -> CameraState {
        switch auth {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .restricted: return .restricted
        case .authorized: return hasCamera ? .checking : .noCamera
        @unknown default: return .denied
        }
    }

    public static func from(error: Error) -> CameraState {
        switch error as? ScanSourceError {
        case .notAllowed: return .denied
        case .noCamera: return .noCamera
        case .disconnected: return .disconnected
        default: return .inUse
        }
    }

    public enum Action: Equatable, Sendable { case allowCamera, openSettings, tryAgain, useSample }

    public struct Card: Equatable, Sendable {
        public let title: String
        public let text: String
        public let symbol: String
        public let actions: [Action]
    }

    /// The card to show, or nil when the live picture should show.
    public var card: Card? {
        switch self {
        case .checking, .ready: return nil
        case .notDetermined:
            return Card(title: "Camera access needed",
                        text: "CADDY needs the camera to see your object. Nothing is filmed until you press Start scan.",
                        symbol: "camera", actions: [.allowCamera])
        case .denied, .restricted:
            return Card(title: "The camera is turned off",
                        text: "A grown-up can turn it on in System Settings, under Privacy and Security.",
                        symbol: "video.slash", actions: [.openSettings, .useSample])
        case .noCamera:
            return Card(title: "No camera found",
                        text: "Plug in a camera, or bring an iPhone close. Then try again.",
                        symbol: "web.camera", actions: [.tryAgain, .useSample])
        case .inUse:
            return Card(title: "Another app is using the camera",
                        text: "Close the other app, like Zoom or FaceTime. Then try again.",
                        symbol: "person.2.wave.2", actions: [.tryAgain, .useSample])
        case .disconnected:
            return Card(title: "The camera came unplugged",
                        text: "Plug it back in and try again. That video was not kept.",
                        symbol: "cable.connector.slash", actions: [.tryAgain])
        }
    }

    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!
}

public enum ChipLevel: Equatable, Sendable { case good, bad, neutral }

public struct ChipInfo: Equatable, Sendable, Identifiable {
    public let id: String
    public let word: String
    public let level: ChipLevel
}

public enum OverlayTone: Equatable, Sendable { case warning, good, done, neutral }

public struct OverlayMessage: Equatable, Sendable {
    public let text: String
    public let tone: OverlayTone
}

public enum GuidanceText {
    public static let good = "Good job. Keep going slowly."
    public static let nearlyDone = "You got every side! Press Finish scan."
    public static let stopped = "I can't check your scan right now. You can keep filming."
    public static let lost = "I stopped checking your scan. You can keep filming."
    public static let empty = "Oops, nothing was filmed. Press Start scan to try again."
    public static let practice = "Practice mode. The sides filling in are pretend. The light and focus checks are real."

    /// Before Start only light and focus matter. While recording all four are checked.
    /// The view shows only the bad ones, see `problems`.
    public static func chips(_ g: GuidanceResult?, recording: Bool, stopped: Bool) -> [ChipInfo] {
        let live = stopped ? nil : g
        func chip(_ id: String, _ goodWord: String, _ ok: Bool?, bad: String) -> ChipInfo {
            guard let ok else { return ChipInfo(id: id, word: goodWord, level: .neutral) }
            return ok ? ChipInfo(id: id, word: goodWord, level: .good) : ChipInfo(id: id, word: bad, level: .bad)
        }
        let lightBad: String
        switch live?.light.issue {
        case "dark": lightBad = "Too dark"
        case "bright": lightBad = "Too bright"
        case "glare": lightBad = "Too shiny"
        default: lightBad = "Light"
        }
        var out = [
            chip("focus", "Focus", live?.blur.ok, bad: "Blurry"),
            chip("light", "Light", live?.light.ok, bad: lightBad),
        ]
        if recording {
            out.append(chip("tracking", "Tracking", live?.tracking.ok, bad: "Can't see it"))
            out.append(chip("speed", "Speed", live?.speed.ok, bad: "Too fast"))
        }
        return out
    }

    /// The chips worth showing: only the ones that need fixing.
    public static func problems(_ chips: [ChipInfo]) -> [ChipInfo] { chips.filter { $0.level == .bad } }

    public static func message(_ g: GuidanceResult?, recording: Bool, gate: FrameGate) -> OverlayMessage? {
        if gate.checksStopped {
            return OverlayMessage(text: gate.lostContact ? lost : stopped, tone: .neutral)
        }
        guard let g else { return nil }
        if recording {
            if g.coverage.pct >= 95 { return OverlayMessage(text: nearlyDone, tone: .done) }
            if let first = g.warnings.first { return OverlayMessage(text: first, tone: .warning) }
            return OverlayMessage(text: good, tone: .good)
        }
        // Ready: say how to fix the room before Start.
        if !g.light.ok {
            switch g.light.issue {
            case "bright": return OverlayMessage(text: "Too bright. Turn away from the bright light.", tone: .warning)
            case "glare": return OverlayMessage(text: "It is too shiny here. Tilt the camera a little.", tone: .warning)
            default: return OverlayMessage(text: "Too dark. Turn on a light.", tone: .warning)
            }
        }
        if !g.blur.ok { return OverlayMessage(text: "A bit blurry. Hold the camera still.", tone: .warning) }
        return nil
    }
}
