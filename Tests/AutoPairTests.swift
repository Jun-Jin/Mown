import XCTest
@testable import Mown

final class AutoPairTests: XCTestCase {

    private func applied(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    func testWrapWithAsterisk() {
        let text = "word"
        let (out, sel) = applied(AutoPair.wrap(typing: "*", text: text as NSString,
                                               selection: NSRange(location: 0, length: 4)), to: text)!
        XCTAssertEqual(out, "*word*")
        XCTAssertEqual(sel, NSRange(location: 1, length: 4)) // inner text stays selected
    }

    func testWrapWithBracketUsesClosingBracket() {
        let text = "link"
        let (out, _) = applied(AutoPair.wrap(typing: "[", text: text as NSString,
                                             selection: NSRange(location: 0, length: 4)), to: text)!
        XCTAssertEqual(out, "[link]")
    }

    func testWrapWithBacktickAndUnderscore() {
        let text = "x"
        let (code, _) = applied(AutoPair.wrap(typing: "`", text: text as NSString,
                                              selection: NSRange(location: 0, length: 1)), to: text)!
        XCTAssertEqual(code, "`x`")
        let (under, _) = applied(AutoPair.wrap(typing: "_", text: text as NSString,
                                               selection: NSRange(location: 0, length: 1)), to: text)!
        XCTAssertEqual(under, "_x_")
    }

    func testNoSelectionReturnsNil() {
        XCTAssertNil(AutoPair.wrap(typing: "*", text: "x" as NSString, selection: NSRange(location: 0, length: 0)))
    }

    func testNonPairingCharacterReturnsNil() {
        XCTAssertNil(AutoPair.wrap(typing: "a", text: "x" as NSString, selection: NSRange(location: 0, length: 1)))
    }
}
