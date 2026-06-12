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

    /// The pasteboard string when it parses as a web URL, so ⌘K can pre-fill the
    /// link target. Returns nil for ordinary copied text.
    private static func clipboardURL() -> String? {
        guard let raw = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let url = URL(string: raw), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return raw
        }
        if raw.hasPrefix("www."), raw.contains(".") { return "https://" + raw }
        return nil
    }
}
