import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers

struct PreviewView: NSViewRepresentable {
    let html: String
    /// Resolved by `ContentView` from the user's "View Theme" setting and the
    /// live system appearance — drives both the preview CSS and the web view's
    /// own chrome (scrollbars, form controls).
    let isDark: Bool
    /// Directory the rendered HTML treats as its base — relative `<img src="…">`
    /// paths in the document resolve against this via the `mownres://doc/…`
    /// scheme handler. `nil` for untitled docs; then relative paths fall back
    /// to the app bundle.
    let baseURL: URL?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Only the bundled highlight.js / mermaid.js need to run, at load time.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // One scheme handler serves two virtual roots:
        //   mownres://res/<name.ext>          → app bundle resource (mermaid.js)
        //   mownres://doc/<relative/path>     → file under the document's dir
        // The doc root is what lets `<img src="pics/foo.png">` resolve next to
        // the markdown file without tripping WKWebView's file:// origin policy.
        config.setURLSchemeHandler(context.coordinator.schemeHandler,
                                   forURLScheme: PreviewSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // let CSS background show through
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        context.coordinator.schemeHandler.docDirectory = baseURL
        let full = PreviewTemplate.wrap(bodyHTML: html, isDark: isDark)
        // baseURL drives relative-path resolution in the loaded HTML:
        //   - With a doc URL, use `mownres://doc/` so `<img src="x.png">`
        //     becomes `mownres://doc/x.png` and gets served from the doc dir.
        //   - Without one (untitled docs), keep the bundle URL so bundled CSS
        //     resolves and we don't try to serve from a nonexistent doc dir.
        let base = baseURL != nil
            ? URL(string: "\(PreviewSchemeHandler.scheme)://doc/")
            : Bundle.main.resourceURL
        webView.loadHTMLString(full, baseURL: base)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let schemeHandler = PreviewSchemeHandler()

        // Open external links in the user's browser instead of inside the preview.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

/// Serves preview resources over a custom scheme so the WKWebView can pull in
/// bundled scripts (mermaid.js) and sibling files of the current document
/// (images referenced by `<img src="…">`) without tripping `loadHTMLString`'s
/// `file://` restrictions on local `<script src>` and cross-file image loads.
///
/// URL layout:
///   `mownres://res/<name>.<ext>` → looked up by name in the app bundle.
///   `mownres://doc/<relative/path>` → resolved under `docDirectory`.
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mownres"

    /// The current document's directory. Updated on every `updateNSView`.
    /// Reads/writes are serialized by SwiftUI's main-actor update flow, so no
    /// extra synchronization is needed.
    var docDirectory: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let root = url.host ?? ""
        let data: Data?
        let resolvedURL: URL?
        switch root {
        case "res":
            // Look up by bundle filename; the URL path can't escape the bundle.
            let file = (url.lastPathComponent as NSString)
            let name = file.deletingPathExtension
            let ext = file.pathExtension
            resolvedURL = name.isEmpty
                ? nil
                : Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext)
        case "doc":
            // Relative path under the document's directory; refuse anything
            // that escapes via `..` after normalization.
            if let dir = docDirectory {
                let rel = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                let candidate = dir.appendingPathComponent(rel).standardized
                resolvedURL = candidate.path.hasPrefix(dir.standardized.path) ? candidate : nil
            } else {
                resolvedURL = nil
            }
        default:
            resolvedURL = nil
        }

        guard let resolved = resolvedURL,
              let bytes = try? Data(contentsOf: resolved) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        data = bytes

        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": Self.mimeType(for: resolved)])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data!)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// Resolve a MIME type for the WKWebView. Falls back to UTType so we don't
    /// have to hand-maintain a long list of image formats.
    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "js":  return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "svg": return "image/svg+xml"
        default:
            if let type = UTType(filenameExtension: url.pathExtension),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }
    }
}
