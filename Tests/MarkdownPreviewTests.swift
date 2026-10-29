import Foundation
import Testing
@testable import PasteMemo

@Suite("Markdown preview")
struct MarkdownPreviewTests {
    @Test("Manual Markdown language selection is always eligible")
    func manualMarkdownSelection() {
        #expect(MarkdownPreviewResolver.isMarkdownText(
            "malformed ** markdown [",
            contentType: .code,
            language: .markdown
        ))
    }

    @Test("Strong Markdown block signatures are eligible", arguments: [
        "# Heading",
        "## Heading",
        "> A quoted paragraph",
        "- first\n- second",
        "1. first\n2. second",
        "```swift\nprint(\"hello\")\n```",
        "| Name | Value |\n| --- | --- |\n| A | B |",
        "- [x] shipped",
    ])
    func strongSignatures(text: String) {
        #expect(MarkdownPreviewResolver.isMarkdownText(
            text,
            contentType: .text,
            language: nil
        ))
    }

    @Test("Inline Markdown needs combined evidence")
    func inlineMarkdownEvidence() {
        #expect(MarkdownPreviewResolver.isMarkdownText(
            "Read the **guide** at [PasteMemo](https://example.com).",
            contentType: .text,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "Use `git status` when needed.",
            contentType: .text,
            language: nil
        ))
    }

    @Test("Plain prose, colors, JSON, and known code stay on existing previews")
    func rejectsCollisions() {
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "This is a regular sentence without Markdown structure.",
            contentType: .text,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "#FFFFFF",
            contentType: .color,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "{\"heading\": \"# Value\"}",
            contentType: .text,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "#include <stdio.h>",
            contentType: .code,
            language: .c
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "这是一段没有 Markdown 结构的普通中文文本。",
            contentType: .text,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "https://example.com/path#heading",
            contentType: .text,
            language: nil
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "<document><title>Heading</title></document>",
            contentType: .code,
            language: .xml
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "struct Heading { let value = \"# text\" }",
            contentType: .code,
            language: .swift
        ))
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            "2026-08-22 INFO [worker] completed request #42",
            contentType: .text,
            language: nil
        ))
    }

    @Test("GFM structures and malformed input parse without changing the source")
    func rendererCoverage() async throws {
        let source = """
        # Heading

        - unordered
        - list

        1. ordered
        2. list

        > blockquote with `inline code`

        ```swift
        print("fenced code")
        ```

        | Name | Value |
        | --- | --- |
        | PasteMemo | Local |

        [Link](https://example.com)
        """
        let rendered = try await MarkdownRendererAdapter.prepare(markdown: source)
        let plainText = rendered.plainText

        #expect(plainText.contains("Heading"))
        #expect(plainText.contains("unordered"))
        #expect(plainText.contains("ordered"))
        #expect(plainText.contains("blockquote"))
        #expect(plainText.contains("inline code"))
        #expect(plainText.contains("fenced code"))
        #expect(plainText.contains("PasteMemo"))
        #expect(plainText.contains("Link"))
        #expect(source.contains("```swift"), "Renderer preparation must not mutate raw Markdown")

        let malformed = "# Unclosed [link](https://example.com and **strong"
        let malformedResult = try await MarkdownRendererAdapter.prepare(markdown: malformed)
        #expect(!malformedResult.plainText.isEmpty)
    }

    @Test("Large Markdown is guarded before parsing")
    func largeMarkdownGuard() async {
        let huge = String(repeating: "- a large list item\n", count: 4_000)
        #expect(!MarkdownPreviewResolver.canRender(huge))

        let withinByteLimitButLineDense = String(
            repeating: "- x\n",
            count: MarkdownPreviewResolver.maximumRenderedLineCount
        )
        #expect(withinByteLimitButLineDense.utf8.count < MarkdownPreviewResolver.maximumRenderedUTF8Bytes)
        #expect(!MarkdownPreviewResolver.canRender(withinByteLimitButLineDense))
        #expect(MarkdownPreviewResolver.canRenderManually(withinByteLimitButLineDense))
        #expect(MarkdownPreviewResolver.renderPolicy(for: withinByteLimitButLineDense) == .onDemand)

        let lastRenderableLineCount = String(
            repeating: "- x\n",
            count: MarkdownPreviewResolver.maximumRenderedLineCount - 1
        )
        #expect(MarkdownPreviewResolver.canRender(lastRenderableLineCount))

        let beyondManualLimit = String(
            repeating: "- x\n",
            count: MarkdownPreviewResolver.maximumManualRenderedLineCount
        )
        #expect(!MarkdownPreviewResolver.canRenderManually(beyondManualLimit))
        #expect(MarkdownPreviewResolver.renderPolicy(for: beyondManualLimit) == .unavailable)

        let manuallyRendered = try? await MarkdownRendererAdapter.prepare(
            markdown: withinByteLimitButLineDense,
            allowingRiskyContent: true
        )
        #expect(manuallyRendered?.plainText.contains("x") == true)

        do {
            _ = try await MarkdownRendererAdapter.prepare(markdown: huge)
            Issue.record("Oversized Markdown should not enter the renderer")
        } catch let error as MarkdownPreviewLoadError {
            #expect(error == .fileTooLarge)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Automatic eligibility work is bounded, while manual Markdown remains available")
    func eligibilityLimit() {
        let huge = "# Heading\n" + String(
            repeating: "ordinary unstructured text ",
            count: MarkdownPreviewResolver.maximumEligibilityUTF8Bytes
        )
        #expect(!MarkdownPreviewResolver.isMarkdownText(
            huge,
            contentType: .text,
            language: nil
        ))
        #expect(MarkdownPreviewResolver.isMarkdownText(
            huge,
            contentType: .code,
            language: .markdown
        ))
    }

    @Test("Remote assets never load and links require an allowed user action")
    func remoteContentPolicy() {
        #expect(!MarkdownRemoteContentPolicy.shouldLoadImage(
            at: URL(string: "https://example.com/tracker.png")
        ))
        #expect(MarkdownRemoteContentPolicy.canOpenAfterUserAction(
            URL(string: "https://example.com")!
        ))
        #expect(MarkdownRemoteContentPolicy.canOpenAfterUserAction(
            URL(string: "mailto:test@example.com")!
        ))
        #expect(!MarkdownRemoteContentPolicy.canOpenAfterUserAction(
            URL(string: "file:///tmp/private")!
        ))
        #expect(!MarkdownRemoteContentPolicy.canOpenAfterUserAction(
            URL(string: "javascript:alert(1)")!
        ))
    }

    @Test("OCR Markdown uses the same renderer and preserves raw text")
    func ocrMarkdownInput() async throws {
        let ocrText = "## Receipt\n\n| Item | Price |\n| --- | --- |\n| Tea | 12 |"
        let rendered = try await MarkdownRendererAdapter.prepare(markdown: ocrText)
        #expect(rendered.plainText.contains("Receipt"))
        #expect(rendered.plainText.contains("Tea"))
        #expect(ocrText.hasPrefix("## Receipt"))
    }

    @Test("Preview preparation never mutates the stored clipboard source")
    @MainActor
    func previewPreparationPreservesClipItem() async throws {
        let raw = "## Original\n\n- Alpha\n- Beta"
        let item = ClipItem(
            content: raw,
            contentType: .code,
            codeLanguage: CodeLanguage.markdown.rawValue
        )

        guard let source = MarkdownPreviewResolver.source(for: item) else {
            Issue.record("Explicit Markdown item did not resolve")
            return
        }
        let loaded = try await MarkdownRendererAdapter.loadText(from: source)
        _ = try await MarkdownRendererAdapter.prepare(markdown: loaded)

        #expect(item.content == raw)
        #expect(item.contentType == .code)
        #expect(item.codeLanguage == CodeLanguage.markdown.rawValue)
    }

    @Test("Only the newest preview request may publish")
    func rapidItemSwitchingGuard() {
        var guardState = MarkdownPreviewRequestGuard()
        let first = guardState.begin()
        let second = guardState.begin()
        #expect(!guardState.accepts(first))
        #expect(guardState.accepts(second))
    }

    @Test("Readable Markdown files are preview sources without changing file semantics")
    func markdownFileEligibility() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastememo-markdown-\(UUID().uuidString).md")
        try Data("# Local file".utf8).write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(MarkdownPreviewResolver.markdownFileURL(
            content: url.path,
            contentType: .document
        ) == url)
        #expect(MarkdownPreviewResolver.markdownFileURL(
            content: url.path,
            contentType: .text
        ) == nil)
        #expect(MarkdownPreviewResolver.markdownFileURL(
            content: url.deletingLastPathComponent()
                .appendingPathComponent("missing.md").path,
            contentType: .document
        ) == nil)
    }

    @Test("Both Markdown file extensions resolve")
    func markdownFileExtensions() throws {
        for fileExtension in ["md", "markdown"] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("pastememo-markdown-\(UUID().uuidString).\(fileExtension)")
            try Data("## Local file".utf8).write(to: url, options: .atomic)
            defer { try? FileManager.default.removeItem(at: url) }

            #expect(MarkdownPreviewResolver.markdownFileURL(
                content: url.path,
                contentType: .document
            ) == url)
        }
    }

    @Test("Invalid UTF-8 and oversized Markdown files fail into the file fallback path")
    func markdownFileLoadFailures() async throws {
        let invalidURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastememo-invalid-\(UUID().uuidString).md")
        try Data([0xFF, 0xFE, 0xFD]).write(to: invalidURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: invalidURL) }

        do {
            _ = try await MarkdownRendererAdapter.loadText(
                from: .file(id: "invalid", url: invalidURL)
            )
            Issue.record("Invalid UTF-8 must not be rendered with replacement characters")
        } catch let error as MarkdownPreviewLoadError {
            #expect(error == .invalidEncoding)
        } catch {
            Issue.record("Unexpected invalid UTF-8 error: \(error)")
        }

        let oversizedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pastememo-oversized-\(UUID().uuidString).md")
        try Data().write(to: oversizedURL, options: .atomic)
        let handle = try FileHandle(forWritingTo: oversizedURL)
        defer {
            try? handle.close()
            try? FileManager.default.removeItem(at: oversizedURL)
        }
        try handle.truncate(atOffset: UInt64(MarkdownPreviewResolver.maximumLoadedFileBytes + 1))

        do {
            _ = try await MarkdownRendererAdapter.loadText(
                from: .file(id: "oversized", url: oversizedURL)
            )
            Issue.record("Oversized files must skip Markdown loading")
        } catch let error as MarkdownPreviewLoadError {
            #expect(error == .fileTooLarge)
        } catch {
            Issue.record("Unexpected oversized file error: \(error)")
        }
    }
}
