import XCTest
@testable import Mown

final class ListEditingTests: XCTestCase {

    /// Applies an edit to a plain string so assertions read as before/after
    /// text plus the resulting caret/selection.
    private func applied(_ edit: ListEditing.Edit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let ns = text as NSString
        let out = ns.replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    private func caret(_ text: String, after marker: String) -> NSRange {
        NSRange(location: (text as NSString).range(of: marker).location + (marker as NSString).length, length: 0)
    }

    // MARK: indent / outdent

    func testIndentBulletLine() {
        let text = "- one\n- two\n"
        let edit = ListEditing.indent(text: text as NSString, selection: NSRange(location: 2, length: 0))
        let (out, sel) = applied(edit, to: text)!
        XCTAssertEqual(out, "  - one\n- two\n")
        XCTAssertEqual(sel, NSRange(location: 4, length: 0)) // caret shifted by 2
    }

    func testOutdentBulletLine() {
        let text = "  - one\n"
        let edit = ListEditing.outdent(text: text as NSString, selection: NSRange(location: 6, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "- one\n")
    }

    func testOutdentNoIndentReturnsNil() {
        let text = "- one\n"
        XCTAssertNil(ListEditing.outdent(text: text as NSString, selection: NSRange(location: 2, length: 0)))
    }

    func testTabOutsideListReturnsNil() {
        let text = "plain text\n"
        XCTAssertNil(ListEditing.indent(text: text as NSString, selection: NSRange(location: 3, length: 0)))
    }

    func testIndentMultiLineSelection() {
        let text = "- a\n- b\n- c\n"
        // Select across the first two lines.
        let edit = ListEditing.indent(text: text as NSString, selection: NSRange(location: 0, length: 6))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "  - a\n  - b\n- c\n")
    }

    // MARK: ordered renumbering

    func testIndentRenumbersFollowingOrderedSiblings() {
        let text = "1. a\n2. b\n3. c\n"
        // Indent the middle item; the third should renumber to keep 1. then 2.
        let edit = ListEditing.indent(text: text as NSString, selection: NSRange(location: 6, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "1. a\n  2. b\n2. c\n")
    }

    func testRenumberPreservesRunHeadNumber() {
        let text = "1. a\n2. b\n3. c\n"
        // Indenting the head nests it; the new top-level head keeps its own
        // number (2) and the run stays contiguous from there (2,3).
        let edit = ListEditing.indent(text: text as NSString, selection: NSRange(location: 2, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "  1. a\n2. b\n3. c\n")
    }

    // MARK: newline continuation

    func testNewlineContinuesBullet() {
        let text = "- one"
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 5, length: 0))
        let (out, sel) = applied(edit, to: text)!
        XCTAssertEqual(out, "- one\n- ")
        XCTAssertEqual(sel, caret(out, after: "- one\n- "))
    }

    func testNewlineIncrementsOrdered() {
        let text = "1. one"
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 6, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "1. one\n2. ")
    }

    func testNewlineContinuesTaskUnchecked() {
        let text = "- [x] done"
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 10, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "- [x] done\n- [ ] ")
    }

    func testNewlineContinuesBlockquote() {
        let text = "> quoted"
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 8, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "> quoted\n> ")
    }

    func testNewlineEmptyBulletExitsList() {
        let text = "- one\n- "
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 8, length: 0))
        let (out, sel) = applied(edit, to: text)!
        XCTAssertEqual(out, "- one\n")
        XCTAssertEqual(sel, NSRange(location: 6, length: 0))
    }

    func testNewlineEmptyTaskExitsList() {
        let text = "- [ ] "
        let edit = ListEditing.newline(text: text as NSString, selection: NSRange(location: 6, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "")
    }

    func testNewlineInMiddleOfItemReturnsNil() {
        let text = "- hello"
        // Caret after "- hel", not at line end.
        XCTAssertNil(ListEditing.newline(text: text as NSString, selection: NSRange(location: 5, length: 0)))
    }

    func testNewlineOnPlainLineReturnsNil() {
        let text = "plain"
        XCTAssertNil(ListEditing.newline(text: text as NSString, selection: NSRange(location: 5, length: 0)))
    }

    // MARK: backspace

    func testBackspaceAtContentStartRemovesMarker() {
        let text = "- one"
        let edit = ListEditing.backspace(text: text as NSString, selection: NSRange(location: 2, length: 0))
        let (out, sel) = applied(edit, to: text)!
        XCTAssertEqual(out, "one")
        XCTAssertEqual(sel, NSRange(location: 0, length: 0))
    }

    func testBackspaceKeepsIndent() {
        let text = "  - one"
        let edit = ListEditing.backspace(text: text as NSString, selection: NSRange(location: 4, length: 0))
        let (out, _) = applied(edit, to: text)!
        XCTAssertEqual(out, "  one")
    }

    func testBackspaceMidContentReturnsNil() {
        let text = "- one"
        XCTAssertNil(ListEditing.backspace(text: text as NSString, selection: NSRange(location: 4, length: 0)))
    }
}
