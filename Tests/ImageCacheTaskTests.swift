import AppKit
import Foundation
import Testing

@testable import PasteMemo

@Suite("ImageCacheTasks", .serialized)
struct ImageCacheTaskTests {
    @Test("A failed preview task is removed so the same key can retry")
    func failedPreviewCanRetry() async throws {
        let cache = ImageCache()
        let validPNG = try makePNG()

        // Fast invalid decodes exercise the completion/registration ordering that used to
        // leave completed tasks in the coalescing registry. Each key must accept a valid
        // retry immediately after the failed task has completed.
        for index in 0..<32 {
            let key = "image-cache-retry-\(UUID().uuidString)-\(index)"
            let failed = cache.previewTask(
                for: Data([0x00]),
                key: key,
                maxDimension: 32
            )
            _ = await failed.value

            let retry = cache.previewTask(
                for: validPNG,
                key: key,
                maxDimension: 32
            )
            let result = await retry.value

            #expect(result.image != nil)
        }
    }

    @Test("A failed thumbnail task is removed so the same key can retry")
    func failedThumbnailCanRetry() async throws {
        let cache = ImageCache()
        let validPNG = try makePNG()

        for index in 0..<32 {
            let key = "thumbnail-cache-retry-\(UUID().uuidString)-\(index)"
            let failed = cache.thumbnailTask(
                for: Data([0x00]),
                key: key,
                size: 24
            )
            _ = await failed.value

            let retry = cache.thumbnailTask(
                for: validPNG,
                key: key,
                size: 24
            )
            let result = await retry.value

            #expect(result.image != nil)
        }
    }

    @Test("Preview task result survives cache eviction before view consumption")
    func previewResultSurvivesCacheEviction() async throws {
        let cache = ImageCache()
        let key = "preview-result-\(UUID().uuidString)"

        let task = cache.previewTask(
            for: try makePNG(),
            key: key,
            maxDimension: 32
        )
        _ = await task.value
        cache.removeAllCachedImagesForTesting()
        let resultAfterEviction = await task.value

        #expect(cache.cachedPreview(for: key, maxDimension: 32) == nil)
        #expect(resultAfterEviction.image != nil)
    }

    @Test("Thumbnail task result survives cache eviction before view consumption")
    func thumbnailResultSurvivesCacheEviction() async throws {
        let cache = ImageCache()
        let key = "thumbnail-result-\(UUID().uuidString)"

        let task = cache.thumbnailTask(
            for: try makePNG(),
            key: key,
            size: 24
        )
        _ = await task.value
        cache.removeAllCachedImagesForTesting()
        let resultAfterEviction = await task.value

        #expect(cache.cachedThumbnail(for: key, size: 24) == nil)
        #expect(resultAfterEviction.image != nil)
    }

    private func makePNG() throws -> Data {
        let representation = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: 2,
                pixelsHigh: 2,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        )
        let color = NSColor(deviceRed: 0.1, green: 0.4, blue: 0.9, alpha: 1)
        representation.setColor(color, atX: 0, y: 0)
        representation.setColor(color, atX: 1, y: 0)
        representation.setColor(color, atX: 0, y: 1)
        representation.setColor(color, atX: 1, y: 1)
        return try #require(representation.representation(using: .png, properties: [:]))
    }
}
