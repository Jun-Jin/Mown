import SwiftUI
import AppKit

/// Mown opens each Markdown file through `DocumentGroup`. macOS can tab those
/// document windows, but SwiftUI gives no API to wire up the standard
/// "⌘N = new window, ⌘T = new tab" split, so we bridge to AppKit:
///
/// - `AppDelegate` enables automatic window tabbing and implements
///   `newWindowForTab:`, the action the tab bar's "+" button sends.
/// - `DocumentTabbing.newTab()` flags a pending tab and creates a new untitled
///   document; it backs both the "+" button and the ⌘T menu command.
/// - `WindowConfiguringView` configures every document window's tabbing *before*
///   the window is ordered on screen. For a pending tab it uses `.preferred`, so
///   AppKit opens the window directly as a tab of the current window — with no
///   standalone-window flash. Otherwise it uses `.automatic`, so File ▸ New (⌘N)
///   opens a *separate* window. A shared tabbing identifier groups the tabs the
///   user does create.

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
    /// attach reads this to decide whether it should open as a tab of the
    /// current window rather than as a standalone window.
    private static var pendingTab = false

    /// Opens a new untitled document. Because `pendingTab` is set, the window
    /// that materializes attaches itself as a tab of the current window (see
    /// `WindowConfiguringView`) instead of opening standalone.
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
/// tabbing once AppKit has attached the view.
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { WindowConfiguringView() }
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
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.tabbingIdentifier = mownTabbingIdentifier

        if DocumentTabbing.consumePendingTab() {
            // ⌘T / "+": join the current window as a tab regardless of the
            // user's system "prefer tabs" setting.
            window.tabbingMode = .preferred
        } else {
            // ⌘N / launch: follow the system setting — a separate window by
            // default.
            window.tabbingMode = .automatic
        }
    }
}
