import Foundation
import cmark_gfm
import cmark_gfm_extensions

/// Bridges raw Markdown text into safe HTML via cmark-gfm.
///
/// Safety: we pass `CMARK_OPT_UNSAFE` so raw HTML (notably `<img>`) is emitted
/// verbatim, but the `tagfilter` extension neutralizes the high-risk tags
/// GFM blocks (`<script>`, `<iframe>`, `<style>`, `<noembed>`, `<noframes>`,
/// `<plaintext>`, `<title>`, `<textarea>`, `<xmp>`) by escaping their opening
/// brackets. This matches GitHub's own rendering behavior.
final class MarkdownRenderer {
    static let shared = MarkdownRenderer()

    /// GFM extensions enabled on every parse — covers §3.3 (tables, task lists,
    /// strikethrough, autolinks) plus `tagfilter` to neutralize dangerous tags.
    private static let extensionNames = [
        "table",
        "strikethrough",
        "tasklist",
        "autolink",
        "tagfilter",
    ]

    private init() {
        // Idempotent — safe to call once on first access.
        cmark_gfm_core_extensions_ensure_registered()
    }

    func renderHTML(_ markdown: String) -> String {
        // Lift TeX math out before cmark sees it (cmark would otherwise read the
        // underscores in `$a_b$` as emphasis); the tokens are swapped back for
        // KaTeX containers after rendering. A no-op when the doc has no math.
        let math = MathExtractor.extract(markdown)

        // UNSAFE lets <img> (and other raw HTML) through; tagfilter still
        // strips the dangerous tags. GITHUB_PRE_LANG emits <pre lang="...">
        // which highlight.js picks up via the language class.
        let options = CMARK_OPT_UNSAFE | CMARK_OPT_GITHUB_PRE_LANG | CMARK_OPT_VALIDATE_UTF8

        guard let parser = cmark_parser_new(options) else { return "" }
        defer { cmark_parser_free(parser) }

        for name in Self.extensionNames {
            if let ext = cmark_find_syntax_extension(name) {
                cmark_parser_attach_syntax_extension(parser, ext)
            }
        }

        math.markdown.withCString { ptr in
            cmark_parser_feed(parser, ptr, strlen(ptr))
        }

        guard let document = cmark_parser_finish(parser) else { return "" }
        defer { cmark_node_free(document) }

        let extensions = cmark_parser_get_syntax_extensions(parser)
        guard let cString = cmark_render_html(document, options, extensions) else {
            return ""
        }
        defer { free(cString) }
        return MathExtractor.reinsert(into: String(cString: cString), spans: math.spans)
    }
}
