import AppKit

/// Removes AppKit's auto-injected "Enter Full Screen" item from the View menu.
///
/// SwiftUI's static View menu only holds the app's own items; AppKit injects
/// "Show Tab Bar", "Show All Tabs", and "Enter Full Screen" live when the menu
/// opens. The app already provides its own "Toggle Full Screen", so we strip
/// the redundant system item each time the menu is about to show. We forward to
/// any pre-existing delegate so we don't clobber AppKit/SwiftUI behavior.
final class ViewMenuTrimmer: NSObject, NSMenuDelegate {
    private weak var originalDelegate: NSMenuDelegate?

    func install(attempt: Int = 0) {
        guard let viewMenu = NSApp.mainMenu?.items.first(where: { $0.title == "View" })?.submenu else {
            if attempt < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.install(attempt: attempt + 1)
                }
            }
            return
        }
        if viewMenu.delegate !== self {
            originalDelegate = viewMenu.delegate
            viewMenu.delegate = self
        }
    }

    private func trim(_ menu: NSMenu) {
        for item in menu.items where item.action == #selector(NSWindow.toggleFullScreen(_:)) {
            menu.removeItem(item)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        originalDelegate?.menuNeedsUpdate?(menu)
        trim(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        originalDelegate?.menuWillOpen?(menu)
        trim(menu)
    }
}
