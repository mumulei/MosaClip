import SwiftUI
import WebKit

/// 每个预览实例独享一个 WKWebView。
///
/// 历史教训(卡死根因):旧实现用全局单例池把一个 WKWebView 在多个窗口间
/// 来回搬运 —— 主窗口详情面板与 QuickPanel 预览都是消费者,`updateNSView`
/// 每次更新都调 `attach(to:)`,一旦两个视图的宿主窗口同时刷新(删除/OCR 完成
/// 触发双 store 通知、滚动逐帧刷新),双方就互相抢夺同一个 WebView:
/// reparent + loadHTMLString 重置 + 重新 load 无限乒乓,主线程在 AppKit 窗口
/// 约束失效循环里卡死。WKWebView 实例本身很轻(WebContent 进程按 App 共享),
/// 没有必要共享外壳。

@MainActor
final class WebPreviewCoordinator: NSObject, WKNavigationDelegate {
    var loadedURL: URL?
    var readinessHandler: ((Bool) -> Void)?

    private var readyToken = 0

    func notifyReady(_ ready: Bool) {
        readinessHandler?(ready)
    }

    /// Wait for real first paint before flipping ready (some sites commit then
    /// stall — see Coordinator.didFinish note below).
    func markReadyAfterFirstPaint() {
        readyToken &+= 1
        let token = readyToken
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self, self.readyToken == token else { return }
            self.notifyReady(true)
        }
    }

    func markReadyImmediately() {
        readyToken &+= 1
        notifyReady(true)
    }

    // issue #46. Caps deliberately leave headroom for fat marketing pages
    // and reasonable image previews while still capping the worst case.
    static let htmlResponseCap: Int64 = 5_000_000
    static let imageResponseCap: Int64 = 10_000_000

    func webView(
        _ webView: WKWebView,
        decidePolicyFor action: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        // Each navigation honours the current user setting; defaults to ON
        // to preserve preview fidelity for legacy users.
        let allowJS = (UserDefaults.standard.object(forKey: "previewExecutesJavaScript") as? Bool) ?? true
        preferences.allowsContentJavaScript = allowJS

        if action.navigationType == .linkActivated {
            if let url = action.request.url {
                NSWorkspace.shared.open(url)
            }
            decisionHandler(.cancel, preferences)
        } else {
            decisionHandler(.allow, preferences)
        }
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
    ) {
        let mimeType = (navigationResponse.response.mimeType ?? "").lowercased()
        let isHTML = mimeType.contains("html") || mimeType.contains("xml")
        let isImage = mimeType.hasPrefix("image/")

        guard isHTML || isImage else {
            // Anything else (application/pdf, octet-stream, video, audio,
            // …) would have WebKit start downloading the body. Refuse so
            // the static fallback card stays visible.
            decisionHandler(.cancel)
            return
        }

        let expected = navigationResponse.response.expectedContentLength
        let cap = isImage ? Self.imageResponseCap : Self.htmlResponseCap
        if expected > 0 && expected > cap {
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        // Ready stays false; caller keeps the static fallback visible.
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        // Ready stays false; caller keeps the static fallback visible.
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        // Do not flip the ready state on commit — some sites (e.g.
        // baidu.com) commit a navigation but then render blank or stall,
        // leaving the viewer staring at an empty webview. Wait for
        // didFinish which only fires after the document is fully loaded.
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        markReadyImmediately()
    }
}

@MainActor
private func makeWebPreviewConfiguration() -> WKWebViewConfiguration {
    let config = WKWebViewConfiguration()
    config.mediaTypesRequiringUserActionForPlayback = .all
    let prefs = WKWebpagePreferences()
    // The per-navigation `decidePolicyFor:preferences:` callback overrides
    // this on every load by reading the current `previewExecutesJavaScript`
    // setting, so toggling the user preference takes effect immediately
    // without rebuilding the web view.
    prefs.allowsContentJavaScript = true
    config.defaultWebpagePreferences = prefs

    let viewportScript = WKUserScript(
        source: """
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
            meta = document.createElement('meta');
            meta.name = 'viewport';
            document.head.appendChild(meta);
        }
        meta.content = 'width=device-width, initial-scale=1.0, shrink-to-fit=yes';
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )
    let muteScript = WKUserScript(
        source: """
        document.querySelectorAll('video, audio').forEach(function(el) {
            el.pause();
            el.muted = true;
            el.autoplay = false;
            el.removeAttribute('autoplay');
        });
        var obs = new MutationObserver(function() {
            document.querySelectorAll('video, audio').forEach(function(el) {
                el.pause();
                el.muted = true;
                el.autoplay = false;
                el.removeAttribute('autoplay');
            });
        });
        obs.observe(document.body || document.documentElement, { childList: true, subtree: true });
        """,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: false
    )
    config.userContentController.addUserScript(viewportScript)
    config.userContentController.addUserScript(muteScript)
    return config
}

/// Owns one WKWebView for one `WebPreviewView` lifetime. The web view never
/// migrates between containers — that reparenting was the freeze bug.
@MainActor
final class WebPreviewContainerView: NSView {
    let coordinator = WebPreviewCoordinator()
    private let webView: WKWebView

    var readinessHandler: ((Bool) -> Void)? {
        get { coordinator.readinessHandler }
        set { coordinator.readinessHandler = newValue }
    }

    override init(frame frameRect: NSRect) {
        webView = WKWebView(frame: .zero, configuration: makeWebPreviewConfiguration())
        super.init(frame: frameRect)
        // Anti-bot guards on sites like baidu.com serve a blank body to the
        // default WKWebView UA (it contains AppleWebKit without Version/…,
        // matching no real Safari release). Pretend to be a stock macOS
        // Safari so we receive the real page markup.
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = coordinator
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        addSubview(webView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported for WebPreviewContainerView")
    }

    func load(_ url: URL) {
        // Offline mode is a hard cut — we never reach the network for previews
        // when the user has flipped the master switch in Privacy.
        if UserDefaults.standard.bool(forKey: "offlineModeEnabled") {
            webView.stopLoading()
            coordinator.loadedURL = nil
            coordinator.notifyReady(false)
            return
        }
        if coordinator.loadedURL == url { return }
        webView.stopLoading()
        coordinator.loadedURL = url
        coordinator.notifyReady(false)
        webView.load(URLRequest(url: url, timeoutInterval: 15))
    }

    /// NSView 也有 `prepareForReuse()`,这里改名避免意外覆写。
    func stopForReuse() {
        coordinator.loadedURL = nil
        webView.stopLoading()
    }
}

struct WebPreviewView: NSViewRepresentable {
    let url: URL
    var onReadyStateChange: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = WebPreviewContainerView(frame: .zero)
        view.readinessHandler = onReadyStateChange
        view.load(url)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? WebPreviewContainerView else { return }
        view.readinessHandler = onReadyStateChange
        view.load(url)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        guard let view = nsView as? WebPreviewContainerView else { return }
        view.stopForReuse()
    }
}
