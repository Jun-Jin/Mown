# Inkwell — Specification

> Working title — final name TBD.

A standalone, native macOS Markdown editor written in Swift + SwiftUI.

## 1. Goals

- A lightweight, truly native Mac app for editing Markdown files.
- Fast toggle between **Edit** and **Preview**.
- Fully offline — no accounts, no cloud sync, no telemetry.
- Distributed as a single `.app` bundle.

## 2. Non-Goals

- Cloud sync / collaboration / multi-user editing.
- Plugin system or extension marketplace.
- WYSIWYG editing (we keep raw text + rendered preview).
- iOS / iPadOS / non-Apple platforms.

## 3. Must-Have Features (MVP)

### 3.1 Markdown Editing
- Plain-text editor area with monospace font.
- Full native text editing inherited from `NSTextView`: cursor movement, selection, copy / cut / paste, undo / redo, IME, spell check, services menu, accessibility.
- UTF-8 file encoding.
- Soft-wrap long lines.

### 3.2 View Modes
The window has a segmented control that switches between three modes:

| Mode      | Description                                        |
|-----------|----------------------------------------------------|
| `Edit`    | Editor only (full width).                          |
| `Preview` | Rendered HTML preview only (full width).           |
| `Split`   | Editor on the left, live preview on the right.     |

- Toggle via toolbar control **and** keyboard shortcut (`⌘E` cycles).
- Preview updates live as the user types (debounced ~150 ms).

### 3.3 Markdown Rendering
- CommonMark + GitHub Flavored Markdown (tables, task lists, strikethrough, fenced code blocks).
- Syntax highlighting inside fenced code blocks (common languages).
- Safe HTML rendering — raw HTML in the input is sanitized.

### 3.4 File Operations
Driven by SwiftUI's `DocumentGroup`, which gives us for free:
- **New / Open / Save / Save As / Duplicate / Revert / Recent Files**.
- Native open / save panels.
- Window title shows the file name; an unsaved-changes indicator appears in the close button.
- Standard "do you want to save?" dialog on close.
- Auto-save & versions via the document architecture.

Supported file types: `.md`, `.markdown`, `.txt`.

### 3.5 Recent Files
- **File → Open Recent** submenu lists the most recently opened documents.
- Selecting an entry reopens that file in a new (or focused existing) window.
- **Clear Menu** item at the bottom of the submenu empties the list.
- List is persisted across app launches by `NSDocumentController` (provided automatically by `DocumentGroup`).
- Default capacity follows the system setting (System Settings → Desktop & Dock → Recent items); no custom UI to configure it for MVP.
- Entries pointing to moved / deleted files are dimmed and removed on next launch (standard AppKit behavior).

### 3.6 GUI Shell
- Standard Mac menu bar: **File / Edit / View / Window / Help** with the usual items.
- Toolbar with: view-mode segmented control, theme button (optional).
- Light / dark theme follows the system appearance.
- Sidebar with document outline (headings) — *post-MVP, see §4*.

## 4. Nice-to-Have (Post-MVP)

- Drag & drop a file onto the dock icon / window to open it.
- Document outline panel (headings → click to jump).
- Word / character / reading-time count in the status bar.
- Export to HTML / PDF (Print → Save as PDF works for free).
- Find & replace inside the editor (`NSTextFinder`).
- Markdown-aware syntax highlighting *in the editor* (bold, headings, code) using `NSTextStorage` delegates.
- Vim-style key bindings.

## 5. Tech Stack

| Concern             | Choice                                                                 |
|---------------------|------------------------------------------------------------------------|
| Language            | Swift 5.9+                                                             |
| Min deployment      | macOS 13 (Ventura) — gives us modern SwiftUI APIs                      |
| App shell           | SwiftUI (`App`, `DocumentGroup`, `Scene`)                              |
| Editor widget       | `NSTextView` wrapped in `NSViewRepresentable` (better than `TextEditor` for control over undo, attributes, find-bar) |
| Preview widget      | `WKWebView` wrapped in `NSViewRepresentable`                           |
| Markdown parser     | [`swift-cmark-gfm`](https://github.com/apple/swift-cmark) (Apple's fork of cmark with GFM extensions) via SwiftPM |
| Syntax highlighting | [`highlight.js`](https://highlightjs.org/) bundled into the preview HTML (simple, zero Swift deps) |
| HTML sanitization   | cmark-gfm's `--unsafe=false` mode (default); raw HTML is escaped       |
| Build system        | Xcode project (SwiftPM dependencies)                                   |

Rationale: `DocumentGroup` eliminates almost all of the file-handling code. `NSTextView` over `TextEditor` because we need find-bar, custom undo grouping, and future syntax highlighting. `WKWebView` for preview because it gives us free CSS theming, code highlighting via JS, and looks identical to how the doc would render on GitHub.

## 6. Architecture (high level)

```
┌────────────────────────────────────────────────────────────┐
│  InkwellApp  (@main, DocumentGroup<MarkdownDocument>)      │
│                                                            │
│  ┌────────────────────────────────────────────────────┐   │
│  │  ContentView                                       │   │
│  │  ┌──────────────┐   ┌────────────────────────────┐ │   │
│  │  │ Toolbar      │   │ Layout (Edit/Preview/Split)│ │   │
│  │  │  - viewMode  │   │  ┌────────┐  ┌──────────┐  │ │   │
│  │  └──────────────┘   │  │Editor  │  │Preview   │  │ │   │
│  │                     │  │View    │->│View      │  │ │   │
│  │                     │  │(NSText)│  │(WKWebView│  │ │   │
│  │                     │  └────────┘  └──────────┘  │ │   │
│  │                     └────────────────────────────┘ │   │
│  └────────────────────────────────────────────────────┘   │
│                                                            │
│  MarkdownDocument : FileDocument                           │
│   - text: String                                           │
│   - read(from:) / fileWrapper(configuration:)              │
│                                                            │
│  MarkdownRenderer                                          │
│   - render(_ markdown: String) -> String (HTML)            │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

### Project layout

```
Inkwell/
├── Inkwell.xcodeproj
├── Inkwell/
│   ├── InkwellApp.swift              // @main
│   ├── Document/
│   │   └── MarkdownDocument.swift    // FileDocument
│   ├── Views/
│   │   ├── ContentView.swift         // Toolbar + layout
│   │   ├── EditorView.swift          // NSTextView wrapper
│   │   ├── PreviewView.swift         // WKWebView wrapper
│   │   └── ViewMode.swift            // enum + segmented control
│   ├── Rendering/
│   │   ├── MarkdownRenderer.swift    // cmark-gfm bridge
│   │   └── PreviewTemplate.swift     // HTML shell + CSS injection
│   └── Resources/
│       ├── preview.css               // GitHub-like styling
│       ├── preview-dark.css
│       └── highlight.min.js          // + a default theme
└── Tests/
    └── MarkdownRendererTests.swift
```

## 7. Keyboard Shortcuts

| Action               | Shortcut       |
|----------------------|----------------|
| New                  | ⌘N             |
| Open                 | ⌘O             |
| Save                 | ⌘S             |
| Save As / Duplicate  | ⇧⌘S            |
| Cycle view mode      | ⌘E             |
| Find                 | ⌘F             |
| Close window         | ⌘W             |
| Quit                 | ⌘Q             |

Most of these are provided automatically by `DocumentGroup` + the standard Edit menu.

## 8. Build & Distribution

- Develop in Xcode; `⌘R` to run.
- `xcodebuild -scheme Inkwell -configuration Release` for archive.
- MVP: unsigned `.app` for personal use.
- Post-MVP: Developer ID signing + notarization for distribution outside the App Store.
- App Store submission is **not** in scope for MVP.

## 9. Milestones

1. **M0 — Skeleton**: Xcode project, `DocumentGroup` opens an empty editable window.
2. **M1 — Editor**: `NSTextView`-backed editor with proper undo, monospace font, soft-wrap.
3. **M2 — Preview**: `WKWebView` renders cmark-gfm HTML with CSS theming.
4. **M3 — View toggle**: Edit / Preview / Split modes + `⌘E` shortcut + debounced live update.
5. **M4 — Polish**: code-block syntax highlighting (highlight.js), dark-mode CSS, toolbar icons, About window.
6. **M5 — Packaging**: release build, optional Developer ID signing notes.

## 10. Out of Scope (explicit)

- iCloud / Dropbox / any cloud storage integration.
- Real-time collaboration.
- iOS / iPadOS / Catalyst.
- Plugin / extension API.
