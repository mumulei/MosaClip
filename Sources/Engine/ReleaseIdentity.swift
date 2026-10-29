import Foundation

/// Distribution identity for the private MosaClip derivative.
///
/// Keep release-owned URLs and feature policy in one place so a future public
/// updater cannot accidentally fall back to the upstream PasteMemo service.
///
/// 命名沿革:产品原名 "PasteMemo Workspace"(bundle id
/// `com.mumulei.pastememo.workspace`),2026-08 更名为 MosaClip。
/// `legacyBundleIdentifiers` 供一次性数据/设置迁移使用,勿删。
enum ReleaseIdentity {
    static let displayName = "MosaClip"
    static let bundleIdentifier = "com.mumulei.mosaclip"
    static let developmentBundleIdentifier = "com.mumulei.mosaclip.dev"

    /// 更名前的 bundle id(旧→新数据目录与设置域迁移的来源)。首项为主域名。
    static let legacyBundleIdentifiers = [
        "com.mumulei.pastememo.workspace",
        "com.mumulei.pastememo.workspace.dev",
    ]

    static let repositoryOwner = "mumulei"
    static let repositoryName = "MosaClip"

    static let repositoryURL = URL(string: "https://github.com/mumulei/MosaClip")!
    static let websiteURL = URL(string: "https://mosaclip.vercel.app/")!
    static let issuesURL = repositoryURL.appendingPathComponent("issues")
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    static let documentationURL = repositoryURL.appendingPathComponent("blob/main/README.md")

    /// Public source availability does not certify a signed distribution or
    /// authorize an updater. Keep disabled until the distribution gates pass.
    static let onlineUpdatesEnabled = false

    /// The derivative has no owned analytics service. Never send telemetry to
    /// the original PasteMemo deployment.
    static let anonymousUsageStatisticsEnabled = false

    /// 上游项目署名(GPL-3.0 归属,与品牌名无关,保持不变)。
    static let upstreamProjectName = "PasteMemo"
    static let upstreamRepositoryURL = URL(string: "https://github.com/lifedever/PasteMemo-app")!
}
