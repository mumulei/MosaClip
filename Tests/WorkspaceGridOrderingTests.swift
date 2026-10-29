import Testing

@testable import PasteMemo

@Suite("Workspace row-major grid ordering")
struct WorkspaceGridOrderingTests {
    @Test("Visual order always equals source order")
    func exactSourceOrder() {
        let items = Array(0..<40)
        #expect(WorkspaceGridOrdering.visualOrder(for: items) == items)
        let reversed = Array(items.reversed())
        #expect(WorkspaceGridOrdering.visualOrder(for: reversed) == reversed)
    }

    @Test("Repeated prepends remain first without layout state")
    func newestAlwaysFirst() {
        var items = Array(1...12)
        items.insert(0, at: 0)
        #expect(WorkspaceGridOrdering.visualOrder(for: items).first == 0)

        items.insert(-1, at: 0)
        #expect(WorkspaceGridOrdering.visualOrder(for: items).first == -1)
    }

    @Test("Deleting any position compacts the next row-major card into the gap")
    func deletionCompacts() {
        let source = Array(0..<8)
        let remaining = source.filter { $0 != 2 }
        let visual = WorkspaceGridOrdering.visualOrder(for: remaining)
        let rows = visual.chunked(into: 4)

        #expect(rows == [[0, 1, 3, 4], [5, 6, 7]])
        #expect(visual.count == remaining.count)
    }

    @Test("Deleting first, middle and last positions never leaves placeholders")
    func deletionEdges() {
        let source = Array(0..<12)
        for deleted in [0, 5, 11] {
            let remaining = source.filter { $0 != deleted }
            let visual = WorkspaceGridOrdering.visualOrder(for: remaining)
            #expect(visual == remaining)
            #expect(visual.count == 11)
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { start in
            Array(self[start..<Swift.min(start + size, count)])
        }
    }
}
