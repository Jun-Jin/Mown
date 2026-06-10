<p align="center">
  <img src="Mown/Assets.xcassets/AppIcon.appiconset/icon_128x128.png" width="128" height="128" alt="Mown icon">
</p>

# Mown

A native macOS Markdown editor — fast, offline, zero telemetry. SwiftUI + `NSTextView` + `WKWebView`.

## Features

- **Three view modes** — Edit, Preview, Split. Toolbar control or rebindable keyboard shortcut.
- **Live preview** rendered through `WKWebView` using Apple's [`swift-cmark-gfm`](https://github.com/apple/swift-cmark). CommonMark + GitHub-flavored Markdown (tables, task lists, strikethrough, fenced code blocks).
- **Code highlighting** via highlight.js, **Mermaid diagrams** via mermaid.js — both bundled, no network calls.
- **TeX math** via KaTeX — inline `$…$`, display `$$…$$`, and ` ```math ` fences, typeset offline (fonts bundled). `$` inside code and currency like `$5` stay literal.
- **Light / dark themes** — independently configurable for the editor and the preview, with a "System" mode that follows macOS appearance.
- **Tabbed windows** — `⌘N` opens a new window, `⌘T` opens a new tab; opens from Finder / Recents join the current window as tabs.
- **`mown` CLI** — opens files from the terminal. Install in one click from Settings.
- Full document model from SwiftUI's `DocumentGroup`: New / Open / Save / Save As / Revert / Recent, autosave, versions, unsaved-changes indicator.

See [SPEC.md](./SPEC.md) for the full design doc.

## Install

### From a notarized DMG

Download the latest `Mown-<version>.dmg` from the [Releases](https://github.com/Jun-Jin/Mown/releases/latest) page, open it, and drag **Mown.app** to **Applications**. The DMG is Developer ID-signed and notarized, so Gatekeeper opens it without warning.

### Build from source

Requires Xcode 16 or newer (the project uses `objectVersion 77` synchronized folders).

```sh
git clone https://github.com/Jun-Jin/Mown.git
cd Mown
xcodebuild -scheme Mown -configuration Release CODE_SIGNING_ALLOWED=NO
```

The unsigned product lands in `~/Library/Developer/Xcode/DerivedData/Mown-*/Build/Products/Release/Mown.app`.

## CLI

Mown ships a `mown` command that opens Markdown files as tabs of the running window. To install it:

1. Drag **Mown.app** into `/Applications`.
2. Launch Mown, open **Settings ▸ Command Line ▸ Install**, and authenticate when macOS asks.

That symlinks the bundled script into `/usr/local/bin/mown` (on the default macOS PATH on both Intel and Apple Silicon). Usage:

```sh
mown                  # launch / focus Mown
mown notes.md         # open notes.md (created empty if it doesn't exist)
mown a.md b.md        # open several files as tabs
mown --help           # show usage
```

`MOWN_APP=/path/to/Mown.app mown …` overrides app resolution if you have multiple builds installed.

## Keyboard shortcuts

| Action                 | Default       |
|------------------------|---------------|
| New window             | `⌘N`          |
| New tab                | `⌘T`          |
| Open                   | `⌘O`          |
| Save / Save As         | `⌘S` / `⇧⌘S` |
| Edit / Preview / Split | `⌘1` / `⌘2` / `⌘3` (rebindable in Settings ▸ Shortcuts) |
| Toggle Full Screen     | `⌘↩`          |

## Releasing

`./.github/workflows/release.yml` builds, codesigns (Developer ID), notarizes, staples, and publishes a GitHub Release when you push a tag matching `v*`. The same pipeline runs locally via `bash .claude/skills/release/release.sh --dmg`.

Required repository secrets: 

- `DEVELOPER_ID_P12_BASE64`
- `P12_PASSWORD`
- `NOTARY_APPLE_ID`
- `NOTARY_TEAM_ID`
- `NOTARY_APP_PASSWORD`
