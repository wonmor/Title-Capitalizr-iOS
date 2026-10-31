//
//  EssayAssistant.swift
//  Title Capitalizr
//
//  Optional on-device help for the parts of an essay the rule-based analyser
//  couldn't pin down: the heading fields, the title and where the source list
//  starts. The model only proposes; every suggestion is shown to the user as
//  "Suggested" until they confirm or edit it. Nothing leaves the device.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
@Generable
struct EssayFrontMatterGuess {
    @Guide(description: "The student's full name exactly as written, or an empty string if absent")
    var authorName: String
    @Guide(description: "The instructor's name with title (for example Professor Lee), or an empty string")
    var instructor: String
    @Guide(description: "The course name or code, or an empty string")
    var course: String
    @Guide(description: "The date exactly as written, or an empty string")
    var date: String
    @Guide(description: "The essay's title exactly as written, without quotation marks")
    var title: String
    @Guide(description: "Number of the first numbered line that is a bibliography or works-cited entry, or 0 when there is none")
    var firstCitationLine: Int
}
#endif

struct EssaySuggestion: Equatable {
    var heading = HeadingFields()
    var title = ""
    /// Index into `EssayStructure.body` where the citation list starts, if the model found one.
    var referencesStartInBody: Int?
}

@MainActor
enum EssayAssistant {
    /// Asks the on-device model about the opening lines and the closing lines of the essay.
    static func suggest(for structure: EssayStructure, source: SourceDocument, availability: SmartModelAvailability) async -> EssaySuggestion? {
        guard availability.isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            let opening = source.paragraphs.prefix(8).map { String($0.text.prefix(200)) }
            let bodyTail = Array(structure.body.suffix(15))
            let tailStart = structure.body.count - bodyTail.count
            var prompt = "Opening lines of the essay:\n"
            for (i, l) in opening.enumerated() { prompt += "[\(i + 1)] \(l)\n" }
            prompt += "\nClosing lines of the essay, numbered:\n"
            for (i, p) in bodyTail.enumerated() { prompt += "(\(i + 1)) \(String(p.text.prefix(160)))\n" }
            do {
                let session = LanguageModelSession(instructions: """
                    You read the first and last lines of a student essay and identify its parts. \
                    Copy text exactly; never invent a name, course, date or title that isn't in the lines. \
                    For firstCitationLine use the numbers in parentheses from the closing lines; a citation entry \
                    looks like "Surname, First. Title. Publisher, Year." Use 0 if no closing line is a citation.
                    """)
                let response = try await session.respond(to: prompt, generating: EssayFrontMatterGuess.self,
                                                         options: GenerationOptions(temperature: 0.0))
                let g = response.content
                let allText = source.paragraphs.prefix(12).map(\.text).joined(separator: "\n")
                // Keep only values that literally appear in the document.
                func grounded(_ s: String) -> String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !t.isEmpty && allText.localizedCaseInsensitiveContains(t) ? t : ""
                }
                var suggestion = EssaySuggestion()
                suggestion.heading = HeadingFields(name: grounded(g.authorName), instructor: grounded(g.instructor),
                                                   course: grounded(g.course), date: grounded(g.date))
                suggestion.title = grounded(g.title)
                if g.firstCitationLine > 0, g.firstCitationLine <= bodyTail.count {
                    suggestion.referencesStartInBody = tailStart + g.firstCitationLine - 1
                }
                return suggestion
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }
}
