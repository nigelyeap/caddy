import SwiftUI
import CADShared

/// Saved builds: plain STL files in Application Support. The name lives in the file name, so there is no index to break.
@MainActor final class BuildLibrary: ObservableObject {
    struct Item: Identifiable, Equatable {
        let url: URL
        let name: String
        let date: Date
        var id: String { url.lastPathComponent }
        /// A build of parts keeps a sidecar next to its merged STL, so it reopens as parts.
        var sidecar: URL? {
            // The helper writes "name.stl.parts/parts.json" next to the merged STL.
            let side = url.appendingPathExtension("parts")
            return FileManager.default.fileExists(atPath: side.appendingPathComponent("parts.json").path) ? side : nil
        }
    }

    @Published private(set) var items: [Item] = []
    private let dir: URL
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    init(dir: URL? = nil) {
        self.dir = dir ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CADDY/Builds", isDirectory: true)
        reload()
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        items = files.filter { $0.pathExtension.lowercased() == "stl" }.compactMap { url in
            let parts = url.deletingPathExtension().lastPathComponent.components(separatedBy: " -- ")
            guard parts.count == 2, let date = Self.stamp.date(from: parts[0]) else { return nil }
            return Item(url: url, name: parts[1], date: date)
        }
        .sorted { $0.date > $1.date }
    }

    /// Copies the model into the library and returns the new item.
    @discardableResult func save(_ stl: URL, name: String) throws -> Item {
        let url = try newURL(name: name)
        try FileManager.default.copyItem(at: stl, to: url)
        reload()
        return items.first { $0.id == url.lastPathComponent } ?? Item(url: url, name: name, date: Date())
    }

    /// Where a new build with this name goes. The helper writes builds of parts here itself.
    func newURL(name: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let clean = String(name.filter { $0.isLetter || $0.isNumber || $0 == " " }.prefix(30))
            .trimmingCharacters(in: .whitespaces)
        return dir.appendingPathComponent("\(Self.stamp.string(from: Date())) -- \(clean.isEmpty ? "My build" : clean).stl")
    }

    func delete(_ item: Item) {
        if let side = item.sidecar { try? FileManager.default.removeItem(at: side) }
        try? FileManager.default.removeItem(at: item.url)
        reload()
    }
}

/// "My builds": a save button and the saved builds, newest first. Tap one to open it.
struct BuildsSection: View {
    @ObservedObject var builds: BuildLibrary
    var canSave: Bool
    let save: () -> Void
    let open: (BuildLibrary.Item) -> Void
    @State private var showAll = false

    var body: some View {
        let limit = 4
        let shown = showAll ? builds.items : Array(builds.items.prefix(limit))
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                SectionHeader(title: "My builds")
                Spacer()
                if canSave {
                    Button("Save", systemImage: "square.and.arrow.down", action: save)
                        .buttonStyle(ChipButtonStyle(tint: Theme.tintAdd))
                        .help("Keep this build so you can come back to it")
                        .fixedSize()
                }
            }
            if builds.items.isEmpty {
                Text("Saved builds show up here, so you can come back to them.")
                    .themeFont(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(shown) { item in
                Button { open(item) } label: {
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: item.sidecar == nil ? "cube.fill" : "square.stack.3d.up.fill")
                            .foregroundStyle(Theme.gold).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.name).themeFont(.secondary).foregroundStyle(Theme.ink).lineLimit(1)
                            Text(item.date.formatted(date: .abbreviated, time: .shortened))
                                .themeFont(.caption).foregroundStyle(Theme.muted)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).strokeBorder(Theme.line))
                }
                .buttonStyle(.plain)
                .help("Open this build")
                .contextMenu { Button("Delete this build", role: .destructive) { builds.delete(item) } }
            }
            if builds.items.count > limit {
                Button(showAll ? "Show fewer" : "Show all \(builds.items.count)") { showAll.toggle() }
                    .buttonStyle(.link).themeFont(.caption)
            }
        }
    }
}
