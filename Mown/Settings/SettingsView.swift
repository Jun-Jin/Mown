import SwiftUI

/// The app's configuration window (opened via the "Settings…" menu item / ⌘,).
/// Two panes: theme selection and keyboard-shortcut binding.
struct SettingsView: View {
    private enum Tab: Hashable { case theme, shortcuts, cli }
    @State private var selection: Tab = .theme

    var body: some View {
        TabView(selection: $selection) {
            ThemeSettingsView()
                .tabItem { Label("Theme", systemImage: "paintpalette") }
                .tag(Tab.theme)

            ShortcutSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(Tab.shortcuts)

            CLISettingsView()
                .tabItem { Label("Command Line", systemImage: "terminal") }
                .tag(Tab.cli)
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

            Section {
                Toggle("Show line numbers", isOn: $settings.showLineNumbers)
            } header: {
                Text("Editor")
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
                row("Edit Mode", shortcut: $settings.editModeShortcut)
                row("Preview Mode", shortcut: $settings.previewModeShortcut)
                row("Split Mode", shortcut: $settings.splitModeShortcut)
            } header: {
                Text("View")
            } footer: {
                Text("Click a field and press the new combination. "
                     + "esc cancels, ⌫ clears.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                formatRows(in: .inline)
            } header: {
                Text("Inline Formatting")
            }

            Section {
                formatRows(in: .heading)
                formatRows(in: .block)
            } header: {
                Text("Block Formatting")
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

    /// One recorder row per Format command in `group`, bound through
    /// `AppSettings` so a change persists and updates the menu.
    private func formatRows(in group: FormatCommand.Group) -> some View {
        ForEach(FormatCommand.allCases.filter { $0.group == group }) { command in
            row(command.title, shortcut: Binding(
                get: { settings.formatShortcut(command) },
                set: { settings.setFormatShortcut(command, $0) }
            ))
        }
    }
}

/// Installs / removes the bundled `mown` script as /usr/local/bin/mown via an
/// admin AppleScript prompt — same pattern as VS Code's "Install 'code' command".
private struct CLISettingsView: View {
    @State private var status: InstallCLI.Status = .notInstalled

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(statusText).foregroundStyle(statusColor)
                }
                LabeledContent("Path") {
                    Text(InstallCLI.destination)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            } header: {
                Text("Command Line Tool")
            } footer: {
                Text("Installs a `\(InstallCLI.toolName)` command that opens Markdown files in Mown from the terminal "
                     + "(e.g. `\(InstallCLI.toolName) notes.md`). macOS will ask for your administrator password "
                     + "because the symlink lives in /usr/local/bin.")
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Button(primaryButtonTitle) {
                    InstallCLI.install()
                    refresh()
                }
                if case .installed = status {
                    Button("Uninstall") {
                        InstallCLI.uninstall()
                        refresh()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh() }
    }

    private var primaryButtonTitle: String {
        switch status {
        case .notInstalled: "Install"
        case .installed: "Reinstall"
        case .foreign: "Replace"
        }
    }

    private var statusText: String {
        switch status {
        case .notInstalled: "Not installed"
        case .installed: "Installed"
        case .foreign(let path): "Another file at this path → \(path)"
        }
    }

    private var statusColor: Color {
        switch status {
        case .installed: .green
        case .foreign: .orange
        case .notInstalled: .secondary
        }
    }

    private func refresh() { status = InstallCLI.currentStatus() }
}
