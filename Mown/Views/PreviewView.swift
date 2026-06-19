import SwiftUI
import WebKit
import AppKit
import UniformTypeIdentifiers
import Combine

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
    /// Shared scroll-fraction bus used in split mode. `nil` outside split.
    var scrollSync: ScrollSync? = nil
    /// Browser-style zoom factor (1.0 = 100%). Applied via `WKWebView.pageZoom`,
    /// which scales text and layout together and survives the per-keystroke
    /// `loadHTMLString` reloads since it lives on the web view, not the document.
    var zoom: Double = 1.0
    /// Called with a new zoom factor as the user pinch-zooms the preview. The
    /// owner writes it back to the shared `previewZoom` setting, which then
    /// flows in again through `zoom` — so pinch and the ⌘+/⌘-/⌘0 menu share one
    /// source of truth. `nil` disables pinch zoom.
    var onZoomChange: ((Double) -> Void)? = nil

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

        // Scroll bridge: a user script posts the page's scroll fraction to
        // the coordinator, and the coordinator pushes incoming fractions back
        // via evaluateJavaScript. Always installed (cheap) so toggling split
        // mode at runtime doesn't require rebuilding the WKWebView.
        config.userContentController.add(context.coordinator,
                                         name: PreviewScrollBridge.messageName)
        config.userContentController.addUserScript(PreviewScrollBridge.userScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground") // let CSS background show through
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator

        // Trackpad pinch drives the shared zoom (pageZoom) rather than WKWebView's
        // built-in magnification, so a pinch reflows text/layout exactly like the
        // menu zoom and persists, instead of scaling the rendered pixels.
        let pinch = NSMagnificationGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleMagnify(_:)))
        webView.addGestureRecognizer(pinch)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if webView.pageZoom != CGFloat(zoom) { webView.pageZoom = CGFloat(zoom) }
        context.coordinator.currentZoom = zoom
        context.coordinator.onZoomChange = onZoomChange
        context.coordinator.schemeHandler.docDirectory = baseURL
        context.coordinator.attachScrollSync(webView: webView, sync: scrollSync)
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

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let schemeHandler = PreviewSchemeHandler()
        /// Live zoom factor, mirrored from `updateNSView`; the pinch gesture reads
        /// it at gesture start so each pinch compounds from the current zoom.
        var currentZoom: Double = 1.0
        /// Reports pinch-driven zoom changes back to the owner.
        var onZoomChange: ((Double) -> Void)?
        /// Zoom captured at the start of a pinch — the magnification delta is
        /// applied relative to this so the gesture feels anchored.
        private var pinchBaseZoom: Double = 1.0
        private(set) weak var boundSync: ScrollSync?
        private var syncCancellable: AnyCancellable?
        /// Last fraction received from the editor; replayed once the page
        /// signals it's ready, since evaluateJavaScript before `didFinish`
        /// would be ignored or hit a stale document.
        private var pendingFraction: CGFloat?
        private weak var lastWebView: WKWebView?
        private var navigationReady = false

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

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            navigationReady = true
            // The HTML reloads on every keystroke (debounced), so re-apply the
            // last known fraction so the preview doesn't snap back to the top
            // while the user is scrolling the editor.
            if let pending = pendingFraction { apply(fraction: pending, webView: webView) }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            navigationReady = false
        }

        // MARK: - Pinch zoom

        @objc func handleMagnify(_ recognizer: NSMagnificationGestureRecognizer) {
            switch recognizer.state {
            case .began:
                pinchBaseZoom = currentZoom
            case .changed, .ended:
                // `magnification` is the cumulative delta since the gesture began
                // (0 at start). Out-of-range results are clamped by the setting's
                // own writer, so no clamping is needed here.
                onZoomChange?(pinchBaseZoom * (1 + recognizer.magnification))
            default:
                break
            }
        }

        // MARK: - Scroll bridge

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.name == PreviewScrollBridge.messageName,
                  let value = message.body as? NSNumber,
                  let sync = boundSync else { return }
            sync.report(CGFloat(value.doubleValue), from: .preview)
        }

        func attachScrollSync(webView: WKWebView, sync: ScrollSync?) {
            lastWebView = webView
            if boundSync === sync { return }
            syncCancellable = nil
            boundSync = sync
            guard let sync else { return }
            syncCancellable = sync.$event
                .receive(on: RunLoop.main)
                .sink { [weak self, weak webView] event in
                    guard let self, let webView else { return }
                    guard event.source != .preview else { return }
                    self.pendingFraction = event.fraction
                    self.apply(fraction: event.fraction, webView: webView)
                }
        }

        private func apply(fraction: CGFloat, webView: WKWebView) {
            guard navigationReady else { return }
            // Set a flag so the page-side scroll listener recognizes this
            // scroll as programmatic and skips reporting it back. Double-RAF
            // ensures the scroll event fires before we clear the flag.
            let js = """
            (function () {
                window.__mownProgrammaticScroll = true;
                var max = Math.max(1, document.documentElement.scrollHeight - window.innerHeight);
                window.scrollTo(0, max * \(fraction));
                requestAnimationFrame(function () {
                    requestAnimationFrame(function () {
                        window.__mownProgrammaticScroll = false;
                    });
                });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

/// Page-side glue for the scroll-sync feature. Lives as a constant so the
/// WKUserScript and message-handler name don't drift apart.
private enum PreviewScrollBridge {
    static let messageName = "mownScroll"

    /// Posts the current scroll fraction to native on every user scroll, while
    /// ignoring scrolls flagged as programmatic (so the editor's `apply` call
    /// doesn't bounce back).
    static let userScript = WKUserScript(
        source: """
        (function () {
            var rafPending = false;
            function fraction() {
                var doc = document.documentElement;
                var max = Math.max(1, doc.scrollHeight - window.innerHeight);
                return window.scrollY / max;
            }
            window.addEventListener('scroll', function () {
                if (window.__mownProgrammaticScroll) return;
                if (rafPending) return;
                rafPending = true;
                requestAnimationFrame(function () {
                    rafPending = false;
                    try {
                        window.webkit.messageHandlers.\(messageName).postMessage(fraction());
                    } catch (_) {}
                });
            }, { passive: true });
        })();
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
    )
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
