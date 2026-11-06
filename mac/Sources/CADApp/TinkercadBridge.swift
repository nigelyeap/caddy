import SwiftUI
import AppKit
import CADShared
import CADViewer

/// One CADDY move and the matching move in Tinkercad.
struct BridgeMove: Identifiable {
    let id: String
    let caddy: String
    let symbol: String
    let tinkercad: String
    let steps: [String]

    // Checked against Tinkercad's Help Center on 2026-11-06. The Import button's exact spot and the import box labels
    // are not in the help pages, so check them in the live editor before each term.
    static let all: [BridgeMove] = [
        .init(id: "move", caddy: "Move", symbol: "hand.draw", tinkercad: "The shape itself",
              steps: ["Click your shape.", "Drag it across the grid.", "Drag the black arrow on top to lift it."]),
        .init(id: "turn", caddy: "Turn", symbol: "arrow.clockwise", tinkercad: "Curved arrows",
              steps: ["Click your shape.", "Grab a curved arrow and drag.", "Hold Shift to jump in big steps."]),
        .init(id: "size", caddy: "Size", symbol: "arrow.up.left.and.arrow.down.right", tinkercad: "Small squares",
              steps: ["Click your shape.", "Drag a small square on the shape.", "Hold Shift to keep it in proportion."]),
        .init(id: "cut", caddy: "Cut", symbol: "scissors", tinkercad: "A hole shape",
              steps: ["Click a shape. Press Hole in the box at the top right.", "Move the hole over the part you want gone.", "Select both and press Union Group."]),
        .init(id: "lift", caddy: "Lift", symbol: "arrow.up.and.down", tinkercad: "Black arrow",
              steps: ["Click your shape.", "Drag the black arrow on top up or down.", "Click the number that shows and type a new one."]),
        .init(id: "import", caddy: "Bring it in", symbol: "square.and.arrow.down", tinkercad: "Import button",
              steps: ["Make a new 3D design.", "Press Import near the top of the screen.", "Pick your file and check the size numbers. Press D to drop it on the grid."]),
    ]
}

/// "Learn the moves": each CADDY tool next to its Tinkercad twin. A click opens a small card that a click elsewhere closes.
struct TinkercadBridge: View {
    @State private var open: String?
    @State private var seen: Set<String> = []
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Same move, new place").themeFont(.title).foregroundStyle(Theme.ink)
            Text("Most of these you know from CADDY. Click one to see where it lives in Tinkercad.")
                .themeFont(.body).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("In CADDY").frame(width: 28 + 12 + 90, alignment: .leading)
                Text("In Tinkercad")
            }
            .themeFont(.caption).foregroundStyle(Theme.muted).padding(.horizontal, 12).accessibilityHidden(true)
            ForEach(BridgeMove.all) { m in
                Button { open = m.id } label: { row(m) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(m.caddy) in CADDY. In Tinkercad: \(m.tinkercad).")
                    .accessibilityValue(seen.contains(m.id) ? "Seen" : "")
                    // Only clear when this row still owns the popover, so opening another row is not undone.
                    .popover(isPresented: Binding(get: { open == m.id }, set: { if !$0, open == m.id { open = nil } }), arrowEdge: .trailing) {
                        BridgeCard(move: m) { open = nil }.onAppear { seen.insert(m.id) }
                    }
            }
        }
    }

    private func row(_ m: BridgeMove) -> some View {
        HStack(spacing: 12) {
            Image(systemName: m.symbol).frame(width: 28).foregroundStyle(Theme.accentInk).accessibilityHidden(true)
            Text(m.caddy).themeFont(.heading).foregroundStyle(Theme.ink).frame(width: 90, alignment: .leading)
            Image(systemName: "arrow.right").foregroundStyle(Theme.muted).accessibilityHidden(true)
            Text(m.tinkercad).themeFont(.body).foregroundStyle(Theme.ink)
            Spacer()
            if seen.contains(m.id) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent).accessibilityHidden(true) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows where this lives in Tinkercad")
    }
}

/// The little pop-up: Caddy, a picture, three short steps and a Got it button.
private struct BridgeCard: View {
    let move: BridgeMove
    let done: () -> Void
    @Environment(\.textScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                CaddyView(pose: .pointRight, size: 44, wave: false)
                Text("In Tinkercad: \(move.tinkercad)").themeFont(.overlay).foregroundStyle(Theme.ink).accessibilityAddTraits(.isHeader)
            }
            picture
            ForEach(Array(move.steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").themeFont(.chip).monospacedDigit().foregroundStyle(Theme.accentInk).frame(width: 18)
                    Text(s).themeFont(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            HStack { Spacer(); Button("Got it", action: done).buttonStyle(.borderedProminent).tint(Theme.accent).keyboardShortcut(.defaultAction) }
        }
        .padding(16)
        .frame(width: 340 * scale)
        .background(Theme.panel)
    }

    /// A real screenshot if one is in Resources/Bridge, otherwise a drawn icon.
    @ViewBuilder private var picture: some View {
        if let url = Bundle.module.url(forResource: move.id, withExtension: "png", subdirectory: "Bridge"),
           let img = NSImage(contentsOf: url) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("Screenshot of \(move.tinkercad) in Tinkercad")
        } else {
            Image(systemName: move.symbol).font(.system(size: 40)).foregroundStyle(Theme.accentInk)
                .frame(maxWidth: .infinity).frame(height: 90)
                .background(Theme.accentSoft.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// The Tinkercad sheet with two tabs: the steps to open it, and the bridge guide.
struct TinkercadTabs: View {
    let stlURL: URL?
    @State private var tab = 0
    var body: some View {
        VStack(spacing: 0) {
            Picker("Tinkercad help", selection: $tab) {
                Text("Open it").tag(0)
                Text("Learn the moves").tag(1)
            }
            .pickerStyle(.segmented).labelsHidden().padding([.horizontal, .top], 24)
            // Both tabs stay alive so the sheet keeps its height and each tab keeps its state.
            ZStack(alignment: .top) {
                TinkercadHelp(stlURL: stlURL)
                    .opacity(tab == 0 ? 1 : 0).disabled(tab != 0).accessibilityHidden(tab != 0)
                VStack(alignment: .leading, spacing: 12) {
                    TinkercadBridge()
                    Spacer(minLength: 0)
                    HStack { Spacer(); CloseButton() }
                }
                .padding(24).frame(width: 480).frame(maxHeight: .infinity)
                .opacity(tab == 1 ? 1 : 0).disabled(tab != 1).accessibilityHidden(tab != 1)
            }
        }
    }
}

private struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View { Button("Close") { dismiss() }.keyboardShortcut(.cancelAction) }
}
