//
//  EssayExporters.swift
//  Title Capitalizr
//
//  PDF (CoreText, US Letter, Word-equivalent line metrics so pages break where Word
//  breaks them), RTF (hand-written so it carries the running header, page breaks and
//  footnotes) and plain text, plus file naming for every export format.
//

import Foundation
import CoreText
import CoreGraphics

enum ExportFormat: String, CaseIterable, Identifiable {
    case docx, pdf, rtf, txt
    var id: Self { self }

    var fileExtension: String { rawValue }

    var label: String {
        switch self {
        case .docx: return "Word"
        case .pdf: return "PDF"
        case .rtf: return "RTF"
        case .txt: return "Text"
        }
    }

    var mimeType: String {
        switch self {
        case .docx: return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case .pdf: return "application/pdf"
        case .rtf: return "application/rtf"
        case .txt: return "text/plain"
        }
    }

    func data(for essay: FormattedEssay) -> Data {
        switch self {
        case .docx: return DocxWriter.write(essay)
        case .pdf: return PDFEssayRenderer.render(essay).data
        case .rtf: return RTFEssayWriter.write(essay)
        case .txt: return Data(PlainTextEssayWriter.write(essay).utf8)
        }
    }
}

enum ExportNaming {
    /// "Seong_The-Lord-of-the-Rings_MLA.docx"
    static func fileName(for essay: FormattedEssay, format: ExportFormat) -> String {
        fileName(lastName: essay.heading.lastName, title: essay.title, style: essay.style, ext: format.fileExtension)
    }

    static func fileName(lastName: String, title: String, style: EssayStyle, ext: String) -> String {
        func clean(_ s: String) -> String {
            let folded = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            let words = folded.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
            return words.prefix(10).joined(separator: "-")
        }
        let styleTag: String
        switch style {
        case .mla9: styleTag = "MLA"
        case .apa7: styleTag = "APA"
        case .chicagoNotes: styleTag = "Chicago"
        case .chicagoAuthorDate: styleTag = "Chicago-AD"
        }
        let parts = [clean(lastName), clean(title).isEmpty ? "Essay" : clean(title), styleTag].filter { !$0.isEmpty }
        var base = parts.joined(separator: "_")
        if base.count > 80 { base = String(base.prefix(80)) }
        return base + "." + ext
    }
}

// MARK: - PDF

enum PDFEssayRenderer {
    static let pageSize = CGSize(width: 612, height: 792)
    static let margin: CGFloat = 72
    /// Word's "single" for Times New Roman 12 is about 13.8 pt (1.15 em); double is twice that.
    static let singleLine: CGFloat = 13.8

    struct Result {
        let data: Data
        let pageCount: Int
    }

    static func render(_ essay: FormattedEssay, maxPages: Int? = nil) -> Result {
        let flows = segments(for: essay)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Result(data: Data(), pageCount: 0) }
        var box = CGRect(origin: .zero, size: pageSize)
        let info: [CFString: Any] = [kCGPDFContextTitle: essay.title, kCGPDFContextCreator: "Title Capitalizr", kCGPDFContextAuthor: essay.heading.name]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Result(data: Data(), pageCount: 0) }
        var page = 0
        let textRect = CGRect(x: margin, y: margin, width: pageSize.width - 2 * margin, height: pageSize.height - 2 * margin)
        outer: for flow in flows where flow.length > 0 {
            let framesetter = CTFramesetterCreateWithAttributedString(flow)
            var start = 0
            while start < flow.length {
                if let maxPages, page >= maxPages { break outer }
                page += 1
                ctx.beginPDFPage(nil)
                ctx.textMatrix = .identity
                drawHeader(essay, page: page, in: ctx)
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), CGPath(rect: textRect, transform: nil), nil)
                CTFrameDraw(frame, ctx)
                ctx.endPDFPage()
                let visible = CTFrameGetVisibleStringRange(frame)
                if visible.length == 0 { break }
                start += visible.length
            }
        }
        ctx.closePDF()
        return Result(data: data as Data, pageCount: page)
    }

    static func drawHeader(_ essay: FormattedEssay, page: Int, in ctx: CGContext) {
        if page == 1 && !essay.headerOnFirstPage { return }
        let text: String
        switch essay.header {
        case .lastNameAndPage(let name): text = "\(name) \(page)"
        case .pageNumber: text = "\(page)"
        }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font(bold: false, italic: false)]))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        // Header 0.5 inch from the top edge, right-aligned to the 1 inch margin.
        ctx.textPosition = CGPoint(x: pageSize.width - margin - CGFloat(width), y: pageSize.height - 36 - 11)
        CTLineDraw(line, ctx)
    }

    static func font(bold: Bool, italic: Bool, size: CGFloat = 12) -> CTFont {
        let name: String
        switch (bold, italic) {
        case (true, true): name = "TimesNewRomanPS-BoldItalicMT"
        case (true, false): name = "TimesNewRomanPS-BoldMT"
        case (false, true): name = "TimesNewRomanPS-ItalicMT"
        default: name = "TimesNewRomanPSMT"
        }
        return CTFontCreateWithName(name as CFString, size, nil)
    }

    /// Splits the essay into flows that each start on a new page; footnotes become a Notes page.
    static func segments(for essay: FormattedEssay) -> [NSAttributedString] {
        var paragraphs = essay.paragraphs
        if !essay.footnotes.isEmpty {
            var notes: [LayoutParagraph] = []
            var h = LayoutParagraph(runs: [TextRun("Notes")], role: .referencesHeading, alignment: .center)
            h.pageBreakBefore = true
            notes.append(h)
            let single = essay.style == .chicagoNotes || essay.style == .chicagoAuthorDate
            for id in essay.footnotes.keys.sorted() {
                notes.append(LayoutParagraph(runs: [TextRun("\(id). ")] + (essay.footnotes[id] ?? []), role: .note, firstLineIndent: 0.5,
                                             lineSpacing: single ? 1.0 : 2.0, spaceAfter: single ? 12 : 0))
            }
            let insertAt = paragraphs.firstIndex { $0.role == .referencesHeading && $0.text != "Notes" } ?? paragraphs.count
            paragraphs.insert(contentsOf: notes, at: insertAt)
        }
        var flows: [NSMutableAttributedString] = [NSMutableAttributedString()]
        for p in paragraphs {
            if p.pageBreakBefore, flows.last!.length > 0 { flows.append(NSMutableAttributedString()) }
            flows[flows.count - 1].append(attributed(p))
        }
        return flows
    }

    static func attributed(_ p: LayoutParagraph) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let fontKey = kCTFontAttributeName as NSAttributedString.Key
        for r in p.runs {
            if let id = r.footnoteID {
                out.append(NSAttributedString(string: "\(id)", attributes: [fontKey: font(bold: false, italic: false, size: 8),
                                                                           kCTSuperscriptAttributeName as NSAttributedString.Key: 1]))
                continue
            }
            var attrs: [NSAttributedString.Key: Any] = [fontKey: font(bold: r.bold, italic: r.italic)]
            if r.underline { attrs[kCTUnderlineStyleAttributeName as NSAttributedString.Key] = CTUnderlineStyle.single.rawValue }
            out.append(NSAttributedString(string: r.text.replacingOccurrences(of: "\n", with: "\u{2028}"), attributes: attrs))
        }
        out.append(NSAttributedString(string: "\n", attributes: [fontKey: font(bold: false, italic: false)]))
        out.addAttribute(kCTParagraphStyleAttributeName as NSAttributedString.Key, value: paragraphStyle(p), range: NSRange(location: 0, length: out.length))
        return out
    }

    static func paragraphStyle(_ p: LayoutParagraph) -> CTParagraphStyle {
        var alignment: CTTextAlignment = {
            switch p.alignment {
            case .left: return .left
            case .center: return .center
            case .right: return .right
            }
        }()
        let left = CGFloat(p.leftIndent * 72)
        var head = left
        var first = p.hangingIndent > 0 ? left - CGFloat(p.hangingIndent * 72) : left + CGFloat(p.firstLineIndent * 72)
        var lineHeight = singleLine * CGFloat(p.lineSpacing)
        var after = CGFloat(p.spaceAfter)
        return withUnsafeBytes(of: &alignment) { a in
            withUnsafeBytes(of: &head) { h in
                withUnsafeBytes(of: &first) { f in
                    withUnsafeBytes(of: &lineHeight) { lh in
                        withUnsafeBytes(of: &after) { af in
                            let settings = [
                                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a.baseAddress!),
                                CTParagraphStyleSetting(spec: .headIndent, valueSize: MemoryLayout<CGFloat>.size, value: h.baseAddress!),
                                CTParagraphStyleSetting(spec: .firstLineHeadIndent, valueSize: MemoryLayout<CGFloat>.size, value: f.baseAddress!),
                                CTParagraphStyleSetting(spec: .minimumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: lh.baseAddress!),
                                CTParagraphStyleSetting(spec: .maximumLineHeight, valueSize: MemoryLayout<CGFloat>.size, value: lh.baseAddress!),
                                CTParagraphStyleSetting(spec: .paragraphSpacing, valueSize: MemoryLayout<CGFloat>.size, value: af.baseAddress!),
                            ]
                            return CTParagraphStyleCreate(settings, settings.count)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - RTF

enum RTFEssayWriter {
    static func write(_ essay: FormattedEssay) -> Data {
        var rtf = #"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\froman\fcharset0 Times New Roman;}}"#
        rtf += "\n" + #"\paperw12240\paperh15840\margl1440\margr1440\margt1440\margb1440\headery720"#
        if !essay.headerOnFirstPage { rtf += #"\titlepg"# }
        rtf += #"\f0\fs24"# + "\n"
        let headerText: String
        switch essay.header {
        case .lastNameAndPage(let name): headerText = escape(name) + " "
        case .pageNumber: headerText = ""
        }
        rtf += #"{\header\pard\qr\sl240\slmult1\f0\fs24 "# + headerText + #"\chpgn\par}"# + "\n"
        if !essay.headerOnFirstPage { rtf += #"{\headerf\pard\par}"# + "\n" }
        for p in essay.paragraphs {
            rtf += #"\pard\plain\f0\fs24"#
            if p.pageBreakBefore { rtf += #"\pagebb"# }
            switch p.alignment {
            case .left: rtf += #"\ql"#
            case .center: rtf += #"\qc"#
            case .right: rtf += #"\qr"#
            }
            rtf += #"\sl\#(Int(p.lineSpacing * 240))\slmult1\sa\#(Int(p.spaceAfter * 20))"#
            let li = DocxWriter.twips(p.leftIndent)
            let fi = p.hangingIndent > 0 ? -DocxWriter.twips(p.hangingIndent) : DocxWriter.twips(p.firstLineIndent)
            rtf += #"\li\#(li)\fi\#(fi) "#
            for r in p.runs {
                if let id = r.footnoteID {
                    let note = essay.footnotes[id] ?? []
                    rtf += #"{\super\chftn}{\footnote\pard\plain\f0\fs20\sl240\slmult1\fi720 {\super\chftn} "# + note.map(runRTF).joined() + "}"
                } else {
                    rtf += runRTF(r)
                }
            }
            rtf += #"\par"# + "\n"
        }
        rtf += "}"
        return Data(rtf.utf8)
    }

    static func runRTF(_ r: TextRun) -> String {
        var open = ""
        if r.bold { open += #"\b"# }
        if r.italic { open += #"\i"# }
        if r.underline { open += #"\ul"# }
        let body = escape(r.text)
        return open.isEmpty ? body : "{\(open) \(body)}"
    }

    /// RTF escaping: braces and backslashes, tabs, and every non-ASCII scalar as \uN?.
    static func escape(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += #"\\"#
            case "{": out += #"\{"#
            case "}": out += #"\}"#
            case "\t": out += #"\tab "#
            case "\n": out += #"\line "#
            default:
                if scalar.value < 0x80 {
                    out.unicodeScalars.append(scalar)
                } else if scalar.value <= 0xFFFF {
                    out += "\\u\(Int16(bitPattern: UInt16(scalar.value)))?"
                } else {
                    // Outside the BMP: write the UTF-16 surrogate pair.
                    for unit in String(scalar).utf16 { out += "\\u\(Int16(bitPattern: unit))?" }
                }
            }
        }
        return out
    }
}

// MARK: - Plain text

enum PlainTextEssayWriter {
    static func write(_ essay: FormattedEssay) -> String {
        var lines: [String] = []
        for p in essay.paragraphs {
            if p.pageBreakBefore, !lines.isEmpty { lines.append("") }
            switch p.role {
            case .spacer:
                continue
            case .body, .note:
                lines.append("\t" + text(p.runs))
            default:
                lines.append(text(p.runs))
            }
        }
        if !essay.footnotes.isEmpty {
            lines.append("")
            lines.append("Notes")
            for id in essay.footnotes.keys.sorted() { lines.append("\t\(id). " + text(essay.footnotes[id] ?? [])) }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func text(_ runs: [TextRun]) -> String {
        runs.map { $0.footnoteID.map { "[\($0)]" } ?? $0.text }.joined()
    }
}
