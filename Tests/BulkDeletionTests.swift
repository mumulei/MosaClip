import Foundation
import SwiftData
import Testing

@testable import PasteMemo

@Suite("Bulk deletion", .serialized)
@MainActor
struct BulkDeletionTests {
    @Test("Clear All deletes every item across multiple batches")
    func clearAllDeletesEveryItem() async throws {
        let schema = Schema([ClipItem.self, SmartGroup.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)

        let items = (0..<250).map { index in
            let item = ClipItem(content: "bulk-clear-\(index)")
            context.insert(item)
            return item
        }
        try context.save()

        var progressValues: [Int] = []
        var allModelsAttachedAtInitialProgress = false
        await ClipItemStore.deleteAndNotifyBatched(
            items,
            from: context,
            batchSize: 17
        ) { done, _ in
            progressValues.append(done)
            if done == 0 {
                allModelsAttachedAtInitialProgress = items.allSatisfy { $0.modelContext != nil }
            }
        }

        #expect(allModelsAttachedAtInitialProgress)
        #expect(progressValues.first == 0)
        #expect(progressValues.last == items.count)
        #expect(zip(progressValues, progressValues.dropFirst()).allSatisfy { $0.0 <= $0.1 })
        #expect(try context.fetchCount(FetchDescriptor<ClipItem>()) == 0)
        #expect(items.allSatisfy { $0.modelContext == nil || $0.isDeleted })
    }
}
