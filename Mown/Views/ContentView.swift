import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    @State private var viewMode: ViewMode = .edit
    @State private var renderedHTML: String = ""

    var body: some View {
        layout
            .frame(minWidth: 600, minHeight: 400)
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
            EditorView(text: $document.text)
        case .preview:
            PreviewView(html: renderedHTML)
        case .split:
            HSplitView {
                EditorView(text: $document.text)
                    .frame(minWidth: 240)
                PreviewView(html: renderedHTML)
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
