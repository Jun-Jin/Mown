import Foundation

/// Pulls TeX math out of Markdown *before* cmark parses it.
///
/// cmark-gfm has no notion of math, so left to itself it mangles common TeX:
/// `$a_b_c$` becomes `$a<em>b</em>c$` (the underscores read as emphasis) and
/// backslash sequences get escaped. We sidestep that by replacing every math
/// span with an inert, alphanumeric placeholder token that cmark passes through
/// verbatim, then — after cmark renders the HTML — swapping the tokens back as
/// `<span class="mown-math">` / `<div class="mown-math">` elements that carry
/// the raw TeX as (HTML-escaped) text for KaTeX to render in the preview.
///
/// Supported delimiters:
///   - inline `$…$`
///   - block  `$$…$$`     (may span multiple lines)
///   - fenced ` ```math `  code blocks
///
/// Math inside fenced code blocks and inline code spans is left untouched.
enum MathExtractor {
    struct Span {
        let tex: String
        /// `true` for display/block math (` $$ `, ` ```math `), `false` for inline ` $…$ `.
        let display: Bool
    }

    struct Result {
        let markdown: String
        /// token → math span. Empty when the document has no math.
        let spans: [String: Span]
        var hasMath: Bool { !spans.isEmpty }
    }

    /// Token core that cmark won't touch: pure ASCII letters/digits, no
    /// Markdown-significant characters, and unlikely to occur in real prose.
    private static let tokenPrefix = "xMownMathToken"
    private static let tokenSuffix = "Endx"

    // MARK: - Extraction

    static func extract(_ markdown: String) -> Result {
        var spans: [String: Span] = [:]
        var counter = 0

        func makeToken(_ tex: String, display: Bool) -> String {
            let token = "\(tokenPrefix)\(counter)\(tokenSuffix)"
            counter += 1
            spans[token] = Span(tex: tex, display: display)
            return token
        }

        let lines = markdown.components(separatedBy: "\n")
        var outLines: [String] = []
        var textBuffer: [String] = []

        // Consecutive non-code lines are scanned together so a `$$…$$` block can
        // span several lines; a code line (or ```math block) flushes the buffer.
        func flushText() {
            guard !textBuffer.isEmpty else { return }
            outLines.append(scanText(textBuffer.joined(separator: "\n"), makeToken: makeToken))
            textBuffer.removeAll(keepingCapacity: true)
        }

        var inFence = false
        var fenceMarker: Character = "`"
        var fenceLen = 0

        var l = 0
        while l < lines.count {
            let line = lines[l]

            if let fence = fenceInfo(line) {
                if inFence {
                    // A matching, info-less fence of equal-or-greater length closes the block.
                    if fence.marker == fenceMarker, fence.length >= fenceLen, fence.info.isEmpty {
                        inFence = false
                    }
                    outLines.append(line)
                    l += 1
                    continue
                }

                if firstWord(fence.info).lowercased() == "math" {
                    // ```math … ``` → one display span. Collect until the closing fence.
                    flushText()
                    var body: [String] = []
                    l += 1
                    while l < lines.count {
                        if let close = fenceInfo(lines[l]),
                           close.marker == fence.marker, close.length >= fence.length, close.info.isEmpty {
                            break
                        }
                        body.append(lines[l])
                        l += 1
                    }
                    let token = makeToken(body.joined(separator: "\n"), display: true)
                    outLines.append("")
                    outLines.append(token)
                    outLines.append("")
                    l += 1 // skip the closing fence (no-op if we ran off the end)
                    continue
                }

                // A normal fenced code block opens here.
                flushText()
                inFence = true
                fenceMarker = fence.marker
                fenceLen = fence.length
                outLines.append(line)
                l += 1
                continue
            }

            if inFence {
                outLines.append(line) // code content, verbatim
            } else {
                textBuffer.append(line)
            }
            l += 1
        }

        flushText()
        return Result(markdown: outLines.joined(separator: "\n"), spans: spans)
    }

    // MARK: - Reinsertion

    /// Swaps placeholder tokens in cmark's HTML output back for KaTeX containers.
    static func reinsert(into html: String, spans: [String: Span]) -> String {
        guard !spans.isEmpty else { return html }
        var result = html
        for (token, span) in spans {
            let escaped = htmlEscape(span.tex)
            if span.display {
                let div = "<div class=\"mown-math\" data-display=\"1\">\(escaped)</div>"
                // A block token sits alone, so cmark wraps it in its own paragraph.
                result = result.replacingOccurrences(of: "<p>\(token)</p>", with: div)
                result = result.replacingOccurrences(of: token, with: div) // fallback
            } else {
                let span = "<span class=\"mown-math\" data-display=\"0\">\(escaped)</span>"
                result = result.replacingOccurrences(of: token, with: span)
            }
        }
        return result
    }

    // MARK: - Inline scanning

    /// Scans a code-free text region, replacing `$$…$$` and `$…$` with tokens
    /// while leaving inline code spans (and their `$`) untouched.
    private static func scanText(_ text: String,
                                 makeToken: (String, Bool) -> String) -> String {
        let a = Array(text)
        let n = a.count
        var out = ""
        var i = 0

        while i < n {
            let c = a[i]

            // Inline code span: copy the opening run, then everything up to and
            // including a closing run of the same length. `$` inside is literal.
            if c == "`" {
                var run = 0
                while i < n, a[i] == "`" { run += 1; i += 1 }
                out += String(repeating: "`", count: run)
                if let close = matchingBacktickRun(a, from: i, length: run) {
                    out += String(a[i..<close])
                    i = close
                }
                continue
            }

            // `$`, unless escaped as `\$`.
            if c == "$", !isEscaped(a, i) {
                // Display math `$$…$$`.
                if i + 1 < n, a[i + 1] == "$" {
                    if let close = findDisplayClose(a, from: i + 2) {
                        let tex = String(a[(i + 2)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let token = makeToken(tex, true)
                        out += "\n\n\(token)\n\n"
                        i = close + 2
                        continue
                    }
                    out += "$$"
                    i += 2
                    continue
                }

                // Inline math `$…$`: opener not followed by space, closer not
                // preceded by space and not followed by a digit, single line.
                if let close = findInlineClose(a, from: i) {
                    let tex = String(a[(i + 1)..<close])
                    let token = makeToken(tex, false)
                    out += token
                    i = close + 1
                    continue
                }
            }

            out.append(c)
            i += 1
        }
        return out
    }

    /// Index just past a closing run of `length` backticks at or after `from`,
    /// or `nil` if there is no matching run (the opener is then literal).
    private static func matchingBacktickRun(_ a: [Character], from: Int, length: Int) -> Int? {
        let n = a.count
        var i = from
        while i < n {
            if a[i] == "`" {
                var run = 0
                while i < n, a[i] == "`" { run += 1; i += 1 }
                if run == length { return i }
            } else {
                i += 1
            }
        }
        return nil
    }

    /// Index of the closing `$$` (its first `$`) starting the search at `from`.
    private static func findDisplayClose(_ a: [Character], from: Int) -> Int? {
        let n = a.count
        var i = from
        while i + 1 < n {
            if a[i] == "`" { return nil } // don't let `$$` reach into a code span
            if a[i] == "$", a[i + 1] == "$", !isEscaped(a, i) { return i }
            i += 1
        }
        return nil
    }

    /// Index of the closing `$` for inline math opened at `open`, applying the
    /// GitHub/pandoc adjacency rules, or `nil` if this `$` isn't inline math.
    private static func findInlineClose(_ a: [Character], from open: Int) -> Int? {
        let n = a.count
        // Opener must be followed by a non-space, non-newline character.
        guard open + 1 < n else { return nil }
        let after = a[open + 1]
        if after == " " || after == "\t" || after == "\n" || after == "$" { return nil }

        var j = open + 1
        while j < n {
            let cj = a[j]
            if cj == "\n" { return nil } // inline math never crosses a line
            if cj == "`" { return nil }  // …nor an inline code span (`$x`)
            if cj == "$", !isEscaped(a, j) {
                let prev = a[j - 1]
                let nextIsDigit = (j + 1 < n) && a[j + 1].isNumber
                if prev != " ", prev != "\t", !nextIsDigit, j > open + 1 {
                    return j
                }
                // A `$` that fails the closing rule (e.g. "$5") aborts this match.
                return nil
            }
            j += 1
        }
        return nil
    }

    /// True when the character at `i` is preceded by an odd number of backslashes.
    private static func isEscaped(_ a: [Character], _ i: Int) -> Bool {
        var backslashes = 0
        var k = i - 1
        while k >= 0, a[k] == "\\" { backslashes += 1; k -= 1 }
        return backslashes % 2 == 1
    }

    // MARK: - Fences

    /// Parses a fence line into `(marker, length, info)` or returns `nil`.
    /// A fence is ≤3 leading spaces, then ≥3 of the same `` ` `` or `~`.
    private static func fenceInfo(_ line: String) -> (marker: Character, length: Int, info: String)? {
        var idx = line.startIndex
        var spaces = 0
        while idx < line.endIndex, line[idx] == " ", spaces < 3 {
            idx = line.index(after: idx)
            spaces += 1
        }
        guard idx < line.endIndex else { return nil }
        let marker = line[idx]
        guard marker == "`" || marker == "~" else { return nil }

        var len = 0
        while idx < line.endIndex, line[idx] == marker {
            len += 1
            idx = line.index(after: idx)
        }
        guard len >= 3 else { return nil }

        let info = String(line[idx...]).trimmingCharacters(in: .whitespaces)
        // CommonMark: a backtick info string may not itself contain a backtick.
        if marker == "`", info.contains("`") { return nil }
        return (marker, len, info)
    }

    private static func firstWord(_ s: String) -> String {
        String(s.split(whereSeparator: { $0 == " " || $0 == "\t" }).first ?? "")
    }

    private static func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default:  out.append(ch)
            }
        }
        return out
    }
}
