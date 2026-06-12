import Foundation

/// Recognises a web URL in pasteboard/clipboard text and normalises it. Shared
/// by `EditorActions` (⌘K pre-fill) and `SmartPaste` so both treat the same
/// strings as links.
enum WebURL {
    /// The trimmed string as an `http(s)` URL, adding a scheme for bare `www.`
    /// hosts, or `nil` when it isn't a single web URL.
    static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return trimmed
        }
        if trimmed.hasPrefix("www."), trimmed.dropFirst(4).contains(".") {
            return "https://" + trimmed
        }
        return nil
    }
}

/// Pure model for smart paste (Tier 4 of the editing epic, #7): pasting a URL
/// over a selection makes a Markdown link, and pasting tab-separated rows makes
/// a Markdown table. `MownTextView.paste` consults this before AppKit's default
/// paste; `nil` means "paste normally".
enum SmartPaste {
    /// Builds the smart-paste edit for `pasted` at `selection`, or `nil` when no
    /// rewrite applies.
    static func transform(pasted: String, text: NSString, selection: NSRange) -> TextEdit? {
        // A URL pasted over selected text becomes the link target.
        if selection.length > 0, let url = WebURL.normalized(pasted) {
            let selected = text.substring(with: selection)
            let link = "[\(selected)](\(url))"
            return TextEdit(range: selection, replacement: link,
                            selectedRange: NSRange(location: selection.location, length: (link as NSString).length))
        }
        // Tab-separated text becomes a Markdown table.
        if let table = markdownTable(from: pasted) {
            return TextEdit(range: selection, replacement: table,
                            selectedRange: NSRange(location: selection.location, length: (table as NSString).length))
        }
        return nil
    }

    /// Converts tab-separated rows into a GitHub-style Markdown table. Returns
    /// `nil` when the text has no tabs (nothing tabular to align).
    static func markdownTable(from raw: String) -> String? {
        let body = raw.hasSuffix("\n") ? String(raw.dropLast()) : raw
        let rows = body.components(separatedBy: "\n").map { $0.components(separatedBy: "\t") }
        guard rows.contains(where: { $0.count > 1 }) else { return nil }

        let columns = rows.map(\.count).max() ?? 1
        func render(_ cells: [String]) -> String {
            let padded = (0..<columns).map { i in
                i < cells.count ? cells[i].trimmingCharacters(in: .whitespaces) : ""
            }
            return "| " + padded.joined(separator: " | ") + " |"
        }

        var lines = [render(rows[0])]
        lines.append("| " + Array(repeating: "---", count: columns).joined(separator: " | ") + " |")
        for row in rows.dropFirst() { lines.append(render(row)) }
        return lines.joined(separator: "\n")
    }
}
