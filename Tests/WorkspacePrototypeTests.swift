import Foundation
import Testing
@testable import PasteMemo

@Suite("Workspace prototype")
struct WorkspacePrototypeTests {
    @Test("Classifies every card variant without changing raw content")
    @MainActor
    func cardVariants() {
        let fixtures = Self.fixtures(count: 8)
        let descriptors = fixtures.map(WorkspaceCardDescriptor.init(item:))

        #expect(descriptors.contains { if case .text = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .markdown = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .image = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .svg = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .color = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .code = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .link = $0.kind { true } else { false } })
        #expect(descriptors.contains { if case .file = $0.kind { true } else { false } })
        #expect(fixtures[1].content == "# Markdown 1\n\n- first\n- second")
        #expect(fixtures[3].content.hasPrefix("<svg"))
    }

    @Test("Bounds tall and wide summaries before layout")
    @MainActor
    func boundedSummaries() {
        let tall = ClipItem(
            content: (0..<2_000).map { "line \($0)" }.joined(separator: "\n"),
            contentType: .text
        )
        let wide = ClipItem(content: String(repeating: "wide", count: 5_000), contentType: .code)
        let huge = ClipItem(content: String(repeating: "word ", count: 100_000), contentType: .text)

        let tallSummary = WorkspaceCardDescriptor(item: tall).summary
        let wideSummary = WorkspaceCardDescriptor(item: wide).summary
        let hugeSummary = WorkspaceCardDescriptor(item: huge).summary
        #expect(tallSummary.count <= WorkspaceCardDescriptor.maximumSummaryCharacters)
        #expect(wideSummary.count <= WorkspaceCardDescriptor.maximumSummaryCharacters)
        #expect(hugeSummary.count <= WorkspaceCardDescriptor.maximumSummaryCharacters)
        #expect(tallSummary.hasSuffix("…"))
        #expect(wideSummary.hasSuffix("…"))
    }

    @Test("Keeps source order for 100, 1,000, and 10,000 mixed items", arguments: [100, 1_000, 10_000])
    @MainActor
    func scaleAndOrder(count: Int) {
        let items = Self.fixtures(count: count)
        let sourceIDs = items.map(\.itemID)
        let descriptors = items.map(WorkspaceCardDescriptor.init(item:))
        let presentedIDs = WorkspaceGridOrdering.visualOrder(for: items).map(\.itemID)

        #expect(items.count == count)
        #expect(descriptors.count == count)
        #expect(descriptors.allSatisfy { $0.summary.count <= WorkspaceCardDescriptor.maximumSummaryCharacters })
        #expect(presentedIDs == sourceIDs)
        #expect(items.map(\.createdAt) == items.map(\.createdAt).sorted(by: >))

        // A rapid capture inserts at the front but does not reorder existing data.
        let inserted = ClipItem(content: "newest", contentType: .text, createdAt: Date())
        let afterInsert = WorkspaceGridOrdering.visualOrder(for: [inserted] + items)
        #expect(afterInsert.dropFirst().map(\.itemID) == sourceIDs)
        #expect(afterInsert.first?.itemID == inserted.itemID)
    }

    @Test("Keyboard navigation follows row-major visual order")
    func keyboardNavigation() {
        let ids = Array(0..<10)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 4, direction: .left, columnCount: 3
        ) == 3)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 4, direction: .right, columnCount: 3
        ) == 5)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 4, direction: .up, columnCount: 3
        ) == 1)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 4, direction: .down, columnCount: 3
        ) == 7)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 9, direction: .down, columnCount: 3
        ) == nil)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 3, direction: .left, columnCount: 3
        ) == nil)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: 5, direction: .right, columnCount: 3
        ) == nil)
        #expect(WorkspaceGridNavigation.neighbor(
            in: ids, current: nil, direction: .right, columnCount: 3
        ) == 0)
    }

    @Test("Resize metrics cover minimum and wide window sizes")
    func resizeMetrics() {
        #expect(WorkspaceGridMetrics.columnCount(for: 240) == 1)
        #expect(WorkspaceGridMetrics.columnCount(for: 680) == 2)
        #expect(WorkspaceGridMetrics.columnCount(for: 690) == 3)
        #expect(WorkspaceGridMetrics.columnCount(for: 1_460) == 6)
    }

    @MainActor
    private static func fixtures(count: Int) -> [ClipItem] {
        let base = Date(timeIntervalSince1970: 2_000_000_000)
        return (0..<count).map { index in
            let createdAt = base.addingTimeInterval(TimeInterval(-index))
            switch index % 8 {
            case 0:
                return ClipItem(content: "Plain text \(index)", contentType: .text, createdAt: createdAt)
            case 1:
                return ClipItem(
                    content: "# Markdown \(index)\n\n- first\n- second",
                    contentType: .text,
                    createdAt: createdAt
                )
            case 2:
                return ClipItem(content: "[Image]", contentType: .image, createdAt: createdAt)
            case 3:
                return ClipItem(
                    content: "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"32\" height=\"12\"><rect width=\"32\" height=\"12\"/></svg>",
                    contentType: .code,
                    createdAt: createdAt,
                    codeLanguage: CodeLanguage.svg.rawValue
                )
            case 4:
                return ClipItem(content: "#336699", contentType: .color, createdAt: createdAt)
            case 5:
                return ClipItem(
                    content: "let value = \(index)\nprint(value)",
                    contentType: .code,
                    createdAt: createdAt,
                    codeLanguage: CodeLanguage.swift.rawValue
                )
            case 6:
                return ClipItem(
                    content: "https://example.com/items/\(index)",
                    contentType: .link,
                    createdAt: createdAt
                )
            default:
                return ClipItem(
                    content: "/tmp/workspace-fixture-\(index).txt",
                    contentType: .file,
                    createdAt: createdAt
                )
            }
        }
    }
}
