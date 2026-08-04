import XCTest
@testable import Mown

final class MermaidDiagramExporterTests: XCTestCase {
    /// A stand-in for mermaid output: viewBox-sized SVG with the inline
    /// `style="max-width: …"` and `width="100%"` mermaid stamps on real
    /// diagrams.
    private let sampleSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 100" \
    style="max-width: 200px;" width="100%"><rect x="10" y="10" width="180" \
    height="80" fill="#4a90d9"/><text x="100" y="60" text-anchor="middle" \
    fill="white">hello</text></svg>
    """

    // MARK: Bitmap rendering (PNG / JPEG)

    func testBitmapRendersAtTwoTimesNaturalSizeAndEncodesBothFormats() {
        let done = expectation(description: "render")
        var rendered: NSBitmapImageRep?
        MermaidBitmapRenderer.render(svg: sampleSVG, isDark: false) { result in
            rendered = try? result.get()
            done.fulfill()
        }
        wait(for: [done], timeout: 15)

        let rep = try! XCTUnwrap(rendered, "renderer should produce a bitmap")
        // (200 + 16pt padding * 2) * 2x scale, and same for the 100pt height.
        XCTAssertEqual(rep.pixelsWide, 464)
        XCTAssertEqual(rep.pixelsHigh, 264)

        // Both bitmap formats must encode, and round-trip at the same size.
        for format in [MermaidExportFormat.png, .jpeg] {
            let encoding = try! XCTUnwrap(format.bitmapEncoding)
            let data = try! XCTUnwrap(rep.representation(using: encoding.type,
                                                         properties: encoding.properties),
                                      "\(format.displayName) should encode")
            let decoded = try! XCTUnwrap(NSBitmapImageRep(data: data),
                                         "\(format.displayName) should decode")
            XCTAssertEqual(decoded.pixelsWide, 464)
            XCTAssertEqual(decoded.pixelsHigh, 264)
        }
    }

    func testBitmapForSVGWithoutViewBox() {
        let done = expectation(description: "render")
        var rendered: NSBitmapImageRep?
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60"><circle cx="60" cy="30" r="25"/></svg>"#
        MermaidBitmapRenderer.render(svg: svg, isDark: true) { result in
            rendered = try? result.get()
            done.fulfill()
        }
        wait(for: [done], timeout: 15)

        let rep = try! XCTUnwrap(rendered)
        XCTAssertEqual(rep.pixelsWide, 304)   // (120 + 32) * 2
        XCTAssertEqual(rep.pixelsHigh, 184)   // (60 + 32) * 2
    }

    // MARK: Standalone SVG export

    func testStandaloneSVGPinsPixelSizeAndDropsPageSizing() {
        let out = MermaidDiagramExporter.standaloneSVG(sampleSVG, isDark: false)
        XCTAssertTrue(out.contains(#"width="200""#))
        XCTAssertTrue(out.contains(#"height="100""#))
        XCTAssertFalse(out.contains("max-width"), "page-only sizing must not survive")
        XCTAssertFalse(out.contains("100%"), "percent sizing must not survive")
    }

    func testStandaloneSVGInjectsThemeBackgroundBehindDrawing() {
        let dark = MermaidDiagramExporter.standaloneSVG(sampleSVG, isDark: true)
        XCTAssertTrue(dark.contains(##"<rect x="0" y="0" width="200" height="100" fill="#0d1117"/>"##))

        let light = MermaidDiagramExporter.standaloneSVG(sampleSVG, isDark: false)
        XCTAssertTrue(light.contains(##"fill="#ffffff""##))
        // The backdrop must sit before (i.e. paint behind) the diagram's own shapes.
        let backdrop = light.range(of: "#ffffff")!
        let shape = light.range(of: "#4a90d9")!
        XCTAssertLessThan(backdrop.lowerBound, shape.lowerBound)
    }

    func testStandaloneSVGAddsMissingXMLNS() {
        let bare = #"<svg viewBox="0 0 10 10"><rect width="10" height="10"/></svg>"#
        let out = MermaidDiagramExporter.standaloneSVG(bare, isDark: false)
        XCTAssertTrue(out.contains(#"xmlns="http://www.w3.org/2000/svg""#))
    }
}
