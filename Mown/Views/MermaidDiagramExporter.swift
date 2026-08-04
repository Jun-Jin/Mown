import AppKit
import UniformTypeIdentifiers
import WebKit

/// Shared constant for the script message the preview posts on right-click,
/// carrying the SVG of the Mermaid diagram under the pointer (or "" when the
/// click wasn't on a diagram). Mirrors the `MermaidZoom` pattern so the
/// page-side JS (in `PreviewTemplate`) and the native handler registration
/// (in `PreviewView`) can't drift apart.
enum MermaidExportMenu {
    static let messageName = "mownMermaidContext"
}

/// A `WKWebView` whose context menu offers "Export Diagram As…" whenever
/// `exportableSVG` is set. The preview updates that per right-click from the
/// page's `contextmenu` message; the zoom window sets it once, since its whole
/// content is one diagram.
final class ExportMenuWebView: WKWebView {
    var exportableSVG: String?
    var exportIsDark = false

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        guard let svg = exportableSVG, !svg.isEmpty else { return }
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Export Diagram As…",
                              action: #selector(exportDiagram(_:)), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
    }

    @objc private func exportDiagram(_ sender: Any?) {
        guard let svg = exportableSVG, !svg.isEmpty else { return }
        MermaidDiagramExporter.export(svg: svg, isDark: exportIsDark, from: window)
    }
}

/// The file formats a diagram can be exported as. Order is the save panel's
/// popup order; PNG leads as the default.
enum MermaidExportFormat: CaseIterable {
    case png
    case svg
    case jpeg

    var displayName: String {
        switch self {
        case .png: return "PNG"
        case .svg: return "SVG"
        case .jpeg: return "JPEG"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: return .png
        case .svg: return .svg
        case .jpeg: return .jpeg
        }
    }

    /// Encoder settings for the bitmap formats; nil for SVG, which is written
    /// as text and never rasterized.
    var bitmapEncoding: (type: NSBitmapImageRep.FileType,
                         properties: [NSBitmapImageRep.PropertyKey: Any])? {
        switch self {
        case .png: return (.png, [:])
        case .jpeg: return (.jpeg, [.compressionFactor: 0.9])
        case .svg: return nil
        }
    }
}

/// The save-panel → render → write flow shared by every export entry point
/// (the preview's context menu, and the zoom window's context menu and ⌘S).
/// The panel carries the standard macOS "Format:" popup (as in TextEdit or
/// Preview) for choosing PNG, SVG, or JPEG.
enum MermaidDiagramExporter {
    static func export(svg: String, isDark: Bool, from window: NSWindow?) {
        let panel = NSSavePanel()
        let picker = FormatPicker(panel: panel)
        panel.accessoryView = picker.view
        panel.allowedContentTypes = [picker.selected.contentType]
        panel.nameFieldStringValue = "diagram.png"
        // `finish` captures `picker`, keeping it — the popup's target — alive
        // for as long as the panel is on screen.
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            write(svg: svg, isDark: isDark, format: picker.selected, to: url, window: window)
        }
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// Rewrites the diagram markup to stand alone as an .svg file. In-page,
    /// mermaid sizes the SVG with `width="100%"` plus an inline `max-width`
    /// style and leaves the background to the page — none of which survives on
    /// disk. So: pin explicit pixel width/height (from the viewBox), drop the
    /// `max-width`, slip a theme-colored rect behind the drawing (a dark-theme
    /// diagram would be unreadable on a white viewer without it), and
    /// guarantee an `xmlns` so the file parses as XML. Everything else —
    /// including the `<style>` block mermaid embeds — already travels inside
    /// the SVG itself.
    static func standaloneSVG(_ svg: String, isDark: Bool) -> String {
        guard let tagStart = svg.range(of: "<svg"),
              let tagClose = svg.range(of: ">", range: tagStart.upperBound..<svg.endIndex) else {
            return svg   // no <svg> root to fix up; write unchanged rather than mangle
        }
        let size = naturalSVGSize(of: svg)
        var tag = String(svg[tagStart.lowerBound..<tagClose.upperBound])

        tag = replacingPattern(#"\s(?:width|height)\s*=\s*["'][^"']*["']"#, in: tag, with: "")
        tag = replacingPattern(#"max-width:\s*[^;"']*;?\s*"#, in: tag, with: "")
        tag = replacingPattern(#"\sstyle\s*=\s*["']\s*["']"#, in: tag, with: "")  // now-empty style
        if !tag.contains("xmlns=") {
            tag = tag.replacingOccurrences(of: "<svg",
                                           with: #"<svg xmlns="http://www.w3.org/2000/svg""#)
        }
        tag.removeLast()   // the ">", re-added after the size attributes
        tag += #" width="\#(svgNumber(size.width))" height="\#(svgNumber(size.height))">"#

        let box = svgViewBox(of: svg)
        let backdrop = #"<rect x="\#(box?.x ?? "0")" y="\#(box?.y ?? "0")" width="\#(svgNumber(size.width))" height="\#(svgNumber(size.height))" fill="\#(themeBackground(isDark: isDark))"/>"#

        return String(svg[svg.startIndex..<tagStart.lowerBound]) + tag + backdrop
            + String(svg[tagClose.upperBound...])
    }

    private static func write(svg: String, isDark: Bool, format: MermaidExportFormat,
                              to url: URL, window: NSWindow?) {
        guard let encoding = format.bitmapEncoding else {
            do {
                try Data(standaloneSVG(svg, isDark: isDark).utf8).write(to: url)
            } catch {
                presentError(error, in: window)
            }
            return
        }
        MermaidBitmapRenderer.render(svg: svg, isDark: isDark) { result in
            do {
                let rep = try result.get()
                guard let data = rep.representation(using: encoding.type,
                                                    properties: encoding.properties) else {
                    throw MermaidBitmapRenderer.RenderError
                        .snapshotFailed("\(format.displayName) encoding failed.")
                }
                try data.write(to: url)
            } catch {
                presentError(error, in: window)
            }
        }
    }

    private static func presentError(_ error: Error, in window: NSWindow?) {
        let alert = NSAlert(error: error)
        alert.messageText = "Export Failed"
        if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// The save panel's "Format:" accessory. Selecting a format retargets the
    /// panel's allowed content type, which also swaps the extension shown in
    /// the name field.
    private final class FormatPicker: NSObject {
        let view: NSView
        private let popup: NSPopUpButton
        private weak var panel: NSSavePanel?

        var selected: MermaidExportFormat {
            let index = popup.indexOfSelectedItem
            let formats = MermaidExportFormat.allCases
            return formats.indices.contains(index) ? formats[index] : .png
        }

        init(panel: NSSavePanel) {
            self.panel = panel
            popup = NSPopUpButton(frame: .zero, pullsDown: false)
            popup.addItems(withTitles: MermaidExportFormat.allCases.map(\.displayName))
            let label = NSTextField(labelWithString: "Format:")
            let stack = NSStackView(views: [label, popup])
            stack.orientation = .horizontal
            stack.spacing = 8
            stack.edgeInsets = NSEdgeInsets(top: 12, left: 20, bottom: 12, right: 20)
            stack.frame = NSRect(origin: .zero, size: stack.fittingSize)
            view = stack
            super.init()
            popup.target = self
            popup.action = #selector(formatChanged(_:))
        }

        @objc private func formatChanged(_ sender: Any?) {
            panel?.allowedContentTypes = [selected.contentType]
        }
    }
}

/// Rasterizes a rendered Mermaid diagram (the `<svg>` markup mermaid.js
/// injected into the preview) to a bitmap for the PNG and JPEG exports. The
/// SVG is loaded in an offscreen WKWebView and snapshotted, so anything the
/// preview can display — including `<foreignObject>` HTML labels, which
/// CoreSVG/NSImage cannot draw — exports exactly as shown. Script execution
/// stays disabled, matching the zoom window's hardened stance toward markup
/// that slips into a diagram.
enum MermaidBitmapRenderer {
    /// CSS pixels of breathing room around the diagram in the exported image.
    private static let padding: CGFloat = 16
    /// Export at 2× so bitmaps stay crisp on Retina displays and when zoomed.
    private static let scale: CGFloat = 2

    enum RenderError: LocalizedError {
        case snapshotFailed(String)
        var errorDescription: String? {
            switch self {
            case .snapshotFailed(let reason):
                return "Could not render the diagram to an image. \(reason)"
            }
        }
    }

    /// Renders `svg` on the theme background and calls `completion` on the
    /// main queue with the bitmap (or an error).
    static func render(svg: String, isDark: Bool,
                       completion: @escaping (Result<NSBitmapImageRep, Error>) -> Void) {
        let size = naturalSVGSize(of: svg)
        let frame = NSRect(x: 0, y: 0,
                           width: (size.width + padding * 2) * scale,
                           height: (size.height + padding * 2) * scale)

        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: frame, configuration: config)
        let session = Session(webView: webView, completion: completion)
        Session.active.insert(session)
        webView.navigationDelegate = session
        webView.loadHTMLString(html(svg: svg, size: size, isDark: isDark), baseURL: nil)
    }

    /// Pins the SVG to its natural size (neutralizing the inline `max-width`
    /// mermaid stamps on it) and scales the whole page up with CSS `zoom`, so
    /// a 1:1 snapshot of the web view yields a `scale`× resolution image.
    private static func html(svg: String, size: NSSize, isDark: Bool) -> String {
        let bg = themeBackground(isDark: isDark)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
            html, body { margin: 0; padding: 0; background: \(bg); }
            body { zoom: \(scale); }
            #wrap { padding: \(padding)px; width: \(size.width)px; }
            #wrap svg { width: \(size.width)px !important; height: \(size.height)px !important;
                        max-width: none !important; }
        </style>
        </head>
        <body><div id="wrap">\(svg)</div></body>
        </html>
        """
    }

    /// Owns the offscreen web view for the duration of one render. A web view
    /// isn't retained by its own load, so without this holder both it and the
    /// delegate would deallocate before `didFinish` fires.
    private final class Session: NSObject, WKNavigationDelegate {
        static var active: Set<Session> = []

        private let webView: WKWebView
        private let completion: (Result<NSBitmapImageRep, Error>) -> Void

        init(webView: WKWebView, completion: @escaping (Result<NSBitmapImageRep, Error>) -> Void) {
            self.webView = webView
            self.completion = completion
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds
            let targetPixels = webView.bounds.size
            webView.takeSnapshot(with: config) { [self] image, error in
                defer { Session.active.remove(self) }
                guard let image else {
                    completion(.failure(RenderError.snapshotFailed(error?.localizedDescription ?? "")))
                    return
                }
                guard let rep = Self.bitmap(from: image, targetPixels: targetPixels) else {
                    completion(.failure(RenderError.snapshotFailed("Bitmap conversion failed.")))
                    return
                }
                completion(.success(rep))
            }
        }

        /// Converts the snapshot to a bitmap of exactly `targetPixels`. The
        /// page is laid out at `scale`× via CSS zoom, but the snapshot's pixel
        /// density also follows the display's backing scale (2× on Retina),
        /// which would silently double the export again — so resample whenever
        /// the dimensions disagree to keep output size display-independent.
        private static func bitmap(from image: NSImage, targetPixels: NSSize) -> NSBitmapImageRep? {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            let w = Int(targetPixels.width.rounded())
            let h = Int(targetPixels.height.rounded())
            if cg.width == w && cg.height == h {
                return NSBitmapImageRep(cgImage: cg)
            }
            guard let ctx = CGContext(data: nil, width: w, height: h,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: cg.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let resampled = ctx.makeImage() else { return nil }
            return NSBitmapImageRep(cgImage: resampled)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Session.active.remove(self)
            completion(.failure(error))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Session.active.remove(self)
            completion(.failure(error))
        }
    }
}

// MARK: - Shared SVG helpers

/// Preview theme backgrounds, mirrored from the preview CSS.
private func themeBackground(isDark: Bool) -> String { isDark ? "#0d1117" : "#ffffff" }

/// The diagram's natural size in CSS pixels. Mermaid stamps every SVG with a
/// `viewBox` whose width/height are the layout size it computed, so that is
/// authoritative; `width`/`height` attributes are a fallback for SVG from
/// other sources, and a fixed page size the last resort.
private func naturalSVGSize(of svg: String) -> NSSize {
    if let box = svgViewBox(of: svg) {
        return NSSize(width: box.width, height: box.height)
    }
    if let attrs = captureGroups(#"width\s*=\s*["']([\d.]+)(?:px)?["'][^>]*height\s*=\s*["']([\d.]+)(?:px)?["']"#, in: svg),
       attrs.count == 2, let w = Double(attrs[0]), let h = Double(attrs[1]), w > 1, h > 1 {
        return NSSize(width: w, height: h)
    }
    return NSSize(width: 1024, height: 768)
}

/// The `viewBox` origin (kept verbatim for re-emission) and size, when present
/// and sane.
private func svgViewBox(of svg: String) -> (x: String, y: String, width: Double, height: Double)? {
    guard let g = captureGroups(#"viewBox\s*=\s*["']\s*([-\d.eE]+)[\s,]+([-\d.eE]+)[\s,]+([\d.eE]+)[\s,]+([\d.eE]+)"#, in: svg),
          g.count == 4, let w = Double(g[2]), let h = Double(g[3]), w > 1, h > 1 else { return nil }
    return (g[0], g[1], w, h)
}

/// Whole-number sizes without a trailing ".0", so attributes read naturally.
private func svgNumber(_ value: CGFloat) -> String {
    value.rounded(.down) == value ? String(Int(value)) : String(Double(value))
}

private func captureGroups(_ pattern: String, in text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern),
          let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
    var groups: [String] = []
    for i in 1..<m.numberOfRanges {
        guard let r = Range(m.range(at: i), in: text) else { return nil }
        groups.append(String(text[r]))
    }
    return groups
}

private func replacingPattern(_ pattern: String, in text: String, with template: String) -> String {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return text }
    return re.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                       withTemplate: template)
}
