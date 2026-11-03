import SwiftUI
import AppKit
import CADShared

// MARK: Step indicator

/// Progress in the toolbar: three numbered dots joined by short lines, "1 Scan, 2 Process, 3 Edit".
/// Status only, not buttons, so a stray click never loses a model.
/// Done steps show a tick on gold, the current step has a gold ring. Shape and weight carry the state, not colour alone.
struct StepIndicator: View {
    let current: AppModel.Step
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppModel.Step.allCases, id: \.self) { step in
                if step.rawValue > 0 {
                    Capsule()
                        .fill(step.rawValue <= current.rawValue ? Theme.gold : Theme.line)
                        .frame(width: 14, height: 2)
                }
                HStack(spacing: 5) {
                    dot(step)
                    Text(step.title)
                        .font(Theme.rounded(12, step == current ? .semibold : .medium))
                        .foregroundStyle(step == current ? Theme.gold : step.rawValue < current.rawValue ? Theme.ink : Theme.muted)
                        .fixedSize()
                }
            }
        }
        .animation(Theme.spring(reduceMotion), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current.rawValue + 1) of 3, \(current.title)")
    }

    @ViewBuilder private func dot(_ step: AppModel.Step) -> some View {
        let done = step.rawValue < current.rawValue
        let now = step == current
        ZStack {
            // Done: solid gold with a dark tick. Now: gold ring with a gold number. Later: a quiet grey ring.
            Circle().fill(done ? Theme.gold : Theme.raised)
            Circle().strokeBorder(now ? Theme.gold : done ? .clear : Theme.line, lineWidth: now ? 2 : 1)
            if done {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(Theme.onGold)
            } else {
                Text("\(step.rawValue + 1)").font(Theme.rounded(10, .bold))
                    .foregroundStyle(now ? Theme.gold : Theme.muted)
            }
        }
        .frame(width: 18, height: 18)
    }
}

// MARK: Banner

struct BannerView: View {
    let kind: BannerKind
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: kind.symbol).foregroundStyle(tint).fontWeight(.semibold)
            Text(kind.text).themeFont(.secondary).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            if kind == .lostContact { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, Theme.screenMargin).padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(tint.opacity(0.10))
        .overlay(alignment: .bottom) { Rectangle().fill(tint.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
    private var tint: Color { kind.isError ? Theme.bad : Theme.warn }
}

// MARK: Messages

/// A short status message on a soft rounded wash with a coloured icon. The icon shape and the words carry
/// the meaning, the colour only backs them up. Raw error text folds away under Details.
struct NoteView: View {
    let note: Note
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder private func bouncing(_ icon: some View) -> some View {
        if #available(macOS 15, *) {
            icon.symbolEffect(.bounce, options: .nonRepeating, isActive: !reduceMotion && note.kind == .good)
        } else { icon }
    }
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous)
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(note.text).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            } icon: {
                bouncing(Image(systemName: symbol).foregroundStyle(tint))
            }
            .themeFont(.secondary)
            if let d = note.detail, !d.isEmpty { TeacherDetails(text: d) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(note.kind == .info ? 0.08 : 0.10), in: shape)
        .overlay(shape.strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
    private var tint: Color { switch note.kind { case .good: Theme.good; case .bad: Theme.bad; case .info: Theme.accentInk } }
    private var symbol: String {
        switch note.kind { case .good: "checkmark.circle.fill"; case .bad: "exclamationmark.triangle.fill"; case .info: "info.circle.fill" }
    }
}

/// Raw error text, folded away, selectable, with a Copy button.
struct TeacherDetails: View {
    let text: String
    @State private var open = false
    @State private var copied = false
    var body: some View {
        DisclosureGroup(isExpanded: $open) {
            VStack(alignment: .trailing, spacing: 6) {
                ScrollView {
                    Text(text).themeFont(.mono).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(maxHeight: 160)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Theme.buttonCorner, style: .continuous).strokeBorder(Theme.line))
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        } label: {
            Text("Details").themeFont(.caption).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: Timers

/// "14 s" that ticks once a second, in tabular digits. The digits roll unless Reduce Motion is on.
struct ElapsedText: View {
    let since: Date
    var prefix = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            let secs = max(0, Int(ctx.date.timeIntervalSince(since)))
            Text("\(prefix)\(secs) s").monospacedDigit()
                .contentTransition(reduceMotion ? .identity : .numericText(countsDown: false))
                .animation(Theme.motion(reduceMotion), value: secs)
        }
    }
}

/// A section title. An optional symbol sits in a small soft tinted square, and an optional count
/// sits in a capsule on the right.
struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var symbol: String? = nil
    var tint: Theme.Tint = Theme.tintAccent
    @Environment(\.textScale) private var scale
    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(tint.ink)
                    .frame(width: 22 * scale, height: 22 * scale)
                    .background(tint.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(title).themeFont(.heading).foregroundStyle(Theme.ink)
            if let trailing { Text(trailing).monospacedDigit().chip(tint: tint) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
