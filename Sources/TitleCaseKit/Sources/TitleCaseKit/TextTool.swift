import Foundation

/// Plain text transformations.
public enum TextTool: String, CaseIterable, Codable, Identifiable, Sendable {
    case upper, lower, sentence, capitalizeEach, camel, pascal, snake, kebab, slug, smartPunctuation, straightPunctuation,
         trimSpaces, removeLineBreaks

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .upper: return "UPPERCASE"
        case .lower: return "lowercase"
        case .sentence: return "Sentence case"
        case .capitalizeEach: return "Capitalize Each Word"
        case .camel: return "camelCase"
        case .pascal: return "PascalCase"
        case .snake: return "snake_case"
        case .kebab: return "kebab-case"
        case .slug: return "URL slug"
        case .smartPunctuation: return "Smart quotes and dashes"
        case .straightPunctuation: return "Straight quotes"
        case .trimSpaces: return "Trim spaces"
        case .removeLineBreaks: return "Remove line breaks"
        }
    }

    public var systemImage: String {
        switch self {
        case .upper: return "textformat.size.larger"
        case .lower: return "textformat.size.smaller"
        case .sentence: return "text.alignleft"
        case .capitalizeEach: return "textformat"
        case .camel: return "chevron.left.forwardslash.chevron.right"
        case .pascal: return "curlybraces"
        case .snake: return "underline"
        case .kebab: return "minus"
        case .slug: return "link"
        case .smartPunctuation: return "quote.opening"
        case .straightPunctuation: return "quote.closing"
        case .trimSpaces: return "scissors"
        case .removeLineBreaks: return "arrow.right.to.line"
        }
    }

    public var isFree: Bool {
        switch self {
        case .upper, .lower, .sentence, .trimSpaces, .removeLineBreaks: return true
        default: return false
        }
    }

    public func apply(_ text: String) -> String {
        switch self {
        case .upper: return text.uppercased()
        case .lower: return text.lowercased()
        case .sentence: return TextTools.sentenceCase(text)
        case .capitalizeEach: return TextTools.capitalizeEach(text)
        case .camel: return TextTools.perLine(text) { TextTools.identifier($0, style: .camel) }
        case .pascal: return TextTools.perLine(text) { TextTools.identifier($0, style: .pascal) }
        case .snake: return TextTools.perLine(text) { TextTools.identifier($0, style: .snake) }
        case .kebab: return TextTools.perLine(text) { TextTools.identifier($0, style: .kebab) }
        case .slug: return TextTools.perLine(text, TextTools.slug)
        case .smartPunctuation: return TextTools.smart(text)
        case .straightPunctuation: return TextTools.straight(text)
        case .trimSpaces: return TextTools.trimSpaces(text)
        case .removeLineBreaks: return TextTools.removeLineBreaks(text)
        }
    }
}

enum TextTools {
    static func perLine(_ text: String, _ f: (String) -> String) -> String {
        text.components(separatedBy: "\n").map { line in
            let cr = line.hasSuffix("\r")
            return f(cr ? String(line.dropLast()) : line) + (cr ? "\r" : "")
        }.joined(separator: "\n")
    }

    static func sentenceCase(_ text: String) -> String {
        perLine(text) { line in
            let allCaps = line.contains(where: { $0.isLetter }) && !line.contains(where: { $0.isLowercase })
            let src = allCaps ? line.lowercased() : line
            var out = ""
            var startSentence = true
            var word = ""
            func flush() {
                guard !word.isEmpty else { return }
                var w = word
                let core = w.filter { $0.isLetter || $0 == "'" || $0 == "’" }
                if TitleCaseEngine.hasDeliberateCaps(w) || w.contains(where: { $0.isNumber }) {
                    // keep
                } else if let known = Lexicon.lookup(core, in: Lexicon.builtIn, excluding: Lexicon.ambiguousBuiltIn), !core.isEmpty {
                    w = w.replacingOccurrences(of: core, with: known, options: .caseInsensitive)
                } else {
                    w = w.lowercased()
                    if Words.pronounI.contains(core.lowercased()) || startSentence { w = TitleCaseEngine.capitalize(w) }
                }
                if w.contains(where: { $0.isLetter }) { startSentence = false }
                let trimmed = w.trimmingCharacters(in: CharacterSet(charactersIn: "\"'”’)]"))
                if let last = trimmed.last, ".!?".contains(last) {
                    let stem = trimmed.dropLast().lowercased().trimmingCharacters(in: .punctuationCharacters)
                    if !Words.abbreviations.contains(stem) && !(stem.count == 1) { startSentence = true }
                }
                out += w
                word = ""
            }
            for ch in src {
                if ch.isWhitespace { flush(); out.append(ch) } else { word.append(ch) }
            }
            flush()
            return out
        }
    }

    static func capitalizeEach(_ text: String) -> String {
        var out = "", word = ""
        func flush() {
            guard !word.isEmpty else { return }
            out += TitleCaseEngine.hasDeliberateCaps(word) ? word : TitleCaseEngine.capitalize(word.lowercased())
            word = ""
        }
        for ch in text { if ch.isWhitespace { flush(); out.append(ch) } else { word.append(ch) } }
        flush()
        return out
    }

    enum IdentStyle { case camel, pascal, snake, kebab }

    /// Splits on any non-alphanumeric and on camel-case boundaries ("HTMLParser" -> html, parser).
    static func identifierWords(_ s: String) -> [String] {
        var words: [String] = []
        var cur: [Character] = []
        let chars = Array(s)
        func flush() { if !cur.isEmpty { words.append(String(cur).lowercased()); cur = [] } }
        for (i, c) in chars.enumerated() {
            guard c.isLetter || c.isNumber else { flush(); continue }
            if let prev = cur.last {
                let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
                if prev.isLowercase && c.isUppercase { flush() }
                else if prev.isUppercase && c.isUppercase, let n = next, n.isLowercase { flush() }
            }
            cur.append(c)
        }
        flush()
        return words.map { $0.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "") }
    }

    static func identifier(_ line: String, style: IdentStyle) -> String {
        let lead = String(line.prefix { $0 == " " || $0 == "\t" })
        let w = identifierWords(line)
        guard !w.isEmpty else { return line }
        switch style {
        case .camel: return lead + w[0] + w.dropFirst().map { TitleCaseEngine.capitalize($0) }.joined()
        case .pascal: return lead + w.map { TitleCaseEngine.capitalize($0) }.joined()
        case .snake: return lead + w.joined(separator: "_")
        case .kebab: return lead + w.joined(separator: "-")
        }
    }

    static func slug(_ line: String) -> String {
        var s = line.replacingOccurrences(of: "ß", with: "ss").replacingOccurrences(of: "æ", with: "ae")
            .replacingOccurrences(of: "Æ", with: "ae").replacingOccurrences(of: "œ", with: "oe").replacingOccurrences(of: "Œ", with: "oe")
            .replacingOccurrences(of: "ø", with: "o").replacingOccurrences(of: "Ø", with: "o").replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US")).lowercased()
        var out = ""
        var dash = false
        for u in s.unicodeScalars {
            if (u.value >= 97 && u.value <= 122) || (u.value >= 48 && u.value <= 57) { out.unicodeScalars.append(u); dash = false }
            else if !dash && !out.isEmpty { out.append("-"); dash = true }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }

    static func smart(_ text: String) -> String {
        var s = text.replacingOccurrences(of: "---", with: "—").replacingOccurrences(of: "--", with: "—")
            .replacingOccurrences(of: "...", with: "…")
        // Number ranges 10-20 -> en dash.
        if let re = try? NSRegularExpression(pattern: "(?<=\\d)-(?=\\d)") {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "–")
        }
        var out = ""
        let chars = Array(s)
        for (i, c) in chars.enumerated() {
            let prev: Character? = i > 0 ? chars[i - 1] : nil
            let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
            let opensAfter = prev == nil || prev!.isWhitespace || "([{“‘—–-/".contains(prev!)
            if c == "\"" {
                out.append(opensAfter ? "“" : "”")
            } else if c == "'" {
                if let p = prev, p.isLetter || p.isNumber || ".,!?;:)".contains(p) { out.append("’") }
                else if let n = next, n.isNumber { out.append("’") } // '90s
                else if opensAfter { out.append("‘") }
                else { out.append("’") }
            } else { out.append(c) }
        }
        return out
    }

    static func straight(_ text: String) -> String {
        var s = text
        for (a, b) in [("“", "\""), ("”", "\""), ("„", "\""), ("‘", "'"), ("’", "'"), ("‚", "'"), ("—", "--"), ("–", "-"), ("…", "...")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        return s
    }

    static func trimSpaces(_ text: String) -> String {
        perLine(text) { line in
            var out = ""
            var lastSpace = false
            for c in line.replacingOccurrences(of: "\u{00A0}", with: " ") {
                if c == " " || c == "\t" { if !lastSpace { out.append(" ") }; lastSpace = true } else { out.append(c); lastSpace = false }
            }
            return out.trimmingCharacters(in: .whitespaces)
        }
    }

    static func removeLineBreaks(_ text: String) -> String {
        let joined = text.replacingOccurrences(of: "\r\n", with: " ").replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\u{2028}", with: " ").replacingOccurrences(of: "\u{2029}", with: " ")
        var out = ""
        var lastSpace = false
        for c in joined {
            if c == " " || c == "\t" { if !lastSpace { out.append(" ") }; lastSpace = true } else { out.append(c); lastSpace = false }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }
}
