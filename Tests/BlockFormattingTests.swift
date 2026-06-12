import XCTest
@testable import Mown

final class BlockFormattingTests: XCTestCase {

    private func applied(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        let out = (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
        return (out, edit.selectedRange)
    }

    private func edit(_ format: BlockFormat, _ text: String, _ selection: NSRange) -> TextEdit? {
        BlockFormatting.edit(for: format, text: text as NSString, selection: selection)
    }

    // MARK: - Headings

    func testHeadingSetsLevelOnPlainLine() {
        let (out, _) = applied(edit(.heading(2), "title", NSRange(location: 1, length: 0)), to: "title")!
        XCTAssertEqual(out, "## title")
    }

    func testHeadingTogglesOffWhenAlreadyAtLevel() {
        let (out, _) = applied(edit(.heading(2), "## title", NSRange(location: 4, length: 0)), to: "## title")!
        XCTAssertEqual(out, "title")
    }

    func testHeadingReplacesExistingLevel() {
        let (out, _) = applied(edit(.heading(1), "### title", NSRange(location: 5, length: 0)), to: "### title")!
        XCTAssertEqual(out, "# title")
    }

    func testHeadingCaretKeepsColumnRelativeToContent() {
        // Caret sits before "title"; after adding "## " it stays before "title".
        let (_, sel) = applied(edit(.heading(2), "title", NSRange(location: 0, length: 0)), to: "title")!
        XCTAssertEqual(sel, NSRange(location: 3, length: 0))
    }

    func testBumpHeadingFromPlainAddsOne() {
        let (out, _) = applied(edit(.bumpHeading(1), "x", NSRange(location: 0, length: 0)), to: "x")!
        XCTAssertEqual(out, "# x")
    }

    func testBumpHeadingDecrementToPlain() {
        let (out, _) = applied(edit(.bumpHeading(-1), "# x", NSRange(location: 2, length: 0)), to: "# x")!
        XCTAssertEqual(out, "x")
    }

    func testBumpHeadingClampsAtSix() {
        XCTAssertNil(edit(.bumpHeading(1), "###### x", NSRange(location: 7, length: 0)))
    }

    // MARK: - Blockquote

    func testBlockquoteAddsPrefix() {
        let (out, _) = applied(edit(.blockquote, "quote me", NSRange(location: 0, length: 0)), to: "quote me")!
        XCTAssertEqual(out, "> quote me")
    }

    func testBlockquoteTogglesOff() {
        let (out, _) = applied(edit(.blockquote, "> quote me", NSRange(location: 4, length: 0)), to: "> quote me")!
        XCTAssertEqual(out, "quote me")
    }

    func testBlockquoteMultiLineAddsToEachNonBlank() {
        let text = "a\n\nb"
        let (out, _) = applied(edit(.blockquote, text, NSRange(location: 0, length: 4)), to: text)!
        XCTAssertEqual(out, "> a\n\n> b")
    }

    // MARK: - Code block

    func testCodeBlockFencesSelection() {
        let text = "let x = 1"
        let (out, sel) = applied(edit(.codeBlock, text, NSRange(location: 0, length: 9)), to: text)!
        XCTAssertEqual(out, "```\nlet x = 1\n```")
        XCTAssertEqual(sel, NSRange(location: 4, length: 9)) // the code stays selected
    }

    func testCodeBlockUnwraps() {
        let text = "```\ncode\n```"
        let (out, _) = applied(edit(.codeBlock, text, NSRange(location: 0, length: 12)), to: text)!
        XCTAssertEqual(out, "code")
    }

    func testCodeBlockEmptyLineCaretBetweenFences() {
        let (out, sel) = applied(edit(.codeBlock, "", NSRange(location: 0, length: 0)), to: "")!
        XCTAssertEqual(out, "```\n\n```")
        XCTAssertEqual(sel, NSRange(location: 4, length: 0))
    }

    // MARK: - Horizontal rule

    func testHorizontalRuleOnEmptyLine() {
        let (out, _) = applied(edit(.horizontalRule, "", NSRange(location: 0, length: 0)), to: "")!
        XCTAssertEqual(out, "---")
    }

    func testHorizontalRuleBelowText() {
        let (out, _) = applied(edit(.horizontalRule, "para", NSRange(location: 4, length: 0)), to: "para")!
        XCTAssertEqual(out, "para\n\n---\n")
    }

    // MARK: - Task toggle

    func testTaskToggleChecksUnchecked() {
        let (out, _) = applied(edit(.taskToggle, "- [ ] todo", NSRange(location: 6, length: 0)), to: "- [ ] todo")!
        XCTAssertEqual(out, "- [x] todo")
    }

    func testTaskToggleUnchecksChecked() {
        let (out, _) = applied(edit(.taskToggle, "- [x] todo", NSRange(location: 6, length: 0)), to: "- [x] todo")!
        XCTAssertEqual(out, "- [ ] todo")
    }

    func testTaskTogglePromotesBullet() {
        let (out, _) = applied(edit(.taskToggle, "- item", NSRange(location: 3, length: 0)), to: "- item")!
        XCTAssertEqual(out, "- [ ] item")
    }

    func testTaskTogglePromotesPlainLine() {
        let (out, _) = applied(edit(.taskToggle, "plain", NSRange(location: 0, length: 0)), to: "plain")!
        XCTAssertEqual(out, "- [ ] plain")
    }

    // MARK: - Table

    func testInsertTableOnEmptyLine() {
        let (out, sel) = applied(edit(.table, "", NSRange(location: 0, length: 0)), to: "")!
        XCTAssertEqual(out, "| Header | Header |\n| --- | --- |\n| Cell | Cell |")
        XCTAssertEqual(sel, NSRange(location: 2, length: 6)) // first "Header" selected
    }
}
