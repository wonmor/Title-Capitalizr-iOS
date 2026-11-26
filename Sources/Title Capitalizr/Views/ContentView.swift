//
//  ContentView.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//  1.7: iPad and Mac split layout (sidebar with workspaces, style guides, favourites and history;
//  editor beside a live preview), iPhone single column, keyboard shortcuts, drag and drop.
//

import SwiftUI
import TitleCaseKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var model = EditorModel()
    @StateObject private var essay = EssayWorkspace()
    @ObservedObject private var store = ProStore.shared
    @ObservedObject private var library = LibraryStore.shared
    @Environment(\.horizontalSizeClass) private var hSize
    @Environment(\.scenePhase) private var phase
    @State private var showingSettings = false
    @State private var columns: NavigationSplitViewVisibility = .all
    @SceneStorage("macSidebar") private var showMacSidebar = true

    private var useSplit: Bool {
        #if os(macOS)
        return true
        #else
        return hSize == .regular
        #endif
    }

    var body: some View {
        Group {
            if useSplit { splitLayout } else { compactLayout }
        }
        .focusedSceneObject(model)
        .bauhausScreen()
        .sheet(isPresented: $model.showingPaywall) { PaywallView(store: store).bauhausSheet() }
        .sheet(isPresented: $showingSettings) { SettingsView(store: store).bauhausSheet() }
        .sheet(isPresented: $model.showingHistory) {
            HistoryView(library: library, onSelect: { model.restore($0); model.showingHistory = false }, showsDone: true)
                .bauhausScreen()
                .bauhausSheet()
        }
        .onOpenURL { url in
            if model.handle(url: url) { return }
            model.workspace = .essay
            if url.isFileURL { essay.load(url: url) } else { essay.load(googleDocsLink: url.absoluteString) }
        }
        .onChange(of: store.isPro) { _, _ in model.refreshAll() }
        .onChange(of: library.dictionary) { _, _ in model.refreshAll() }
        .onChange(of: phase) { _, p in
            guard p == .active else { return }
            library.reload()
            if let pending = library.takePendingInput() { model.receive(pending) }
            Task { await store.foreground() }
        }
        .onChange(of: store.paywallRequested) { _, requested in
            if requested { model.showingPaywall = true; store.paywallRequested = false }
        }
        .overlay(alignment: .bottom) { toast }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: .tcReceiveText)) { note in
            if let text = note.object as? String { model.receive(text) }
        }
        #endif
        .onAppear(perform: applyDemoEnvironment)
    }

    /// Screenshot runs: TC_DEMO_SCROLL=why|ai|preview scrolls to that panel.
    private func demoScroll(_ proxy: ScrollViewProxy) {
        guard let raw = ProcessInfo.processInfo.environment["TC_DEMO_SCROLL"] else { return }
        let parts = raw.split(separator: "@").map(String.init)
        let unit: UnitPoint = parts.count > 1 && parts[1] == "bottom" ? .bottom : .top
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            proxy.scrollTo(parts[0], anchor: unit)
        }
    }

    // MARK: Layouts

    @ViewBuilder
    private var splitLayout: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            if showMacSidebar {
                SidebarView(model: model, library: library, store: store)
                    .frame(width: 270)
                    .transition(.move(edge: .leading))
            }
            detailColumn
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { withAnimation(.easeOut(duration: 0.2)) { showMacSidebar.toggle() } } label: {
                    Label("Sidebar", systemImage: "sidebar.left")
                }
                .help("Show or hide the sidebar")
            }
        }
        #else
        NavigationSplitView(columnVisibility: $columns) {
            SidebarView(model: model, library: library, store: store)
                .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    private var detailColumn: some View {
            ScrollViewReader { proxy in ScrollView {
                VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                    detailHeader
                    workspaceContent(wide: true)
                }
                .padding(Bauhaus.Space.l)
                .frame(maxWidth: 1180)
                .frame(maxWidth: .infinity)
            }
            .background(Bauhaus.Palette.ground)
            .onAppear { demoScroll(proxy) }
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { detailToolbar }
    }

    private var compactLayout: some View {
        ScrollViewReader { proxy in ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                Masthead(onHistory: { hideKeyboard(); model.showingHistory = true },
                         onSettings: { hideKeyboard(); showingSettings = true })
                Segmented(options: Workspace.allCases.map { ($0, $0 == .tools ? "Tools" : $0.name) },
                          selection: $model.workspace, identifierPrefix: "mode")
                workspaceContent(wide: false)
                Text("Designed by John Seong")
                    .font(Bauhaus.Typo.caption)
                    .foregroundStyle(Bauhaus.Palette.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, Bauhaus.Space.m)
            }
            .padding(.horizontal, Bauhaus.Space.m + 4)
            .padding(.top, Bauhaus.Space.m)
            .padding(.bottom, Bauhaus.Space.xl)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .onAppear { demoScroll(proxy) }
        }
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.workspace.name.uppercased()).font(Bauhaus.Typo.display).tracking(1)
                Spacer()
            }
            HStack(spacing: 0) {
                Bauhaus.Palette.red.frame(width: 48, height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.yellow.frame(width: 48, height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.blue.frame(width: 48, height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.ink.frame(height: Bauhaus.Rule.heavy).frame(maxWidth: .infinity)
            }
            .accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button { model.pasteAndConvert() } label: { Label("Paste and Convert", systemImage: "doc.on.clipboard") }
                .help("Paste and Convert (Shift Command V)")
            Button { model.clear() } label: { Label("Clear", systemImage: "eraser") }
                .help("Clear (Command K)")
            if !store.isPro {
                Button { model.showingPaywall = true } label: { Label("Pro", systemImage: "lock.open") }
                    .help("See Pro plans")
            }
            #if os(iOS)
            Button { showingSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            #endif
        }
    }

    @ViewBuilder
    private func workspaceContent(wide: Bool) -> some View {
        switch model.workspace {
        case .title: TitleWorkspaceView(model: model, store: store, library: library, wide: wide)
        case .batch: BatchView(model: model, store: store, wide: wide)
        case .tools: ToolsView(model: model, store: store, wide: wide)
        case .essay: EssayView(workspace: essay, store: store)
        }
    }

    @ViewBuilder
    private var toast: some View {
        if let text = model.flash {
            Label(text, systemImage: "checkmark")
                .font(Bauhaus.Typo.button)
                .foregroundStyle(Bauhaus.Palette.ground)
                .padding(.horizontal, Bauhaus.Space.m).padding(.vertical, Bauhaus.Space.s + 2)
                .background(Bauhaus.Palette.ink)
                .padding(.bottom, Bauhaus.Space.l)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    /// Screenshot and UI smoke hooks (environment variables, never set in release use):
    /// TC_DEMO_MODE=title|batch|tools|essay, TC_DEMO_TITLE, TC_DEMO_GUIDE, TC_DEMO_BATCH, TC_DEMO_TOOLS,
    /// TC_DEMO_TOOL, TC_DEMO_SAMPLE=1, TC_DEMO_STYLE (essay), TC_DEMO_SHOW_SETTINGS, TC_DEMO_PAYWALL, TC_DEMO_HISTORY.
    private func applyDemoEnvironment() {
        let env = ProcessInfo.processInfo.environment
        if let m = env["TC_DEMO_MODE"], let parsed = Workspace(rawValue: m) { model.workspace = parsed }
        if let g = env["TC_DEMO_GUIDE"], let guide = StyleGuide(rawValue: g) { model.guide = guide }
        if let t = env["TC_DEMO_TITLE"], model.input.isEmpty { model.input = t }
        if let b = env["TC_DEMO_BATCH"] { model.batchInput = b.replacingOccurrences(of: "\\n", with: "\n") }
        if env["TC_DEMO_BATCH_CSV"] == "1" { model.batchOptions.mode = .csvColumn; model.batchOptions.csvColumn = Int(env["TC_DEMO_BATCH_COL"] ?? "0") ?? 0 }
        if let t = env["TC_DEMO_TOOLS"] { model.toolsInput = t.replacingOccurrences(of: "\\n", with: "\n") }
        if let t = env["TC_DEMO_TOOL"], let tool = TextTool(rawValue: t) { model.tool = tool }
        if env["TC_DEMO_SAMPLE"] == "1", !essay.hasDocument { essay.loadSample() }
        if let s = env["TC_DEMO_STYLE"], let style = EssayStyle(rawValue: s) { essay.style = style }
        if env["TC_DEMO_SHOW_SETTINGS"] == "1" { showingSettings = true }
        if env["TC_DEMO_PAYWALL"] == "1" { model.showingPaywall = true }
        if env["TC_DEMO_HISTORY"] == "1" { model.showingHistory = true }
        if let seed = env["TC_DEMO_SEED_HISTORY"] {
            // "guide|input;guide|input*" (a trailing * marks a favourite)
            for item in seed.split(separator: ";").reversed() {
                let parts = item.split(separator: "|", maxSplits: 1).map(String.init)
                guard parts.count == 2, let g = StyleGuide(rawValue: parts[0]) else { continue }
                let fav = parts[1].hasSuffix("*")
                let text = fav ? String(parts[1].dropLast()) : parts[1]
                let out = TitleCaseEngine.apply(text, guide: g)
                library.record(input: text, output: out, guide: g)
                if fav, !library.isFavorite(output: out, guide: g) { library.toggleFavorite(input: text, output: out, guide: g) }
            }
        }
        if let words = env["TC_DEMO_DICTIONARY"] { words.split(separator: ",").forEach { library.addWord(String($0)) } }
    }
}

// MARK: - Masthead (iPhone)

struct Masthead: View {
    var onHistory: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Bauhaus.Space.m - 4) {
                Image("AppIconPreview")
                    .resizable()
                    .frame(width: 52, height: 52)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: -6) {
                    Text("TITLE").font(Bauhaus.Typo.display).tracking(1)
                    Text("CAPITALIZR").font(Bauhaus.Typo.display).tracking(1).foregroundStyle(Bauhaus.Palette.blue)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Title Capitalizr")
                .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                squareButton("clock.arrow.circlepath", "History", action: onHistory)
                squareButton("gearshape", "Settings", action: onSettings)
            }
            .padding(.bottom, Bauhaus.Space.m - 4)
            HStack(spacing: 0) {
                Bauhaus.Palette.red.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.yellow.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.blue.frame(height: Bauhaus.Rule.heavy)
                Bauhaus.Palette.ink.frame(height: Bauhaus.Rule.heavy).frame(maxWidth: .infinity)
            }
            .accessibilityHidden(true)
        }
    }

    private func squareButton(_ glyph: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: glyph)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: Bauhaus.tapTarget, height: Bauhaus.tapTarget)
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Sidebar (iPad, Mac)

struct SidebarView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var library: LibraryStore
    @ObservedObject var store: ProStore

    enum Item: Hashable { case workspace(Workspace), guide(StyleGuide), entry(UUID) }

    private var selection: Binding<Item?> {
        Binding(get: { .workspace(model.workspace) }, set: { item in
            switch item {
            case .workspace(let w)?: model.workspace = w
            case .guide(let g)?: model.workspace = .title; model.choose(g)
            case .entry(let id)?: if let e = library.history.first(where: { $0.id == id }) { model.restore(e) }
            case nil: break
            }
        })
    }

    var body: some View {
        #if os(macOS)
        macBody
        #else
        listBody
        #endif
    }

    #if os(macOS)
    /// Mac: a plain Bauhaus column (no vibrancy material), same sections as the iPad list.
    private var macBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
                macSection("Workspaces") {
                    ForEach(Workspace.allCases) { w in
                        macRow(selected: model.workspace == w) { model.workspace = w } label: {
                            Label(w.name, systemImage: w.systemImage).font(Bauhaus.Typo.bodyBold)
                        }
                    }
                }
                macSection("Style guides") {
                    ForEach(StyleGuide.allCases) { g in
                        macRow(selected: false) { model.workspace = .title; model.choose(g) } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(Bauhaus.Palette.blue).opacity(g == model.guide ? 1 : 0).frame(width: 14)
                                Text(g.displayName).font(Bauhaus.Typo.body)
                                Spacer(minLength: 0)
                                if !store.isUnlocked(g) { Image(systemName: "lock").font(.system(size: 11)).foregroundStyle(Bauhaus.Palette.redInk) }
                            }
                        }
                        .accessibilityLabel(g.displayName + (store.isUnlocked(g) ? "" : ", Pro"))
                    }
                }
                if !library.favorites.isEmpty {
                    macSection("Favourites") { ForEach(library.favorites) { e in macEntry(e) } }
                }
                macSection("History") {
                    if library.recents.isEmpty {
                        Text("Copied titles appear here.").font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    }
                    ForEach(library.recents.prefix(40)) { e in macEntry(e) }
                }
            }
            .padding(.horizontal, Bauhaus.Space.m)
            .padding(.vertical, Bauhaus.Space.m)
        }
        .background(Bauhaus.Palette.groundSoft)
        .overlay(alignment: .trailing) { VRule(thickness: Bauhaus.Rule.regular) }
    }

    private func macSection<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            header(title)
            HRule(thickness: Bauhaus.Rule.thick).padding(.bottom, 4)
            content()
        }
    }

    private func macRow<L: View>(selected: Bool, action: @escaping () -> Void, @ViewBuilder label: () -> L) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(selected ? Bauhaus.Palette.ground : Bauhaus.Palette.ink)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? Bauhaus.Palette.blue : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func macEntry(_ e: HistoryEntry) -> some View {
        macRow(selected: false) { model.restore(e) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.output).font(Bauhaus.Typo.body).lineLimit(2)
                Text(e.guide.shortName.uppercased()).font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.inkSecondary)
            }
        }
        .draggable(e.output)
        .contextMenu {
            Button { Platform.copyToClipboard(e.output) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { library.toggleFavorite(e) } label: {
                Label(e.favorite ? "Remove from Favourites" : "Add to Favourites", systemImage: e.favorite ? "star.slash" : "star")
            }
            Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
        }
    }
    #endif

    private var listBody: some View {
        List(selection: selection) {
            Section {
                ForEach(Workspace.allCases) { w in
                    Label(w.name, systemImage: w.systemImage)
                        .font(Bauhaus.Typo.bodyBold)
                        .tag(Item.workspace(w))
                }
            } header: { header("Workspaces") }

            Section {
                ForEach(StyleGuide.allCases) { g in
                    HStack {
                        Image(systemName: "checkmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Bauhaus.Palette.blue)
                            .opacity(g == model.guide ? 1 : 0)
                            .frame(width: 18)
                        Text(g.displayName).font(Bauhaus.Typo.body)
                        Spacer()
                        if !store.isUnlocked(g) { Image(systemName: "lock").font(.caption).foregroundStyle(Bauhaus.Palette.redInk) }
                    }
                    .tag(Item.guide(g))
                    .accessibilityLabel(g.displayName + (store.isUnlocked(g) ? "" : ", Pro"))
                }
            } header: { header("Style guides") }

            if !library.favorites.isEmpty {
                Section {
                    ForEach(library.favorites) { e in entryRow(e).tag(Item.entry(e.id)) }
                } header: { header("Favourites") }
            }

            Section {
                if library.recents.isEmpty {
                    Text("Copied titles appear here.").font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                }
                ForEach(library.recents.prefix(40)) { e in entryRow(e).tag(Item.entry(e.id)) }
            } header: { header("History") }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Bauhaus.Palette.groundSoft)
        .navigationTitle("Title Capitalizr")
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(Bauhaus.Typo.section).tracking(1.4).foregroundStyle(Bauhaus.Palette.ink)
    }

    private func entryRow(_ e: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(e.output).font(Bauhaus.Typo.body).lineLimit(2)
            Text(e.guide.shortName.uppercased()).font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.inkSecondary)
        }
        .draggable(e.output)
        .contextMenu {
            Button { Platform.copyToClipboard(e.output) } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button { library.toggleFavorite(e) } label: {
                Label(e.favorite ? "Remove from Favourites" : "Add to Favourites", systemImage: e.favorite ? "star.slash" : "star")
            }
            Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
        }
        .swipeActions {
            Button(role: .destructive) { library.delete(e) } label: { Label("Delete", systemImage: "trash") }
            Button { library.toggleFavorite(e) } label: { Label("Favourite", systemImage: e.favorite ? "star.slash" : "star") }
                .tint(Bauhaus.Palette.yellow)
        }
    }
}
