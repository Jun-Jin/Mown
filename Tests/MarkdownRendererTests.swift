import XCTest
@testable import Inkwell

final class MarkdownRendererTests: XCTestCase {
    private let renderer = MarkdownRenderer.shared

    func testCommonMarkHeadingAndParagraph() {
        let html = renderer.renderHTML("# Title\n\nHello *world*.\n")
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<em>world</em>"))
    }

    func testGFMStrikethrough() {
        let html = renderer.renderHTML("~~gone~~\n")
        XCTAssertTrue(html.contains("<del>gone</del>"))
    }

    func testGFMTable() {
        let md = """
        | a | b |
        |---|---|
        | 1 | 2 |
        """
        let html = renderer.renderHTML(md)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<th>a</th>"))
        XCTAssertTrue(html.contains("<td>1</td>"))
    }

    func testGFMTaskList() {
        let html = renderer.renderHTML("- [ ] todo\n- [x] done\n")
        XCTAssertTrue(html.contains("type=\"checkbox\""))
        XCTAssertTrue(html.contains("checked"))
    }

    func testFencedCodeUsesLanguageClass() {
        let md = """
        ```swift
        let x = 1
        ```
        """
        let html = renderer.renderHTML(md)
        // GITHUB_PRE_LANG emits `<pre lang="swift">` and `<code class="language-swift">`.
        XCTAssertTrue(html.contains("language-swift") || html.contains("lang=\"swift\""),
                      "expected a swift language hint, got: \(html)")
    }

    func testRawHTMLIsEscapedOrFiltered() {
        // Without CMARK_OPT_UNSAFE, raw HTML must not render as live markup.
        let html = renderer.renderHTML("<script>alert(1)</script>\n")
        XCTAssertFalse(html.contains("<script>alert(1)</script>"),
                       "raw <script> leaked into output: \(html)")
    }

    func testAutolink() {
        let html = renderer.renderHTML("Visit https://example.com today.\n")
        XCTAssertTrue(html.contains("href=\"https://example.com\""))
    }

    func testEmptyInputDoesNotCrash() {
        XCTAssertEqual(renderer.renderHTML(""), "")
    }
}
