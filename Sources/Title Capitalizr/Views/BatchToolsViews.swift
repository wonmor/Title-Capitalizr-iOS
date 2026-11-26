//
//  BatchToolsViews.swift
//  Title Capitalizr
//
//  Batch mode (many titles, file names or one CSV column at once) and the text tools.
//

import SwiftUI
import TitleCaseKit
import UniformTypeIdentifiers

/// Boxed multi-line editor with drop support.
struct BoxedEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 180
    var monospaced = false
    var onDropText: ((String) -> Void)? = nil
    @State private var targeted = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(monospaced ? .system(size: 15, design: .monospaced) : Bauhaus.Typo.body)
                .scrollContentBackground(.hidden)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
                .padding(Bauhaus.Space.s)
            if text.isEmpty {
                Text(placeholder)
                    .font(Bauhaus.Typo.body)
                    .foregroundStyle(Bauhaus.Palette.inkDisabled)
                    .padding(Bauhaus.Space.m - 2)
                    .allowsHitTesting(false)
            }
        }
        .frame(minHeight: minHeight)
        .background(targeted ? Bauhaus.Palette.groundSoft : Bauhaus.Palette.ground)
        .overlay(Rectangle().stroke(targeted ? Bauhaus.Palette.blue : Bauhaus.Palette.ink, lineWidth: targeted ? Bauhaus.Rule.thick : Bauhaus.Rule.regular))
        .dropDestination(for: String.self) { items, _ in
            guard let t = items.first else { return false }
            if let onDropText { onDropText(t) } else { text = t }
            return true
        } isTargeted: { targeted = $0 }
    }
}

/// Read-only output box that can be selected, dragged out and copied.
struct OutputBox: View {
    let text: String
    var placeholder: String
    var minHeight: CGFloat = 180
    var monospaced = false

    var body: some View {
        ScrollView {
            Text(text.isEmpty ? placeholder : text)
                .font(monospaced ? .system(size: 15, design: .monospaced) : Bauhaus.Typo.body)
                .foregroundStyle(text.isEmpty ? Bauhaus.Palette.inkDisabled : Bauhaus.Palette.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Bauhaus.Space.m - 2)
        }
        .frame(minHeight: minHeight, maxHeight: 520)
        .background(Bauhaus.Palette.groundSoft)
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
        .draggable(text)
    }
}

/// A plain text or CSV file for the exporter.
struct TextFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = configuration.file.regularFileContents.flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

// MARK: - Batch

struct BatchView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore
    var wide: Bool
    @State private var exporting = false
    @State private var importing = false

    private var modeBinding: Binding<BatchMode> {
        Binding(get: { model.batchOptions.mode }, set: { m in
            if m != .lines, !store.isPro { model.showingPaywall = true } else { model.batchOptions.mode = m }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Source") {
                    if !store.isPro { Text("PRO").font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.redInk) }
                }
                Segmented(options: [(BatchMode.lines, "Lines"), (BatchMode.fileNames, "File names"), (BatchMode.csvColumn, "CSV column")],
                          selection: modeBinding, identifierPrefix: "batch")
                if model.batchOptions.mode == .csvColumn { csvOptions }
            }
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Convert with")
                Segmented(options: [(false, "Style guide"), (true, "Text tool")], selection: $model.batchUseTool, identifierPrefix: "batch-with")
                if model.batchUseTool {
                    ToolGrid(model: model, store: store)
                } else {
                    GuidePicker(model: model, store: store)
                }
            }
            if wide {
                HStack(alignment: .top, spacing: Bauhaus.Space.l) {
                    inputColumn.frame(maxWidth: .infinity)
                    outputColumn.frame(maxWidth: .infinity)
                }
            } else {
                inputColumn
                outputColumn
            }
        }
        .fileExporter(isPresented: $exporting, document: TextFileDocument(text: model.batchOutput),
                      contentType: model.batchOptions.mode == .csvColumn ? .commaSeparatedText : .plainText,
                      defaultFilename: model.batchOptions.mode == .csvColumn ? "Converted.csv" : "Converted.txt") { _ in }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .commaSeparatedText, .text]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                if url.pathExtension.lowercased() == "csv", store.isPro { model.batchOptions.mode = .csvColumn }
                model.batchInput = s
            }
        }
    }

    private var csvOptions: some View {
        let columns = BatchConverter.csvColumns(model.batchInput)
        return HStack(spacing: Bauhaus.Space.m) {
            Picker("Column", selection: $model.batchOptions.csvColumn) {
                ForEach(Array(columns.enumerated()), id: \.offset) { i, name in Text(name).tag(i) }
                if columns.isEmpty { Text("Column 1").tag(0) }
            }
            .pickerStyle(.menu)
            .font(Bauhaus.Typo.body)
            Checkbox(label: "First row is a header", isOn: $model.batchOptions.csvHasHeader)
        }
    }

    private var inputColumn: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Input") {
                Text("\(model.batchLineCount) LINES").font(Bauhaus.Typo.section).tracking(1)
            }
            BoxedEditor(text: $model.batchInput, placeholder: placeholder, minHeight: wide ? 320 : 200,
                        monospaced: model.batchOptions.mode != .lines)
                .accessibilityIdentifier("batch-input")
            HStack(spacing: Bauhaus.Space.s) {
                TagButton(title: "Paste", systemImage: "doc.on.clipboard") { if let s = Platform.clipboardString() { model.batchInput = s } }
                TagButton(title: "Open file", systemImage: "folder") { importing = true }
                if !model.batchInput.isEmpty { TagButton(title: "Clear", systemImage: "xmark") { model.batchInput = "" } }
                Spacer(minLength: 0)
            }
        }
    }

    private var outputColumn: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Output")
            OutputBox(text: model.batchOutput, placeholder: "Converted lines appear here", minHeight: wide ? 320 : 200,
                      monospaced: model.batchOptions.mode != .lines)
                .accessibilityIdentifier("batch-output")
            if model.batchIsTruncated {
                HStack(spacing: Bauhaus.Space.s) {
                    Image(systemName: "lock").foregroundStyle(Bauhaus.Palette.redInk)
                    Text("Free preview converts the first \(EditorModel.freeBatchPreviewLines) lines. Pro converts every line, file names and CSV columns.")
                        .font(Bauhaus.Typo.caption).fixedSize(horizontal: false, vertical: true)
                }
                TagButton(title: "Unlock batch", systemImage: "lock.open", filled: true) { model.showingPaywall = true }
            }
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "Copy all", systemImage: "doc.on.doc", kind: .action) {
                    Platform.copyToClipboard(model.batchOutput)
                    model.show("Copied")
                }
                .disabled(model.batchOutput.isEmpty)
                BarButton(title: "Save file", systemImage: "square.and.arrow.down", kind: .secondary) { exporting = true }
                    .disabled(model.batchOutput.isEmpty || !store.isPro)
            }
        }
    }

    private var placeholder: String {
        switch model.batchOptions.mode {
        case .lines: return "One title or heading per line"
        case .fileNames: return "my_vacation-photos_2024.jpg\nquarterly-report_final.pdf"
        case .csvColumn: return "title,author\n\"the old man and the sea\",Hemingway"
        }
    }
}

// MARK: - Text tools

struct ToolGrid: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 0)], spacing: 0) {
            ForEach(TextTool.allCases) { t in
                let selected = t == model.tool
                let locked = !store.isUnlocked(t)
                Button { model.choose(t) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: t.systemImage).font(.system(size: 13, weight: .semibold))
                        Text(t.displayName).font(Bauhaus.Typo.font(14, weight: .semibold, relativeTo: .footnote)).lineLimit(1).minimumScaleFactor(0.7)
                        if locked { Image(systemName: "lock.fill").font(.system(size: 10, weight: .bold)) }
                    }
                    .foregroundStyle(selected ? Bauhaus.Palette.ground : (locked ? Bauhaus.Palette.inkSecondary : Bauhaus.Palette.ink))
                    .frame(maxWidth: .infinity, minHeight: Bauhaus.tapTarget)
                    .padding(.horizontal, 4)
                    .background(selected ? Bauhaus.Palette.blue : Bauhaus.Palette.ground)
                    .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.thin))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerHover()
                .accessibilityLabel(t.displayName + (locked ? ", Pro" : ""))
                .accessibilityIdentifier("tool-\(t.rawValue)")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .overlay(Rectangle().stroke(Bauhaus.Palette.ink, lineWidth: Bauhaus.Rule.regular))
    }
}

struct ToolsView: View {
    @ObservedObject var model: EditorModel
    @ObservedObject var store: ProStore
    var wide: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.l) {
            VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
                SectionTitle("Tool") {
                    if !store.isPro { Text("5 FREE | 8 PRO").font(Bauhaus.Typo.section).tracking(1).foregroundStyle(Bauhaus.Palette.redInk) }
                }
                ToolGrid(model: model, store: store)
            }
            if wide {
                HStack(alignment: .top, spacing: Bauhaus.Space.l) {
                    input.frame(maxWidth: .infinity)
                    output.frame(maxWidth: .infinity)
                }
            } else {
                input
                output
            }
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle("Text")
            BoxedEditor(text: $model.toolsInput, placeholder: "Paste or type any text", minHeight: wide ? 300 : 160)
                .accessibilityIdentifier("tools-input")
            HStack(spacing: Bauhaus.Space.s) {
                TagButton(title: "Paste", systemImage: "doc.on.clipboard") { if let s = Platform.clipboardString() { model.toolsInput = s } }
                if !model.toolsInput.isEmpty { TagButton(title: "Clear", systemImage: "xmark") { model.toolsInput = "" } }
                Spacer(minLength: 0)
            }
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: Bauhaus.Space.s) {
            SectionTitle(model.tool.displayName)
            OutputBox(text: model.toolOutput, placeholder: "The result appears here", minHeight: wide ? 300 : 160,
                      monospaced: [.camel, .pascal, .snake, .kebab, .slug].contains(model.tool))
                .accessibilityIdentifier("tools-output")
            HStack(spacing: Bauhaus.Space.s) {
                BarButton(title: "Copy", systemImage: "doc.on.doc", kind: .action) {
                    Platform.copyToClipboard(model.toolOutput)
                    model.show("Copied")
                }
                .disabled(model.toolOutput.isEmpty)
                BarButton(title: "Use as input", systemImage: "arrow.uturn.up", kind: .secondary) { model.toolsInput = model.toolOutput }
                    .disabled(model.toolOutput.isEmpty || model.toolOutput == model.toolsInput)
            }
        }
    }
}
