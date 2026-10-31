//
//  Models.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import Foundation

// Minor words stay lowercase unless they open or close the title or a subtitle.

/// MLA 9 and Chicago 17: articles, coordinating conjunctions, the "to" of infinitives and
/// prepositions of any length. Short words that are usually adverbs or particles in titles
/// ("Up", "Out", "Off", "Down", "Over") stay capitalized.
let exceptionsForMLA_Chicago = [
    "a", "an", "the",
    "and", "but", "for", "nor", "or", "so", "yet",
    "about", "above", "across", "after", "against", "along", "amid", "among", "around", "as", "at",
    "before", "behind", "below", "beneath", "beside", "besides", "between", "beyond", "by",
    "despite", "during", "except", "from", "in", "inside", "into", "of", "on", "onto", "opposite",
    "outside", "per", "than", "through", "throughout", "to", "toward", "towards", "under", "underneath",
    "unlike", "upon", "versus", "via", "vs", "vs.", "with", "within", "without"
]

/// APA 7 and AP: only minor words of three letters or fewer stay lowercase.
let exceptionsForAPA_AP = [
    "a", "an", "the",
    "and", "as", "but", "for", "if", "nor", "or", "so", "yet",
    "at", "by", "in", "of", "off", "on", "per", "to", "up", "via"
]

// This is where the actual logic for the app starts...

enum DesiredOutput: String, CaseIterable, Identifiable {
    case mla, apa
    var id: Self { self }

    /// Human readable name shown in the UI.
    var displayName: String {
        switch self {
        case .mla: return "MLA and Chicago"
        case .apa: return "APA and AP"
        }
    }

    /// The style-guide description handed to the on-device model.
    var styleGuideDescription: String {
        switch self {
        case .mla:
            return "MLA / Chicago Manual of Style title case: capitalize the first and last word, every noun, pronoun, verb, adjective, adverb and subordinating conjunction; lowercase articles (a, an, the), coordinating conjunctions (and, but, for, nor, or, so, yet) and prepositions of any length unless they begin or end the title or subtitle."
        case .apa:
            return "APA / AP style title case: capitalize the first and last word, every major word (nouns, verbs, adjectives, adverbs, pronouns) and every word of four letters or more; lowercase articles, coordinating conjunctions and prepositions of three letters or fewer unless they begin or end the title or subtitle."
        }
    }
}

/// The original, deterministic rule-based title-case engine. This is always the
/// default path: it runs instantly, offline and gives the same answer every time.
final class Capitalizer: ObservableObject {
    init(inputLine: String) {
        self.inputLine = inputLine
    }
    
    @Published var inputLine: String
    
    func capitalizeTitle(selectedOutput: DesiredOutput) -> String {
        TitleCaser.apply(inputLine, style: selectedOutput)
    }
}

/// Word-by-word title case. Keeps acronyms and brand spellings (NASA, iPhone, McDonald's),
/// capitalizes the first and last word and the first word of a subtitle, and handles
/// hyphenated compounds and quoted words.
enum TitleCaser {
    static func apply(_ input: String, style: DesiredOutput) -> String {
        let minor = Set(style == .mla ? exceptionsForMLA_Chicago : exceptionsForAPA_AP)
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        // ALL CAPS input carries no casing information: start from lowercase.
        if !text.contains(where: { $0.isLowercase }) { text = text.lowercased() }
        let tokens = text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
        var out: [String] = []
        var startsSubtitle = true
        for (i, token) in tokens.enumerated() {
            let isLast = i == tokens.count - 1
            let parts = token.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
            var casedParts: [String] = []
            for (j, part) in parts.enumerated() {
                let forceCap = (j == 0 && startsSubtitle) || (j == parts.count - 1 && isLast) || (j > 0 && !minor.contains(core(part).lowercased()))
                casedParts.append(caseWord(part, forceCapital: forceCap, minor: minor, inCompound: j > 0))
            }
            out.append(casedParts.joined(separator: "-"))
            if let last = token.last { startsSubtitle = ":?!—–".contains(last) } else { startsSubtitle = false }
            if token == "—" || token == "–" || token == "-" { startsSubtitle = true }
        }
        return out.joined(separator: " ")
    }

    /// The letters of a token without surrounding quotes, brackets or punctuation.
    static func core(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'’")))
            .trimmingCharacters(in: CharacterSet(charactersIn: "'’"))
    }

    private static func caseWord(_ word: String, forceCapital: Bool, minor: Set<String>, inCompound: Bool) -> String {
        let c = core(word)
        guard !c.isEmpty else { return word }
        // Keep words that already carry deliberate casing (NASA, iPhone, eBay, McDonald's) or digits / dots.
        let tail = c.dropFirst()
        if tail.contains(where: { $0.isUppercase }) || c.contains(where: { $0.isNumber }) || c.contains(".") { return word }
        if word.contains("@") || word.lowercased().hasPrefix("http") || word.lowercased().hasPrefix("www.") { return word }
        let lower = c.lowercased()
        if !forceCapital, minor.contains(lower) {
            return word.replacingOccurrences(of: c, with: lower)
        }
        if inCompound, !forceCapital { return word.replacingOccurrences(of: c, with: lower) }
        return word.replacingOccurrences(of: c, with: c.prefix(1).uppercased() + c.dropFirst())
    }
}

extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).capitalized + dropFirst()
    }
    
    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}
