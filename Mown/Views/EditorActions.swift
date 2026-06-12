import AppKit

/// Bridges the SwiftUI Format menu to the focused window's editor. `EditorView`
/// registers its `NSTextView` here when the view is created; the menu invokes
/// `apply(_:)` through a focused scene value so commands target only the active
/// window's editor. Held weakly so a torn-down editor (e.g. switching to
/// preview-only mode) makes the actions a safe no-op.
final class EditorActions: ObservableObject {
    weak var textView: NSTextView?

    func apply(_ format: InlineFormat) {
        guard let textView else { return }
        let text = textView.string as NSString
        let selection = textView.selectedRange()

        let edit: InlineFormatting.Edit
        if format == .link {
            edit = InlineFormatting.link(text: text, selection: selection,
                                         clipboardURL: Self.clipboardURL())
        } else {
            edit = InlineFormatting.toggle(format, text: text, selection: selection)
        }

        // Apply through the change-tracking path so undo coalescing, the
        // SwiftUI binding push, and the highlighter's storage delegate fire
        // exactly as for a typed edit.
        guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }
        textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
        textView.didChangeText()
        textView.setSelectedRange(edit.selectedRange)
    }

    /// Applies a block-level formatting action (Tier 3, #6) to the whole lines
    /// covered by the selection. A no-op action leaves the text untouched.
    func apply(_ format: BlockFormat) {
        guard let textView else { return }
        let edit = BlockFormatting.edit(for: format,
                                        text: textView.string as NSString,
                                        selection: textView.selectedRange())
        if let edit { textView.apply(edit) }
    }

    /// The pasteboard string when it parses as a web URL, so ⌘K can pre-fill the
    /// link target. Returns nil for ordinary copied text.
    private static func clipboardURL() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return nil }
        return WebURL.normalized(raw)
    }
}
