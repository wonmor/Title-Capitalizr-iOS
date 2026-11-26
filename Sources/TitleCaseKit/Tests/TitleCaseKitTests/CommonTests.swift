import XCTest
@testable import TitleCaseKit

final class CommonTests: XCTestCase {
    func testDictionary() { eq(.apa, "mckinsey reports on ai", "McKinsey Reports on AI", dict: ["McKinsey"]) }
    func testDictionaryPossessive() { eq(.mla, "the acme's new plan", "The ACME's New Plan", dict: ["ACME"]) }
    func testDictionaryOverridesFirstWord() { eq(.chicago, "iphone sales soar", "iPhone Sales Soar") }
    func testAllCapsInput() { eq(.mla, "THE IPHONE AND NASA", "The iPhone and NASA") }
    func testAllCapsNote() { XCTAssertFalse(TitleCaseEngine.convert("HELLO WORLD", guide: .ap).notes.isEmpty) }
    func testDeliberateCasingKept() { eq(.apa, "why the FAA and McDonald's matter", "Why the FAA and McDonald's Matter") }
    func testBrandsRestored() { eq(.ap, "ebay and macos tips", "eBay and macOS Tips") }
    func testUsPronounNotAcronym() { eq(.apa, "made for us", "Made for Us") }
    func testUSDotted() { eq(.mla, "the u.s. economy", "The U.S. Economy") }
    func testRockNRoll() { eq(.apa, "rock 'n' roll forever", "Rock 'n' Roll Forever") }
    func testApostrophes() { eq(.mla, "don't stop believin'", "Don't Stop Believin'") }
    func testPossessive() { eq(.apa, "the children's book", "The Children's Book") }
    func testEmDashNoSpaces() { eq(.mla, "life—a memoir", "Life—A Memoir") }
    func testEmDashSpaced() { eq(.mla, "life — a memoir", "Life — A Memoir") }
    func testQuestionSubtitle() { eq(.chicago, "who is afraid? a study", "Who Is Afraid? A Study") }
    func testQuotedTitle() { eq(.mla, "\"the raven\" and other poems", "\"The Raven\" and Other Poems") }
    func testCurlyQuotes() { eq(.apa, "“the raven” and other poems", "“The Raven” and Other Poems") }
    func testParentheses() { eq(.ap, "notes (and other things)", "Notes (and Other Things)") }
    func testURLKept() { eq(.apa, "visit www.example.com today", "Visit www.example.com Today") }
    func testEmailKept() { eq(.apa, "write to john@example.com now", "Write to john@example.com Now") }
    func testNumbers() { eq(.plain, "top 10 tips for 2026", "Top 10 Tips for 2026") }
    func testOrdinalCompound() { eq(.apa, "a 19th-century study", "A 19th-Century Study") }
    func testPrepositionAsNoun() { eq(.chicago, "a look into the past", "A Look into the Past") }
    func testPrepositionAsNounMidTitle() { eq(.mla, "the down side of growth", "The Down Side of Growth") }
    func testSlash() { eq(.apa, "input/output and/or errors", "Input/Output and/or Errors") }
    func testWhitespacePreserved() { eq(.apa, "hello  world", "Hello  World") }
    func testTrimmed() { eq(.apa, "  hello world \n", "Hello World") }
    func testEmpty() { XCTAssertEqual(TitleCaseEngine.convert("   ", guide: .ap).text, "") }
    func testIdempotent() {
        for g in StyleGuide.allCases {
            let once = TitleCaseEngine.apply("the history of the world: a study in five parts", guide: g)
            XCTAssertEqual(TitleCaseEngine.apply(once, guide: g), once, g.displayName)
        }
    }
    func testExplanationsForEveryWord() {
        let sample = "how to log in: a self-report study of NASA's up-to-date data from the u.s. and www.x.com in 2026"
        for g in StyleGuide.allCases {
            let r = TitleCaseEngine.convert(sample, guide: g)
            XCTAssertEqual(r.words.count, 18, g.displayName)
            for w in r.words {
                XCTAssertFalse(w.explanation.isEmpty, "\(g.displayName) \(w.original)")
                XCTAssertFalse(w.explanation.contains("·") || w.explanation.contains("•"))
            }
        }
    }
    func testExplanationNamesGuide() {
        let r = TitleCaseEngine.convert("life between buildings", guide: .chicago)
        XCTAssertEqual(r.words[1].rule, .minorWord)
        XCTAssertTrue(r.words[1].explanation.contains("Chicago"))
        XCTAssertTrue(r.words[1].explanation.contains("any length"))
    }
    func testRulesRecorded() {
        let r = TitleCaseEngine.convert("gone with the wind: a novel", guide: .apa)
        XCTAssertEqual(r.words.map(\.rule), [.firstWord, .longPreposition, .minorWord, .majorWord, .afterColon, .lastWord])
    }
    func testPhrasalRuleAndNote() {
        let r = TitleCaseEngine.convert("how to sign up for a class", guide: .mla)
        XCTAssertEqual(r.text, "How to Sign Up for a Class")
        XCTAssertTrue(r.words.contains { $0.rule == .verbPhrasal })
        XCTAssertFalse(r.notes.isEmpty)
    }
    func testDictionaryRule() {
        let r = TitleCaseEngine.convert("acme widgets", guide: .ap, dictionary: CustomDictionary(words: ["ACME"]))
        XCTAssertEqual(r.words[0].rule, .dictionary)
    }
    func testSentenceProperNounNote() { XCTAssertFalse(TitleCaseEngine.convert("A Trip", guide: .sentence).notes.isEmpty) }
    func testFreeGuides() { XCTAssertEqual(StyleGuide.freeGuides, [.plain, .apa, .mla]) }
    func testShortNamesFit() { for g in StyleGuide.allCases { XCTAssertLessThanOrEqual(g.shortName.count, 10) } }
    func testAmbiguityNotesForEveryGuide() { for g in StyleGuide.allCases { XCTAssertFalse(g.ambiguities.isEmpty, g.displayName) } }
    func testNoBulletsInCopy() {
        let all = StyleGuide.allCases.flatMap { [$0.summary, $0.displayName] + $0.ambiguities } + TextTool.allCases.map(\.displayName)
        for s in all { XCTAssertFalse(s.contains("·") || s.contains("•"), s) }
    }
    func testCustomDictionaryLookup() {
        let d = CustomDictionary(words: ["iPhone", "NASA"])
        XCTAssertEqual(d.spelling(for: "IPHONE"), "iPhone")
        XCTAssertEqual(d.spelling(for: "nasa's"), "NASA's")
        XCTAssertNil(d.spelling(for: "nope"))
    }
    func testCodableRoundTrip() throws {
        let d = CustomDictionary(words: ["iPhone"])
        let back = try JSONDecoder().decode(CustomDictionary.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back, d)
    }
}
