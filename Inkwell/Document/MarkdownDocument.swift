import SwiftUI
import UniformTypeIdentifiers

struct MarkdownDocument: FileDocument {
    var text: String

    init(text: String = "") {
        self.text = text
    }

    static var readableContentTypes: [UTType] {
        [.markdown, .plainText]
    }

    static var writableContentTypes: [UTType] {
        [.markdown, .plainText]
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    static let markdown = UTType(importedAs: "net.daringfireball.markdown")
}
