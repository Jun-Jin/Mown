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
    @State private var floatingPickerVisible = false
    /// Size of the content area, captured via a background `GeometryReader` so
    /// the root view tree stays un-wrapped — wrapping the document root in a
    /// `GeometryReader` defers `WindowAccessor`'s attachment past order-front,
    /// which breaks ⌘T tabbing (tabbingMode must be set before the window shows).
    @State private var contentSize: CGSize = .zero
    /// Unsaved-changes flag, driven from AppKit (see DocumentEditedIndicator).
    @StateObject private var editState = DocumentEditState()
    /// Drives editor↔preview scroll sync in split mode. Held across mode
    /// changes so the panes don't reset their position when split is
    /// re-entered.
    @StateObject private var scrollSync = ScrollSync()
    /// Bridges the Format menu to this window's editor text view.
    @StateObject private var editorActions = EditorActions()

    /// Resolves the preview's effective light/dark, deferring to the live
    /// system appearance when the user's choice is `.system`.
    private var previewIsDark: Bool {
        settings.previewTheme.isDark(whenSystem: colorScheme == .dark)
    }

    var body: some View {
        layout
            .overlay(alignment: .bottom) {
                ViewModePicker(mode: $viewMode)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                    .padding(.bottom, 18)
                    .opacity(floatingPickerVisible ? 1 : 0)
                    .allowsHitTesting(floatingPickerVisible)
                    .animation(.easeInOut(duration: 0.15), value: floatingPickerVisible)
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p):
                    // Reveal when the cursor enters a band at the bottom-center
                    // of the window. Generous width so the user doesn't have to
                    // aim precisely; height kept shallow so it doesn't pop in
                    // during normal editing.
                    let dx = abs(p.x - contentSize.width / 2)
                    let dy = contentSize.height - p.y
                    let show = dx < 160 && dy < 70
                    // `onContinuousHover` fires on every mouse move; only write
                    // when the result flips so we don't invalidate `body` on
                    // each pixel of movement.
                    if show != floatingPickerVisible { floatingPickerVisible = show }
                case .ended:
                    if floatingPickerVisible { floatingPickerVisible = false }
                }
            }
            .overlay(alignment: .topTrailing) {
                if editState.isEdited {
                    HStack(spacing: 5) {
                        Circle().fill(.orange).frame(width: 7, height: 7)
                        Text("Unsaved")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: editState.isEdited)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { contentSize = geo.size }
                        .onChange(of: geo.size) { newSize in contentSize = newSize }
                }
            )
            .frame(minWidth: 600, minHeight: 400)
            .background(WindowAccessor(fileURL: fileURL, editState: editState))
            .task(id: document.text) {
                await scheduleRender(source: document.text)
            }
            .focusedSceneValue(\.setViewMode) { mode in
                viewMode = mode
            }
            // Only publish the format action when an editor is on screen, so
            // the Format menu disables itself in preview-only mode.
            .modifier(OptionalFormatAction(action: viewMode == .preview ? nil : editorActions.apply))
    }

    @ViewBuilder
    private var layout: some View {
        switch viewMode {
        case .edit:
            EditorView(text: $document.text, theme: settings.editorTheme, showLineNumbers: settings.showLineNumbers, editorActions: editorActions)
        case .preview:
            PreviewView(html: renderedHTML, isDark: previewIsDark, baseURL: fileURL?.deletingLastPathComponent())
        case .split:
            HSplitView {
                EditorView(text: $document.text, theme: settings.editorTheme, scrollSync: scrollSync, showLineNumbers: settings.showLineNumbers, editorActions: editorActions)
                    .frame(minWidth: 240)
                PreviewView(html: renderedHTML, isDark: previewIsDark, baseURL: fileURL?.deletingLastPathComponent(), scrollSync: scrollSync)
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
