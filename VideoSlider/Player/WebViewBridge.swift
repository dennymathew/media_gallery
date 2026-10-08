import Foundation
import UIKit
import WebKit

/// Receives JS messages for a web-based player and keeps the page from navigating away inside the
/// slider. Holds no strong reference back to its controller (the user content controller retains it).
final class WebViewBridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    var onMessage: ((WKScriptMessage) -> Void)?
    var onLoadFailure: ((Error) -> Void)?
    var onLoadFinish: (() -> Void)?

    /// A web view configured for inline, gesture-free media playback with a black, non-scrolling page.
    static func makeWebView(configuration: WKWebViewConfiguration, bridge: WebViewBridge) -> WKWebView {
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsLinkPreview = false
        webView.navigationDelegate = bridge
        webView.uiDelegate = bridge
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        onMessage?(message)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Our own HTML and the provider iframes load freely; a tapped link in the main frame
        // opens outside the app instead of replacing the player.
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        if isMainFrame, navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
            await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // target="_blank" links from inside an iframe (e.g. "Watch on YouTube").
        if let url = navigationAction.request.url {
            UIApplication.shared.open(url)
        }
        return nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadFinish?()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadFailure?(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadFailure?(error)
    }
}
