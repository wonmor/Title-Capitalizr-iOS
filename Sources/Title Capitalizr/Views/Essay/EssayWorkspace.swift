//
//  EssayWorkspace.swift
//  Title Capitalizr
//
//  State for the essay formatter: the imported source, the analysed structure, the
//  heading fields the user confirms, the chosen style, switched-off fixes, and the
//  rendered preview. Formatting is a pure function of this state.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class EssayWorkspace: ObservableObject {
    @Published private(set) var source: SourceDocument?
    @Published private(set) var structure: EssayStructure?
    @Published var heading = HeadingFields() { didSet { scheduleFormat() } }
    @Published var title = "" { didSet { scheduleFormat() } }
    @Published var style: EssayStyle = .mla9 { didSet { if oldValue != style { reformatDate(); scheduleFormat(immediate: true) } } }
    @Published var disabledFixes: Set<String> = [] { didSet { scheduleFormat(immediate: true) } }
    /// Fields the user has looked at and accepted.
    @Published var confirmed: Set<EssayStructure.Field> = []
    /// Fields filled from an Apple Intelligence suggestion and not yet confirmed.
    @Published private(set) var suggested: Set<EssayStructure.Field> = []
    @Published private(set) var referencesSuggestion: (index: Int, text: String)?

    @Published private(set) var output: EssayFormatter.Output?
    @Published private(set) var previewPDF: Data?
    @Published private(set) var pageCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isAsking = false
    @Published var errorMessage: String?

    private var formatTask: Task<Void, Never>?

    static let docxType = UTType(filenameExtension: "docx") ?? .data
    static let importTypes: [UTType] = [docxType, .pdf, .rtf, .plainText, .text]

    var hasDocument: Bool { structure != nil }

    /// Fields that still need the user's eye.
    var needsReview: [EssayStructure.Field] {
        guard let structure else { return [] }
        let fields: [EssayStructure.Field] = [.name, .instructor, .course, .date, .title, .references]
        return fields.filter { (structure.uncertain.contains($0) || suggested.contains($0)) && !confirmed.contains($0) }
    }

    // MARK: Import

    func load(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let doc = try EssayImporter.read(url: url)
            adopt(doc)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func load(data: Data, fileExtension: String, fileName: String) {
        do {
            adopt(try EssayImporter.read(data: data, fileExtension: fileExtension, fileName: fileName))
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func load(googleDocsLink link: String) {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let doc = try await GoogleDocsFetcher().fetch(link)
                adopt(doc)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    func loadSample() { adopt(SampleEssay.document) }

    func clear() {
        source = nil
        structure = nil
        output = nil
        previewPDF = nil
        pageCount = 0
        confirmed = []
        suggested = []
        referencesSuggestion = nil
        disabledFixes = []
    }

    func adopt(_ doc: SourceDocument) {
        errorMessage = nil
        source = doc
        let s = EssayAnalyzer.analyze(doc)
        structure = s
        confirmed = []
        suggested = []
        referencesSuggestion = nil
        disabledFixes = []
        heading = s.heading
        if heading.date.isEmpty {
            heading.date = DateParsing.format(DateParsing.today(), style: style)
        }
        title = s.title
        reformatDate()
        scheduleFormat(immediate: true)
    }

    // MARK: Review

    func confirm(_ field: EssayStructure.Field) {
        confirmed.insert(field)
        suggested.remove(field)
    }

    func edited(_ field: EssayStructure.Field) {
        confirmed.insert(field)
        suggested.remove(field)
    }

    /// Asks the on-device model to fill the fields the rules couldn't find.
    func askAppleIntelligence(availability: SmartModelAvailability) {
        guard let structure, let source else { return }
        isAsking = true
        Task {
            defer { isAsking = false }
            guard let s = await EssayAssistant.suggest(for: structure, source: source, availability: availability) else {
                errorMessage = "Apple Intelligence couldn't suggest anything for this essay."
                return
            }
            var newSuggested: Set<EssayStructure.Field> = []
            let candidates: [(EssayStructure.Field, String, WritableKeyPath<HeadingFields, String>)] = [
                (.name, s.heading.name, \.name), (.instructor, s.heading.instructor, \.instructor),
                (.course, s.heading.course, \.course), (.date, s.heading.date, \.date),
            ]
            for (field, value, path) in candidates where !value.isEmpty && structure.uncertain.contains(field) && !confirmed.contains(field) {
                heading[keyPath: path] = value
                newSuggested.insert(field)
            }
            if !s.title.isEmpty, structure.uncertain.contains(.title), !confirmed.contains(.title) {
                title = s.title
                newSuggested.insert(.title)
            }
            if structure.references.isEmpty, let i = s.referencesStartInBody, structure.body.indices.contains(i) {
                referencesSuggestion = (i, structure.body[i].text)
                newSuggested.insert(.references)
            }
            suggested = newSuggested
            reformatDate()
            if newSuggested.isEmpty { errorMessage = "Apple Intelligence found nothing to add. Fill in the fields above." }
        }
    }

    /// Moves body paragraphs from `index` on into the source list.
    func acceptReferencesSuggestion() {
        guard var s = structure, let suggestion = referencesSuggestion, s.body.indices.contains(suggestion.index) else { return }
        s.references = Array(s.body[suggestion.index...])
        s.body = Array(s.body[..<suggestion.index])
        s.uncertain.remove(.references)
        structure = s
        referencesSuggestion = nil
        confirm(.references)
        scheduleFormat(immediate: true)
    }

    // MARK: Formatting

    private func reformatDate() {
        if let d = DateParsing.parse(heading.date) {
            let f = DateParsing.format(d, style: style)
            if f != heading.date { heading.date = f }
        }
    }

    private func scheduleFormat(immediate: Bool = false) {
        guard let structure else { return }
        formatTask?.cancel()
        let input = EssayFormatter.Input(structure: structure, heading: heading, title: title, style: style, disabledFixes: disabledFixes)
        formatTask = Task { @MainActor in
            if !immediate {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
            }
            let out = EssayFormatter.format(input)
            let rendered = PDFEssayRenderer.render(out.essay)
            guard !Task.isCancelled else { return }
            output = out
            previewPDF = rendered.data
            pageCount = rendered.pageCount
        }
    }

    // MARK: Export

    func exportData(_ format: ExportFormat) -> Data? {
        guard let essay = output?.essay else { return nil }
        return format.data(for: essay)
    }

    func exportFileName(_ format: ExportFormat) -> String {
        guard let essay = output?.essay else { return "Essay.\(format.fileExtension)" }
        return ExportNaming.fileName(for: essay, format: format)
    }

    /// Writes the export to a fresh temporary folder and returns its URL (for share sheets and drags).
    func writeTemporaryFile(_ format: ExportFormat) -> URL? {
        guard let data = exportData(format) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(exportFileName(format))
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = "Couldn't prepare the file: \(error.localizedDescription)"
            return nil
        }
    }
}

/// A short original sample used by "Try a sample essay" (all sources invented).
enum SampleEssay {
    static var document: SourceDocument {
        func p(_ t: String, hint: ParagraphHint = .normal) -> SourceParagraph { SourceParagraph(text: t, hint: hint) }
        var first = SourceParagraph([TextRun("\tThe bicycle began as a wooden toy pushed along by the rider's feet. Within a few decades it became an everyday machine, and as Smith argues in "),
                                     TextRun("Two Wheels", italic: true),
                                     TextRun(", it changed how towns were planned (Smith, 12).")])
        first.hint = .normal
        return SourceDocument(paragraphs: [
            p("Jane Q. Doe"), p("Professor Alan Rivera"), p("ENGL 101"), p("October 30, 2026"),
            p("the long road: a short history of the bicycle", hint: .title),
            first,
            p("Pedals and cranks arrived later and changed everything. Riders could  finally travel without touching the ground, and \"the machine felt like flight.\" (Lopez 45)"),
            p("Some writers describe the chain drive as the decisive step (Okafor p. 7), while others credit smoother roads and cheaper steel."),
            p("Many towns built paths, and the bicycle became a symbol of independence for young people across the country. Today it is again a common sight in busy cities."),
            p("Works Cited", hint: .centered),
            SourceParagraph([TextRun("Smith, Henry. "), TextRun("Two Wheels: An Invented History", italic: true), TextRun(". Placeholder Press, 2001")]),
            SourceParagraph([TextRun("Lopez, Maria. \"Riding into Town.\" "), TextRun("Journal of Imaginary Transport", italic: true), TextRun(", vol. 3, no. 2, 2015, pp. 40-52. https://www.example.com/lopez.")]),
            SourceParagraph([TextRun("Okafor, Chidi. "), TextRun("Chains and Gears", italic: true), TextRun(". Sample House, 2010.")]),
        ], kind: .docx, fileName: "Sample essay")
    }
}
