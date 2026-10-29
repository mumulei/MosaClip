import SwiftUI

@MainActor
enum L10n {
    static let supportedLanguages: [(code: String, name: String)] = [
        ("zh-Hans", "简体中文"),
        ("zh-Hant", "繁體中文"),
        ("en", "English"),
        ("ja", "日本語"),
        ("ko", "한국어"),
        ("fr", "Français"),
        ("de", "Deutsch"),
        ("es", "Español"),
        ("it", "Italiano"),
        ("ru", "Русский"),
        ("id", "Bahasa Indonesia"),
    ]

    /// 解析好的 lproj Bundle 缓存(按语言)。`Bundle(path:)` 每次调用都要做
    /// 路径解析 + 对象分配,而 tr() 有 ~949 个调用点、大量位于列表行 body 里,
    /// 逐帧重建是纯浪费。语言切换通过 setLanguage → 清缓存失效。
    private static var lprojBundleCache: [String: Bundle] = [:]

    static func tr(_ key: String) -> String {
        let lang = LanguageManager.shared.current
        if let cached = lprojBundleCache[lang] {
            return NSLocalizedString(key, bundle: cached, comment: "")
        }
        guard let path = Bundle.pasteMemoResources.path(forResource: lang, ofType: "lproj")
                ?? Bundle.pasteMemoResources.paths(forResourcesOfType: "lproj", inDirectory: nil)
                    .first(where: { $0.lowercased().contains(lang.lowercased()) }),
              let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, bundle: .pasteMemoResources, comment: "")
        }
        lprojBundleCache[lang] = bundle
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }

    /// 语言切换后调用,让下一条 tr() 重新解析新语言的 lproj。
    static func invalidateBundleCache() {
        lprojBundleCache.removeAll()
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }

    /// The resource bundle that holds our `.lproj` directories.
    /// Exposed for tests; production code resolves via `Bundle.pasteMemoResources`
    /// (the generated `Bundle.module` can't find the bundle in signed builds).
    static var resourceBundle: Bundle { .pasteMemoResources }
}

@MainActor
final class LanguageManager: ObservableObject {
    static let shared = LanguageManager()
    @AppStorage("appLanguage") var current: String = ""

    private init() {
        // Auto-detect system language on first launch
        if current.isEmpty {
            current = detectSystemLanguage()
        }
    }

    func setLanguage(_ lang: String) {
        current = lang
        L10n.invalidateBundleCache()
        objectWillChange.send()
    }

    /// Detect system language and match to supported languages
    private func detectSystemLanguage() -> String {
        let preferred = Locale.preferredLanguages
        let supportedCodes = L10n.supportedLanguages.map(\.code)

        for lang in preferred {
            // Exact match
            if supportedCodes.contains(lang) {
                return lang
            }
            // Prefix match: "zh-Hans-CN" → "zh-Hans", "ja-JP" → "ja"
            for code in supportedCodes {
                if lang.hasPrefix(code) {
                    return code
                }
            }
            // Base language match: "zh" → "zh-Hans"
            let base = lang.components(separatedBy: "-").first ?? lang
            if let match = supportedCodes.first(where: { $0.hasPrefix(base) }) {
                return match
            }
        }

        return "en"
    }
}

@MainActor
struct LocalizedViewModifier: ViewModifier {
    @ObservedObject private var languageManager = LanguageManager.shared

    func body(content: Content) -> some View {
        content
            .id(languageManager.current)
    }
}

extension View {
    @MainActor
    func localized() -> some View {
        modifier(LocalizedViewModifier())
    }
}
