import Foundation

/// Pure model for Markdown list/line editing actions (Tier 1 of the editing
/// epic, #4). Each entry point takes the current text plus selection and
/// returns an `Edit` — a single replacement range, its replacement string, and
/// where the selection should land afterwards — or `nil` when the keystroke has
/// no list-aware meaning (the caller then lets `NSTextView` do its default).
///
/// The type is intentionally Foundation-only and side-effect-free so it can be
/// unit-tested without an `NSTextView`. The editor's `Coordinator` is the only
/// thing that touches AppKit: it applies the returned `Edit` through
/// `shouldChangeText`/`textStorage` so undo and syntax highlighting keep
/// working.
enum ListEditing {
    /// One indent level. Two spaces keeps nested markers visually aligned with
    /// the parent's content under proportional and monospaced fonts alike.
    static let indentUnit = "  "

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

    // MARK: - Public entry points

    /// Tab. Adds one indent level to every list line in the selection (or the
    /// cursor's line), then renumbers the surrounding ordered list.
    static func indent(text: NSString, selection: NSRange) -> Edit? {
        reindent(text: text, selection: selection, delta: 1)
    }

    /// Shift-Tab. Removes one indent level from every list line in the
    /// selection. Returns `nil` when nothing is indented (so the editor's
    /// default backtab applies).
    static func outdent(text: NSString, selection: NSRange) -> Edit? {
        reindent(text: text, selection: selection, delta: -1)
    }

    /// Return. Continues a list/blockquote onto a fresh line, or — on an
    /// otherwise empty item — clears the orphan marker to exit the list.
    static func newline(text: NSString, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let rawLine = text.substring(with: lineRange)
        let line = stripNewline(rawLine)
        let lineContentEnd = lineRange.location + (line as NSString).length
        let atLineEnd = selection.location == lineContentEnd

        if let item = parse(line) {
            let task = taskInfo(item.content)
            let isEmpty = task.isTask ? task.remainder.isEmpty
                                      : item.content.trimmingCharacters(in: .whitespaces).isEmpty
            if isEmpty {
                // Pressing Return on a bare marker exits the list: blank the
                // line and drop the cursor at its start.
                return Edit(range: NSRange(location: lineRange.location, length: (line as NSString).length),
                            replacement: "",
                            selectedRange: NSRange(location: lineRange.location, length: 0))
            }
            guard atLineEnd else { return nil }
            var prefix = item.indent
            if let n = item.number, let delim = item.delimiter {
                prefix += "\(n + 1)\(delim)\(item.spacing)"
            } else if let bullet = item.bullet {
                prefix += "\(bullet)\(item.spacing)"
            }
            if task.isTask { prefix += "[ ] " }
            let insertion = "\n" + prefix
            let caret = selection.location + (insertion as NSString).length
            return Edit(range: NSRange(location: selection.location, length: 0),
                        replacement: insertion,
                        selectedRange: NSRange(location: caret, length: 0))
        }

        if let quote = parseQuote(line) {
            if quote.content.trimmingCharacters(in: .whitespaces).isEmpty {
                return Edit(range: NSRange(location: lineRange.location, length: (line as NSString).length),
                            replacement: "",
                            selectedRange: NSRange(location: lineRange.location, length: 0))
            }
            guard atLineEnd else { return nil }
            let insertion = "\n" + quote.indent + quote.markers
            let caret = selection.location + (insertion as NSString).length
            return Edit(range: NSRange(location: selection.location, length: 0),
                        replacement: insertion,
                        selectedRange: NSRange(location: caret, length: 0))
        }

        return nil
    }

    /// Delete (backspace). When the caret sits just after a list marker,
    /// removes the whole marker (e.g. `- `) in one stroke instead of a single
    /// character. Indentation is preserved.
    static func backspace(text: NSString, selection: NSRange) -> Edit? {
        guard selection.length == 0 else { return nil }
        let lineRange = text.lineRange(for: NSRange(location: selection.location, length: 0))
        let line = stripNewline(text.substring(with: lineRange))
        guard let item = parse(line) else { return nil }
        let indentLen = (item.indent as NSString).length
        let markerLen = (item.markerString as NSString).length + (item.spacing as NSString).length
        let contentStart = lineRange.location + indentLen + markerLen
        guard selection.location == contentStart else { return nil }
        let markerStart = lineRange.location + indentLen
        return Edit(range: NSRange(location: markerStart, length: markerLen),
                    replacement: "",
                    selectedRange: NSRange(location: markerStart, length: 0))
    }

    // MARK: - Indent / outdent core

    private static func reindent(text: NSString, selection: NSRange, delta: Int) -> Edit? {
        let selLines = text.lineRange(for: selection)

        // Extend the replacement downward through the contiguous list block so
        // following ordered siblings renumber too.
        var blockEnd = NSMaxRange(selLines)
        while blockEnd < text.length {
            let next = text.lineRange(for: NSRange(location: blockEnd, length: 0))
            if isListItem(stripNewline(text.substring(with: next))) {
                blockEnd = NSMaxRange(next)
            } else { break }
        }
        let blockRange = NSRange(location: selLines.location, length: blockEnd - selLines.location)
        let blockStr = text.substring(with: blockRange)
        let hadTrailingNewline = blockStr.hasSuffix("\n")
        var origLines = blockStr.components(separatedBy: "\n")
        if hadTrailingNewline { origLines.removeLast() }

        // The selected lines are the prefix of the block (it starts at
        // `selLines.location`). Count how many lines the selection spans.
        let selStr = text.substring(with: selLines)
        var selCount = selStr.components(separatedBy: "\n").count
        if selStr.hasSuffix("\n") { selCount -= 1 }
        selCount = min(max(selCount, 1), origLines.count)

        guard origLines[0..<selCount].contains(where: isListItem) else { return nil }

        var lines = origLines
        for i in 0..<selCount where isListItem(lines[i]) {
            lines[i] = delta > 0 ? indentUnit + lines[i] : removeOneIndent(lines[i])
        }

        // Seed the ordered-list counters from the list items immediately above
        // the block so the first renumbered item continues their sequence.
        var counters: [Int: Int] = [:]
        var seedLoc = selLines.location
        var seeds: [String] = []
        while seedLoc > 0 {
            let prev = text.lineRange(for: NSRange(location: seedLoc - 1, length: 0))
            let s = stripNewline(text.substring(with: prev))
            if isListItem(s) { seeds.insert(s, at: 0); seedLoc = prev.location } else { break }
        }
        for s in seeds { _ = renumber(s, counters: &counters) }
        for i in lines.indices {
            if let fixed = renumber(lines[i], counters: &counters) { lines[i] = fixed }
        }

        let newBlock = lines.joined(separator: "\n") + (hadTrailingNewline ? "\n" : "")
        guard newBlock != blockStr else { return nil }

        let newSelection = mapSelection(selection,
                                        blockStart: blockRange.location,
                                        origLines: origLines,
                                        newLines: lines,
                                        selCount: selCount,
                                        originalText: text)
        return Edit(range: blockRange, replacement: newBlock, selectedRange: newSelection)
    }

    /// Maps the pre-edit selection onto the rebuilt block. A bare caret keeps
    /// the text to its right invariant; a range re-selects the edited lines so
    /// repeated Tab works.
    private static func mapSelection(_ selection: NSRange,
                                     blockStart: Int,
                                     origLines: [String],
                                     newLines: [String],
                                     selCount: Int,
                                     originalText: NSString) -> NSRange {
        func newLineStart(_ idx: Int) -> Int {
            var off = blockStart
            for i in 0..<idx { off += (newLines[i] as NSString).length + 1 }
            return off
        }

        if selection.length == 0 {
            let pre = originalText.substring(with: NSRange(location: blockStart,
                                                           length: selection.location - blockStart))
            let preNS = pre as NSString
            let idx = pre.components(separatedBy: "\n").count - 1
            let lastSegment = pre.components(separatedBy: "\n").last ?? ""
            let lineStartInOrig = blockStart + preNS.length - (lastSegment as NSString).length
            let column = selection.location - lineStartInOrig
            let origLen = (origLines[idx] as NSString).length
            let charsAfter = origLen - column
            let newLen = (newLines[idx] as NSString).length
            let newColumn = max(0, newLen - charsAfter)
            return NSRange(location: newLineStart(idx) + newColumn, length: 0)
        }

        let start = blockStart
        let lastIdx = selCount - 1
        let end = newLineStart(lastIdx) + (newLines[lastIdx] as NSString).length
        return NSRange(location: start, length: end - start)
    }

    // MARK: - Ordered-list renumbering

    /// Feeds one line through the running ordered-list counters keyed by indent
    /// width. Returns a rewritten line when its number changed, else `nil`.
    private static func renumber(_ line: String, counters: inout [Int: Int]) -> String? {
        guard let item = parse(line) else { counters.removeAll(); return nil }
        let width = indentWidth(item.indent)
        for key in counters.keys where key > width { counters[key] = nil }
        guard let current = item.number, let delim = item.delimiter else {
            // A bullet breaks any ordered run at its indent.
            counters[width] = nil
            return nil
        }
        let n = counters[width].map { $0 + 1 } ?? current
        counters[width] = n
        guard n != current else { return nil }
        return item.indent + "\(n)\(delim)" + item.spacing + item.content
    }

    // MARK: - Parsing

    private struct Item {
        var indent: String
        var bullet: Character?      // - * +
        var number: Int?            // ordered list ordinal
        var delimiter: Character?   // . or )
        var spacing: String         // whitespace between marker and content
        var content: String         // text after the marker

        /// The marker glyph without indent or spacing (e.g. `-` or `12.`).
        var markerString: String {
            if let number, let delimiter { return "\(number)\(delimiter)" }
            return bullet.map(String.init) ?? ""
        }
    }

    private static let itemRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)(?:([-*+])|([0-9]{1,9})([.)]))([ \t]+)(.*)$"#)

    private static func parse(_ line: String) -> Item? {
        let ns = line as NSString
        guard let m = itemRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        return Item(indent: group(1) ?? "",
                    bullet: group(2)?.first,
                    number: group(3).flatMap { Int($0) },
                    delimiter: group(4)?.first,
                    spacing: group(5) ?? " ",
                    content: group(6) ?? "")
    }

    private static func isListItem(_ line: String) -> Bool { parse(line) != nil }

    private struct Quote {
        var indent: String
        var markers: String   // the run of `>` plus following space(s)
        var content: String
    }

    private static let quoteRegex = try! NSRegularExpression(
        pattern: #"^([ \t]*)((?:>[ \t]?)+)(.*)$"#)

    private static func parseQuote(_ line: String) -> Quote? {
        let ns = line as NSString
        guard let m = quoteRegex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        func group(_ i: Int) -> String { ns.substring(with: m.range(at: i)) }
        return Quote(indent: group(1), markers: group(2), content: group(3))
    }

    private static let taskRegex = try! NSRegularExpression(
        pattern: #"^\[([ xX])\](?:[ \t]+(.*))?$"#)

    /// Splits a `[ ] remainder` task-list body into its checkbox and the text
    /// after it. `isTask` is false for ordinary list content.
    private static func taskInfo(_ content: String) -> (isTask: Bool, remainder: String) {
        let ns = content as NSString
        guard let m = taskRegex.firstMatch(in: content, range: NSRange(location: 0, length: ns.length)) else {
            return (false, content)
        }
        let r = m.range(at: 2)
        return (true, r.location == NSNotFound ? "" : ns.substring(with: r))
    }

    // MARK: - Whitespace helpers

    private static func stripNewline(_ s: String) -> String {
        s.hasSuffix("\n") ? String(s.dropLast()) : s
    }

    /// Visual width of leading whitespace; a tab counts as one indent level.
    private static func indentWidth(_ indent: String) -> Int {
        indent.reduce(0) { $0 + ($1 == "\t" ? indentUnit.count : 1) }
    }

    private static func removeOneIndent(_ line: String) -> String {
        if line.hasPrefix(indentUnit) { return String(line.dropFirst(indentUnit.count)) }
        if line.hasPrefix(" ") { return String(line.dropFirst()) }
        if line.hasPrefix("\t") { return String(line.dropFirst()) }
        return line
    }
}
