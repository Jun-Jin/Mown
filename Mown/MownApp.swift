import SwiftUI

@main
struct MownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
            // ⌘N (File ▸ New) stays as DocumentGroup's built-in "new window".
            // ⌘T adds a tab to the current window instead.
            CommandGroup(after: .newItem) {
                Button("New Tab") { DocumentTabbing.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                CycleViewModeMenuItem()
            }
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

    var body: some View {
        Button("Cycle View Mode") { action?() }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(action == nil)
    }
}
