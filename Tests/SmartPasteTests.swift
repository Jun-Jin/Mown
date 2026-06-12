import XCTest
@testable import Mown

final class SmartPasteTests: XCTestCase {

    private func applied(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    // MARK: - URL → link

    func testPasteURLOverSelectionMakesLink() {
        let text = "Mown"
        let (out, _) = applied(SmartPaste.transform(pasted: "https://example.com",
                                                    text: text as NSString,
                                                    selection: NSRange(location: 0, length: 4)), to: text)!
        XCTAssertEqual(out, "[Mown](https://example.com)")
    }

    func testPasteURLWithoutSelectionFallsThrough() {
        XCTAssertNil(SmartPaste.transform(pasted: "https://example.com",
                                          text: "" as NSString,
                                          selection: NSRange(location: 0, length: 0)))
    }

    func testNonURLNonTabularReturnsNil() {
        XCTAssertNil(SmartPaste.transform(pasted: "just some words",
                                          text: "x" as NSString,
                                          selection: NSRange(location: 0, length: 1)))
    }

    // MARK: - Tabular → table

    func testTabSeparatedBecomesTable() {
        let pasted = "a\tb\nc\td"
        let table = SmartPaste.markdownTable(from: pasted)
        XCTAssertEqual(table, "| a | b |\n| --- | --- |\n| c | d |")
    }

    func testRaggedRowsArePadded() {
        let pasted = "a\tb\tc\nd\te"
        let table = SmartPaste.markdownTable(from: pasted)
        XCTAssertEqual(table, "| a | b | c |\n| --- | --- | --- |\n| d | e |  |")
    }

    func testNoTabsIsNotTabular() {
        XCTAssertNil(SmartPaste.markdownTable(from: "one line no tabs"))
    }

    // MARK: - URL detection

    func testBareWWWGetsScheme() {
        XCTAssertEqual(WebURL.normalized("www.example.com"), "https://www.example.com")
    }

    func testPlainTextIsNotAURL() {
        XCTAssertNil(WebURL.normalized("hello world"))
    }
}
