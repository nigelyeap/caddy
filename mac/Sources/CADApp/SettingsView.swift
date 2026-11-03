import SwiftUI
import AppKit
import CADShared

struct SettingsView: View {
    @ObservedObject var helper: Helper
    @AppStorage("cameraID") private var cameraID = ""
    @AppStorage("helperPort") private var port = 8000
    @AppStorage("teacherMode") private var teacherMode = false
    @AppStorage("textSize") private var textSize = TextSize.large
    @AppStorage("soundEnabled") private var soundOn = true
    @AppStorage("seenIntro") private var seenIntro = false
    @State private var cameras: [(id: String, name: String)] = []

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Camera", selection: $cameraID) {
                    Text("Automatic").tag("")
                    ForEach(cameras, id: \.id) { Text($0.name).tag($0.id) }
                }
                .onChange(of: cameraID) { _, id in if !id.isEmpty { chooseCamera(id) } }
                Text("A nearby iPhone can be used through Continuity Camera.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Display and sound") {
                Picker("Text size", selection: $textSize) {
                    ForEach(TextSize.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Sounds", isOn: $soundOn)
                Toggle("Show diagnostics button", isOn: $teacherMode)
                Text("Adds a toolbar button with the helper log and which engine is running.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Show the intro next time") { seenIntro = false }
                    .disabled(!seenIntro)
            }
            Section("Claude") {
                LabeledContent("Claude key") {
                    Label(helper.hasAPIKey ? "Found" : "Not set",
                          systemImage: helper.hasAPIKey ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(helper.hasAPIKey ? Theme.good : Theme.warn)
                }
                Text(helper.hasAPIKey
                     ? "Students can describe their own changes."
                     : Helper.bundledRuntime == nil
                        ? "Only the quick changes work. Add ANTHROPIC_API_KEY to the .env file in the project folder, then reopen the app."
                        : "Only the quick changes work. Add ANTHROPIC_API_KEY to a .env file in ~/Library/Application Support/CADDY, then reopen the app.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Helper") {
                LabeledContent("Port") {
                    TextField("Port", value: $port, format: .number.grouping(.never))
                        .labelsHidden().frame(width: 90).multilineTextAlignment(.trailing)
                }
                Text("Applies the next time the app opens. If the port is busy, the next free one is used.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Saved models") {
                    Button("Show in Finder") { openDataFolder() }
                        .disabled(dataFolder == nil)
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { cameras = cameraChoices() }
    }

    private var dataFolder: URL? {
        if Helper.bundledRuntime != nil { return Helper.supportFolder.appendingPathComponent("data", isDirectory: true) }
        return CADDYApp.projectRoot.map { $0.appendingPathComponent("webapp/data", isDirectory: true) }
    }

    private func openDataFolder() {
        guard let url = dataFolder else { return }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }
}
