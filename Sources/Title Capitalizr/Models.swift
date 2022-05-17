//
//  Models.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import Foundation

// Dictionaries for storing presets...

let exceptionsForMLA = [
    "against", "between", "in", "of", "to", "and", "but", "for", "nor", "or", "so", "yet"
]

let exceptionsForAPA = [
    "against", "between", "in", "of", "to", "and", "but", "for", "nor", "or", "so", "yet"
]

let exceptionsForChicago = [
    "against", "between", "in", "of", "to", "and", "but", "for", "nor", "or", "so", "yet"
]

// This is where the actual logic for the app starts...

enum DesiredOutput: String, CaseIterable, Identifiable {
    case mla, apa, chicago
    var id: Self { self }
}

final class Capitalizer: ObservableObject {
    init(inputLine: String) {
        self.inputLine = inputLine
    }
    
    @Published var inputLine: String
    
    func capitalizeTitle(selectedOutput: DesiredOutput) -> String {
        var target: [String]
        
        switch selectedOutput {
        case .mla:
            target = exceptionsForMLA
        case .apa:
            target = exceptionsForAPA
        case .chicago:
            target = exceptionsForChicago
        }
        
        self.inputLine = self.inputLine.capitalized
        
        for exception in target {
            self.inputLine = self.inputLine.replacingOccurrences(of: exception.capitalizingFirstLetter(), with: exception)
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
