import AppKit

/// Vertical gutter that draws logical line numbers next to an `NSTextView`.
///
/// Soft-wrapped continuation rows are intentionally left blank, so the
/// numbers always match what `⌘L`-style "go to line" features expect (i.e.
/// newline-separated source lines, not visual rows).
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    private var observers: [NSObjectProtocol] = []

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        self.clientView = textView

        // Re-layout / re-paint whenever the storage changes (line count and
        // therefore the gutter's width can change) and whenever the editor's
        // frame changes (the scroll view emits this on resize and on theme
        // appearance flips, both of which can shift fragment positions).
        if let storage = textView.textStorage {
            observers.append(NotificationCenter.default.addObserver(
                forName: NSTextStorage.didProcessEditingNotification,
                object: storage, queue: .main
            ) { [weak self] _ in self?.refresh() })
        }
        textView.postsFrameChangedNotifications = true
        observers.append(NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: textView, queue: .main
        ) { [weak self] _ in self?.refresh() })

        refresh()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Re-measure gutter width to fit the largest line number and redraw.
    func refresh() {
        let count = max(1, lineCount())
        // Reserve room for one extra digit so the gutter doesn't twitch as the
        // doc grows past 9 → 10, 99 → 100, etc.
        let digits = max(2, String(count).count + 1)
        let advance = digitAdvance()
        let newThickness = ceil(CGFloat(digits) * advance) + horizontalPadding * 2
        if ruleThickness != newThickness { ruleThickness = newThickness }
        needsDisplay = true
    }

    // MARK: - Drawing

    private let horizontalPadding: CGFloat = 6

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let storage = textView.textStorage,
              let scrollView = self.scrollView else { return }

        // Background — clip to the gutter's own thickness. AppKit may pass a
        // `rect` wider than `ruleThickness` during a full redraw; filling it
        // unclipped paints over the document area and "hides" the text.
        let gutterRect = NSRect(x: 0, y: rect.minY,
                                width: ruleThickness, height: rect.height)
        NSColor.windowBackgroundColor.setFill()
        gutterRect.fill()

        let visibleRect = scrollView.contentView.bounds
        let visibleGlyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect,
                                                         in: textContainer)
        let visibleCharRange = layoutManager.characterRange(forGlyphRange: visibleGlyphRange,
                                                            actualGlyphRange: nil)

        let content = storage.string as NSString
        // Logical line for the first visible character = newlines in everything
        // before it + 1. Counting on demand is fine for the doc sizes Mown
        // targets; if this ever becomes hot we can cache per text edit.
        var lineNumber = 1 + countNewlines(in: content, upTo: visibleCharRange.location)

        let inset = textView.textContainerInset.height
        let yOffset = inset - visibleRect.origin.y

        let attrs = labelAttributes()

        layoutManager.enumerateLineFragments(forGlyphRange: visibleGlyphRange) {
            (fragmentRect, _, _, glyphRange, _) in
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange,
                                                         actualGlyphRange: nil)
            let isLogicalLineStart = charRange.location == 0 ||
                content.character(at: charRange.location - 1) == 0x0A // '\n'

            if isLogicalLineStart {
                self.drawNumber(lineNumber,
                                topY: fragmentRect.minY + yOffset,
                                attributes: attrs)
                lineNumber += 1
            }
        }

        // `enumerateLineFragments` skips the "extra" trailing fragment that
        // exists when the document ends with a newline (cursor sitting on an
        // empty last line). Draw it explicitly so the count matches reality.
        if content.length == 0 || content.character(at: content.length - 1) == 0x0A {
            let extra = layoutManager.extraLineFragmentRect
            if extra.height > 0,
               NSIntersectsRect(extra, visibleRect) {
                drawNumber(lineNumber,
                           topY: extra.minY + yOffset,
                           attributes: attrs)
            }
        }
    }

    private func drawNumber(_ number: Int,
                            topY: CGFloat,
                            attributes: [NSAttributedString.Key: Any]) {
        let text = String(number) as NSString
        let size = text.size(withAttributes: attributes)
        // Right-aligned, with a small bottom padding so digits sit on the
        // baseline of their line rather than the top.
        let x = ruleThickness - size.width - horizontalPadding
        text.draw(at: NSPoint(x: x, y: topY + 1), withAttributes: attributes)
    }

    // MARK: - Helpers

    private func labelAttributes() -> [NSAttributedString.Key: Any] {
        let base = textView?.font ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize,
                                                                 weight: .regular)
        // Slightly smaller than the editor body so the gutter doesn't compete
        // visually; matches what Xcode/VS Code do.
        let font = NSFont.monospacedDigitSystemFont(ofSize: base.pointSize - 1, weight: .regular)
        return [
            .font: font,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
    }

    private func digitAdvance() -> CGFloat {
        let attrs = labelAttributes()
        return ("0" as NSString).size(withAttributes: attrs).width
    }

    private func lineCount() -> Int {
        guard let storage = textView?.textStorage else { return 1 }
        let content = storage.string as NSString
        if content.length == 0 { return 1 }
        return 1 + countNewlines(in: content, upTo: content.length)
    }

    private func countNewlines(in string: NSString, upTo location: Int) -> Int {
        var count = 0
        var idx = 0
        let end = min(location, string.length)
        while idx < end {
            if string.character(at: idx) == 0x0A { count += 1 }
            idx += 1
        }
        return count
    }
}
