import SwiftUI
import WebKit
import AppKit

struct PreviewView: NSViewRepresentable {
    let html: String
    /// Resolved by `ContentView` from the user's "View Theme" setting and the
    /// live system appearance — drives both the preview CSS and the web view's
    /// own chrome (scrollbars, form controls).
    let isDark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Disable JS-driven navigation from the rendered preview — only the
        // bundled highlight.js / mermaid.js need to run, at load time.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Serve large bundled scripts (mermaid.js) over a custom scheme:
        // `loadHTMLString` with a file:// baseURL refuses local <script src>.
        config.setURLSchemeHandler(BundleResourceSchemeHandler(),
                                   forURLScheme: BundleResourceSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // let CSS background show through
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        let full = PreviewTemplate.wrap(bodyHTML: html, isDark: isDark)
        webView.loadHTMLString(full, baseURL: Bundle.main.resourceURL)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
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

/// Serves bundled web resources (e.g. `mermaid.min.js`) to the preview over the
/// `mownres://` scheme. The preview is loaded with `loadHTMLString` + a file://
/// baseURL, which blocks local `<script src>`, so a scheme handler is the
/// reliable way to pull in large bundled scripts without inlining megabytes of
/// JS into every render. Resources are resolved by name from the app bundle, so
/// the URL path can't escape it.
private final class BundleResourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "mownres"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        let file = (url.lastPathComponent as NSString)
        let name = file.deletingPathExtension
        let ext = file.pathExtension
        guard !name.isEmpty,
              let resourceURL = Bundle.main.url(forResource: name, withExtension: ext.isEmpty ? nil : ext),
              let data = try? Data(contentsOf: resourceURL) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime: String
        switch ext.lowercased() {
        case "js":  mime = "application/javascript; charset=utf-8"
        case "css": mime = "text/css; charset=utf-8"
        default:    mime = "application/octet-stream"
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": mime])!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
