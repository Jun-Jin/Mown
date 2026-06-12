import Foundation

/// The block-level formatting actions surfaced by the editor's Format menu
/// (Tier 3 of the editing epic, #6). Each operates on whole lines and, where it
/// makes sense, toggles (re-applying strips what it added).
enum BlockFormat: Equatable {
    /// Set every selected line to ATX heading level 1…6, or strip the heading
    /// when every line is already at that level (⌘1–⌘6).
    case heading(Int)
    /// Nudge the heading level by ±1 across the selection (⌘] / ⌘[). 0 means a
    /// plain paragraph; clamps to 0…6.
    case bumpHeading(Int)
    /// Prefix/strip `> ` on every selected line.
    case blockquote
    /// Fence the selection in a triple-backtick code block (toggles).
    case codeBlock
    /// Insert a horizontal rule (`---`).
    case horizontalRule
    /// Flip `- [ ]` ⇄ `- [x]` per line, promoting plain lines into tasks.
    case taskToggle
    /// Insert a starter Markdown table.
    case table
}

/// Pure model for the block-formatting actions. Mirrors `InlineFormatting`:
/// every entry point maps text + selection to a single `TextEdit`, with no
/// AppKit dependency, so the logic is unit-testable; `EditorActions` applies
/// the result through the text view's change-tracking path.
enum BlockFormatting {

    /// Dispatches a `BlockFormat` to its handler. Returns `nil` when the action
    /// would be a no-op (so the caller leaves the text untouched).
    static func edit(for format: BlockFormat, text: NSString, selection: NSRange) -> TextEdit? {
        switch format {
        case .heading(let level):   return heading(level: level, text: text, selection: selection)
        case .bumpHeading(let by):  return bumpHeading(by, text: text, selection: selection)
        case .blockquote:           return blockquote(text: text, selection: selection)
        case .codeBlock:            return codeBlock(text: text, selection: selection)
        case .horizontalRule:       return horizontalRule(text: text, selection: selection)
        case .taskToggle:           return taskToggle(text: text, selection: selection)
        case .table:                return TableEditing.insert(text: text, selection: selection)
        }
    }

    // MARK: - Headings

    static func heading(level: Int, text: NSString, selection: NSRange) -> TextEdit? {
        let lvl = min(6, max(1, level))
        return transformLines(text: text, selection: selection) { lines in
            let bodyIdx = lines.indices.filter { !isBlank(lines[$0]) }
            // Toggle off only when every non-blank line is already at this level.
            let allAtLevel = !bodyIdx.isEmpty && bodyIdx.allSatisfy { headingLevel(lines[$0]) == lvl }
            return lines.map { line in
                if isBlank(line) && lines.count > 1 { return line }
                let body = strippedHeading(line)
                return allAtLevel ? body : String(repeating: "#", count: lvl) + " " + body
            }
        }
    }

    static func bumpHeading(_ delta: Int, text: NSString, selection: NSRange) -> TextEdit? {
        transformLines(text: text, selection: selection) { lines in
            lines.map { line in
                if isBlank(line) && lines.count > 1 { return line }
                let current = headingLevel(line) ?? 0
                let next = min(6, max(0, current + delta))
                let body = strippedHeading(line)
                return next == 0 ? body : String(repeating: "#", count: next) + " " + body
            }
        }
    }

    private static let headingRegex = try! NSRegularExpression(pattern: #"^(#{1,6})(?:[ \t]+(.*)|[ \t]*)$"#)

    /// The heading level of an ATX line (`### x` → 3), or `nil` when it isn't a
    /// heading.
    private static func headingLevel(_ line: String) -> Int? {
        let ns = line as NSString
        guard let m = headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return m.range(at: 1).length
    }

    /// The text of a line with any leading ATX heading markup removed.
    private static func strippedHeading(_ line: String) -> String {
        let ns = line as NSString
        guard let m = headingRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return line
        }
        let r = m.range(at: 2)
        return r.location == NSNotFound ? "" : ns.substring(with: r)
    }

    // MARK: - Blockquote

    private static let quoteRegex = try! NSRegularExpression(pattern: #"^[ \t]*>[ \t]?(.*)$"#)

    static func blockquote(text: NSString, selection: NSRange) -> TextEdit? {
        transformLines(text: text, selection: selection) { lines in
            let bodyIdx = lines.indices.filter { !isBlank(lines[$0]) }
            let allQuoted = !bodyIdx.isEmpty && bodyIdx.allSatisfy { isQuoted(lines[$0]) }
            return lines.map { line in
                if allQuoted { return stripQuote(line) }
                if isBlank(line) && lines.count > 1 { return line }
                return "> " + line
            }
        }
    }

    private static func isQuoted(_ line: String) -> Bool {
        let ns = line as NSString
        return quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func stripQuote(_ line: String) -> String {
        let ns = line as NSString
        guard let m = quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return line
        }
        return ns.substring(with: m.range(at: 1))
    }

    // MARK: - Code block

    static func codeBlock(text: NSString, selection: NSRange) -> TextEdit? {
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        let content = hadTrailingNewline ? String(block.dropLast()) : block
        let lines = content.components(separatedBy: "\n")

        // Already fenced → unwrap.
        if lines.count >= 2, isFence(lines.first!), isFence(lines.last!) {
            let inner = lines.dropFirst().dropLast().joined(separator: "\n")
            let replacement = inner + (hadTrailingNewline ? "\n" : "")
            return TextEdit(range: lineRange, replacement: replacement,
                            selectedRange: NSRange(location: lineRange.location, length: (inner as NSString).length))
        }

        let fenced = "```\n" + content + "\n```"
        let replacement = fenced + (hadTrailingNewline ? "\n" : "")
        // Select the original content, now sitting between the fences (after the
        // opening "```\n").
        let selected = NSRange(location: lineRange.location + 4, length: (content as NSString).length)
        return TextEdit(range: lineRange, replacement: replacement, selectedRange: selected)
    }

    private static func isFence(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    // MARK: - Horizontal rule

    static func horizontalRule(text: NSString, selection: NSRange) -> TextEdit? {
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let raw = text.substring(with: lineRange)
        let line = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw

        if line.trimmingCharacters(in: .whitespaces).isEmpty {
            // Turn the blank line itself into the rule; its trailing newline (if
            // any) stays put.
            let contentRange = NSRange(location: lineRange.location, length: (line as NSString).length)
            return TextEdit(range: contentRange, replacement: "---",
                            selectedRange: NSRange(location: lineRange.location + 3, length: 0))
        }
        // Drop the rule onto its own line below, blank-line separated.
        let insertLoc = lineRange.location + (line as NSString).length
        let insertion = "\n\n---\n"
        return TextEdit(range: NSRange(location: insertLoc, length: 0), replacement: insertion,
                        selectedRange: NSRange(location: insertLoc + (insertion as NSString).length, length: 0))
    }

    // MARK: - Task toggle

    private static let taskRegex = try! NSRegularExpression(pattern: #"^([ \t]*[-*+][ \t]+)\[([ xX])\]([ \t]+.*|[ \t]*)$"#)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^([ \t]*[-*+][ \t]+)(.*)$"#)
    private static let indentRegex = try! NSRegularExpression(pattern: #"^([ \t]*)(.*)$"#)

    static func taskToggle(text: NSString, selection: NSRange) -> TextEdit? {
        transformLines(text: text, selection: selection) { lines in
            lines.map { line in
                if isBlank(line) && lines.count > 1 { return line }
                return toggledTask(line)
            }
        }
    }

    /// A task line flips its checkbox; a bullet gains an unchecked box; anything
    /// else becomes an unchecked task item. Repeated application then cycles
    /// `[ ]` ⇄ `[x]`.
    private static func toggledTask(_ line: String) -> String {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        if let m = taskRegex.firstMatch(in: line, range: full) {
            let prefix = ns.substring(with: m.range(at: 1))
            let mark = ns.substring(with: m.range(at: 2))
            let rest = ns.substring(with: m.range(at: 3))
            let box = mark == " " ? "[x]" : "[ ]"
            return prefix + box + rest
        }
        if let m = bulletRegex.firstMatch(in: line, range: full) {
            return ns.substring(with: m.range(at: 1)) + "[ ] " + ns.substring(with: m.range(at: 2))
        }
        if let m = indentRegex.firstMatch(in: line, range: full) {
            return ns.substring(with: m.range(at: 1)) + "- [ ] " + ns.substring(with: m.range(at: 2))
        }
        return "- [ ] " + line
    }

    // MARK: - Whole-line transform core

    private static func isBlank(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Rebuilds the lines covered by `selection` through `body` and maps the
    /// selection onto the result. A caret keeps its column (shifted by the
    /// prefix change on its line); a range re-selects the rewritten block so
    /// repeated invocation works. Returns `nil` when nothing changed.
    private static func transformLines(text: NSString, selection: NSRange,
                                       _ body: ([String]) -> [String]) -> TextEdit? {
        let lineRange = text.lineRange(for: selection)
        let block = text.substring(with: lineRange)
        let hadTrailingNewline = block.hasSuffix("\n")
        var lines = block.components(separatedBy: "\n")
        if hadTrailingNewline { lines.removeLast() }

        let newLines = body(lines)
        let newBlock = newLines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        guard newBlock != block else { return nil }

        let selected = mapSelection(selection, blockStart: lineRange.location,
                                    oldLines: lines, newLines: newLines,
                                    hadTrailingNewline: hadTrailingNewline)
        return TextEdit(range: lineRange, replacement: newBlock, selectedRange: selected)
    }

    private static func mapSelection(_ selection: NSRange, blockStart: Int,
                                     oldLines: [String], newLines: [String],
                                     hadTrailingNewline: Bool) -> NSRange {
        func start(_ lines: [String], _ idx: Int) -> Int {
            var off = blockStart
            for i in 0..<idx { off += (lines[i] as NSString).length + 1 }
            return off
        }

        if selection.length == 0 {
            // Locate the caret's line and column, then keep the column relative
            // to content by shifting it by that line's length change.
            var idx = 0
            for i in oldLines.indices {
                let lineStart = start(oldLines, i)
                let lineEnd = lineStart + (oldLines[i] as NSString).length
                if selection.location <= lineEnd { idx = i; break }
                idx = i
            }
            let column = selection.location - start(oldLines, idx)
            let delta = (newLines[idx] as NSString).length - (oldLines[idx] as NSString).length
            let newColumn = min(max(0, column + delta), (newLines[idx] as NSString).length)
            return NSRange(location: start(newLines, idx) + newColumn, length: 0)
        }

        // Re-select the rewritten lines (excluding the trailing newline).
        let joined = newLines.joined(separator: "\n") as NSString
        return NSRange(location: blockStart, length: joined.length)
    }
}
