import XCTest
@testable import TitleCaseKit

final class TextToolTests: XCTestCase {
    func testUpper() { XCTAssertEqual(TextTool.upper.apply("Hello iPhone"), "HELLO IPHONE") }
    func testLower() { XCTAssertEqual(TextTool.lower.apply("Hello NASA"), "hello nasa") }
    func testSentence() { XCTAssertEqual(TextTool.sentence.apply("HELLO THERE. HOW ARE YOU"), "Hello there. How are you") }
    func testSentenceKeepsAcronymsAndI() { XCTAssertEqual(TextTool.sentence.apply("i think NASA is cool. yes"), "I think NASA is cool. Yes") }
    func testSentenceMultiline() { XCTAssertEqual(TextTool.sentence.apply("ONE TWO\nTHREE"), "One two\nThree") }
    func testCapitalizeEach() { XCTAssertEqual(TextTool.capitalizeEach.apply("hello world of iPhone"), "Hello World Of iPhone") }
    func testCamel() { XCTAssertEqual(TextTool.camel.apply("Hello world-foo bar"), "helloWorldFooBar") }
    func testPascal() { XCTAssertEqual(TextTool.pascal.apply("Hello world-foo bar"), "HelloWorldFooBar") }
    func testSnake() { XCTAssertEqual(TextTool.snake.apply("Hello World Foo"), "hello_world_foo") }
    func testSnakeFromCamel() { XCTAssertEqual(TextTool.snake.apply("HTMLParser rocks"), "html_parser_rocks") }
    func testKebab() { XCTAssertEqual(TextTool.kebab.apply("myVariableName2"), "my-variable-name2") }
    func testIdentifierPerLine() { XCTAssertEqual(TextTool.snake.apply("First Line\nSecond Line"), "first_line\nsecond_line") }
    func testSlugDiacritics() { XCTAssertEqual(TextTool.slug.apply("Crème Brûlée!"), "creme-brulee") }
    func testSlugAmpersandApostrophe() { XCTAssertEqual(TextTool.slug.apply("Rock & Roll: Don't Stop"), "rock-and-roll-dont-stop") }
    func testSlugGerman() { XCTAssertEqual(TextTool.slug.apply("Straße"), "strasse") }
    func testSmartQuotes() { XCTAssertEqual(TextTool.smartPunctuation.apply("\"Hello,\" she said -- it's 10-20 minutes..."), "“Hello,” she said — it’s 10–20 minutes…") }
    func testSmartSingleQuotes() { XCTAssertEqual(TextTool.smartPunctuation.apply("'quoted' in the '90s"), "‘quoted’ in the ’90s") }
    func testStraight() { XCTAssertEqual(TextTool.straightPunctuation.apply("“Hi” it’s — 1–2…"), "\"Hi\" it's -- 1-2...") }
    func testTrimSpaces() { XCTAssertEqual(TextTool.trimSpaces.apply("  a   b \t c  \n  d  "), "a b c\nd") }
    func testRemoveLineBreaks() { XCTAssertEqual(TextTool.removeLineBreaks.apply("a\nb\r\nc\n\nd "), "a b c d") }
    func testFreeTools() { XCTAssertEqual(TextTool.allCases.filter(\.isFree), [.upper, .lower, .sentence, .trimSpaces, .removeLineBreaks]) }
    func testGlyphsPresent() { for t in TextTool.allCases { XCTAssertFalse(t.systemImage.isEmpty) } }
}

final class BatchTests: XCTestCase {
    let apa: (String) -> String = { TitleCaseEngine.apply($0, guide: .apa) }
    let plain: (String) -> String = { TitleCaseEngine.apply($0, guide: .plain) }

    func testLinesKeepEmpty() {
        XCTAssertEqual(BatchConverter.convert("a tale\n\nwar and peace", options: BatchOptions(), transform: apa), "A Tale\n\nWar and Peace")
    }
    func testLinesSkipEmpty() {
        XCTAssertEqual(BatchConverter.convert("a tale\n\n  \nwar and peace", options: BatchOptions(skipEmpty: true), transform: apa), "A Tale\nWar and Peace")
    }
    func testLinesCRLF() {
        XCTAssertEqual(BatchConverter.convert("a tale\r\nwar and peace\r\n", options: BatchOptions(), transform: apa), "A Tale\r\nWar and Peace\r\n")
    }
    func testFileNameSeparators() {
        XCTAssertEqual(BatchConverter.convert("my_report-final.pdf", options: BatchOptions(mode: .fileNames), transform: plain), "My_Report-Final.pdf")
    }
    func testFileNameSpaces() {
        XCTAssertEqual(BatchConverter.convert("the lord of the rings.epub", options: BatchOptions(mode: .fileNames), transform: plain), "The Lord of the Rings.epub")
    }
    func testFileNameNoExtension() {
        XCTAssertEqual(BatchConverter.convert("notes about life", options: BatchOptions(mode: .fileNames), transform: plain), "Notes About Life")
    }
    func testFileNameWithTool() {
        XCTAssertEqual(BatchConverter.convert("Final Report.docx\nmy notes.txt", options: BatchOptions(mode: .fileNames), transform: TextTool.upper.apply), "FINAL REPORT.docx\nMY NOTES.txt")
    }
    func testCSVColumnQuotesAndNewlines() {
        let input = "id,title\n1,a tale of two cities\n2,\"war, and peace\"\n3,\"multi\nline title\"\n"
        let expected = "id,title\n1,A Tale of Two Cities\n2,\"War, and Peace\"\n3,\"Multi\nLine Title\"\n"
        XCTAssertEqual(BatchConverter.convert(input, options: BatchOptions(mode: .csvColumn, csvColumn: 1), transform: plain), expected)
    }
    func testCSVEscapedQuotes() {
        let input = "t\n\"say \"\"hi\"\" now\""
        XCTAssertEqual(BatchConverter.convert(input, options: BatchOptions(mode: .csvColumn), transform: plain), "t\n\"Say \"\"Hi\"\" Now\"")
    }
    func testCSVNoHeader() {
        XCTAssertEqual(BatchConverter.convert("the end,x\nof days,y", options: BatchOptions(mode: .csvColumn, csvHasHeader: false), transform: plain), "The End,x\nOf Days,y")
    }
    func testCSVOtherColumnsUntouched() {
        XCTAssertEqual(BatchConverter.convert("a,b\nthe x,the y", options: BatchOptions(mode: .csvColumn, csvColumn: 0), transform: plain), "a,b\nThe X,the y")
    }
    func testCSVTabDelimiter() {
        XCTAssertEqual(BatchConverter.convert("name\tnote\nthe cat\tthe dog", options: BatchOptions(mode: .csvColumn, csvColumn: 1), transform: plain), "name\tnote\nthe cat\tThe Dog")
    }
    func testCSVCRLF() {
        XCTAssertEqual(BatchConverter.convert("h\r\nthe end\r\n", options: BatchOptions(mode: .csvColumn), transform: plain), "h\r\nThe End\r\n")
    }
    func testCSVColumnOutOfRange() {
        XCTAssertEqual(BatchConverter.convert("a\nb", options: BatchOptions(mode: .csvColumn, csvColumn: 5), transform: plain), "a\nb")
    }
    func testCSVColumns() {
        XCTAssertEqual(BatchConverter.csvColumns("id,\"Book, title\",\nx,y,z"), ["id", "Book, title", "Column 3"])
        XCTAssertEqual(BatchConverter.csvColumns("x,y", hasHeader: false), ["Column 1", "Column 2"])
    }
}
