//
//  SettingsView.swift
//  Title Capitalizr
//
//  Feature switches, Pro status and the privacy note.
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: ProStore
    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiFeaturesEnabled = true
    @AppStorage(SettingsKeys.alternativesEnabled) private var alternativesEnabled = true
    @AppStorage(SettingsKeys.grammarChecksEnabled) private var grammarChecksEnabled = true
    @AppStorage(SettingsKeys.spellingChecksEnabled) private var spellingChecksEnabled = true

    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
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
                        Text(store.isPro ? "Pro is active: essay formatting and every export." : "Pro unlocks the essay formatter's full preview and exports.")
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

                section("Apple Intelligence") {
                    Checkbox(label: "Smart Capitalize", systemImage: "sparkles", isOn: $aiFeaturesEnabled)
                    Checkbox(label: "Suggest alternative titles", systemImage: "text.badge.star", isOn: $alternativesEnabled)
                        .disabled(!aiFeaturesEnabled)
                    note(availability.isAvailable
                         ? "Uses the on-device Apple Intelligence model to apply your style guide, keep proper nouns and acronyms intact, propose titles and fill gaps in an essay's heading."
                         : "Apple Intelligence not available: \(availability.message) The rule-based capitalizer and formatter keep working as usual.")
                }

                section("Checks") {
                    Checkbox(label: "Spelling", systemImage: "textformat.abc.dottedunderline", isOn: $spellingChecksEnabled)
                    Checkbox(label: "Grammar suggestions", systemImage: "text.book.closed", isOn: $grammarChecksEnabled)
                    note("Spelling uses the system dictionary. Grammar looks for a/an mistakes, doubled words, missing apostrophes, first-word capitalization and subject-verb agreement. Nothing changes until you tap Fix.")
                }

                section("Privacy") {
                    HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                        Image(systemName: "lock.shield").font(.system(size: 18, weight: .semibold))
                        Text("Titles and essays are processed on your device and never uploaded. The only network request is downloading a Google Doc when you paste its link.")
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
