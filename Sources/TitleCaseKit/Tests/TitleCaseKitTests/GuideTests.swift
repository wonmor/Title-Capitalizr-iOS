import XCTest
@testable import TitleCaseKit

// AP Stylebook, "composition titles": capitalize principal words, including prepositions and conjunctions of
// four or more letters; lowercase articles and prepositions/conjunctions of three or fewer letters unless first or last.
final class APTests: XCTestCase {
    func testOverIsFourLetters() { eq(.ap, "the quick brown fox jumps over the lazy dog", "The Quick Brown Fox Jumps Over the Lazy Dog") }
    func testTaleOfTwoCities() { eq(.ap, "a tale of two cities", "A Tale of Two Cities") }
    func testWithIsCapitalized() { eq(.ap, "gone with the wind", "Gone With the Wind") }
    func testShortLastWord() { eq(.ap, "what is it for", "What Is It For") }
    func testManInTheHighCastle() { eq(.ap, "the man in the high castle", "The Man in the High Castle") }
    func testOfMiceAndMen() { eq(.ap, "of mice and men", "Of Mice and Men") }
    func testAsLowercase() { eq(.ap, "life as we know it", "Life as We Know It") }
    // Ambiguous: AP gives no phrasal-verb rule; we capitalize the particle after a common verb.
    func testAmbiguousPhrasalLogIn() { eq(.ap, "how to log in to your account", "How to Log In to Your Account") }
}

// APA 7, 6.17: capitalize words of four letters or more, both parts of hyphenated major words, the first word
// after a colon, em dash or end punctuation; lowercase short articles, conjunctions (and, as, but, for, if, nor,
// or, so, yet) and prepositions (as, at, by, for, in, of, off, on, per, to, up, via).
final class APATests: XCTestCase {
    func testSelfReport() { eq(.apa, "a study of self-report measures", "A Study of Self-Report Measures") }
    func testColonSubtitle() { eq(.apa, "effects of sleep on memory: a meta-analysis", "Effects of Sleep on Memory: A Meta-Analysis") }
    func testFourLetterPrepositions() { eq(.apa, "learning from mistakes with children", "Learning From Mistakes With Children") }
    func testUpToDate() { eq(.apa, "the role of anxiety in up-to-date models", "The Role of Anxiety in Up-to-Date Models") }
    func testShortVerbsCapitalized() { eq(.apa, "what it is and is not", "What It Is and Is Not") }
    func testIfAfterColon() { eq(.apa, "if only: a review", "If Only: A Review") }
    func testAsLowercase() { eq(.apa, "mindfulness as a practice", "Mindfulness as a Practice") }
    func testTowardFirstWord() { eq(.apa, "toward a theory of mind", "Toward a Theory of Mind") }
    func testEmDashSubtitle() { eq(.apa, "grief—a qualitative study", "Grief—A Qualitative Study") }
}

// Chicago 18, 8.159: lowercase articles, prepositions regardless of length, and/but/for/or/nor, to, as;
// capitalize subordinating conjunctions. 8.161: hyphenated compounds.
final class ChicagoTests: XCTestCase {
    func testSoundAndFury() { eq(.chicago, "the sound and the fury", "The Sound and the Fury") }
    func testLongPrepositionLowercase() { eq(.chicago, "a walk through the woods", "A Walk through the Woods") }
    func testBetween() { eq(.chicago, "life between buildings", "Life between Buildings") }
    func testSubordinatingWhen() { eq(.chicago, "what to expect when you're expecting", "What to Expect When You're Expecting") }
    func testSelfSustaining() { eq(.chicago, "a self-sustaining system", "A Self-Sustaining System") }
    func testAsLowercase() { eq(.chicago, "running as a sport", "Running as a Sport") }
    func testYetCapitalized() { eq(.chicago, "smart yet simple design", "Smart Yet Simple Design") }
    func testBeingEarnest() { eq(.chicago, "the importance of being earnest", "The Importance of Being Earnest") }
    // Ambiguous: 8.161 lowercases the element after a prefix; proper nouns after a prefix need the dictionary.
    func testAmbiguousPrefixCompound() { eq(.chicago, "anti-intellectualism in american life", "Anti-intellectualism in American Life") }
    func testAmbiguousSpelledNumber() { eq(.chicago, "the twenty-first century", "The Twenty-first Century") }
}

// MLA 9, 1.2: lowercase articles, prepositions, coordinating conjunctions and the to of infinitives.
final class MLATests: XCTestCase {
    func testGrapesOfWrath() { eq(.mla, "the grapes of wrath", "The Grapes of Wrath") }
    func testFarewellToArms() { eq(.mla, "a farewell to arms", "A Farewell to Arms") }
    func testThingsFallApart() { eq(.mla, "things fall apart", "Things Fall Apart") }
    func testBeyondFirst() { eq(.mla, "beyond good and evil", "Beyond Good and Evil") }
    func testWithoutLowercase() { eq(.mla, "a room without a view", "A Room without a View") }
    func testSubordinatingBecause() { eq(.mla, "because i could not stop for death", "Because I Could Not Stop for Death") }
    func testSubtitle() { eq(.mla, "voices from the past: an anthology", "Voices from the Past: An Anthology") }
    func testLongTerm() { eq(.mla, "the long-term effects", "The Long-Term Effects") }
    func testYetLowercase() { eq(.mla, "small yet mighty", "Small yet Mighty") }
}

// Bluebook 21st ed., rule 8(a): capitalize the initial word and the word after a colon; do not capitalize
// articles, conjunctions or prepositions of four or fewer letters.
final class BluebookTests: XCTestCase {
    func testLawOfTorts() { eq(.bluebook, "the law of torts", "The Law of Torts") }
    func testThroughIsLong() { eq(.bluebook, "justice through law", "Justice Through Law") }
    func testWithIsShort() { eq(.bluebook, "rights with limits", "Rights with Limits") }
    func testFromIsShort() { eq(.bluebook, "duties from statute", "Duties from Statute") }
    func testAboveIsLong() { eq(.bluebook, "searching above the law", "Searching Above the Law") }
    func testIntoIsShort() { eq(.bluebook, "liability into the future", "Liability into the Future") }
    func testColon() { eq(.bluebook, "the case for reform: a reply", "The Case for Reform: A Reply") }
    func testIfConjunction() { eq(.bluebook, "contracts if breached", "Contracts if Breached") }
    // Ambiguous: rule 8 does not mention the last word, so a short final preposition stays lowercase.
    func testAmbiguousLastWord() { eq(.bluebook, "what the law is for", "What the Law Is for") }
}

// AMA 11, 10.2.1: lowercase articles, coordinating conjunctions (and, or, for, nor, but), prepositions of three
// or fewer letters and the to of infinitives; 10.2.2: capitalize the second part of a compound unless minor.
final class AMATests: XCTestCase {
    func testBloodPressure() { eq(.ama, "effect of exercise on blood pressure in adults", "Effect of Exercise on Blood Pressure in Adults") }
    func testWithIsLong() { eq(.ama, "outcomes with early treatment", "Outcomes With Early Treatment") }
    func testLongTermAfter() { eq(.ama, "long-term survival after surgery", "Long-Term Survival After Surgery") }
    func testColon() { eq(.ama, "risk factors and outcomes: a cohort study", "Risk Factors and Outcomes: A Cohort Study") }
    func testInfinitive() { eq(.ama, "how to measure pain", "How to Measure Pain") }
    func testYetCapitalized() { eq(.ama, "safe yet effective therapy", "Safe Yet Effective Therapy") }
    func testFollowUp() { eq(.ama, "follow-up of patients from rural areas", "Follow-up of Patients From Rural Areas") }
}

// New York Times headline style: capitalize all but a, and, as, at, but, by, en, for, if, in, of, on, or, the,
// to, v., vs., via (unless first or last).
final class NYTTests: XCTestCase {
    func testManWhoCame() { eq(.nyt, "the man who came to dinner", "The Man Who Came to Dinner") }
    func testWithCapitalized() { eq(.nyt, "a day with the president", "A Day With the President") }
    func testUpAndIs() { eq(.nyt, "what is up with the economy", "What Is Up With the Economy") }
    func testAsAndFor() { eq(.nyt, "stocks fall as markets brace for rates", "Stocks Fall as Markets Brace for Rates") }
    func testNo() { eq(.nyt, "no deal on the table", "No Deal on the Table") }
    func testOffFrom() { eq(.nyt, "taking off from the coast", "Taking Off From the Coast") }
    func testBy() { eq(.nyt, "a vote by the board", "A Vote by the Board") }
    func testIfLower() { eq(.nyt, "what if the deal fails", "What if the Deal Fails") }
}

// Wikipedia MOS:SECTIONCAPS: sentence case; lowercase after a colon unless a proper noun.
final class WikipediaTests: XCTestCase {
    func testEarlyLife() { eq(.wikipedia, "Early Life And Career", "Early life and career") }
    func testHistory() { eq(.wikipedia, "History Of The Region", "History of the region") }
    func testColonLowercase() { eq(.wikipedia, "Reception: Critical Response", "Reception: critical response") }
    func testAcronymKept() { eq(.wikipedia, "Use Of NASA Data", "Use of NASA data") }
    func testAllCaps() { eq(.wikipedia, "THE ROLE OF DNA", "The role of DNA") }
    func testBrandKept() { eq(.wikipedia, "Links To iPhone Apps", "Links to iPhone apps") }
    func testDictionaryProperNoun() { eq(.wikipedia, "Travels In France", "Travels in France", dict: ["France"]) }
}

final class SentenceTests: XCTestCase {
    func testBasic() { eq(.sentence, "The Quick Brown Fox", "The quick brown fox") }
    func testColonCapitalized() { eq(.sentence, "Effects Of Sleep: A Review", "Effects of sleep: A review") }
    func testPronounI() { eq(.sentence, "Why I Love NASA", "Why I love NASA") }
    func testTwoSentences() { eq(.sentence, "Hello World. This Is A Test", "Hello world. This is a test") }
    func testAbbreviationNoBreak() { eq(.sentence, "Data From The U.S. Census", "Data from the U.S. census") }
    func testEgKept() { eq(.sentence, "e.g. Some Examples", "e.g. some examples") }
}

final class PlainTests: XCTestCase {
    func testLordOfTheRings() { eq(.plain, "the lord of the rings", "The Lord of the Rings") }
    func testWith() { eq(.plain, "gone with the wind", "Gone With the Wind") }
    func testHarryPotter() { eq(.plain, "harry potter and the chamber of secrets", "Harry Potter and the Chamber of Secrets") }
    func testGuide() { eq(.plain, "a guide to the galaxy", "A Guide to the Galaxy") }
    func testAboutWhen() { eq(.plain, "what we talk about when we talk about love", "What We Talk About When We Talk About Love") }
    func testPhrasalSetUp() { eq(.plain, "set up your mac", "Set Up Your Mac") }
}
