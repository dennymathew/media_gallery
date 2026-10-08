import Foundation
import Observation
import UIKit
import WebKit

/// Plays a video page from any platform: resolves it to an embeddable player (oEmbed), hosts that
/// player in an iframe, and drives the provider's HTML5 `<video>` element through `VideoBridgeScript`.
///
/// Falls back to the provider's own, interactive UI when no `<video>` can be reached, or when one is
/// found but won't start (some players only attach their stream after a real tap on their own play
/// button). If that video then starts playing, control is handed back to the native overlay.
@Observable
final class GenericEmbedController: VideoPlayerController {
    let pageURL: URL
    private(set) var state: PlaybackState = .idle {
        didSet { if state == .playing { hasStartedPlayback = true } }
    }
    private(set) var hasStartedPlayback = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var controlMode: ControlMode = .native
    private(set) var posterURL: URL?

    /// How long to wait for the bridge to find a `<video>` before handing over to the provider UI.
    private static let discoveryTimeout: Duration = .seconds(6)
    /// How long a found `<video>` may take to start after we asked it to play. Some players ignore a
    /// programmatic play() and only start from their own button; handing over to their UI is harmless
    /// because control comes back to the native overlay as soon as the video plays.
    private static let playbackStartTimeout: Duration = .seconds(8)

    @ObservationIgnored private let embedURL: URL?
    /// False when no embeddable player was found and the page itself was loaded.
    @ObservationIgnored private var isResolvedPlayer = true
    @ObservationIgnored private var webView: WKWebView?
    @ObservationIgnored private var videoFrame: WKFrameInfo?
    @ObservationIgnored private var videoFrameKey: String?
    @ObservationIgnored private var videoArea = 0
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var discoveryTask: Task<Void, Never>?
    @ObservationIgnored private var playbackStartTask: Task<Void, Never>?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var isMuted = true

    init(pageURL: URL, embedURL: URL?, posterURL: URL?) {
        self.pageURL = pageURL
        self.embedURL = embedURL
        self.posterURL = posterURL
    }

    // MARK: VideoPlayerController

    func play() {
        wantsPlay = true
        send("__vsb.play()")
        startPlaybackStartTimeout()
    }

    func pause() {
        wantsPlay = false
        playbackStartTask?.cancel()
        send("__vsb.pause()")
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        send("__vsb.setMuted(\(muted))")
    }

    func seek(to time: Double) {
        currentTime = time
        send("__vsb.seek(\(time))")
    }

    func makePlayerView() -> UIView {
        if let webView { return webView }

        let configuration = WKWebViewConfiguration()
        let bridge = WebViewBridge()
        bridge.onMessage = { [weak self] message in self?.handle(message) }
        bridge.onLoadFailure = { [weak self] _ in self?.fallBackToProviderUI() }
        configuration.userContentController.addUserScript(VideoBridgeScript.userScript)
        configuration.userContentController.add(
            bridge,
            contentWorld: VideoBridgeScript.contentWorld,
            name: VideoBridgeScript.messageHandlerName
        )

        let webView = WebViewBridge.makeWebView(configuration: configuration, bridge: bridge)
        // Our overlay owns the controls; touches only reach the page in provider mode.
        webView.isUserInteractionEnabled = false
        self.webView = webView
        state = .loading

        loadTask = Task { [weak self, pageURL, embedURL, posterURL] in
            let resolved = await EmbedResolver.shared.resolve(pageURL: pageURL, embedURL: embedURL, thumbnailURL: posterURL)
            guard let self, !Task.isCancelled, let webView = self.webView else { return }
            if self.posterURL == nil { self.posterURL = resolved.thumbnailURL }
            self.isResolvedPlayer = resolved.isPlayer
            if resolved.isPlayer {
                webView.loadHTMLString(EmbedHTML.genericHost(playerURL: resolved.playerURL), baseURL: EmbedHTML.baseURL)
            } else {
                // No embeddable player found: load the page itself; the bridge still looks for a <video>.
                webView.load(URLRequest(url: resolved.playerURL))
            }
            self.startDiscoveryTimeout()
        }
        return webView
    }

    func tearDown() {
        loadTask?.cancel()
        discoveryTask?.cancel()
        playbackStartTask?.cancel()
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.configuration.userContentController.removeAllUserScripts()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        webView = nil
        videoFrame = nil
        videoFrameKey = nil
        videoArea = 0
        hasStartedPlayback = false
        controlMode = .native
        state = .idle
    }

    // MARK: Bridge

    private func handle(_ message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
        let area = body["area"] as? Int ?? 0

        if event == "videoFound" {
            // Several frames may report a video (ads, previews); keep the largest.
            guard videoFrame == nil || area >= videoArea || Self.key(for: message.frameInfo) == videoFrameKey else { return }
            videoFrame = message.frameInfo
            videoFrameKey = Self.key(for: message.frameInfo)
            videoArea = area
            discoveryTask?.cancel()
            if state.isLoading { state = .ready }
            send("__vsb.setMuted(\(isMuted))")
            if wantsPlay { play() } else { send("__vsb.pause()") }
        }

        // Ignore events from frames other than the one we're controlling.
        guard Self.key(for: message.frameInfo) == videoFrameKey else { return }

        currentTime = body["currentTime"] as? Double ?? currentTime
        if let reported = body["duration"] as? Double, reported > 0 { duration = reported }

        switch event {
        case "playing":
            playbackStartTask?.cancel()
            state = .playing
            // Started from the provider's own play button: hand control back to the native overlay.
            if controlMode == .provider { setControlMode(.native) }
            if !wantsPlay { send("__vsb.pause()") }
        case "paused":
            state = .paused
        case "buffering":
            state = .buffering
        case "ended":
            state = .ended
            if wantsPlay {
                send("__vsb.seek(0)")
                send("__vsb.play()")
            }
        case "blocked", "noSource", "error":
            // The provider's own play button is needed, autoplay was refused, or the video failed:
            // let the provider's UI take over (it knows how to start or explain its own video).
            fallBackToProviderUI()
        default:
            break
        }
    }

    private func send(_ script: String) {
        // Also used in provider mode, so swiping away still pauses a video the user started there.
        guard let webView, let videoFrame else { return }
        webView.evaluateJavaScript(script, in: videoFrame, in: VideoBridgeScript.contentWorld) { [weak self] result in
            if case .failure = result {
                // The frame went away (provider reloaded it); wait for the bridge to report again.
                self?.videoFrame = nil
                self?.videoFrameKey = nil
                self?.videoArea = 0
            }
        }
    }

    /// Each message carries a fresh `WKFrameInfo` object, so frames are identified by origin + URL.
    private static func key(for frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        return "\(frame.isMainFrame)|\(origin.protocol)://\(origin.host):\(origin.port)|\(frame.request.url?.absoluteString ?? "")"
    }

    private func startDiscoveryTimeout() {
        discoveryTask?.cancel()
        discoveryTask = Task { [weak self] in
            try? await Task.sleep(for: Self.discoveryTimeout)
            guard let self, !Task.isCancelled, self.videoFrame == nil else { return }
            if self.isResolvedPlayer {
                self.fallBackToProviderUI()
            } else {
                // Neither oEmbed nor the page itself offers a video; don't show an arbitrary web page.
                self.state = .failed("No playable video found on this page.")
            }
        }
    }

    private func startPlaybackStartTimeout() {
        playbackStartTask?.cancel()
        guard videoFrame != nil, controlMode == .native, state != .playing else { return }
        playbackStartTask = Task { [weak self] in
            try? await Task.sleep(for: Self.playbackStartTimeout)
            guard let self, !Task.isCancelled, self.wantsPlay, self.state != .playing else { return }
            self.fallBackToProviderUI()
        }
    }

    private func setControlMode(_ mode: ControlMode) {
        controlMode = mode
        // Touches reach the page only while the provider's UI is in charge.
        webView?.isUserInteractionEnabled = mode == .provider
    }

    private func fallBackToProviderUI() {
        guard controlMode == .native else { return }
        setControlMode(.provider)
        if state.isLoading { state = .ready }
        // Reveal the provider's player (with its own play button) instead of keeping the poster up.
        hasStartedPlayback = true
    }
}
