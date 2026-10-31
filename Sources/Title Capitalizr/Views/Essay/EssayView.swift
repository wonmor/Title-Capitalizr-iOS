//
//  EssayView.swift
//  Title Capitalizr
//
//  The essay formatter: drop or pick a Word, PDF, RTF or text file (or paste a
//  Google Docs link), confirm the detected heading and title, review every fix,
//  preview the formatted pages and export. Free users see the detected structure,
//  all checks and the first page; Pro unlocks the full preview and every export.
//

import SwiftUI
import UniformTypeIdentifiers

struct EssayView: View {
    @ObservedObject var workspace: EssayWorkspace
    @ObservedObject var store: ProStore
    @StateObject private var smart = SmartCapitalizer()
    @AppStorage(SettingsKeys.aiFeaturesEnabled) private var aiFeaturesEnabled = true

    @State private var showingImporter = false
    @State private var googleLink = ""
    @State private var dropTargeted = false
    @State private var showingPaywall = false
    @State private var showingGoogleDocsHelp = false

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            if let error = workspace.errorMessage { errorBanner(error) }
            if workspace.hasDocument {
                SourceStrip(workspace: workspace)
                StylePicker(style: $workspace.style)
                HeadingEditor(workspace: workspace, aiAvailable: aiFeaturesEnabled && smart.availability.isAvailable,
                              askAI: { workspace.askAppleIntelligence(availability: smart.availability) })
                ChecksList(workspace: workspace).id("checks")
                previewSection.id("preview")
                exportSection.id("export")
            } else {
                importSection
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: EssayWorkspace.importTypes, allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { workspace.load(url: url) }
            if case .failure(let error) = result { workspace.errorMessage = error.localizedDescription }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView(store: store)
                .bauhausSheet()
        }
        .onAppear {
            if ProcessInfo.processInfo.environment["TC_DEMO_PAYWALL"] == "1" { showingPaywall = true }
        }
        .alert("Open in Google Docs", isPresented: $showingGoogleDocsHelp) {
            #if os(iOS)
            Button("Save to Files or Drive") { if let url = workspace.writeTemporaryFile(.docx) { PlatformExport.saveToFiles([url]) } }
            Button("Share") { if let url = workspace.writeTemporaryFile(.docx) { PlatformExport.share([url]) } }
            #endif
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Google Docs isn't installed. Save the Word file to Google Drive or Files, then open it in Google Docs or at docs.google.com. It keeps the running header, spacing and indents.")
        }
    }

    // MARK: Import

    private var importSection: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            dropZone
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Google Docs link")
                HStack(spacing: 0) {
                    BoxedTextField(placeholder: "docs.google.com/document/d/...", text: $googleLink)
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .onSubmit(fetchGoogleDoc)
                    Button(action: fetchGoogleDoc) {
                        Image(systemName: workspace.isLoading ? "hourglass" : "arrow.down.doc")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Bauhaus.Palette.ground)
                            .frame(width: 52, height: 48)
                            .background(googleLink.isEmpty ? Bauhaus.Palette.inkDisabled : Bauhaus.Palette.blue)
                            .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                    }
                    .buttonStyle(.plain)
                    .disabled(googleLink.isEmpty || workspace.isLoading)
                    .accessibilityLabel("Fetch Google Doc")
                }
                Text("Works for docs shared as \"Anyone with the link\". For a private doc, choose File > Download > Microsoft Word (.docx) in Google Docs and drop the file here.")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("What it fixes")
                FeatureRow(glyph: "text.alignleft", fill: Bauhaus.Palette.blue, text: "MLA 9, APA 7 and Chicago: Times New Roman 12, double spacing, 1 inch margins, running header")
                FeatureRow(glyph: "person.text.rectangle", fill: Bauhaus.Palette.yellow, text: "Heading block or title page, title case, 0.5 inch indents")
                FeatureRow(glyph: "books.vertical", fill: Bauhaus.Palette.red, text: "Works Cited on its own page, sorted, with hanging indents; in-text citation checks")
                FeatureRow(glyph: "square.and.arrow.up", fill: Bauhaus.Palette.ink, text: "Export Word, PDF, RTF or text, or open it in Google Docs")
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Bauhaus.Palette.yellow.frame(height: 10)
                Bauhaus.Palette.blue.frame(width: 64, height: 10)
            }
            VStack(spacing: Bauhaus.Space.m) {
                GlyphTile(systemImage: "doc.badge.plus", fill: dropTargeted ? Bauhaus.Palette.blue : Bauhaus.Palette.yellow, size: 64)
                Text(Platform.isMac ? "DROP AN ESSAY HERE" : "FORMAT AN ESSAY")
                    .font(Bauhaus.Typo.title).tracking(1)
                Text("Word (.docx), PDF, RTF or plain text")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                VStack(spacing: Bauhaus.Space.s) {
                    BarButton(title: "Choose a file", systemImage: "folder", kind: .action) { showingImporter = true }
                    BarButton(title: "Try a sample essay", systemImage: "doc.text", kind: .secondary) { workspace.loadSample() }
                }
                .frame(maxWidth: 360)
            }
            .padding(Bauhaus.Space.l)
            .frame(maxWidth: .infinity)
        }
        .background(dropTargeted ? Bauhaus.Palette.groundSoft : Bauhaus.Palette.ground)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: dropTargeted ? Bauhaus.Rule.thick : Bauhaus.Rule.regular))
        .onDrop(of: [.fileURL, .item, .url], isTargeted: $dropTargeted, perform: handleDrop)
        .accessibilityElement(children: .contain)
    }

    private func fetchGoogleDoc() {
        guard !googleLink.isEmpty else { return }
        hideKeyboard()
        workspace.load(googleDocsLink: googleLink)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        // A file URL (Finder, Files).
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in
                    if url.isFileURL { workspace.load(url: url) } else { workspace.load(googleDocsLink: url.absoluteString) }
                }
            }
            return true
        }
        // A file representation (drag from another app on iPhone or iPad).
        for type in EssayWorkspace.importTypes where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            let ext = type.preferredFilenameExtension ?? "txt"
            provider.loadFileRepresentation(forTypeIdentifier: type.identifier) { url, _ in
                guard let url, let data = try? Data(contentsOf: url) else { return }
                let name = url.deletingPathExtension().lastPathComponent
                Task { @MainActor in workspace.load(data: data, fileExtension: url.pathExtension.isEmpty ? ext : url.pathExtension, fileName: name) }
            }
            return true
        }
        // A web link (Google Docs dragged from a browser).
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in workspace.load(googleDocsLink: url.absoluteString) }
            }
            return true
        }
        return false
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
            GlyphTile(systemImage: "exclamationmark", fill: Bauhaus.Palette.red, size: 30)
            Text(message).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { workspace.errorMessage = nil } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .bold)) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
        }
        .padding(Bauhaus.Space.m - 4)
        .background(Bauhaus.Palette.ground)
        .overlay(Rectangle().stroke(Bauhaus.Palette.redInk, lineWidth: Bauhaus.Rule.regular))
    }

    // MARK: Preview

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Preview") {
                Text(workspace.pageCount == 1 ? "1 PAGE" : "\(workspace.pageCount) PAGES")
                    .font(Bauhaus.Typo.section).tracking(1.2).foregroundStyle(Bauhaus.Palette.inkSecondary)
            }
            if store.isPro {
                PDFPreview(data: workspace.previewPDF)
                    .frame(height: Platform.isMac ? 620 : 520)
                    .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                    .accessibilityLabel("Formatted essay preview")
            } else {
                VStack(spacing: 0) {
                    PDFPageImage(data: workspace.previewPDF)
                        .padding(Bauhaus.Space.m)
                        .background(Bauhaus.Palette.groundSoft)
                    HStack(spacing: Bauhaus.Space.m - 4) {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                        Text(workspace.pageCount > 1 ? "Page 1 of \(workspace.pageCount). Pro shows every page and exports the file." : "Pro exports the formatted file.")
                            .font(Bauhaus.Typo.bodyBold).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .foregroundStyle(Bauhaus.Palette.ground)
                    .padding(Bauhaus.Space.m - 4)
                    .background(Bauhaus.Palette.ink)
                }
                .frame(maxWidth: Platform.isMac ? 520 : .infinity)
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                .accessibilityLabel("First page preview")
            }
        }
    }

    // MARK: Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Export") {
                if !store.isPro {
                    Text("PRO").font(Bauhaus.Typo.section).tracking(1.4).foregroundStyle(Bauhaus.Palette.ground)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Bauhaus.Palette.red)
                }
            }
            Text(workspace.exportFileName(.docx))
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            if store.isPro {
                ExportButtons(workspace: workspace, onGoogleDocsMissing: { showingGoogleDocsHelp = true })
            } else {
                BarButton(title: "Unlock export with Pro", systemImage: "lock.open", kind: .pro) { showingPaywall = true }
                Text("Word, PDF, Google Docs, RTF and text. Your structure, checks and first page stay free.")
                    .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
            }
        }
    }
}

// MARK: - Pieces

private struct FeatureRow: View {
    let glyph: String
    let fill: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
            GlyphTile(systemImage: glyph, fill: fill, size: 30)
            Text(text).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct SourceStrip: View {
    @ObservedObject var workspace: EssayWorkspace

    var body: some View {
        HStack(spacing: Bauhaus.Space.m - 4) {
            GlyphTile(systemImage: icon, fill: Bauhaus.Palette.ink, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.source?.fileName ?? "Essay").font(Bauhaus.Typo.bodyBold).lineLimit(1)
                Text(detail).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary).lineLimit(2)
            }
            Spacer(minLength: Bauhaus.Space.s)
            TagButton(title: "New", systemImage: "arrow.uturn.backward") { workspace.clear() }
                .accessibilityLabel("Format a different essay")
        }
        .padding(Bauhaus.Space.m - 4)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }

    private var icon: String {
        switch workspace.source?.kind {
        case .pdf: return "doc.richtext"
        case .googleDocs: return "link"
        case .txt, .rtf: return "doc.plaintext"
        default: return "doc.text"
        }
    }

    private var detail: String {
        guard let s = workspace.structure, let src = workspace.source else { return "" }
        var parts = ["\(src.kind.rawValue)", "\(s.body.count) paragraph\(s.body.count == 1 ? "" : "s")",
                     "\(s.references.count) source\(s.references.count == 1 ? "" : "s")"]
        if !s.footnotes.isEmpty { parts.append("\(s.footnotes.count) footnote\(s.footnotes.count == 1 ? "" : "s")") }
        var line = parts.joined(separator: " | ")
        if let note = src.notes.first { line += "\n" + note }
        return line
    }
}

private struct StylePicker: View {
    @Binding var style: EssayStyle

    private var family: Binding<Int> {
        Binding(get: {
            switch style {
            case .mla9: return 0
            case .apa7: return 1
            case .chicagoNotes, .chicagoAuthorDate: return 2
            }
        }, set: { v in
            switch v {
            case 0: style = .mla9
            case 1: style = .apa7
            default: if style != .chicagoAuthorDate { style = .chicagoNotes }
            }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Style")
            Segmented(options: [(0, "MLA 9"), (1, "APA 7"), (2, "Chicago")], selection: family, identifierPrefix: "essay-style")
            if style == .chicagoNotes || style == .chicagoAuthorDate {
                Segmented(options: [(EssayStyle.chicagoNotes, "Notes-bibliography"), (EssayStyle.chicagoAuthorDate, "Author-date")],
                          selection: $style, identifierPrefix: "chicago")
            }
        }
    }
}

private struct HeadingEditor: View {
    @ObservedObject var workspace: EssayWorkspace
    let aiAvailable: Bool
    let askAI: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
            SectionTitle(workspace.style == .mla9 ? "Heading" : "Title page") {
                if !workspace.needsReview.isEmpty {
                    Text("\(workspace.needsReview.count) TO CHECK")
                        .font(Bauhaus.Typo.section).tracking(1.2)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Bauhaus.Palette.yellow)
                }
            }
            field(.name, \.name, placeholder: "First and last name")
            field(.instructor, \.instructor, placeholder: "Professor Rivera")
            field(.course, \.course, placeholder: "ENGL 101")
            field(.date, \.date, placeholder: workspace.style == .mla9 ? "30 October 2026" : "October 30, 2026")
            if workspace.style == .apa7 {
                field(.institution, \.institution, placeholder: "Department of English, Example University")
            }
            titleField
            if let suggestion = workspace.referencesSuggestion {
                VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                    Label("Apple Intelligence thinks your sources start at:", systemImage: "sparkles").font(Bauhaus.Typo.bodyBold)
                    Text(suggestion.text).font(Bauhaus.Typo.caption).lineLimit(3)
                    HStack {
                        TagButton(title: "Use as Works Cited", systemImage: "checkmark", filled: true) { workspace.acceptReferencesSuggestion() }
                        Spacer()
                    }
                }
                .padding(Bauhaus.Space.m - 4)
                .overlay(Rectangle().stroke(Bauhaus.Palette.blue, lineWidth: Bauhaus.Rule.regular))
            }
            if aiAvailable, !workspace.needsReview.isEmpty {
                BarButton(title: workspace.isAsking ? "Reading your essay" : "Fill gaps with Apple Intelligence", systemImage: "sparkles", kind: .secondary, action: askAI)
                    .disabled(workspace.isAsking)
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label(for: .title)
            BoxedTextField(placeholder: "Your essay's title", text: Binding(get: { workspace.title }, set: { workspace.title = $0; workspace.edited(.title) }))
            if let out = workspace.output, !out.essay.title.isEmpty, out.essay.title != workspace.title {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 12, weight: .bold))
                    Text(out.essay.title).font(Bauhaus.Typo.bodyBold)
                }
                .foregroundStyle(Bauhaus.Palette.blue)
                .accessibilityLabel("Printed as \(out.essay.title)")
            }
        }
    }

    private func field(_ f: EssayStructure.Field, _ path: WritableKeyPath<HeadingFields, String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(for: f)
            BoxedTextField(placeholder: placeholder, text: Binding(get: { workspace.heading[keyPath: path] },
                                                                  set: { workspace.heading[keyPath: path] = $0; workspace.edited(f) }))
        }
    }

    private func label(for f: EssayStructure.Field) -> some View {
        HStack(spacing: Bauhaus.Space.s) {
            Text(f.label.uppercased()).font(Bauhaus.Typo.section).tracking(1.2).foregroundStyle(Bauhaus.Palette.inkSecondary)
            if workspace.needsReview.contains(f) {
                let isSuggested = workspace.suggested.contains(f)
                Text(isSuggested ? "SUGGESTED" : "CHECK")
                    .font(Bauhaus.Typo.font(11, weight: .bold, relativeTo: .caption2)).tracking(1)
                    .foregroundStyle(isSuggested ? Bauhaus.Palette.ground : Bauhaus.Palette.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(isSuggested ? Bauhaus.Palette.blue : Bauhaus.Palette.yellow)
                Spacer(minLength: 0)
                Button("Looks right") { workspace.confirm(f) }
                    .font(Bauhaus.Typo.font(13, weight: .semibold, relativeTo: .caption))
                    .buttonStyle(.plain)
                    .foregroundStyle(Bauhaus.Palette.blue)
            }
        }
    }
}

private struct ChecksList: View {
    @ObservedObject var workspace: EssayWorkspace
    @State private var showApplied = false

    var body: some View {
        let issues = workspace.output?.issues ?? []
        let fixes = issues.filter { $0.kind == .fix }
        let warnings = issues.filter { $0.kind == .warning }
        let applied = issues.filter { $0.kind == .applied }
        VStack(alignment: .leading, spacing: Bauhaus.Space.m - 4) {
            SectionTitle("Checks") {
                Text("\(fixes.count) FIX\(fixes.count == 1 ? "" : "ES") | \(warnings.count) TO REVIEW")
                    .font(Bauhaus.Typo.section).tracking(1.2).foregroundStyle(Bauhaus.Palette.inkSecondary)
            }
            if fixes.isEmpty && warnings.isEmpty {
                Label("No citation problems found", systemImage: "checkmark.seal").font(Bauhaus.Typo.body)
            }
            ForEach(warnings) { w in
                HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                    GlyphTile(systemImage: "eye", fill: Bauhaus.Palette.yellow, size: 26)
                    Text(w.message).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
            ForEach(fixes) { f in
                let on = !workspace.disabledFixes.contains(f.id)
                HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                    Checkbox(label: "", isOn: Binding(get: { on }, set: { v in
                        if v { workspace.disabledFixes.remove(f.id) } else { workspace.disabledFixes.insert(f.id) }
                    }))
                    .frame(width: 28)
                    .accessibilityLabel(f.message)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f.message).font(Bauhaus.Typo.bodyBold).fixedSize(horizontal: false, vertical: true)
                        if let o = f.original, let r = f.replacement {
                            Text("\(o)  \u{2192}  \(r)")
                                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                                .strikethrough(!on).lineLimit(3)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            Button { withAnimation(.easeOut(duration: 0.15)) { showApplied.toggle() } } label: {
                HStack {
                    Text("\(applied.count) FORMATTING RULES APPLIED").font(Bauhaus.Typo.section).tracking(1.2)
                    Spacer()
                    Image(systemName: showApplied ? "chevron.up" : "chevron.down").font(.system(size: 13, weight: .bold))
                }
                .frame(minHeight: Bauhaus.tapTarget)
                .padding(.horizontal, Bauhaus.Space.m - 4)
                .background(Bauhaus.Palette.groundSoft)
                .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showApplied {
                ForEach(applied) { a in
                    HStack(alignment: .top, spacing: Bauhaus.Space.m - 4) {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Bauhaus.Palette.blue).frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.message).font(Bauhaus.Typo.body).fixedSize(horizontal: false, vertical: true)
                            if let o = a.original, let r = a.replacement {
                                Text("\(o)  \u{2192}  \(r)").font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct ExportButtons: View {
    @ObservedObject var workspace: EssayWorkspace
    let onGoogleDocsMissing: () -> Void

    var body: some View {
        VStack(spacing: Bauhaus.Space.s) {
            #if os(iOS)
            BarButton(title: "Share Word file", systemImage: "square.and.arrow.up", kind: .action) { share(.docx) }
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "Save to Files", systemImage: "folder", kind: .secondary) {
                    if let url = workspace.writeTemporaryFile(.docx) { PlatformExport.saveToFiles([url]) }
                }
                BarButton(title: "Google Docs", systemImage: "arrow.up.forward.app", kind: .secondary) {
                    if PlatformExport.googleDocsInstalled { share(.docx) } else { onGoogleDocsMissing() }
                }
            }
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "PDF", systemImage: "doc.richtext", kind: .secondary) { share(.pdf) }
                BarButton(title: "RTF", systemImage: "doc", kind: .secondary) { share(.rtf) }
                BarButton(title: "Text", systemImage: "doc.plaintext", kind: .secondary) { share(.txt) }
            }
            Text("For Google Docs, choose Docs in the share sheet. Save to Files also reaches Google Drive.")
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            #else
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "Save Word file", systemImage: "square.and.arrow.down", kind: .action) { save(.docx) }
                BarButton(title: "Save PDF", systemImage: "doc.richtext", kind: .secondary) { save(.pdf) }
            }
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "Google Docs", systemImage: "arrow.up.forward.app", kind: .secondary) {
                    if let data = workspace.exportData(.docx) { PlatformExport.handOffToGoogleDocs(data, suggestedName: workspace.exportFileName(.docx)) }
                }
                BarButton(title: "RTF", systemImage: "doc", kind: .secondary) { save(.rtf) }
                BarButton(title: "Text", systemImage: "doc.plaintext", kind: .secondary) { save(.txt) }
            }
            DragOutTile(workspace: workspace)
            Text("Google Docs: the Word file is saved, shown in Finder and Google Drive opens; drop it in and it opens in Google Docs.")
                .font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            #endif
        }
    }

    #if os(iOS)
    private func share(_ format: ExportFormat) {
        if let url = workspace.writeTemporaryFile(format) { PlatformExport.share([url]) }
    }
    #else
    private func save(_ format: ExportFormat) {
        if let data = workspace.exportData(format) { PlatformExport.save(data, suggestedName: workspace.exportFileName(format), format: format) }
    }
    #endif
}

#if os(macOS)
/// Drag the formatted .docx straight into Finder, Mail or a browser upload.
private struct DragOutTile: View {
    @ObservedObject var workspace: EssayWorkspace

    var body: some View {
        HStack(spacing: Bauhaus.Space.m - 4) {
            GlyphTile(systemImage: "hand.draw", fill: Bauhaus.Palette.yellow, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Drag the Word file out").font(Bauhaus.Typo.bodyBold)
                Text(workspace.exportFileName(.docx)).font(Bauhaus.Typo.caption).foregroundStyle(Bauhaus.Palette.inkSecondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").font(.system(size: 15, weight: .semibold))
        }
        .padding(Bauhaus.Space.m - 4)
        .background(Bauhaus.Palette.ground)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, style: StrokeStyle(lineWidth: Bauhaus.Rule.regular, dash: [6, 4])))
        .contentShape(Rectangle())
        .onDrag {
            guard let url = workspace.writeTemporaryFile(.docx) else { return NSItemProvider() }
            return NSItemProvider(contentsOf: url) ?? NSItemProvider()
        }
        .help("Drag into Finder or any app that accepts Word files")
    }
}
#endif
