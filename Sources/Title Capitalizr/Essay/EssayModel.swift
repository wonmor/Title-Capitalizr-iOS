//
//  EssayModel.swift
//  Title Capitalizr
//
//  Plain value types shared by the readers, the analyser, the style rules and the
//  writers. Everything here is platform independent and unit tested.
//

import Foundation

// MARK: - Source (what was imported)

/// A run of text with the character formatting that survives re-formatting.
struct TextRun: Equatable {
    var text: String
    var italic = false
    var bold = false
    var underline = false
    /// When set, this run is a footnote reference marker (its `text` is empty).
    var footnoteID: Int? = nil

    init(_ text: String, italic: Bool = false, bold: Bool = false, underline: Bool = false, footnoteID: Int? = nil) {
        self.text = text
        self.italic = italic
        self.bold = bold
        self.underline = underline
        self.footnoteID = footnoteID
    }

    func sameFormat(as other: TextRun) -> Bool {
        italic == other.italic && bold == other.bold && underline == other.underline && footnoteID == nil && other.footnoteID == nil
    }
}

extension Array where Element == TextRun {
    var plainText: String { map(\.text).joined() }

    /// Merges adjacent runs with identical formatting and drops empty text runs.
    func coalesced() -> [TextRun] {
        var out: [TextRun] = []
        for r in self {
            if r.footnoteID == nil, r.text.isEmpty { continue }
            if let last = out.last, last.sameFormat(as: r) {
                out[out.count - 1].text += r.text
            } else {
                out.append(r)
            }
        }
        return out
    }

    /// Trims leading and trailing whitespace across the runs.
    func trimmed() -> [TextRun] {
        var runs = coalesced()
        while let first = runs.first, first.footnoteID == nil {
            let t = String(first.text.drop(while: { $0.isWhitespace }))
            if t.isEmpty { runs.removeFirst() } else { runs[0].text = t; break }
        }
        while let last = runs.last, last.footnoteID == nil {
            var t = last.text
            while let c = t.last, c.isWhitespace { t.removeLast() }
            if t.isEmpty { runs.removeLast() } else { runs[runs.count - 1].text = t; break }
        }
        return runs
    }

    /// Applies a text transform that keeps the character count (for example re-casing)
    /// while preserving each run's formatting. Falls back to a single run otherwise.
    func replacingText(with newText: String) -> [TextRun] {
        let old = plainText
        guard old.count == newText.count else {
            return [TextRun(newText, italic: first?.italic ?? false, bold: first?.bold ?? false)]
        }
        var out: [TextRun] = []
        var idx = newText.startIndex
        for r in self {
            if r.footnoteID != nil { out.append(r); continue }
            let end = newText.index(idx, offsetBy: r.text.count)
            var copy = r
            copy.text = String(newText[idx..<end])
            out.append(copy)
            idx = end
        }
        return out
    }
}

enum ParagraphHint: Equatable {
    case normal
    case title
    case subtitle
    case heading(Int)
    case centered
    case quote
    case listItem
}

struct SourceParagraph: Equatable {
    var runs: [TextRun]
    var hint: ParagraphHint = .normal
    var pageBreakBefore = false

    init(_ runs: [TextRun], hint: ParagraphHint = .normal, pageBreakBefore: Bool = false) {
        self.runs = runs
        self.hint = hint
        self.pageBreakBefore = pageBreakBefore
    }

    init(text: String, hint: ParagraphHint = .normal) {
        self.init([TextRun(text)], hint: hint)
    }

    var text: String { runs.plainText }
    var isBlank: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !runs.contains { $0.footnoteID != nil } }
    var isWhollyBold: Bool {
        let visible = runs.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        return !visible.isEmpty && visible.allSatisfy(\.bold)
    }
}

enum SourceKind: String, Equatable {
    case docx = "Word"
    case pdf = "PDF"
    case rtf = "RTF"
    case txt = "Text"
    case googleDocs = "Google Docs"
}

struct SourceDocument: Equatable {
    var paragraphs: [SourceParagraph]
    var footnotes: [Int: [TextRun]] = [:]
    var kind: SourceKind
    var fileName: String = "Essay"
    /// Notes about what could not be carried over (shown to the user).
    var notes: [String] = []
}

// MARK: - Styles

enum EssayStyle: String, CaseIterable, Identifiable, Codable {
    case mla9
    case apa7
    case chicagoNotes
    case chicagoAuthorDate

    var id: Self { self }

    var shortName: String {
        switch self {
        case .mla9: return "MLA"
        case .apa7: return "APA"
        case .chicagoNotes: return "Chicago"
        case .chicagoAuthorDate: return "Chicago AD"
        }
    }

    var displayName: String {
        switch self {
        case .mla9: return "MLA 9"
        case .apa7: return "APA 7"
        case .chicagoNotes: return "Chicago notes-bibliography"
        case .chicagoAuthorDate: return "Chicago author-date"
        }
    }

    /// The heading of the source list in this style.
    var referencesHeading: String {
        switch self {
        case .mla9: return "Works Cited"
        case .apa7, .chicagoAuthorDate: return "References"
        case .chicagoNotes: return "Bibliography"
        }
    }

    /// Which title-case rules the style uses (shared with the title capitalizer).
    var titleCase: DesiredOutput {
        switch self {
        case .apa7: return .apa
        case .mla9, .chicagoNotes, .chicagoAuthorDate: return .mla
        }
    }

    var usesTitlePage: Bool { self != .mla9 }
}

/// The identifying block. MLA prints it as four lines; APA and Chicago put it on a title page.
struct HeadingFields: Equatable, Codable {
    var name = ""
    var instructor = ""
    var course = ""
    var date = ""
    /// APA student papers list the department and university.
    var institution = ""

    var lastName: String {
        let suffixes: Set<String> = ["jr", "jr.", "sr", "sr.", "ii", "iii", "iv", "phd", "ph.d."]
        let words = name.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
        return words.last(where: { !suffixes.contains($0.lowercased()) }) ?? ""
    }
}

// MARK: - Layout (what the writers draw)

enum Alignment: Equatable { case left, center, right }

struct LayoutParagraph: Equatable {
    enum Role: Equatable { case heading, title, body, sectionHeading, blockQuote, referencesHeading, reference, note, titlePage, spacer }

    var runs: [TextRun]
    var role: Role
    var alignment: Alignment = .left
    /// Indents in inches.
    var firstLineIndent: Double = 0
    var leftIndent: Double = 0
    var hangingIndent: Double = 0
    /// 1.0 single, 2.0 double.
    var lineSpacing: Double = 2.0
    /// Points of space after the paragraph.
    var spaceAfter: Double = 0
    var pageBreakBefore = false

    var text: String { runs.plainText }
}

enum RunningHeader: Equatable {
    /// "Lastname 7", top right (MLA).
    case lastNameAndPage(String)
    /// Page number only, top right (APA student, Chicago).
    case pageNumber
}

struct FormattedEssay: Equatable {
    var style: EssayStyle
    var header: RunningHeader
    /// Whether the first page shows the header (Chicago hides it on the title page).
    var headerOnFirstPage: Bool
    var paragraphs: [LayoutParagraph]
    /// Footnotes keyed by their renumbered id (1...n), in reference order.
    var footnotes: [Int: [TextRun]]
    var title: String
    var heading: HeadingFields

    static let fontName = "Times New Roman"
    static let fontSize: Double = 12
}
