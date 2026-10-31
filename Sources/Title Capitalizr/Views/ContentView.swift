//
//  ContentView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//  Bauhaus redesign and essay formatter, version 1.7.
//

import SwiftUI

enum AppMode: String { case title, essay }

struct ContentView: View {
    @StateObject private var workspace = EssayWorkspace()
    @ObservedObject private var store = ProStore.shared
    @SceneStorage("mode") private var modeRaw = AppMode.title.rawValue
    @State private var showingSettings = false

    private var mode: Binding<AppMode> {
        Binding(get: { AppMode(rawValue: modeRaw) ?? .title }, set: { modeRaw = $0.rawValue })
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                masthead
                Segmented(options: [(AppMode.title, "Title"), (AppMode.essay, "Essay")], selection: mode, identifierPrefix: "mode")
                switch mode.wrappedValue {
                case .title: TitleCaseView()
                case .essay: EssayView(workspace: workspace, store: store)
                }
                footer
            }
            .padding(.horizontal, Bauhaus.Space.l)
            .padding(.top, Bauhaus.Space.m)
            .padding(.bottom, Bauhaus.Space.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            // Screenshot runs: TC_DEMO_SCROLL=checks|preview|export scrolls to that section.
            if let anchor = ProcessInfo.processInfo.environment["TC_DEMO_SCROLL"] {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    proxy.scrollTo(anchor, anchor: .top)
                }
            }
        }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .bauhausScreen()
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store).bauhausSheet()
        }
        .onOpenURL { url in
            mode.wrappedValue = .essay
            if url.isFileURL { workspace.load(url: url) } else { workspace.load(googleDocsLink: url.absoluteString) }
        }
        .onAppear(perform: applyDemoEnvironment)
    }

    /// TC_DEMO_MODE=essay opens the formatter; TC_DEMO_SAMPLE=1 loads the sample essay;
    /// TC_DEMO_STYLE=apa7 picks a style; TC_DEMO_SHOW_SETTINGS / TC_DEMO_PAYWALL open sheets.
    /// Used for screenshots and UI smoke runs only.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let m = env["TC_DEMO_MODE"], let parsed = AppMode(rawValue: m) { mode.wrappedValue = parsed }
        if env["TC_DEMO_SAMPLE"] == "1", !workspace.hasDocument { workspace.loadSample() }
        if let s = env["TC_DEMO_STYLE"], let style = EssayStyle(rawValue: s) { workspace.style = style }
        if env["TC_DEMO_SHOW_SETTINGS"] == "1" { showingSettings = true }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Bauhaus.Space.m) {
                Image("AppIconPreview")
                    .resizable()
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -6) {
                    Text("TITLE").font(Bauhaus.Typo.display).tracking(1)
                    Text("CAPITALIZR").font(Bauhaus.Typo.display).tracking(1).foregroundStyle(Bauhaus.Palette.blue)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Title Capitalizr")
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                #if os(iOS)
                Button {
                    hideKeyboard()
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: Bauhaus.tapTarget, height: Bauhaus.tapTarget)
                        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
                #endif
            }
            .padding(.bottom, Bauhaus.Space.m - 4)
            // Primary colour fields as a rule: red, yellow, blue.
            HStack(spacing: 0) {
                Bauhaus.Palette.red.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.yellow.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.blue.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.ink.frame(height: Bauhaus.Rule.heavy).frame(maxWidth: .infinity)
            }
            .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        Text("Designed by John Seong")
            .font(Bauhaus.Typo.caption)
            .foregroundStyle(Bauhaus.Palette.inkSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, Bauhaus.Space.m)
    }
}

// MARK: - Title capitalizer

struct TitleCaseView: View {
    @State private var titleName: String = ""
    @State private var finalOutput: String = ""
    @AppStorage("titleStyle") private var selectedOutputRaw = DesiredOutput.mla.rawValue
    @State private var copied = false

    // On-device AI (Apple Intelligence)
    @StateObject private var smart = SmartCapitalizer()
    @State private var smartOutput: String?
    @State private var isSmartRunning = false
    @State private var alternatives: [String] = []
    @State private var isSuggesting = false
    @State private var smartFailed = false

    // Spelling & grammar
    @State private var issues: [GrammarIssue] = []
    @State private var checkTask: Task<Void, Never>?
    @State private var isReviewing = false
    private let grammarChecker = GrammarChecker()
    private let spellChecker = SpellChecker()

    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiFeaturesEnabled = true
    @AppStorage(SettingsKeys.alternativesEnabled) private var alternativesEnabled = true
    @AppStorage(SettingsKeys.grammarChecksEnabled) private var grammarChecksEnabled = true
    @AppStorage(SettingsKeys.spellingChecksEnabled) private var spellingChecksEnabled = true

    private var selectedOutput: DesiredOutput { DesiredOutput(rawValue: selectedOutputRaw) ?? .mla }
    private var styleBinding: Binding<DesiredOutput> {
        Binding(get: { selectedOutput }, set: { selectedOutputRaw = $0.rawValue; recompute() })
    }
    private var smartAvailable: Bool { aiFeaturesEnabled && smart.availability.isAvailable }
    private var hasTitle: Bool { !titleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var displayedOutput: String { smartOutput ?? finalOutput }

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Style")
                Segmented(options: [(DesiredOutput.mla, "MLA | Chicago"), (DesiredOutput.apa, "APA | AP")], selection: styleBinding, identifierPrefix: "style")
            }
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Your title")
                BoxedTextField(placeholder: "Are you going to be the next Tolkien?", text: $titleName, font: Bauhaus.Typo.font(18, relativeTo: .body))
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .onChange(of: titleName) { _ in recompute() }
            }
            resultSection
            smartSection
            issuesSection
        }
        .onAppear(perform: applyDemoEnvironment)
    }

    /// TC_DEMO_TITLE pre-fills the title, TC_DEMO_SMART=1 runs the AI features. Screenshots only.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if titleName.isEmpty, let demo = env["TC_DEMO_TITLE"], !demo.isEmpty { titleName = demo }
        if env["TC_DEMO_SMART"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                runSmartCapitalize()
                runSuggestAlternatives()
            }
        }
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(smartOutput != nil ? "APPLE INTELLIGENCE | \(selectedOutput.displayName.uppercased())" : selectedOutput.displayName.uppercased())
                    .font(Bauhaus.Typo.section).tracking(1.4)
                Spacer()
            }
            .foregroundStyle(Bauhaus.Palette.ground)
            .padding(.horizontal, Bauhaus.Space.m - 4).padding(.vertical, Bauhaus.Space.s)
            .background(Bauhaus.Palette.ink)
            Text(hasTitle ? displayedOutput : "Your capitalized title appears here")
                .font(Bauhaus.Typo.result)
                .foregroundStyle(hasTitle ? Bauhaus.Palette.ink : Bauhaus.Palette.inkSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                .padding(Bauhaus.Space.m)
            HRule()
            HStack(spacing: 0) {
                Button {
                    Platform.copyToClipboard(displayedOutput)
                    copied = true
                    Task { try? await Task.sleep(nanoseconds: 1_500_000_000); copied = false }
                } label: {
                    Label(copied ? "COPIED" : "COPY", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(Bauhaus.Typo.button).tracking(1)
                        .foregroundStyle(Bauhaus.Palette.ground)
                        .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
                        .background(hasTitle ? Bauhaus.Palette.blue : Bauhaus.Palette.inkDisabled)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!hasTitle)
            }
        }
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }

    @ViewBuilder
    private var smartSection: some View {
        if aiFeaturesEnabled {
            VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
                if smartAvailable {
                    SectionTitle("Apple Intelligence")
                    HStack(spacing: Bauhaus.Space.s) {
                        BarButton(title: isSmartRunning ? "Thinking" : "Smart Capitalize", systemImage: "sparkles", kind: .primary) { runSmartCapitalize() }
                            .disabled(!hasTitle || isSmartRunning)
                        if alternativesEnabled {
                            BarButton(title: isSuggesting ? "Writing" : "Suggest titles", systemImage: "text.badge.star", kind: .secondary) { runSuggestAlternatives() }
                                .disabled(!hasTitle || isSuggesting)
                        }
                    }
                    if smartFailed {
                        Text("Apple Intelligence couldn't improve this title, so the standard result is shown.")
                            .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    }
                    if !alternatives.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(alternatives.enumerated()), id: \.offset) { i, alt in
                                HStack(spacing: Bauhaus.Space.s) {
                                    Text("\(i + 1)").font(Bauhaus.Typo.bodyBold).frame(width: 28, height: 28)
                                        .background(Bauhaus.Palette.yellow)
                                        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                                    Text(alt).font(Bauhaus.Typo.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 4)
                                    Button { Platform.copyToClipboard(alt) } label: { Image(systemName: "doc.on.doc") }
                                        .buttonStyle(.plain).accessibilityLabel("Copy")
                                    TagButton(title: "Use") { titleName = alt }
                                }
                                .padding(Bauhaus.Space.m - 4)
                                if i < alternatives.count - 1 { HRule(thickness: Bauhaus.Rule.thin) }
                            }
                        }
                        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                    }
                } else {
                    Label("Apple Intelligence not available", systemImage: "sparkles")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                        .help(smart.availability.message)
                }
            }
        }
    }

    @ViewBuilder
    private var issuesSection: some View {
        if hasTitle, grammarChecksEnabled || spellingChecksEnabled {
            VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
                if issues.isEmpty {
                    Label(isReviewing ? "Checking" : "No spelling or grammar issues found", systemImage: isReviewing ? "hourglass" : "checkmark.seal")
                        .font(Bauhaus.Typo.body).foregroundStyle(Bauhaus.Palette.inkSecondary)
                } else {
                    IssuesView(issues: issues, onFix: { titleName = $0.applying(to: titleName) }, onFixAll: { titleName = issues.applyingAll(to: titleName) })
                }
                if smartAvailable, grammarChecksEnabled {
                    TagButton(title: isReviewing ? "Reviewing" : "Review with Apple Intelligence", systemImage: "sparkles") { runAIReview() }
                        .disabled(isReviewing)
                }
            }
        }
    }

    // MARK: Logic

    private func recompute() {
        finalOutput = Capitalizer(inputLine: titleName).capitalizeTitle(selectedOutput: selectedOutput)
        smartOutput = nil
        smartFailed = false
        alternatives = []
        scheduleChecks()
    }

    private func scheduleChecks() {
        checkTask?.cancel()
        let text = titleName
        guard hasTitle else { issues = []; return }
        checkTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, text == titleName else { return }
            var found: [GrammarIssue] = []
            if spellingChecksEnabled { found += spellChecker.check(text) }
            if grammarChecksEnabled { found += grammarChecker.check(text) }
            var seen = Set<String>()
            issues = found.sorted { $0.range.location < $1.range.location }.filter { issue in
                let key = "\(issue.range.location)-\(issue.range.length)"
                let isSpellingDup = issue.kind == .spelling && found.contains { $0.kind != .spelling && NSIntersectionRange($0.range, issue.range).length > 0 }
                return !isSpellingDup && seen.insert(key).inserted
            }
        }
    }

    private func runSmartCapitalize() {
        hideKeyboard()
        isSmartRunning = true
        smartFailed = false
        let text = titleName
        let style = selectedOutput
        Task { @MainActor in
            let result = await smart.capitalize(text, style: style)
            guard text == titleName else { isSmartRunning = false; return }
            smartOutput = result.usedFallback ? nil : result.title
            smartFailed = result.usedFallback
            isSmartRunning = false
        }
    }

    private func runSuggestAlternatives() {
        hideKeyboard()
        isSuggesting = true
        let text = titleName
        let style = selectedOutput
        Task { @MainActor in
            let result = await smart.suggestAlternatives(for: text, style: style)
            guard text == titleName else { isSuggesting = false; return }
            alternatives = result
            isSuggesting = false
        }
    }

    private func runAIReview() {
        hideKeyboard()
        isReviewing = true
        let text = titleName
        Task { @MainActor in
            let suggestion = await smart.reviewGrammar(text)
            guard text == titleName else { isReviewing = false; return }
            if let suggestion, !issues.contains(where: { $0.kind == .aiSuggestion }) { issues.append(suggestion) }
            isReviewing = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}
