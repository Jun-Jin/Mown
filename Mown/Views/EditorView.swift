import SwiftUI
import AppKit
import Combine

struct EditorView: NSViewRepresentable {
    @Binding var text: String
    /// Editor color scheme. `.system` inherits; `.light`/`.dark` pin the
    /// editor's appearance so its background and the highlighter's dynamic
    /// `NSColor`s re-resolve against the chosen scheme.
    var theme: AppTheme = .system
    /// Shared scroll-fraction bus used in split mode. `nil` outside split.
    var scrollSync: ScrollSync? = nil
    /// Show the line-number gutter. Toggled live from Settings.
    var showLineNumbers: Bool = true
    /// Receives a weak reference to this editor's text view so the Format menu
    /// can drive inline-formatting commands. `nil` when no menu is wired.
    var editorActions: EditorActions? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        // Build the text stack by hand (rather than NSTextView.scrollableTextView())
        // so the document view is our `MownTextView` subclass, which the Tier 4
        // editing actions (#7) need. Explicit TextKit 1 wiring keeps the
        // highlighter's `NSTextStorageDelegate` and the line-number ruler's
        // `layoutManager` use working as before.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: scrollView.contentSize.width,
                                                         height: .greatestFiniteMagnitude))
        layoutManager.addTextContainer(textContainer)
        let textView = MownTextView(frame: NSRect(origin: .zero, size: scrollView.contentSize),
                                    textContainer: textContainer)
        scrollView.documentView = textView

        applyTheme(to: scrollView, textView: textView)

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        let editorFont = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.font = editorFont
        textView.textContainerInset = NSSize(width: 16, height: 16)

        // Install the Markdown highlighter as the storage's delegate. The
        // coordinator retains it; NSTextStorage holds the delegate weakly.
        let highlighter = MarkdownSyntaxHighlighter(baseFont: editorFont)
        highlighter.textView = textView
        context.coordinator.highlighter = highlighter
        textView.textStorage?.delegate = highlighter

        // Disable substitutions that interfere with Markdown source.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false

        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        // Soft-wrap: track the scroll view's width, no horizontal growth.
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        if let container = textView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: scrollView.contentSize.width,
                                             height: CGFloat.greatestFiniteMagnitude)
        }

        textView.string = text
        // Setting `string` above goes through textStorage and fires the
        // delegate; force one extra pass in case the view was empty (no edit
        // would have been processed otherwise).
        if let storage = textView.textStorage, storage.length > 0 {
            highlighter.highlight(storage)
        }

        context.coordinator.attachScrollSync(to: scrollView, sync: scrollSync)
        context.coordinator.applyLineNumbers(showLineNumbers, scrollView: scrollView, textView: textView)
        editorActions?.textView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyTheme(to: scrollView, textView: textView)
        // Re-bind sync if the parent swapped in a different ScrollSync (e.g.
        // entering/leaving split mode). No-op when the identity is unchanged.
        if context.coordinator.boundSync !== scrollSync {
            context.coordinator.attachScrollSync(to: scrollView, sync: scrollSync)
        }
        context.coordinator.applyLineNumbers(showLineNumbers, scrollView: scrollView, textView: textView)
        if textView.string != text {
            let ranges = textView.selectedRanges
            textView.string = text
            // Re-clamp ranges to the new string length so we don't crash.
            let len = (textView.string as NSString).length
            let clamped = ranges.compactMap { value -> NSValue? in
                var r = value.rangeValue
                r.location = min(r.location, len)
                r.length = min(r.length, len - r.location)
                return NSValue(range: r)
            }
            textView.selectedRanges = clamped.isEmpty ? [NSValue(range: NSRange(location: len, length: 0))] : clamped
        }
    }

    /// Pins (or releases) the editor's appearance to match `theme`. The text
    /// view's background and the highlighter's dynamic colors resolve against
    /// the view's effective appearance, so AppKit repaints them on change.
    private func applyTheme(to scrollView: NSScrollView, textView: NSTextView) {
        let appearance = theme.nsAppearance
        scrollView.appearance = appearance
        textView.appearance = appearance
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditorView
        /// Strong reference — NSTextStorage holds its delegate weakly.
        var highlighter: MarkdownSyntaxHighlighter?

        /// Held to detect identity changes across `updateNSView`.
        private(set) weak var boundSync: ScrollSync?
        private var boundsObserver: NSObjectProtocol?
        private var syncCancellable: AnyCancellable?
        /// Swallow the boundsDidChange notification that fires from our own
        /// programmatic scroll — without this the editor would immediately
        /// re-publish the value it just received from the preview.
        private var suppressEcho = false

        init(_ parent: EditorView) { self.parent = parent }

        deinit {
            if let token = boundsObserver { NotificationCenter.default.removeObserver(token) }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            // Avoid feedback loop: only push if value actually changed.
            if parent.text != textView.string {
                parent.text = textView.string
            }
        }

        /// Intercepts the list-aware keystrokes (Tab/Shift-Tab/Return/Delete)
        /// and routes them through `ListEditing`. Returning `false` (including
        /// when `ListEditing` declines) lets `NSTextView` perform its default,
        /// so this only changes behavior inside Markdown lists.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Defer to the input method while a composition is in flight.
            if textView.hasMarkedText() { return false }
            let text = textView.string as NSString
            let selection = textView.selectedRange()
            let edit: ListEditing.Edit?
            switch commandSelector {
            case #selector(NSResponder.insertTab(_:)):
                // Inside a Markdown table, Tab jumps to the next cell (#7); only
                // outside one does it fall through to list indentation (#4).
                if let jump = TableEditing.tabJump(text: text, selection: selection, reverse: false) {
                    textView.apply(jump); return true
                }
                edit = ListEditing.indent(text: text, selection: selection)
            case #selector(NSResponder.insertBacktab(_:)):
                if let jump = TableEditing.tabJump(text: text, selection: selection, reverse: true) {
                    textView.apply(jump); return true
                }
                edit = ListEditing.outdent(text: text, selection: selection)
            case #selector(NSResponder.insertNewline(_:)):
                edit = ListEditing.newline(text: text, selection: selection)
            case #selector(NSResponder.deleteBackward(_:)):
                edit = ListEditing.backspace(text: text, selection: selection)
            default:
                return false
            }
            guard let edit else { return false }
            return apply(edit, to: textView)
        }

        /// Applies a `ListEditing.Edit` through the text view's change-tracking
        /// path so undo coalescing, the binding push, and the highlighter's
        /// storage delegate all fire as for a normal user edit.
        private func apply(_ edit: ListEditing.Edit, to textView: NSTextView) -> Bool {
            guard textView.shouldChangeText(in: edit.range, replacementString: edit.replacement) else {
                return true
            }
            textView.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
            textView.didChangeText()
            textView.setSelectedRange(edit.selectedRange)
            return true
        }

        func attachScrollSync(to scrollView: NSScrollView, sync: ScrollSync?) {
            if let token = boundsObserver {
                NotificationCenter.default.removeObserver(token)
                boundsObserver = nil
            }
            syncCancellable = nil
            boundSync = sync
            guard let sync else { return }

            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true

            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                if self.suppressEcho { self.suppressEcho = false; return }
                guard let fraction = Self.currentFraction(scrollView) else { return }
                sync.report(fraction, from: .editor)
            }

            syncCancellable = sync.$event
                .receive(on: RunLoop.main)
                .sink { [weak self, weak scrollView] event in
                    guard let self, let scrollView else { return }
                    guard event.source != .editor else { return }
                    self.apply(fraction: event.fraction, to: scrollView)
                }
        }

        private static func currentFraction(_ scrollView: NSScrollView) -> CGFloat? {
            guard let documentView = scrollView.documentView else { return nil }
            let visibleHeight = scrollView.contentView.bounds.height
            let scrollable = documentView.bounds.height - visibleHeight
            guard scrollable > 0 else { return 0 }
            return scrollView.contentView.bounds.origin.y / scrollable
        }

        // MARK: - Line numbers

        private var lineRuler: LineNumberRulerView?

        func applyLineNumbers(_ enabled: Bool, scrollView: NSScrollView, textView: NSTextView) {
            if enabled, lineRuler == nil {
                let ruler = LineNumberRulerView(textView: textView)
                scrollView.hasVerticalRuler = true
                scrollView.verticalRulerView = ruler
                scrollView.rulersVisible = true
                lineRuler = ruler
                // The ruler steals horizontal space from the document area.
                // Without an explicit tile, the text view keeps its old frame
                // and renders text behind the ruler — visually invisible
                // because the gutter paints over it.
                scrollView.tile()
            } else if !enabled, lineRuler != nil {
                scrollView.rulersVisible = false
                scrollView.verticalRulerView = nil
                scrollView.hasVerticalRuler = false
                lineRuler = nil
                scrollView.tile()
            }
        }

        private func apply(fraction: CGFloat, to scrollView: NSScrollView) {
            guard let documentView = scrollView.documentView else { return }
            let clipView = scrollView.contentView
            let scrollable = documentView.bounds.height - clipView.bounds.height
            guard scrollable > 0 else { return }
            let targetY = fraction * scrollable
            if abs(targetY - clipView.bounds.origin.y) < 0.5 { return }
            suppressEcho = true
            clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: targetY))
            scrollView.reflectScrolledClipView(clipView)
        }
    }
}
