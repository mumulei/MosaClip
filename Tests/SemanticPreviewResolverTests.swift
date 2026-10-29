import Foundation
import Testing
@testable import PasteMemo

@Suite("Semantic preview routing")
struct SemanticPreviewResolverTests {
    @Test("Routes each proven semantic preview without changing source data")
    @MainActor
    func routesProvenKinds() throws {
        let markdownText = "# Release notes\n\n- Added preview\n- Kept raw copy"
        let markdown = ClipItem(content: markdownText, contentType: .text)
        guard case .markdown(.inline(_, let routedMarkdown))? =
            SemanticPreviewResolver.resolve(markdown)
        else {
            Issue.record("Expected Markdown routing")
            return
        }
        #expect(routedMarkdown == markdownText)
        #expect(markdown.content == markdownText)

        let svgText = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8\" height=\"8\"><path d=\"M0 0h8v8H0z\"/></svg>"
        let svg = ClipItem(content: svgText, contentType: .code, codeLanguage: CodeLanguage.svg.rawValue)
        guard case .svg(.inline(_, let routedSVG))? = SemanticPreviewResolver.resolve(svg) else {
            Issue.record("Expected SVG routing")
            return
        }
        #expect(routedSVG == svgText)
        #expect(svg.content == svgText)

        let colorText = "hsla(210, 50%, 40%, 0.5)"
        let color = ClipItem(content: colorText, contentType: .color)
        guard case .color(let routedColorText, let parsed)? =
            SemanticPreviewResolver.resolve(color)
        else {
            Issue.record("Expected Color routing")
            return
        }
        #expect(routedColorText == colorText)
        #expect(parsed.formatted(.hsla) == colorText)
        #expect(color.content == colorText)
    }

    @Test("SVG owns routing priority and ordinary text has no semantic preview")
    @MainActor
    func priorityAndFallback() {
        let svgText = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text># Heading</text></svg>"
        let svg = ClipItem(content: svgText, contentType: .code, codeLanguage: CodeLanguage.svg.rawValue)
        #expect({
            if case .svg? = SemanticPreviewResolver.resolve(svg) { return true }
            return false
        }())

        let prose = ClipItem(content: "An ordinary clipboard note.", contentType: .text)
        #expect(SemanticPreviewResolver.resolve(prose) == nil)
    }

    @Test("Malformed color data does not gain a semantic preview")
    @MainActor
    func malformedColorFallback() {
        let item = ClipItem(content: "rgb(999, 0, 0)", contentType: .color)
        #expect(SemanticPreviewResolver.resolve(item) == nil)
    }
}
