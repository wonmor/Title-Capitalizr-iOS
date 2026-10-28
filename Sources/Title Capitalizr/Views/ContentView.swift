//
//  ContentView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import SwiftUI

let desiredOutputDict = [DesiredOutput.mla: "MLA and Chicago",
                         DesiredOutput.apa: "APA and AP"]

struct ContentView: View {
    @State private var titleName: String = ""
    @State private var finalOutput: String = ""

    @State private var showingSheet = false
    @State private var showingSettings = false
    @State private var selectedOutput: DesiredOutput = .mla

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

    // Detect whether OS is on dark mode or light mode
    @Environment(\.colorScheme) var colorScheme

    private var smartAvailable: Bool { aiFeaturesEnabled && smart.availability.isAvailable }
    private var hasTitle: Bool { !titleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ScrollView {
                VStack(alignment: .center) {
                    titleBar()
                    textEntry()
                    resultSection()
                    smartSection()
                    issuesSection()
                }
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)
            }
            .onTapGesture {
                hideKeyboard()
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif

            #if os(iOS)
            settingsButton()
            #endif
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .onChange(of: selectedOutput) { _ in
            recompute()
        }
        .onAppear(perform: applyDemoEnvironment)
    }

    /// Lets screenshots and UI smoke runs pre-fill the title (TC_DEMO_TITLE) or open
    /// Settings (TC_DEMO_SHOW_SETTINGS=1). No effect in normal use.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if titleName.isEmpty, let demo = env["TC_DEMO_TITLE"], !demo.isEmpty {
            titleName = demo
        }
        if env["TC_DEMO_SHOW_SETTINGS"] == "1" {
            showingSettings = true
        }
        if env["TC_DEMO_SMART"] == "1" {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                runSmartCapitalize()
                runSuggestAlternatives()
            }
        }
    }

    private func settingsButton() -> some View {
        Button {
            hideKeyboard()
            showingSettings = true
        } label: {
            Image(systemName: "gearshape")
                .font(.title3)
                .padding(12)
        }
        .accessibilityLabel("Settings")
        .padding(.trailing, 6)
    }

    private func titleBar() -> some View {
        // iOS draws the style button as plain text, so the stack can be tight. The macOS
        // button has a bezel, which overlapped the heading at -20, so it gets normal spacing.
        #if os(macOS)
        let spacing: CGFloat = 0
        #else
        let spacing: CGFloat = -20
        #endif
        return VStack(spacing: spacing) {
            Image("AppIconPreview")
                .resizable()
                .frame(width: 60, height: 60)
                .cornerRadius(10)
                .padding()

            Text("Title Capitalizr")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding()

            Button(action: {
                hideKeyboard()
                showingSheet.toggle()
            }) {
                VStack {
                    Text("Press here to choose style")
                        .font(.title2)
                        .padding()
                }
            }
            #if os(macOS)
            .buttonStyle(.borderless)
            #endif
            .sheet(isPresented: $showingSheet) {
                PickerView(selectedOutput: $selectedOutput)
            }
        }
    }

    private func textEntry() -> some View {
        VStack(alignment: .center) {
            Text("Are you going to be the next Tolkien?")
                .font(.callout)
                .bold()
            TextField("Enter your title name...", text: $titleName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                #endif
                .onChange(of: self.titleName) { _ in
                    recompute()
                }
            Text("Selected: **\(desiredOutputDict[selectedOutput]!)**")
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var displayedOutput: String {
        smartOutput ?? finalOutput
    }

    private func resultSection() -> some View {
        VStack {
            Text(!hasTitle ? "Your capitalized title will appear here..." : displayedOutput)
                .textSelection(.enabled)
                .padding(.leading)
                .padding(.trailing)
                .padding(.top)
                .multilineTextAlignment(.center)

            if smartOutput != nil {
                Label("Apple Intelligence | \(desiredOutputDict[selectedOutput]!)", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(action: { Platform.copyToClipboard(displayedOutput) }) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                    Text("Copy to **clipboard**")
                        .font(.body)
                }
                .padding(8)
                .foregroundColor(colorScheme == .dark ? .white : .black)
                .contentShape(Rectangle())
                .overlay(
                    RoundedRectangle(cornerRadius: 10.0)
                        .stroke(lineWidth: 2.0)
                        .foregroundColor(colorScheme == .dark ? .white : .black)
                )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func smartSection() -> some View {
        if aiFeaturesEnabled {
            VStack(spacing: 12) {
                if smartAvailable {
                    HStack(spacing: 12) {
                        Button {
                            runSmartCapitalize()
                        } label: {
                            Label(isSmartRunning ? "Thinking…" : "Smart Capitalize", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasTitle || isSmartRunning)

                        if alternativesEnabled {
                            Button {
                                runSuggestAlternatives()
                            } label: {
                                Label(isSuggesting ? "Writing…" : "Suggest titles", systemImage: "text.badge.star")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!hasTitle || isSuggesting)
                        }
                    }
                    if smartFailed {
                        Text("Apple Intelligence couldn't improve this title, showing the standard result.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if !alternatives.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Alternative titles", systemImage: "text.badge.star")
                                .font(.headline)
                            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                                HStack {
                                    Text(alt)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Button {
                                        Platform.copyToClipboard(alt)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel("Copy")
                                    Button("Use") {
                                        titleName = alt
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                    }
                } else {
                    Label("Apple Intelligence not available", systemImage: "sparkles.slash")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .help(smart.availability.message)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }

    @ViewBuilder
    private func issuesSection() -> some View {
        if hasTitle, grammarChecksEnabled || spellingChecksEnabled {
            VStack(spacing: 10) {
                if issues.isEmpty {
                    Label(isReviewing ? "Checking…" : "No spelling or grammar issues found", systemImage: isReviewing ? "hourglass" : "checkmark.circle")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                } else {
                    IssuesView(issues: issues, onFix: apply(issue:), onFixAll: applyAllIssues)
                }
                if smartAvailable, grammarChecksEnabled {
                    Button {
                        runAIReview()
                    } label: {
                        Label(isReviewing ? "Reviewing…" : "Review with Apple Intelligence", systemImage: "sparkles")
                            .font(.footnote)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isReviewing)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
        }
    }

    // MARK: - Logic

    /// Rule-based path: instant and deterministic. Runs on every keystroke.
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
            // Drop duplicates that cover the same characters (e.g. spelling + apostrophe on "dont").
            var seen = Set<String>()
            issues = found.sorted { $0.range.location < $1.range.location }.filter { issue in
                let key = "\(issue.range.location)-\(issue.range.length)"
                let isSpellingDup = issue.kind == .spelling && found.contains { $0.kind != .spelling && NSIntersectionRange($0.range, issue.range).length > 0 }
                return !isSpellingDup && seen.insert(key).inserted
            }
        }
    }

    private func apply(issue: GrammarIssue) {
        titleName = issue.applying(to: titleName)
    }

    private func applyAllIssues() {
        titleName = issues.applyingAll(to: titleName)
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
            if let suggestion, !issues.contains(where: { $0.kind == .aiSuggestion }) {
                issues.append(suggestion)
            }
            isReviewing = false
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
