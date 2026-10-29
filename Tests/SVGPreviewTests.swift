import AppKit
import Foundation
import Testing
@testable import PasteMemo

@Suite("Safe SVG preview")
struct SVGPreviewTests {
    private let validSVG = """
    <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80">
      <defs>
        <linearGradient id="paint"><stop stop-color="#5B8CFF"/></linearGradient>
      </defs>
      <rect width="120" height="80" rx="16" fill="url(#paint)"/>
    </svg>
    """

    @Test("Complete SVG owns semantic detection before generic XML")
    @MainActor func detectionPriority() throws {
        #expect(SVGPreviewResolver.isInlineSVGSource(validSVG))
        let detected = ClipboardManager.shared.detectContentType(validSVG)
        #expect(detected.type == .code)
        #expect(detected.language == CodeLanguage.svg.rawValue)

        let item = ClipItem(
            content: validSVG,
            contentType: detected.type,
            codeLanguage: detected.language
        )
        guard case .inline(_, let resolvedText) = SVGPreviewResolver.source(for: item) else {
            Issue.record("Expected inline SVG preview source")
            return
        }
        #expect(resolvedText == validSVG)
    }

    @Test("Root detection accepts XML preambles and self-closing SVG")
    func rootForms() {
        let declared = "<?xml version=\"1.0\"?>\n<!-- icon -->\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"/>"
        #expect(SVGPreviewResolver.isInlineSVGSource(declared))
        #expect(SVGPreviewResolver.prepare(
            data: Data(declared.utf8),
            sourceText: declared
        ).failure == nil)
        #expect(!SVGPreviewResolver.isInlineSVGSource("<div><svg></svg></div>"))
        #expect(!SVGPreviewResolver.isInlineSVGSource("<svg><path/></svg> trailing"))
        #expect(!SVGPreviewResolver.isInlineSVGSource("<svg><path/>"))
    }

    @Test("Safe SVG validates metadata and native vector decoding")
    func validDocument() throws {
        let data = Data(validSVG.utf8)
        let document = SVGPreviewResolver.prepare(data: data, sourceText: validSVG)
        #expect(document.canRender)
        #expect(document.failure == nil)
        #expect(document.renderData == data)
        #expect(document.sourceText == validSVG)
        #expect(document.metadata.viewBox == "0 0 120 80")
        #expect(document.metadata.width == "120")
        #expect(document.metadata.height == "80")
        #expect(document.metadata.sourceByteCount == data.count)

        let nativeImage = try #require(NSImage(data: data))
        #expect(nativeImage.size.width > 0)
        #expect(nativeImage.size.height > 0)
    }

    @Test("Local fragment references remain renderable")
    func localReferences() {
        let source = """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
          <defs><path id="shape" d="M1 1h18v18H1z"/></defs>
          <use href="#shape" style="fill: url(#paint)"/>
        </svg>
        """
        let document = SVGPreviewResolver.prepare(data: Data(source.utf8), sourceText: source)
        #expect(document.failure == nil)
    }

    @Test("Scripts, event handlers, and external references are blocked", arguments: [
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\" onload=\"alert(1)\"></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><image href=\"https://example.com/a.png\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><use href=\"other.svg#shape\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><style>@import url(https://example.com/a.css)</style></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect style=\"fill:url(file:///tmp/a.svg)\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><rect style=\"fill:u\\72l(https://example.com/a.svg)\"/></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><style>u/**/rl(https://example.com/a.svg)</style></svg>",
        "<svg xmlns=\"http://www.w3.org/2000/svg\"><foreignObject><div>HTML</div></foreignObject></svg>",
    ])
    func unsafeContent(source: String) {
        let document = SVGPreviewResolver.prepare(data: Data(source.utf8), sourceText: source)
        #expect(document.failure == .unsafeContent)
        #expect(document.renderData == nil)
        #expect(document.sourceText == source)
    }

    @Test("DTD and entity declarations are rejected without resolution")
    func entityDeclarations() {
        let source = """
        <!DOCTYPE svg [<!ENTITY remote SYSTEM "https://example.com/payload">]>
        <svg xmlns="http://www.w3.org/2000/svg"><text>&remote;</text></svg>
        """
        #expect(SVGPreviewResolver.isInlineSVGSource(source))
        let document = SVGPreviewResolver.prepare(data: Data(source.utf8), sourceText: source)
        #expect(document.failure == .unsafeContent)
        #expect(document.renderData == nil)
    }

    @Test("Malformed XML keeps its raw fallback")
    func malformedXML() {
        let source = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path></svg>"
        #expect(SVGPreviewResolver.isInlineSVGSource(source))
        let document = SVGPreviewResolver.prepare(data: Data(source.utf8), sourceText: source)
        #expect(document.failure == .invalidXML)
        #expect(document.sourceText == source)
        #expect(document.renderData == nil)
    }

    @Test("Oversized and excessive path data fall back safely")
    func complexityBounds() {
        let oversized = "<svg><desc>" + String(repeating: "x", count: SVGPreviewResolver.maximumRenderableBytes) + "</desc></svg>"
        #expect(SVGPreviewResolver.isInlineSVGSource(oversized))
        let oversizedDocument = SVGPreviewResolver.prepare(
            data: Data(oversized.utf8),
            sourceText: oversized
        )
        #expect(oversizedDocument.failure == .tooLarge)
        #expect(oversizedDocument.sourceText == oversized)

        let path = String(
            repeating: "M0 0 ",
            count: SVGPreviewResolver.maximumPathDataCharacters / 5 + 1
        )
        let complex = "<svg xmlns=\"http://www.w3.org/2000/svg\"><path d=\"\(path)\"/></svg>"
        let complexDocument = SVGPreviewResolver.prepare(
            data: Data(complex.utf8),
            sourceText: complex
        )
        #expect(complexDocument.failure == .tooComplex)
        #expect(complexDocument.renderData == nil)
    }

    @Test("Unreasonable canvas dimensions are rejected")
    func dimensionBounds() {
        let source = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1000000000\" height=\"10\"></svg>"
        let document = SVGPreviewResolver.prepare(data: Data(source.utf8), sourceText: source)
        #expect(document.failure == .tooComplex)
    }

    @Test("SVG files use async bounded loading while retaining file identity")
    @MainActor func fileSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PasteMemo-SVGPreviewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("fixture.svg")
        try Data(validSVG.utf8).write(to: url, options: .atomic)
        let item = ClipItem(content: url.path, contentType: .image)

        let source = try #require(SVGPreviewResolver.source(for: item))
        guard case .file(_, let resolvedURL) = source else {
            Issue.record("Expected file SVG preview source")
            return
        }
        #expect(resolvedURL == url)
        #expect(item.content == url.path)

        let document = await SVGPreviewResolver.prepare(source)
        #expect(document.canRender)
        #expect(document.sourceText == validSVG)
        #expect(item.content == url.path)
    }
}
