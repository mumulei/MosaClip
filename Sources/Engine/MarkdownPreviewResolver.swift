import Foundation

/// The source used by the Markdown preview layer. This remains a presentation-only
/// value: clipboard text and file paths continue to be stored and copied unchanged.
enum MarkdownPreviewSource: Equatable, Sendable {
    case inline(id: String, text: String)
    case file(id: String, url: URL)

    var id: String {
        switch self {
        case .inline(let id, _), .file(let id, _): id
        }
    }
}

/// Conservatively decides whether an existing clip should receive a Markdown preview.
/// It deliberately does not create a new persisted content type or run in capture code.
enum MarkdownPreviewResolver {
    static let maximumEligibilityUTF8Bytes = 128 * 1024
    static let maximumRenderedUTF8Bytes = 64 * 1024
    /// SwiftUI layout cost tracks block/line count as well as byte count. Very
    /// line-dense documents stay available in Raw mode instead of building
    /// thousands of MarkdownUI nodes on the main thread.
    static let maximumRenderedLineCount = 800
    /// A user may explicitly render content beyond the automatic safety budget.
    /// Keep a separate absolute ceiling so an accidental multi-megabyte document
    /// still cannot lock the main window indefinitely.
    static let maximumManualRenderedUTF8Bytes = 512 * 1024
    static let maximumManualRenderedLineCount = 10_000
    static let maximumLoadedFileBytes = 8 * 1024 * 1024

    enum RenderPolicy: Equatable, Sendable {
        case automatic
        case onDemand
        case unavailable
    }

    @MainActor
    static func source(for item: ClipItem) -> MarkdownPreviewSource? {
        if isMarkdownText(
            item.content,
            contentType: item.contentType,
            language: item.resolvedCodeLanguage
        ) {
            return .inline(
                id: "\(item.itemID):\(item.content.hashValue)",
                text: item.content
            )
        }

        guard let url = markdownFileURL(
            content: item.content,
            contentType: item.contentType
        ) else {
            return nil
        }

        return .file(id: "\(item.itemID):\(url.path)", url: url)
    }

    static func isMarkdownText(
        _ text: String,
        contentType: ClipContentType,
        language: CodeLanguage?
    ) -> Bool {
        if language == .markdown {
            return contentType == .code || contentType == .text
        }

        guard language == nil else { return false }
        guard contentType == .text || contentType == .code else { return false }
        guard text.utf8.prefix(maximumEligibilityUTF8Bytes + 1).count
            <= maximumEligibilityUTF8Bytes else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isColorLiteral(trimmed), !isJSON(trimmed) else { return false }

        let lines = trimmed.components(separatedBy: .newlines)
        let nonEmptyLines = lines.map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }

        let fencedLines = nonEmptyLines.filter {
            $0.hasPrefix("```") || $0.hasPrefix("~~~")
        }.count
        if fencedLines >= 2 { return true }

        if nonEmptyLines.contains(where: isATXHeading) { return true }
        if nonEmptyLines.contains(where: isBlockquote) { return true }
        if hasMarkdownTable(lines) { return true }

        let unorderedCount = nonEmptyLines.filter(isUnorderedListItem).count
        let orderedCount = nonEmptyLines.filter(isOrderedListItem).count
        if unorderedCount >= 2 || orderedCount >= 2 { return true }

        let hasTaskList = nonEmptyLines.contains {
            let lower = $0.lowercased()
            return lower.hasPrefix("- [ ] ") || lower.hasPrefix("- [x] ")
                || lower.hasPrefix("* [ ] ") || lower.hasPrefix("* [x] ")
        }
        if hasTaskList { return true }

        var inlineScore = 0
        if trimmed.range(
            of: #"\[[^\]\n]+\]\([^)\n]+\)"#,
            options: .regularExpression
        ) != nil {
            inlineScore += 2
        }
        if trimmed.range(of: #"`[^`\n]+`"#, options: .regularExpression) != nil {
            inlineScore += 1
        }
        if trimmed.range(
            of: #"(\*\*|__)[^\n]+(\*\*|__)"#,
            options: .regularExpression
        ) != nil {
            inlineScore += 1
        }
        if nonEmptyLines.contains(where: isThematicBreak) {
            inlineScore += 2
        }
        return inlineScore >= 3
    }

    static func markdownFileURL(
        content: String,
        contentType: ClipContentType
    ) -> URL? {
        guard contentType.isFileBased, !content.contains("\n") else { return nil }
        let path = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "md" || fileExtension == "markdown" else { return nil }
        guard FileManager.default.isReadableFile(atPath: url.path) else { return nil }
        return url
    }

    static func canRender(_ text: String) -> Bool {
        renderPolicy(for: text) == .automatic
    }

    static func canRenderManually(_ text: String) -> Bool {
        renderPolicy(for: text) != .unavailable
    }

    static func renderPolicy(for text: String) -> RenderPolicy {
        if isWithinRenderLimits(
            text,
            maximumUTF8Bytes: maximumRenderedUTF8Bytes,
            maximumLineCount: maximumRenderedLineCount
        ) {
            return .automatic
        }
        if isWithinRenderLimits(
            text,
            maximumUTF8Bytes: maximumManualRenderedUTF8Bytes,
            maximumLineCount: maximumManualRenderedLineCount
        ) {
            return .onDemand
        }
        return .unavailable
    }

    private static func isWithinRenderLimits(
        _ text: String,
        maximumUTF8Bytes: Int,
        maximumLineCount: Int
    ) -> Bool {
        let bytes = text.utf8
        guard bytes.prefix(maximumUTF8Bytes + 1).count <= maximumUTF8Bytes else {
            return false
        }

        var lineCount = 1
        var previousWasCarriageReturn = false
        for byte in bytes {
            if byte == 0x0D {
                lineCount += 1
                previousWasCarriageReturn = true
            } else if byte == 0x0A {
                if !previousWasCarriageReturn { lineCount += 1 }
                previousWasCarriageReturn = false
            } else {
                previousWasCarriageReturn = false
            }
            if lineCount > maximumLineCount { return false }
        }
        return true
    }

    private static func isATXHeading(_ line: String) -> Bool {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.count > hashes else { return false }
        let next = line.index(line.startIndex, offsetBy: hashes)
        return line[next].isWhitespace
    }

    private static func isBlockquote(_ line: String) -> Bool {
        line.hasPrefix("> ") && line.count > 2
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        guard line.count > 2 else { return false }
        return line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        guard let markerIndex = line.firstIndex(where: { $0 == "." || $0 == ")" }) else {
            return false
        }
        let marker = line[..<markerIndex]
        guard !marker.isEmpty, marker.allSatisfy(\.isNumber) else { return false }
        let contentIndex = line.index(after: markerIndex)
        guard contentIndex < line.endIndex else { return false }
        return line[contentIndex].isWhitespace
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let marker = compact.first else { return false }
        guard marker == "-" || marker == "*" || marker == "_" else { return false }
        return compact.allSatisfy { $0 == marker }
    }

    private static func hasMarkdownTable(_ lines: [String]) -> Bool {
        guard lines.count >= 2 else { return false }
        for index in 1..<lines.count {
            let header = lines[index - 1].trimmingCharacters(in: .whitespaces)
            let divider = lines[index].trimmingCharacters(in: .whitespaces)
            guard header.contains("|") else { continue }

            let cells = divider.split(separator: "|", omittingEmptySubsequences: true)
            guard cells.count >= 2 else { continue }
            if cells.allSatisfy({ cell in
                let value = cell.trimmingCharacters(in: .whitespaces)
                let dashes = value.filter { $0 == "-" }.count
                return dashes >= 3 && value.allSatisfy {
                    $0 == "-" || $0 == ":" || $0.isWhitespace
                }
            }) {
                return true
            }
        }
        return false
    }

    private static func isColorLiteral(_ text: String) -> Bool {
        ColorConverter.parse(text) != nil
    }

    private static func isJSON(_ text: String) -> Bool {
        guard text.first == "{" || text.first == "[" else { return false }
        guard let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}

/// Explicit security policy shared by the renderer and unit tests.
enum MarkdownRemoteContentPolicy {
    static func shouldLoadImage(at _: URL?) -> Bool { false }

    static func canOpenAfterUserAction(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }
}

struct MarkdownPreviewRequestGuard: Sendable {
    private(set) var currentID = UUID()

    mutating func begin() -> UUID {
        currentID = UUID()
        return currentID
    }

    func accepts(_ requestID: UUID) -> Bool {
        requestID == currentID
    }
}
