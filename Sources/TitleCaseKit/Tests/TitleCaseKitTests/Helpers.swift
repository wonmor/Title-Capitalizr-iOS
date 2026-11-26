import XCTest
@testable import TitleCaseKit

func eq(_ g: StyleGuide, _ input: String, _ expected: String, dict: [String] = [], file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(TitleCaseEngine.apply(input, guide: g, dictionary: CustomDictionary(words: dict)), expected, "\(g.displayName)", file: file, line: line)
}
