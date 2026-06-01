import SwiftUI
import AppKit

/// A click-to-record control for a single keyboard shortcut. Clicking it starts
/// recording; the next key combination that includes a command/option/control
/// modifier is captured. `esc` cancels, `⌫` clears.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: KeyboardShortcutSetting

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onCapture = { shortcut = $0 }
        button.display(shortcut)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.onCapture = { shortcut = $0 }
        // Don't overwrite the live "Type shortcut…" prompt while recording.
        if !nsView.isRecording {
            nsView.display(shortcut)
        }
    }
}

/// AppKit backing for `ShortcutRecorder`. While recording it intercepts key
/// equivalents (e.g. ⌘T) via `performKeyEquivalent` so they configure the
/// shortcut instead of firing the matching menu command.
final class RecorderButton: NSButton {
    var onCapture: ((KeyboardShortcutSetting) -> Void)?
    private(set) var isRecording = false
    private var current: KeyboardShortcutSetting = .none

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(beginRecording)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func display(_ shortcut: KeyboardShortcutSetting) {
        current = shortcut
        refreshTitle()
    }

    override var acceptsFirstResponder: Bool { true }

    override func resignFirstResponder() -> Bool {
        if isRecording { endRecording() }
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        capture(event)
        return true
    }

    // MARK: Recording

    @objc private func beginRecording() {
        isRecording = true
        refreshTitle()
        window?.makeFirstResponder(self)
    }

    private func endRecording() {
        isRecording = false
        refreshTitle()
    }

    private func capture(_ event: NSEvent) {
        switch event.keyCode {
        case 53: // esc — cancel, keep the existing shortcut
            endRecording()
            return
        case 51, 117: // delete / forward-delete — clear the shortcut
            current = .none
            onCapture?(.none)
            endRecording()
            return
        default:
            break
        }

        let modifiers = event.modifierFlags.eventModifiers
        // Require at least one "real" modifier so a menu shortcut is meaningful;
        // otherwise keep waiting for a complete combination.
        guard modifiers.contains(.command)
            || modifiers.contains(.option)
            || modifiers.contains(.control),
              let character = event.charactersIgnoringModifiers?.first,
              character.isLetter || character.isNumber
                || character.isPunctuation || character.isSymbol
        else { return }

        let captured = KeyboardShortcutSetting(
            key: String(character).lowercased(),
            modifiers: modifiers
        )
        current = captured
        onCapture?(captured)
        endRecording()
    }

    private func refreshTitle() {
        title = isRecording
            ? "Type shortcut…"
            : (current.isSet ? current.displayString : "Click to record")
    }
}

private extension NSEvent.ModifierFlags {
    /// Maps Cocoa modifier flags to the SwiftUI `EventModifiers` the menu uses.
    var eventModifiers: EventModifiers {
        var result = EventModifiers()
        if contains(.command) { result.insert(.command) }
        if contains(.shift)   { result.insert(.shift) }
        if contains(.option)  { result.insert(.option) }
        if contains(.control) { result.insert(.control) }
        return result
    }
}
