import XCTest
@testable import Mown

final class MathExtractorTests: XCTestCase {
    private let renderer = MarkdownRenderer.shared

    // MARK: - End-to-end through the renderer

    func testInlineMathBecomesKaTeXContainer() {
        let html = renderer.renderHTML("Euler: $e^{i\\pi}+1=0$ is neat.\n")
        XCTAssertTrue(html.contains(#"<span class="mown-math" data-display="0">"#))
        XCTAssertTrue(html.contains("e^{i\\pi}+1=0"))
        // The surrounding prose still renders normally.
        XCTAssertTrue(html.contains("Euler:"))
        XCTAssertTrue(html.contains("is neat."))
    }

    func testInlineMathSubscriptIsNotMangledByEmphasis() {
        // The whole point: cmark must not turn `a_b_c` into `a<em>b</em>c`.
        let html = renderer.renderHTML("$a_b_c$\n")
        XCTAssertTrue(html.contains("a_b_c"), "subscripts were mangled: \(html)")
        XCTAssertFalse(html.contains("<em>"))
    }

    func testDisplayMathDoubleDollar() {
        let html = renderer.renderHTML("$$\nE = mc^2\n$$\n")
        XCTAssertTrue(html.contains(#"<div class="mown-math" data-display="1">"#))
        XCTAssertTrue(html.contains("E = mc^2"))
    }

    func testMathFenceBecomesDisplayMath() {
        let md = """
        ```math
        \\int_0^1 x\\,dx
        ```
        """
        let html = renderer.renderHTML(md)
        XCTAssertTrue(html.contains(#"<div class="mown-math" data-display="1">"#))
        XCTAssertTrue(html.contains("\\int_0^1"))
    }

    func testTexSpecialCharsAreHtmlEscaped() {
        // `<`, `>`, `&` must survive as literal text for KaTeX's reader.
        let html = renderer.renderHTML("$a < b > c \\& d$\n")
        XCTAssertTrue(html.contains("a &lt; b &gt; c \\&amp; d"))
    }

    // MARK: - Things that must NOT be treated as math

    func testDollarsInInlineCodeAreLiteral() {
        let html = renderer.renderHTML("Use `$HOME` and `$PATH` here.\n")
        XCTAssertFalse(html.contains("mown-math"))
        XCTAssertTrue(html.contains("<code>$HOME</code>"))
    }

    func testDollarsInFencedCodeAreLiteral() {
        let md = """
        ```sh
        echo $foo
        x=$((1 + 2))
        ```
        """
        let html = renderer.renderHTML(md)
        XCTAssertFalse(html.contains("mown-math"))
        XCTAssertTrue(html.contains("echo $foo"))
    }

    func testCurrencyIsNotMath() {
        // "$5 and $10" — closing-`$`-followed-by-digit guard keeps this as prose.
        let html = renderer.renderHTML("It costs $5 and $10 total.\n")
        XCTAssertFalse(html.contains("mown-math"))
    }

    func testEscapedDollarIsLiteral() {
        let html = renderer.renderHTML("Price is \\$5 today.\n")
        XCTAssertFalse(html.contains("mown-math"))
    }

    func testUnclosedDollarDoesNotReachIntoCodeSpan() {
        // `$10` must not grab the `$` inside `$HOME` as its closing delimiter.
        let html = renderer.renderHTML("Costs $10, and `$HOME` is a var.\n")
        XCTAssertFalse(html.contains("mown-math"))
        XCTAssertTrue(html.contains("<code>$HOME</code>"))
    }

    func testDoubleDollarInCodeSpanIsLiteral() {
        let html = renderer.renderHTML("Write `$$` for display math.\n")
        XCTAssertFalse(html.contains("mown-math"))
        XCTAssertTrue(html.contains("<code>$$</code>"))
    }

    func testNoMathLeavesDocumentUntouched() {
        let html = renderer.renderHTML("# Title\n\nPlain *text* only.\n")
        XCTAssertFalse(html.contains("mown-math"))
        XCTAssertTrue(html.contains("<h1>Title</h1>"))
        XCTAssertTrue(html.contains("<em>text</em>"))
    }

    // MARK: - Extractor internals

    func testExtractReportsHasMath() {
        XCTAssertTrue(MathExtractor.extract("$x$").hasMath)
        XCTAssertFalse(MathExtractor.extract("no math").hasMath)
        XCTAssertFalse(MathExtractor.extract("").hasMath)
    }

    func testMultipleInlineSpansGetDistinctTokens() {
        let result = MathExtractor.extract("$a$ and $b$")
        XCTAssertEqual(result.spans.count, 2)
        XCTAssertEqual(Set(result.spans.values.map(\.tex)), ["a", "b"])
    }
}
