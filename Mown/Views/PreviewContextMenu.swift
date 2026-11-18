import AppKit
import WebKit

/// Shared constant for the script message the preview posts on right-click,
/// describing what's under the pointer: `{kind: "diagram", svg}` for a
/// rendered Mermaid diagram, `{kind: "image", src}` for an `<img>`, or `{}`
/// for anything else. Mirrors the `MermaidZoom` pattern so the page-side JS
/// (in `PreviewTemplate`) and the native handler registration (in
/// `PreviewView`) can't drift apart.
enum PreviewContextMenu {
    static let messageName = "mownContextMenu"

    /// Decodes the message body posted by the page's `contextmenu` listener.
    static func target(from body: Any) -> PreviewContextTarget? {
        guard let dict = body as? [String: Any] else { return nil }
        switch dict["kind"] as? String {
        case "diagram":
            guard let svg = dict["svg"] as? String, !svg.isEmpty else { return nil }
            return .diagram(svg: svg)
        case "image":
            guard let src = dict["src"] as? String, let url = URL(string: src) else { return nil }
            return .image(url)
        default:
            return nil
        }
    }
}

/// What the user right-clicked in a preview web view.
enum PreviewContextTarget: Equatable {
    /// A Mermaid diagram, carried as the `<svg>` markup mermaid.js injected.
    case diagram(svg: String)
    /// An `<img>`, by its resolved source URL (`mownres://doc/…` for files
    /// next to the document, http(s) for remote images, …).
    case image(URL)
}

/// A `WKWebView` whose context menu adapts to `contextTarget`:
/// - a diagram gets "Copy Image" and "Export Diagram As…";
/// - an image gets a "Copy Image" that reads the bytes itself, replacing
///   WebKit's own item, which doesn't reliably handle images served over the
///   custom `mownres://` scheme.
/// The preview updates `contextTarget` per right-click from the page's
/// `contextmenu` message; the zoom window sets it once, since its whole
/// content is one diagram.
final class PreviewContextWebView: WKWebView {
    var contextTarget: PreviewContextTarget?
    var isDarkTheme = false

    /// Identifier WebKit stamps on its built-in "Copy Image" item.
    private static let webKitCopyImageIdentifier = "WKMenuItemIdentifierCopyImage"

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        switch contextTarget {
        case .diagram:
            menu.addItem(.separator())
            menu.addItem(makeItem("Copy Image", #selector(copyImage(_:))))
            menu.addItem(makeItem("Export Diagram As…", #selector(exportDiagram(_:))))
        case .image:
            let copy = makeItem("Copy Image", #selector(copyImage(_:)))
            if let index = menu.items.firstIndex(where: {
                $0.identifier?.rawValue == Self.webKitCopyImageIdentifier
            }) {
                menu.removeItem(at: index)
                menu.insertItem(copy, at: index)
            } else {
                menu.addItem(.separator())
                menu.addItem(copy)
            }
        case nil:
            break
        }
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc func copyImage(_ sender: Any?) {
        switch contextTarget {
        case .diagram(let svg):
            MermaidDiagramExporter.copy(svg: svg, isDark: isDarkTheme, window: window)
        case .image(let url):
            guard let resolved = fileURL(for: url) else {
                presentAlert(ImageClipboard.CopyError.fetchFailed("Unsupported image location."),
                             title: "Copy Failed", in: window)
                return
            }
            ImageClipboard.copy(contentsOf: resolved) { [weak self] error in
                if let error { presentAlert(error, title: "Copy Failed", in: self?.window) }
            }
        case nil:
            break
        }
    }

    @objc private func exportDiagram(_ sender: Any?) {
        guard case .diagram(let svg) = contextTarget else { return }
        MermaidDiagramExporter.export(svg: svg, isDark: isDarkTheme, from: window)
    }

    /// Maps an image source to something `ImageClipboard` can load: doc-scheme
    /// URLs become the file they're served from; file, http(s), and data URLs
    /// pass through; anything else (an unknown scheme) is refused.
    private func fileURL(for url: URL) -> URL? {
        if url.scheme == PreviewSchemeHandler.scheme {
            let handler = configuration.urlSchemeHandler(forURLScheme: PreviewSchemeHandler.scheme)
            return (handler as? PreviewSchemeHandler)?.fileURL(forDocURL: url)
        }
        switch url.scheme?.lowercased() {
        case "file", "http", "https", "data": return url
        default: return nil
        }
    }
}
