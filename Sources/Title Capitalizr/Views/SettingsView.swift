//
//  SettingsView.swift
//  Title Capitalizr
//
//  Feature switches, Pro status and the privacy note.
//

import SwiftUI
import TitleCaseKit

struct SettingsView: View {
    @ObservedObject var store: ProStore
    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiFeaturesEnabled = true
    @AppStorage(SettingsKeys.alternativesEnabled) private var alternativesEnabled = true
    @AppStorage(SettingsKeys.grammarChecksEnabled) private var grammarChecksEnabled = true
    @AppStorage(SettingsKeys.spellingChecksEnabled) private var spellingChecksEnabled = true
    @AppStorage(SettingsKeys.whyPanelEnabled) private var whyEnabled = true

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @ObservedObject private var library = LibraryStore.shared
    @State private var linkCode: OrchestrLink.Code?
    @State private var linkTask: Task<Void, Never>?
    @State private var linkMessage: String?
    @Environment(\.openURL) private var openURL
    private let availability = SmartCapitalizer.systemAvailability()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                #if os(iOS)
                HStack {
                    Text("SETTINGS").font(Bauhaus.Typo.title).tracking(1)
                    Spacer()
                    TagButton(title: "Done", filled: true) { dismiss() }
                }
                #endif

                section("Pro") {
                    HStack(spacing: Bauhaus.Space.m - 4) {
                        GlyphTile(systemImage: store.isPro ? "checkmark" : "lock", fill: store.isPro ? Bauhaus.Palette.blue : Bauhaus.Palette.red)
                        Text(proText)
                            .font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: Bauhaus.Space.s) {
                        if !store.isPro { TagButton(title: "See plans", systemImage: "lock.open", filled: true) { showingPaywall = true } }
                        TagButton(title: "Restore purchases", systemImage: "arrow.clockwise") { Task { await store.restore() } }
                        Spacer(minLength: 0)
                    }
                    if let m = store.message { Text(m).font(Bauhaus.Typo.caption) }
                }

                section("Orchestr account") { accountSection }

                section("Custom dictionary") {
                    DictionaryEditor(library: library, store: store)
                }

                section(Platform.isMac ? "Shortcuts and Services" : "Shortcuts and sharing") {
                    note(Platform.isMac
                         ? "Pro adds Title Capitalizr actions to Shortcuts and a Services menu item (select text in any app, then Services, Title Case with Title Capitalizr). Both use the style guide you picked last: \(library.snapshot.lastGuide.displayName)."
                         : "Pro adds Title Capitalizr actions to Shortcuts and Siri. In any app, share selected text to Title Capitalizr to convert it; add the Recent Titles widget to your Home Screen. Actions use the style guide you picked last: \(library.snapshot.lastGuide.displayName).")
                }

                section("Apple Intelligence") {
                    Checkbox(label: "Smart Capitalize", systemImage: "sparkles", isOn: $aiFeaturesEnabled)
                    Checkbox(label: "Suggest alternative titles", systemImage: "text.badge.star", isOn: $alternativesEnabled)
                        .disabled(!aiFeaturesEnabled)
                    note(availability.isAvailable
                         ? "Pro: headline polish, grammar fix, Smart Capitalize and title ideas with the on-device Apple Intelligence model, plus filling gaps in an essay's heading."
                         : "Apple Intelligence not available: \(availability.message) The rule-based capitalizer and formatter keep working as usual.")
                }

                section("Checks") {
                    Checkbox(label: "Spelling", systemImage: "textformat.abc.dottedunderline", isOn: $spellingChecksEnabled)
                    Checkbox(label: "Grammar suggestions", systemImage: "text.book.closed", isOn: $grammarChecksEnabled)
                    Checkbox(label: "Show why each word is cased", systemImage: "questionmark.circle", isOn: $whyEnabled)
                    note("Spelling uses the system dictionary. Grammar looks for a/an mistakes, doubled words, missing apostrophes, first-word capitalization and subject-verb agreement. Nothing changes until you tap Fix.")
                }

                section("Privacy") {
                    HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                        Image(systemName: "lock.shield").font(.system(size: 18, weight: .semibold))
                        Text("Titles and essays are processed on your device and never uploaded. Network requests: downloading a Google Doc when you paste its link, and, only if you link an Orchestr account, checking that link.")
                            .font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                    }
                }

                Text("Developed and designed by John Seong")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
            }
            .padding(Bauhaus.Space.l)
        }
        .bauhausScreen()
        .sheet(isPresented: $showingPaywall) { PaywallView(store: store).bauhausSheet() }
        .onDisappear { linkTask?.cancel() }
    }

    private var proText: String {
        guard store.isPro else { return "Pro unlocks every style guide, batch mode, the developer text tools, the custom dictionary, Shortcuts actions, Apple Intelligence polish and the essay formatter." }
        switch store.grantedBy {
        case "allaccess": return "Pro is active through Orchestr All Access."
        default: return "Pro is active: every style guide and tool is unlocked."
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let claims = store.link.claims {
            note("Linked\(claims.em.map { " as \($0)" } ?? ""). Orchestr All Access bought in any Orchestr app unlocks Pro here.")
            HStack(spacing: Bauhaus.Space.s) {
                TagButton(title: "Unlink", systemImage: "minus.circle") { Task { await store.link.unlink(); await store.refresh() } }
                TagButton(title: "Delete account", systemImage: "person.crop.circle.badge.xmark") { openURL(OrchestrLink.deleteAccountURL) }
                Spacer(minLength: 0)
            }
        } else if let code = linkCode {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                Text(code.userCode).font(Bauhaus.Typo.font(30, weight: .bold, relativeTo: .title)).tracking(3).textSelection(.enabled)
                note("Approve this code on the page that opened. This screen updates by itself.")
                HStack(spacing: Bauhaus.Space.s) {
                    TagButton(title: "Open page again", systemImage: "safari") { openURL(code.url) }
                    TagButton(title: "Cancel", systemImage: "xmark") { linkTask?.cancel(); linkCode = nil }
                    Spacer(minLength: 0)
                }
            }
        } else {
            note("Optional. Link a free Orchestr account to use Orchestr All Access from your other Orchestr apps here. Not needed to buy or use Pro.")
            TagButton(title: "Link Orchestr account", systemImage: "link") { startLink() }
        }
        if let linkMessage { Text(linkMessage).font(Bauhaus.Typo.caption) }
    }

    private func startLink() {
        linkMessage = nil
        linkTask?.cancel()
        linkTask = Task { @MainActor in
            do {
                let code = try await store.link.start()
                linkCode = code
                openURL(code.url)
                try await store.link.waitForApproval(code)
                linkCode = nil
                await store.restore()
                linkMessage = store.isPro ? "Linked. Pro is active." : "Linked."
            } catch is CancellationError {
                linkCode = nil
            } catch {
                linkCode = nil
                linkMessage = "Linking didn't finish: \(error.localizedDescription)"
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle(title)
            content()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }
}
