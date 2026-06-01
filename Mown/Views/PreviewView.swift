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
        // bundled highlight.js needs to run, and it runs at load time.
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

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
