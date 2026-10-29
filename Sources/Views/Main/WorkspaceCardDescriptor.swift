import Foundation

enum WorkspaceCardKind: Equatable {
    case text
    case markdown(MarkdownPreviewSource)
    case image
    case svg(SVGPreviewSource)
    case color(ParsedColor)
    case code
    case link(domain: String?)
    case file

    var icon: String {
        switch self {
        case .text: "doc.text"
        case .markdown: "text.document"
        case .image: "photo"
        case .svg: "scribble.variable"
        case .color: "paintpalette.fill"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .link: "link"
        case .file: "doc"
        }
    }

    @MainActor
    var label: String {
        switch self {
        case .text: ClipContentType.text.label
        case .markdown: "Markdown"
        case .image: ClipContentType.image.label
        case .svg: "SVG"
        case .color: ClipContentType.color.label
        case .code: ClipContentType.code.label
        case .link: ClipContentType.link.label
        case .file: ClipContentType.file.label
        }
    }
}

/// Lightweight card metadata. It never mutates a ClipItem and intentionally
/// bounds text before it reaches SwiftUI's layout engine.
struct WorkspaceCardDescriptor: Equatable {
    static let maximumSummaryCharacters = 360
    static let maximumSummarySourceCharacters = 4_096

    let kind: WorkspaceCardKind
    let title: String
    let summary: String

    @MainActor
    init(item: ClipItem) {
        let semantic = SemanticPreviewResolver.resolve(item)
        switch semantic {
        case .svg(let source):
            kind = .svg(source)
            title = Self.title(for: item, fallback: "SVG")
            summary = Self.summary(for: item.content)
        case .markdown(let source):
            kind = .markdown(source)
            title = Self.markdownTitle(source: source, item: item)
            summary = Self.markdownSummary(source: source, item: item)
        case .color(_, let parsed):
            kind = .color(parsed)
            title = item.content
            summary = parsed.formatted(parsed.originalFormat)
        case nil:
            switch item.contentType {
            case .image:
                kind = .image
            case .code:
                kind = .code
            case .link:
                kind = .link(domain: item.resolvedURL?.host())
            case .file, .video, .audio, .document, .archive, .application:
                kind = .file
            default:
                kind = .text
            }
            title = Self.title(for: item, fallback: item.contentType.label)
            summary = Self.summary(for: item.content)
        }
    }

    static func summary(for text: String) -> String {
        // Card construction runs on the UI actor for visible SwiftData items.
        // Bound normalization work before splitting an arbitrarily large source.
        let boundedSource = text.prefix(maximumSummarySourceCharacters)
        let normalized = boundedSource
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.count > maximumSummaryCharacters else { return normalized }
        return String(normalized.prefix(maximumSummaryCharacters - 1)) + "…"
    }

    private static func title(for item: ClipItem, fallback: String) -> String {
        let value = item.displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value! : fallback
    }

    private static func markdownTitle(source: MarkdownPreviewSource, item: ClipItem) -> String {
        if case .file(_, let url) = source {
            return url.lastPathComponent
        }
        return title(for: item, fallback: "Markdown")
    }

    private static func markdownSummary(source: MarkdownPreviewSource, item: ClipItem) -> String {
        guard case .inline(_, let text) = source else {
            return summary(for: item.content)
        }
        let cleaned = text
            .replacingOccurrences(
                of: #"!\[[^\]]*\]\([^)]+\)"#,
                with: "[image]",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"[#>*_`~\[\]()]"#,
                with: " ",
                options: .regularExpression
            )
        return summary(for: cleaned)
    }
}
