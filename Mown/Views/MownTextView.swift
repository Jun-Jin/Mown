import AppKit

/// The editor's `NSTextView`. A subclass is needed for the Tier 4 editing
/// niceties (#7) that AppKit exposes only through overridable methods rather
/// than the delegate: moving/duplicating lines (`keyDown`), wrapping a
/// selection when a pairing character is typed (`insertText`), and smart paste
/// (`paste`). Each defers to a pure model (`LineEditing`, `AutoPair`,
/// `SmartPaste`) and applies the result through `apply(_:)` so undo and the
/// highlighter behave as for any edit; anything not handled falls through to
/// `super`.
final class MownTextView: NSTextView {

    // MARK: - Line moves & duplication

    override func keyDown(with event: NSEvent) {
        if handleEditingKey(event) { return }
        super.keyDown(with: event)
    }

    /// Consumes ⌥↑/⌥↓ (move line) and ⇧⌘D (duplicate line). Returns `true` even
    /// at the document edge, so a no-op move doesn't fall through to AppKit's
    /// default ⌥-arrow navigation.
    private func handleEditingKey(_ event: NSEvent) -> Bool {
        guard !hasMarkedText() else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .option, event.specialKey == .upArrow {
            applyLineMove(.up); return true
        }
        if flags == .option, event.specialKey == .downArrow {
            applyLineMove(.down); return true
        }
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "d" {
            apply(LineEditing.duplicate(text: string as NSString, selection: selectedRange()))
            return true
        }
        return false
    }

    private func applyLineMove(_ direction: LineEditing.Direction) {
        if let edit = LineEditing.move(direction, text: string as NSString, selection: selectedRange()) {
            apply(edit)
        }
    }

    // MARK: - Auto-pair

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        let typed = (insertString as? String) ?? (insertString as? NSAttributedString)?.string
        if let typed, !hasMarkedText(),
           let edit = AutoPair.wrap(typing: typed, text: string as NSString, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    // MARK: - Smart paste

    override func paste(_ sender: Any?) {
        if !hasMarkedText(),
           let pasted = NSPasteboard.general.string(forType: .string),
           let edit = SmartPaste.transform(pasted: pasted, text: string as NSString, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.paste(sender)
    }
}
