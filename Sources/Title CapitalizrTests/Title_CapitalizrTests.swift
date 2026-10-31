//
//  Title_CapitalizrTests.swift
//  Title CapitalizrTests
//
//  Created by John Seong on 2022-05-16.
//

import XCTest
@testable import Title_Capitalizr

final class Title_CapitalizrTests: XCTestCase {

    // MARK: Rule-based capitalizer (the default path)

    func testRuleBasedCapitalizerLowercasesStyleExceptions() {
        let mla = Capitalizer(inputLine: "the lord of the rings").capitalizeTitle(selectedOutput: .mla)
        XCTAssertEqual(mla, "The Lord of the Rings")
        let apa = Capitalizer(inputLine: "a war between the worlds").capitalizeTitle(selectedOutput: .apa)
        XCTAssertEqual(apa, "A War Between the Worlds", "APA capitalizes words of four letters or more")
        XCTAssertEqual(Capitalizer(inputLine: "an apple a day").capitalizeTitle(selectedOutput: .mla), "An Apple a Day")
    }

    // MARK: Grammar: a / an

    func testArticleAnBeforeVowelSound() {
        let issues = GrammarChecker().checkArticles("a apple a day")
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .article)
        XCTAssertEqual(issues[0].original, "a")
        XCTAssertEqual(issues[0].preferredReplacement, "an")
        XCTAssertEqual(issues[0].applying(to: "a apple a day"), "an apple a day")
    }

    func testArticleABeforeConsonantSoundAndExceptions() {
        XCTAssertEqual(GrammarChecker().checkArticles("an book").first?.preferredReplacement, "a")
        XCTAssertEqual(GrammarChecker().checkArticles("An Honest Mistake").count, 0, "silent h takes 'an'")
        XCTAssertEqual(GrammarChecker().checkArticles("a university").count, 0, "'yu' sound takes 'a'")
        XCTAssertEqual(GrammarChecker().checkArticles("an university").first?.preferredReplacement, "a")
        XCTAssertEqual(GrammarChecker().checkArticles("a hour").first?.preferredReplacement, "an")
        XCTAssertEqual(GrammarChecker().checkArticles("a FBI agent").first?.preferredReplacement, "an")
        XCTAssertEqual(GrammarChecker().checkArticles("A Elephant").first?.preferredReplacement, "An", "keeps capitalisation")
    }

    // MARK: Grammar: doubled words

    func testDoubledWordsAreFlaggedOnce() {
        let text = "the the history of of time"
        let issues = GrammarChecker().checkDoubledWords(text)
        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].original, "the the")
        XCTAssertEqual(issues[0].preferredReplacement, "the")
        XCTAssertEqual(issues.applyingAll(to: text), "the history of time")
    }

    func testDoubledWordsIgnoreCaseAndNoFalsePositives() {
        XCTAssertEqual(GrammarChecker().checkDoubledWords("The the end").first?.preferredReplacement, "The")
        XCTAssertTrue(GrammarChecker().checkDoubledWords("Theory of the Theme").isEmpty)
        XCTAssertTrue(GrammarChecker().checkDoubledWords("Round and Round").isEmpty)
    }

    // MARK: Grammar: first-word capitalisation

    func testFirstWordCapitalization() {
        let issues = GrammarChecker().checkFirstWordCapitalization("  harry potter and the goblet")
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues[0].kind, .firstWordCapital)
        XCTAssertEqual(issues[0].original, "harry")
        XCTAssertEqual(issues[0].preferredReplacement, "Harry")
        XCTAssertEqual(issues[0].applying(to: "  harry potter and the goblet"), "  Harry potter and the goblet")
        XCTAssertTrue(GrammarChecker().checkFirstWordCapitalization("Harry potter").isEmpty)
        XCTAssertTrue(GrammarChecker().checkFirstWordCapitalization("").isEmpty)
    }

    // MARK: Grammar: apostrophes and subject-verb agreement

    func testMissingApostrophes() {
        let issues = GrammarChecker().checkApostrophes("why we dont sleep and Im tired")
        XCTAssertEqual(issues.map(\.preferredReplacement), ["don't", "I'm"])
        XCTAssertTrue(GrammarChecker().checkApostrophes("It's its own thing").isEmpty)
    }

    func testSubjectVerbAgreement() {
        XCTAssertEqual(GrammarChecker().checkSubjectVerbAgreement("why she go home").first?.preferredReplacement, "goes")
        XCTAssertEqual(GrammarChecker().checkSubjectVerbAgreement("they was here").first?.preferredReplacement, "were")
        XCTAssertEqual(GrammarChecker().checkSubjectVerbAgreement("He Have a Dream").first?.preferredReplacement, "Has")
        XCTAssertTrue(GrammarChecker().checkSubjectVerbAgreement("She goes home").isEmpty)
        XCTAssertTrue(GrammarChecker().checkSubjectVerbAgreement("I was there").isEmpty)
    }

    func testCombinedCheckIsSortedAndFixAllAppliesEverything() {
        let text = "a apple a a day dont"
        let issues = GrammarChecker().check(text)
        // The first-word capitalisation is folded into the overlapping a/an fix ("a" -> "An").
        XCTAssertEqual(issues.map(\.kind), [.article, .doubledWord, .apostrophe])
        XCTAssertEqual(issues.first?.preferredReplacement, "An")
        XCTAssertEqual(issues.applyingAll(to: text), "An apple a day don't")
        XCTAssertEqual(GrammarChecker().check("harry potter").map(\.kind), [.firstWordCapital])
    }

    // MARK: Fallback when the on-device model is unavailable

    @MainActor
    func testSmartCapitalizeFallsBackToRuleEngineWhenModelUnavailable() async {
        let smart = SmartCapitalizer(availabilityProvider: { .unavailable(reason: "test") })
        XCTAssertFalse(smart.availability.isAvailable)
        let result = await smart.capitalize("the lord of the rings", style: .mla)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.title, Capitalizer(inputLine: "the lord of the rings").capitalizeTitle(selectedOutput: .mla))
        let alternatives = await smart.suggestAlternatives(for: "the lord of the rings", style: .mla)
        XCTAssertTrue(alternatives.isEmpty)
        let review = await smart.reviewGrammar("a apple")
        XCTAssertNil(review)
    }

    @MainActor
    func testSmartCapitalizeFallsBackForEmptyInput() async {
        let smart = SmartCapitalizer(availabilityProvider: { .available })
        let result = await smart.capitalize("   ", style: .apa)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(result.title, "")
    }

    func testSystemAvailabilityNeverCrashes() {
        // Whatever the host supports, the probe must return a usable answer.
        let availability = SmartCapitalizer.systemAvailability()
        if case .unavailable(let reason) = availability { XCTAssertFalse(reason.isEmpty) }
    }

    func testSmartOutputGuardRejectsRewrites() {
        XCTAssertTrue(SmartCapitalizer.looksLikeSameTitle("The Lord of the Rings", as: "the lord of the rings"))
        XCTAssertFalse(SmartCapitalizer.looksLikeSameTitle("The Hobbit", as: "the lord of the rings"))
        XCTAssertEqual(SmartCapitalizer.clean("Title: \"The Lord of the Rings\"\n"), "The Lord of the Rings")
    }

    // MARK: Spelling (system checker, on-device)

    @MainActor
    func testSpellCheckerFlagsMisspelling() {
        let issues = SpellChecker().check("The Lrod of the Rings")
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.original, "Lrod")
        XCTAssertTrue(SpellChecker().check("The Lord of the Rings").isEmpty)
    }
}
