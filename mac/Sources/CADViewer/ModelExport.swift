import AppKit
import CADShared
import SwiftUI
import UniformTypeIdentifiers

/// Saving and sharing the kid's STL. All functions show panels, so call them on the main thread.
/// Each returns nil when the kid presses Cancel.
@MainActor
public enum ModelExport {
    public static let tinkercadURL = URL(string: "https://www.tinkercad.com")!
    /// Tinkercad refuses bigger imports.
    public static let tinkercadMaxBytes = 25_000_000

    /// Asks where to save, then copies the STL there.
    @discardableResult
    public static func saveCopy(of stl: URL, suggestedName: String = "My model.stl") throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save your model"
        panel.prompt = "Save"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [UTType(filenameExtension: "stl") ?? .data]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return nil }
        try copy(stl, to: dest)
        return dest
    }

    /// Asks where to save, then writes a PNG.
    @discardableResult
    public static func savePNG(_ image: NSImage, suggestedName: String = "My model.png") throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save a picture"
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return nil }
        guard let png = pngData(image) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: dest, options: .atomic)
        return dest
    }

    public static func pngData(_ image: NSImage) -> Data? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    public static func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Asks for a folder, copies the STL into it, shows it in Finder and opens Tinkercad in the browser. Tinkercad opens even if the copy is cancelled.
    @discardableResult
    public static func copyForTinkercad(_ stl: URL, name: String = "My model.stl") throws -> URL? {
        // Open the browser even when the kid cancels the folder, or the copy fails.
        defer { NSWorkspace.shared.open(tinkercadURL) }
        guard let dest = try copyToChosenFolder(stl, name: name) else { return nil }
        revealInFinder(dest)
        return dest
    }

    /// The FreeCAD app, if this Mac has it.
    public static var freeCADAppURL: URL? {
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "org.freecad.FreeCAD") { return u }
        let guess = URL(fileURLWithPath: "/Applications/FreeCAD.app")
        return FileManager.default.fileExists(atPath: guess.path) ? guess : nil
    }

    /// Opens the STL in FreeCAD. Returns false when FreeCAD is not installed.
    @discardableResult
    public static func openInFreeCAD(_ stl: URL) -> Bool {
        guard let app = freeCADAppURL else { return false }
        // FreeCAD's Info.plist does not list STL, so a plain "open file" starts it empty.
        // Run its binary with a small start-up script that imports the mesh and fits the view.
        let bin = app.appendingPathComponent("Contents/Resources/bin/freecad")
        if FileManager.default.isExecutableFile(atPath: bin.path),
           let script = try? writeFreeCADScript() {
            let p = Process()
            p.executableURL = bin
            p.arguments = [script.path]
            p.environment = ProcessInfo.processInfo.environment.merging(["CADDY_STL": stl.path]) { $1 }
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            if (try? p.run()) != nil { return true }
        }
        NSWorkspace.shared.open([stl], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }

    private static func writeFreeCADScript() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("CADDY", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("open_in_freecad.py")
        let py = """
        import os, FreeCAD, FreeCADGui
        from PySide import QtCore
        PATH = os.environ.get("CADDY_STL", "")
        def go():
            import Mesh, MeshGui
            FreeCADGui.activateWorkbench("MeshWorkbench")
            doc = FreeCAD.newDocument(os.path.splitext(os.path.basename(PATH))[0])
            Mesh.insert(PATH, doc.Name)
            doc.recompute()
            FreeCADGui.activeDocument().activeView().viewIsometric()
            FreeCADGui.SendMsgToActiveView("ViewFit")
        QtCore.QTimer.singleShot(2500, go)
        """
        try py.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func copyToChosenFolder(_ stl: URL, name: String) throws -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Pick a folder you can find again, like Desktop"
        panel.prompt = "Put it here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return nil }
        let dest = uniqueURL(folder.appendingPathComponent(name))
        try copy(stl, to: dest)
        return dest
    }

    /// "My model.stl", then "My model 2.stl" and so on. Never overwrites a kid's earlier file.
    static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let u = dir.appendingPathComponent("\(base) \(n)").appendingPathExtension(ext)
            if !fm.fileExists(atPath: u.path) { return u }
            n += 1
        }
    }

    /// The save panel already asked about replacing, so replace.
    static func copy(_ src: URL, to dest: URL) throws {
        let fm = FileManager.default
        if src.standardizedFileURL == dest.standardizedFileURL { return }
        let tmp = dest.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).stl")
        try fm.copyItem(at: src, to: tmp)
        do {
            if fm.fileExists(atPath: dest.path) {
                _ = try fm.replaceItemAt(dest, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: dest)
            }
        } catch {
            try? fm.removeItem(at: tmp)
            throw error
        }
    }
}

// MARK: Help sheets

private struct HelpSheet<Actions: View>: View {
    let title: String
    let steps: [String]
    let note: String?
    let error: String?
    @ViewBuilder let actions: () -> Actions
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.ink)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(i + 1)")
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Theme.accent.opacity(0.14)))
                    Text(step).font(.system(size: 15)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let note {
                Text(note).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13)).foregroundStyle(Theme.bad)
            }
            HStack(spacing: 12) {
                actions()
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction).controlSize(.regular)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

/// Steps to take the model into Tinkercad. Show it in a sheet.
public struct TinkercadHelp: View {
    private let stlURL: URL?
    @State private var error: String?
    @State private var copied: URL?

    public init(stlURL: URL?) { self.stlURL = stlURL }

    public var body: some View {
        HelpSheet(
            title: "Open it in Tinkercad",
            steps: [
                "Press the button below. Pick a folder you can find again, like Desktop.",
                "Tinkercad opens in your web browser. Sign in, or ask your teacher.",
                "Make a new 3D design.",
                "Press Import at the top right. Choose your file.",
                "Your shape shows up. Now you can change it even more.",
            ],
            note: note,
            error: error
        ) {
            Button {
                guard let stlURL else { return }
                do { copied = try ModelExport.copyForTinkercad(stlURL) ?? copied } catch { self.error = "Could not copy the file. \(error.localizedDescription)" }
            } label: {
                Label("Copy file and open Tinkercad", systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .controlSize(.regular)
            .disabled(stlURL == nil)
        }
    }

    private var note: String? {
        if let copied { return "Your file is in \(copied.deletingLastPathComponent().lastPathComponent). It is called \(copied.lastPathComponent)." }
        if let stlURL, let size = try? stlURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > ModelExport.tinkercadMaxBytes {
            return "This file is big. Tinkercad may say it is too big to import."
        }
        return nil
    }
}

/// Steps to take the model into FreeCAD. Opens it straight away if FreeCAD is installed.
public struct FreeCADHelp: View {
    private let stlURL: URL?
    @State private var error: String?

    public init(stlURL: URL?) { self.stlURL = stlURL }

    public var body: some View {
        let installed = ModelExport.freeCADAppURL != nil
        HelpSheet(
            title: "Open it in FreeCAD",
            steps: installed ? [
                "Press Open in FreeCAD below.",
                "Your shape opens as a mesh made of triangles.",
                "To measure it, use the Measure tool at the top.",
            ] : [
                "FreeCAD is not on this Mac. Ask your teacher to install it from freecad.org.",
                "Save your model first, with Save a copy below.",
                "In FreeCAD, choose File, then Open. Pick your STL file.",
                "Your shape opens as a mesh made of triangles.",
            ],
            note: "Teacher tip: to edit it as a solid, use the Part workbench, then Part, Create shape from mesh.",
            error: error
        ) {
            if installed {
                Button {
                    if let stlURL, !ModelExport.openInFreeCAD(stlURL) { error = "FreeCAD did not open." }
                } label: { Label("Open in FreeCAD", systemImage: "arrow.up.forward.app") }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).controlSize(.regular).disabled(stlURL == nil)
            }
            Button {
                guard let stlURL else { return }
                do {
                    if let dest = try ModelExport.saveCopy(of: stlURL) { ModelExport.revealInFinder(dest) }
                } catch { self.error = "Could not save the file. \(error.localizedDescription)" }
            } label: { Label("Save a copy", systemImage: "square.and.arrow.down") }
                .controlSize(.regular).disabled(stlURL == nil)
        }
    }
}
