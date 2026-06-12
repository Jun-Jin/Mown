import XCTest
@testable import Mown

final class TableEditingTests: XCTestCase {

    private func applied(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    // MARK: - Insert

    func testInsertBelowText() {
        let text = "intro"
        let (out, _) = applied(TableEditing.insert(text: text as NSString,
                                                   selection: NSRange(location: 5, length: 0)), to: text)!
        XCTAssertEqual(out, "intro\n\n| Header | Header |\n| --- | --- |\n| Cell | Cell |")
    }

    // MARK: - Cell jump

    private let table = "| a | b |\n| --- | --- |\n| c | d |"

    func testTabMovesToNextCell() {
        // Caret in the first cell "a" (index 2).
        let jump = TableEditing.tabJump(text: table as NSString,
                                        selection: NSRange(location: 2, length: 0), reverse: false)
        XCTAssertEqual(jump?.selectedRange, NSRange(location: 6, length: 1)) // selects "b"
        XCTAssertEqual(jump?.replacement, "") // navigation only
    }

    func testTabFromLastCellJumpsToNextRow() {
        // Caret in last cell "b" of the header row (index 6).
        let jump = TableEditing.tabJump(text: table as NSString,
                                        selection: NSRange(location: 6, length: 0), reverse: false)
        // Next row is the separator "| --- | --- |" (starts at offset 10, after
        // "| a | b |\n"); its first cell "---" sits two columns in, at 12.
        XCTAssertEqual(jump?.selectedRange, NSRange(location: 12, length: 3))
    }

    func testShiftTabMovesToPreviousCell() {
        let jump = TableEditing.tabJump(text: table as NSString,
                                        selection: NSRange(location: 6, length: 1), reverse: true)
        XCTAssertEqual(jump?.selectedRange, NSRange(location: 2, length: 1)) // back to "a"
    }

    func testTabOutsideTableReturnsNil() {
        let text = "a | b" // single pipe line, no table context
        XCTAssertNil(TableEditing.tabJump(text: text as NSString,
                                          selection: NSRange(location: 0, length: 0), reverse: false))
    }
}
