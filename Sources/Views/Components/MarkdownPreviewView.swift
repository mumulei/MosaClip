import AppKit
import MarkdownUI
import SwiftUI

enum MarkdownPreviewMode: String, CaseIterable {
    case rendered
    case raw
}

/// Immutable parsed Markdown produced away from the main actor. MarkdownUI's
/// value graph contains only parsed value nodes but predates Swift's Sendable
/// annotations, so the adapter owns the audited boundary in one place.
struct PreparedMarkdownContent: @unchecked Sendable {
    let value: MarkdownUI.MarkdownContent

    var plainText: String { value.renderPlainText() }
}

enum MarkdownPreviewLoadError: Error, Equatable, Sendable {
    case fileTooLarge
    case invalidEncoding
    case unreadableFile
}

/// The only layer that imports and exposes MarkdownUI behavior to PasteMemo.
/// Business views pass raw presentation sources and remain renderer-agnostic.
enum MarkdownRendererAdapter {
    static func loadText(from source: MarkdownPreviewSource) async throws -> String {
        switch source {
        case .inline(_, let text):
            return text
        case .file(_, let url):
            let worker = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { throw CancellationError() }
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
                guard byteCount <= MarkdownPreviewResolver.maximumLoadedFileBytes else {
                    throw MarkdownPreviewLoadError.fileTooLarge
                }

                guard let handle = try? FileHandle(forReadingFrom: url) else {
                    throw MarkdownPreviewLoadError.unreadableFile
                }
                defer { try? handle.close() }
                let data = try handle.readToEnd() ?? Data()
                guard !Task.isCancelled else { throw CancellationError() }
                guard let text = String(data: data, encoding: .utf8) else {
                    throw MarkdownPreviewLoadError.invalidEncoding
                }
                return text
            }
            return try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
        }
    }

    static func prepare(
        markdown: String,
        allowingRiskyContent: Bool = false
    ) async throws -> PreparedMarkdownContent {
        let canRender = allowingRiskyContent
            ? MarkdownPreviewResolver.canRenderManually(markdown)
            : MarkdownPreviewResolver.canRender(markdown)
        guard canRender else {
            throw MarkdownPreviewLoadError.fileTooLarge
        }

        let worker = Task.detached(priority: .userInitiated) {
            guard !Task.isCancelled else { throw CancellationError() }
            let parsed = PreparedMarkdownContent(value: MarkdownUI.MarkdownContent(markdown))
            guard !Task.isCancelled else { throw CancellationError() }
            return parsed
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

/// A MarkdownUI image provider that never reads local files and never starts a
/// network request. The URL is used only to distinguish the accessibility hint.
private struct BlockedMarkdownImageProvider: ImageProvider {
    let label: String

    func makeImage(url: URL?) -> some View {
        Label {
            Text(label)
        } icon: {
            Image(systemName: "photo.badge.exclamationmark")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .accessibilityHint(url?.absoluteString ?? "")
    }
}

struct MarkdownPreviewView: View {
    let source: MarkdownPreviewSource
    var showsModePicker = true

    @State private var mode = MarkdownPreviewMode.rendered
    @State private var rawText: String?
    @State private var preparedContent: PreparedMarkdownContent?
    @State private var isLoading = true
    @State private var isOverRenderLimit = false
    @State private var isOverManualRenderLimit = false
    @State private var loadError: MarkdownPreviewLoadError?
    @State private var requestGuard = MarkdownPreviewRequestGuard()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsModePicker {
                modePicker
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                Divider()
            }

            previewBody
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .task(id: source.id) {
            await loadPreview()
        }
        .task(id: "\(source.id):\(mode.rawValue):\(rawText != nil)") {
            guard mode == .rendered,
                  preparedContent == nil,
                  rawText != nil,
                  !isLoading,
                  !isOverManualRenderLimit else { return }
            await renderOnDemand()
        }
    }

    private var modePicker: some View {
        HStack {
            Picker(L10n.tr("markdown.preview.mode"), selection: $mode) {
                Text(L10n.tr("markdown.preview.rendered"))
                    .tag(MarkdownPreviewMode.rendered)
                Text(L10n.tr("markdown.preview.raw"))
                    .tag(MarkdownPreviewMode.raw)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .disabled(rawText == nil || isOverManualRenderLimit)

            if isOverRenderLimit {
                Label(
                    L10n.tr(
                        isOverManualRenderLimit
                            ? "markdown.preview.tooLarge"
                            : "markdown.preview.renderOnDemand"
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var previewBody: some View {
        if isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if loadError != nil, rawText == nil {
            fileFallback
        } else if mode == .raw || preparedContent == nil {
            if let rawText {
                NativeTextView(
                    text: rawText,
                    allowRichRender: false,
                    itemID: source.id
                )
                .id("markdown-raw:\(source.id):\(rawText.hashValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if let preparedContent {
            ScrollView {
                Markdown(preparedContent.value)
                    .markdownTheme(.pasteMemo)
                    .markdownImageProvider(
                        BlockedMarkdownImageProvider(
                            label: L10n.tr("markdown.preview.imageBlocked")
                        )
                    )
                    .environment(\.openURL, OpenURLAction { url in
                        guard MarkdownRemoteContentPolicy.canOpenAfterUserAction(url) else {
                            return .discarded
                        }
                        NSWorkspace.shared.open(url)
                        return .handled
                    })
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var fileFallback: some View {
        switch source {
        case .file(_, let url):
            SingleFilePreview(
                path: url.path,
                iconSize: 64,
                nameFont: .system(size: 15, weight: .medium)
            )
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .inline:
            ContentUnavailableView(
                L10n.tr("detail.preview_failed"),
                systemImage: "doc.badge.ellipsis"
            )
        }
    }

    @MainActor
    private func loadPreview() async {
        let requestID = requestGuard.begin()
        mode = .rendered
        rawText = nil
        preparedContent = nil
        loadError = nil
        isOverRenderLimit = false
        isOverManualRenderLimit = false
        isLoading = true

        do {
            let text = try await MarkdownRendererAdapter.loadText(from: source)
            guard !Task.isCancelled, requestGuard.accepts(requestID) else { return }
            rawText = text

            let renderPolicy = MarkdownPreviewResolver.renderPolicy(for: text)
            guard renderPolicy == .automatic else {
                mode = .raw
                isOverRenderLimit = true
                isOverManualRenderLimit = renderPolicy == .unavailable
                isLoading = false
                return
            }

            let prepared = try await MarkdownRendererAdapter.prepare(markdown: text)
            guard !Task.isCancelled, requestGuard.accepts(requestID) else { return }
            preparedContent = prepared
            isLoading = false
        } catch is CancellationError {
            return
        } catch let error as MarkdownPreviewLoadError {
            guard requestGuard.accepts(requestID) else { return }
            loadError = error
            isOverRenderLimit = error == .fileTooLarge
            mode = .raw
            isLoading = false
        } catch {
            guard requestGuard.accepts(requestID) else { return }
            loadError = .unreadableFile
            mode = .raw
            isLoading = false
        }
    }

    @MainActor
    private func renderOnDemand() async {
        guard let text = rawText else { return }
        let requestID = requestGuard.currentID
        isLoading = true
        do {
            let prepared = try await MarkdownRendererAdapter.prepare(
                markdown: text,
                allowingRiskyContent: true
            )
            guard !Task.isCancelled, requestGuard.accepts(requestID) else { return }
            preparedContent = prepared
            isLoading = false
        } catch is CancellationError {
            return
        } catch let error as MarkdownPreviewLoadError {
            guard requestGuard.accepts(requestID) else { return }
            loadError = error
            isOverRenderLimit = true
            isOverManualRenderLimit = true
            mode = .raw
            isLoading = false
        } catch {
            guard requestGuard.accepts(requestID) else { return }
            loadError = .unreadableFile
            mode = .raw
            isLoading = false
        }
    }
}
