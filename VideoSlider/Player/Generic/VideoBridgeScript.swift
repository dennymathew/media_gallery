import WebKit

/// JS injected into every frame (including cross-origin provider iframes) that finds the page's
/// HTML5 `<video>` element and bridges it to Swift. Runs in its own content world, so it is invisible
/// to the provider's scripts and they can't tamper with it.
///
/// JS → Swift: `messageHandlers.videoBridge.postMessage({ event, currentTime, duration, area })`
///   events: videoFound, playing, paused, buffering, ended, time, blocked, noSource, error
/// Swift → JS (in the reporting frame): `__vsb.play()`, `pause()`, `setMuted(bool)`, `seek(seconds)`
enum VideoBridgeScript {
    static let messageHandlerName = "videoBridge"
    static let contentWorld = WKContentWorld.world(name: "VideoBridge")

    static var userScript: WKUserScript {
        WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: contentWorld)
    }

    private static let source = """
    (function () {
      if (window.__vsb) { return; }
      var handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(messageHandlerName);
      if (!handler) { return; }

      var video = null;
      var desiredMuted = true;
      var lastTimePost = 0;

      function area(v) { var r = v.getBoundingClientRect(); return Math.round(r.width * r.height); }

      function post(event) {
        handler.postMessage({
          event: event,
          currentTime: video ? (video.currentTime || 0) : 0,
          duration: video && isFinite(video.duration) ? video.duration : 0,
          area: video ? area(video) : 0
        });
      }

      var listeners = {
        playing: function () { post("playing"); },
        pause: function () { post("paused"); },
        waiting: function () { post("buffering"); },
        ended: function () { post("ended"); },
        error: function () { post("error"); },
        durationchange: function () { post("time"); },
        loadedmetadata: function () { post("time"); },
        seeked: function () { post("time"); },
        timeupdate: function () {
          var now = Date.now();
          if (now - lastTimePost > 250) { lastTimePost = now; post("time"); }
        }
      };

      function attach(v) {
        if (video) { for (var name in listeners) { video.removeEventListener(name, listeners[name]); } }
        video = v;
        video.playsInline = true;
        video.setAttribute("playsinline", "");
        video.muted = desiredMuted;
        for (var name in listeners) { video.addEventListener(name, listeners[name]); }
        post("videoFound");
        if (!video.paused) { post("playing"); }
      }

      // Players built as web components keep their <video> in a shadow root, which neither
      // querySelectorAll nor a document-level MutationObserver can see; walk and watch open ones.
      var observedRoots = new WeakSet();
      var pending = null;
      var observer = new MutationObserver(function () {
        if (pending) { return; }
        pending = setTimeout(function () { pending = null; pick(); }, 200);
      });

      function watch(root) {
        if (observedRoots.has(root)) { return; }
        observedRoots.add(root);
        observer.observe(root, { childList: true, subtree: true });
      }

      function collectVideos(root, out) {
        var videos = root.querySelectorAll("video");
        for (var i = 0; i < videos.length; i++) { out.push(videos[i]); }
        var elements = root.querySelectorAll("*");
        for (var j = 0; j < elements.length; j++) {
          var shadow = elements[j].shadowRoot;
          if (shadow) { watch(shadow); collectVideos(shadow, out); }
        }
        return out;
      }

      // The main video is the largest one; providers often add small preview/ad elements too.
      function pick() {
        var best = null;
        var videos = collectVideos(document, []);
        for (var i = 0; i < videos.length; i++) {
          if (!best || area(videos[i]) > area(best)) { best = videos[i]; }
        }
        if (best && best !== video) { attach(best); }
      }

      watch(document.documentElement);
      pick();

      window.__vsb = {
        play: function () {
          if (!video) { return; }
          // Some players only attach their stream after a real tap on their own play button.
          // Forcing play() on a source-less element would wedge them, so let Swift hand over instead.
          if (video.networkState === HTMLMediaElement.NETWORK_NO_SOURCE) { post("noSource"); return; }
          video.muted = desiredMuted;
          var p = video.play();
          if (p && p.catch) {
            // AbortError just means a pause() interrupted this play(); anything else is a real refusal.
            p.catch(function (e) { if (!e || e.name !== "AbortError") { post("blocked"); } });
          }
        },
        pause: function () { if (video) { video.pause(); } },
        setMuted: function (muted) { desiredMuted = muted; if (video) { video.muted = muted; } },
        seek: function (t) { if (video) { video.currentTime = t; } }
      };
    })();
    """
}
