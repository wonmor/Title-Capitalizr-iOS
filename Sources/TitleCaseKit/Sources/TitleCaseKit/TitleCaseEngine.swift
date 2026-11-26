import Foundation

/// Why a word got its case.
public enum CaseRule: String, Codable, Sendable {
    case firstWord, lastWord, afterColon, majorWord, minorWord, longPreposition, hyphenFirst, hyphenSecond,
         keptCasing, dictionary, properNounKept, sentenceLower, number, url, verbPhrasal, toInfinitive, other

    public var label: String {
        switch self {
        case .firstWord: return "First word"
        case .lastWord: return "Last word"
        case .afterColon: return "Subtitle start"
        case .majorWord: return "Major word"
        case .minorWord: return "Minor word"
        case .longPreposition: return "Long word"
        case .hyphenFirst: return "Compound start"
        case .hyphenSecond: return "Compound part"
        case .keptCasing: return "Kept casing"
        case .dictionary: return "Dictionary"
        case .properNounKept: return "Proper noun"
        case .sentenceLower: return "Lowercase"
        case .number: return "Number"
        case .url: return "Link"
        case .verbPhrasal: return "Phrasal verb"
        case .toInfinitive: return "To"
        case .other: return "Other"
        }
    }
}

public struct WordDecision: Identifiable, Equatable, Sendable {
    public let id: Int
    public let original: String
    public let output: String
    public let rule: CaseRule
    public let explanation: String

    public init(id: Int, original: String, output: String, rule: CaseRule, explanation: String) {
        self.id = id; self.original = original; self.output = output; self.rule = rule; self.explanation = explanation
    }
}

public struct CaseResult: Equatable, Sendable {
    public let text: String
    public let words: [WordDecision]
    public let guide: StyleGuide
    public let notes: [String]
}

// MARK: - Word classes

enum WordClass { case article, coordConj, shortConj, preposition }

enum Words {
    static let articles: Set<String> = ["a", "an", "the"]
    static let coordinating: Set<String> = ["and", "but", "for", "nor", "or", "so", "yet"]
    static let prepositions: Set<String> = [
        "aboard", "about", "above", "across", "after", "against", "along", "amid", "among", "around", "as", "at",
        "atop", "before", "behind", "below", "beneath", "beside", "besides", "between", "beyond", "by",
        "concerning", "despite", "down", "during", "except", "for", "from", "in", "inside", "into", "like",
        "near", "of", "off", "on", "onto", "opposite", "out", "outside", "over", "past", "per", "regarding",
        "since", "than", "through", "throughout", "till", "to", "toward", "towards", "under", "underneath",
        "unlike", "until", "unto", "up", "upon", "versus", "via", "vs", "v", "with", "within", "without",
    ]
    /// Short subordinating conjunctions that length-based guides lowercase with the coordinating ones.
    static let shortConjunctions: Set<String> = ["as", "if", "than", "when", "once", "lest", "till", "that", "though"]
    static let subordinating: Set<String> = ["if", "because", "that", "when", "while", "although", "though", "unless",
                                             "whether", "whereas", "once", "how", "where", "why", "lest"]
    static let nytLower: Set<String> = ["a", "and", "as", "at", "but", "by", "en", "for", "if", "in", "of", "on",
                                        "or", "the", "to", "v", "vs", "via"]
    static let particles: Set<String> = ["in", "on", "up", "off", "out", "down", "over", "back", "around", "away"]
    static let phrasalVerbs: [String] = ["log", "sign", "set", "turn", "back", "give", "look", "pick", "shut", "show",
                                         "take", "break", "check", "hold", "opt", "plug", "follow", "wake", "grow",
                                         "fill", "figure", "pay", "sum", "wrap", "warm", "cool", "calm", "clean",
                                         "power", "start", "speed", "slow", "shake", "build", "back"]
    static let irregularPhrasal: Set<String> = ["took", "taken", "gave", "given", "broke", "broken", "held", "shown",
                                                "grew", "grown", "built", "woke", "woken", "paid"]
    static let afterParticle: Set<String> = ["a", "an", "the", "to", "your", "my", "our", "their", "his", "her", "its",
                                             "with", "and", "for", "of", "this", "that", "these", "those", "on", "in",
                                             "at", "from", "or", "now", "today", "again"]
    static let chicagoPrefixes: Set<String> = ["anti", "pre", "post", "re", "non", "co", "semi", "multi", "inter",
                                               "intra", "pro", "sub", "super", "un", "mid", "mis", "over", "under",
                                               "ultra", "neo", "pseudo", "quasi", "trans", "counter", "extra", "infra", "micro", "macro"]
    static let determiners: Set<String> = ["the", "a", "an", "my", "your", "our", "their", "his", "her", "its", "this", "that", "these", "those"]
    static let tens: Set<String> = ["twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"]
    static let abbreviations: Set<String> = ["e.g", "i.e", "etc", "vs", "v", "mr", "mrs", "ms", "dr", "st", "jr", "sr",
                                             "no", "vol", "fig", "approx", "inc", "ltd", "co", "u.s", "u.k"]
    static let pronounI: Set<String> = ["i", "i'm", "i've", "i'd", "i'll", "i’m", "i’ve", "i’d", "i’ll"]

    static func isPhrasalVerb(_ w: String) -> Bool {
        let w = w.lowercased()
        if irregularPhrasal.contains(w) { return true }
        for v in phrasalVerbs where w.hasPrefix(v) {
            let rest = w.dropFirst(v.count)
            let last = v.last.map(String.init) ?? ""
            let endings = ["", "s", "es", "ed", "d", "ing", "n", "en", last + "ed", last + "ing"]
            if endings.contains(String(rest)) { return true }
        }
        return false
    }
}

// MARK: - Engine

public enum TitleCaseEngine {

    public static func apply(_ text: String, guide: StyleGuide, dictionary: CustomDictionary = .init()) -> String {
        convert(text, guide: guide, dictionary: dictionary).text
    }

    /// Guide policy: is this lowercase word a minor word, and which class/threshold explains it.
    static func minorClass(_ w: String, _ g: StyleGuide) -> WordClass? {
        let art = Words.articles.contains(w), prep = Words.prepositions.contains(w), co = Words.coordinating.contains(w)
        let n = w.count
        switch g {
        case .plain:
            if art { return .article }
            if co { return .coordConj }
            if prep && n <= 3 { return .preposition }
        case .ap, .apa:
            if art { return .article }
            if co { return .coordConj }
            if (w == "as" || w == "if") { return .shortConj }
            if prep && n <= 3 { return .preposition }
        case .ama:
            if art { return .article }
            if ["and", "or", "for", "nor", "but"].contains(w) { return .coordConj }
            if prep && n <= 3 { return .preposition }
        case .chicago:
            if art { return .article }
            if ["and", "but", "for", "or", "nor"].contains(w) { return .coordConj }
            if prep || w == "to" || w == "as" { return .preposition }
        case .mla:
            if art { return .article }
            if co { return .coordConj }
            if prep { return .preposition }
        case .bluebook:
            if art { return .article }
            if co { return .coordConj }
            if Words.shortConjunctions.contains(w) && n <= 4 && w != "that" { return .shortConj }
            if prep && n <= 4 { return .preposition }
        case .nyt:
            if Words.nytLower.contains(w) { return art ? .article : (co ? .coordConj : .preposition) }
        case .sentence, .wikipedia:
            return nil
        }
        return nil
    }

    /// Letters threshold: prepositions/conjunctions longer than this are capitalized (length-based guides).
    static func lengthLimit(_ g: StyleGuide) -> Int? {
        switch g {
        case .plain, .ap, .apa, .ama: return 3
        case .bluebook: return 4
        default: return nil
        }
    }

    static func usesPhrasalRule(_ g: StyleGuide) -> Bool { g.isTitleCase && g != .bluebook }
    static func capitalizesLastWord(_ g: StyleGuide) -> Bool { g.isTitleCase && g != .bluebook }

    // MARK: Tokens

    struct Token {
        var text: String
        var isSpace: Bool
        var prefix = "", core = "", suffix = ""
        var isWord: Bool { !isSpace && !core.isEmpty }
    }

    static func isAlnum(_ c: Character) -> Bool { c.isLetter || c.isNumber }

    static func tokenize(_ s: String) -> [Token] {
        var out: [Token] = []
        var cur = ""
        var curSpace: Bool?
        for c in s {
            let sp = c.isWhitespace
            if curSpace == nil || curSpace == sp { cur.append(c); curSpace = sp } else {
                out.append(Token(text: cur, isSpace: curSpace!)); cur = String(c); curSpace = sp
            }
        }
        if let sp = curSpace { out.append(Token(text: cur, isSpace: sp)) }
        for i in out.indices where !out[i].isSpace {
            let t = out[i].text
            guard let first = t.firstIndex(where: isAlnum), let last = t.lastIndex(where: isAlnum) else { continue }
            out[i].prefix = String(t[..<first])
            out[i].core = String(t[first...last])
            out[i].suffix = String(t[t.index(after: last)...])
        }
        return out
    }

    static func capitalize(_ w: String) -> String {
        guard let i = w.firstIndex(where: { $0.isLetter }) else { return w }
        return String(w[..<i]) + String(w[i]).uppercased() + String(w[w.index(after: i)...])
    }

    static func hasDeliberateCaps(_ w: String) -> Bool {
        let letters = w.filter { $0.isLetter }
        guard let f = letters.first else { return false }
        return letters.dropFirst().contains(where: { $0.isUppercase }) || (f.isLowercase && letters.contains(where: { $0.isUppercase }))
    }

    // MARK: Convert

    public static func convert(_ input: String, guide g: StyleGuide, dictionary: CustomDictionary = .init()) -> CaseResult {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return CaseResult(text: "", words: [], guide: g, notes: []) }
        var notes: [String] = []
        let allCaps = text.contains(where: { $0.isLetter }) && !text.contains(where: { $0.isLowercase })
        if allCaps {
            text = text.lowercased()
            notes.append("The text was all capitals, so it was lowercased first; acronyms the app doesn't know need adding to your dictionary.")
        }
        var tokens = tokenize(text)
        let wordIdx = tokens.indices.filter { tokens[$0].isWord }
        let firstWord = wordIdx.first, lastWord = wordIdx.last
        var decisions: [WordDecision] = []
        var startsSubtitle = false
        var sawPhrasal = false, sawChicagoPrefix = false, sawHyphen = false, sawAs = false, sawBlueLast = false

        for (n, i) in wordIdx.enumerated() {
            var tok = tokens[i]
            // Subtitle / sentence start from the previous token run.
            let prevTokens = n == 0 ? [] : Array(tokens[(wordIdx[n - 1])..<i])
            if n > 0 { startsSubtitle = triggersStart(prevTokens, guide: g, previousCore: tokens[wordIdx[n - 1]].core) }
            if tok.prefix.contains("—") || tok.prefix.contains("–") { startsSubtitle = true }
            let isFirst = i == firstWord, isLast = i == lastWord
            let prevCore = n > 0 ? tokens[wordIdx[n - 1]].core : nil
            let nextCore = n + 1 < wordIdx.count ? tokens[wordIdx[n + 1]].core.lowercased() : nil
            let ctx = Context(guide: g, dictionary: dictionary, isFirst: isFirst, isLast: isLast,
                              startsSubtitle: startsSubtitle, prevCore: prevCore, nextCore: nextCore,
                              fullToken: tok.text, prefix: tok.prefix, suffix: tok.suffix)
            let r = caseToken(tok.core, ctx)
            tok.core = r.output
            tokens[i] = tok
            tokens[i].text = tok.prefix + r.output + tok.suffix
            decisions.append(WordDecision(id: n, original: r.original,
                                          output: r.output, rule: r.rule, explanation: r.explanation))
            if r.rule == .verbPhrasal { sawPhrasal = true }
            if r.chicagoPrefix { sawChicagoPrefix = true }
            if r.original.contains("-") { sawHyphen = true }
            if r.original.lowercased() == "as" { sawAs = true }
            if g == .bluebook, isLast, r.rule == .minorWord { sawBlueLast = true }
        }
        let out = tokens.map(\.text).joined()

        if sawPhrasal { notes.append("A short word after a verb was read as part of a phrasal verb (like “Log In”) and capitalized; if it is a preposition there, lowercase it.") }
        if sawChicagoPrefix { notes.append("Chicago lowercases the word after a prefix such as anti- or re-; proper nouns after a prefix (Pre-Columbian) need your dictionary.") }
        else if sawHyphen && g == .chicago { notes.append("Chicago capitalizes the second part of a compound unless it is a minor word or follows a prefix.") }
        if sawAs && (g == .chicago || g == .mla || g == .apa || g == .ap) { notes.append("“As” can be a preposition, conjunction or adverb; \(g.ruleName) treatment here follows the guide's usual lowercase choice.") }
        if sawBlueLast { notes.append("Bluebook rule 8 names only the first word and the word after a colon; a short last word stays lowercase.") }
        if !g.isTitleCase { notes.append("\(g.ruleName) keeps proper nouns capitalized, but the app can't recognise names on its own: add them to your custom dictionary.") }
        if g.isTitleCase, wordIdx.contains(where: { ["since", "until", "before", "after", "till", "like", "than"].contains(tokens[$0].core.lowercased()) }), g == .chicago || g == .mla {
            notes.append("Words such as since, until, before and after are lowercased as prepositions; capitalize them where they work as subordinating conjunctions.")
        }
        return CaseResult(text: out, words: decisions, guide: g, notes: notes)
    }

    static func triggersStart(_ run: [Token], guide g: StyleGuide, previousCore: String) -> Bool {
        let joined = run.map { $0.isWord ? $0.suffix : $0.text }.joined()
        if joined.contains("?") || joined.contains("!") { return true }
        if joined.contains(":") { return g != .wikipedia }
        if joined.contains("—") || joined.contains("–") { return g.isTitleCase }
        if run.dropFirst().contains(where: { !$0.isSpace && !$0.isWord && ($0.text == "-" || $0.text == "--") }) { return g.isTitleCase }
        if !g.isTitleCase, joined.contains(".") {
            let w = previousCore.lowercased()
            if Words.abbreviations.contains(w) || (w.count == 1 && w.first?.isLetter == true) { return false }
            return true
        }
        return false
    }

    struct Context {
        let guide: StyleGuide
        let dictionary: CustomDictionary
        let isFirst: Bool, isLast: Bool, startsSubtitle: Bool
        let prevCore: String?, nextCore: String?
        let fullToken: String, prefix: String, suffix: String
    }

    struct PartResult {
        var original: String, output: String, rule: CaseRule, explanation: String
        var chicagoPrefix = false
    }

    // MARK: Per token

    static func caseToken(_ core: String, _ c: Context) -> PartResult {
        let g = c.guide
        // Whole-token protections.
        if c.fullToken.contains("@") || c.fullToken.contains("://") || c.fullToken.lowercased().hasPrefix("www.") {
            return PartResult(original: core, output: core, rule: .url, explanation: "“\(core)” looks like a web address or email, so it is left as written.")
        }
        if let k = protected(core, c, withDot: c.suffix.hasPrefix(".")) { return k }

        // Split into parts on - / — –
        var parts: [String] = [], seps: [Character] = []
        var cur = ""
        for ch in core {
            if ch == "-" || ch == "/" || ch == "—" || ch == "–" { parts.append(cur); seps.append(ch); cur = "" } else { cur.append(ch) }
        }
        parts.append(cur)
        if parts.count == 1 { return casePart(core, c, position: .single) }

        var outs: [String] = [], explanations: [String] = []
        var rule: CaseRule = .other
        var chicagoPrefix = false
        for (j, p) in parts.enumerated() {
            let sepBefore: Character? = j > 0 ? seps[j - 1] : nil
            let firstLower = parts[0].lowercased()
            var pos: Position
            if j == 0 { pos = seps[0] == "-" ? .compoundFirst : .single }
            else if sepBefore == "—" || sepBefore == "–" { pos = .afterDash }
            else if sepBefore == "/" { pos = .single }
            else { pos = .compoundLater(first: firstLower, isLastPart: j == parts.count - 1) }
            // last-word forcing only for the final part, first-word forcing only for the first part
            let pc = Context(guide: g, dictionary: c.dictionary, isFirst: c.isFirst && j == 0, isLast: c.isLast && j == parts.count - 1,
                             startsSubtitle: (c.startsSubtitle && j == 0) || pos == .afterDash, prevCore: j == 0 ? c.prevCore : parts[j - 1],
                             nextCore: j == parts.count - 1 ? c.nextCore : parts[j + 1].lowercased(),
                             fullToken: c.fullToken, prefix: "", suffix: "")
            let r = p.isEmpty ? PartResult(original: p, output: p, rule: .other, explanation: "") : casePart(p, pc, position: pos)
            outs.append(r.output)
            if !r.explanation.isEmpty && !explanations.contains(r.explanation) { explanations.append(r.explanation) }
            if r.chicagoPrefix { chicagoPrefix = true }
            if j == 0 { rule = r.rule } else if r.rule == .hyphenSecond { rule = .hyphenSecond }
        }
        var joined = ""
        for (j, o) in outs.enumerated() { joined += o; if j < seps.count { joined.append(seps[j]) } }
        return PartResult(original: core, output: joined, rule: rule, explanation: explanations.joined(separator: " "), chicagoPrefix: chicagoPrefix)
    }

    enum Position: Equatable { case single, compoundFirst, compoundLater(first: String, isLastPart: Bool), afterDash }

    /// Dictionary, known acronyms, digits, dotted words, deliberate capitals.
    static func protected(_ w: String, _ c: Context, withDot: Bool) -> PartResult? {
        if let s = c.dictionary.spelling(for: w) ?? (withDot ? c.dictionary.spelling(for: w + ".").map { String($0.dropLast()) } : nil) {
            return PartResult(original: w, output: s, rule: .dictionary, explanation: "“\(s)” is in your custom dictionary, so its spelling is kept.")
        }
        let exclude = Lexicon.ambiguousBuiltIn
        if let s = Lexicon.lookup(w, in: Lexicon.builtIn, excluding: exclude) ?? (withDot ? Lexicon.lookup(w + ".", in: Lexicon.builtIn, excluding: exclude).map { String($0.dropLast()) } : nil) {
            return PartResult(original: w, output: s, rule: .keptCasing, explanation: "“\(s)” is a known acronym or brand name, so it keeps its usual spelling.")
        }
        let hasSep = w.contains("-") || w.contains("/") || w.contains("—") || w.contains("–")
        if hasSep { return nil }
        if w.contains(where: { $0.isNumber }) {
            return PartResult(original: w, output: w, rule: .number, explanation: "“\(w)” contains digits, so it is left as written.")
        }
        if w.contains(".") {
            return PartResult(original: w, output: w, rule: .keptCasing, explanation: "“\(w)” is an abbreviation or dotted name, so it is left as written.")
        }
        if hasDeliberateCaps(w) {
            return PartResult(original: w, output: w, rule: .keptCasing, explanation: "“\(w)” is written with deliberate capitals (an acronym or brand), so its casing is kept.")
        }
        return nil
    }

    static func casePart(_ w: String, _ c: Context, position: Position) -> PartResult {
        let g = c.guide, name = g.ruleName
        if let k = protected(w, c, withDot: false) { return k }
        let lower = w.lowercased()
        func cap(_ rule: CaseRule, _ e: String) -> PartResult { PartResult(original: w, output: capitalize(lower), rule: rule, explanation: e) }
        func low(_ rule: CaseRule, _ e: String) -> PartResult { PartResult(original: w, output: lower, rule: rule, explanation: e) }
        let C = capitalize(lower)

        if Words.pronounI.contains(lower) {
            return cap(.properNounKept, "The pronoun “I” is always capitalized.")
        }
        // Sentence-style guides.
        if !g.isTitleCase {
            if c.isFirst { return cap(.firstWord, "\(name) capitalizes the first word, so “\(C)” is capitalized.") }
            if c.startsSubtitle { return cap(.afterColon, "\(name) capitalizes the first word of a new sentence or subtitle, so “\(C)” is capitalized.") }
            return low(.sentenceLower, "\(name) capitalizes only the first word and proper nouns, so “\(lower)” is lowercase.")
        }
        // 'n' as in Rock 'n' Roll
        if lower == "n", c.fullToken.contains("'") || c.fullToken.contains("’") {
            if !c.isFirst && !c.isLast { return low(.minorWord, "“'n'” stands for “and”, so it stays lowercase.") }
        }
        if c.isFirst { return cap(.firstWord, "\(name) always capitalizes the first word, so “\(C)” is capitalized.") }
        if c.startsSubtitle { return cap(.afterColon, "\(name) capitalizes the first word of a subtitle or new sentence, so “\(C)” is capitalized.") }
        if c.isLast && capitalizesLastWord(g) { return cap(.lastWord, "\(name) capitalizes the last word, so “\(C)” is capitalized.") }

        switch position {
        case .compoundFirst:
            return cap(.hyphenFirst, "\(name) capitalizes the first part of a hyphenated compound, so “\(C)” is capitalized.")
        case .compoundLater(let first, _):
            if g == .chicago {
                if Words.chicagoPrefixes.contains(first) {
                    var r = low(.hyphenSecond, "Chicago lowercases the part after a prefix such as anti- or re-, so “\(lower)” stays lowercase.")
                    r.chicagoPrefix = true
                    return r
                }
                if Words.tens.contains(first) {
                    return low(.hyphenSecond, "Chicago lowercases the second part of a spelled-out hyphenated number, so “\(lower)” stays lowercase.")
                }
            }
            if minorClass(lower, g) != nil || (g.isTitleCase && lower == "to" && g != .nyt && g != .bluebook) {
                return low(.hyphenSecond, "\(name) keeps minor words lowercase inside a hyphenated compound, so “\(lower)” stays lowercase.")
            }
            return cap(.hyphenSecond, "\(name) capitalizes each major part of a hyphenated compound, so “\(C)” is capitalized.")
        default: break
        }

        // Phrasal verb particle.
        if usesPhrasalRule(g), Words.particles.contains(lower), let prev = c.prevCore, Words.isPhrasalVerb(prev),
           minorClass(lower, g) != nil, c.nextCore.map({ Words.afterParticle.contains($0) }) ?? true {
            return cap(.verbPhrasal, "“\(C)” works as an adverb in the phrasal verb “\(capitalize(prev.lowercased())) \(C)”, so \(name) capitalizes it.")
        }

        if Words.prepositions.contains(lower), !Words.coordinating.contains(lower), lower != "to", lower != "as",
           let prev = c.prevCore?.lowercased(), Words.determiners.contains(prev), minorClass(lower, g) != nil {
            return cap(.majorWord, "“\(C)” follows “\(prev)”, so it is read as a noun and \(name) capitalizes it.")
        }
        if let cls = minorClass(lower, g) {
            if lower == "to" { return low(.toInfinitive, "\(name) lowercases “to”, whether it is a preposition or part of an infinitive.") }
            return low(.minorWord, minorExplanation(cls, lower, g))
        }
        if g == .mla && lower == "to" { return low(.toInfinitive, "MLA 9 lowercases “to”, whether it is a preposition or part of an infinitive.") }
        if let limit = lengthLimit(g), Words.prepositions.contains(lower) || Words.shortConjunctions.contains(lower) || Words.coordinating.contains(lower) {
            let what = Words.prepositions.contains(lower) ? "prepositions" : "conjunctions"
            return cap(.longPreposition, "\(name) capitalizes \(what) of \(limit + 1) letters or more, so “\(C)” is capitalized.")
        }
        if g == .nyt { return cap(.majorWord, "The New York Times capitalizes every word that isn't on its short lowercase list, so “\(C)” is capitalized.") }
        if (g == .chicago || g == .mla) && Words.subordinating.contains(lower) {
            return cap(.majorWord, "\(name) capitalizes subordinating conjunctions, so “\(C)” is capitalized.")
        }
        if (g == .chicago || g == .ama) && (lower == "so" || lower == "yet") {
            return cap(.majorWord, "\(name) lowercases only and, but, for, or and nor among conjunctions, so “\(C)” is capitalized.")
        }
        return cap(.majorWord, "\(name) capitalizes major words such as nouns, verbs, adjectives, adverbs and pronouns, so “\(C)” is capitalized.")
    }

    static func minorExplanation(_ cls: WordClass, _ w: String, _ g: StyleGuide) -> String {
        let name = g.ruleName
        if g == .nyt { return "The New York Times keeps “\(w)” lowercase: it is on the Times list of short words that stay lowercase." }
        switch cls {
        case .article:
            return "\(name) lowercases articles (a, an, the) inside a title, so “\(w)” stays lowercase."
        case .coordConj:
            return "\(name) lowercases coordinating conjunctions such as and, but and or, so “\(w)” stays lowercase."
        case .shortConj:
            let n = lengthLimit(g) ?? 3
            return "\(name) lowercases conjunctions of \(n == 4 ? "four" : "three") letters or fewer, so “\(w)” stays lowercase."
        case .preposition:
            if let n = lengthLimit(g) {
                return "\(name) lowercases prepositions of \(n == 4 ? "four" : "three") letters or fewer, so “\(w)” stays lowercase."
            }
            if g == .chicago && w == "as" { return "Chicago lowercases “as” in every use, so it stays lowercase." }
            return "\(name) lowercases prepositions of any length, so “\(w)” stays lowercase."
        }
    }

    // MARK: Ambiguities

    public static let ambiguityNotes: [StyleGuide: [String]] = [
        .plain: [
            "Not a published guide: a common default that lowercases articles, coordinating conjunctions and prepositions of three letters or fewer.",
        ],
        .ap: [
            "AP lists prepositions and conjunctions of three letters or fewer as lowercase; short subordinating conjunctions (as, if) are lowercased here too.",
            "Short words used as adverbs in phrasal verbs (Log In, Set Up) are capitalized; the app spots these only after common verbs.",
        ],
        .apa: [
            "APA capitalizes every word of four letters or more; minor words of three letters or fewer stay lowercase, including as and if.",
            "Both parts of a hyphenated major-word compound are capitalized (Self-Report); a short minor part stays lowercase (Up-to-Date).",
        ],
        .chicago: [
            "Chicago lowercases prepositions of any length, but capitalizes them when used as adverbs or adjectives; the app detects only phrasal verbs after common verbs.",
            "Since, until, before and after are lowercased as prepositions even where they act as subordinating conjunctions.",
            "The part after a prefix (anti-, pre-, re-) and the second part of spelled-out numbers (Twenty-first) stay lowercase; proper nouns need the dictionary.",
            "Chicago lowercases only and, but, for, or and nor among conjunctions, so So and Yet are capitalized.",
            "A preposition right after an article or possessive (the Past, the Down Side) is read as a noun and capitalized.",
        ],
        .mla: [
            "MLA lowercases prepositions of any length; adverbs and particles in phrasal verbs are capitalized only after common verbs the app knows.",
            "As is lowercased as a preposition; capitalize it yourself where it is a subordinating conjunction.",
            "A preposition right after an article or possessive (the Past, the Down Side) is read as a noun and capitalized.",
        ],
        .bluebook: [
            "Rule 8 names only the first word and the word after a colon, so a short last word (with, for) stays lowercase.",
            "Conjunctions of four or fewer letters include as, if, than and when; that is kept capitalized because it is usually a pronoun in titles.",
        ],
        .ama: [
            "AMA lowercases only the coordinating conjunctions and, or, for, nor and but, so So and Yet are capitalized.",
            "Prepositions of four letters or more are capitalized (With, From); phrasal-verb particles are capitalized after common verbs.",
        ],
        .nyt: [
            "Times headline style lowercases a fixed list; words like Is, Be, Up, Off, Out and No are always capitalized.",
            "In and On are capitalized when part of a phrasal verb after a common verb.",
        ],
        .wikipedia: [
            "Wikipedia uses sentence case and lowercases the word after a colon unless it is a proper noun.",
            "Proper nouns can't be detected automatically: add names to your custom dictionary.",
        ],
        .sentence: [
            "Capitalizes the first word of each sentence and the first word after a colon.",
            "Proper nouns can't be detected automatically: add names to your custom dictionary.",
        ],
    ]
}
