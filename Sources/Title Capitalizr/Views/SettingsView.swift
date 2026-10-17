//
//  SettingsView.swift
//  Title Capitalizr
//
//  Toggles for the on-device AI features and the grammar/spelling checks,
//  plus a short privacy note.
//

import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiFeaturesEnabled = true
    @AppStorage(SettingsKeys.alternativesEnabled) private var alternativesEnabled = true
    @AppStorage(SettingsKeys.grammarChecksEnabled) private var grammarChecksEnabled = true
    @AppStorage(SettingsKeys.spellingChecksEnabled) private var spellingChecksEnabled = true

    @Environment(\.dismiss) private var dismiss
    private let availability = SmartCapitalizer.systemAvailability()

    var body: some View {
        #if os(macOS)
        form
            .formStyle(.grouped)
            .padding(.bottom)
        #else
        NavigationStack {
            form
                .navigationTitle("Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #endif
    }

    private var form: some View {
        Form {
            Section {
                Toggle(isOn: $aiFeaturesEnabled) {
                    Label("Smart Capitalize", systemImage: "sparkles")
                }
                Toggle(isOn: $alternativesEnabled) {
                    Label("Suggest alternative titles", systemImage: "text.badge.star")
                }
                .disabled(!aiFeaturesEnabled)
            } header: {
                Text("Apple Intelligence")
            } footer: {
                Text(availability.isAvailable
                     ? "Smart Capitalize uses the on-device Apple Intelligence model to apply your style guide, keep proper nouns and acronyms intact and propose alternative titles."
                     : "Apple Intelligence not available: \(availability.message) The instant rule-based capitalizer keeps working as usual.")
            }

            Section {
                Toggle(isOn: $spellingChecksEnabled) {
                    Label("Spelling", systemImage: "textformat.abc.dottedunderline")
                }
                Toggle(isOn: $grammarChecksEnabled) {
                    Label("Grammar suggestions", systemImage: "text.book.closed")
                }
            } header: {
                Text("Checks")
            } footer: {
                Text("Spelling uses the system dictionary. Grammar looks for a/an mistakes, doubled words, missing apostrophes, first-word capitalization and subject-verb agreement. Nothing changes until you tap Fix.")
            }

            Section {
                Label {
                    Text("Everything is processed on your device. Your titles are never sent to a server, and the app makes no network requests.")
                } icon: {
                    Image(systemName: "lock.shield")
                }
                .font(.footnote)
            } header: {
                Text("Privacy")
            }
        }
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
