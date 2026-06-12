import Foundation

/// Pure model for whole-line moves (Tier 4 of the editing epic, #7): move the
/// selected line(s) up/down and duplicate them. Like the other editing models
/// it maps text + selection to a `TextEdit` with no AppKit dependency, so it is
/// unit-testable; `MownTextView` drives it from `keyDown`.
enum LineEditing {
    enum Direction { case up, down }

    /// Swaps the line(s) spanning the selection with the neighbouring line in
    /// `direction`, carrying the selection with them. Returns `nil` at the
    /// document edge (nothing to swap with).
    static func move(_ direction: Direction, text: NSString, selection: NSRange) -> TextEdit? {
        let block = text.lineRange(for: selection)

        switch direction {
        case .up:
            guard block.location > 0 else { return nil }
            let prev = text.lineRange(for: NSRange(location: block.location - 1, length: 0))
            return swap(text: text, first: prev, second: block, selection: selection, movingFirst: false)
        case .down:
            guard NSMaxRange(block) < text.length else { return nil }
            let next = text.lineRange(for: NSRange(location: NSMaxRange(block), length: 0))
            return swap(text: text, first: block, second: next, selection: selection, movingFirst: true)
        }
    }

    /// Reorders two adjacent line ranges (`first` immediately precedes
    /// `second`). `movingFirst` says which of the two carries the user's
    /// selection: the selected block is `first` when moving down, `second` when
    /// moving up.
    private static func swap(text: NSString, first: NSRange, second: NSRange,
                             selection: NSRange, movingFirst: Bool) -> TextEdit {
        let union = NSRange(location: first.location, length: NSMaxRange(second) - first.location)
        let unionStr = text.substring(with: union)
        let hadTrailingNewline = unionStr.hasSuffix("\n")
        var lines = unionStr.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        // Split the union back into the two ranges' lines. Either side can span
        // multiple lines (a multi-line selection moving down makes `first` the
        // block), so count `first`'s logical lines rather than assuming one.
        let firstStr = text.substring(with: first)
        var firstLineCount = firstStr.components(separatedBy: "\n").count
        if firstStr.hasSuffix("\n") { firstLineCount -= 1 }
        let firstLines = Array(lines[0..<firstLineCount])
        let secondLines = Array(lines[firstLineCount...])
        let reordered = secondLines + firstLines

        let newUnion = reordered.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")

        // The selected block keeps its text; only its offset within the union
        // shifts. When moving down it now sits after `second`; when moving up it
        // moves to the front.
        let movedBlock = movingFirst ? first : second
        let withinOffset = selection.location - movedBlock.location
        let newBlockStart: Int
        if movingFirst {
            // first → after secondLines (+ the newline joining them).
            newBlockStart = union.location + (secondLines.joined(separator: "\n") as NSString).length + 1
        } else {
            newBlockStart = union.location
        }
        let newSelection = NSRange(location: newBlockStart + withinOffset, length: selection.length)
        return TextEdit(range: union, replacement: newUnion, selectedRange: newSelection)
    }

    /// Copies the line(s) spanning the selection directly below, then moves the
    /// selection onto the copy so a repeated press keeps duplicating.
    static func duplicate(text: NSString, selection: NSRange) -> TextEdit {
        let block = text.lineRange(for: selection)
        let blockStr = text.substring(with: block)
        let endsWithNewline = blockStr.hasSuffix("\n")
        // A newline-terminated block copies as-is right after itself; an
        // unterminated last line needs a separating newline first.
        let insertion = endsWithNewline ? blockStr : "\n" + blockStr
        let copyStart = endsWithNewline ? NSMaxRange(block) : NSMaxRange(block) + 1
        let withinOffset = selection.location - block.location
        return TextEdit(range: NSRange(location: NSMaxRange(block), length: 0),
                        replacement: insertion,
                        selectedRange: NSRange(location: copyStart + withinOffset, length: selection.length))
    }
}
