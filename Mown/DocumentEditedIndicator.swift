import AppKit
import Combine

/// Observable unsaved-changes flag for one document window, surfaced to SwiftUI
/// so the editor can show a live "Unsaved" badge.
final class DocumentEditState: ObservableObject {
    @Published var isEdited = false
}

/// Tracks a document window's unsaved state and publishes it two ways: the
/// native close-button dot (`window.isDocumentEdited`) and a `DocumentEditState`
/// the SwiftUI editor renders as a badge.
///
/// SwiftUI's `DocumentGroup` never sets `window.isDocumentEdited`, and the
/// backing `NSDocument.isDocumentEdited` isn't KVO-compliant (its value updates
/// on edit/save but posts no notification). So we refresh on every text change
/// (instant while typing) and poll as a safety net (catches save, which has no
/// observable event).
final class DocumentEditedIndicator: NSObject {
    private weak var window: NSWindow?
    private weak var document: NSDocument?
    private var editState: DocumentEditState?
    private var timer: Timer?
    private var textObserver: NSObjectProtocol?

    func attach(to window: NSWindow, editState: DocumentEditState) {
        self.window = window
        self.editState = editState
        bindDocument(attempt: 0)

        textObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.sync() }

        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] t in
            guard let self, self.window != nil else { t.invalidate(); return }
            self.sync()
        }
    }

    deinit {
        timer?.invalidate()
        if let textObserver { NotificationCenter.default.removeObserver(textObserver) }
    }

    private func sync() {
        guard let window, let document else { return }
        let edited = document.isDocumentEdited
        if window.isDocumentEdited != edited { window.isDocumentEdited = edited }
        if editState?.isEdited != edited { editState?.isEdited = edited }
    }

    private func bindDocument(attempt: Int) {
        guard let window else { return }
        if let doc = Self.document(for: window) {
            document = doc
            sync()
        } else if attempt < 10 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.bindDocument(attempt: attempt + 1)
            }
        }
    }

    private static func document(for window: NSWindow) -> NSDocument? {
        if let doc = window.windowController?.document as? NSDocument { return doc }
        return NSDocumentController.shared.documents.first { doc in
            doc.windowControllers.contains { $0.window === window }
        }
    }
}
