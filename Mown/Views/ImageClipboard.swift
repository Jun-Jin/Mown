import AppKit
import UniformTypeIdentifiers

/// Puts an image on the pasteboard in the forms apps actually paste: the
/// original encoded bytes under their own type (so a JPEG stays a JPEG and a
/// GIF keeps its frames), plus TIFF and PNG renditions for apps that only read
/// one of those. The pasteboard is injectable so tests don't clobber the
/// user's clipboard.
enum ImageClipboard {
    enum CopyError: LocalizedError {
        case undecodable
        case fetchFailed(String)
        var errorDescription: String? {
            switch self {
            case .undecodable: return "The data isn't an image macOS can decode."
            case .fetchFailed(let reason): return "The image couldn't be loaded. \(reason)"
            }
        }
    }

    /// Writes encoded image `data` (PNG, JPEG, GIF, SVG, …) to `pasteboard`.
    /// `type`, when known and an image type, labels the original bytes; TIFF
    /// and PNG renditions are added regardless.
    static func write(imageData data: Data, type: UTType?,
                      to pasteboard: NSPasteboard = .general) throws {
        guard let image = NSImage(data: data) else { throw CopyError.undecodable }
        pasteboard.clearContents()
        if let type, type.conforms(to: .image) {
            pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type.identifier))
        }
        writeRenditions(of: image, to: pasteboard)
    }

    /// Writes an already-rasterized bitmap (the Mermaid renderer's output).
    static func write(bitmap: NSBitmapImageRep, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        if let png = bitmap.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
        if let tiff = bitmap.tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
    }

    /// Adds TIFF and PNG renditions of `image` unless the pasteboard already
    /// carries that type (the original bytes).
    private static func writeRenditions(of image: NSImage, to pasteboard: NSPasteboard) {
        guard let tiff = image.tiffRepresentation else { return }
        let present = Set(pasteboard.types ?? [])
        if !present.contains(.tiff) { pasteboard.setData(tiff, forType: .tiff) }
        if !present.contains(.png),
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            pasteboard.setData(png, forType: .png)
        }
    }

    /// Loads the image at `url` — a local file (read directly) or anything
    /// else URLSession can fetch (http(s), data:) — and copies it. Calls
    /// `completion` on the main queue with the error, if any.
    static func copy(contentsOf url: URL, to pasteboard: NSPasteboard = .general,
                     completion: @escaping (Error?) -> Void) {
        if url.isFileURL {
            do {
                let data = try Data(contentsOf: url)
                try write(imageData: data, type: UTType(filenameExtension: url.pathExtension),
                          to: pasteboard)
                completion(nil)
            } catch {
                completion(error)
            }
            return
        }
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                guard let data, error == nil else {
                    completion(CopyError.fetchFailed(error?.localizedDescription ?? ""))
                    return
                }
                let type = response?.mimeType.flatMap { UTType(mimeType: $0) }
                    ?? UTType(filenameExtension: url.pathExtension)
                do {
                    try write(imageData: data, type: type, to: pasteboard)
                    completion(nil)
                } catch {
                    completion(error)
                }
            }
        }.resume()
    }
}

/// Shows `error` as a sheet on `window` (or app-modal without one).
func presentAlert(_ error: Error, title: String, in window: NSWindow?) {
    let alert = NSAlert(error: error)
    alert.messageText = title
    if let window { alert.beginSheetModal(for: window) } else { alert.runModal() }
}
