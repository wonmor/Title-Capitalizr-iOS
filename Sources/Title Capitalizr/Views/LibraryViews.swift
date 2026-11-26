//
//  LibraryViews.swift
//  Title Capitalizr
//
//  History with favourites (iPhone sheet) and the custom dictionary editor.
//

import SwiftUI
import TitleCaseKit

struct HistoryView: View {
    @ObservedObject var library: LibraryStore
    var onSelect: (HistoryEntry) -> Void
    var showsDone = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var confirmClear = false

    private func filtered(_ items: [HistoryEntry]) -> [HistoryEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { $0.output.lowercased().contains(q) || $0.input.lowercased().contains(q) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                HStack {
                    Text("HISTORY").font(Bauhaus.Typo.title).tracking(1)
                    Spacer()
                    if showsDone { TagButton(title: "Done", filled: true) { dismiss() }.keyboardShortcut(.cancelAction) }
                }
                BoxedTextField(placeholder: "Search", text: $query)
                section("Favourites", filtered(library.favorites), empty: "Tap Favourite on a result to keep it here.")
                section("Recent", filtered(library.recents), empty: "Titles you copy appear here.")
                if !library.recents.isEmpty {
                    TagButton(title: "Clear recent", systemImage: "trash") { confirmClear = true }
                }
            }
            .padding(Bauhaus.Space.l)
        }
        .confirmationDialog("Clear recent titles? Favourites stay.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear recent", role: .destructive) { library.clearRecents() }
        }
    }

    private func section(_ title: String, _ items: [HistoryEntry], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle(title) { Text("\(items.count)").font(Bauhaus.Typo.section) }
            if items.isEmpty {
                Text(empty).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, e in
                        row(e)
                        if i < items.count - 1 { HRule(thickness: Bauhaus.Rule.thin) }
                    }
                }
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            }
        }
    }

    private func row(_ e: HistoryEntry) -> some View {
        HStack(alignment: .top, spacing: Bauhaus.Space.s) {
            Button { onSelect(e) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.output).font(Bauhaus.Typo.bodyBold).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("\(e.guide.displayName) | \(e.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button { library.toggleFavorite(e) } label: {
                Image(systemName: e.favorite ? "star.fill" : "star").frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(e.favorite ? "Remove from favourites" : "Add to favourites")
            Button { Platform.copyToClipboard(e.output) } label: {
                Image(systemName: "doc.on.doc").frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy")
        }
        .padding(Bauhaus.Space.m - 6)
        .draggable(e.output)
        .contextMenu {
            Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
        }
    }
}

struct DictionaryEditor: View {
    @ObservedObject var library: LibraryStore
    @ObservedObject var store: ProStore
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            if store.isPro {
                HStack(spacing: Bauhaus.Space.s) {
                    BoxedTextField(placeholder: "iPhone, NASA, McKinsey", text: $newWord)
                        .onSubmit(add)
                        .accessibilityIdentifier("dictionary-input")
                    TagButton(title: "Add", systemImage: "plus", filled: true, action: add)
                        .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if library.dictionary.words.isEmpty {
                    Text("No words yet. Every style guide keeps these spellings exactly as you type them.")
                        .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                } else {
                    FlowWords(words: library.dictionary.words) { library.removeWord($0) }
                }
            } else {
                HStack(spacing: Bauhaus.Space.m - 4) {
                    GlyphTile(systemImage: "character.book.closed", fill: Bauhaus.Palette.red, size: 32)
                    Text("Keep brand names and acronyms (iPhone, NASA, eBay) exactly as written in every guide with Pro.")
                        .font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                }
                TagButton(title: "See Pro plans", systemImage: "lock.open", filled: true) { store.paywallRequested = true }
            }
            Text("Built in: common acronyms and brands such as NASA, FBI, iPhone, macOS, YouTube and COVID-19.")
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
        }
    }

    private func add() {
        newWord.split(separator: ",").forEach { library.addWord(String($0)) }
        newWord = ""
    }
}

/// Removable word tags laid out in rows.
struct FlowWords: View {
    let words: [String]
    var onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: Bauhaus.Space.s)], alignment: .leading, spacing: Bauhaus.Space.s) {
            ForEach(words, id: \.self) { w in
                HStack(spacing: 4) {
                    Text(w).font(Bauhaus.Typo.bodyBold).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 0)
                    Button { onRemove(w) } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .bold)) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(w)")
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 34)
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
            }
        }
    }
}
