//
//  DocxReader.swift
//  Title Capitalizr
//
//  Reads a Word .docx (also what Google Docs exports) into a SourceDocument:
//  paragraphs with their style hints, italic / bold / underline runs, page breaks
//  and footnotes / endnotes. Deleted revisions, field codes, text boxes and
//  compatibility fallbacks are skipped so text is never duplicated.
//

import Foundation

enum DocxReaderError: LocalizedError {
    case notADocx
    case missingDocument

    var errorDescription: String? {
        switch self {
        case .notADocx: return "This file isn't a Word document (.docx). If it's an old .doc file, save it as .docx first."
        case .missingDocument: return "This Word file has no document body."
        }
    }
}

enum DocxReader {
    static func read(data: Data, fileName: String = "Essay", kind: SourceKind = .docx) throws -> SourceDocument {
        let zip: ZipArchive
        do { zip = try ZipArchive(data: data) } catch { throw DocxReaderError.notADocx }
        guard zip.contains("word/document.xml") else { throw DocxReaderError.missingDocument }

        var styleNames: [String: String] = [:]
        if let styles = try? zip.data(for: "word/styles.xml") {
            styleNames = StyleNameParser.parse(styles)
        }

        let body = BodyParser(styleNames: styleNames, mode: .body)
        body.parse(try zip.data(for: "word/document.xml"))

        var footnotes: [Int: [TextRun]] = [:]
        if let fdata = try? zip.data(for: "word/footnotes.xml") {
            let p = BodyParser(styleNames: styleNames, mode: .notes(element: "footnote"))
            p.parse(fdata)
            footnotes.merge(p.notes) { a, _ in a }
        }
        if let edata = try? zip.data(for: "word/endnotes.xml") {
            let p = BodyParser(styleNames: styleNames, mode: .notes(element: "endnote"))
            p.parse(edata)
            for (k, v) in p.notes { footnotes[k + BodyParser.endnoteOffset] = v }
        }

        var notes: [String] = []
        if body.skippedTextBoxes { notes.append("Text boxes were skipped.") }
        if body.sawImages { notes.append("Images were left out of the formatted essay.") }
        return SourceDocument(paragraphs: body.paragraphs, footnotes: footnotes, kind: kind, fileName: fileName, notes: notes)
    }
}

/// Maps style ids to their lower-cased names ("Heading1" -> "heading 1").
private final class StyleNameParser: NSObject, XMLParserDelegate {
    private var names: [String: String] = [:]
    private var currentID: String?

    static func parse(_ data: Data) -> [String: String] {
        let p = StyleNameParser()
        let x = XMLParser(data: data)
        x.delegate = p
        x.parse()
        return p.names
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = localName(elementName)
        let attrs = localAttributes(attributes)
        if name == "style" { currentID = attrs["styleId"] }
        if name == "name", let id = currentID, let v = attrs["val"] { names[id] = v.lowercased() }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if localName(elementName) == "style" { currentID = nil }
    }
}

private func localName(_ qualified: String) -> String {
    if let i = qualified.lastIndex(of: ":") { return String(qualified[qualified.index(after: i)...]) }
    return qualified
}

private func localAttributes(_ attrs: [String: String]) -> [String: String] {
    var out: [String: String] = [:]
    for (k, v) in attrs { out[localName(k)] = v }
    return out
}

private func isOn(_ attrs: [String: String]) -> Bool {
    guard let v = attrs["val"]?.lowercased() else { return true }
    return !(v == "0" || v == "false" || v == "off" || v == "none")
}

private final class BodyParser: NSObject, XMLParserDelegate {
    enum Mode: Equatable { case body, notes(element: String) }
    static let endnoteOffset = 10_000

    let styleNames: [String: String]
    let mode: Mode

    private(set) var paragraphs: [SourceParagraph] = []
    private(set) var notes: [Int: [TextRun]] = [:]
    private(set) var skippedTextBoxes = false
    private(set) var sawImages = false

    // Paragraph state
    private var inParagraph = false
    private var runs: [TextRun] = []
    private var styleID: String?
    private var centered = false
    private var leftIndentTwips = 0
    private var hasNumbering = false
    private var pendingPageBreak = false
    private var inPPr = false

    // Run state
    private var inRun = false
    private var inRPr = false
    private var runItalic = false, runBold = false, runUnderline = false
    private var isFootnoteMarkRun = false
    private var paragraphMarkItalic = false

    // Text capture
    private var capturing = false
    private var buffer = ""

    // Skip regions
    private var skipDepth = 0
    private var skipElements: [String] = []

    // Notes
    private var currentNoteID: Int?
    private var currentNoteSkipped = false
    private var noteRuns: [TextRun] = []

    init(styleNames: [String: String], mode: Mode) {
        self.styleNames = styleNames
        self.mode = mode
    }

    func parse(_ data: Data) {
        let x = XMLParser(data: data)
        x.delegate = self
        x.parse()
    }

    private var noteElement: String? {
        if case .notes(let e) = mode { return e }
        return nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        let name = localName(elementName)
        let attrs = localAttributes(attributes)

        if skipDepth > 0 {
            if skipElements.last == name { skipDepth += 1 }
            return
        }
        switch name {
        case "del", "instrText", "delText", "Fallback", "txbxContent":
            if name == "txbxContent" { skippedTextBoxes = true }
            skipElements.append(name)
            skipDepth = 1
            return
        case "drawing", "pict":
            sawImages = true
        default: break
        }

        if let ne = noteElement, name == ne {
            let type = attrs["type"] ?? "normal"
            currentNoteID = Int(attrs["id"] ?? "")
            currentNoteSkipped = type == "separator" || type == "continuationSeparator" || type == "continuationNotice"
            noteRuns = []
            return
        }

        switch name {
        case "p":
            inParagraph = true
            runs = []
            styleID = nil
            centered = false
            leftIndentTwips = 0
            hasNumbering = false
        case "pPr":
            inPPr = true
        case "pStyle":
            if inPPr { styleID = attrs["val"] }
        case "jc":
            if inPPr, !inRPr { centered = attrs["val"] == "center" }
        case "ind":
            if inPPr, !inRPr {
                let left = Int(attrs["left"] ?? attrs["start"] ?? "0") ?? 0
                let hanging = Int(attrs["hanging"] ?? "0") ?? 0
                // A hanging indent (Works Cited) starts its first line at the margin: not a block quote.
                leftIndentTwips = hanging > 0 ? 0 : left
            }
        case "numPr":
            if inPPr { hasNumbering = true }
        case "pageBreakBefore":
            if inPPr, isOn(attrs) { pendingPageBreak = true }
        case "r":
            inRun = true
            runItalic = false; runBold = false; runUnderline = false
            isFootnoteMarkRun = false
        case "rPr":
            inRPr = true
        case "i":
            if inRPr { if inRun { runItalic = isOn(attrs) } else { paragraphMarkItalic = isOn(attrs) } }
        case "b":
            if inRPr, inRun { runBold = isOn(attrs) }
        case "u":
            if inRPr, inRun { runUnderline = isOn(attrs) }
        case "rStyle":
            if inRPr, inRun, let v = attrs["val"] {
                let n = (styleNames[v] ?? v).lowercased()
                if n.contains("emphasis") || n.contains("italic") || n.contains("book title") { runItalic = true }
                if n.contains("strong") { runBold = true }
            }
        case "t":
            capturing = true
            buffer = ""
        case "tab":
            if inRun, !inPPr { append("\t") }
        case "br", "cr":
            if inRun {
                if attrs["type"] == "page" {
                    if noteElement == nil { finishParagraph(); pendingPageBreak = true; startContinuation() }
                } else if noteElement == nil {
                    // A soft line break inside a paragraph: split it so heading lines separate.
                    finishParagraph(); startContinuation()
                } else {
                    append(" ")
                }
            }
        case "noBreakHyphen":
            if inRun { append("-") }
        case "footnoteReference":
            if noteElement == nil, let id = Int(attrs["id"] ?? "") { runs.append(TextRun("", footnoteID: id)) }
        case "endnoteReference":
            if noteElement == nil, let id = Int(attrs["id"] ?? "") { runs.append(TextRun("", footnoteID: id + Self.endnoteOffset)) }
        case "footnoteRef", "endnoteRef":
            isFootnoteMarkRun = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if skipDepth == 0, capturing { buffer += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        if skipDepth > 0 {
            if skipElements.last == name {
                skipDepth -= 1
                if skipDepth == 0 { skipElements.removeLast() }
            }
            return
        }
        if let ne = noteElement, name == ne {
            if let id = currentNoteID, !currentNoteSkipped {
                notes[id] = noteRuns.trimmed()
            }
            currentNoteID = nil
            return
        }
        switch name {
        case "t":
            capturing = false
            if inRun, !isFootnoteMarkRun { append(buffer) }
            buffer = ""
        case "rPr":
            inRPr = false
        case "pPr":
            inPPr = false
        case "r":
            inRun = false
        case "p":
            finishParagraph()
            inParagraph = false
        default:
            break
        }
    }

    private func append(_ text: String) {
        guard !text.isEmpty else { return }
        runs.append(TextRun(text, italic: runItalic, bold: runBold, underline: runUnderline))
    }

    /// After a soft or page break the remaining runs belong to a new paragraph with the same properties.
    private func startContinuation() {
        runs = []
    }

    private func finishParagraph() {
        let finished = runs.coalesced()
        runs = []
        if noteElement != nil {
            if !noteRuns.isEmpty, !finished.isEmpty { noteRuns.append(TextRun(" ")) }
            noteRuns += finished
            return
        }
        var para = SourceParagraph(finished, hint: hint(), pageBreakBefore: pendingPageBreak)
        if para.isBlank {
            // Keep the break for the next real paragraph.
            return
        }
        pendingPageBreak = false
        if para.hint == .normal, centered { para.hint = .centered }
        paragraphs.append(para)
    }

    private func hint() -> ParagraphHint {
        let style = styleID.map { (styleNames[$0] ?? $0).lowercased() } ?? ""
        if style == "title" { return .title }
        if style == "subtitle" { return .subtitle }
        if style.hasPrefix("heading") {
            let digits = style.filter(\.isNumber)
            return .heading(Int(digits) ?? 1)
        }
        if style.contains("quote") { return .quote }
        if hasNumbering || style.contains("list") { return .listItem }
        if leftIndentTwips >= 600 { return .quote }
        return .normal
    }
}
