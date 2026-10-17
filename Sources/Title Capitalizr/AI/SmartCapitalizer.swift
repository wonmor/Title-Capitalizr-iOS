//
//  SmartCapitalizer.swift
//  Title Capitalizr
//
//  On-device "Smart Capitalize" powered by Apple's Foundation Models framework
//  (Apple Intelligence, iOS 26 / macOS 26 and later). The rule-based engine in
//  Models.swift stays the default path; this class is an optional extra that is
//  only offered when `SystemLanguageModel.default` reports `.available`.
//  Nothing here ever leaves the device: there are no network calls and no keys.
//

import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device model can be used, with a user-facing explanation when it can't.
enum SmartModelAvailability: Equatable {
    case available
    case unavailable(reason: String)

    var isAvailable: Bool { self == .available }

    var message: String {
        switch self {
        case .available: return "Apple Intelligence is ready."
        case .unavailable(let reason): return reason
        }
    }
}

/// Result of a smart capitalisation. `usedFallback` is true when the rule-based
/// engine produced the text (model unavailable, disabled or failed).
struct SmartCapitalizeResult: Equatable {
    let title: String
    let usedFallback: Bool
}

#if canImport(FoundationModels)
@available(iOS 26, macOS 26, *)
@Generable
struct AlternativeTitles {
    @Guide(description: "Exactly three alternative titles, each already in the requested title case", .count(3))
    var titles: [String]
}

@available(iOS 26, macOS 26, *)
@Generable
struct GrammarReview {
    @Guide(description: "The title with spelling and grammar corrected, leaving wording and meaning untouched; identical to the input when nothing is wrong")
    var correctedTitle: String
    @Guide(description: "One short sentence explaining what changed, or an empty string when nothing changed")
    var explanation: String
}
#endif

@MainActor
final class SmartCapitalizer: ObservableObject {

    /// Injected availability probe so the fallback can be unit-tested without Apple Intelligence.
    private let availabilityProvider: () -> SmartModelAvailability

    init(availabilityProvider: @escaping () -> SmartModelAvailability = SmartCapitalizer.systemAvailability) {
        self.availabilityProvider = availabilityProvider
    }

    var availability: SmartModelAvailability { availabilityProvider() }

    /// Reads the live state of the system model. Safe to call on any OS version.
    nonisolated static func systemAvailability() -> SmartModelAvailability {
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    return .unavailable(reason: "Apple Intelligence is not available on this device.")
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: "Turn on Apple Intelligence in Settings to use Smart Capitalize.")
                case .modelNotReady:
                    return .unavailable(reason: "Apple Intelligence is still downloading its model. Try again later.")
                @unknown default:
                    return .unavailable(reason: "Apple Intelligence is not available right now.")
                }
            }
        }
        #endif
        return .unavailable(reason: "Apple Intelligence requires iOS 26 or macOS 26.")
    }

    // MARK: Smart Capitalize

    /// Applies the selected style guide with the on-device model. Falls back to the
    /// deterministic engine whenever the model is unavailable or anything fails.
    func capitalize(_ title: String, style: DesiredOutput) async -> SmartCapitalizeResult {
        let fallback = SmartCapitalizeResult(title: Capitalizer(inputLine: title).capitalizeTitle(selectedOutput: style),
                                             usedFallback: true)
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, availability.isAvailable else { return fallback }
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: Self.capitalizeInstructions(style: style))
                let prompt = "Title: \(trimmed)\n\nReturn only the title in \(style.displayName) title case."
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.0))
                let cleaned = Self.clean(response.content)
                guard !cleaned.isEmpty, Self.looksLikeSameTitle(cleaned, as: trimmed) else { return fallback }
                return SmartCapitalizeResult(title: cleaned, usedFallback: false)
            } catch {
                return fallback
            }
        }
        #endif
        return fallback
    }

    /// Three alternative titles in the selected style, or an empty array when the model is unavailable.
    func suggestAlternatives(for title: String, style: DesiredOutput) async -> [String] {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, availability.isAvailable else { return [] }
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: """
                    You are an editor who proposes alternative titles for essays, articles and papers. \
                    Keep the subject and tone of the original. Each alternative must be a complete title of at most twelve words, \
                    different in wording from the original and from each other. \
                    Write every alternative using \(style.styleGuideDescription)
                    """)
                let response = try await session.respond(to: "Original title: \(trimmed)",
                                                         generating: AlternativeTitles.self,
                                                         options: GenerationOptions(temperature: 0.8))
                return response.content.titles.map(Self.clean).filter { !$0.isEmpty }
            } catch {
                return []
            }
        }
        #endif
        return []
    }

    /// Asks the model for a grammar/spelling corrected version of the title. Returns nil when
    /// nothing should change or the model is unavailable. The caller presents it as a suggestion.
    func reviewGrammar(_ title: String) async -> GrammarIssue? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, availability.isAvailable else { return nil }
        #if canImport(FoundationModels)
        if #available(iOS 26, macOS 26, *) {
            do {
                let session = LanguageModelSession(instructions: """
                    You are a careful copy editor. Correct only spelling, subject-verb agreement, articles (a/an), \
                    doubled words and missing apostrophes in the title you are given. Never change word choice, \
                    word order, meaning or capitalisation beyond what grammar requires. \
                    If the title is already correct, return it unchanged with an empty explanation.
                    """)
                let response = try await session.respond(to: "Title: \(trimmed)",
                                                         generating: GrammarReview.self,
                                                         options: GenerationOptions(temperature: 0.0))
                let corrected = Self.clean(response.content.correctedTitle)
                guard !corrected.isEmpty, corrected != trimmed,
                      corrected.lowercased() != trimmed.lowercased() else { return nil }
                let ns = title as NSString
                let range = ns.range(of: trimmed)
                let explanation = response.content.explanation.trimmingCharacters(in: .whitespacesAndNewlines)
                return GrammarIssue(kind: .aiSuggestion, range: range, original: trimmed, replacements: [corrected],
                                    message: explanation.isEmpty ? "Suggested: “\(corrected)”" : explanation)
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    // MARK: Helpers

    nonisolated static func capitalizeInstructions(style: DesiredOutput) -> String {
        """
        You convert a single title into title case. Apply \(style.styleGuideDescription) \
        Keep proper nouns, brand names and acronyms exactly as they are normally written (for example NASA, iPhone, macOS, eBay, McDonald's). \
        In hyphenated compounds capitalize each part that would be capitalized on its own (Self-Esteem, Follow-Up) but not articles or prepositions after the hyphen. \
        A subtitle after a colon, em dash or question mark starts with a capital letter. \
        Never add, remove or reorder words, never change punctuation, and never explain. Output only the converted title.
        """
    }

    nonisolated static func clean(_ text: String) -> String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let firstLine = t.components(separatedBy: .newlines).first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            t = firstLine.trimmingCharacters(in: .whitespaces)
        }
        for prefix in ["Title:", "title:"] where t.hasPrefix(prefix) { t = String(t.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("“") && t.hasSuffix("”")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }

    /// Guards against the model rewriting the title instead of just re-casing it.
    nonisolated static func looksLikeSameTitle(_ candidate: String, as original: String) -> Bool {
        func normalize(_ s: String) -> String {
            s.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return normalize(candidate) == normalize(original)
    }
}
