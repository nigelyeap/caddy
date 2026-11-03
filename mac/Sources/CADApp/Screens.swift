import SwiftUI
import AppKit
import CADShared
import CADViewer

// MARK: Launch

struct LaunchView: View {
    let failure: String?
    let diagnostics: String
    let retry: () -> Void
    @State private var startedAt = Date()
    @State private var showDetails = false

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            if failure == nil {
                TalkingCaddy(moment: .launch, pose: .hatching, size: 96)
            } else {
                CaddyView(pose: .sad, size: 96)
            }
            if let failure {
                Text("CADDY could not get ready").themeFont(.title).foregroundStyle(Theme.ink)
                Text("Ask your teacher to help. They can look at the details.")
                    .themeFont(.body).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                HStack(spacing: Theme.Space.xs) {
                    Button("Show details") { showDetails.toggle() }.buttonStyle(BigButtonStyle(.secondary))
                    Button("Try again", action: retry).buttonStyle(BigButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                }
                if showDetails {
                    // The raw reason is for the teacher, so it lives with the other details.
                    TeacherDetails(text: diagnostics.isEmpty ? failure : failure + "\n\n" + diagnostics)
                        .frame(maxWidth: 560)
                }
            } else {
                HStack(spacing: Theme.Space.xs) {
                    ProgressView().controlSize(.small)
                    Text("Getting ready…").themeFont(.body).foregroundStyle(Theme.muted)
                }
                TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
                    if ctx.date.timeIntervalSince(startedAt) > 10 {
                        VStack(spacing: Theme.Space.xs) {
                            Text("This is taking a bit longer than normal.").themeFont(.secondary).foregroundStyle(Theme.muted)
                            Button("Show details") { showDetails.toggle() }.buttonStyle(BigButtonStyle(.secondary, compact: true))
                        }
                    }
                }
                if showDetails {
                    TeacherDetails(text: diagnostics.isEmpty ? "Nothing to show yet." : diagnostics)
                        .frame(maxWidth: 560)
                }
            }
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Shared pieces

/// The three steps of the app, with the current one marked. Used on the first run and scan screens.
struct WorkflowSteps: View {
    var current: Int? = nil
    @Environment(\.textScale) private var scale
    // Names match the toolbar breadcrumb. Each step has its own soft tint for the icon well.
    private let steps: [(String, String, String, Theme.Tint)] = [
        ("Scan", "Film your object from every side.", "camera.viewfinder", Theme.tintSize),
        ("Process", "CADDY turns it into a 3D model. A video takes about a minute.", "wand.and.stars", Theme.tintSun),
        ("Edit", "Tell CADDY what to change. Then save it for the 3D printer.", "paintbrush.pointed", Theme.tintAdd),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                if i > 0 { Divider() }
                HStack(alignment: .top, spacing: Theme.Space.s) {
                    Image(systemName: step.2)
                        .font(.system(size: 14 * scale, weight: .semibold))
                        .foregroundStyle(step.3.ink)
                        .frame(width: 30 * scale, height: 30 * scale)
                        .background(Circle().fill(step.3.fill))
                        .overlay(Circle().strokeBorder(i == current ? step.3.ink : step.3.edge, lineWidth: i == current ? 2 : 1))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(i + 1). \(step.0)").themeFont(.heading).foregroundStyle(Theme.ink)
                        Text(step.1).themeFont(.secondary).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if i == current { Text("You are here").chip(tint: Theme.tintAccent) }
                }
                .padding(.vertical, Theme.Space.s)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A small titled list of plain sentences with check marks.
private struct TipList: View {
    let title: String
    let tips: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: title)
            ForEach(tips, id: \.self) { tip in
                Label {
                    Text(tip).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                }
                .themeFont(.secondary).foregroundStyle(Theme.ink)
            }
        }
    }
}

private let scanTips = [
    "Things that are not shiny work best",
    "Bright, even light with no dark shadows",
    "A plain table with nothing else on it",
    "Keep all of your object in the picture",
]

// MARK: Scan side panel

/// Sits beside the camera so the scan screen shows where you are and the other ways in.
struct ScanSidePanel: View {
    @ObservedObject var builds: BuildLibrary
    let openBuild: (BuildLibrary.Item) -> Void
    let openFile: () -> Void
    let sample: () -> Void
    let openTurntable: () -> Void
    let turntableSample: () -> Void
    @State private var showTurntableHelp = false
    @Environment(\.textScale) private var textScale
    var body: some View {
        TutorialScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 0) {
                    SectionHeader(title: "Steps")
                    WorkflowSteps(current: 0)
                }
                if !builds.items.isEmpty {
                    BuildsSection(builds: builds, canSave: false, save: {}, open: openBuild)
                    Divider()
                }
                TipList(title: "For a good scan", tips: scanTips)
                Divider()
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionHeader(title: "No camera? No problem")
                    Text("Open a model or a video you already have. Or practise with the sample.")
                        .themeFont(.secondary).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open a model file…", systemImage: "folder", action: openFile)
                        .buttonStyle(ChipButtonStyle(tint: Theme.tintSize))
                    Button("Use the sample model", systemImage: "cube", action: sample)
                        .buttonStyle(ChipButtonStyle(tint: Theme.tintAdd))
                        .tutorialTarget(.sampleChip)
                }
                Divider()
                turntable
            }
            .padding(Theme.panelPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.panel)
        .sheet(isPresented: $showTurntableHelp) {
            TurntableHelpSheet(open: openTurntable, sample: turntableSample)
                .environment(\.textScale, textScale)
        }
    }

    private var turntable: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionHeader(title: "Turntable scanner")
            Text("Used the turntable? Open the file from its SD card.")
                .themeFont(.secondary).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Scan from turntable…", systemImage: "sdcard", action: openTurntable)
                .buttonStyle(ChipButtonStyle(tint: Theme.tintSun))
                .accessibilityHint("Opens a scan file from the turntable SD card")
            Button("How to use the turntable", systemImage: "questionmark.circle") { showTurntableHelp = true }
                .buttonStyle(ChipButtonStyle())
                .accessibilityHint("Shows the steps for the turntable scanner")
            Button("Try a sample turntable scan", systemImage: "cylinder", action: turntableSample)
                .buttonStyle(ChipButtonStyle())
                .accessibilityHint("Opens a practice scan of a cylinder")
        }
    }
}

// MARK: Turntable help

/// Five steps for the turntable scanner, then open the SD card file or try the sample.
struct TurntableHelpSheet: View {
    let open: () -> Void
    let sample: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textScale) private var textScale

    private let steps = [
        "Put your object in the middle of the turntable.",
        "Press the button on the scanner.",
        "Wait until it stops. This takes about 10 minutes.",
        "Take the SD card out and put it in the Mac.",
        "Open the file here. It is usually called scan_001.txt.",
    ]
    private let tips = [
        "Things that are not shiny work best",
        "Shiny, see-through or dark things come out blobby",
        "Things up to about 12 cm wide, about as big as your hand",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Text("How to scan with the turntable").themeFont(.title).foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                                Text("\(i + 1)")
                                    .themeFont(.heading).monospacedDigit()
                                    .foregroundStyle(Theme.tintSize.ink)
                                    .frame(width: 24 * textScale, height: 24 * textScale)
                                    .background(Circle().fill(Theme.tintSize.fill))
                                    .overlay(Circle().strokeBorder(Theme.tintSize.edge, lineWidth: 1))
                                Text(step).themeFont(.body).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Step \(i + 1) of \(steps.count). \(step)")
                        }
                    }
                    Divider()
                    TipList(title: "For a good turntable scan", tips: tips)
                }
                .padding(Theme.Space.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xs) { buttons }
                VStack(alignment: .leading, spacing: Theme.Space.xs) { buttons }
            }
            .padding(Theme.Space.m)
        }
        .frame(width: 480 * textScale)
        .frame(minHeight: 360, idealHeight: 520 * textScale)
        .background(Theme.panel)
    }

    @ViewBuilder private var buttons: some View {
        Button("Open the scan file…") { dismiss(); open() }
            .buttonStyle(BigButtonStyle(.primary, compact: true)).fixedSize()
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Opens a scan file from the turntable SD card")
        Button("Try the sample") { dismiss(); sample() }
            .buttonStyle(BigButtonStyle(.secondary, compact: true)).fixedSize()
            .accessibilityHint("Opens a practice scan of a cylinder")
        Spacer(minLength: 0)
        Button("Close") { dismiss() }
            .buttonStyle(BigButtonStyle(.secondary, compact: true)).fixedSize()
            .keyboardShortcut(.cancelAction)
    }
}

// MARK: First run

struct FirstRunView: View {
    let start: () -> Void
    let sample: () -> Void
    /// While the Caddy tour shows, Return belongs to the tour bubble.
    var tutorialOn = false
    @StateObject private var stage = ViewerController()
    private let mug = Bundle.module.url(forResource: "mug", withExtension: "stl")

    var body: some View {
        HStack(spacing: 0) {
            // Text sits on a solid panel beside the stage, so it never overlaps the model.
            TutorialScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    hello
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("What do you want to do?").themeFont(.heading).foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Button(action: start) {
                            ChoiceLabel(title: "Start scanning", detail: "Film a small thing from every side.",
                                        symbol: "camera.viewfinder", tint: Theme.tintSize)
                        }
                        .buttonStyle(ChoiceCardStyle(tint: Theme.tintSize, main: true))
                        .keyboardShortcut(tutorialOn ? nil : .defaultAction)
                        .tutorialTarget(.startScanning)
                        Button(action: sample) {
                            ChoiceLabel(title: "Use the sample model", detail: "Practise on a cup we made for you.",
                                        symbol: "cup.and.saucer", tint: Theme.tintAdd)
                        }
                        .buttonStyle(ChoiceCardStyle(tint: Theme.tintAdd, main: false))
                    }
                    stepsCard
                    tipsCard
                    Label("You can also drag a 3D model, a video or a turntable scan onto this window.",
                          systemImage: "tray.and.arrow.down")
                        .themeFont(.secondary).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.Space.xl)
            }
            .frame(width: 460)
            .background(Theme.panel)
            Divider()
            ModelViewer(stlURL: mug, revision: 0, controller: stage)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.line))
                .padding(Theme.Space.s)
                .background(Theme.background)
                .accessibilityHidden(true)
        }
        .onAppear { stage.autoRotate = true }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Caddy says hello in a soft sunny bubble. The words do the talking, so the picture is hidden from VoiceOver.
    private var hello: some View {
        HStack(alignment: .center, spacing: Theme.Space.s) {
            TalkingCaddy(moment: .home, pose: .hello, size: 80, bubbleAlignment: .bottomLeading)
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Hi, I'm Caddy!").themeFont(.title).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Let's turn a real thing into a 3D model you can print.")
                    .themeFont(.body).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: Theme.Space.s, tint: Theme.tintSun)
        .accessibilityElement(children: .combine)
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "How it works")
            WorkflowSteps()
        }
        .card(padding: Theme.panelPadding)
    }

    private var tipsCard: some View {
        TipList(title: "For a good scan", tips: scanTips)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: Theme.panelPadding)
    }
}

// MARK: Processing

struct ProcessingView: View {
    let processing: AppModel.Processing
    let back: () -> Void
    let sample: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            preview
                .padding(Theme.screenMargin)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if let failure = processing.failure { failed(failure) } else { working }
                }
                .padding(Theme.panelPadding)
                // The whole panel, so the failure and Back to scan buttons stay clickable during the tour.
                .tutorialTarget(.processStatus)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(width: 320)
            .background(Theme.panel)
        }
    }

    /// Where the model will appear. Caddy works here on a calm backdrop, never on the 3D stage.
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
                .fill(LinearGradient(colors: [Theme.stageTop, Theme.stageBottom], startPoint: .top, endPoint: .bottom))
            RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous).strokeBorder(Theme.line)
            VStack(spacing: Theme.Space.s) {
                if processing.failure == nil {
                    TalkingCaddy(moment: .process, pose: .thinking, size: 120, idle: true)
                    VStack(spacing: Theme.Space.xs) {
                        HStack(spacing: Theme.Space.xs) {
                            ProgressView().controlSize(.small)
                            Text(stages[min(processing.stage.rawValue, stages.count - 1)])
                                .themeFont(.heading).foregroundStyle(Theme.ink)
                        }
                        FunLine(start: processing.startedAt)
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                    .card(padding: 0)
                } else {
                    TalkingCaddy(moment: .processFailed, pose: .sad, size: 120)
                    Text("No model this time").themeFont(.heading).foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.s)
                        .card(padding: 0)
                }
            }
            .multilineTextAlignment(.center)
            .padding(Theme.Space.l)
        }
    }

    private var sourceText: String {
        switch processing.source {
        case .sample: "Sample model"
        case .mesh: "Your model file"
        case .video: "Your video"
        }
    }

    private var stages: [String] {
        let first = switch processing.source {
        case .sample: "Getting the sample"
        case .mesh: "Opening your file"
        case .video: "Sending your video"
        }
        return [first, "Building your model", "Ready to edit"]
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                Text("Making your model").themeFont(.title).foregroundStyle(Theme.ink)
                HStack(spacing: 6) {
                    Text(sourceText)
                    Text("·")
                    TimelineView(.periodic(from: processing.startedAt, by: 1)) { ctx in
                        Text("\(max(0, Int(ctx.date.timeIntervalSince(processing.startedAt)))) seconds").monospacedDigit()
                    }
                }
                .themeFont(.secondary).foregroundStyle(Theme.muted)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                SectionHeader(title: "What I'm doing")
                ForEach(Array(stages.enumerated()), id: \.offset) { i, label in
                    stageRow(i, label)
                }
            }
            .accessibilityElement(children: .contain)
            Divider()
            VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                SectionHeader(title: "What happens next")
                Text("The next screen opens by itself. A video takes about a minute. A file or the sample takes a few seconds.")
                    .themeFont(.secondary).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TimelineView(.periodic(from: processing.startedAt, by: 1)) { ctx in
                if Int(ctx.date.timeIntervalSince(processing.startedAt)) >= 60 && processing.stage != .ready {
                    VStack(alignment: .leading, spacing: Theme.Space.xs) {
                        Label("This is taking a long time. You can go back and try again.", systemImage: "clock")
                            .themeFont(.secondary).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Button("Back to scan", action: back).buttonStyle(BigButtonStyle(.secondary, compact: true))
                    }
                    .card(padding: Theme.Space.s, tint: Theme.tintSun)
                }
            }
        }
    }

    private func stageRow(_ i: Int, _ label: String) -> some View {
        let at = processing.stage.rawValue
        let done = i < at || (i == at && processing.stage == .ready)
        let current = i == at && !done
        return HStack(spacing: Theme.Space.xs) {
            ZStack {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.good)
                } else if current {
                    ProgressView().controlSize(.mini)
                } else {
                    Circle().strokeBorder(Theme.line, lineWidth: 1.5).frame(width: 12, height: 12)
                }
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 18, height: 18)
            Text(label)
                .themeFont(.body)
                .fontWeight(current ? .medium : .regular)
                .foregroundStyle(i > at ? Theme.muted : Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(done ? "done" : current ? "working" : "waiting")")
    }

    private func failed(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Label("Oops, that did not work", systemImage: "exclamationmark.triangle.fill")
                .themeFont(.title).foregroundStyle(Theme.ink)
                .labelStyle(TintedIconLabel(tint: Theme.bad))
            Text(note.text).themeFont(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("It happens to everyone. Let's try again.")
                .themeFont(.secondary).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            if let d = note.detail, !d.isEmpty { TeacherDetails(text: d) }
            Divider()
            TipList(title: "Next time, try this", tips: scanTips)
            Divider()
            Button("Back to scan", action: back)
                .buttonStyle(BigButtonStyle(.primary)).keyboardShortcut(.defaultAction)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Use the sample model", action: sample).buttonStyle(BigButtonStyle(.secondary))
        }
    }
}

private struct TintedIconLabel: LabelStyle {
    let tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) { configuration.icon.foregroundStyle(tint); configuration.title }
    }
}

/// A short friendly line under the wait spinner. It changes every 6 seconds.
/// Text only, so it is fine with Reduce Motion. The cross-fade turns off there. VoiceOver skips it,
/// because the stage line beside it already says what is going on.
private struct FunLine: View {
    let start: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let lines = [
        "Hang on. Good things take a little time.",
        "I'm putting all the pieces together.",
        "Your model is on its way.",
        "Thanks for waiting. You're doing great.",
    ]
    var body: some View {
        TimelineView(.periodic(from: start, by: 6)) { ctx in
            let i = Int(max(0, ctx.date.timeIntervalSince(start)) / 6) % Self.lines.count
            Text(Self.lines[i])
                .themeFont(.secondary).foregroundStyle(Theme.muted)
                .id(i)
                .transition(.opacity)
                .animation(Theme.motion(reduceMotion), value: i)
        }
        .accessibilityHidden(true)
    }
}

/// The text inside a big start-screen choice: an icon well, a title, one short line and a chevron.
private struct ChoiceLabel: View {
    let title: String
    let detail: String
    let symbol: String
    let tint: Theme.Tint
    @Environment(\.textScale) private var scale
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 20 * scale, weight: .semibold))
                .foregroundStyle(tint.ink)
                .frame(width: 44 * scale, height: 44 * scale)
                .background(Circle().fill(Theme.panel))
                .overlay(Circle().strokeBorder(tint.edge, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).themeFont(.overlay).foregroundStyle(Theme.ink)
                Text(detail).themeFont(.secondary).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(tint.ink)
                .accessibilityHidden(true)
        }
        .multilineTextAlignment(.leading)
    }
}

/// A big soft tinted card that is a button. The main choice gets a stronger border, so the
/// difference never rests on colour alone. Hover and press only change the border and a light shade.
private struct ChoiceCardStyle: ButtonStyle {
    let tint: Theme.Tint
    let main: Bool
    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, tint: tint, main: main)
    }
    private struct CardBody: View {
        let configuration: Configuration
        let tint: Theme.Tint
        let main: Bool
        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hover = false
        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
            let pressed = configuration.isPressed && enabled
            configuration.label
                .padding(Theme.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(tint.fill, in: shape)
                .overlay(shape.strokeBorder(main || hover ? tint.ink : tint.edge, lineWidth: main ? 2 : 1))
                .overlay(shape.fill(Theme.ink.opacity(pressed ? 0.08 : 0)))
                .shadow(color: Theme.shadow, radius: hover && enabled ? 10 : 6, y: hover && enabled ? 4 : 2)
                .scaleEffect(pressed && !reduceMotion ? 0.98 : 1)
                .animation(Theme.spring(reduceMotion), value: pressed)
                .animation(Theme.motion(reduceMotion), value: hover)
                .opacity(enabled ? 1 : 0.45)
                .contentShape(shape)
                .onHover { hover = $0 }
        }
    }
}
