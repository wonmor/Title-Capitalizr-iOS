//
//  EssayFormatter.swift
//  Title Capitalizr
//
//  Turns an analysed essay plus the user's confirmed heading fields into a
//  FormattedEssay for MLA 9, APA 7 or Chicago, and lists every change: layout rules
//  that are always applied, text fixes the user can switch off one by one, and
//  warnings that need a human decision (nothing in a warning is changed).
//

import Foundation

struct FormatIssue: Identifiable, Equatable {
    enum Kind: Equatable {
        /// Layout or normalisation that is always applied.
        case applied
        /// A deterministic text fix; on by default, the user can switch it off.
        case fix
        /// Needs a human: nothing is changed.
        case warning
    }

    /// Stable across re-formatting so switching a fix off survives edits elsewhere.
    let id: String
    let kind: Kind
    let message: String
    var original: String? = nil
    var replacement: String? = nil
}

enum EssayFormatter {
    struct Input {
        var structure: EssayStructure
        var heading: HeadingFields
        var title: String
        var style: EssayStyle
        /// Fix ids the user switched off.
        var disabledFixes: Set<String> = []
    }

    struct Output: Equatable {
        var essay: FormattedEssay
        var issues: [FormatIssue]
    }

    static func format(_ input: Input) -> Output {
        let style = input.style
        var issues: [FormatIssue] = []
        var paragraphs: [LayoutParagraph] = []

        issues.append(FormatIssue(id: "layout", kind: .applied,
                                  message: "Times New Roman 12 pt, 1 inch margins, \(style == .chicagoNotes || style == .chicagoAuthorDate ? "double-spaced text with single-spaced notes and bibliography" : "double-spaced throughout")"))

        // Title case
        let rawTitle = EssayAnalyzer.cleanTitle(input.title)
        let title = TitleCaser.apply(rawTitle, style: style.titleCase)
        if !rawTitle.isEmpty, title != rawTitle {
            issues.append(FormatIssue(id: "titlecase", kind: .applied, message: "Title set in \(style.shortName) title case", original: rawTitle, replacement: title))
        }

        // Heading fields and date
        var heading = input.heading
        heading = HeadingFields(name: tidy(heading.name), instructor: tidy(heading.instructor), course: tidy(heading.course),
                                date: tidy(heading.date), institution: tidy(heading.institution))
        if let d = DateParsing.parse(heading.date) {
            let formatted = DateParsing.format(d, style: style)
            if formatted != heading.date {
                issues.append(FormatIssue(id: "date", kind: .applied, message: "Date written as \(style == .mla9 ? "day Month year" : "Month day, year")", original: heading.date, replacement: formatted))
                heading.date = formatted
            }
        } else if !heading.date.isEmpty {
            issues.append(FormatIssue(id: "date-unparsed", kind: .warning, message: "Couldn't read the date \"\(heading.date)\". It's printed as typed."))
        }
        for (field, value) in [("name", heading.name), ("instructor", heading.instructor), ("course", heading.course), ("date", heading.date)] where value.isEmpty {
            issues.append(FormatIssue(id: "missing-\(field)", kind: .warning, message: "The heading has no \(field). Add it above before exporting."))
        }
        if rawTitle.isEmpty {
            issues.append(FormatIssue(id: "missing-title", kind: .warning, message: "No title found. Add one above."))
        }

        // Front matter
        switch style {
        case .mla9:
            for line in [heading.name, heading.instructor, heading.course, heading.date] where !line.isEmpty {
                paragraphs.append(LayoutParagraph(runs: [TextRun(line)], role: .heading))
            }
            if !title.isEmpty {
                paragraphs.append(LayoutParagraph(runs: [TextRun(title)], role: .title, alignment: .center))
            }
            issues.append(FormatIssue(id: "mla-heading", kind: .applied, message: "Four-line heading and centered title on page 1; \"\(heading.lastName.isEmpty ? "Lastname" : heading.lastName) 1\" running header, top right"))
        case .apa7:
            paragraphs += spacers(3)
            paragraphs.append(LayoutParagraph(runs: [TextRun(title, bold: true)], role: .titlePage, alignment: .center))
            paragraphs += spacers(1)
            for line in [heading.name, heading.institution, heading.course, heading.instructor, heading.date] where !line.isEmpty {
                paragraphs.append(LayoutParagraph(runs: [TextRun(line)], role: .titlePage, alignment: .center))
            }
            var repeatTitle = LayoutParagraph(runs: [TextRun(title, bold: true)], role: .title, alignment: .center)
            repeatTitle.pageBreakBefore = true
            paragraphs.append(repeatTitle)
            issues.append(FormatIssue(id: "apa-titlepage", kind: .applied, message: "APA student title page; bold title repeated on page 2; page numbers top right"))
            if heading.institution.isEmpty {
                issues.append(FormatIssue(id: "missing-institution", kind: .warning, message: "APA title pages list your department and university. Add it under Institution."))
            }
        case .chicagoNotes, .chicagoAuthorDate:
            paragraphs += spacers(6)
            paragraphs.append(LayoutParagraph(runs: [TextRun(title)], role: .titlePage, alignment: .center))
            paragraphs += spacers(7)
            for line in [heading.name, heading.course, heading.instructor, heading.date] where !line.isEmpty {
                paragraphs.append(LayoutParagraph(runs: [TextRun(line)], role: .titlePage, alignment: .center, lineSpacing: 1.0, spaceAfter: 0))
            }
            issues.append(FormatIssue(id: "chicago-titlepage", kind: .applied, message: "Chicago title page without a page number; page numbers top right from page 2"))
        }

        // References: tidy, fix, sort
        let refs = input.structure.references.map { tidyRuns($0.runs) }
        var referenceKeysBefore: [String] = []
        var refParagraphs: [[TextRun]] = []
        for (i, runs) in refs.enumerated() {
            var r = runs
            r = applyReferenceFixes(r, index: i, style: style, disabled: input.disabledFixes, issues: &issues)
            referenceKeysBefore.append(sortKey(r.plainText))
            refParagraphs.append(r)
        }
        let sortedRefs = refParagraphs.sorted { sortKey($0.plainText) < sortKey($1.plainText) }
        if sortedRefs.map({ sortKey($0.plainText) }) != referenceKeysBefore {
            issues.append(FormatIssue(id: "sort", kind: .applied, message: "\(style.referencesHeading) entries put in alphabetical order"))
        }
        if let found = input.structure.detectedReferencesHeading, ReferenceDetector.normalized(found) != style.referencesHeading.lowercased() {
            issues.append(FormatIssue(id: "refs-heading", kind: .applied, message: "\"\(found)\" heading renamed \"\(style.referencesHeading)\"", original: found, replacement: style.referencesHeading))
        }

        // Body
        var manualIndents = 0, extraSpaces = 0
        var bodyLayout: [LayoutParagraph] = []
        let referenceText = sortedRefs.map { $0.plainText.lowercased() }
        var citedAuthors = Set<String>()
        var parentheticalCount = 0
        for (i, para) in input.structure.body.enumerated() {
            let original = para.runs.plainText
            if original.first == "\t" || original.hasPrefix("  ") { manualIndents += 1 }
            var runs = tidyRuns(para.runs)
            if original.contains("  ") && !original.trimmingCharacters(in: .whitespaces).isEmpty,
               original.trimmingCharacters(in: .whitespaces).contains("  ") { extraSpaces += 1 }
            runs = applyCitationChecks(runs, paragraph: i, style: style, references: referenceText, disabled: input.disabledFixes,
                                       issues: &issues, citedAuthors: &citedAuthors, count: &parentheticalCount)
            let isHeading: Bool = {
                if case .heading = para.hint { return true }
                let t = runs.plainText
                return para.isWhollyBold && t.split(separator: " ").count <= 12 && !t.hasSuffix(".")
            }()
            if isHeading {
                let cased = runs.replacingText(with: TitleCaser.apply(runs.plainText, style: style.titleCase))
                switch style {
                case .apa7:
                    bodyLayout.append(LayoutParagraph(runs: cased.map { var r = $0; r.bold = true; return r }, role: .sectionHeading, alignment: .center))
                case .mla9, .chicagoNotes, .chicagoAuthorDate:
                    bodyLayout.append(LayoutParagraph(runs: cased, role: .sectionHeading, alignment: style == .mla9 ? .left : .center))
                }
            } else if para.hint == .quote {
                let single = style == .chicagoNotes || style == .chicagoAuthorDate
                bodyLayout.append(LayoutParagraph(runs: runs, role: .blockQuote, leftIndent: 0.5, lineSpacing: single ? 1.0 : 2.0, spaceAfter: single ? 12 : 0))
            } else {
                bodyLayout.append(LayoutParagraph(runs: runs, role: .body, firstLineIndent: 0.5))
            }
        }
        // Chicago title page: the text starts on a new page.
        if style == .chicagoNotes || style == .chicagoAuthorDate, !bodyLayout.isEmpty { bodyLayout[0].pageBreakBefore = true }
        paragraphs += bodyLayout
        issues.append(FormatIssue(id: "indent", kind: .applied, message: "Paragraphs indented 0.5 inch on the first line\(manualIndents > 0 ? "; \(manualIndents) typed tab or space indents removed" : "")"))
        if extraSpaces > 0 {
            issues.append(FormatIssue(id: "spaces", kind: .applied, message: "Double spaces collapsed in \(extraSpaces) paragraph\(extraSpaces == 1 ? "" : "s")"))
        }

        // Notes section carried over from the source (endnotes typed as text)
        if !input.structure.notes.isEmpty {
            var h = LayoutParagraph(runs: [TextRun("Notes")], role: .referencesHeading, alignment: .center)
            h.pageBreakBefore = true
            paragraphs.append(h)
            for n in input.structure.notes {
                let single = style == .chicagoNotes || style == .chicagoAuthorDate
                paragraphs.append(LayoutParagraph(runs: tidyRuns(n.runs), role: .note, firstLineIndent: 0.5, lineSpacing: single ? 1.0 : 2.0, spaceAfter: single ? 12 : 0))
            }
        }

        // References list
        if !sortedRefs.isEmpty {
            var h = LayoutParagraph(runs: [TextRun(style.referencesHeading, bold: style == .apa7)], role: .referencesHeading, alignment: .center)
            h.pageBreakBefore = true
            paragraphs.append(h)
            let single = style == .chicagoNotes || style == .chicagoAuthorDate
            for r in sortedRefs {
                paragraphs.append(LayoutParagraph(runs: r, role: .reference, leftIndent: 0.5, hangingIndent: 0.5,
                                                  lineSpacing: single ? 1.0 : 2.0, spaceAfter: single ? 12 : 0))
            }
            issues.append(FormatIssue(id: "refs-layout", kind: .applied, message: "\(style.referencesHeading) on a new page: centered heading, 0.5 inch hanging indents"))
        } else if parentheticalCount > 0 || !input.structure.footnotes.isEmpty {
            issues.append(FormatIssue(id: "no-refs", kind: .warning, message: "The essay cites sources but no \(style.referencesHeading) list was found. Add one at the end of the document."))
        }

        // Works Cited entries nobody cites (author-based styles only)
        if style != .chicagoNotes, parentheticalCount > 0 {
            for r in sortedRefs {
                let surname = leadingSurname(r.plainText)
                guard surname.count > 1 else { continue }
                if !citedAuthors.contains(surname.lowercased()) {
                    let bodyMentions = input.structure.body.contains { $0.text.localizedCaseInsensitiveContains(surname) }
                    if !bodyMentions {
                        issues.append(FormatIssue(id: "uncited-\(surname)", kind: .warning, message: "\"\(surname)\" is in \(style.referencesHeading) but never cited in the text."))
                    }
                }
            }
        }
        if style == .chicagoNotes, parentheticalCount > 0 {
            issues.append(FormatIssue(id: "chicago-parenthetical", kind: .warning, message: "\(parentheticalCount) parenthetical citation\(parentheticalCount == 1 ? "" : "s") found. Chicago notes-bibliography cites sources in footnotes; switch to Chicago author-date or convert them to footnotes."))
        }

        // Footnotes: renumber in reference order
        var footnotes: [Int: [TextRun]] = [:]
        var map: [Int: Int] = [:]
        for i in paragraphs.indices {
            for j in paragraphs[i].runs.indices {
                guard let old = paragraphs[i].runs[j].footnoteID else { continue }
                if map[old] == nil {
                    map[old] = map.count + 1
                    footnotes[map[old]!] = tidyRuns(input.structure.footnotes[old] ?? [TextRun("")])
                }
                paragraphs[i].runs[j].footnoteID = map[old]
            }
        }
        if !footnotes.isEmpty {
            issues.append(FormatIssue(id: "footnotes", kind: .applied, message: "\(footnotes.count) footnote\(footnotes.count == 1 ? "" : "s") kept as real Word footnotes (listed as Notes in the PDF)"))
        }

        let header: RunningHeader = style == .mla9 && !heading.lastName.isEmpty ? .lastNameAndPage(heading.lastName) : .pageNumber
        let essay = FormattedEssay(style: style, header: header, headerOnFirstPage: !(style == .chicagoNotes || style == .chicagoAuthorDate),
                                   paragraphs: paragraphs, footnotes: footnotes, title: title, heading: heading)
        return Output(essay: essay, issues: issues)
    }

    // MARK: Helpers

    static func spacers(_ n: Int) -> [LayoutParagraph] {
        Array(repeating: LayoutParagraph(runs: [], role: .spacer), count: n)
    }

    static func tidy(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
    }

    /// Removes typed indents (tabs, leading spaces) and collapses runs of spaces.
    static func tidyRuns(_ runs: [TextRun]) -> [TextRun] {
        var out = runs.map { r -> TextRun in
            var r = r
            r.text = r.text.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
            return r
        }.trimmed()
        // Collapse a space that straddles two runs.
        for i in out.indices.dropFirst() where out[i].text.hasPrefix(" ") && out[i - 1].text.hasSuffix(" ") {
            out[i].text.removeFirst()
        }
        return out.coalesced()
    }

    /// Alphabetising key: case- and accent-insensitive, ignoring opening quotes and a leading article.
    static func sortKey(_ text: String) -> String {
        var s = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        s = s.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        for article in ["the ", "a ", "an "] where s.hasPrefix(article) {
            s = String(s.dropFirst(article.count))
            break
        }
        return s
    }

    /// The first author's surname of a reference entry ("Smith, John. ..." -> "Smith").
    static func leadingSurname(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let first = t.first, first.isLetter, first.isUppercase else { return "" }
        let end = t.firstIndex(where: { $0 == "," || $0 == "." || $0 == " " }) ?? t.endIndex
        return String(t[..<end])
    }

    // MARK: Reference fixes

    static func applyReferenceFixes(_ runs: [TextRun], index: Int, style: EssayStyle, disabled: Set<String>, issues: inout [FormatIssue]) -> [TextRun] {
        var r = runs
        let text = r.plainText
        if style == .mla9 {
            let ns = text as NSString
            if let re = try? NSRegularExpression(pattern: #"https?://(www\.)?"#) {
                let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
                if !matches.isEmpty {
                    let id = "ref-url-\(index)"
                    issues.append(FormatIssue(id: id, kind: .fix, message: "MLA 9 drops \"https://\" from URLs in Works Cited", original: ns.substring(with: matches[0].range), replacement: ""))
                    if !disabled.contains(id) {
                        for m in matches.reversed() { r = replace(in: r, range: m.range, with: "") }
                    }
                }
            }
            if text.range(of: "Retrieved from", options: .caseInsensitive) != nil {
                issues.append(FormatIssue(id: "ref-retrieved-\(index)", kind: .warning, message: "\"Retrieved from\" is APA wording. MLA entries end with the URL or DOI."))
            }
        }
        let current = r.plainText
        if let last = current.last, !".?!".contains(last), !current.hasSuffix(".”"), !current.hasSuffix(".\"") {
            let id = "ref-period-\(index)"
            issues.append(FormatIssue(id: id, kind: .fix, message: "Entry ends with a period", original: String(current.suffix(24)), replacement: String(current.suffix(24)) + "."))
            if !disabled.contains(id), let lastIndex = r.lastIndex(where: { $0.footnoteID == nil }) {
                r[lastIndex].text += "."
            }
        }
        return r
    }

    // MARK: In-text citations

    private static let parenthetical = try! NSRegularExpression(pattern: #"\(([^()]{1,120})\)"#)
    private static let mlaComma = try! NSRegularExpression(pattern: #"^([^\d,;]*[A-Za-z\.”"])\s*,\s*(?:(?:p|pp)\.\s*)?(\d+(?:[-–]\d+)?)$"#)
    private static let mlaPageAbbrev = try! NSRegularExpression(pattern: #"^((?:[^\d,;]*[A-Za-z\.”"]\s+)?)(?:p|pp)\.\s*(\d+(?:[-–]\d+)?)$"#)
    private static let apaNoComma = try! NSRegularExpression(pattern: #"^([A-Z][^\d,;]*[A-Za-z\.])\s+((?:1[5-9]|20)\d{2}[a-z]?|n\.d\.)((?:,\s*.*)?)$"#)
    private static let chicagoADComma = try! NSRegularExpression(pattern: #"^([A-Z][^\d;]*[A-Za-z\.]),\s*((?:1[5-9]|20)\d{2}[a-z]?|n\.d\.)((?:,\s*.*)?)$"#)
    private static let yearOnly = try! NSRegularExpression(pattern: #"^[^\d;]*,\s*(?:1[5-9]|20)\d{2}[a-z]?(?:,.*)?$"#)
    private static let punctuationBeforeCitation = try! NSRegularExpression(pattern: #"([.,])(["”])\s+(\([^()]{1,120}\))"#)

    static func applyCitationChecks(_ runs: [TextRun], paragraph: Int, style: EssayStyle, references: [String], disabled: Set<String>,
                                    issues: inout [FormatIssue], citedAuthors: inout Set<String>, count: inout Int) -> [TextRun] {
        var r = runs
        // Punctuation goes after the citation: ..."quote" (Smith 4).
        if style != .chicagoNotes {
            let text = r.plainText
            let ns = text as NSString
            for m in punctuationBeforeCitation.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                let punct = ns.substring(with: m.range(at: 1)), quote = ns.substring(with: m.range(at: 2)), cite = ns.substring(with: m.range(at: 3))
                guard citationLike(String(cite.dropFirst().dropLast())) else { continue }
                let replacement = "\(quote) \(cite)\(punct)"
                let id = "punct-\(paragraph)-\(cite)"
                issues.append(FormatIssue(id: id, kind: .fix, message: "Punctuation moved after the citation", original: ns.substring(with: m.range), replacement: replacement))
                if !disabled.contains(id) { r = replace(in: r, range: m.range, with: replacement) }
            }
        }

        let text = r.plainText
        let ns = text as NSString
        for m in parenthetical.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let inner = ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespaces)
            guard citationLike(inner) else { continue }
            count += 1
            let innerNS = inner as NSString
            let whole = NSRange(location: 0, length: innerNS.length)
            var fixed: String?
            var message = ""
            switch style {
            case .mla9:
                if inner.contains(";") { break }
                if yearOnly.firstMatch(in: inner, range: whole) != nil, !inner.contains("p.") {
                    issues.append(FormatIssue(id: "apa-in-mla-\(paragraph)-\(inner)", kind: .warning, message: "(\(inner)) looks like an APA citation. MLA cites author and page: (Author 23)."))
                } else if let mm = mlaComma.firstMatch(in: inner, range: whole) {
                    fixed = "\(innerNS.substring(with: mm.range(at: 1))) \(innerNS.substring(with: mm.range(at: 2)))"
                    message = "MLA puts no comma or \"p.\" between author and page"
                } else if let mm = mlaPageAbbrev.firstMatch(in: inner, range: whole) {
                    let author = innerNS.substring(with: mm.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    fixed = author.isEmpty ? innerNS.substring(with: mm.range(at: 2)) : "\(author) \(innerNS.substring(with: mm.range(at: 2)))"
                    message = "MLA drops \"p.\" and \"pp.\" before page numbers"
                }
            case .apa7:
                if let mm = apaNoComma.firstMatch(in: inner, range: whole), !inner.contains(";") {
                    fixed = "\(innerNS.substring(with: mm.range(at: 1))), \(innerNS.substring(with: mm.range(at: 2)))\(innerNS.substring(with: mm.range(at: 3)))"
                    message = "APA puts a comma between author and year"
                } else if inner.range(of: #"(1[5-9]|20)\d{2}|n\.d\."#, options: .regularExpression) == nil, inner.first?.isUppercase == true {
                    issues.append(FormatIssue(id: "apa-year-\(paragraph)-\(inner)", kind: .warning, message: "(\(inner)) has no year. APA cites (Author, Year)."))
                }
            case .chicagoAuthorDate:
                if let mm = chicagoADComma.firstMatch(in: inner, range: whole), !inner.contains(";") {
                    fixed = "\(innerNS.substring(with: mm.range(at: 1))) \(innerNS.substring(with: mm.range(at: 2)))\(innerNS.substring(with: mm.range(at: 3)))"
                    message = "Chicago author-date puts no comma between author and year"
                }
            case .chicagoNotes:
                break
            }
            let finalInner = fixed ?? inner
            // Record the cited author and check the list.
            let author = citedAuthor(finalInner)
            if !author.isEmpty {
                citedAuthors.insert(author.lowercased())
                if !references.isEmpty, style != .chicagoNotes,
                   !references.contains(where: { $0.hasPrefix(author.lowercased()) || $0.prefix(80).contains(author.lowercased()) }) {
                    issues.append(FormatIssue(id: "unknown-author-\(author)", kind: .warning, message: "\"\(author)\" is cited in the text but isn't in \(style.referencesHeading)."))
                }
            }
            if let fixed, fixed != inner {
                let id = "cite-\(paragraph)-\(inner)"
                issues.append(FormatIssue(id: id, kind: .fix, message: message, original: "(\(inner))", replacement: "(\(fixed))"))
                if !disabled.contains(id) { r = replace(in: r, range: m.range(at: 1), with: fixed) }
            }
        }
        // De-duplicate warnings that repeat for the same author.
        var seen = Set<String>()
        issues = issues.filter { seen.insert($0.id).inserted }
        return r
    }

    /// A parenthetical that holds a page number, a year or "n.d." with something author-like.
    static func citationLike(_ inner: String) -> Bool {
        guard inner.contains(where: \.isNumber) || inner.contains("n.d.") else { return false }
        if inner.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "–" }) { return true }
        if inner.range(of: #"^(p|pp)\.\s*\d"#, options: .regularExpression) != nil { return true }
        // "(1990-1995)" style ranges and "(see figure 2)" aren't citations.
        if inner.lowercased().hasPrefix("see ") || inner.lowercased().hasPrefix("fig") { return false }
        return inner.first?.isUppercase == true || inner.first == "\"" || inner.first == "“"
    }

    static func citedAuthor(_ inner: String) -> String {
        guard let first = inner.first, first.isUppercase else { return "" }
        let word = inner.prefix { $0.isLetter || $0 == "-" || $0 == "'" || $0 == "’" }
        let w = String(word)
        let skip: Set<String> = ["See", "Qtd", "Ibid", "Id", "Cf"]
        return skip.contains(w) ? "" : w
    }

    // MARK: Run-aware text replacement

    /// Replaces a UTF-16 range of the runs' plain text, keeping the formatting of the run where the range starts.
    static func replace(in runs: [TextRun], range: NSRange, with replacement: String) -> [TextRun] {
        var out: [TextRun] = []
        var pos = 0
        var inserted = false
        let start = range.location, end = range.location + range.length
        for run in runs {
            if run.footnoteID != nil {
                if pos >= start && pos < end && range.length > 0 { continue }
                out.append(run); continue
            }
            let len = (run.text as NSString).length
            let runStart = pos, runEnd = pos + len
            pos = runEnd
            if runEnd <= start || runStart >= end {
                if runStart >= end, !inserted {
                    var r = run; r.text = replacement; out.append(r); inserted = true
                }
                out.append(run)
                continue
            }
            let ns = run.text as NSString
            let keepBefore = ns.substring(to: max(0, start - runStart))
            let keepAfter = end < runEnd ? ns.substring(from: end - runStart) : ""
            var r = run
            if !inserted {
                r.text = keepBefore + replacement + keepAfter
                inserted = true
            } else {
                r.text = keepBefore + keepAfter
            }
            out.append(r)
        }
        if !inserted { out.append(TextRun(replacement)) }
        return out.coalesced()
    }
}
