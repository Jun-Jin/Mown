import SwiftUI

@main
struct InkwellApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            ContentView(document: file.$document)
        }
        .commands {
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
