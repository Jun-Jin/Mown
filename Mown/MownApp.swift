import SwiftUI
import AppKit

@main
struct MownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(settings)
        }
        .commands {
            // ⌘N (File ▸ New) stays as DocumentGroup's built-in "new window".
            // New Tab keeps a fixed ⌘T (not rebindable). The view-mode commands
            // take their shortcuts from AppSettings, so the Settings ▸ Shortcuts
            // pane can rebind them.
            CommandGroup(after: .newItem) {
                Button("New Tab") { DocumentTabbing.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            // Find bar for the editor. The NSTextView already enables it
            // (`usesFindBar`); SwiftUI just doesn't ship a Find menu, so these
            // items forward the standard text-finder actions to the focused
            // text view. "Find Previous" intentionally has no shortcut — the
            // conventional ⇧⌘G is taken by the Split-mode default; reach it via
            // the find bar's ‹ button (or rebind Split in Settings to free it).
            CommandGroup(after: .pasteboard) {
                Menu("Find") {
                    Button("Find…") { TextFinderCommand.perform(.showFindInterface) }
                        .keyboardShortcut("f", modifiers: .command)
                    Button("Find Next") { TextFinderCommand.perform(.nextMatch) }
                        .keyboardShortcut("g", modifiers: .command)
                    Button("Find Previous") { TextFinderCommand.perform(.previousMatch) }
                    Button("Use Selection for Find") { TextFinderCommand.perform(.setSearchString) }
                        .keyboardShortcut("e", modifiers: .command)
                }
            }
            CommandMenu("Format") {
                FormatMenuItem("Bold", format: .bold, key: "b", modifiers: .command)
                FormatMenuItem("Italic", format: .italic, key: "i", modifiers: .command)
                // ⌘E is already bound to "Use Selection for Find"; inline code
                // takes ⇧⌘C instead.
                FormatMenuItem("Inline Code", format: .code, key: "c", modifiers: [.command, .shift])
                FormatMenuItem("Strikethrough", format: .strikethrough, key: "x", modifiers: [.command, .shift])
                Divider()
                FormatMenuItem("Link", format: .link, key: "k", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                ViewModeMenuItem("Edit Mode", mode: .edit,
                                 shortcut: settings.editModeShortcut)
                ViewModeMenuItem("Preview Mode", mode: .preview,
                                 shortcut: settings.previewModeShortcut)
                ViewModeMenuItem("Split Mode", mode: .split,
                                 shortcut: settings.splitModeShortcut)
                // Full Screen is a fixed ⌘↵, not rebindable.
                Button("Toggle Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut(.return, modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

/// Forwards a text-finder action up the responder chain to the focused
/// `NSTextView`, which hosts the editor's find bar. `sendAction(to: nil …)`
/// targets the first responder, so this is a no-op when the editor isn't
/// focused (e.g. preview-only mode). The action is carried on the sender's
/// `tag`, exactly as AppKit's own Find menu items do.
enum TextFinderCommand {
    static func perform(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }
}

/// Applies `.keyboardShortcut` only when the setting actually has a key.
struct OptionalShortcut: ViewModifier {
    private let shortcut: KeyboardShortcutSetting

    init(_ shortcut: KeyboardShortcutSetting) { self.shortcut = shortcut }

    @ViewBuilder
    func body(content: Content) -> some View {
        if shortcut.isSet, let key = shortcut.keyEquivalent {
            content.keyboardShortcut(key, modifiers: shortcut.modifiers)
        } else {
            content
        }
    }
}

/// Action exposed by the frontmost document window so the global view-mode menu
/// items can drive only the focused window's view mode.
struct SetViewModeActionKey: FocusedValueKey {
    typealias Value = (ViewMode) -> Void
}

extension FocusedValues {
    var setViewMode: SetViewModeActionKey.Value? {
        get { self[SetViewModeActionKey.self] }
        set { self[SetViewModeActionKey.self] = newValue }
    }
}

/// Action exposed by the frontmost editor so the global Format menu drives only
/// the focused window's editor. Absent in preview-only mode, which disables the
/// menu items.
struct FormatTextActionKey: FocusedValueKey {
    typealias Value = (InlineFormat) -> Void
}

extension FocusedValues {
    var formatText: FormatTextActionKey.Value? {
        get { self[FormatTextActionKey.self] }
        set { self[FormatTextActionKey.self] = newValue }
    }
}

/// Publishes the format action as a focused scene value only when `action` is
/// non-nil, so the Format menu's `@FocusedValue` reads `nil` (and the items
/// disable) whenever no editor is on screen.
struct OptionalFormatAction: ViewModifier {
    let action: ((InlineFormat) -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let action {
            content.focusedSceneValue(\.formatText, action)
        } else {
            content
        }
    }
}

/// A Format-menu item that applies an inline-formatting toggle to the focused
/// editor. Disabled when no editor is focused (e.g. preview-only mode).
private struct FormatMenuItem: View {
    @FocusedValue(\.formatText) private var formatText
    private let title: String
    private let format: InlineFormat
    private let key: KeyEquivalent
    private let modifiers: EventModifiers

    init(_ title: String, format: InlineFormat, key: KeyEquivalent, modifiers: EventModifiers) {
        self.title = title
        self.format = format
        self.key = key
        self.modifiers = modifiers
    }

    var body: some View {
        Button(title) { formatText?(format) }
            .keyboardShortcut(key, modifiers: modifiers)
            .disabled(formatText == nil)
    }
}

/// A menu item that switches the focused window to a specific `ViewMode`, with a
/// configurable keyboard shortcut. Disabled when no document window is focused.
private struct ViewModeMenuItem: View {
    @FocusedValue(\.setViewMode) private var setMode
    private let title: String
    private let mode: ViewMode
    private let shortcut: KeyboardShortcutSetting

    init(_ title: String, mode: ViewMode, shortcut: KeyboardShortcutSetting) {
        self.title = title
        self.mode = mode
        self.shortcut = shortcut
    }

    var body: some View {
        Button(title) { setMode?(mode) }
            .modifier(OptionalShortcut(shortcut))
            .disabled(setMode == nil)
    }
}
