# Changelog

All notable changes to Mown are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
uses [semantic versioning](https://semver.org/).

## [0.5.5] - 2026-08-04

### Added
- **Export Mermaid diagrams as PNG, SVG, or JPEG.** Right-click a rendered
  diagram — in the preview or its full-size window — and choose **Export
  Diagram As…**; the save panel's standard Format popup picks the type (`⌘S`
  also works in the diagram window). PNG and JPEG export at 2× resolution on
  the preview's theme background; SVG stays vector, written to stand alone
  with explicit pixel size and a theme background.

## [0.5.4] - 2026-07-15

### Added
- **Reload from disk (`⌘R`)** — re-read the open file when another program (a
  formatter, `git checkout`, a sync client) has rewritten it underneath you.
  Reloads silently when the document is unchanged; prompts first when you have
  unsaved edits. Disabled for untitled documents.

### Changed
- **Preview now fills the full window width.** The rendered document was capped
  at 980px, leaving wide windows with large empty gutters; it now spans the
  preview width (padding still keeps text off the edges), in preview mode and
  the split-mode preview pane.

### Fixed
- **Preview keeps its scroll position across app switches.** Returning to Mown
  from another app no longer snaps the preview back to the top.

[0.5.5]: https://github.com/Jun-Jin/Mown/releases/tag/v0.5.5
[0.5.4]: https://github.com/Jun-Jin/Mown/releases/tag/v0.5.4
