import SwiftUI
import AppKit
import CADShared

struct EditScreen: View {
    @ObservedObject var model: AppModel
    var focus: FocusState<Bool>.Binding
    let save: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HSplitView {
            viewer
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            Inspector(model: model, focus: focus, save: save)
                .frame(minWidth: 340, idealWidth: 360, maxWidth: 440, maxHeight: .infinity)
        }
    }

    private var viewer: some View {
        let stageShape = RoundedRectangle(cornerRadius: Theme.cornerLarge, style: .continuous)
        return ZStack {
            ViewerStep(stlURL: model.stlURL, revision: model.revision, highlightChange: model.lastChangeWasEdit,
                       controller: model.viewer)
                .tutorialTarget(.viewer)
            // Size top left, Caddiy bottom right, view controls bottom centre, so they never overlap.
            VStack {
                HStack { ViewerSizeBadge(controller: model.viewer); Spacer() }
                Spacer()
                ViewerButtons(controller: model.viewer)
            }
            .padding(Theme.Space.s)
            StageCaddiy(model: model)
            if let since = model.editStartedAt {
                ZStack {
                    // The model stays visible under a dim. Nothing loops, only the timer ticks.
                    Theme.viewer.opacity(reduceTransparency ? 0.7 : 0.4)
                    HStack(spacing: Theme.Space.xs) {
                        Image(systemName: "wand.and.stars").foregroundStyle(Theme.gold).accessibilityHidden(true)
                        Text("Applying the change").themeFont(.body).foregroundStyle(Theme.ink)
                        ElapsedText(since: since).themeFont(.body).foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, Theme.Space.m).padding(.vertical, Theme.Space.xs)
                    .card(padding: 0)
                    .accessibilityElement(children: .combine)
                }
                .transition(.opacity)
            }
        }
        .clipShape(stageShape)
        .overlay(stageShape.strokeBorder(Theme.line, lineWidth: 1))
        .padding(Theme.Space.s)
        .background(Theme.background)
        .animation(Theme.motion(reduceMotion), value: model.isEditing)
    }
}

/// Caddiy in the stage corner. Says something short after a change, or when clicked, then goes quiet.
/// Steps aside whenever the model would sit under it.
private struct StageCaddiy: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.textScale) private var scale
    @State private var saying: CaddiyLine?
    @State private var last: CaddiyLine?
    @State private var hop = false
    @State private var covered = false
    @State private var corner: Alignment = .bottomTrailing

    private var caddiy: some View {
        Button { say(.edit) } label: {
            // The pose follows the line. A plain swap, no cross fade.
            CaddiyView(pose: saying?.pose ?? .hello, size: 76, wave: false)
                .transaction { $0.animation = nil }
                .offset(y: hop ? -6 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click Caddiy for a tip")
        .accessibilityLabel("Caddiy")
        .accessibilityHint("Says a tip")
        .allowsHitTesting(!covered)
        .accessibilityHidden(covered)
    }

    var body: some View {
        let side = 76 * scale
        let leading = corner == .bottomLeading
        GeometryReader { geo in
            HStack(alignment: corner == .topTrailing ? .top : .bottom, spacing: 4) {
                if leading { caddiy }
                if let saying {
                    CaddiyBubble(text: saying.text)
                        .padding(corner == .topTrailing ? .top : .bottom, side * 0.55)
                        .transition(reduceMotion ? .identity
                                    : .scale(scale: 0.6, anchor: leading ? .bottomLeading : corner == .topTrailing ? .topTrailing : .bottomTrailing).combined(with: .opacity))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if !leading { caddiy }
            }
            .padding(Theme.Space.s)
            // Top right sits below the size badge row so the two never touch.
            .padding(.top, corner == .topTrailing ? 44 : 0)
            .frame(width: geo.size.width, height: geo.size.height, alignment: corner)
            .opacity(covered ? 0 : 1)
            .task(id: geo.size) {
                // Cheap check twice a second: eight projected box corners.
                // Tries bottom right, then top right, then bottom left. Hides when the model reaches all three.
                // ponytail: checks Caddiy only, the short-lived bubble may brush the model's edge.
                while !Task.isCancelled {
                    let w = geo.size.width, h = geo.size.height, bw = side + 16, bh = side + 24
                    let spots: [(Alignment, CGRect)] = [
                        (.bottomTrailing, CGRect(x: w - bw, y: h - bh, width: bw, height: bh)),
                        (.topTrailing, CGRect(x: w - bw, y: 44, width: bw, height: bh)),
                        (.bottomLeading, CGRect(x: 0, y: h - bh, width: bw, height: bh)),
                    ]
                    let free = model.viewer.modelRect().flatMap { m in spots.first { !$0.1.intersects(m) }?.0 }
                    if (free == nil) != covered || (free != nil && free != corner) {
                        withAnimation(Theme.motion(reduceMotion)) {
                            covered = free == nil
                            if let free { corner = free }
                        }
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        .onChange(of: model.revision) { _, _ in
            guard model.lastChangeWasEdit else { return }
            say(.afterChange, announce: false)
        }
        .task(id: saying) {
            guard let now = saying else { return }
            try? await Task.sleep(for: .seconds(now.then.isEmpty ? 3 : 2))
            guard !Task.isCancelled else { return }
            withAnimation(Theme.motion(reduceMotion)) { saying = now.then.first }
        }
    }

    private func say(_ moment: CaddiyMoment, announce: Bool = true) {
        let line = CaddiyLines.pick(moment, after: last)
        last = line
        withAnimation(Theme.spring(reduceMotion)) { saying = line }
        if announce { AccessibilityNotification.Announcement(line.text).post() }
        guard announce, !reduceMotion else { return }
        withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) { hop = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { hop = false }
        }
    }
}

private struct Inspector: View {
    @ObservedObject var model: AppModel
    var focus: FocusState<Bool>.Binding
    let save: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var help: HelpSheetKind?
    @State private var showAllHistory = false
    @State private var showMoreIdeas = false

    /// The original scan is version 1, so anything past it is a change.
    private var hasChanges: Bool { (model.state?.versions.count ?? 0) > 1 }
    private var canChange: Bool { !model.isEditing && model.connected }

    var body: some View {
        TutorialScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                if model.state?.sample == true {
                    Text("Sample model. Open a scan file to work on your own object.")
                        .themeFont(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                changeSection
                quickSection
                Divider()
                BuildsSection(builds: model.builds, canSave: canChange, save: { model.saveBuild() }, open: model.openBuild)
                Divider()
                historySection
                Divider()
                modelSection
            }
            .padding(Theme.panelPadding)
        }
        // Saving stays in view however long the history gets.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            saveSection
                // The stacked layout at big text hugs its content, so fill the width or the bar floats off centre.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.panelPadding)
                .background(Theme.background)
                .overlay(alignment: .top) { Divider() }
        }
        .background(Theme.panel)
    }

    // MARK: Change

    private var changeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            InspectorHeader(title: "Describe a change", symbol: "text.bubble")
            // Caddiy only chimes in before the first change, so the panel goes quiet once the kid has started.
            if !hasChanges && model.draft.isEmpty {
                HStack(alignment: .center, spacing: Theme.Space.xs) {
                    TalkingCaddiy(moment: .edit, pose: .idea, size: 34, bubbleAlignment: .topLeading)
                    Text("Tell me what to change, in your own words.")
                        .themeFont(.secondary).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Theme.tintSun.fill, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                            .strokeBorder(Theme.tintSun.edge))
                }
                .transition(.opacity)
            }
            TextField("Try: make it 20 percent taller", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .themeFont(.body)
                .lineLimit(2...5)
                .padding(10)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                    .strokeBorder(focus.wrappedValue ? Theme.focus : Theme.line, lineWidth: focus.wrappedValue ? 2 : 1))
                .focused(focus)
                .disabled(model.isEditing)
                .onKeyPress(keys: [.return]) { press in
                    if press.modifiers.contains(.shift) { model.draft += "\n" } else { model.send(model.draft) }
                    return .handled
                }
                .accessibilityLabel("Describe a change")
                .accessibilityHint("Press Return to apply. Shift Return adds a line.")
            HStack(spacing: Theme.Space.xs) {
                Text("Return to apply").themeFont(.caption).foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
                Button { model.send(model.draft) } label: {
                    if let since = model.editStartedAt {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            ElapsedText(since: since, prefix: "Applying, ")
                        }
                    } else {
                        Label("Apply", systemImage: "wand.and.stars").frame(minWidth: 84)
                    }
                }
                // Before the first change, Apply is the main action. After it, Save takes over.
                .buttonStyle(BigButtonStyle(hasChanges ? .secondary : .primary))
                .disabled(!canChange)
            }
        }
        .animation(Theme.motion(reduceMotion), value: model.draft.isEmpty)
    }

    private var quickSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            InspectorHeader(title: "Quick changes", symbol: "sparkles")
            ForEach(Ideas.groups, id: \.self, content: ideaGroup)
            Button {
                withAnimation(Theme.motion(reduceMotion)) { showMoreIdeas.toggle() }
            } label: {
                Label(showMoreIdeas ? "Fewer ideas" : "More ideas: ears, lids, patterns…",
                      systemImage: showMoreIdeas ? "chevron.up" : "chevron.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(BigButtonStyle(.secondary, compact: true))
            if showMoreIdeas { ForEach(Ideas.moreGroups, id: \.self, content: ideaGroup) }
        }
        .disabled(!canChange)
    }

    /// One block per group: a tinted icon and the name on top, then two columns of tinted chips.
    private func ideaGroup(_ group: String) -> some View {
        let tint = Theme.tint(forGroup: group)
        let shape = RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: 6) {
                Image(systemName: Ideas.symbol(forGroup: group))
                    .themeFont(.caption).fontWeight(.semibold)
                    .foregroundStyle(tint.ink)
                    .frame(width: 22, height: 22)
                    .background(tint.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint.edge))
                Text(group).themeFont(.secondary).fontWeight(.semibold).foregroundStyle(Theme.ink)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 10) {
                ForEach(Ideas.all.filter { $0.group == group }) { idea in
                    Button { model.pick(idea) } label: {
                        Label(idea.short, systemImage: idea.symbol)
                    }
                    .buttonStyle(TileButtonStyle(tint: tint))
                    .tutorialTarget(idea.short == "Taller" ? .taller : nil)
                    .help(idea.fill ? idea.label + ". Type it, then press Return." : idea.label)
                    .accessibilityHint(idea.fill ? "Starts the words for you to finish" : "Applies: \(idea.text)")
                }
            }
        }
        .padding(10)
        .background(Theme.panel, in: shape)
        .overlay(shape.strokeBorder(tint.edge))
    }

    // MARK: History

    private var historySection: some View {
        let versions = model.state?.versions ?? []
        let undone = Array((model.state?.redo ?? []).reversed())
        let rows: [(index: Int, text: String, isNow: Bool, undone: Bool)] =
            versions.enumerated().map { ($0.offset, $0.element.instruction, $0.offset == versions.count - 1, false) }
            + undone.enumerated().map { (versions.count + $0.offset, $0.element.instruction, false, true) }
        // Show the newest few by default. The rest fold away.
        let limit = 5
        let shown = showAllHistory ? rows : Array(rows.suffix(limit))
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                InspectorHeader(title: "History", symbol: "clock.arrow.circlepath",
                                trailing: versions.isEmpty ? nil : "\(versions.count)")
                Spacer()
                HStack(spacing: 4) {
                    Button("Undo", systemImage: "arrow.uturn.backward", action: model.undo)
                        .disabled(!model.canUndo)
                        .help("Undo the last change (Command Z)")
                    Button("Redo", systemImage: "arrow.uturn.forward", action: model.redo)
                        .disabled(!model.canRedo)
                        .help("Redo (Shift Command Z)")
                }
                .buttonStyle(ChipButtonStyle())
                .fixedSize()
            }
            if rows.count > limit {
                Button(showAllHistory ? "Show fewer" : "Show all \(rows.count)") { showAllHistory.toggle() }
                    .buttonStyle(.link).themeFont(.caption)
            }
            VStack(alignment: .leading, spacing: 2) {
                ForEach(shown, id: \.index) { r in row(index: r.index, text: r.text, isNow: r.isNow, undone: r.undone) }
            }
            if !hasChanges && undone.isEmpty {
                Label("No changes yet. Describe one above or pick a quick change.", systemImage: "lightbulb")
                    .themeFont(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tutorialTarget(.history)
    }

    private func row(index: Int, text: String, isNow: Bool, undone: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
        return HStack(alignment: .center, spacing: 8) {
            // Numbered dots. The one on screen now gets an accent ring.
            Text("\(index + 1)").themeFont(.caption).fontWeight(.semibold).monospacedDigit()
                .foregroundStyle(isNow ? Theme.ink : Theme.muted)
                .frame(minWidth: 20, minHeight: 20)
                .background(isNow ? Theme.panel : Theme.raised, in: Circle())
                .overlay(Circle().strokeBorder(isNow ? Theme.accent : Theme.line, lineWidth: isNow ? 1.5 : 1))
            Text(text.prefix(1).uppercased() + text.dropFirst())
                .themeFont(.secondary)
                .fontWeight(isNow ? .medium : .regular)
                .strikethrough(undone)
                .foregroundStyle(undone ? Theme.muted : Theme.ink)
                .lineLimit(2)
            Spacer(minLength: 0)
            if isNow { Text("Now").themeFont(.caption).fontWeight(.semibold).foregroundStyle(Theme.accentInk) }
            if undone { Text("Undone").themeFont(.caption).foregroundStyle(Theme.muted) }
        }
        .padding(.vertical, 5).padding(.horizontal, 6)
        .background(isNow ? Theme.accentSoft : .clear, in: shape)
        .help(text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Version \(index + 1), \(text)\(isNow ? ", current" : undone ? ", undone" : "")")
    }

    // MARK: Model

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack {
                InspectorHeader(title: "Model", symbol: "cube")
                Spacer()
                Button("New scan…") { model.confirmNewScan = true }
                    .buttonStyle(ChipButtonStyle())
                    .disabled(model.isEditing)
            }
            ModelInfoRows(controller: model.viewer)
                .padding(Theme.Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).strokeBorder(Theme.line))
        }
    }

    // MARK: Save

    private var saveSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            // The status line sits next to Save, so "Saved" never scrolls out of sight.
            if let note = model.note { NoteView(note: note).transition(.opacity) }
            // Side by side when there is room. At big text sizes Save drops to its own row.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.xs) { openInRow; Spacer(minLength: 0); saveButton }
                VStack(alignment: .leading, spacing: Theme.Space.xs) { openInRow; saveButton }
            }
            .disabled(!model.canSave)
        }
        .animation(Theme.motion(reduceMotion), value: model.note)
        .sheet(item: $help) { which in
            switch which {
            case .tinkercad: TinkercadSheet(stlURL: model.stlURL)
            case .freecad: FreeCADSheet(stlURL: model.stlURL)
            }
        }
    }

    private var openInRow: some View {
        HStack(spacing: 6) {
            Text("Open in").themeFont(.caption).foregroundStyle(Theme.muted)
            Button { help = .tinkercad } label: { Label("Tinkercad", systemImage: "globe") }
                .help("Copy the file and open Tinkercad in the browser")
            Button { openFreeCAD() } label: { Label("FreeCAD", systemImage: "arrow.up.forward.app") }
                .help(freeCADInstalled() ? "Open the model in FreeCAD" : "Steps to get FreeCAD")
        }
        .buttonStyle(ChipButtonStyle())
        .fixedSize()
        .tutorialTarget(.openIn)
    }

    private var saveButton: some View {
        Button(action: save) { Label("Save STL…", systemImage: "square.and.arrow.down") }
            .buttonStyle(BigButtonStyle(hasChanges ? .primary : .secondary))
            .fixedSize()
            .tutorialTarget(.saveSTL)
    }


    /// Opens straight in FreeCAD when it is installed. Otherwise shows the steps to get it.
    private func openFreeCAD() {
        guard let stl = model.stlURL, freeCADInstalled() else { help = .freecad; return }
        if !openInFreeCAD(stl) { help = .freecad }
    }
}

private enum HelpSheetKind: String, Identifiable {
    case tinkercad, freecad
    var id: String { rawValue }
}

/// A section title with a small accent icon, so each part of the panel is easy to find.
private struct InspectorHeader: View {
    let title: String
    let symbol: String
    var trailing: String? = nil
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(Theme.accentInk).accessibilityHidden(true)
            Text(title).foregroundStyle(Theme.ink)
            if let trailing { Text(trailing).chip() }
        }
        .themeFont(.heading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
