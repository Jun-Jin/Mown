import AppKit

/// Regex-driven Markdown syntax highlighter for the editor's `NSTextStorage`
/// (SPEC §4: "Markdown-aware syntax highlighting *in the editor*").
///
/// Strategy: on every character edit, re-attribute the entire storage. Block
/// constructs (fenced code, headings, blockquotes, lists, HR) run first and
/// claim their ranges in a "consumed" index set; inline rules (code spans,
/// links, bold, italic, strikethrough) then skip any range that overlaps the
/// consumed set so we don't paint italic markup inside a code fence.
///
/// The implementation is intentionally pragmatic, not a full CommonMark
/// parser — the *preview* uses cmark-gfm for correctness. The editor only
/// needs visual cues that survive typical Markdown.
final class MarkdownSyntaxHighlighter: NSObject, NSTextStorageDelegate {

    /// The text view this storage backs. Used to detect an active input-method
    /// composition (marked text); re-attributing the storage mid-composition
    /// wipes the IME's marked-text underline and disturbs the session.
    weak var textView: NSTextView?

    // MARK: Fonts

    private let baseFont: NSFont
    private let monoFont: NSFont
    private let boldFont: NSFont
    private let italicFont: NSFont
    private let boldItalicFont: NSFont

    init(baseFont: NSFont) {
        self.baseFont = baseFont
        let size = baseFont.pointSize
        self.monoFont = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        let fm = NSFontManager.shared
        self.boldFont = fm.convert(baseFont, toHaveTrait: .boldFontMask)
        self.italicFont = fm.convert(baseFont, toHaveTrait: .italicFontMask)
        self.boldItalicFont = fm.convert(self.boldFont, toHaveTrait: .italicFontMask)
        super.init()
    }

    // MARK: Compiled regexes (built once)

    private struct Rules {
        let fencedCode    = try! NSRegularExpression(pattern: #"(?m)^```[^\n]*\n[\s\S]*?^```[ \t]*$"#)
        let heading       = try! NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}#{1,6}[ \t]+.*$"#)
        let blockquote    = try! NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}>.*$"#)
        let listMarker    = try! NSRegularExpression(pattern: #"(?m)^[ \t]*(?:[-*+]|\d+[.)])[ \t]+"#)
        let horizontalRule = try! NSRegularExpression(pattern: #"(?m)^[ \t]{0,3}(?:-{3,}|_{3,}|\*{3,})[ \t]*$"#)
        let inlineCode    = try! NSRegularExpression(pattern: #"`[^`\n]+`"#)
        let image         = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\([^)\s]+(?:\s+"[^"]*")?\)"#)
        let link          = try! NSRegularExpression(pattern: #"\[[^\]]+\]\([^)\s]+(?:\s+"[^"]*")?\)"#)
        let boldStar      = try! NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*"#)
        let boldUnder     = try! NSRegularExpression(pattern: #"__[^_\n]+__"#)
        let italicStar    = try! NSRegularExpression(pattern: #"(?<![*\w])\*[^*\n]+\*(?![*\w])"#)
        let italicUnder   = try! NSRegularExpression(pattern: #"(?<![_\w])_[^_\n]+_(?![_\w])"#)
        let strikethrough = try! NSRegularExpression(pattern: #"~~[^~\n]+~~"#)
    }
    private let rules = Rules()

    // MARK: NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        // Only react to character edits. Our own attribute changes during
        // highlighting fire `.editedAttributes`, which we ignore here to avoid
        // recursive re-highlighting.
        guard editedMask.contains(.editedCharacters) else { return }
        // Leave the storage alone while an IME composition (Japanese, Chinese,
        // Korean, ...) is in flight. The edit that commits or cancels the
        // composition fires this hook again with no marked text, and the
        // document re-highlights then.
        if textView?.hasMarkedText() == true { return }
        highlight(textStorage)
    }

    /// Re-attribute the entire storage. Safe to call from `didProcessEditing`
    /// because `setAttributes`/`addAttributes` only fire `.editedAttributes`,
    /// which our delegate guard filters out.
    func highlight(_ storage: NSTextStorage) {
        let full = NSRange(location: 0, length: storage.length)
        guard full.length > 0 else { return }
        let text = storage.string

        // 1. Reset to baseline.
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .strikethroughStyle: 0,
        ], range: full)

        // 2. Block-level rules first; record ranges they own.
        let consumed = NSMutableIndexSet()

        applyMatches(of: rules.fencedCode, in: text, range: full, to: storage,
                     attrs: codeAttrs, consuming: consumed)
        applyMatches(of: rules.horizontalRule, in: text, range: full, to: storage,
                     attrs: [.foregroundColor: NSColor.tertiaryLabelColor], consuming: consumed)
        applyMatches(of: rules.heading, in: text, range: full, to: storage,
                     attrs: [.font: boldFont, .foregroundColor: NSColor.systemBlue],
                     consuming: consumed)
        applyMatches(of: rules.blockquote, in: text, range: full, to: storage,
                     attrs: [.foregroundColor: NSColor.secondaryLabelColor],
                     consuming: consumed)
        applyMatches(of: rules.listMarker, in: text, range: full, to: storage,
                     attrs: [.font: boldFont, .foregroundColor: NSColor.systemOrange],
                     consuming: nil) // markers don't shield the rest of the line

        // 3. Inline rules; skip anything already inside a consumed (code) range.
        applyMatches(of: rules.inlineCode, in: text, range: full, to: storage,
                     attrs: codeAttrs, consuming: consumed, skipConsumed: true)
        applyMatches(of: rules.image, in: text, range: full, to: storage,
                     attrs: [.foregroundColor: NSColor.systemPurple], consuming: consumed,
                     skipConsumed: true)
        applyMatches(of: rules.link, in: text, range: full, to: storage,
                     attrs: [.foregroundColor: NSColor.linkColor], consuming: consumed,
                     skipConsumed: true)
        applyMatches(of: rules.boldStar, in: text, range: full, to: storage,
                     attrs: [.font: boldFont], consuming: consumed, skipConsumed: true)
        applyMatches(of: rules.boldUnder, in: text, range: full, to: storage,
                     attrs: [.font: boldFont], consuming: consumed, skipConsumed: true)
        applyMatches(of: rules.italicStar, in: text, range: full, to: storage,
                     attrs: [.font: italicFont], consuming: nil, skipConsumed: true,
                     consumedReadOnly: consumed)
        applyMatches(of: rules.italicUnder, in: text, range: full, to: storage,
                     attrs: [.font: italicFont], consuming: nil, skipConsumed: true,
                     consumedReadOnly: consumed)
        applyMatches(of: rules.strikethrough, in: text, range: full, to: storage,
                     attrs: [.strikethroughStyle: NSUnderlineStyle.single.rawValue],
                     consuming: nil, skipConsumed: true, consumedReadOnly: consumed)

        // 4. Attribute changes made inside `didProcessEditing` skip AppKit's
        // automatic attribute-fixing pass, so characters the assigned font
        // can't render (CJK in the monospaced system font, notably) would keep
        // a glyph-less font and draw as nothing. Fix explicitly so fallback
        // fonts are substituted.
        storage.fixAttributes(in: full)
    }

    // MARK: helpers

    private var codeAttrs: [NSAttributedString.Key: Any] {
        [.font: monoFont, .foregroundColor: NSColor.systemPink]
    }

    /// Run `regex` over `range` of `text`, applying `attrs` to each match in
    /// `storage`. If `consuming` is non-nil, matched ranges are added to it so
    /// later rules can skip them. If `skipConsumed` is true, matches that
    /// overlap either `consuming` or `consumedReadOnly` are skipped.
    private func applyMatches(of regex: NSRegularExpression,
                              in text: String,
                              range: NSRange,
                              to storage: NSTextStorage,
                              attrs: [NSAttributedString.Key: Any],
                              consuming: NSMutableIndexSet?,
                              skipConsumed: Bool = false,
                              consumedReadOnly: NSIndexSet? = nil) {
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let r = match?.range else { return }
            if skipConsumed {
                if let c = consuming, c.intersects(in: r) { return }
                if let c = consumedReadOnly, c.intersects(in: r) { return }
            }
            storage.addAttributes(attrs, range: r)
            consuming?.add(in: r)
        }
    }
}
