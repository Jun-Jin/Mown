import XCTest
import AppKit
@testable import Mown

final class MarkdownSyntaxHighlighterTests: XCTestCase {

    private func makeStorage(_ string: String) -> (NSTextStorage, MarkdownSyntaxHighlighter) {
        let base = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let highlighter = MarkdownSyntaxHighlighter(baseFont: base)
        let storage = NSTextStorage(string: string)
        storage.delegate = highlighter
        return (storage, highlighter)
    }

    /// Regression: attribute changes made inside `didProcessEditing` skip
    /// AppKit's attribute-fixing pass, so a highlight triggered by a keystroke
    /// used to leave CJK runs with the glyph-less monospaced system font —
    /// the text rendered as nothing. The highlighter must end with a font
    /// capable of rendering the characters.
    func testJapaneseKeepsRenderableFontAfterEditTimeHighlight() {
        let (storage, _) = makeStorage("こんにちは world\n")

        // Simulate a keystroke: a character edit fires the delegate's
        // didProcessEditing hook, where automatic attribute fixing is off.
        storage.replaceCharacters(in: NSRange(location: storage.length - 1, length: 0), with: "a")

        let kana = Unicode.Scalar("こ")
        var index = 0
        while index < 5 { // the five kana at the head of the string
            let font = storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
            XCTAssertNotNil(font)
            if let font {
                XCTAssertTrue(font.coveredCharacterSet.contains(kana),
                              "font \(font.fontName) at index \(index) cannot render Japanese")
            }
            index += 1
        }
    }

    func testHighlightOutsideEditingPassAlsoFixesFonts() {
        let (storage, highlighter) = makeStorage("漢字 **bold**\n")
        highlighter.highlight(storage)

        let kanji = Unicode.Scalar("漢")
        let font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertNotNil(font)
        if let font {
            XCTAssertTrue(font.coveredCharacterSet.contains(kanji),
                          "font \(font.fontName) cannot render kanji")
        }
    }
}
