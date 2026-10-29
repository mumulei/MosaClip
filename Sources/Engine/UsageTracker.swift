import Foundation

enum PingSource: String {
    case launch
    case quick
    case main
}

@MainActor
enum UsageTracker {
    // Retain the preference keys so older local preferences are harmless and
    // source-compatible, but this derivative has no analytics transport.
    static let ANALYTICS_ENABLED_KEY = "analyticsEnabled"
    static let ANALYTICS_ASKED_KEY = "analyticsAsked"

    static var isEnabled: Bool {
        get { ReleaseIdentity.anonymousUsageStatisticsEnabled }
        set { UserDefaults.standard.set(false, forKey: ANALYTICS_ENABLED_KEY) }
    }

    static var hasAskedConsent: Bool {
        true
    }

    static func markConsentAsked() {
        UserDefaults.standard.set(true, forKey: ANALYTICS_ASKED_KEY)
        UserDefaults.standard.set(false, forKey: ANALYTICS_ENABLED_KEY)
    }

    static func pingIfNeeded(source: PingSource = .launch) {
        // Intentionally empty. Kept as a compatibility surface for callers in
        // older code paths; there is no URL, request, identifier, or retry path.
        _ = source
    }
}
