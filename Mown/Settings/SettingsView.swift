import SwiftUI

/// The app's configuration window (opened via the "Settings…" menu item / ⌘,).
/// Two panes: theme selection and keyboard-shortcut binding.
struct SettingsView: View {
    private enum Tab: Hashable { case theme, shortcuts }
    @State private var selection: Tab = .theme

    var body: some View {
        TabView(selection: $selection) {
            ThemeSettingsView()
                .tabItem { Label("Theme", systemImage: "paintpalette") }
                .tag(Tab.theme)

            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)
        }
        .frame(width: 480)
    }
}

/// Edit theme styles the source editor; view theme styles the rendered preview.
private struct ThemeSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Picker("Edit Theme", selection: $settings.editorTheme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
                Picker("View Theme", selection: $settings.previewTheme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Edit theme styles the Markdown source editor. "
                     + "View theme styles the rendered preview. "
                     + "System follows the macOS appearance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Rebindable shortcuts for the app's custom commands.
private struct ShortcutSettingsView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Form {
            Section {
                row("New Tab", shortcut: $settings.newTabShortcut)
                row("Cycle View Mode", shortcut: $settings.cycleViewModeShortcut)
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Click a field and press the new combination. "
                     + "esc cancels, ⌫ clears.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button("Restore Defaults") { settings.resetShortcuts() }
            }
        }
        .formStyle(.grouped)
    }

    private func row(_ title: String,
                     shortcut: Binding<KeyboardShortcutSetting>) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(shortcut: shortcut)
                .frame(width: 150, height: 22)
        }
    }
}
