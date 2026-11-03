import CADShared
import Foundation
import SwiftUI

/// A fake guidance service for previews and tests. It acts like the `stub` engine:
/// the ring fills a bit with every frame, and frames 8 to 10 say "Too fast".
actor PreviewBackendAPI: BackendAPI {
    private(set) var frames = 0
    private(set) var resets = 0
    var failNext = false

    func setFailNext(_ value: Bool) { failNext = value }

    static func result(frame n: Int) -> GuidanceResult {
        // Each frame adds a third of a sector, so the ring is full after 36 frames.
        let filled = Double(n) / 3
        let sectors = (0..<12).map { min(1, max(0, filled - Double($0))) }
        let fast = (8...10).contains(n)
        let json: [String: Any] = [
            "blur": ["score": 210.0, "ok": true],
            "light": ["mean": 120.0, "clipped_pct": 0.3, "ok": true, "issue": NSNull()],
            "tracking": ["match_ratio": 0.8, "ok": true],
            "speed": ["value": fast ? 34.0 : 10.0, "ok": !fast],
            "coverage": ["sectors": sectors, "pct": sectors.reduce(0, +) / 12 * 100],
            "warnings": fast ? ["Too fast. Walk around more slowly."] : [],
            "t": Double(n),
        ]
        let data = try! JSONSerialization.data(withJSONObject: json)
        return try! JSONDecoder().decode(GuidanceResult.self, from: data)
    }

    func status() async throws -> ModelState {
        let json = #"{"status":"idle","versions":[],"redo":[],"sample":false,"engine":"stub"}"#
        return try JSONDecoder().decode(ModelState.self, from: Data(json.utf8))
    }

    func sendFrame(jpeg: Data) async throws -> GuidanceResult {
        if failNext { throw APIFailure(message: "Lost contact", isConnectionLost: true) }
        frames += 1
        return Self.result(frame: frames)
    }

    func resetGuidance() async throws {
        resets += 1
        frames = 0
    }

    func uploadScan(fileURL: URL) async throws { throw APIFailure(message: "Preview only.") }
    func edit(instruction: String) async throws -> ModelState { throw APIFailure(message: "Preview only.") }
    func undo() async throws -> ModelState { throw APIFailure(message: "Preview only.") }
    func redo() async throws -> ModelState { throw APIFailure(message: "Preview only.") }
    func downloadModel(to destination: URL) async throws { throw APIFailure(message: "Preview only.") }
}

/// A busy backdrop so overlay contrast can be judged in previews.
struct BusyBackdrop: View {
    var body: some View {
        Canvas { ctx, size in
            for i in 0..<40 {
                let x = Double((i * 97) % 100) / 100 * size.width
                let y = Double((i * 61) % 100) / 100 * size.height
                let r = 30 + Double((i * 37) % 90)
                let hue = Double((i * 29) % 100) / 100
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(Color(hue: hue, saturation: 0.6, brightness: 0.4 + Double(i % 5) * 0.12)))
            }
        }
        .background(Color(white: 0.85))
    }
}

/// Overlay parts on a busy picture. Tests render this to a PNG to check the look.
struct OverlayGallery: View {
    var body: some View {
        ZStack {
            BusyBackdrop()
            HStack(alignment: .top, spacing: 30) {
                VStack(alignment: .leading, spacing: 10) {
                    StatusChip("Focus", level: .good)
                    StatusChip("Too dark", level: .bad)
                    StatusChip("Tracking", level: .neutral)
                    StatusChip("Too fast", level: .bad)
                }
                CoverageRing(sectors: [1, 1, 1, 1, 0.6, 0.2, 0, 0, 0, 0, 0, 0], percent: 39)
                CoverageRing(sectors: Array(repeating: 1, count: 12), percent: 100)
                CoverageRing(sectors: [1, 1, 1, 0.5, 0, 0, 0, 0, 0, 0, 1, 1], percent: 45,
                             lower: [1, 1, 0.3, 0, 0, 0, 0, 0, 0, 0, 0, 1], upper: [1, 0.4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            VStack(spacing: 12) {
                Spacer()
                WarningBar(OverlayMessage(text: "Too fast. Walk around more slowly.", tone: .warning))
                WarningBar(OverlayMessage(text: GuidanceText.good, tone: .good))
                HStack(spacing: 12) {
                    RecBadge(start: Date())
                    WarningBar(OverlayMessage(text: GuidanceText.stopped, tone: .neutral))
                }
            }
            .padding(24)
        }
        .frame(width: 1100, height: 620)
    }
}

#Preview("Scan screen, practice clip") {
    ScanView(api: PreviewBackendAPI(), source: PreviewScanSource(), onFinished: { print("Finished:", $0) }, onSkip: {})
        .frame(width: 1280, height: 800)
}

#Preview("Overlay parts") {
    OverlayGallery()
}

#Preview("Camera blocked") {
    ZStack {
        Color.black
        CameraStateCard(card: CameraState.denied.card!, perform: { _ in })
    }
    .frame(width: 1000, height: 560)
}
