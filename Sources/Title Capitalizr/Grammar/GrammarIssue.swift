//
//  GrammarIssue.swift
//  Title Capitalizr
//
//  A single spelling or grammar problem found in the user's title, together
//  with the replacement the user can accept with one tap. Nothing is ever
//  changed automatically: the user applies a fix explicitly.
//

import Foundation

struct GrammarIssue: Identifiable, Equatable {
    enum Kind: String {
        case spelling
        case article          // a / an
        case doubledWord
        case apostrophe
        case firstWordCapital
        case subjectVerb
        case aiSuggestion     // whole-title rewrite proposed by the on-device model
    }

    let id: UUID
    let kind: Kind
    /// Range of the offending text, expressed as an NSRange over the UTF-16 view of the checked string.
    let range: NSRange
    /// The exact text that was flagged.
    let original: String
    /// Replacement candidates; the first one is used by "Fix" / "Fix all".
    let replacements: [String]
    let message: String

    init(kind: Kind, range: NSRange, original: String, replacements: [String], message: String) {
        self.id = UUID()
        self.kind = kind
        self.range = range
        self.original = original
        self.replacements = replacements
        self.message = message
    }

    var preferredReplacement: String? { replacements.first }

    var title: String {
        switch kind {
        case .spelling: return "Possible misspelling"
        case .article: return "Wrong article"
        case .doubledWord: return "Doubled word"
        case .apostrophe: return "Missing apostrophe"
        case .firstWordCapital: return "Capitalize the first word"
        case .subjectVerb: return "Subject-verb agreement"
        case .aiSuggestion: return "Apple Intelligence suggestion"
        }
    }

    var systemImage: String {
        switch kind {
        case .spelling: return "textformat.abc.dottedunderline"
        case .article: return "a.circle"
        case .doubledWord: return "repeat"
        case .apostrophe: return "quote.opening"
        case .firstWordCapital: return "textformat.size.larger"
        case .subjectVerb: return "person.2"
        case .aiSuggestion: return "sparkles"
        }
    }
}

extension Array where Element == GrammarIssue {
    /// Applies the preferred replacement of every issue to `text`, from the end of
    /// the string backwards so earlier ranges stay valid. Issues without a
    /// replacement are skipped. Used by "Fix all".
    func applyingAll(to text: String) -> String {
        let ns = NSMutableString(string: text)
        let ordered = self
            .filter { $0.preferredReplacement != nil && $0.range.location != NSNotFound }
            .sorted { $0.range.location > $1.range.location }
        var lastLocation = Int.max
        for issue in ordered {
            // Skip overlapping ranges (e.g. a spelling issue inside an AI rewrite).
            guard issue.range.location + issue.range.length <= lastLocation,
                  issue.range.location + issue.range.length <= ns.length else { continue }
            ns.replaceCharacters(in: issue.range, with: issue.preferredReplacement!)
            lastLocation = issue.range.location
        }
        return ns as String
    }
}

extension GrammarIssue {
    /// Applies this single issue to `text`. Returns the text unchanged if the range no longer matches.
    func applying(to text: String) -> String {
        guard let replacement = preferredReplacement, range.location != NSNotFound else { return text }
        let ns = text as NSString
        guard range.location + range.length <= ns.length, ns.substring(with: range) == original else { return text }
        return ns.replacingCharacters(in: range, with: replacement)
    }
}
