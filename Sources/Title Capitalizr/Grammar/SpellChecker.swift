//
//  SpellChecker.swift
//  Title Capitalizr
//
//  Thin wrapper around the system spell checker: NSSpellChecker on macOS and
//  UITextChecker on iOS. Both are entirely on-device.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct SpellChecker {
    var language: String = "en"
    /// Words the checker should never flag (brand names, proper nouns the app knows about).
    var ignoredWords: Set<String> = ["Capitalizr", "Capitalzr", "iPhone", "iPad", "macOS", "iOS"]

    @MainActor
    func check(_ text: String) -> [GrammarIssue] {
        var issues: [GrammarIssue] = []
        let ns = text as NSString
        var offset = 0
        var guard_ = 0
        while offset < ns.length, guard_ < 200 {
            guard_ += 1
            let range = misspelledRange(in: text, startingAt: offset)
            guard range.location != NSNotFound, range.length > 0 else { break }
            let word = ns.substring(with: range)
            offset = range.location + range.length
            if ignoredWords.contains(word) || word.count < 2 { continue }
            // Skip words that look like acronyms or contain digits.
            if word == word.uppercased() || word.rangeOfCharacter(from: .decimalDigits) != nil { continue }
            let suggestions = guesses(for: range, in: text)
            issues.append(GrammarIssue(kind: .spelling, range: range, original: word,
                                       replacements: suggestions,
                                       message: suggestions.isEmpty ? "“\(word)” may be misspelled." : "Did you mean “\(suggestions[0])”?"))
        }
        return issues
    }

    @MainActor
    private func misspelledRange(in text: String, startingAt offset: Int) -> NSRange {
        #if os(macOS)
        return NSSpellChecker.shared.checkSpelling(of: text, startingAt: offset, language: language, wrap: false,
                                                   inSpellDocumentWithTag: 0, wordCount: nil)
        #else
        let checker = UITextChecker()
        let ns = text as NSString
        return checker.rangeOfMisspelledWord(in: text, range: NSRange(location: 0, length: ns.length),
                                             startingAt: offset, wrap: false, language: language)
        #endif
    }

    @MainActor
    private func guesses(for range: NSRange, in text: String) -> [String] {
        #if os(macOS)
        let g = NSSpellChecker.shared.guesses(forWordRange: range, in: text, language: language, inSpellDocumentWithTag: 0) ?? []
        #else
        let g = UITextChecker().guesses(forWordRange: range, in: text, language: language) ?? []
        #endif
        return Array(g.prefix(3))
    }
}
