import AppKit
import Foundation

enum SVGPreviewSource: Equatable, Sendable {
    case inline(id: String, text: String)
    case file(id: String, url: URL)

    var id: String {
        switch self {
        case .inline(let id, _), .file(let id, _): id
        }
    }
}

struct SVGMetadata: Equatable, Sendable {
    let viewBox: String?
    let width: String?
    let height: String?
    let sourceByteCount: Int
}

enum SVGPreviewFailure: Equatable, Sendable {
    case tooLarge
    case unreadable
    case invalidXML
    case unsafeContent
    case tooComplex
    case unsupported
}

struct PreparedSVGDocument: Equatable, Sendable {
    let sourceText: String?
    let renderData: Data?
    let metadata: SVGMetadata
    let failure: SVGPreviewFailure?

    var canRender: Bool { renderData != nil && failure == nil }
}

enum SVGPreviewResolver {
    /// Native SVG decoding and XML validation happen outside the capture path.
    /// Detection is allowed a wider bound so oversized-but-obviously-SVG clips
    /// still reach a safe Raw fallback instead of generic code detection.
    static let maximumRenderableBytes = 512 * 1024
    static let maximumDetectionBytes = 2 * 1024 * 1024
    static let maximumElementCount = 5_000
    static let maximumDepth = 128
    static let maximumAttributeCharacters = 256 * 1024
    static let maximumPathDataCharacters = 192 * 1024

    static func source(for item: ClipItem) -> SVGPreviewSource? {
        if let url = svgFileURL(for: item) {
            return .file(id: "\(item.itemID):svg-file", url: url)
        }

        guard item.contentType == .code || item.contentType == .text else { return nil }
        if item.codeLanguage == CodeLanguage.svg.rawValue || isInlineSVGSource(item.content) {
            return .inline(id: "\(item.itemID):svg-inline", text: item.content)
        }
        return nil
    }

    static func svgFileURL(for item: ClipItem) -> URL? {
        guard item.contentType == .image,
              item.content != "[Image]",
              !item.content.contains("\n")
        else {
            return nil
        }

        let path = item.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "svg",
              FileManager.default.fileExists(atPath: path)
        else {
            return nil
        }
        return url
    }

    /// Cheap capture-time routing only. Full XML/security validation is deferred
    /// to `prepare(_:)`, away from clipboard monitoring.
    static func isInlineSVGSource(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= maximumDetectionBytes
        else {
            return false
        }

        let lowercased = trimmed.lowercased()
        guard let opening = lowercased.range(of: #"<svg(?=\s|/?>)"#, options: .regularExpression) else {
            return false
        }

        // The SVG root must be the first real element. XML declarations,
        // comments, processing instructions and a DOCTYPE may precede it; the
        // security validator rejects unsafe preambles before native rendering.
        let prefix = String(lowercased[..<opening.lowerBound])
        if prefix.range(of: #"<\s*[a-z]"#, options: .regularExpression) != nil {
            return false
        }

        guard let openingEnd = lowercased[opening.lowerBound...].firstIndex(of: ">") else {
            return false
        }
        let openingTag = lowercased[opening.lowerBound...openingEnd]
        if openingTag.dropLast().trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("/") {
            return lowercased[lowercased.index(after: openingEnd)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
        }

        guard let closing = lowercased.range(
            of: #"</svg\s*>"#,
            options: [.regularExpression, .backwards]
        ) else {
            return false
        }
        return lowercased[closing.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    static func prepare(_ source: SVGPreviewSource) async -> PreparedSVGDocument {
        await Task.detached(priority: .userInitiated) {
            prepareSynchronously(source)
        }.value
    }

    static func prepare(data: Data, sourceText: String? = nil) -> PreparedSVGDocument {
        prepareData(data, sourceText: sourceText)
    }

    private static func prepareSynchronously(_ source: SVGPreviewSource) -> PreparedSVGDocument {
        switch source {
        case .inline(_, let text):
            let data = Data(text.utf8)
            return prepareData(data, sourceText: text)

        case .file(_, let url):
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let byteCount = values.fileSize
            else {
                return failureDocument(.unreadable, sourceByteCount: 0)
            }
            guard byteCount <= maximumRenderableBytes else {
                return failureDocument(.tooLarge, sourceByteCount: byteCount)
            }
            guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return failureDocument(.unreadable, sourceByteCount: byteCount)
            }
            return prepareData(data, sourceText: String(data: data, encoding: .utf8))
        }
    }

    private static func prepareData(_ data: Data, sourceText: String?) -> PreparedSVGDocument {
        let byteCount = data.count
        guard byteCount <= maximumRenderableBytes else {
            return failureDocument(.tooLarge, sourceText: sourceText, sourceByteCount: byteCount)
        }
        guard let text = sourceText ?? String(data: data, encoding: .utf8) else {
            return failureDocument(.unreadable, sourceByteCount: byteCount)
        }

        let lowered = text.lowercased()
        guard !lowered.contains("<!doctype"), !lowered.contains("<!entity") else {
            return failureDocument(.unsafeContent, sourceText: text, sourceByteCount: byteCount)
        }

        let validator = SafeSVGXMLValidator()
        let parser = XMLParser(data: data)
        parser.delegate = validator
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never

        guard parser.parse(), validator.failure == nil, validator.rootWasSVG else {
            return failureDocument(
                validator.failure ?? .invalidXML,
                sourceText: text,
                sourceByteCount: byteCount
            )
        }

        let metadata = SVGMetadata(
            viewBox: validator.viewBox,
            width: validator.width,
            height: validator.height,
            sourceByteCount: byteCount
        )

        // This is intentionally performed only after the document passes the
        // no-script/no-external-resource validator. NSImage retains the SVG's
        // native vector representation; the UI decodes the same validated bytes
        // asynchronously through ImageCache.
        guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
            return PreparedSVGDocument(
                sourceText: text,
                renderData: nil,
                metadata: metadata,
                failure: .unsupported
            )
        }

        return PreparedSVGDocument(
            sourceText: text,
            renderData: data,
            metadata: metadata,
            failure: nil
        )
    }

    private static func failureDocument(
        _ failure: SVGPreviewFailure,
        sourceText: String? = nil,
        sourceByteCount: Int
    ) -> PreparedSVGDocument {
        PreparedSVGDocument(
            sourceText: sourceText,
            renderData: nil,
            metadata: SVGMetadata(
                viewBox: nil,
                width: nil,
                height: nil,
                sourceByteCount: sourceByteCount
            ),
            failure: failure
        )
    }
}

private final class SafeSVGXMLValidator: NSObject, XMLParserDelegate {
    private(set) var failure: SVGPreviewFailure?
    private(set) var rootWasSVG = false
    private(set) var viewBox: String?
    private(set) var width: String?
    private(set) var height: String?

    private var depth = 0
    private var elementCount = 0
    private var attributeCharacters = 0
    private var pathDataCharacters = 0
    private var styleDepth: Int?
    private var styleText = ""

    private static let blockedElements: Set<String> = [
        "script", "foreignobject", "iframe", "object", "embed", "audio", "video"
    ]

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard failure == nil else { return }
        depth += 1
        elementCount += 1

        let element = localName(qName ?? elementName)
        if depth == 1 {
            guard element == "svg" else {
                reject(.invalidXML, parser: parser)
                return
            }
            rootWasSVG = true
            viewBox = attributeValue(named: "viewbox", in: attributeDict)
            width = attributeValue(named: "width", in: attributeDict)
            height = attributeValue(named: "height", in: attributeDict)
            guard dimensionsAreReasonable(viewBox: viewBox, width: width, height: height) else {
                reject(.tooComplex, parser: parser)
                return
            }
        }

        guard elementCount <= SVGPreviewResolver.maximumElementCount,
              depth <= SVGPreviewResolver.maximumDepth,
              !Self.blockedElements.contains(element)
        else {
            reject(Self.blockedElements.contains(element) ? .unsafeContent : .tooComplex, parser: parser)
            return
        }

        if element == "style" {
            styleDepth = depth
            styleText = ""
        }

        for (rawName, rawValue) in attributeDict {
            let name = localName(rawName)
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            attributeCharacters += rawName.count + rawValue.count
            if element == "path", name == "d" {
                pathDataCharacters += rawValue.count
            }

            if attributeCharacters > SVGPreviewResolver.maximumAttributeCharacters
                || pathDataCharacters > SVGPreviewResolver.maximumPathDataCharacters {
                reject(.tooComplex, parser: parser)
                return
            }
            if name.hasPrefix("on") || name == "base" {
                reject(.unsafeContent, parser: parser)
                return
            }
            if name == "href" || name == "src" {
                guard value.isEmpty || value.hasPrefix("#") else {
                    reject(.unsafeContent, parser: parser)
                    return
                }
            }
            if !cssReferencesAreLocal(rawValue) {
                reject(.unsafeContent, parser: parser)
                return
            }
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if styleDepth == depth {
            if !cssReferencesAreLocal(styleText) {
                reject(.unsafeContent, parser: parser)
                return
            }
            styleDepth = nil
            styleText = ""
        }
        depth -= 1
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if styleDepth != nil { styleText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard styleDepth != nil else { return }
        guard let value = String(data: CDATABlock, encoding: .utf8) else {
            reject(.invalidXML, parser: parser)
            return
        }
        styleText += value
    }

    func parser(
        _ parser: XMLParser,
        foundProcessingInstructionWithTarget target: String,
        data: String?
    ) {
        reject(.unsafeContent, parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        resolveExternalEntityName name: String,
        systemID: String?
    ) -> Data? {
        reject(.unsafeContent, parser: parser)
        return nil
    }

    func parser(
        _ parser: XMLParser,
        foundExternalEntityDeclarationWithName name: String,
        publicID: String?,
        systemID: String?
    ) {
        reject(.unsafeContent, parser: parser)
    }

    func parser(
        _ parser: XMLParser,
        foundInternalEntityDeclarationWithName name: String,
        value: String?
    ) {
        reject(.unsafeContent, parser: parser)
    }

    private func reject(_ reason: SVGPreviewFailure, parser: XMLParser) {
        guard failure == nil else { return }
        failure = reason
        parser.abortParsing()
    }

    private func localName(_ name: String) -> String {
        (name.split(separator: ":").last.map(String.init) ?? name).lowercased()
    }

    private func attributeValue(named name: String, in attributes: [String: String]) -> String? {
        attributes.first { localName($0.key) == name }?.value
    }

    private func cssReferencesAreLocal(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        // Reject CSS escape/comment tricks that could conceal `url` or `@import`
        // from the small validator while still being understood by a renderer.
        guard !lowercased.contains("@import"),
              !value.contains("\\"),
              !lowercased.contains("/*")
        else {
            return false
        }
        guard lowercased.contains("url") else { return true }

        guard let regex = try? NSRegularExpression(
            pattern: #"url\s*\(\s*([^\)]*)\s*\)"#,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        let matches = regex.matches(in: value, range: range)
        guard let tokenRegex = try? NSRegularExpression(
            pattern: #"url\s*\("#,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let tokenCount = tokenRegex.numberOfMatches(in: value, range: range)
        guard !matches.isEmpty, matches.count == tokenCount else { return false }

        return matches.allSatisfy { match in
            guard let capture = Range(match.range(at: 1), in: value) else { return false }
            let reference = value[capture]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            return reference.hasPrefix("#")
        }
    }

    private func dimensionsAreReasonable(
        viewBox: String?,
        width: String?,
        height: String?
    ) -> Bool {
        if let viewBox {
            let numbers = viewBox
                .split(whereSeparator: { $0.isWhitespace || $0 == "," })
                .compactMap { Double($0) }
            guard numbers.count == 4,
                  numbers.allSatisfy(\.isFinite),
                  numbers[2] > 0,
                  numbers[3] > 0,
                  numbers[2] <= 100_000,
                  numbers[3] <= 100_000,
                  abs(numbers[0]) <= 1_000_000_000,
                  abs(numbers[1]) <= 1_000_000_000
            else {
                return false
            }
        }
        return [width, height].compactMap { $0 }.allSatisfy(reasonableLength)
    }

    private func reasonableLength(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"^([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:e[+-]?\d+)?)(%|px|pt|pc|mm|cm|in)?$"#,
            options: [.caseInsensitive]
        ) else {
            return false
        }
        let range = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Double(value[numberRange]),
              number.isFinite,
              number > 0
        else {
            return false
        }
        return number <= (value.hasSuffix("%") ? 10_000 : 100_000)
    }
}
