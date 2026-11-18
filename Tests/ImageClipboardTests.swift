import XCTest
import UniformTypeIdentifiers
@testable import Mown

final class ImageClipboardTests: XCTestCase {
    /// A private pasteboard so the tests never touch the user's clipboard.
    private let pasteboard = NSPasteboard(name: NSPasteboard.Name("MownImageClipboardTests"))

    override func tearDown() {
        pasteboard.releaseGlobally()
        super.tearDown()
    }

    /// 4×3 solid-red PNG.
    private func samplePNG() -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 3,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 3).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testWritesOriginalBytesPlusTIFFAndPNG() throws {
        let jpeg = NSBitmapImageRep(data: samplePNG())!.representation(using: .jpeg, properties: [:])!
        try ImageClipboard.write(imageData: jpeg, type: .jpeg, to: pasteboard)

        let types = Set(pasteboard.types ?? [])
        XCTAssertTrue(types.contains(NSPasteboard.PasteboardType(UTType.jpeg.identifier)))
        XCTAssertTrue(types.contains(.tiff))
        XCTAssertTrue(types.contains(.png))
        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType(UTType.jpeg.identifier)), jpeg)
        let png = try XCTUnwrap(pasteboard.data(forType: .png))
        XCTAssertEqual(NSBitmapImageRep(data: png)?.pixelsWide, 4)
    }

    func testNonImageDataIsRejected() {
        XCTAssertThrowsError(try ImageClipboard.write(imageData: Data("not an image".utf8),
                                                      type: .plainText, to: pasteboard))
        XCTAssertNil(pasteboard.types?.first { $0 == .tiff })
    }

    func testWritesBitmapAsPNGAndTIFF() {
        ImageClipboard.write(bitmap: NSBitmapImageRep(data: samplePNG())!, to: pasteboard)
        XCTAssertNotNil(pasteboard.data(forType: .png))
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testCopiesFromLocalFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mown-clipboard-\(UUID().uuidString).png")
        try samplePNG().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let done = expectation(description: "copy")
        var copyError: Error?
        ImageClipboard.copy(contentsOf: url, to: pasteboard) { copyError = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertNil(copyError)
        XCTAssertEqual(pasteboard.data(forType: .png), samplePNG())
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    func testCopiesFromDataURL() throws {
        let url = URL(string: "data:image/png;base64," + samplePNG().base64EncodedString())!
        let done = expectation(description: "copy")
        var copyError: Error?
        ImageClipboard.copy(contentsOf: url, to: pasteboard) { copyError = $0; done.fulfill() }
        wait(for: [done], timeout: 5)

        XCTAssertNil(copyError)
        XCTAssertNotNil(pasteboard.data(forType: .tiff))
    }

    // MARK: Context-menu message decoding

    func testContextMenuTargetDecoding() {
        XCTAssertEqual(PreviewContextMenu.target(from: ["kind": "diagram", "svg": "<svg/>"]),
                       .diagram(svg: "<svg/>"))
        XCTAssertEqual(PreviewContextMenu.target(from: ["kind": "image", "src": "mownres://doc/a.png"]),
                       .image(URL(string: "mownres://doc/a.png")!))
        XCTAssertNil(PreviewContextMenu.target(from: ["kind": "diagram", "svg": ""]))
        XCTAssertNil(PreviewContextMenu.target(from: [String: Any]()))
        XCTAssertNil(PreviewContextMenu.target(from: "legacy string body"))
    }

    func testDocSchemeResolvesUnderDocumentDirectoryOnly() {
        let handler = PreviewSchemeHandler()
        let dir = URL(fileURLWithPath: "/tmp/mown-doc", isDirectory: true)
        handler.docDirectory = dir
        XCTAssertEqual(handler.fileURL(forDocURL: URL(string: "mownres://doc/pics/a.png")!)?.path,
                       "/tmp/mown-doc/pics/a.png")
        XCTAssertNil(handler.fileURL(forDocURL: URL(string: "mownres://doc/../secret.png")!))
        XCTAssertNil(handler.fileURL(forDocURL: URL(string: "mownres://res/mermaid.min.js")!))
        handler.docDirectory = nil
        XCTAssertNil(handler.fileURL(forDocURL: URL(string: "mownres://doc/a.png")!))
    }
}
