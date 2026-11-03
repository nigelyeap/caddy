import SwiftUI
import CADShared
import CADBackend
import CADScan
import CADViewer

// The one place where the app meets the other targets.

// MARK: Backend

typealias Helper = BackendService
typealias HelperPhase = BackendService.Phase

@MainActor func makeHelper(root: URL?, port: Int) -> Helper { BackendService(root: root, preferredPort: port) }
@MainActor func helperPhase(_ h: Helper) -> HelperPhase { h.phase }

/// One camera for the whole app, so Settings and the scan screen agree on which one is used.
@MainActor let sharedCamera = CameraScanSource()

// MARK: Scan step

struct ScanStep: View {
    let api: BackendAPI
    let onFinished: (URL) -> Void
    let onSkip: () -> Void
    /// The Caddiy tour plays a practice clip, so it never needs the camera.
    var practice = false
    var body: some View {
        // The id makes a new ScanModel when practice changes, since StateObject keeps the first source.
        ScanView(api: api, source: practice ? PreviewScanSource() : sharedCamera, onFinished: onFinished, onSkip: onSkip)
            .id(practice)
    }
}

// MARK: Viewer

typealias ViewerControl = ViewerController

struct ViewerStep: View {
    let stlURL: URL?
    let revision: Int
    let highlightChange: Bool
    let controller: ViewerControl
    var body: some View {
        ModelViewer(stlURL: stlURL, revision: revision, highlightChange: highlightChange, controller: controller)
    }
}

struct ViewerSizeBadge: View {
    @ObservedObject var controller: ViewerControl
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            SizeBadge(info: controller.info, gridStepMM: controller.gridStepMM)
            if let d = controller.sizeDelta {
                // The axis that moved most, so "make it taller" reads "+19 mm tall".
                let axes = [("wide", d.x), ("deep", d.y), ("tall", d.z)]
                let (name, v) = axes.max { abs($0.1) < abs($1.1) }!
                Text("\(v > 0 ? "+" : "−")\(Int(abs(v).rounded())) mm \(name)")
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText(value: v))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Theme.accent.opacity(0.14), in: Capsule())
                    .transition(.opacity)
                    .accessibilityLabel("Changed by \(Int(abs(v).rounded())) millimetres \(name)")
            }
        }
        .animation(Theme.motion(reduceMotion), value: controller.sizeDelta)
    }
}

/// Size, volume, triangle count and watertight check for the model on screen.
struct ModelInfoRows: View {
    @ObservedObject var controller: ViewerControl
    var body: some View {
        if let i = controller.info {
            Grid(alignment: .leading, horizontalSpacing: Theme.Space.s, verticalSpacing: 6) {
                row("Size", String(format: "%.0f × %.0f × %.0f mm", i.sizeMM.x, i.sizeMM.y, i.sizeMM.z))
                row("Volume", i.volumeMM3.map { String(format: "%.1f cm³", $0 / 1000) } ?? "Unknown")
                row("Triangles", i.triangleCount.formatted())
                GridRow {
                    label("Watertight")
                    HStack(spacing: 4) {
                        Image(systemName: i.isWatertight ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(i.isWatertight ? Theme.good : Theme.warn)
                        Text(i.isWatertight ? "Yes, ready to print" : "No, may not print cleanly").foregroundStyle(Theme.ink)
                    }
                    .themeFont(.secondary)
                }
            }
        } else {
            Text("Loading model details").themeFont(.secondary).foregroundStyle(Theme.muted)
        }
    }
    private func label(_ s: String) -> some View {
        Text(s).themeFont(.secondary).foregroundStyle(Theme.muted).gridColumnAlignment(.leading)
    }
    private func row(_ k: String, _ v: String) -> some View {
        GridRow { label(k); Text(v).themeFont(.secondary).monospacedDigit().foregroundStyle(Theme.ink) }
    }
}

struct ViewerButtons: View {
    let controller: ViewerControl
    var body: some View { ViewerToolbar(controller: controller) }
}

struct TinkercadSheet: View {
    let stlURL: URL?
    var body: some View { TinkercadHelp(stlURL: stlURL) }
}

struct FreeCADSheet: View {
    let stlURL: URL?
    var body: some View { FreeCADHelp(stlURL: stlURL) }
}

@MainActor func freeCADInstalled() -> Bool { ModelExport.freeCADAppURL != nil }
@MainActor func openInFreeCAD(_ stl: URL) -> Bool { ModelExport.openInFreeCAD(stl) }

/// Asks where to save, then copies the STL there. Returns nil when the kid presses Cancel.
@MainActor func saveModelCopy(_ stl: URL) throws -> URL? { try ModelExport.saveCopy(of: stl) }

/// Cameras the scan screen can use, for the Settings picker.
@MainActor func cameraChoices() -> [(id: String, name: String)] { sharedCamera.cameras.map { ($0.id, $0.name) } }
@MainActor func chooseCamera(_ id: String) { Task { try? await sharedCamera.selectCamera(id: id) } }

// MARK: Previews

func previewAPI() -> BackendAPI { MockBackendAPI() }
