//
//  AppModel.swift
//  Title Capitalizr
//
//  LibraryStore: history, favourites and the custom dictionary (shared with the extensions).
//  EditorModel: one per window: the text being converted, the chosen guide, batch and tools state.
//

import Foundation
import SwiftUI
import TitleCaseKit
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var snapshot: SharedSnapshot

    init() { snapshot = SharedVault.load() }

    var history: [HistoryEntry] { snapshot.history }
    var favorites: [HistoryEntry] { snapshot.favorites }
    var recents: [HistoryEntry] { snapshot.recents }
    var dictionary: CustomDictionary { snapshot.dictionary }

    /// Re-reads the vault (the share extension may have added entries).
    func reload() {
        let fresh = SharedVault.load()
        if fresh != snapshot { snapshot = fresh }
    }

    func record(input: String, output: String, guide: StyleGuide) {
        mutate { $0.record(input: input, output: output, guide: guide) }
    }

    func toggleFavorite(_ entry: HistoryEntry) {
        mutate { s in
            if let i = s.history.firstIndex(where: { $0.id == entry.id }) { s.history[i].favorite.toggle() }
        }
    }

    /// Marks the given conversion as a favourite, recording it first if needed. Returns the new state.
    @discardableResult
    func toggleFavorite(input: String, output: String, guide: StyleGuide) -> Bool {
        var result = false
        mutate { s in
            if s.history.firstIndex(where: { $0.output == output && $0.guide == guide }) == nil {
                s.record(input: input, output: output, guide: guide)
            }
            if let i = s.history.firstIndex(where: { $0.output == output && $0.guide == guide }) {
                s.history[i].favorite.toggle()
                result = s.history[i].favorite
            }
        }
        return result
    }

    func isFavorite(output: String, guide: StyleGuide) -> Bool {
        snapshot.history.contains { $0.output == output && $0.guide == guide && $0.favorite }
    }

    func delete(_ entry: HistoryEntry) { mutate { $0.history.removeAll { $0.id == entry.id } } }
    func clearRecents() { mutate { $0.history.removeAll { !$0.favorite } } }

    func addWord(_ word: String) {
        let w = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !w.isEmpty else { return }
        mutate { s in
            s.dictionary.words.removeAll { $0.lowercased() == w.lowercased() }
            s.dictionary.words.append(w)
            s.dictionary.words.sort { $0.lowercased() < $1.lowercased() }
        }
    }

    func removeWord(_ word: String) { mutate { $0.dictionary.words.removeAll { $0 == word } } }

    func setLastGuide(_ guide: StyleGuide) {
        guard snapshot.lastGuide != guide else { return }
        mutate { $0.lastGuide = guide }
    }

    func takePendingInput() -> String? {
        reload()
        guard let p = snapshot.pendingInput else { return nil }
        mutate { $0.pendingInput = nil }
        return p
    }

    private func mutate(_ change: (inout SharedSnapshot) -> Void) {
        var s = snapshot
        change(&s)
        guard s != snapshot else { return }
        snapshot = s
        SharedVault.save(s)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

enum Workspace: String, CaseIterable, Identifiable {
    case title, batch, tools, essay
    var id: String { rawValue }

    var name: String {
        switch self {
        case .title: return "Title"
        case .batch: return "Batch"
        case .tools: return "Text tools"
        case .essay: return "Essay"
        }
    }

    var systemImage: String {
        switch self {
        case .title: return "textformat"
        case .batch: return "list.bullet.rectangle"
        case .tools: return "wrench.and.screwdriver"
        case .essay: return "doc.text"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .title: return "1"
        case .batch: return "2"
        case .tools: return "3"
        case .essay: return "4"
        }
    }
}

@MainActor
final class EditorModel: ObservableObject {
    @Published var workspace: Workspace = .title
    @Published var input: String = "" { didSet { if input != oldValue { recompute() } } }
    @Published var guide: StyleGuide { didSet { if guide != oldValue { UserDefaults.standard.set(guide.rawValue, forKey: Self.guideKey); recompute(); library.setLastGuide(guide) } } }
    @Published private(set) var result: CaseResult

    // Batch
    @Published var batchInput: String = "" { didSet { recomputeBatch() } }
    @Published var batchOptions = BatchOptions() { didSet { recomputeBatch() } }
    @Published var batchUseTool = false { didSet { recomputeBatch() } }
    @Published private(set) var batchOutput: String = ""

    // Text tools
    @Published var toolsInput: String = "" { didSet { recomputeTool() } }
    @Published var tool: TextTool = .upper { didSet { recomputeTool() } }
    @Published private(set) var toolOutput: String = ""

    @Published var showingPaywall = false
    @Published var showingHistory = false
    @Published var flash: String?

    static let guideKey = "titleGuide"
    static let freeBatchPreviewLines = 3

    let library: LibraryStore
    let store: ProStore

    init(library: LibraryStore? = nil, store: ProStore? = nil) {
        let library = library ?? .shared
        self.library = library
        self.store = store ?? .shared
        let saved = UserDefaults.standard.string(forKey: Self.guideKey).flatMap(StyleGuide.init(rawValue:))
        let g = saved ?? .mla
        guide = g
        result = TitleCaseEngine.convert("", guide: g)
        recompute()
    }

    var hasInput: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var output: String { result.text }
    var isFavorite: Bool { hasInput && library.isFavorite(output: output, guide: guide) }

    /// Picks a guide, or opens the paywall for a locked one.
    func choose(_ g: StyleGuide) {
        if store.isUnlocked(g) { guide = g } else { showingPaywall = true }
    }

    func choose(_ t: TextTool) {
        if store.isUnlocked(t) { tool = t } else { showingPaywall = true }
    }

    func stepGuide(_ delta: Int) {
        let all = StyleGuide.allCases.filter { store.isUnlocked($0) }
        guard !all.isEmpty else { return }
        let i = all.firstIndex(of: guide) ?? 0
        guide = all[(i + delta + all.count) % all.count]
    }

    func recompute() {
        let flat = input.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\n", with: " ")
        let g = store.isUnlocked(guide) ? guide : .mla
        result = TitleCaseEngine.convert(flat, guide: g, dictionary: store.isPro ? library.dictionary : CustomDictionary())
    }

    func copyResult() {
        guard hasInput else { return }
        Platform.copyToClipboard(output)
        library.record(input: input, output: output, guide: guide)
        show("Copied")
    }

    func toggleFavorite() {
        guard hasInput else { return }
        let on = library.toggleFavorite(input: input, output: output, guide: guide)
        objectWillChange.send()
        show(on ? "Added to favourites" : "Removed from favourites")
    }

    func clear() {
        switch workspace {
        case .title: input = ""
        case .batch: batchInput = ""
        case .tools: toolsInput = ""
        case .essay: break
        }
    }

    func pasteAndConvert() {
        guard let s = Platform.clipboardString(), !s.isEmpty else { show("The clipboard has no text"); return }
        switch workspace {
        case .batch: batchInput = s
        case .tools: toolsInput = s
        case .title, .essay:
            workspace = .title
            input = s
        }
    }

    func restore(_ entry: HistoryEntry) {
        workspace = .title
        if store.isUnlocked(entry.guide) { guide = entry.guide }
        input = entry.input
    }

    /// Text dropped or shared in: many lines go to batch, a short one to the title editor.
    func receive(_ text: String) {
        let lines = text.split(whereSeparator: \.isNewline).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1 {
            workspace = .batch
            batchInput = text
        } else {
            workspace = .title
            input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    func handle(url: URL) -> Bool {
        guard url.scheme == TCLink.scheme else { return false }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if url.host == "history", let id = items.first(where: { $0.name == "id" })?.value.flatMap(UUID.init(uuidString:)),
           let entry = library.history.first(where: { $0.id == id }) {
            restore(entry)
            return true
        }
        if let g = items.first(where: { $0.name == "guide" })?.value.flatMap(StyleGuide.init(rawValue:)) { workspace = .title; choose(g) }
        let mode = items.first(where: { $0.name == "mode" })?.value
        if let m = mode.flatMap(Workspace.init(rawValue:)) { workspace = m }
        if mode == "paste" { workspace = .title; pasteAndConvert() }
        if items.contains(where: { $0.name == "paywall" }) { showingPaywall = true }
        if let pending = library.takePendingInput() { receive(pending) }
        return true
    }

    func recomputeBatch() {
        let transform: (String) -> String
        if batchUseTool {
            let t = store.isUnlocked(tool) ? tool : .upper
            transform = { t.apply($0) }
        } else {
            let g = store.isUnlocked(guide) ? guide : .mla
            let dict = store.isPro ? library.dictionary : CustomDictionary()
            transform = { TitleCaseEngine.apply($0, guide: g, dictionary: dict) }
        }
        var options = batchOptions
        if !store.isPro { options.mode = .lines }
        var source = batchInput
        if !store.isPro {
            let lines = batchInput.components(separatedBy: "\n")
            source = lines.prefix(Self.freeBatchPreviewLines).joined(separator: "\n")
        }
        batchOutput = BatchConverter.convert(source, options: options, transform: transform)
    }

    var batchLineCount: Int { batchInput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count }
    var batchIsTruncated: Bool { !store.isPro && batchInput.components(separatedBy: "\n").count > Self.freeBatchPreviewLines }

    func recomputeTool() {
        let t = store.isUnlocked(tool) ? tool : .upper
        toolOutput = t.apply(toolsInput)
    }

    /// Re-applies Pro state after a purchase, restore or dictionary change.
    func refreshAll() {
        recompute()
        recomputeBatch()
        recomputeTool()
    }

    func show(_ text: String) {
        flash = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            if flash == text { flash = nil }
        }
    }
}
