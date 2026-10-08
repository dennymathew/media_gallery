import Foundation
import Observation
import UIKit
import WebKit

/// Plays YouTube / Vimeo links through their official embed player APIs inside a `WKWebView`.
@Observable
final class EmbeddedPlayerController: VideoPlayerController {
    let source: VideoSource
    private(set) var state: PlaybackState = .idle {
        didSet { if state == .playing { hasStartedPlayback = true } }
    }
    private(set) var hasStartedPlayback = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    /// YouTube's policies forbid overlays on its player, so it keeps its own controls and no
    /// native chrome is drawn over it. Vimeo is driven by the native overlay.
    let controlMode: ControlMode
    let posterURL: URL?

    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var isPlayerReady = false
    // Desired state, applied once the JS player reports `ready`.
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var isMuted = true

    init(source: VideoSource, posterURL: URL?) {
        self.source = source
        self.posterURL = posterURL ?? source.thumbnailURL
        if case .youtube = source {
            controlMode = .provider
        } else {
            controlMode = .native
        }
    }

    // MARK: VideoPlayerController

    func play() {
        wantsPlay = true
        if isPlayerReady { evaluate("playerPlay()") }
    }

    func pause() {
        wantsPlay = false
        if isPlayerReady { evaluate("playerPause()") }
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        if isPlayerReady { evaluate("playerSetMuted(\(muted))") }
    }

    func seek(to time: Double) {
        currentTime = time
        if isPlayerReady { evaluate("playerSeek(\(time))") }
    }

    func makePlayerView() -> UIView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        let bridge = WebViewBridge()
        bridge.onMessage = { [weak self] message in self?.handle(message) }
        bridge.onLoadFailure = { [weak self] error in self?.state = .failed(error.localizedDescription) }
        configuration.userContentController.add(bridge, name: EmbedHTML.messageHandlerName)

        let webView = WebViewBridge.makeWebView(configuration: configuration, bridge: bridge)
        // Touches reach the page only when the provider's own controls are in charge.
        webView.isUserInteractionEnabled = controlMode == .provider
        self.webView = webView

        if let html = EmbedHTML.html(for: source) {
            state = .loading
            webView.loadHTMLString(html, baseURL: EmbedHTML.baseURL)
        } else {
            state = .failed("Unsupported video link.")
        }
        return webView
    }

    func tearDown() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        isPlayerReady = false
        hasStartedPlayback = false
        state = .idle
    }

    // MARK: Bridge

    private func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        let data = body["data"] as? String

        switch event {
        case "ready":
            isPlayerReady = true
            state = .ready
            evaluate("playerSetMuted(\(isMuted))")
            if wantsPlay { evaluate("playerPlay()") }
        case "playing":
            state = .playing
            // The page may have been swiped away while the player was starting.
            if !wantsPlay { evaluate("playerPause()") }
        case "paused":
            state = .paused
        case "buffering":
            state = .buffering
        case "ended":
            state = .ended
            if wantsPlay { evaluate("playerRestart()") }
        case "time":
            let parts = (data ?? "").split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 {
                currentTime = parts[0]
                if parts[1] > 0 { duration = parts[1] }
            }
        case "error":
            state = .failed(EmbedHTML.errorMessage(for: data))
        default:
            break
        }
    }

    private func evaluate(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}
