import SwiftUI
import AppKit

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
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = true
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

    /// Opens a new untitled document as a tab of the current window. Backs ⌘T
    /// and the tab bar's "+" button.
    static func newTab() {
        pendingTab = true
        NSDocumentController.shared.newDocument(nil)
    }

    /// Read once by the next window that attaches, then cleared.
    fileprivate static func consumePendingTab() -> Bool {
        defer { pendingTab = false }
        return pendingTab
    }
}

/// Identifier shared by every document window so they tab together instead of
/// each forming its own single-tab group.
private let mownTabbingIdentifier = NSWindow.TabbingIdentifier("com.mown.document")

/// Locates the window hosting the SwiftUI document scene and configures its
/// tabbing once AppKit has attached the view. `isFileBacked` marks windows
/// opened from a file on disk so they default to tabbing.
struct WindowAccessor: NSViewRepresentable {
    var isFileBacked: Bool = false

    func makeNSView(context: Context) -> NSView {
        WindowConfiguringView(isFileBacked: isFileBacked)
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
    private let isFileBacked: Bool

    init(isFileBacked: Bool) {
        self.isFileBacked = isFileBacked
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.tabbingIdentifier = mownTabbingIdentifier

        // Always consume the pending flag so it can't leak onto a later window.
        let pending = DocumentTabbing.consumePendingTab()
        if pending || isFileBacked {
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
    }
}
