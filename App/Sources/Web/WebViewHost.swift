import SwiftUI
import UIKit
import WebKit

/// The one web view the app keeps for its whole life: the AIOStreams web app,
/// transparent, over the video.
@MainActor
final class WebViewHost: NSObject, WKNavigationDelegate, WKUIDelegate {
    weak var model: AppModel?
    let bridge: AppBridge
    private(set) var webView: WKWebView!
    private var host: String?

    init(bridge: AppBridge) {
        self.bridge = bridge
        super.init()
        webView = makeWebView()
        bridge.webView = webView
    }

    private func makeWebView() -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: Scripts.bridge(identity: AppBridge.identity()),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        controller.addUserScript(WKUserScript(
            source: Scripts.chrome,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        let handler = ScriptHandler(host: self)
        controller.add(handler, name: "aiostreams")
        controller.add(handler, name: "aiostreamsNav")
        controller.add(handler, name: "aiostreamsPlayer")
        configuration.userContentController = controller

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.scrollView.bounces = false
        view.allowsBackForwardNavigationGestures = true
        view.allowsLinkPreview = false
        view.isInspectable = true
        view.navigationDelegate = self
        view.uiDelegate = self
        return view
    }

    func load(_ url: URL) {
        host = url.host
        webView.load(URLRequest(url: url))
    }

    func tap(navItem id: String) {
        let escaped = id.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        webView.evaluateJavaScript("window.__aiostreamsTap && window.__aiostreamsTap('\(escaped)');") { _, _ in }
    }

    /// No swipe back through the history while a video plays: it would close the player.
    func playerActive(_ active: Bool) {
        webView.allowsBackForwardNavigationGestures = !active
    }

    fileprivate func received(_ message: WKScriptMessage) {
        guard let body = message.body as? String else { return }
        switch message.name {
        case "aiostreams": bridge.receive(json: body)
        case "aiostreamsNav": model?.updateNav(json: body)
        case "aiostreamsPlayer": model?.updatePlayerChrome(json: body)
        default: break
        }
    }

    // MARK: WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else { return decisionHandler(.cancel) }
        if url.scheme == "aiostreams" {
            model?.open(link: url)
            return decisionHandler(.cancel)
        }
        let inApp = url.host == nil || url.host == host || url.scheme == "about" || url.scheme == "blob" || url.scheme == "data"
        if !inApp, navigationAction.targetFrame?.isMainFrame != false {
            UIApplication.shared.open(url)
            return decisionHandler(.cancel)
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(error)
    }

    private func failed(_ error: Error) {
        let code = (error as NSError).code
        // A navigation replaced by another one isn't a failure.
        if code == NSURLErrorCancelled || code == 102 { return }
        model?.loadError = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        model?.reload()
    }

    // MARK: WKUIDelegate

    /// `window.open` and `target=_blank` links leave the app.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url { UIApplication.shared.open(url) }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        guard let top = Orientation.topController else { return completionHandler() }
        top.present(alert, animated: true)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Annulla", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        guard let top = Orientation.topController else { return completionHandler(false) }
        top.present(alert, animated: true)
    }
}

/// Holds the host weakly: the content controller keeps its handlers for good.
private final class ScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var host: WebViewHost?

    init(host: WebViewHost) {
        self.host = host
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { host?.received(message) }
    }
}

/// Puts the app's web view in SwiftUI.
struct WebViewContainer: UIViewRepresentable {
    let host: WebViewHost

    func makeUIView(context: Context) -> WKWebView { host.webView }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
