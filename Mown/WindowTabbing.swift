import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Mown opens each Markdown file through `DocumentGroup`. macOS can tab those
/// document windows, but SwiftUI gives no API to wire up "⌘N = new window,
/// ⌘T = new tab, open = tab", so we bridge to AppKit:
///
/// - `AppDelegate` enables automatic window tabbing and implements
///   `newWindowForTab:`, the action the tab bar's "+" button sends.
/// - `DocumentTabbing.newTab()` flags a pending tab and creates a new untitled
///   document; it backs both the "+" button and the ⌘T menu command.
/// - `WindowConfiguringView` configures every document window's tabbing *before*
///   the window is ordered on screen. It opens as a tab (`.preferred`) when the
///   request was ⌘T/"+" (a pending flag) or when the window is backed by a file
///   on disk (File ▸ Open, Finder); otherwise (an untitled ⌘N window) it uses
///   `.automatic` so it opens as a separate window. A shared tabbing identifier
///   groups the tabs.
///
/// Note: we deliberately do NOT subclass `NSDocumentController` — SwiftUI's
/// `DocumentGroup` requires its own `PlatformDocumentController` to be the
/// shared instance, and installing another one crashes at launch.

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Owns the Open Recent submenu takeover (SwiftUI doesn't populate it).
    private let recentDocumentsMenu = RecentDocumentsMenuController()
    private let viewMenuTrimmer = ViewMenuTrimmer()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true

        // AppKit's macOS 13+ default is to show the system Open panel at
        // launch (controlled by NSShowAppCentricOpenPanelInsteadOfUntitledFile).
        // Register false so it skips the panel.
        UserDefaults.standard.register(
            defaults: ["NSShowAppCentricOpenPanelInsteadOfUntitledFile": false]
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        recentDocumentsMenu.install()
        viewMenuTrimmer.install()
    }

    /// Sent up the responder chain by the tab bar's "+" button.
    @objc func newWindowForTab(_ sender: Any?) {
        DocumentTabbing.newTab()
    }
}

enum DocumentTabbing {
    /// Set while a ⌘T / "+" request is in flight. The next document window to
    /// attach reads this to decide whether to join the current window as a tab.
    private static var pendingTab = false
    /// The window the pending tab should join, captured the moment ⌘T fires —
    /// by the time the new window attaches, key/main status has already moved
    /// to it, so we can no longer ask AppKit which window was front.
    private static weak var pendingHost: NSWindow?

    /// Opens a new untitled document as a tab of the current window. Backs ⌘T
    /// and the tab bar's "+" button.
    static func newTab() {
        pendingTab = true
        pendingHost = NSApp.keyWindow ?? NSApp.mainWindow
        NSDocumentController.shared.newDocument(nil)
    }

    /// Read once by the next window that attaches, then cleared.
    fileprivate static func consumePending() -> (pending: Bool, host: NSWindow?) {
        defer { pendingTab = false; pendingHost = nil }
        return (pendingTab, pendingHost)
    }
}

/// Identifier shared by every document window so they tab together instead of
/// each forming its own single-tab group.
private let mownTabbingIdentifier = NSWindow.TabbingIdentifier("com.mown.document")

/// Locates the window hosting the SwiftUI document scene and configures its
/// tabbing once AppKit has attached the view. `isFileBacked` marks windows
/// opened from a file on disk so they default to tabbing.
struct WindowAccessor: NSViewRepresentable {
    /// File on disk backing this window, if any. `nil` for untitled ⌘N/⌘T docs.
    var fileURL: URL? = nil
    var editState: DocumentEditState

    func makeNSView(context: Context) -> NSView {
        WindowConfiguringView(fileURL: fileURL, editState: editState)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Sets its host window's tabbing *before* the window is ordered on screen.
///
/// `viewDidMoveToWindow()` runs synchronously while SwiftUI is still assembling
/// the window's content — earlier than `view.window` becomes non-nil inside
/// `makeNSView`, and crucially before `makeKeyAndOrderFront`. Setting the
/// tabbing here lets AppKit place the window directly into the right group at
/// order-front time, so a new tab never appears as a standalone window first.
private final class WindowConfiguringView: NSView {
    private let fileURL: URL?
    private var isFileBacked: Bool { fileURL != nil }
    private let editState: DocumentEditState
    /// Drives the close-button dot and the editor's "Unsaved" badge.
    private let editedIndicator = DocumentEditedIndicator()

    init(fileURL: URL?, editState: DocumentEditState) {
        self.fileURL = fileURL
        self.editState = editState
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.tabbingIdentifier = mownTabbingIdentifier

        // The tab already shows the document name, so the large titlebar title is
        // redundant — hide it from the titlebar. This only affects the titlebar
        // text; the tab's own label is set explicitly below.
        window.titleVisibility = .hidden

        // SwiftUI's document window opts into full-size content, letting the
        // content view (and HSplitView's divider — the "center line") draw up
        // behind the titlebar. Turn that off so the divider stops at the top of
        // the content area. (Previously fixed in b055165, lost when the toolbar
        // was removed; restored here because the window enables it regardless.)
        window.styleMask.remove(.fullSizeContentView)
        window.titlebarAppearsTransparent = false

        // Make every tab show BOTH the file icon and the filename. With the
        // titlebar title hidden, AppKit otherwise collapses a file-backed
        // window's tab to its proxy icon only while untitled windows keep text
        // only — the inconsistency users see. An explicit attributed title
        // (icon image attachment + name) overrides that fallback, so every tab
        // renders identically as "icon filename".
        window.tab.attributedTitle = tabTitle(for: fileURL)

        // Restore (and keep saving) the window size/position across launches.
        window.setFrameAutosaveName("MownDocumentWindow")

        // Drive the close-button dot and the editor's "Unsaved" badge.
        editedIndicator.attach(to: window, editState: editState)

        // Always consume the pending flag so it can't leak onto a later window.
        let (pending, host) = DocumentTabbing.consumePending()
        let wantsTab = pending || isFileBacked
        if wantsTab {
            // ⌘T / "+" / open-from-disk: join the current window as a tab
            // regardless of the user's system "prefer tabs" setting. With no
            // current window (e.g. the first file opened) AppKit opens it
            // standalone, forming a new group.
            window.tabbingMode = .preferred
        } else {
            // Untitled ⌘N / launch: follow the system setting — a separate
            // window by default.
            window.tabbingMode = .automatic
        }

        // A file-backed window appears right after the user picks a file, so any
        // free-standing open panel has done its job — dismiss it. (Sheet panels
        // are left to AppKit; closing those would disrupt the modal session.)
        if isFileBacked {
            for case let panel as NSOpenPanel in NSApp.windows
            where panel.isVisible && panel.sheetParent == nil {
                panel.close()
            }
        }

        // Finish on the next runloop tick, once the window is on screen:
        //   1. `.preferred` reliably joins an *existing* tab group but fails to
        //      merge into a lone, un-grouped window — the ⌘T-from-a-single-window
        //      case. Detect that and merge explicitly.
        //   2. Keep the tab bar visible even with a single tab (AppKit hides it
        //      by default below two tabs).
        DispatchQueue.main.async { [weak window, fileURL] in
            guard let window else { return }
            if wantsTab { mergeIntoTabGroup(window, preferredHost: host) }
            ensureTabBarVisible(window)
            // Re-apply after SwiftUI has finished wiring the document chrome,
            // which can re-show the titlebar title and re-derive the tab title.
            window.titleVisibility = .hidden
            window.tab.attributedTitle = tabTitle(for: fileURL)
        }
    }
}

/// Builds a tab label of the document's file icon followed by its name, so every
/// tab renders consistently as "icon filename". A `nil` url (an untitled
/// document) gets a generic document icon and the name "Untitled".
private func tabTitle(for url: URL?) -> NSAttributedString {
    let name = url?.lastPathComponent ?? "Untitled"
    let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
        ?? NSWorkspace.shared.icon(for: .plainText)
    icon.size = NSSize(width: 14, height: 14)

    let attachment = NSTextAttachment()
    attachment.image = icon
    // Drop the icon a few points so it centers on the text baseline.
    attachment.bounds = CGRect(x: 0, y: -3, width: 14, height: 14)

    let title = NSMutableAttributedString(attachment: attachment)
    title.append(NSAttributedString(string: " " + name))
    return title
}

/// Explicitly tabs `window` into a sibling group when AppKit's `.preferred`
/// tabbing didn't (the first merge into a previously-standalone window). No-op
/// if the window already landed in a multi-tab group.
private func mergeIntoTabGroup(_ window: NSWindow, preferredHost: NSWindow?) {
    if let group = window.tabGroup, group.windows.count > 1 { return }

    let host = preferredHost ?? NSApp.windows.first {
        $0 !== window && $0.tabbingIdentifier == mownTabbingIdentifier && $0.isVisible
    }
    guard let host, host !== window,
          host.tabbingIdentifier == mownTabbingIdentifier,
          host.isVisible,
          host.tabGroup?.windows.contains(window) != true
    else { return }

    host.addTabbedWindow(window, ordered: .above)
    window.makeKeyAndOrderFront(nil)
}

/// Shows the window's tab bar if AppKit has it hidden, so it stays visible even
/// when only one tab remains.
private func ensureTabBarVisible(_ window: NSWindow) {
    if window.tabGroup?.isTabBarVisible == false {
        window.toggleTabBar(nil)
    }
}
