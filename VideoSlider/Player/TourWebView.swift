import SwiftUI
import UIKit
import WebKit

/// Hosts a virtual tour page (e.g. `https://tour.ogulo.com/<code>`) in a web view. Uses the default
/// persistent website data store, so the provider's cookie-consent choice is remembered.
struct TourWebView: UIViewRepresentable {
    let url: URL
    let isInteractive: Bool
    var onLoaded: () -> Void = {}
    var onFailed: (String) -> Void = { _ in }

    func makeCoordinator() -> WebViewBridge { WebViewBridge() }

    func makeUIView(context: Context) -> WKWebView {
        let bridge = context.coordinator
        bridge.onLoadFinish = onLoaded
        bridge.onLoadFailure = { onFailed($0.localizedDescription) }

        let webView = WebViewBridge.makeWebView(configuration: WKWebViewConfiguration(), bridge: bridge)
        webView.isUserInteractionEnabled = isInteractive
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.isUserInteractionEnabled = isInteractive
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: WebViewBridge) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }
}
