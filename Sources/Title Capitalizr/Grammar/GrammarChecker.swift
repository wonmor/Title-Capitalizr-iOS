//
//  GrammarChecker.swift
//  Title Capitalizr
//
//  Deterministic, fully offline grammar heuristics for short titles:
//  a/an, doubled words, missing apostrophes, first-word capitalisation and
//  simple subject-verb agreement. NaturalLanguage's tagger is only used as a
//  veto to avoid false positives; the rules work without it too.
//

import Foundation
import NaturalLanguage

struct GrammarChecker {

    init() {}

    // MARK: Public API

    /// Runs every rule-based check and returns the issues ordered by position.
    func check(_ text: String) -> [GrammarIssue] {
        var issues: [GrammarIssue] = []
        issues += checkFirstWordCapitalization(text)
        issues += checkArticles(text)
        issues += checkDoubledWords(text)
        issues += checkApostrophes(text)
        issues += checkSubjectVerbAgreement(text)
        return Self.resolvingOverlaps(issues).sorted { $0.range.location < $1.range.location }
    }

    /// When the first-word capitalisation issue overlaps another issue on the same word
    /// (for example "a apple" -> "an" + capital), fold the capitalisation into that
    /// issue's replacement so "Fix" and "Fix all" give the expected "An apple".
    static func resolvingOverlaps(_ issues: [GrammarIssue]) -> [GrammarIssue] {
        guard let capital = issues.first(where: { $0.kind == .firstWordCapital }) else { return issues }
        let overlapping = issues.filter { $0.kind != .firstWordCapital && NSIntersectionRange($0.range, capital.range).length > 0 }
        guard !overlapping.isEmpty else { return issues }
        return issues.compactMap { issue in
            if issue.kind == .firstWordCapital { return nil }
            guard overlapping.contains(issue) else { return issue }
            return GrammarIssue(kind: issue.kind, range: issue.range, original: issue.original,
                                replacements: issue.replacements.map { $0.capitalizingFirstLetter() },
                                message: issue.message)
        }
    }

    // MARK: Rules

    /// The first word of a title should start with a capital letter.
    func checkFirstWordCapitalization(_ text: String) -> [GrammarIssue] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"^\s*([a-z][\p{L}'’-]*)"#)
        guard let m = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return [] }
        let r = m.range(at: 1)
        let word = ns.substring(with: r)
        return [GrammarIssue(kind: .firstWordCapital, range: r, original: word,
                             replacements: [word.capitalizingFirstLetter()],
                             message: "Titles start with a capital letter: “\(word.capitalizingFirstLetter())”.")]
    }

    /// "a" before a vowel sound and "an" before a consonant sound.
    func checkArticles(_ text: String) -> [GrammarIssue] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\b([Aa]n?)\s+([\p{L}][\p{L}'’-]*)"#)
        var issues: [GrammarIssue] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let article = ns.substring(with: m.range(at: 1))
            let next = ns.substring(with: m.range(at: 2))
            // "a a" / "an an" is a doubled word, not an article problem.
            if ["a", "an"].contains(next.lowercased()) { continue }
            let wantsAn = Self.startsWithVowelSound(next)
            let isAn = article.lowercased() == "an"
            guard wantsAn != isAn else { continue }
            let fixed: String
            if isAn {
                fixed = article.first!.isUppercase ? "A" : "a"
            } else {
                fixed = article.first!.isUppercase ? "An" : "an"
            }
            issues.append(GrammarIssue(kind: .article, range: m.range(at: 1), original: article,
                                       replacements: [fixed],
                                       message: "Use “\(fixed)” before “\(next)”."))
        }
        return issues
    }

    /// The same word repeated twice in a row ("the the").
    func checkDoubledWords(_ text: String) -> [GrammarIssue] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\b([\p{L}]+)(\s+)\1\b"#, options: [.caseInsensitive])
        var issues: [GrammarIssue] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let whole = ns.substring(with: m.range)
            let first = ns.substring(with: m.range(at: 1))
            // Allow legitimate repeats such as "that that" or "had had" only when the user clearly intends them (rare in titles); flag everything.
            issues.append(GrammarIssue(kind: .doubledWord, range: m.range, original: whole,
                                       replacements: [first],
                                       message: "“\(first)” appears twice in a row."))
        }
        return issues
    }

    /// Common contractions typed without their apostrophe.
    func checkApostrophes(_ text: String) -> [GrammarIssue] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\b([\p{L}]+)\b"#)
        var issues: [GrammarIssue] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let word = ns.substring(with: m.range)
            guard let fixed = Self.contractions[word.lowercased()] else { continue }
            let cased = Self.matchCase(of: word, to: fixed)
            issues.append(GrammarIssue(kind: .apostrophe, range: m.range, original: word,
                                       replacements: [cased],
                                       message: "“\(word)” is missing an apostrophe: “\(cased)”."))
        }
        return issues
    }

    /// Very small, conservative subject-verb agreement table for pronoun subjects.
    func checkSubjectVerbAgreement(_ text: String) -> [GrammarIssue] {
        let ns = text as NSString
        let regex = try! NSRegularExpression(pattern: #"\b(I|you|we|they|he|she|it)\s+([\p{L}]+)\b"#, options: [.caseInsensitive])
        var issues: [GrammarIssue] = []
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let subject = ns.substring(with: m.range(at: 1))
            let verb = ns.substring(with: m.range(at: 2))
            guard let corrected = Self.agreementFix(subject: subject.lowercased(), verb: verb.lowercased()) else { continue }
            // Veto: if the tagger is confident the token is a noun, don't flag it ("it works" vs "it work").
            if Self.lexicalClass(of: verb, in: text, at: m.range(at: 2)) == .noun { continue }
            let cased = Self.matchCase(of: verb, to: corrected)
            issues.append(GrammarIssue(kind: .subjectVerb, range: m.range(at: 2), original: verb,
                                       replacements: [cased],
                                       message: "“\(subject) \(verb)” should be “\(subject) \(cased)”."))
        }
        return issues
    }

    // MARK: Helpers

    static let contractions: [String: String] = [
        "dont": "don't", "cant": "can't", "wont": "won't", "isnt": "isn't", "arent": "aren't",
        "wasnt": "wasn't", "werent": "weren't", "doesnt": "doesn't", "didnt": "didn't",
        "hasnt": "hasn't", "havent": "haven't", "hadnt": "hadn't", "wouldnt": "wouldn't",
        "couldnt": "couldn't", "shouldnt": "shouldn't", "im": "I'm", "ive": "I've", "youre": "you're",
        "youve": "you've", "theyre": "they're", "theyve": "they've", "weve": "we've", "thats": "that's",
        "whats": "what's", "heres": "here's", "theres": "there's", "lets": "let's", "aint": "ain't",
        "mustnt": "mustn't", "neednt": "needn't", "whos": "who's", "hows": "how's", "whens": "when's"
    ]

    /// Words that start with a vowel letter but a consonant sound (take "a").
    static let consonantSoundExceptions: Set<String> = [
        "one", "once", "unicorn", "uniform", "union", "unique", "unit", "united", "universe", "university",
        "universal", "unanimous", "usual", "useful", "user", "use", "used", "using", "utensil", "utility",
        "utopia", "ukulele", "euro", "european", "eulogy", "euphoria", "ewe", "uranium", "urine", "usage",
        "utah", "ubiquitous", "eucalyptus", "eukaryote", "unilateral", "unicycle", "urea"
    ]

    /// Words that start with a consonant letter but a vowel sound (take "an").
    static let vowelSoundExceptions: Set<String> = [
        "hour", "hourly", "honest", "honestly", "honor", "honour", "honorable", "honourable", "heir", "heirloom",
        "herb", "homage", "mba", "mp", "nba", "nfl", "fbi", "html", "sos", "x-ray", "xml", "lcd", "led", "mri", "rsvp"
    ]

    static func startsWithVowelSound(_ word: String) -> Bool {
        let lower = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "'’-"))
        guard let first = lower.first else { return false }
        if vowelSoundExceptions.contains(lower) { return true }
        if consonantSoundExceptions.contains(lower) { return false }
        for prefix in ["uni", "use", "usu", "eu", "ur", "ute", "uti"] where lower.hasPrefix(prefix) { return false }
        // All-caps acronyms whose first letter is pronounced with a vowel sound (F, H, L, M, N, R, S, X).
        if word.count > 1, word == word.uppercased(), "FHLMNRSX".contains(word.first!) { return true }
        return "aeiou".contains(first)
    }

    static func agreementFix(subject: String, verb: String) -> String? {
        let thirdSingular: Set<String> = ["he", "she", "it"]
        let plural: Set<String> = ["you", "we", "they"]
        if thirdSingular.contains(subject) {
            switch verb {
            case "are", "am": return "is"
            case "were": return "was"
            case "have": return "has"
            case "do": return "does"
            case "go": return "goes"
            default:
                if baseVerbs.contains(verb) { return thirdPersonForm(verb) }
                return nil
            }
        }
        if plural.contains(subject) {
            switch verb {
            case "is", "am": return "are"
            case "was": return "were"
            case "has": return "have"
            case "does": return "do"
            case "goes": return "go"
            default:
                if let base = thirdPersonBases[verb] { return base }
                return nil
            }
        }
        if subject == "i" {
            switch verb {
            case "is", "are": return "am"
            case "were": return "was"
            case "has": return "have"
            case "does": return "do"
            case "goes": return "go"
            default: return nil
            }
        }
        return nil
    }

    static let baseVerbs: Set<String> = [
        "want", "need", "know", "think", "take", "see", "come", "get", "give", "find", "tell", "ask", "work", "seem",
        "feel", "try", "leave", "call", "keep", "let", "begin", "help", "talk", "turn", "start", "show", "hear", "play",
        "run", "move", "live", "believe", "hold", "bring", "happen", "write", "provide", "sit", "stand", "lose", "pay",
        "meet", "include", "continue", "set", "learn", "change", "lead", "understand", "watch", "follow", "stop",
        "create", "speak", "read", "allow", "add", "spend", "grow", "open", "walk", "win", "offer", "remember", "love",
        "consider", "appear", "buy", "wait", "serve", "die", "send", "expect", "build", "stay", "fall", "cut", "reach",
        "kill", "remain", "like", "look", "use", "make", "say", "eat", "sleep", "teach", "catch", "fly", "carry", "cry",
        "study", "fix", "miss", "pass", "push", "wish", "wash", "touch", "reach", "rise", "sell", "mean", "seek", "dream"
    ]

    static let thirdPersonBases: [String: String] = {
        var map: [String: String] = [:]
        for v in baseVerbs { map[thirdPersonForm(v)] = v }
        return map
    }()

    static func thirdPersonForm(_ verb: String) -> String {
        if verb.hasSuffix("y"), verb.count > 1, !"aeiou".contains(verb[verb.index(verb.endIndex, offsetBy: -2)]) {
            return String(verb.dropLast()) + "ies"
        }
        for suffix in ["s", "x", "z", "ch", "sh", "o"] where verb.hasSuffix(suffix) { return verb + "es" }
        return verb + "s"
    }

    static func lexicalClass(of word: String, in text: String, at range: NSRange) -> NLTag? {
        guard let swiftRange = Range(range, in: text) else { return nil }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let (tag, _) = tagger.tag(at: swiftRange.lowerBound, unit: .word, scheme: .lexicalClass)
        return tag
    }

    /// Copies the capitalisation pattern of `source` onto `target` (first letter only; all-caps words stay all-caps).
    static func matchCase(of source: String, to target: String) -> String {
        if source == source.uppercased(), source.count > 1 { return target.uppercased() }
        if let first = source.first, first.isUppercase { return target.capitalizingFirstLetter() }
        return target
    }
}
