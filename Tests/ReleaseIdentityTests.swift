import Foundation
import Testing
@testable import PasteMemo

@Suite("Release identity")
@MainActor
struct ReleaseIdentityTests {
    @Test("MosaClip installs independently from upstream PasteMemo")
    func independentIdentity() {
        #expect(ReleaseIdentity.displayName == "MosaClip")
        #expect(ReleaseIdentity.bundleIdentifier == "com.mumulei.mosaclip")
        #expect(!ReleaseIdentity.bundleIdentifier.contains("lifedever"))
        // 更名迁移的来源 ID 必须保留,且不得与新 ID 混淆。
        #expect(ReleaseIdentity.legacyBundleIdentifiers.contains("com.mumulei.pastememo.workspace"))
        #expect(!ReleaseIdentity.legacyBundleIdentifiers.contains(ReleaseIdentity.bundleIdentifier))
        #expect(!ReleaseIdentity.developmentBundleIdentifier.isEmpty)
        #expect(ReleaseIdentity.upstreamRepositoryURL.absoluteString == "https://github.com/lifedever/PasteMemo-app")
        // 仓库已随品牌更名为 mumulei/MosaClip;链接必须指向新 slug。
        #expect(ReleaseIdentity.repositoryName == "MosaClip")
        #expect(ReleaseIdentity.repositoryURL.absoluteString == "https://github.com/mumulei/MosaClip")
    }

    @Test("Private build fails closed for updates and analytics")
    func networkPolicy() {
        #expect(!ReleaseIdentity.onlineUpdatesEnabled)
        #expect(!ReleaseIdentity.anonymousUsageStatisticsEnabled)
        #expect(!UsageTracker.isEnabled)

        // The compatibility method must remain a no-op even when called by an
        // older path. Its implementation contains no URL or URLSession.
        UsageTracker.pingIfNeeded(source: .launch)
        #expect(!UsageTracker.isEnabled)
    }

    @Test("Bundled MCP proxy follows current and legacy socket identities")
    func mcpProxySocketIdentity() throws {
        // MCPProxy 是独立 executable target,主测试 target 不能直接 import；读取其
        // 小型入口源码作为发布护栏,防止下次 bundle id 更名只改主 App、漏掉 helper。
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let proxySourceURL = packageRoot.appendingPathComponent("Sources/MCPProxy/main.swift")
        let source = try String(contentsOf: proxySourceURL, encoding: .utf8)

        let currentProduction = try #require(source.range(of: "\"\(ReleaseIdentity.bundleIdentifier)\""))
        let currentDevelopment = try #require(source.range(of: "\"\(ReleaseIdentity.developmentBundleIdentifier)\""))
        let legacyProduction = try #require(source.range(of: "\"\(ReleaseIdentity.legacyBundleIdentifiers[0])\""))

        #expect(currentProduction.lowerBound < currentDevelopment.lowerBound)
        #expect(currentDevelopment.lowerBound < legacyProduction.lowerBound)
        #expect(source.contains("return base.appendingPathComponent(bundleIDs[0])"))
        #expect(source.contains("\"name\": \"mosaclip (offline)\""))
        #expect(source.contains("MosaClip is not running"))
    }
}
