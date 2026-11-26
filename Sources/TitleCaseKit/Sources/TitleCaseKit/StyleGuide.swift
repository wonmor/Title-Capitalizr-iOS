import Foundation

/// A capitalization style guide.
public enum StyleGuide: String, CaseIterable, Codable, Identifiable, Sendable {
    case plain, ap, apa, chicago, mla, bluebook, ama, nyt, wikipedia, sentence

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .plain: return "Title Case"
        case .ap: return "AP"
        case .apa: return "APA 7"
        case .chicago: return "Chicago 18"
        case .mla: return "MLA 9"
        case .bluebook: return "Bluebook"
        case .ama: return "AMA 11"
        case .nyt: return "New York Times"
        case .wikipedia: return "Wikipedia"
        case .sentence: return "Sentence case"
        }
    }

    /// Up to 10 characters, for chips.
    public var shortName: String {
        switch self {
        case .plain: return "Title"
        case .ap: return "AP"
        case .apa: return "APA"
        case .chicago: return "Chicago"
        case .mla: return "MLA"
        case .bluebook: return "Bluebook"
        case .ama: return "AMA"
        case .nyt: return "NYT"
        case .wikipedia: return "Wikipedia"
        case .sentence: return "Sentence"
        }
    }

    /// Name used inside explanations ("APA 7 lowercases ...").
    var ruleName: String {
        switch self {
        case .plain: return "Standard title case"
        case .nyt: return "The New York Times"
        case .sentence: return "Sentence case"
        case .wikipedia: return "Wikipedia style"
        default: return displayName
        }
    }

    public var summary: String {
        switch self {
        case .plain: return "Capitalizes every word except articles, coordinating conjunctions and prepositions of three letters or fewer."
        case .ap: return "Associated Press: capitalizes words of four or more letters; lowercases articles and conjunctions or prepositions of three letters or fewer."
        case .apa: return "APA 7: capitalizes words of four letters or more and both parts of hyphenated major words; lowercases short articles, conjunctions and prepositions."
        case .chicago: return "Chicago Manual of Style: lowercases articles, prepositions of any length, and, but, for, or, nor, and the words to and as."
        case .mla: return "MLA Handbook: lowercases articles, prepositions of any length, coordinating conjunctions and the to of infinitives."
        case .bluebook: return "Bluebook rule 8: lowercases articles, conjunctions and prepositions of four or fewer letters unless they begin the title or follow a colon."
        case .ama: return "AMA Manual of Style: lowercases articles, coordinating conjunctions, prepositions of three or fewer letters and the to of infinitives."
        case .nyt: return "New York Times headline style: capitalizes every word except a short fixed list (a, and, as, at, but, by, en, for, if, in, of, on, or, the, to, vs., via)."
        case .wikipedia: return "Wikipedia titles and headings: sentence case, with only the first word and proper nouns capitalized."
        case .sentence: return "Capitalizes only the first word, the first word after a colon and proper nouns or acronyms."
        }
    }

    public var isFree: Bool { self == .plain || self == .apa || self == .mla }
    public var isTitleCase: Bool { self != .sentence && self != .wikipedia }
    public static var freeGuides: [StyleGuide] { allCases.filter(\.isFree) }

    /// Notes on where the guide is ambiguous and which choice this engine makes.
    public var ambiguities: [String] { TitleCaseEngine.ambiguityNotes[self] ?? [] }
}
