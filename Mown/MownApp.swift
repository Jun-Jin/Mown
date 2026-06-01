import SwiftUI

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
            // The custom commands below take their shortcuts from AppSettings, so
            // the Settings ▸ Shortcuts pane can rebind them.
            CommandGroup(after: .newItem) {
                ShortcutCommandButton("New Tab", shortcut: settings.newTabShortcut) {
                    DocumentTabbing.newTab()
                }
            }
            CommandGroup(after: .toolbar) {
                CycleViewModeMenuItem(shortcut: settings.cycleViewModeShortcut)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(settings)
        }
    }
}

/// A menu `Button` whose keyboard shortcut comes from a configurable
/// `KeyboardShortcutSetting`. When the setting is empty, no shortcut is bound.
struct ShortcutCommandButton: View {
    private let title: String
    private let shortcut: KeyboardShortcutSetting
    private let action: () -> Void

    init(_ title: String, shortcut: KeyboardShortcutSetting, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    var body: some View {
        Button(title, action: action)
            .modifier(OptionalShortcut(shortcut))
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

/// Action exposed by the frontmost document window so the global "Cycle View
/// Mode" menu item can drive only the focused window's view mode.
struct CycleViewModeActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var cycleViewMode: CycleViewModeActionKey.Value? {
        get { self[CycleViewModeActionKey.self] }
        set { self[CycleViewModeActionKey.self] = newValue }
    }
}

private struct CycleViewModeMenuItem: View {
    @FocusedValue(\.cycleViewMode) private var action
    let shortcut: KeyboardShortcutSetting

    var body: some View {
        Button("Cycle View Mode") { action?() }
            .modifier(OptionalShortcut(shortcut))
            .disabled(action == nil)
    }
}
