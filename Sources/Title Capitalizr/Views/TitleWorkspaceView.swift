//
//  TitleWorkspaceView.swift
//  Title Capitalizr
//
//  The title editor: style guide picker, the text, a live preview with Copy / Favourite / Share /
//  drag out, the "why" panel (which rule set each word's case), spelling and grammar checks and
//  the Apple Intelligence tools. Wide layouts put the editor beside the preview.
//

import SwiftUI
import TitleCaseKit
import UniformTypeIdentifiers

struct TitleWorkspaceView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore
    @ObservedObject var library: LibraryStore
    var wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            GuidePicker(model: model, store: store)
            if wide {
                HStack(alignment: .top, spacing: Bauhaus.Space.l) {
                    VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                        EditorBox(model: model, minHeight: 150)
                        ChecksPanel(model: model)
                        AIPanel(model: model, store: store)
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                        PreviewPanel(model: model, library: library)
                        WhyPanel(model: model, store: store, library: library)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                EditorBox(model: model, minHeight: 64)
                PreviewPanel(model: model, library: library)
                WhyPanel(model: model, store: store, library: library)
                ChecksPanel(model: model)
                AIPanel(model: model, store: store)
            }
        }
    }
}

// MARK: - Guide picker

struct GuidePicker: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Style guide") {
                if !store.isPro {
                    Text("3 FREE | 7 PRO").font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.redInk)
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 0)], spacing: 0) {
                ForEach(StyleGuide.allCases) { g in chip(g) }
            }
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            Text(model.guide.summary)
                .font(Bauhaus.Typo.caption)
                .foregroundStyle(Bauhaus.Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ g: StyleGuide) -> some View {
        let selected = g == model.guide
        let locked = !store.isUnlocked(g)
        return Button { model.choose(g) } label: {
            HStack(spacing: 4) {
                Text(g.shortName.uppercased()).font(Bauhaus.Typo.button).tracking(0.6).lineLimit(1).minimumScaleFactor(0.7)
                if locked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
            }
            .foregroundStyle(selected ? Bauhaus.Palette.ground : (locked ? Bauhaus.Palette.inkSecondary : Bauhaus.Palette.ink))
            .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
            .background(selected ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.thin))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerHover()
        .accessibilityLabel(g.displayName + (locked ? ", Pro" : ""))
        .accessibilityIdentifier("guide-\(g.rawValue)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(g.summary)
    }
}

// MARK: - Editor

struct EditorBox: View {
    @ObservedObject var model: EditorModel
    var minHeight: CGFloat
    @State private var targeted = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Your title") {
                if model.hasInput {
                    Button { model.input = "" } label: { Label("Clear", systemImage: "xmark").labelStyle(.iconOnly) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear")
                }
            }
            TextField("Are you going to be the next Tolkien?", text: $model.input, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Bauhaus.Typo.font(19, relativeTo: .body))
                .lineLimit(2...8)
                .focused($focused)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(Bauhaus.Space.m - 4)
                .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                .background(targeted ? Bauhaus.Palette.groundSoft : Bauhaus.Palette.ground)
                .overlay(Rectangle().stroke(targeted ? Bauhaus.Palette.blue : Bauhaus.Palette.ink, lineWidth: targeted ? Bauhaus.Rule.thick : Bauhaus.Rule.regular))
                .contentShape(Rectangle())
                .onTapGesture { focused = true }
                .dropDestination(for: String.self) { items, _ in
                    guard let text = items.first else { return false }
                    model.receive(text)
                    return true
                } isTargeted: { targeted = $0 }
                .accessibilityIdentifier("title-input")
            Text("Type, paste or drop text. Many lines go to Batch.")
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
        }
    }
}

// MARK: - Preview

struct PreviewPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var library: LibraryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(model.guide.displayName.uppercased()).font(Bauhaus.Typo.section).tracking(1.4)
                Spacer()
                if model.hasInput {
                    Image(systemName: "hand.draw").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                    Text("DRAG TO SHARE").font(Bauhaus.Typo.section).tracking(1).accessibilityHidden(true)
                }
            }
            .foregroundStyle(Bauhaus.Palette.ground)
            .padding(.horizontal, Bauhaus.Space.m - 4).padding(.vertical, Bauhaus.Space.s)
            .background(Bauhaus.Palette.ink)

            Text(model.hasInput ? model.output : "Your capitalized title appears here")
                .font(Bauhaus.Typo.result)
                .foregroundStyle(model.hasInput ? Bauhaus.Palette.ink : Bauhaus.Palette.inkSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                .padding(Bauhaus.Space.m)
                .draggable(model.output)
                .accessibilityIdentifier("title-output")
            HRule()
            HStack(spacing: 0) {
                actionButton(model.flash == "Copied" ? "COPIED" : "COPY", model.flash == "Copied" ? "checkmark" : "doc.on.doc", fill: Bauhaus.Palette.blue) { model.copyResult() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                    .help("Copy (Shift Command C)")
                VRule()
                actionButton(model.isFavorite ? "SAVED" : "FAVOURITE", model.isFavorite ? "star.fill" : "star", fill: Bauhaus.Palette.ground, ink: true) { model.toggleFavorite() }
                    .keyboardShortcut("d", modifiers: .command)
                    .help("Favourite (Command D)")
                VRule()
                ShareLink(item: model.output) {
                    Label("SHARE", systemImage: "square.and.arrow.up")
                        .font(Bauhaus.Typo.button).tracking(1)
                        .foregroundStyle(model.hasInput ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled)
                        .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!model.hasInput)
                .pointerHover()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }

    private func actionButton(_ title: String, _ glyph: String, fill: Color, ink: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: glyph)
                .font(Bauhaus.Typo.button).tracking(1)
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundStyle(ink ? (model.hasInput ? Bauhaus.Palette.ink : Bauhaus.Palette.inkDisabled) : Bauhaus.Palette.ground)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget, maxHeight: .infinity)
                .background(ink ? fill : (model.hasInput ? fill : Bauhaus.Palette.inkDisabled))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!model.hasInput)
        .pointerHover()
    }
}

// MARK: - Why

struct WhyPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore
    @ObservedObject var library: LibraryStore
    @AppStorage(SettingsKeys.whyPanelEnabled) private var expanded = true

    var body: some View {
        if model.hasInput {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                Button { withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() } } label: {
                    SectionTitle("Why each word") {
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint(expanded ? "Hides the explanations" : "Shows which rule set each word's case")
                if expanded {
                    VStack(spacing: 0) {
                        let words = model.result.words
                        ForEach(Array(words.enumerated()), id: \.offset) { i, w in
                            row(w)
                            if i < words.count - 1 { HRule(thickness: Bauhaus.Rule.thin) }
                        }
                    }
                    .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                    ForEach(model.result.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(store.isPro ? "Long-press or right-click a word to keep its spelling in your dictionary." : "Custom dictionary for brand names and acronyms is part of Pro.")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                }
            }
        }
    }

    private func row(_ w: WordDecision) -> some View {
        HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
            Text(w.output)
                .font(Bauhaus.Typo.bodyBold)
                .frame(minWidth: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(w.rule.label.uppercased())
                    .font(Bauhaus.Typo.section).tracking(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .foregroundStyle(chipInk(w.rule))
                    .background(chipFill(w.rule))
                    .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.thin))
                Text(w.explanation)
                    .font(Bauhaus.Typo.caption)
                    .foregroundStyle(Bauhaus.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Bauhaus.Space.m - 6)
        .accessibilityElement(children: .combine)
        .contextMenu {
            if store.isPro {
                Button { library.addWord(w.original.trimmingCharacters(in: .punctuationCharacters)) } label: {
                    Label("Keep “\(w.original.trimmingCharacters(in: .punctuationCharacters))” as written", systemImage: "character.book.closed")
                }
                Button { library.addWord(w.output.trimmingCharacters(in: .punctuationCharacters)) } label: {
                    Label("Keep “\(w.output.trimmingCharacters(in: .punctuationCharacters))” in the dictionary", systemImage: "character.book.closed.fill")
                }
            } else {
                Button { model.showingPaywall = true } label: { Label("Custom dictionary (Pro)", systemImage: "lock") }
            }
        }
    }

    private func chipFill(_ r: CaseRule) -> Color {
        switch r {
        case .minorWord, .sentenceLower, .toInfinitive: return Bauhaus.Palette.yellow
        case .keptCasing, .dictionary, .properNounKept, .number, .url: return Bauhaus.Palette.groundSoft
        default: return Bauhaus.Palette.blue
        }
    }

    private func chipInk(_ r: CaseRule) -> Color {
        chipFill(r) == Bauhaus.Palette.blue ? Bauhaus.Palette.ground : Bauhaus.Palette.ink
    }
}

// MARK: - Spelling and grammar

struct ChecksPanel: View {
    @ObservedObject var model: EditorModel
    @State private var issues: [GrammarIssue] = []
    @State private var task: Task<Void, Never>?
    @AppStorage(SettingsKeys.grammarChecksEnabled) private var grammarOn = true
    @AppStorage(SettingsKeys.spellingChecksEnabled) private var spellingOn = true
    private let grammar = GrammarChecker()
    private let spelling = SpellChecker()

    var body: some View {
        Group {
            if model.hasInput, grammarOn || spellingOn {
                VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                    if issues.isEmpty {
                        Label("No spelling or grammar issues found", systemImage: "checkmark.seal")
                            .font(Bauhaus.Typo.body).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    } else {
                        IssuesView(issues: issues, onFix: { model.input = $0.applying(to: model.input) },
                                   onFixAll: { model.input = issues.applyingAll(to: model.input) })
                    }
                }
            }
        }
        .onAppear { schedule(model.input) }
        .onChange(of: model.input) { _, v in schedule(v) }
    }

    private func schedule(_ text: String) {
        task?.cancel()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { issues = []; return }
        task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, text == model.input else { return }
            var found: [GrammarIssue] = []
            if spellingOn { found += spelling.check(text) }
            // The style guide already capitalizes the first word; don't nag about it.
            if grammarOn { found += grammar.check(text).filter { $0.kind != .firstWordCapital } }
            var seen = Set<String>()
            issues = found.sorted { $0.range.location < $1.range.location }.filter { issue in
                let key = "\(issue.range.location)-\(issue.range.length)"
                let dup = issue.kind == .spelling && found.contains { $0.kind != .spelling && NSIntersectionRange($0.range, issue.range).length > 0 }
                return !dup && seen.insert(key).inserted
            }
        }
    }
}

// MARK: - Apple Intelligence (Pro)

struct AIPanel: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore
    @StateObject private var smart = SmartCapitalizer()
    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiOn = true
    @AppStorage(SettingsKeys.alternativesEnabled) private var alternativesOn = true

    enum Job: String { case smart = "Smart Capitalize", polish = "Polish headline", grammar = "Fix grammar", ideas = "Suggest titles" }
    @State private var running: Job?
    @State private var suggestion: (job: Job, text: String, note: String)?
    @State private var alternatives: [String] = []
    @State private var problem: String?

    var body: some View {
        if aiOn {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Apple Intelligence") {
                    if !store.isPro { Text("PRO").font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.redInk) }
                }
                if !store.isPro {
                    HStack(spacing: Bauhaus.Space.m - 4) {
                        GlyphTile(systemImage: "sparkles", fill: Bauhaus.Palette.red, size: 32)
                        Text("Headline polish, grammar fix, Smart Capitalize and title ideas run on your device with Pro.")
                            .font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                    }
                    TagButton(title: "See Pro plans", systemImage: "lock.open", filled: true) { model.showingPaywall = true }
                } else if !smart.availability.isAvailable {
                    Label("Apple Intelligence unavailable: \(smart.availability.message)", systemImage: "sparkles")
                        .font(Bauhaus.Typo.body).foregroundStyle(Bauhaus.Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("ai-unavailable")
                    Text("The rule-based style guides keep working as usual.")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Bauhaus.Space.s)], spacing: Bauhaus.Space.s) {
                        button(.polish, "wand.and.stars", .primary)
                        button(.grammar, "text.badge.checkmark", .secondary)
                        button(.smart, "sparkles", .secondary)
                        if alternativesOn { button(.ideas, "text.badge.star", .secondary) }
                    }
                    if let problem {
                        Text(problem).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.redInk).fixedSize(horizontal: false, vertical: true)
                    }
                    if let s = suggestion { suggestionCard(s) }
                    if !alternatives.isEmpty { alternativesList }
                }
            }
            .onChange(of: model.input) { _, _ in suggestion = nil; alternatives = []; problem = nil }
            .onChange(of: model.guide) { _, _ in suggestion = nil; alternatives = []; problem = nil }
        }
    }

    private func button(_ job: Job, _ glyph: String, _ kind: BarButton.Kind) -> some View {
        BarButton(title: running == job ? "Working" : job.rawValue, systemImage: glyph, kind: kind) { run(job) }
            .disabled(!model.hasInput || running != nil)
    }

    private func suggestionCard(_ s: (job: Job, text: String, note: String)) -> some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            Text(s.job.rawValue.uppercased()).font(Bauhaus.Typo.section).tracking(1.2)
            Text(s.text).font(Bauhaus.Typo.title).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !s.note.isEmpty { Text(s.note).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: Bauhaus.Space.s) {
                TagButton(title: "Use", systemImage: "arrow.up.left", filled: true) { model.input = s.text; suggestion = nil }
                TagButton(title: "Copy", systemImage: "doc.on.doc") { Platform.copyToClipboard(s.text); model.show("Copied") }
                Spacer()
            }
            Text("Suggested by Apple Intelligence on this device. Check it before you use it.")
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
        }
        .padding(Bauhaus.Space.m - 4)
        .background(Bauhaus.Palette.groundSoft)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }

    private var alternativesList: some View {
        VStack(spacing: 0) {
            ForEach(Array(alternatives.enumerated()), id: \.offset) { i, alt in
                HStack(spacing: Bauhaus.Space.s) {
                    Text("\(i + 1)").font(Bauhaus.Typo.bodyBold).frame(width: 28, height: 28)
                        .background(Bauhaus.Palette.yellow)
                        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                    Text(alt).font(Bauhaus.Typo.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    TagButton(title: "Use") { model.input = alt }
                }
                .padding(Bauhaus.Space.m - 4)
                if i < alternatives.count - 1 { HRule(thickness: Bauhaus.Rule.thin) }
            }
        }
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }

    private func run(_ job: Job) {
        let text = model.input
        let guide = model.guide
        let dict = model.library.dictionary
        running = job
        problem = nil
        suggestion = nil
        Task { @MainActor in
            defer { running = nil }
            switch job {
            case .smart:
                let r = await smart.capitalize(text, style: guide)
                guard text == model.input else { return }
                if r.usedFallback { problem = "Apple Intelligence couldn't improve this title, so the rule-based result stands." }
                else if r.title == model.output { problem = "Apple Intelligence agrees with the rule-based result." }
                else { suggestion = (job, r.title, "Applied by the on-device model; compare it with the rule-based preview.") }
            case .ideas:
                let r = await smart.suggestAlternatives(for: text, style: guide)
                guard text == model.input else { return }
                alternatives = r.map { TitleCaseEngine.apply($0, guide: guide, dictionary: dict) }
                if r.isEmpty { problem = "Apple Intelligence didn't return any titles. Try again." }
            case .polish, .grammar:
                let outcome = job == .polish
                    ? await smart.polishHeadline(text, style: guide, dictionary: dict)
                    : await smart.fixGrammar(text, style: guide, dictionary: dict)
                guard text == model.input else { return }
                switch outcome {
                case .suggestion(let t, let note): suggestion = (job, t, note)
                case .unchanged: problem = job == .polish ? "Apple Intelligence had nothing to tighten." : "No spelling or grammar fixes needed."
                case .unavailable(let why): problem = "Apple Intelligence unavailable: \(why)"
                case .failed(let why): problem = why
                }
            }
        }
    }
}

extension View {
    /// iPad pointer highlight; no-op elsewhere.
    @ViewBuilder
    func pointerHover() -> some View {
        #if os(iOS)
        self.hoverEffect(.highlight)
        #else
        self
        #endif
    }
}
