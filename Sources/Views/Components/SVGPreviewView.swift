import SwiftUI

private enum SVGPreviewMode: String, CaseIterable {
    case rendered
    case raw
}

struct SVGPreviewView: View {
    let source: SVGPreviewSource
    var showsModePicker = true
    var compact = false

    @State private var mode: SVGPreviewMode = .rendered
    @State private var document: PreparedSVGDocument?
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            if showsModePicker, document?.sourceText != nil {
                HStack(spacing: 10) {
                    Text(L10n.tr("svg.preview.mode"))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $mode) {
                        Text(L10n.tr("svg.preview.rendered"))
                            .tag(SVGPreviewMode.rendered)
                        Text(L10n.tr("svg.preview.raw"))
                            .tag(SVGPreviewMode.raw)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 164)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                Divider().opacity(0.35)
            }

            Group {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let document {
                    preview(document)
                } else {
                    failureMessage(.unreadable)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: source.id) {
            isLoading = true
            document = nil
            mode = .rendered
            let prepared = await SVGPreviewResolver.prepare(source)
            guard !Task.isCancelled else { return }
            document = prepared
            isLoading = false
        }
    }

    @ViewBuilder
    private func preview(_ document: PreparedSVGDocument) -> some View {
        if mode == .raw, let sourceText = document.sourceText {
            rawPreview(sourceText)
        } else if document.canRender, let data = document.renderData {
            renderedPreview(data: data, metadata: document.metadata)
        } else {
            fallbackPreview(document)
        }
    }

    private func renderedPreview(data: Data, metadata: SVGMetadata) -> some View {
        VStack(spacing: 0) {
            ZStack {
                SVGTransparencySurface(squareSize: compact ? 9 : 13)
                ZoomablePreviewImageView(
                    source: .inMemory(data: data, cacheKey: "safe-svg:\(source.id)"),
                    maxPixelSize: compact ? 900 : 1_400,
                    thumbnailSize: compact ? 180 : 240,
                    cornerRadius: 8
                )
                .padding(compact ? 10 : 18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            }
            .padding(compact ? 10 : 16)

            if !compact {
                Divider().opacity(0.3)
                metadataView(metadata)
            }
        }
    }

    @ViewBuilder
    private func fallbackPreview(_ document: PreparedSVGDocument) -> some View {
        VStack(spacing: 0) {
            failureMessage(document.failure ?? .invalidXML)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            Divider().opacity(0.3)
            if let sourceText = document.sourceText {
                rawPreview(sourceText)
            } else if case .file(_, let url) = source {
                SingleFilePreview(
                    path: url.path,
                    iconSize: compact ? 48 : 64,
                    nameFont: .system(size: compact ? 13 : 15, weight: .medium)
                )
                .padding(16)
            }
        }
    }

    private func rawPreview(_ sourceText: String) -> some View {
        NativeTextView(
            text: sourceText,
            allowRichRender: false,
            itemID: source.id
        )
        .id("svg-raw:\(source.id):\(sourceText.hashValue)")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failureMessage(_ failure: SVGPreviewFailure) -> some View {
        Label(failureText(failure), systemImage: "exclamationmark.shield.fill")
            .font(.system(size: compact ? 11 : 12, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureText(_ failure: SVGPreviewFailure) -> String {
        switch failure {
        case .tooLarge, .tooComplex:
            L10n.tr("svg.preview.tooLarge")
        case .unsafeContent:
            L10n.tr("svg.preview.blocked")
        case .invalidXML:
            L10n.tr("svg.preview.invalid")
        case .unreadable:
            L10n.tr("svg.preview.unreadable")
        case .unsupported:
            L10n.tr("svg.preview.unsupported")
        }
    }

    private func metadataView(_ metadata: SVGMetadata) -> some View {
        HStack(spacing: 0) {
            metadataCell(
                label: L10n.tr("svg.metadata.viewBox"),
                value: metadata.viewBox ?? "—"
            )
            metadataCell(
                label: L10n.tr("svg.metadata.width"),
                value: metadata.width ?? "—"
            )
            metadataCell(
                label: L10n.tr("svg.metadata.height"),
                value: metadata.height ?? "—"
            )
            metadataCell(
                label: L10n.tr("svg.metadata.sourceSize"),
                value: ByteCountFormatter.string(
                    fromByteCount: Int64(metadata.sourceByteCount),
                    countStyle: .file
                )
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func metadataCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SVGTransparencySurface: View {
    let squareSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / squareSize))
            let rows = Int(ceil(size.height / squareSize))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(Path(rect), with: .color(Color.primary.opacity(0.035)))
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityHidden(true)
    }
}
