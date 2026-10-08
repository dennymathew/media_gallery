import Foundation

/// HTML pages hosting the official YouTube / Vimeo embed players, with a tiny JS bridge.
///
/// JS → Swift: `window.webkit.messageHandlers.player.postMessage({ event, data })`
///   events: ready, playing, paused, buffering, ended, error
///   plus `time` with data "currentTime,duration"
/// Swift → JS: `playerPlay()`, `playerPause()`, `playerSetMuted(bool)`, `playerSeek(seconds)`, `playerRestart()`
///
/// YouTube keeps its own controls: its policies forbid drawing anything over the embedded player
/// (https://developers.google.com/youtube/terms/required-minimum-functionality), so the slider
/// only drives it through the API. Vimeo runs with `controls=0` under the slider's native controls.
enum EmbedHTML {
    static let messageHandlerName = "player"

    /// YouTube refuses to play embeds without a valid HTTP referer/origin (errors 152/153),
    /// so pages are loaded with an https base URL identifying the app.
    static let baseURL: URL = {
        let bundleID = (Bundle.main.bundleIdentifier ?? "com.example.videoslider").lowercased()
        return URL(string: "https://\(bundleID)") ?? URL(string: "https://com.example.videoslider")!
    }()

    static func html(for source: VideoSource) -> String? {
        switch source {
        case .youtube(let id):
            guard let id = sanitized(id) else { return nil }
            return youtube(videoID: id)
        case .vimeo(let id, let hash):
            guard let id = sanitized(id) else { return nil }
            return vimeo(videoID: id, hash: hash.flatMap { sanitized($0) })
        case .direct, .embed, .unsupported:
            return nil
        }
    }

    /// IDs are interpolated into HTML/JS, so only allow the characters real IDs use.
    private static func sanitized(_ value: String) -> String? {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !value.isEmpty, value.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return value
    }

    private static let head = """
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          html, body { margin: 0; padding: 0; width: 100%; height: 100%; background: #000; overflow: hidden; }
          #player, iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
        </style>
        <script>
          function send(event, data) {
            window.webkit.messageHandlers.\(messageHandlerName).postMessage({ event: event, data: data === undefined ? null : String(data) });
          }
        </script>
        """

    private static func youtube(videoID: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>\(head)</head>
        <body>
          <div id="player"></div>
          <script>
            var player;
            var timer = null;
            var states = { "0": "ended", "1": "playing", "2": "paused", "3": "buffering" };

            // The IFrame API has no time events, so poll while playing.
            function sendTime() { if (player && player.getCurrentTime) { send("time", player.getCurrentTime() + "," + player.getDuration()); } }
            function startTimer() { if (!timer) { timer = setInterval(sendTime, 500); } }
            function stopTimer() { clearInterval(timer); timer = null; sendTime(); }

            function onYouTubeIframeAPIReady() {
              player = new YT.Player("player", {
                width: "100%",
                height: "100%",
                videoId: "\(videoID)",
                playerVars: {
                  playsinline: 1, autoplay: 0, mute: 1, controls: 1, rel: 0,
                  modestbranding: 1, enablejsapi: 1, fs: 0, disablekb: 1, iv_load_policy: 3,
                  origin: "\(baseURL.absoluteString)"
                },
                events: {
                  onReady: function () { send("ready"); sendTime(); },
                  onStateChange: function (e) {
                    if (e.data === 1) { startTimer(); } else { stopTimer(); }
                    var s = states[String(e.data)];
                    if (s) { send(s); }
                  },
                  onError: function (e) { send("error", "youtube:" + e.data); }
                }
              });
            }

            function playerPlay() { if (player && player.playVideo) { player.playVideo(); } }
            function playerPause() { if (player && player.pauseVideo) { player.pauseVideo(); } }
            function playerSetMuted(muted) { if (!player || !player.mute) { return; } muted ? player.mute() : player.unMute(); }
            function playerSeek(t) { if (player && player.seekTo) { player.seekTo(t, true); sendTime(); } }
            function playerRestart() { if (player && player.seekTo) { player.seekTo(0, true); player.playVideo(); } }
          </script>
          <script src="https://www.youtube.com/iframe_api" onerror="send('error', 'network')"></script>
        </body>
        </html>
        """
    }

    private static func vimeo(videoID: String, hash: String?) -> String {
        let hashParam = hash.map { "h=\($0)&" } ?? ""
        let src = "https://player.vimeo.com/video/\(videoID)?\(hashParam)playsinline=1&muted=1&autoplay=0&controls=0&dnt=1&title=0&byline=0&portrait=0"
        return """
        <!DOCTYPE html>
        <html>
        <head>\(head)</head>
        <body>
          <iframe id="player" src="\(src)" allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>
          <script src="https://player.vimeo.com/api/player.js" onerror="send('error', 'network')"></script>
          <script>
            var player = new Vimeo.Player(document.getElementById("player"));
            player.ready()
              .then(function () { send("ready"); return Promise.all([player.getCurrentTime(), player.getDuration()]); })
              .then(function (t) { send("time", t[0] + "," + t[1]); })
              .catch(function (e) { send("error", "vimeo:" + e.name); });
            player.on("timeupdate", function (d) { send("time", d.seconds + "," + d.duration); });
            player.on("play", function () { send("playing"); });
            player.on("pause", function () { send("paused"); });
            player.on("bufferstart", function () { send("buffering"); });
            player.on("bufferend", function () { send("playing"); });
            player.on("ended", function () { send("ended"); });
            // Vimeo also emits recoverable errors here (e.g. AbortError when a play is interrupted
            // by pause); only the ones that mean "this video will never play" are fatal.
            var fatalErrors = ["PrivacyError", "NotFoundError", "PasswordError"];
            player.on("error", function (e) { if (fatalErrors.indexOf(e.name) !== -1) { send("error", "vimeo:" + e.name); } });

            // play() rejects when autoplay is blocked; that's not fatal, the user can tap play.
            function playerPlay() { player.play().catch(function () {}); }
            function playerPause() { player.pause().catch(function () {}); }
            function playerSetMuted(muted) { player.setMuted(muted).catch(function () {}); }
            function playerSeek(t) { player.setCurrentTime(t).catch(function () {}); }
            function playerRestart() { player.setCurrentTime(0).then(function () { return player.play(); }).catch(function () {}); }
          </script>
        </body>
        </html>
        """
    }

    /// Black page hosting any provider's player URL in a full-screen iframe.
    static func genericHost(playerURL: URL) -> String {
        let src = playerURL.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!DOCTYPE html>
        <html>
        <head>\(head)</head>
        <body>
          <iframe src="\(src)" allow="autoplay; fullscreen; encrypted-media; picture-in-picture" allowfullscreen></iframe>
        </body>
        </html>
        """
    }

    static func errorMessage(for code: String?) -> String {
        switch code {
        case "youtube:2": "Invalid video id."
        case "youtube:5": "This video can't be played in an HTML5 player."
        case "youtube:100": "Video not found or removed."
        case "youtube:101", "youtube:150": "The owner doesn't allow this video to be embedded."
        case "youtube:152", "youtube:153": "YouTube rejected the embed (missing app referer)."
        case "vimeo:PrivacyError", "vimeo:PasswordError": "This Vimeo video is private or can't be embedded."
        case "vimeo:NotFoundError": "Video not found or removed."
        case "network": "Couldn't reach the video provider."
        default: "This video can't be played (\(code ?? "unknown"))."
        }
    }
}
