import XCTest
@testable import Mown

final class LineEditingTests: XCTestCase {

    private func applied(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    // MARK: - Move

    func testMoveLineDownSwapsWithNext() {
        let text = "a\nb\nc"
        let (out, sel) = applied(LineEditing.move(.down, text: text as NSString,
                                                  selection: NSRange(location: 0, length: 0)), to: text)!
        XCTAssertEqual(out, "b\na\nc")
        XCTAssertEqual(sel, NSRange(location: 2, length: 0)) // caret followed "a"
    }

    func testMoveLineUpSwapsWithPrevious() {
        let text = "a\nb\nc"
        let (out, sel) = applied(LineEditing.move(.up, text: text as NSString,
                                                  selection: NSRange(location: 2, length: 0)), to: text)!
        XCTAssertEqual(out, "b\na\nc")
        XCTAssertEqual(sel, NSRange(location: 0, length: 0)) // caret followed "b"
    }

    func testMoveUpAtTopReturnsNil() {
        let text = "a\nb"
        XCTAssertNil(LineEditing.move(.up, text: text as NSString, selection: NSRange(location: 0, length: 0)))
    }

    func testMoveDownAtBottomReturnsNil() {
        let text = "a\nb"
        XCTAssertNil(LineEditing.move(.down, text: text as NSString, selection: NSRange(location: 2, length: 0)))
    }

    func testMoveDownLastLineWithoutTrailingNewline() {
        // Moving the middle line down past the unterminated last line keeps the
        // doc unterminated.
        let text = "a\nb\nc"
        let (out, _) = applied(LineEditing.move(.down, text: text as NSString,
                                                selection: NSRange(location: 2, length: 0)), to: text)!
        XCTAssertEqual(out, "a\nc\nb")
    }

    func testMoveMultiLineSelectionDown() {
        let text = "a\nb\nc\nd"
        // Select lines "a" and "b".
        let (out, _) = applied(LineEditing.move(.down, text: text as NSString,
                                                selection: NSRange(location: 0, length: 3)), to: text)!
        XCTAssertEqual(out, "c\na\nb\nd")
    }

    // MARK: - Duplicate

    func testDuplicateLine() {
        let text = "hello\nworld\n"
        let (out, sel) = applied(LineEditing.duplicate(text: text as NSString,
                                                       selection: NSRange(location: 2, length: 0)), to: text)!
        XCTAssertEqual(out, "hello\nhello\nworld\n")
        XCTAssertEqual(sel, NSRange(location: 8, length: 0)) // caret moved onto the copy
    }

    func testDuplicateLastLineWithoutTrailingNewline() {
        let text = "only"
        let (out, _) = applied(LineEditing.duplicate(text: text as NSString,
                                                     selection: NSRange(location: 2, length: 0)), to: text)!
        XCTAssertEqual(out, "only\nonly")
    }
}
