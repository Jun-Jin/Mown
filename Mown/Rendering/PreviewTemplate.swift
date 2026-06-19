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

        // Browser-style hover status bar (bottom-left), themed to match the
        // preview. Shows the raw `href` the author wrote — cleaner than the
        // resolved internal `mownres://doc/…` URL.
        let statusFG = isDark ? "#9da5b4" : "#57606a"
        let statusBG = isDark ? "#21252b" : "#f6f8fa"
        let statusBorder = isDark ? "#3a3f4b" : "#d0d7de"

        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>\(appCSS)</style>
        <style>\(hljsCSS)</style>
        <style>.markdown-body .mermaid { cursor: zoom-in; }</style>
        <style>
        #mown-link-status {
            position: fixed;
            bottom: 0;
            left: 0;
            max-width: 70%;
            padding: 1px 8px;
            font-size: 11px;
            line-height: 1.6;
            color: \(statusFG);
            background: \(statusBG);
            border-top: 1px solid \(statusBorder);
            border-right: 1px solid \(statusBorder);
            border-top-right-radius: 4px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            pointer-events: none;
            z-index: 2147483647;
            opacity: 0;
            transition: opacity 0.08s ease-out;
        }
        #mown-link-status.visible { opacity: 1; }
        </style>
        \(katexStyle)
        </head>
        <body class="markdown-body">
        \(bodyHTML)
        <script>\(hljsJS)</script>
        \(mermaidTag)
        \(katexTag)
        <script>
        (function () {
            // Give headings GitHub-style slug ids so in-page section links
            // (`[x](#my-heading)`) have a target to scroll to — cmark doesn't
            // emit these. Collisions get a numeric suffix (`-1`, `-2`, …),
            // matching GitHub so links authored for GitHub resolve here too.
            (function () {
                var counts = {};
                function slugify(text) {
                    return text.trim().toLowerCase()
                        .replace(/[^\\p{L}\\p{N}\\p{M}\\- ]+/gu, '')
                        .replace(/ +/g, '-');
                }
                document.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function (h) {
                    if (h.id) return;
                    var base = slugify(h.textContent || '');
                    if (!base) return;
                    var slug = base;
                    if (counts[base] == null) { counts[base] = 0; }
                    else { counts[base] += 1; slug = base + '-' + counts[base]; }
                    h.id = slug;
                });
            })();

            // A bare `#section` link scrolls within the page. Doing it here
            // (instead of relying on the native fragment jump) lets us animate
            // and gives one consistent code path. Every other link — sibling
            // Markdown files and external URLs — is left for the native
            // navigation delegate (see PreviewView), which routes them to a new
            // tab or the browser.
            document.addEventListener('click', function (e) {
                var a = e.target.closest ? e.target.closest('a[href]') : null;
                if (!a) return;
                var href = a.getAttribute('href') || '';
                if (href.charAt(0) !== '#') return;       // not an in-page link
                var id = decodeURIComponent(href.slice(1));
                var target = document.getElementById(id) || document.getElementsByName(id)[0];
                if (!target) return;
                e.preventDefault();
                target.scrollIntoView({ behavior: 'smooth', block: 'start' });
            });

            // Browser-style hover hint: show the link's href in a small status
            // bar at the bottom-left while the pointer is over it, and hide it
            // otherwise (including when the pointer leaves the window).
            (function () {
                var status = document.createElement('div');
                status.id = 'mown-link-status';
                document.body.appendChild(status);
                function show(text) {
                    status.textContent = text;
                    status.classList.add('visible');
                }
                function hide() {
                    status.classList.remove('visible');
                    status.textContent = '';
                }
                document.addEventListener('mouseover', function (e) {
                    var a = e.target.closest ? e.target.closest('a[href]') : null;
                    if (a) { show(a.getAttribute('href') || ''); } else { hide(); }
                });
                // Pointer left the document entirely (relatedTarget is null).
                document.addEventListener('mouseout', function (e) {
                    if (!e.relatedTarget) hide();
                });
            })();

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

            // Click a rendered diagram to pop it out at full size. Delegated off
            // the document so it works no matter when mermaid (async) finishes
            // injecting each <svg>.
            document.addEventListener('click', function (e) {
                var node = e.target.closest ? e.target.closest('.mermaid') : null;
                if (!node) return;
                var svg = node.querySelector('svg');
                if (!svg) return;
                try {
                    window.webkit.messageHandlers.\(MermaidZoom.messageName).postMessage(svg.outerHTML);
                } catch (_) {}
            });
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
