import Foundation

/// Pure model for Markdown tables (Tier 4 of the editing epic, #7): insert a
/// starter table and jump cell-to-cell with Tab/Shift-Tab. `BlockFormatting`
/// drives the insert from the Format menu; the editor's `Coordinator` drives
/// the cell-jump from `doCommandBy:` (before falling back to list indent).
enum TableEditing {

    /// The starter table dropped in by the Format menu. Three rows so the header
    /// separator is unmistakable.
    static let template = "| Header | Header |\n| --- | --- |\n| Cell | Cell |"

    // MARK: - Insert

    /// Inserts `template`, replacing a blank current line or dropping below a
    /// non-blank one (blank-line separated). The first `Header` cell is selected
    /// so the user can type straight over it.
    static func insert(text: NSString, selection: NSRange) -> TextEdit? {
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let raw = text.substring(with: lineRange)
        let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        let firstCellOffset = 2                          // past the leading "| "
        let headerLen = ("Header" as NSString).length

        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
            return TextEdit(range: contentRange, replacement: template,
                            selectedRange: NSRange(location: lineRange.location + firstCellOffset, length: headerLen))
        }
        let insertLoc = lineRange.location + (line as NSString).length
        let insertion = "\n\n" + template
        return TextEdit(range: NSRange(location: insertLoc, length: 0), replacement: insertion,
                        selectedRange: NSRange(location: insertLoc + 2 + firstCellOffset, length: headerLen))
    }

    // MARK: - Cell jump

    /// Moves to the next (or previous, when `reverse`) table cell, selecting its
    /// trimmed content. Returns `nil` when the caret isn't inside a table, so
    /// the caller can fall back to its normal Tab handling.
    static func tabJump(text: NSString, selection: NSRange, reverse: Bool) -> TextEdit? {
        let referenceLoc = reverse ? selection.location : NSMaxRange(selection)
        let lineRange = text.lineRange(for: NSRange(location: referenceLoc, length: 0))
        let line = stripNewline(text.substring(with: lineRange)) as NSString
        guard isInTable(text: text, lineRange: lineRange) else { return nil }

        let cells = cellRanges(line)
        guard !cells.isEmpty else { return nil }
        let column = referenceLoc - lineRange.location

        // Which cell holds the reference position? The cell whose right boundary
        // is at or past it.
        let currentIndex = cells.firstIndex { column <= $0.bound } ?? cells.count - 1

        let targetIndex = reverse ? currentIndex - 1 : currentIndex + 1
        if cells.indices.contains(targetIndex) {
            let cell = cells[targetIndex]
            return select(cell.content, inLineAt: lineRange.location)
        }
        return jumpAcrossRows(text: text, fromLine: lineRange, reverse: reverse)
    }

    /// Lands on the first/last cell of the adjacent table row, if any.
    private static func jumpAcrossRows(text: NSString, fromLine: NSRange, reverse: Bool) -> TextEdit? {
        let neighborLoc = reverse ? fromLine.location - 1 : NSMaxRange(fromLine)
        guard neighborLoc >= 0, neighborLoc <= text.length, !(reverse && fromLine.location == 0) else { return nil }
        guard NSMaxRange(fromLine) < text.length || reverse else { return nil }

        let neighbor = text.lineRange(for: NSRange(location: min(neighborLoc, text.length - 1), length: 0))
        guard neighbor.location != fromLine.location else { return nil }
        let line = stripNewline(text.substring(with: neighbor)) as NSString
        let cells = cellRanges(line)
        guard let cell = reverse ? cells.last : cells.first else { return nil }
        return select(cell.content, inLineAt: neighbor.location)
    }

    private static func select(_ content: NSRange, inLineAt lineStart: Int) -> TextEdit {
        let absolute = NSRange(location: lineStart + content.location, length: content.length)
        return TextEdit(range: NSRange(location: absolute.location, length: 0),
                        replacement: "", selectedRange: absolute)
    }

    // MARK: - Table / cell parsing

    /// A pipe-bearing line is treated as a table only when a neighbouring line
    /// also bears a pipe — that two-line minimum keeps a lone `a | b` in prose
    /// from hijacking Tab.
    private static func isInTable(text: NSString, lineRange: NSRange) -> Bool {
        let current = stripNewline(text.substring(with: lineRange))
        guard current.contains("|") else { return false }
        func pipes(_ loc: Int) -> Bool {
            guard loc >= 0, loc < text.length else { return false }
            let r = text.lineRange(for: NSRange(location: loc, length: 0))
            guard r.location != lineRange.location else { return false }
            return stripNewline(text.substring(with: r)).contains("|")
        }
        return pipes(lineRange.location - 1) || pipes(NSMaxRange(lineRange))
    }

    /// One table cell: `bound` is the index of its right-hand `|` (or line end),
    /// used to locate the caret; `content` is the trimmed text to select.
    private struct Cell { let bound: Int; let content: NSRange }

    /// Splits a table row into its cells. The empty segments outside the outer
    /// pipes (when the row is `| a | b |`) are dropped; each remaining cell's
    /// content range trims surrounding spaces.
    private static func cellRanges(_ line: NSString) -> [Cell] {
        // Pipe positions.
        var pipes: [Int] = []
        for i in 0..<line.length where line.character(at: i) == 0x7C { pipes.append(i) } // '|'
        guard !pipes.isEmpty else { return [] }

        // Segment boundaries: line start, each pipe, line end.
        var bounds: [Int] = [-1] + pipes + [line.length]
        var cells: [Cell] = []
        for i in 0..<(bounds.count - 1) {
            let segStart = bounds[i] + 1
            let segEnd = bounds[i + 1]
            // Drop the empty leading/trailing segments around outer pipes.
            let segment = line.substring(with: NSRange(location: segStart, length: segEnd - segStart))
            if (i == 0 || i == bounds.count - 2) && segment.trimmingCharacters(in: .whitespaces).isEmpty {
                continue
            }
            cells.append(Cell(bound: segEnd, content: trimmedRange(in: line, from: segStart, to: segEnd)))
        }
        return cells
    }

    /// The range of `line[from..<to]` with surrounding spaces/tabs removed; a
    /// zero-length caret (at the first content slot) for an empty cell.
    private static func trimmedRange(in line: NSString, from: Int, to: Int) -> NSRange {
        var start = from, end = to
        while start < end, isSpace(line.character(at: start)) { start += 1 }
        while end > start, isSpace(line.character(at: end - 1)) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func isSpace(_ c: unichar) -> Bool { c == 0x20 || c == 0x09 }

    private static func stripNewline(_ s: String) -> String {
        s.hasSuffix("\n") ? String(s.dropLast()) : s
    }
}
