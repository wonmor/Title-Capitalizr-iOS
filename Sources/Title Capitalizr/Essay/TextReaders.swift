//
//  TextReaders.swift
//  Title Capitalizr
//
//  Readers for PDF (PDFKit text extraction with line geometry), RTF (the system
//  attributed-string importer) and plain text, plus the dispatcher that picks a
//  reader from a file's extension or contents.
//

import Foundation
import PDFKit
#if os(macOS)
import AppKit
typealias PlatformFont = NSFont
#else
import UIKit
typealias PlatformFont = UIFont
#endif

enum EssayImportError: LocalizedError, Equatable {
    case unsupported(String)
    case empty
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let ext):
            if ext == "pages" {
                return "Pages files can't be read directly. In Pages choose File > Export To > Word, then drop the .docx here."
            }
            if ext == "doc" {
                return "Old Word .doc files can't be read. Open it in Word or Pages and save it as .docx."
            }
            return "Title Capitalizr reads Word (.docx), PDF, RTF and plain text files, plus Google Docs links. \".\(ext)\" isn't supported."
        case .empty:
            return "No text was found in this file. Scanned PDFs (pictures of pages) have no text to format."
        case .unreadable(let why):
            return why
        }
    }
}

enum EssayImporter {
    static let supportedExtensions = ["docx", "pdf", "rtf", "txt", "text", "md"]

    static func read(url: URL) throws -> SourceDocument {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent
        if ext == "pdf" {
            guard let doc = PDFDocument(url: url) else { throw EssayImportError.unreadable("This PDF couldn't be opened.") }
            return try PDFEssayReader.read(doc, fileName: name)
        }
        let data = try Data(contentsOf: url)
        return try read(data: data, fileExtension: ext, fileName: name)
    }

    static func read(data: Data, fileExtension ext: String, fileName: String) throws -> SourceDocument {
        let doc: SourceDocument
        switch ext.lowercased() {
        case "docx", "dotx":
            doc = try DocxReader.read(data: data, fileName: fileName)
        case "pdf":
            guard let pdf = PDFDocument(data: data) else { throw EssayImportError.unreadable("This PDF couldn't be opened.") }
            doc = try PDFEssayReader.read(pdf, fileName: fileName)
        case "rtf":
            doc = try RTFEssayReader.read(data: data, fileName: fileName)
        case "txt", "text", "md":
            doc = PlainTextReader.read(PlainTextReader.decode(data), fileName: fileName)
        default:
            // Sniff: a zip is probably a docx, "%PDF" a PDF, "{\rtf" RTF.
            if data.starts(with: [0x50, 0x4B]) { return try read(data: data, fileExtension: "docx", fileName: fileName) }
            if data.starts(with: Array("%PDF".utf8)) { return try read(data: data, fileExtension: "pdf", fileName: fileName) }
            if data.starts(with: Array("{\\rtf".utf8)) { return try read(data: data, fileExtension: "rtf", fileName: fileName) }
            throw EssayImportError.unsupported(ext.lowercased())
        }
        guard doc.paragraphs.contains(where: { !$0.isBlank }) else { throw EssayImportError.empty }
        return doc
    }
}

// MARK: - Plain text

enum PlainTextReader {
    static func decode(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        return String(data: data, encoding: .windowsCP1252) ?? String(decoding: data, as: UTF8.self)
    }

    /// Blank lines separate paragraphs when the text has any; otherwise every line is a paragraph.
    static func read(_ text: String, fileName: String = "Essay", kind: SourceKind = .txt) -> SourceDocument {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        let hasBlankSeparators = lines.contains { $0.trimmingCharacters(in: .whitespaces).isEmpty }
            && lines.filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }).count > 1
        var paragraphs: [SourceParagraph] = []
        var current: [String] = []
        var pendingBreak = false
        func flush() {
            let joined = current.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
            if !joined.isEmpty {
                paragraphs.append(SourceParagraph([TextRun(joined)], pageBreakBefore: pendingBreak))
                pendingBreak = false
            }
            current = []
        }
        // A short line in a block of short lines (the MLA heading) still needs its own paragraph.
        for line in lines {
            if line.contains("\u{0C}") { flush(); pendingBreak = true }
            let clean = line.replacingOccurrences(of: "\u{0C}", with: "")
            if !hasBlankSeparators {
                current = [clean]; flush(); continue
            }
            if clean.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }
            // An indented line starts a new paragraph even without a blank line.
            if let first = clean.first, first == "\t" || clean.hasPrefix("    "), !current.isEmpty { flush() }
            current.append(clean)
        }
        flush()
        return SourceDocument(paragraphs: paragraphs, kind: kind, fileName: fileName)
    }
}

// MARK: - RTF

enum RTFEssayReader {
    static func read(data: Data, fileName: String) throws -> SourceDocument {
        let attributed: NSAttributedString
        do {
            attributed = try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        } catch {
            throw EssayImportError.unreadable("This RTF file couldn't be read.")
        }
        return read(attributed, fileName: fileName, kind: .rtf)
    }

    static func read(_ attributed: NSAttributedString, fileName: String, kind: SourceKind) -> SourceDocument {
        let ns = attributed.string as NSString
        var paragraphs: [SourceParagraph] = []
        var location = 0
        var pendingBreak = false
        while location < ns.length {
            let range = ns.paragraphRange(for: NSRange(location: location, length: 0))
            location = NSMaxRange(range)
            var runs: [TextRun] = []
            var centered = false
            var indented = false
            attributed.enumerateAttributes(in: range) { attrs, r, _ in
                var text = ns.substring(with: r)
                if text.contains("\u{0C}") { pendingBreak = true; text = text.replacingOccurrences(of: "\u{0C}", with: "") }
                text = text.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\u{2029}", with: "")
                let font = attrs[.font] as? PlatformFont
                let (italic, bold) = traits(of: font)
                let underline = ((attrs[.underlineStyle] as? Int) ?? 0) != 0
                runs.append(TextRun(text, italic: italic, bold: bold, underline: underline))
                if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
                    if ps.alignment == .center { centered = true }
                    if ps.headIndent >= 30, ps.firstLineHeadIndent >= 30 { indented = true }
                }
            }
            let para = SourceParagraph(runs.coalesced(), hint: centered ? .centered : (indented ? .quote : .normal), pageBreakBefore: pendingBreak)
            if !para.isBlank {
                paragraphs.append(para)
                pendingBreak = false
            }
        }
        return SourceDocument(paragraphs: paragraphs, kind: kind, fileName: fileName)
    }

    static func traits(of font: PlatformFont?) -> (italic: Bool, bold: Bool) {
        guard let font else { return (false, false) }
        #if os(macOS)
        let t = font.fontDescriptor.symbolicTraits
        return (t.contains(.italic), t.contains(.bold))
        #else
        let t = font.fontDescriptor.symbolicTraits
        return (t.contains(.traitItalic), t.contains(.traitBold))
        #endif
    }
}

// MARK: - PDF

/// Rebuilds paragraphs from a PDF's text lines. PDFs carry no paragraph structure, so this
/// uses line geometry: first-line indents, vertical gaps and short closing lines start a new
/// paragraph; running headers and page numbers in the margins are dropped; words hyphenated
/// across lines are re-joined. Works Cited entries use hanging indents, so after a Works
/// Cited heading a line at the margin starts a new entry instead.
enum PDFEssayReader {
    struct Line {
        var text: String
        var runs: [TextRun]
        var minX: Double
        var maxX: Double
        var top: Double      // distance from the top of the page
        var height: Double
        var page: Int
        var pageWidth: Double
    }

    static func read(_ pdf: PDFDocument, fileName: String) throws -> SourceDocument {
        var lines: [Line] = []
        for i in 0..<pdf.pageCount {
            guard let page = pdf.page(at: i) else { continue }
            let box = page.bounds(for: .mediaBox)
            guard let selection = page.selection(for: box) else { continue }
            for lineSel in selection.selectionsByLine() {
                let raw = (lineSel.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let r = lineSel.bounds(for: page)
                var runs: [TextRun] = []
                if let attr = lineSel.attributedString {
                    attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
                        let t = (attr.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: "")
                        let name = (value as? PlatformFont)?.fontName.lowercased() ?? ""
                        let italic = name.contains("italic") || name.contains("oblique")
                        let bold = name.contains("bold")
                        runs.append(TextRun(t, italic: italic, bold: bold))
                    }
                }
                runs = runs.trimmed()
                if runs.plainText.isEmpty { runs = [TextRun(raw)] }
                lines.append(Line(text: raw, runs: runs, minX: Double(r.minX - box.minX), maxX: Double(r.maxX - box.minX),
                                  top: Double(box.maxY - r.maxY), height: Double(r.height), page: i, pageWidth: Double(box.width)))
            }
        }
        let paragraphs = assemble(lines, pageHeights: (0..<pdf.pageCount).map { Double(pdf.page(at: $0)?.bounds(for: .mediaBox).height ?? 792) })
        guard !paragraphs.isEmpty else { throw EssayImportError.empty }
        return SourceDocument(paragraphs: paragraphs, kind: .pdf, fileName: fileName,
                              notes: ["PDF text is rebuilt from line positions. Check paragraph breaks in the preview."])
    }

    static func isMarginFurniture(_ line: Line, pageHeight: Double) -> Bool {
        let inTop = line.top < 54
        let inBottom = line.top > pageHeight - 54
        guard inTop || inBottom else { return false }
        let words = line.text.split(separator: " ")
        let hasNumber = line.text.contains { $0.isNumber }
        return words.count <= 6 && (hasNumber || inBottom)
    }

    static func assemble(_ all: [Line], pageHeights: [Double]) -> [SourceParagraph] {
        let lines = all.filter { !isMarginFurniture($0, pageHeight: pageHeights[safe: $0.page] ?? 792) }
        guard !lines.isEmpty else { return [] }
        // Left margin: the most common rounded minX.
        var counts: [Int: Int] = [:]
        for l in lines { counts[Int((l.minX / 4).rounded()), default: 0] += 1 }
        let margin = Double((counts.max { $0.value < $1.value }?.key ?? 18) * 4)
        let rightEdge = lines.map(\.maxX).sorted()[Int(Double(lines.count - 1) * 0.9)]
        let textWidth = max(rightEdge - margin, 100)
        // Typical line advance within a page.
        var gaps: [Double] = []
        for (a, b) in zip(lines, lines.dropFirst()) where a.page == b.page {
            let g = b.top - a.top
            if g > 0 { gaps.append(g) }
        }
        let typicalGap = gaps.sorted()[safe: gaps.count / 2] ?? 24

        var out: [SourceParagraph] = []
        var current: [Line] = []
        var inReferences = false

        func flush() {
            guard !current.isEmpty else { return }
            var runs: [TextRun] = []
            for line in current {
                if var last = runs.last, last.footnoteID == nil {
                    if last.text.hasSuffix("-"), last.text.dropLast().last?.isLetter == true,
                       line.text.first?.isLowercase == true {
                        last.text.removeLast()
                        runs[runs.count - 1] = last
                    } else {
                        runs.append(TextRun(" "))
                    }
                }
                runs += line.runs
            }
            let first = current[0]
            let center = (first.minX + first.maxX) / 2
            let pageCenter = first.pageWidth / 2
            let isCentered = current.count == 1 && first.minX > margin + 24 && abs(center - pageCenter) < 14
            var para = SourceParagraph(runs.coalesced(), hint: isCentered ? .centered : .normal)
            if !inReferences, current.allSatisfy({ $0.minX > margin + 30 && $0.maxX < rightEdge - 20 }), current.count > 1 { para.hint = .quote }
            out.append(para)
            if ReferenceDetector.isReferencesHeading(para.text) { inReferences = true }
            current = []
        }

        for line in lines {
            guard let prev = current.last else { current = [line]; continue }
            let indented = line.minX > margin + 12
            let samePage = line.page == prev.page
            let gap = samePage ? line.top - prev.top : typicalGap
            let bigGap = samePage && gap > typicalGap * 1.45
            let prevShort = prev.maxX < margin + textWidth * 0.8
            let prevEndsSentence = prev.text.last.map { ".?!:\"”)".contains($0) } ?? false
            let prevCentered = abs((prev.minX + prev.maxX) / 2 - prev.pageWidth / 2) < 14 && prev.minX > margin + 24
            var startsNew: Bool
            if inReferences || ReferenceDetector.isReferencesHeading(prev.text) {
                inReferences = true
                startsNew = !indented || bigGap
            } else {
                startsNew = indented || bigGap || (prevShort && (prevEndsSentence || current.count == 1 && prev.text.count < 60)) || prevCentered
            }
            if startsNew { flush() }
            current.append(line)
        }
        flush()
        return out
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
