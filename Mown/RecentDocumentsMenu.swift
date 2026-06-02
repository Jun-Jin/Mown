import AppKit

/// Populates the File ▸ Open Recent submenu from `recentDocumentURLs`.
///
/// SwiftUI's `DocumentGroup` *tracks* recent documents — they show up in
/// `NSDocumentController.shared.recentDocumentURLs` — but it never adds them to
/// the actual Open Recent menu, which it leaves holding only "Clear Menu". We
/// take over that submenu and rebuild it on demand, so recents are reachable
/// without depending on Spotlight or the system open panel.
final class RecentDocumentsMenuController: NSObject, NSMenuDelegate {
    /// Installs self as the Open Recent submenu's delegate. SwiftUI builds the
    /// menu slightly after launch, so retry briefly until it appears.
    func install(attempt: Int = 0) {
        if let menu = Self.findOpenRecentMenu() {
            menu.delegate = self
        } else if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.install(attempt: attempt + 1)
            }
        }
    }

    /// Rebuilt every time the menu opens, so it always reflects the current list.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Drop entries whose file no longer exists — opening them would just fail.
        let urls = NSDocumentController.shared.recentDocumentURLs
            .filter { FileManager.default.fileExists(atPath: $0.path) }

        for url in urls {
            let item = NSMenuItem(title: url.lastPathComponent,
                                  action: #selector(openRecentDocument(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }

        if !urls.isEmpty { menu.addItem(.separator()) }
        // Keep "Clear Menu"; routed to the document controller via the responder
        // chain (target nil) exactly as the system item was.
        let clear = NSMenuItem(title: "Clear Menu",
                               action: #selector(NSDocumentController.clearRecentDocuments(_:)),
                               keyEquivalent: "")
        clear.target = nil
        menu.addItem(clear)
    }

    @objc private func openRecentDocument(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        // Routes through the same path as Finder / the `mown` CLI: the resulting
        // file-backed window joins the current tab group (see WindowTabbing).
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// Locates the Open Recent submenu without depending on its (localized)
    /// title: it's the one whose items include `clearRecentDocuments:`.
    private static func findOpenRecentMenu() -> NSMenu? {
        func search(_ menu: NSMenu) -> NSMenu? {
            for item in menu.items {
                guard let sub = item.submenu else { continue }
                if sub.items.contains(where: { $0.action == #selector(NSDocumentController.clearRecentDocuments(_:)) }) {
                    return sub
                }
                if let found = search(sub) { return found }
            }
            return nil
        }
        return NSApp.mainMenu.flatMap(search)
    }
}
