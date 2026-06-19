import AppKit
import WebKit

/// Shared constant for the script message the preview posts when a rendered
/// Mermaid diagram is clicked. Lives here so the page-side JS (in
/// `PreviewTemplate`) and the native handler registration (in `PreviewView`)
/// can't drift apart.
enum MermaidZoom {
    static let messageName = "mownMermaidZoom"
}

/// A standalone window that shows a single rendered Mermaid diagram at full
/// window size for a closer look. Mermaid output is vector (SVG), so filling a
/// large, magnifiable web view keeps it crisp at any size — the "high
/// resolution" the small inline preview can't give. Closes on ⎋ (Esc).
final class MermaidZoomWindowController: NSWindowController, NSWindowDelegate {
    /// Keeps presented controllers alive: an `NSWindowController` isn't retained
    /// by its window, so without this strong reference the window would
    /// deallocate the moment `present` returns.
    private static var active: Set<MermaidZoomWindowController> = []

    /// Local key monitor backing ⎋-to-close. A monitor (rather than relying on
    /// the responder chain) closes the window even while the WKWebView is first
    /// responder and would otherwise swallow the key event.
    private var keyMonitor: Any?

    /// Opens a zoom window for `svg`, themed to match the preview and sized
    /// relative to its source window.
    static func present(svg: String, isDark: Bool, relativeTo parent: NSWindow?) {
        let controller = MermaidZoomWindowController(svg: svg, isDark: isDark, parent: parent)
        active.insert(controller)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private init(svg: String, isDark: Bool, parent: NSWindow?) {
        let contentRect = Self.frame(for: parent)
        let window = NSWindow(contentRect: contentRect,
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Diagram"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 320, height: 240)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)

        // No script execution needed to display an SVG; disabling it keeps any
        // markup that slips into a diagram from running.
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: contentRect, configuration: config)
        webView.allowsMagnification = true       // trackpad pinch to zoom in further
        webView.setValue(false, forKey: "drawsBackground")
        webView.loadHTMLString(Self.html(svg: svg, isDark: isDark), baseURL: nil)
        window.contentView = webView

        super.init(window: window)
        window.delegate = self
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.keyCode == 53 {   // Esc
                self.close()
                return nil
            }
            return event
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        Self.active.remove(self)   // last strong ref → controller (and window) deallocate
    }

    /// Centers a window over `parent`, sized to a comfortable fraction of it, or
    /// falls back to a sensible default when there's no source window.
    private static func frame(for parent: NSWindow?) -> NSRect {
        guard let p = parent?.frame else {
            return NSRect(x: 0, y: 0, width: 900, height: 680)
        }
        let w = max(480, p.width * 0.85)
        let h = max(360, p.height * 0.85)
        return NSRect(x: p.midX - w / 2, y: p.midY - h / 2, width: w, height: h)
    }

    /// Wraps the diagram SVG in a minimal document that centers it and lets it
    /// grow to fill the window. The `!important` overrides neutralize the inline
    /// `max-width` Mermaid stamps on its `<svg>`, which would otherwise cap the
    /// diagram at its original inline size.
    private static func html(svg: String, isDark: Bool) -> String {
        let bg = isDark ? "#0d1117" : "#ffffff"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            html, body { margin: 0; width: 100%; height: 100%; background: \(bg); }
            body { display: flex; align-items: center; justify-content: center;
                   box-sizing: border-box; padding: 24px; }
            svg { max-width: 100% !important; max-height: 100% !important;
                  width: auto; height: auto; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}
