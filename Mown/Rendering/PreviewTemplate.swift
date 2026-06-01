import Foundation

/// Wraps rendered Markdown HTML in a full HTML document with bundled CSS and
/// `highlight.js` for code-block syntax highlighting (§3.3, §4 polish).
enum PreviewTemplate {
    static func wrap(bodyHTML: String, isDark: Bool) -> String {
        let appCSS  = loadResource(isDark ? "preview-dark" : "preview", ext: "css")
        let hljsCSS = loadResource(isDark ? "highlight-dark" : "highlight-light", ext: "css")
        let hljsJS  = loadResource("highlight.min", ext: "js")

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(appCSS)</style>
        <style>\(hljsCSS)</style>
        </head>
        <body class="markdown-body">
        \(bodyHTML)
        <script>\(hljsJS)</script>
        <script>
        if (window.hljs) {
            document.querySelectorAll('pre code').forEach(function (el) {
                try { hljs.highlightElement(el); } catch (_) {}
            });
        }
        </script>
        </body>
        </html>
        """
    }

    private static func loadResource(_ name: String, ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext),
              let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return ""
        }
        return contents
    }
}
