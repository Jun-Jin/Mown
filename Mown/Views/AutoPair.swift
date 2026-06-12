import Foundation

/// Pure model for "wrap the selection instead of replacing it" when a pairing
/// character is typed over a selection (Tier 4 of the editing epic, #7). Typing
/// `*`, `_`, `` ` `` or `[` with text selected surrounds it rather than
/// overwriting it. `MownTextView.insertText` consults this before the default
/// insertion.
enum AutoPair {
    /// Opening → closing delimiter for each character that wraps. `[` pairs with
    /// `]`; the symmetric marks pair with themselves.
    private static let pairs: [String: String] = [
        "*": "*", "_": "_", "`": "`", "[": "]",
    ]

    /// Returns the wrap edit when `typed` is a single pairing character and the
    /// selection is non-empty; otherwise `nil` (the caller inserts normally).
    /// The wrapped text stays selected so a further keystroke can wrap again.
    static func wrap(typing typed: String, text: NSString, selection: NSRange) -> TextEdit? {
        guard selection.length > 0, let close = pairs[typed] else { return nil }
        let selected = text.substring(with: selection)
        return TextEdit(range: selection,
                        replacement: typed + selected + close,
                        selectedRange: NSRange(location: selection.location + (typed as NSString).length,
                                               length: selection.length))
    }
}
