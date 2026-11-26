import Foundation

/// Words whose exact spelling must be kept (brand names, acronyms, proper nouns).
public struct CustomDictionary: Codable, Equatable, Sendable {
    public var words: [String]

    public init(words: [String] = []) { self.words = words }

    /// Case-insensitive lookup of a kept spelling. Handles a trailing possessive ('s).
    public func spelling(for word: String) -> String? {
        Lexicon.lookup(word, in: words)
    }
}

enum Lexicon {
    static func lookup(_ word: String, in list: [String], excluding: Set<String> = []) -> String? {
        guard !word.isEmpty else { return nil }
        let key = word.lowercased()
        if let hit = list.first(where: { $0.lowercased() == key && !excluding.contains($0) }) { return hit }
        for suffix in ["'s", "’s"] where key.hasSuffix(suffix) && key.count > suffix.count {
            let stem = String(key.dropLast(suffix.count))
            if let hit = list.first(where: { $0.lowercased() == stem && !excluding.contains($0) }) {
                return hit + String(word.suffix(suffix.count))
            }
        }
        return nil
    }

    /// Built-in acronyms and brand spellings, restored case-insensitively ("nasa" -> "NASA").
    static let builtIn: [String] = [
        "NASA", "FBI", "CIA", "USA", "UK", "EU", "UN", "AI", "API", "CEO", "CFO", "CTO", "PhD", "MBA",
        "iOS", "macOS", "iPadOS", "watchOS", "tvOS", "visionOS", "iPhone", "iPad", "iPod", "iCloud", "iMac",
        "YouTube", "LinkedIn", "GitHub", "PayPal", "eBay", "TikTok", "WhatsApp", "ChatGPT", "OpenAI",
        "COVID-19", "DNA", "RNA", "HIV", "AIDS", "NATO", "TV", "PC", "URL", "HTML", "CSS", "JSON", "SQL", "PDF",
        "GPS", "USB", "FAQ", "DIY", "NFL", "NBA", "MLB", "NHL", "BBC", "CNN", "UNESCO", "WHO", "US", "U.S.", "U.K.",
    ]
    /// Built-ins that collide with ordinary words ("us", "who"): only kept when typed in capitals.
    static let ambiguousBuiltIn: Set<String> = ["US", "WHO", "AIDS"]
}
