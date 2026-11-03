import SwiftUI
import AppKit
import CADShared

/// The small About panel: Caddy, the app name, the version and one friendly line.
struct AboutView: View {
    @AppStorage("textSize") private var textSize = TextSize.large

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            CaddyView(pose: .logo, size: 96, label: "Caddy, the CADDY chick")
            Text("CADDY").themeFont(.title).foregroundStyle(Theme.ink)
            Text("Version \(version)").themeFont(.secondary).foregroundStyle(Theme.muted)
            Text("Hi, I'm Caddy. Scan it, change it, print it.")
                .themeFont(.body).foregroundStyle(Theme.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.l)
        .frame(width: 300 * textSize.scale)
        .background(Theme.panel)
        .environment(\.textScale, textSize.scale)
    }
}

/// Opens one About window, or brings the open one forward.
enum AboutWindow {
    @MainActor private static var window: NSWindow?

    @MainActor static func show() {
        if let w = window {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let host = NSHostingController(rootView: AboutView())
        host.sizingOptions = .preferredContentSize
        let w = NSWindow(contentViewController: host)
        w.title = "About CADDY"
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.backgroundColor = NSColor(name: nil) { a in
            a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(srgbRed: 0x24 / 255, green: 0x24 / 255, blue: 0x26 / 255, alpha: 1) : .white
        }
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
