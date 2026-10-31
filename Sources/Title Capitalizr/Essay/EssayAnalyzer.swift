//
//  EssayAnalyzer.swift
//  Title Capitalizr
//
//  Deterministic structure detection: the heading block (name, instructor, course,
//  date) or a title page, the title, body paragraphs, section headings, block quotes,
//  a Notes section and the Works Cited / References / Bibliography list. Every guess
//  that isn't certain is recorded so the UI can ask the user to confirm it.
//

import Foundation

enum ReferenceDetector {
    static let headings = ["works cited", "work cited", "works consulted", "bibliography", "references",
                           "reference list", "sources", "sources cited", "literature cited", "citations", "cited works"]

    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":.").union(.whitespaces))
            .lowercased()
    }

    static func isReferencesHeading(_ text: String) -> Bool { headings.contains(normalized(text)) }
    static func isNotesHeading(_ text: String) -> Bool { ["notes", "endnotes", "end notes"].contains(normalized(text)) }
}

struct EssayStructure: Equatable {
    enum Field: String, CaseIterable, Identifiable {
        case name, instructor, course, date, institution, title, references
        var id: Self { self }
        var label: String {
            switch self {
            case .name: return "Your name"
            case .instructor: return "Instructor"
            case .course: return "Course"
            case .date: return "Date"
            case .institution: return "Institution"
            case .title: return "Title"
            case .references: return "Works Cited list"
            }
        }
    }

    var heading = HeadingFields()
    var title = ""
    var body: [SourceParagraph] = []
    var notes: [SourceParagraph] = []
    var references: [SourceParagraph] = []
    var footnotes: [Int: [TextRun]] = [:]
    /// Fields the analyser could not determine with confidence.
    var uncertain: Set<Field> = []
    /// Where each field came from, for the "detected" view.
    var detectedReferencesHeading: String?
    /// Parsed date, when the date line could be read.
    var parsedDate: Date?
}

enum EssayAnalyzer {
    static let maxFrontMatterWords = 14

    static func analyze(_ doc: SourceDocument) -> EssayStructure {
        var s = EssayStructure()
        s.footnotes = doc.footnotes
        var paras = doc.paragraphs.filter { !$0.isBlank }.map { p -> SourceParagraph in
            var p = p
            p.runs = p.runs.trimmed()
            return p
        }
        // Drop a leading running header such as "Seong 1".
        while let first = paras.first, isRunningHeader(first.text) { paras.removeFirst() }

        // 1. References and notes, searching from the end.
        if let refIndex = paras.lastIndex(where: { ReferenceDetector.isReferencesHeading($0.text) }), refIndex > 0 {
            s.detectedReferencesHeading = paras[refIndex].text
            s.references = Array(paras[(refIndex + 1)...]).filter { !isRunningHeader($0.text) }
            paras = Array(paras[..<refIndex])
        } else {
            s.uncertain.insert(.references)
        }
        if let notesIndex = paras.lastIndex(where: { ReferenceDetector.isNotesHeading($0.text) }), notesIndex > paras.count / 2 {
            s.notes = Array(paras[(notesIndex + 1)...])
            paras = Array(paras[..<notesIndex])
        }

        // 2. Front matter: the leading run of short lines before the first real paragraph.
        var front: [SourceParagraph] = []
        var idx = 0
        while idx < paras.count, idx < 9 {
            let p = paras[idx]
            if idx > 0, p.pageBreakBefore { break }
            guard isShortLine(p) else { break }
            front.append(p)
            idx += 1
        }
        // A title page ends with a page break: everything before the break is front matter.
        if idx < paras.count, paras[idx].pageBreakBefore, front.count == idx { /* already complete */ }

        // 3. Title: an explicit Title style, else a centered or bold line, else the last front line.
        var titleIndex: Int?
        if let i = front.firstIndex(where: { $0.hint == .title }) {
            titleIndex = i
        } else if let i = front.firstIndex(where: { $0.hint == .centered || $0.hint == .heading(1) || $0.isWhollyBold }),
                  !looksLikeDate(front[i].text) {
            titleIndex = i
        } else if let d = front.prefix(5).firstIndex(where: { looksLikeDate($0.text) }), d + 1 < front.count {
            // MLA heading typed as plain lines: the title follows the date.
            titleIndex = d + 1
            s.uncertain.insert(.title)
        } else if front.count >= 2 {
            titleIndex = front.count - 1
            s.uncertain.insert(.title)
        } else if front.count == 1 {
            titleIndex = 0
            s.uncertain.insert(.title)
        }
        // Lines after the title stay front matter only on a title page (centered lines or a
        // page break after the block); otherwise they are body, e.g. an "Introduction" heading.
        if let t = titleIndex, t + 1 < front.count {
            let endsWithPageBreak = idx < paras.count && paras[idx].pageBreakBefore
            if !endsWithPageBreak {
                var cut = t + 1
                if cut < front.count, front[cut].hint == .subtitle { cut += 1 }
                while cut < front.count, front[cut].hint == .centered { cut += 1 }
                if cut < front.count {
                    idx = cut
                    front = Array(front.prefix(cut))
                }
            }
        }
        // A subtitle line right after the title joins it with a colon.
        if let t = titleIndex {
            var title = front[t].text
            if t + 1 < front.count, front[t + 1].hint == .subtitle {
                title += ": " + front[t + 1].text
                front.remove(at: t + 1)
            }
            s.title = cleanTitle(title)
        } else {
            s.uncertain.insert(.title)
        }

        // 4. Classify the remaining front lines.
        var rest = front.enumerated().filter { $0.offset != titleIndex }.map(\.element.text)
        // Lines after the title in an MLA-style heading are rare; anything past 6 lines is body.
        if rest.count > 6 { rest = Array(rest.prefix(6)) }
        classifyHeading(rest, into: &s)

        // Body is everything after the front matter.
        s.body = Array(paras[idx...])
        if s.body.isEmpty, !front.isEmpty {
            // Very short document: treat it all as body except the title.
            s.body = front.enumerated().filter { $0.offset != titleIndex }.map(\.element)
        }
        return s
    }

    static func classifyHeading(_ lines: [String], into s: inout EssayStructure) {
        var unassigned: [String] = []
        for line in lines {
            let lower = line.lowercased()
            if s.heading.date.isEmpty, looksLikeDate(line) {
                s.heading.date = line
                s.parsedDate = DateParsing.parse(line)
            } else if s.heading.instructor.isEmpty, isInstructor(lower) {
                s.heading.instructor = line
            } else if s.heading.institution.isEmpty, isInstitution(lower) {
                s.heading.institution = line
            } else if s.heading.course.isEmpty, isCourse(line) {
                s.heading.course = line
            } else {
                unassigned.append(line)
            }
        }
        // MLA order is name, instructor, course, date: fill the gaps in that order.
        for line in unassigned {
            if s.heading.name.isEmpty { s.heading.name = line }
            else if s.heading.instructor.isEmpty { s.heading.instructor = line; s.uncertain.insert(.instructor) }
            else if s.heading.course.isEmpty { s.heading.course = line; s.uncertain.insert(.course) }
        }
        if s.heading.name.isEmpty { s.uncertain.insert(.name) }
        if s.heading.instructor.isEmpty { s.uncertain.insert(.instructor) }
        if s.heading.course.isEmpty { s.uncertain.insert(.course) }
        if s.heading.date.isEmpty || s.parsedDate == nil { s.uncertain.insert(.date) }
        if !s.heading.name.isEmpty, s.heading.name.split(separator: " ").count > 5 { s.uncertain.insert(.name) }
    }

    // MARK: Heuristics

    static func isShortLine(_ p: SourceParagraph) -> Bool {
        if p.hint == .title || p.hint == .subtitle { return true }
        let text = p.text.trimmingCharacters(in: .whitespaces)
        let words = text.split(separator: " ").count
        guard words > 0, words <= maxFrontMatterWords else { return false }
        if p.runs.contains(where: { $0.footnoteID != nil }) { return false }
        // Sentences end with a period; heading lines don't (but "Dr." and dates may).
        if text.hasSuffix("."), !looksLikeDate(text) {
            let last = text.split(separator: " ").last.map(String.init) ?? ""
            let abbreviations = ["dr.", "prof.", "jr.", "sr.", "ph.d.", "st.", "inc.", "u.s."]
            if !abbreviations.contains(last.lowercased()) && words > 4 { return false }
        }
        return true
    }

    static func isRunningHeader(_ text: String) -> Bool {
        let parts = text.split(separator: " ")
        guard parts.count == 2 || parts.count == 1, let last = parts.last, last.allSatisfy(\.isNumber) else { return false }
        return parts.count == 1 || parts[0].first?.isUppercase == true
    }

    static func isInstructor(_ lower: String) -> Bool {
        let titles = ["professor", "prof.", "prof ", "dr.", "dr ", "mr.", "mrs.", "ms.", "mx.", "mr ", "mrs ", "ms ", "instructor", "teacher", "dean "]
        return titles.contains { lower.hasPrefix($0) } || lower.contains("professor")
    }

    static func isInstitution(_ lower: String) -> Bool {
        ["university", "college", "department of", "school of", "institute", "academy"].contains { lower.contains($0) }
    }

    static func isCourse(_ line: String) -> Bool {
        let lower = line.lowercased()
        let keywords = ["english", "engl", "history", "hist", "course", "section", "seminar", "writing", "composition",
                        "literature", "philosophy", "psychology", "psych", "sociology", "biology", "chemistry", "physics",
                        "math", "economics", "econ", "humanities", "class", "period", "honors", "ap ", "rhetoric", "studies"]
        let hasCode = line.range(of: #"\b[A-Z]{2,5}\s?-?\d{1,4}[A-Z]?\b"#, options: .regularExpression) != nil
        return hasCode || keywords.contains { lower.contains($0) } || (line.contains { $0.isNumber } && !looksLikeDate(line))
    }

    static func looksLikeDate(_ text: String) -> Bool { DateParsing.parse(text) != nil }

    static func cleanTitle(_ t: String) -> String {
        var s = t.trimmingCharacters(in: .whitespacesAndNewlines)
        // Titles don't end in a period (but may end in ? or !).
        while s.hasSuffix(".") && !s.hasSuffix("...") { s.removeLast() }
        // Strip quotes wrapping the entire title.
        if s.count > 2, (s.hasPrefix("\"") && s.hasSuffix("\"")) || (s.hasPrefix("“") && s.hasSuffix("”")) {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }
}

enum DateParsing {
    private static let formats = [
        "d MMMM yyyy", "d MMM yyyy", "d MMM. yyyy", "MMMM d, yyyy", "MMMM d yyyy", "MMM d, yyyy", "MMM. d, yyyy",
        "MMMM dd, yyyy", "d MMMM, yyyy", "yyyy-MM-dd", "M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "d.M.yyyy", "MMMM d'st', yyyy",
        "MMMM d'nd', yyyy", "MMMM d'rd', yyyy", "MMMM d'th', yyyy", "EEEE, MMMM d, yyyy"
    ]

    static func parse(_ text: String) -> Date? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard t.count <= 40, t.contains(where: \.isNumber) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.isLenient = false
        for format in formats {
            f.dateFormat = format
            if let d = f.date(from: t) { return d }
        }
        return nil
    }

    /// MLA: "30 October 2026". APA and Chicago: "October 30, 2026".
    static func format(_ date: Date, style: EssayStyle) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = style == .mla9 ? "d MMMM yyyy" : "MMMM d, yyyy"
        return f.string(from: date)
    }

    /// Today's date at UTC midnight so it formats the same way everywhere.
    static func today(_ now: Date = Date()) -> Date {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: now)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        return utc.date(from: c) ?? now
    }
}
