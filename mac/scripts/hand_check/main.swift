// Throwaway playground for hand control. Built by scripts/hand_check.sh, not part of the package.
// Shows the real viewer with a model and the Hands button, without the helper or the rest of the app.
import AppKit
import CADGesture
import CADShared
import CADViewer
import SwiftUI

extension ViewerController: @retroactive HandDragTarget {}

struct Playground: View {
    let stl: URL?
    @StateObject private var viewer = ViewerController()
    @StateObject private var hands = HandControl()

    var body: some View {
        ZStack {
            ModelViewer(stlURL: stl, revision: 0, controller: viewer)
            VStack {
                HStack(alignment: .top) {
                    SizeBadge(info: viewer.info, gridStepMM: viewer.gridStepMM)
                    Spacer()
                    VStack(alignment: .trailing, spacing: Theme.Space.xs) {
                        HandToggle(hands: hands)
                        HandCameraBubble(hands: hands)
                    }
                }
                Spacer()
                ViewerToolbar(controller: viewer)
            }
            .padding(Theme.Space.s)
            HandCursor(hands: hands)
        }
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { hands.target = viewer }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ note: Notification) {
        let arg = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
        let stl = arg.map { URL(fileURLWithPath: $0) } ?? Bundle.main.url(forResource: "mug", withExtension: "stl")
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                         styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "CADDIY hand playground"
        w.contentView = NSHostingView(rootView: Playground(stl: stl).preferredColorScheme(.dark))
        w.center()
        w.makeKeyAndOrderFront(nil)
        window = w
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
