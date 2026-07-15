import AppKit
import UniformTypeIdentifiers

/// Reloads the frontmost document window's file from disk — backs the ⌘R
/// "Refresh" command, for when another program has rewritten the file underneath
/// the open document (a formatter, a `git checkout`, a sync client, …).
///
/// SwiftUI's `DocumentGroup` exposes no API to re-read a file, so we bridge to
/// the backing `NSDocument` and drive its own revert path
/// (`revert(toContentsOf:ofType:)`). That re-runs the document's read, which
/// flows back through SwiftUI's binding to refresh the editor and preview, and —
/// unlike reassigning `document.text` — leaves the document *clean* (in sync with
/// disk) with a reset undo stack, which is what "reload from disk" should mean.
enum DocumentReload {
    /// Reverts the given window's document to the bytes now on disk. When the
    /// document has unsaved edits, confirms first, since a reload discards them.
    static func reload(window: NSWindow?) {
        guard let window,
              let document = document(for: window),
              let url = document.fileURL else { return }

        guard document.isDocumentEdited else {
            revert(document, url: url)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Reload “\(url.lastPathComponent)” from disk?"
        alert.informativeText = "This document has unsaved changes. Reloading replaces them with the version on disk."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reload")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { revert(document, url: url) }
        }
    }

    private static func revert(_ document: NSDocument, url: URL) {
        do {
            try document.revert(toContentsOf: url,
                                ofType: document.fileType ?? UTType.markdown.identifier)
        } catch {
            NSSound.beep()
        }
    }

    /// Finds the `NSDocument` backing a window. Mirrors the lookup in
    /// `DocumentEditedIndicator`: SwiftUI's window controller usually owns the
    /// document, but fall back to scanning the shared controller's documents.
    private static func document(for window: NSWindow) -> NSDocument? {
        if let doc = window.windowController?.document as? NSDocument { return doc }
        return NSDocumentController.shared.documents.first { doc in
            doc.windowControllers.contains { $0.window === window }
        }
    }
}
