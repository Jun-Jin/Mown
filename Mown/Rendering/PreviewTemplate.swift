import Foundation

/// Wraps rendered Markdown HTML in a full HTML document with bundled CSS and
/// `highlight.js` for code-block syntax highlighting (§3.3, §4 polish), plus
/// `mermaid.js` to render ```mermaid fences as diagrams.
enum PreviewTemplate {
    static func wrap(bodyHTML: String, isDark: Bool) -> String {
        let appCSS  = loadResource(isDark ? "preview-dark" : "preview", ext: "css")
        let hljsCSS = loadResource(isDark ? "highlight-dark" : "highlight-light", ext: "css")
        let hljsJS  = loadResource("highlight.min", ext: "js")

        // cmark (with GITHUB_PRE_LANG) renders a ```mermaid fence as
        // <pre lang="mermaid">. Only pull in the 3 MB mermaid bundle when the
        // document actually has one — most don't.
        let needsMermaid = bodyHTML.contains("lang=\"mermaid\"") || bodyHTML.contains("language-mermaid")
        // Served by BundleResourceSchemeHandler — `loadHTMLString` with a file://
        // baseURL won't load a local <script src>, so we go through the scheme.
        let mermaidTag = needsMermaid ? #"<script src="mownres://res/mermaid.min.js"></script>"# : ""
        let mermaidTheme = isDark ? "dark" : "default"

        // KaTeX renders the `.mown-math` containers MathExtractor leaves behind.
        // Only pull in its ~290 KB of CSS+JS when the document actually has math.
        // The bundled CSS points fonts at `fonts/…`; rewrite that to the scheme
        // the web view can serve (the woff2 files live flat in the bundle, and
        // WebKit picks woff2 first so the un-rewritten woff/ttf URLs never load).
        let needsKaTeX = bodyHTML.contains("mown-math")
        let katexStyle = needsKaTeX
            ? "<style>\(loadResource("katex.min", ext: "css").replacingOccurrences(of: "url(fonts/", with: "url(mownres://res/"))</style>"
            : ""
        let katexTag = needsKaTeX ? #"<script src="mownres://res/katex.min.js"></script>"# : ""

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(appCSS)</style>
        <style>\(hljsCSS)</style>
        \(katexStyle)
        </head>
        <body class="markdown-body">
        \(bodyHTML)
        <script>\(hljsJS)</script>
        \(mermaidTag)
        \(katexTag)
        <script>
        (function () {
            // Turn ```mermaid fences (<pre lang="mermaid">) into mermaid
            // containers *before* highlight.js runs, so they render as diagrams
            // rather than being syntax-highlighted as source.
            document.querySelectorAll('pre[lang="mermaid"], pre > code.language-mermaid').forEach(function (node) {
                var pre = node.tagName === 'PRE' ? node : node.parentElement;
                var code = pre.querySelector('code') || pre;
                var div = document.createElement('div');
                div.className = 'mermaid';
                div.textContent = code.textContent;
                pre.replaceWith(div);
            });

            if (window.hljs) {
                document.querySelectorAll('pre code').forEach(function (el) {
                    try { hljs.highlightElement(el); } catch (_) {}
                });
            }

            if (window.mermaid) {
                try {
                    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: '\(mermaidTheme)' });
                    mermaid.run({ querySelector: '.mermaid', suppressErrors: true });
                } catch (_) {}
            }

            if (window.katex) {
                // Each .mown-math node carries its raw TeX as text content;
                // katex.render replaces that text with the typeset output.
                document.querySelectorAll('.mown-math').forEach(function (el) {
                    try {
                        katex.render(el.textContent, el, {
                            displayMode: el.getAttribute('data-display') === '1',
                            throwOnError: false,
                            errorColor: '#cc0000'
                        });
                    } catch (_) {}
                });
            }
        })();
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
