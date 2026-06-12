import XCTest
@testable import Mown

final class InlineFormattingTests: XCTestCase {

    private func applied(_ edit: InlineFormatting.Edit, to text: String) -> (String, NSRange) {
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    // MARK: wrap

    func testWrapBoldKeepsTextSelected() {
        let text = "make bold"
        let edit = InlineFormatting.toggle(.bold, text: text as NSString, selection: NSRange(location: 5, length: 4))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "make **bold**")
        XCTAssertEqual(sel, NSRange(location: 7, length: 4)) // "bold" still selected
    }

    func testWrapItalic() {
        let text = "x"
        let edit = InlineFormatting.toggle(.italic, text: text as NSString, selection: NSRange(location: 0, length: 1))
        let (out, _) = applied(edit, to: text)
        XCTAssertEqual(out, "*x*")
    }

    func testWrapInlineCode() {
        let text = "code"
        let edit = InlineFormatting.toggle(.code, text: text as NSString, selection: NSRange(location: 0, length: 4))
        let (out, _) = applied(edit, to: text)
        XCTAssertEqual(out, "`code`")
    }

    func testWrapStrikethrough() {
        let text = "gone"
        let edit = InlineFormatting.toggle(.strikethrough, text: text as NSString, selection: NSRange(location: 0, length: 4))
        let (out, _) = applied(edit, to: text)
        XCTAssertEqual(out, "~~gone~~")
    }

    // MARK: unwrap

    func testUnwrapWhenMarkersInsideSelection() {
        let text = "**bold**"
        let edit = InlineFormatting.toggle(.bold, text: text as NSString, selection: NSRange(location: 0, length: 8))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "bold")
        XCTAssertEqual(sel, NSRange(location: 0, length: 4))
    }

    func testUnwrapWhenMarkersOutsideSelection() {
        let text = "**bold**"
        // Select just the inner "bold".
        let edit = InlineFormatting.toggle(.bold, text: text as NSString, selection: NSRange(location: 2, length: 4))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "bold")
        XCTAssertEqual(sel, NSRange(location: 0, length: 4))
    }

    // MARK: empty selection

    func testEmptySelectionInsertsPairWithCaretBetween() {
        let text = "ab"
        let edit = InlineFormatting.toggle(.bold, text: text as NSString, selection: NSRange(location: 1, length: 0))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "a****b")
        XCTAssertEqual(sel, NSRange(location: 3, length: 0)) // between the ** pairs
    }

    // MARK: link

    func testLinkWrapsSelectionAndSelectsURLSlot() {
        let text = "site"
        let edit = InlineFormatting.link(text: text as NSString, selection: NSRange(location: 0, length: 4))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "[site]()")
        XCTAssertEqual(sel, NSRange(location: 7, length: 0)) // inside the ()
    }

    func testLinkPrefillsClipboardURL() {
        let text = "site"
        let edit = InlineFormatting.link(text: text as NSString, selection: NSRange(location: 0, length: 4),
                                         clipboardURL: "https://x.com")
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "[site](https://x.com)")
        XCTAssertEqual(sel, NSRange(location: 7, length: 13)) // URL selected
    }

    func testLinkEmptySelectionCaretInTextSlot() {
        let text = ""
        let edit = InlineFormatting.link(text: text as NSString, selection: NSRange(location: 0, length: 0))
        let (out, sel) = applied(edit, to: text)
        XCTAssertEqual(out, "[]()")
        XCTAssertEqual(sel, NSRange(location: 1, length: 0)) // inside the []
    }
}
