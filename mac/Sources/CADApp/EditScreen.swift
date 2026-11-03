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
            Group {
                if model.hasParts {
                    PartsViewerStep(parts: model.partViews, controller: model.viewer)
                } else {
                    ViewerStep(stlURL: model.stlURL, revision: model.revision, highlightChange: model.lastChangeWasEdit,
                               controller: model.viewer)
                }
            }
            .tutorialTarget(.viewer)
            // Size top left, hands top right, tools left, Caddiy bottom right, view controls bottom centre,
            // so they never overlap.
            VStack {
                HStack(alignment: .top) {
                    ViewerSizeBadge(controller: model.viewer)
                    Spacer()
                    if model.offerSplit { SplitOffer(model: model) }
                    Spacer()
                    // The row keeps only the button's height. The camera mirror hangs below it over the
                    // empty right side, so it never pushes the tool strip down.
                    StageHandPanel(hands: model.hands).frame(height: 38, alignment: .top)
                }
                HStack { ToolStrip(model: model); Spacer() }
                Spacer()
                if model.pendingCut != nil {
                    CutBar(model: model)
                } else {
                    if model.hasParts && (model.tool == .cut || model.tool == .turn) {
                        Text(model.tool == .cut ? "Draw a line across a part" : "Drag a part sideways to turn it")
                            .themeFont(.secondary).foregroundStyle(Theme.ink)
                            .padding(.horizontal, Theme.Space.s).padding(.vertical, 6).card(padding: 0)
                    }
                    ViewerButtons(controller: model.viewer)
                }
            }
            .padding(Theme.Space.s)
            StageCaddiy(model: model)
            HandPaletteView(stage: model.handStage, hands: model.hands, shown: model.canChangeParts && model.pendingCut == nil)
            StageHandCursor(hands: model.hands)
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
        .onDisappear { model.hands.enabled = false }
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
                    // Top right holds the camera mirror while hands are on.
                    let handsOn = model.hands.enabled
                    let free = model.viewer.modelRect().flatMap { m in spots.first { !$0.1.intersects(m) && !(handsOn && $0.0 == .topTrailing) }?.0 }
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
        .onChange(of: model.cue) { _, cue in
            if let cue { say(cue.moment) }
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
                if model.parts.count >= 2 || !model.putAway.isEmpty {
                    PartsSection(model: model)
                    Divider()
                }
                changeSection
                quickSection
                Divider()
                BuildsSection(builds: model.builds, canSave: canChange, save: { Task { await model.saveBuild() } },
                              open: { item in Task { await model.openBuild(item) } })
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
            if model.hasParts {
                Group {
                    if let p = model.selectedPart {
                        Label("Changing: \(p.name)", systemImage: "scope").foregroundStyle(Theme.accentInk)
                    } else {
                        Label("Pick a part first", systemImage: "hand.point.up.left").foregroundStyle(Theme.muted)
                    }
                }
                .themeFont(.caption).fontWeight(.semibold)
            }
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
            StageToggles(viewer: model.viewer)
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

/// What the stage shows: size tags, a ruler, and parts that snap into line.
private struct StageToggles: View {
    @ObservedObject var viewer: ViewerControl
    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Toggle("Sizes", isOn: $viewer.showSizes).help("Show how big each part is")
            Toggle("Ruler", isOn: $viewer.showRuler).help("Show a ruler on the floor")
            Toggle("Snap", isOn: $viewer.snapEnabled).help("Parts click into line when you move them")
        }
        .toggleStyle(.checkbox)
        .themeFont(.secondary)
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

// MARK: Parts

/// Down the left of the stage: three tools, then Add and Copy.
private struct ToolStrip: View {
    @ObservedObject var model: AppModel
    @State private var showTurn = false
    @State private var showLift = false
    @State private var showSize = false

    var body: some View {
        VStack(spacing: 4) {
            tool(.look, "Look", "eye", "Drag to turn the view")
            tool(.move, "Move", "hand.draw", "Drag a part to slide it")
            tool(.cut, "Cut", "scissors", "Draw a line across a part to cut it")
            tool(.turn, "Turn", "arrow.clockwise", "Drag a part sideways to turn it, or pick an exact turn") { showTurn = true }
                .popover(isPresented: $showTurn, arrowEdge: .trailing) { TurnPanel(model: model) }
            stripButton("Lift", "arrow.up.and.down", "Raise or lower the picked part") { showLift = true }
                .popover(isPresented: $showLift, arrowEdge: .trailing) { LiftPanel(model: model) }
            stripButton("Size", "arrow.up.left.and.arrow.down.right", "Make the picked part bigger or smaller") { showSize = true }
                .popover(isPresented: $showSize, arrowEdge: .trailing) { SizePanel(model: model) }
            Divider().frame(width: 44).padding(.vertical, 2)
            stripButton("Add", "plus.circle", "Add a ready-made shape") { model.showAddShelf = true }
                .popover(isPresented: $model.showAddShelf, arrowEdge: .trailing) { AddShelf(model: model) }
            stripButton("Copy", "plus.square.on.square", "Copy the picked part") { Task { await model.copySelected() } }
                .disabled(model.hasParts && model.selectedPart == nil)
        }
        .padding(6)
        .card(padding: 0)
        .disabled(!model.canChangeParts)
    }

    private func tool(_ t: PartTool, _ title: String, _ symbol: String, _ help: String,
                      then: (() -> Void)? = nil) -> some View {
        let on = model.tool == t
        return Button { Task { await model.chooseTool(t); then?() } } label: { stripLabel(title, symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(on ? Theme.accentInk : Theme.ink)
            .background(on ? Theme.accentSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
                .strokeBorder(on ? Theme.accent : .clear, lineWidth: 1.5))
            .help(help)
            .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func stripButton(_ title: String, _ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { stripLabel(title, symbol) }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.ink)
            .help(help)
    }

    private func stripLabel(_ title: String, _ symbol: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 18, weight: .medium))
            Text(title).themeFont(.caption)
        }
        .frame(width: 52, height: 48)
        .contentShape(Rectangle())
    }
}

/// Turn the picked part: quick quarter turns, or any angle you type.
private struct TurnPanel: View {
    @ObservedObject var model: AppModel
    @State private var degrees = 45.0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Turn the part").themeFont(.heading).foregroundStyle(Theme.ink)
            Button { Task { await model.layFlatSelected() } } label: { Label("Lay flat", systemImage: "square.bottomhalf.filled") }
                .buttonStyle(BigButtonStyle(.primary, compact: true))
                .help("Lay the part on its biggest flat side")
            HStack(spacing: 8) {
                Button { Task { await model.turnSelected(-90) } } label: { Label("Left 90", systemImage: "arrow.counterclockwise") }
                Button { Task { await model.turnSelected(90) } } label: { Label("Right 90", systemImage: "arrow.clockwise") }
                Button { Task { await model.turnSelected(180) } } label: { Label("Flip 180", systemImage: "arrow.left.arrow.right") }
            }
            .buttonStyle(BigButtonStyle(.secondary, compact: true))
            Text("Tip front/back").themeFont(.secondary).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Button { Task { await model.tipSelected(-90) } } label: { Label("Back 90", systemImage: "arrow.up.backward") }
                Button { Task { await model.tipSelected(90) } } label: { Label("Forward 90", systemImage: "arrow.down.forward") }
                Button { Task { await model.tipSelected(180) } } label: { Label("Flip over", systemImage: "arrow.up.arrow.down") }
            }
            .buttonStyle(BigButtonStyle(.secondary, compact: true))
            Text("Tip left/right").themeFont(.secondary).foregroundStyle(Theme.muted)
            HStack(spacing: 8) {
                Button { Task { await model.tipSelected(-90, sideways: true) } } label: { Label("Left 90", systemImage: "arrow.down.backward") }
                Button { Task { await model.tipSelected(90, sideways: true) } } label: { Label("Right 90", systemImage: "arrow.down.forward") }
            }
            .buttonStyle(BigButtonStyle(.secondary, compact: true))
            HStack(spacing: 8) {
                Text("Your own angle").themeFont(.secondary).foregroundStyle(Theme.muted)
                TextField("degrees", value: $degrees, format: .number).frame(width: 56).textFieldStyle(.roundedBorder)
                Text("degrees").themeFont(.secondary).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Button { Task { await model.turnSelected(-degrees) } } label: { Label("Turn left", systemImage: "arrow.counterclockwise") }
                Button { Task { await model.turnSelected(degrees) } } label: { Label("Turn right", systemImage: "arrow.clockwise") }
                Button { Task { await model.tipSelected(degrees) } } label: { Label("Tip forward", systemImage: "arrow.down.forward") }
                Button { Task { await model.tipSelected(degrees, sideways: true) } } label: { Label("Tip right", systemImage: "arrow.down.right") }
            }
            .buttonStyle(BigButtonStyle(.primary, compact: true))
            Text("Flip").themeFont(.secondary).foregroundStyle(Theme.muted)
            MirrorButtons(model: model)
            if model.hasParts && model.selectedPart == nil {
                Text("Click a part first.").themeFont(.secondary).foregroundStyle(Theme.muted)
            }
        }
        .padding(Theme.Space.m)
        .disabled(!model.canChangeParts)
    }
}

/// Flip the picked part like in a mirror, as seen on screen.
private struct MirrorButtons: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: 8) {
            Button { Task { await model.mirrorSelected(sideways: true) } } label: {
                Label("Mirror left/right", systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
            }
            .help("Flip the part so its left side is on the right")
            Button { Task { await model.mirrorSelected(sideways: false) } } label: {
                Label("Mirror front/back", systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down")
            }
            .help("Flip the part so its front is at the back")
        }
        .buttonStyle(BigButtonStyle(.secondary, compact: true))
    }
}

/// Make the picked part bigger or smaller. Sizes are in mm.
private struct SizePanel: View {
    @ObservedObject var model: AppModel
    /// Width, depth and height the kid typed.
    @State private var size = SIMD3<Double>(repeating: 0)
    @State private var keepShape = true
    static let bed = 250.0

    private var old: SIMD3<Double>? { model.selectedSize }
    private var factors: SIMD3<Double>? {
        guard let old, old.min() > 0 else { return nil }
        return size / old
    }
    private var changed: Bool {
        guard let f = factors else { return false }
        return (0..<3).contains { abs(f[$0] - 1) > 0.001 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Change the size").themeFont(.heading).foregroundStyle(Theme.ink)
            if old == nil {
                Text("Click a part first.").themeFont(.secondary).foregroundStyle(Theme.muted)
            } else {
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                    row("Width", 0, "left to right")
                    row("Depth", 1, "front to back")
                    row("Height", 2, "bottom to top")
                }
                Toggle("Keep shape", isOn: $keepShape)
                    .help("Change one size and the other two follow, so the part does not get squashed")
                HStack(spacing: 8) {
                    Button { size *= 0.5 } label: { Label("Half", systemImage: "minus.magnifyingglass") }
                    Button { size *= 2 } label: { Label("Double", systemImage: "plus.magnifyingglass") }
                }
                .buttonStyle(BigButtonStyle(.secondary, compact: true))
                if size.max() > Self.bed {
                    Text("That is bigger than the printer bed (250 mm). Try a smaller size.")
                        .themeFont(.secondary).foregroundStyle(Theme.muted)
                } else if size.min() < 1 {
                    Text("That is too tiny to print. Keep every side at 1 mm or more.")
                        .themeFont(.secondary).foregroundStyle(Theme.muted)
                }
                Button {
                    guard let f = factors else { return }
                    Task { await model.resizeSelected(sx: f.x, sy: f.y, sz: f.z) }
                } label: { Label("Apply", systemImage: "checkmark") }
                .buttonStyle(BigButtonStyle(.primary, compact: true))
                .disabled(!changed)
            }
        }
        .padding(Theme.Space.m)
        .disabled(!model.canChangeParts)
        .onAppear { size = old ?? size }
        .onChange(of: old) { _, new in if let new { size = new } }
    }

    private func row(_ title: String, _ i: Int, _ hint: String) -> some View {
        GridRow {
            Text(title).themeFont(.secondary).foregroundStyle(Theme.muted)
            TextField(title, value: binding(i), format: .number.precision(.fractionLength(0...1)))
                .frame(width: 72).textFieldStyle(.roundedBorder)
                .help("The \(title.lowercased()) of the part, \(hint)")
            Text("mm").themeFont(.secondary).foregroundStyle(Theme.muted)
        }
    }

    /// With Keep shape on, a new value scales all three sides by the same amount.
    private func binding(_ i: Int) -> Binding<Double> {
        Binding(get: { size[i] }, set: { v in
            if keepShape, size[i] > 0 { size *= v / size[i] } else { size[i] = v }
        })
    }
}

/// Raise or lower the picked part by any amount, or put it back on the floor.
private struct LiftPanel: View {
    @ObservedObject var model: AppModel
    @State private var mm = 5.0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Lift the part").themeFont(.heading).foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Text("Amount").themeFont(.secondary).foregroundStyle(Theme.muted)
                TextField("mm", value: $mm, format: .number).frame(width: 56).textFieldStyle(.roundedBorder)
                Text("mm").themeFont(.secondary).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 8) {
                Button { Task { await model.liftSelected(mm) } } label: { Label("Up", systemImage: "arrow.up") }
                Button { Task { await model.liftSelected(-mm) } } label: { Label("Down", systemImage: "arrow.down") }
                Button { Task { await model.dropSelected() } } label: { Label("To floor", systemImage: "arrow.down.to.line") }
            }
            .buttonStyle(BigButtonStyle(.primary, compact: true))
            Text("Tip: hold Shift while you drag a part to lift it.").themeFont(.secondary).foregroundStyle(Theme.muted)
        }
        .padding(Theme.Space.m)
        .disabled(!model.canChangeParts)
    }
}

/// The ready-made shapes. Names match the helper's library.
struct AddShelf: View {
    @ObservedObject var model: AppModel
    static let shapes: [(name: String, symbol: String)] = [
        ("cube", "cube"), ("ball", "circle.fill"), ("cylinder", "cylinder"), ("cone", "cone"),
        ("pyramid", "pyramid"), ("donut", "circle.circle"), ("star", "star"), ("heart", "heart"),
        ("base plate", "square.stack.3d.down.right"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Add a part").themeFont(.heading).foregroundStyle(Theme.ink)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 8), count: 3), spacing: 8) {
                ForEach(Self.shapes, id: \.name) { s in
                    Button { Task { await model.add(s.name) } } label: {
                        Label(s.name.prefix(1).uppercased() + s.name.dropFirst(), systemImage: s.symbol)
                    }
                    .buttonStyle(TileButtonStyle(tint: Theme.tintAdd))
                }
            }
        }
        .padding(Theme.Space.m)
        .disabled(!model.canChangeParts)
    }
}

/// After a cut line is drawn. Nothing is cut until Cut here.
private struct CutBar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Button { Task { await model.confirmCut() } } label: { Label("Cut here", systemImage: "scissors") }
                .buttonStyle(BigButtonStyle(.primary, compact: true))
                .keyboardShortcut(.return, modifiers: [])
            Button("Try again") { model.cancelCut() }
                .buttonStyle(BigButtonStyle(.secondary, compact: true))
                .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(Theme.Space.xs)
        .card(padding: 0)
        .disabled(!model.canChangeParts)
    }
}

/// Right after a scan: a gentle offer to split the scan into its separate things.
private struct SplitOffer: View {
    @ObservedObject var model: AppModel
    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            Image(systemName: "square.split.2x1").foregroundStyle(Theme.gold).accessibilityHidden(true)
            Text("More than one thing in your scan?").themeFont(.secondary).foregroundStyle(Theme.ink)
            Button("Break it into pieces") { Task { await model.split() } }
                .buttonStyle(BigButtonStyle(.secondary, compact: true))
                .disabled(!model.canChangeParts)
            Button { model.splitDismissed = true } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .help("Hide this")
                .accessibilityLabel("Hide")
        }
        .padding(.horizontal, Theme.Space.s).padding(.vertical, 6)
        .card(padding: 0)
    }
}

/// "My parts": pick a part, copy it, put it away, or stick picked parts together.
private struct PartsSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            InspectorHeader(title: "My parts", symbol: "square.stack.3d.up", trailing: "\(model.parts.count)")
            ForEach(Array(model.parts.enumerated()), id: \.element.id) { i, p in row(p, index: i) }
            if model.selection.count >= 2 {
                Button { Task { await model.joinSelected() } } label: {
                    Label("Stick together", systemImage: "link").frame(maxWidth: .infinity)
                }
                .buttonStyle(BigButtonStyle(.primary, compact: true))
            } else if model.parts.count >= 2 {
                Text("Shift click two parts to stick them together.")
                    .themeFont(.caption).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !model.putAway.isEmpty {
                Text("Put away (\(model.putAway.count))").themeFont(.secondary).fontWeight(.semibold).foregroundStyle(Theme.muted)
                ForEach(model.putAway) { p in
                    HStack {
                        Text(p.name).themeFont(.secondary).foregroundStyle(Theme.muted).lineLimit(1)
                        Spacer(minLength: 0)
                        Button("Bring back") { Task { await model.bringBack(p.id) } }.buttonStyle(ChipButtonStyle())
                    }
                }
            }
        }
        .disabled(!model.canChangeParts)
    }

    private func row(_ p: ModelPart, index: Int) -> some View {
        let picked = model.selection.contains(p.id)
        let shape = RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
        return HStack(spacing: 6) {
            Button {
                model.select(p.id, adding: NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command))
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(picked ? Theme.accentInk : Theme.muted)
                    Text(p.name).themeFont(.secondary).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(p.name), part \(index + 1) of \(model.parts.count)\(picked ? ", picked" : "")")
            .accessibilityHint("Picks this part. Shift click to pick more than one.")
            if picked && model.selection.count == 1 {
                Button("Copy") { Task { await model.copySelected() } }.buttonStyle(ChipButtonStyle())
                Button("Put away") { Task { await model.putAway(p.id) } }.buttonStyle(ChipButtonStyle())
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(picked ? Theme.accentSoft : .clear, in: shape)
        .fixedSize(horizontal: false, vertical: true)
    }
}
