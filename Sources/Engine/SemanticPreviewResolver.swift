import Foundation

/// Presentation-only semantic previews shared by the main detail, Quick Preview,
/// and workspace surfaces. Each feature keeps ownership of its own parsing,
/// validation, loading, and safety policy.
enum SemanticPreviewKind: Equatable {
    case svg(SVGPreviewSource)
    case markdown(MarkdownPreviewSource)
    case color(sourceText: String, parsed: ParsedColor)
}

enum SemanticPreviewResolver {
    /// Resolves only lightweight routing information. SVG validation, Markdown
    /// parsing, and file loading remain deferred to their dedicated preview views.
    @MainActor
    static func resolve(_ item: ClipItem) -> SemanticPreviewKind? {
        // SVG must win over generic Markdown/code routing because XML-shaped SVG
        // source can otherwise fall through to a text-oriented preview.
        if let source = SVGPreviewResolver.source(for: item) {
            return .svg(source)
        }

        if let source = MarkdownPreviewResolver.source(for: item) {
            return .markdown(source)
        }

        guard item.contentType == .color,
              let parsed = ColorConverter.parse(item.content)
        else {
            return nil
        }
        return .color(sourceText: item.content, parsed: parsed)
    }
}
