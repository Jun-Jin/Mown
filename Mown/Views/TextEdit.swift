import AppKit

/// A single text replacement plus where the selection should land afterwards —
/// the common currency of the Markdown editing models added in the editing
/// epic (#3). `ListEditing` and `InlineFormatting` predate this and keep their
/// own equivalent `Edit` structs; everything newer (`BlockFormatting`,
/// `LineEditing`, `AutoPair`, `SmartPaste`, `TableEditing`) returns a
/// `TextEdit` so they share one application path.
///
/// Like those models, a `TextEdit` is pure data: the models map text +
/// selection to a `TextEdit` with no AppKit side effects, so they can be unit
/// tested without an `NSTextView`. `NSTextView.apply(_:)` is the only place
/// that touches the live view.
struct TextEdit: Equatable {
    /// Characters to replace (UTF-16 range, matching `NSString`).
    let range: NSRange
    let replacement: String
    /// Selection/caret to set once the replacement is in place.
    let selectedRange: NSRange
}

extension NSTextView {
    /// Applies a `TextEdit` through the change-tracking path so undo coalescing,
    /// the SwiftUI binding push (`textDidChange`), and the highlighter's storage
    /// delegate all fire exactly as for a typed edit.
    ///
    /// A pure navigation edit (zero-length range, empty replacement) only moves
    /// the selection — it skips `shouldChangeText` so table cell-jumps and the
    /// like don't litter the undo stack with empty edits.
    @discardableResult
    func apply(_ edit: TextEdit) -> Bool {
        if edit.range.length == 0, edit.replacement.isEmpty {
            setSelectedRange(edit.selectedRange)
            return true
        }
        guard shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return false }
        textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()
        setSelectedRange(edit.selectedRange)
        return true
    }
}
