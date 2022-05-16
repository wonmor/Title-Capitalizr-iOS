//
//  Models.swift
//  Title Capitalizr
//
//  Created by John Seong on 2022-05-16.
//

import Foundation

enum DesiredOutput: String, CaseIterable, Identifiable {
    case mla, apa, chicago
    var id: Self { self }
}

final class Capitalizer: ObservableObject {
    init(selectedOutput: DesiredOutput, inputLine: String) {
        self.selectedOutput = selectedOutput
        self.inputLine = inputLine
    }
    @Published var selectedOutput: DesiredOutput
    @Published var inputLine: String
}
