import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    /// File on disk backing this window, if any. Drives "opened files become
    /// tabs" (see WindowAccessor); nil for untitled ⌘N/⌘T documents.
    var fileURL: URL? = nil
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewMode: ViewMode = .edit
    @State private var renderedHTML: String = ""

    /// Resolves the preview's effective light/dark, deferring to the live
    /// system appearance when the user's choice is `.system`.
    private var previewIsDark: Bool {
        settings.previewTheme.isDark(whenSystem: colorScheme == .dark)
    }

    var body: some View {
        layout
            .frame(minWidth: 600, minHeight: 400)
            .background(WindowAccessor(isFileBacked: fileURL != nil))
            .toolbar {
                ToolbarItem(placement: .principal) {
                    ViewModePicker(mode: $viewMode)
                }
            }
            .task(id: document.text) {
                await scheduleRender(source: document.text)
            }
            .focusedSceneValue(\.cycleViewMode) {
                viewMode = viewMode.next()
            }
    }

    @ViewBuilder
    private var layout: some View {
        switch viewMode {
        case .edit:
            EditorView(text: $document.text, theme: settings.editorTheme)
        case .preview:
            PreviewView(html: renderedHTML, isDark: previewIsDark)
        case .split:
            HSplitView {
                EditorView(text: $document.text, theme: settings.editorTheme)
                    .frame(minWidth: 240)
                PreviewView(html: renderedHTML, isDark: previewIsDark)
                    .frame(minWidth: 240)
            }
        }
    }

    private func scheduleRender(source: String) async {
        // 150ms debounce — if the source changes again, .task(id:) cancels us.
        try? await Task.sleep(nanoseconds: 150_000_000)
        if Task.isCancelled { return }
        let html = MarkdownRenderer.shared.renderHTML(source)
        if Task.isCancelled { return }
        renderedHTML = html
    }
}
