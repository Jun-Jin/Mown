import Foundation

/// The inline-formatting actions surfaced by the editor's Format menu
/// (Tier 2 of the editing epic, #5).
enum InlineFormat {
    case bold
    case italic
    case code
    case strikethrough
    case link

    /// The paired Markdown delimiter wrapped around the selection. Empty for
    /// `.link`, which has an asymmetric `[text](url)` shape handled separately.
    var marker: String {
        switch self {
        case .bold:          return "**"
        case .italic:        return "*"
        case .code:          return "`"
        case .strikethrough: return "~~"
        case .link:          return ""
        }
    }
}

/// Pure model for the inline-formatting toggles. Like `ListEditing`, every
/// entry point maps text + selection to a single `Edit` so it can be unit
/// tested without an `NSTextView`; `EditorActions` applies the result through
/// the text view's change-tracking path to preserve undo and highlighting.
enum InlineFormatting {

    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let selectedRange: NSRange

        static func == (lhs: Edit, rhs: Edit) -> Bool {
            NSEqualRanges(lhs.range, rhs.range) &&
            lhs.replacement == rhs.replacement &&
            NSEqualRanges(lhs.selectedRange, rhs.selectedRange)
        }
    }

    /// Wraps the selection in `format`'s delimiters, or strips them when the
    /// selection is already wrapped (markers inside *or* immediately outside the
    /// selection). With an empty selection it inserts an empty pair and drops
    /// the caret between them.
    static func toggle(_ format: InlineFormat, text: NSString, selection: NSRange) -> Edit {
        let marker = format.marker
        let mlen = (marker as NSString).length

        guard selection.length > 0 else {
            let caret = selection.location + mlen
            return Edit(range: selection,
                        replacement: marker + marker,
                        selectedRange: NSRange(location: caret, length: 0))
        }

        let selected = text.substring(with: selection)

        // Already wrapped, markers inside the selection → unwrap.
        if selected.count >= 2 * marker.count,
           selected.hasPrefix(marker), selected.hasSuffix(marker) {
            let inner = String(selected.dropFirst(marker.count).dropLast(marker.count))
            return Edit(range: selection,
                        replacement: inner,
                        selectedRange: NSRange(location: selection.location,
                                               length: (inner as NSString).length))
        }

        // Markers sit just outside the selection → unwrap them too.
        let beforeLoc = selection.location - mlen
        let afterLoc = NSMaxRange(selection)
        let before = beforeLoc >= 0 ? text.substring(with: NSRange(location: beforeLoc, length: mlen)) : ""
        let after = afterLoc + mlen <= text.length ? text.substring(with: NSRange(location: afterLoc, length: mlen)) : ""
        if before == marker, after == marker {
            let outer = NSRange(location: beforeLoc, length: selection.length + 2 * mlen)
            return Edit(range: outer,
                        replacement: selected,
                        selectedRange: NSRange(location: beforeLoc, length: selection.length))
        }

        // Otherwise wrap, keeping the original text selected.
        return Edit(range: selection,
                    replacement: marker + selected + marker,
                    selectedRange: NSRange(location: selection.location + mlen, length: selection.length))
    }

    /// Builds a `[text](url)` link. With a selection, the selected text becomes
    /// the link text and the caret/selection lands in the URL slot (pre-filled
    /// and selected when `clipboardURL` is a URL). With an empty selection it
    /// inserts `[](url)` and drops the caret in the empty text slot.
    static func link(text: NSString, selection: NSRange, clipboardURL: String? = nil) -> Edit {
        let url = clipboardURL ?? ""
        let urlLen = (url as NSString).length

        guard selection.length > 0 else {
            let insertion = "[](\(url))"
            return Edit(range: selection,
                        replacement: insertion,
                        selectedRange: NSRange(location: selection.location + 1, length: 0))
        }

        let selected = text.substring(with: selection)
        let insertion = "[\(selected)](\(url))"
        // "[" + selected + "](" precedes the URL slot.
        let urlStart = selection.location + 1 + (selected as NSString).length + 2
        return Edit(range: selection,
                    replacement: insertion,
                    selectedRange: NSRange(location: urlStart, length: urlLen))
    }
}
