//
//  Models.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import Foundation

// Dictionaries for storing presets...

let exceptionsForMLA_Chicago = [
    "in", "of", "to", "and", "but", "for", "nor", "or", "nor", "so", "yet", "the", "a", "an"
]

let exceptionsForAPA_AP = [
    "against", "between", "in", "of", "to", "and", "but", "for", "nor", "or", "nor", "so", "yet", "the", "a", "an"
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
        var target: [String]
        
        switch selectedOutput {
        case .mla:
            target = exceptionsForMLA_Chicago
        case .apa:
            target = exceptionsForAPA_AP
        }
        
        self.inputLine = self.inputLine.capitalized
        
        for exception in target {
            // Apply the exceptions...
            self.inputLine = self.inputLine.replacingOccurrences(of: " \(exception.capitalizingFirstLetter()) ", with: " \(exception) ")
        }
        
        // Capitalize the first character despite the selected style and remove all the blankspaces...
        return self.inputLine.trimmingCharacters(in: .whitespacesAndNewlines).capitalizingFirstLetter()
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
