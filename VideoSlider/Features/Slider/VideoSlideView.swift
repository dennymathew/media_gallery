import SwiftUI

struct VideoSlideView: View {
    let item: SliderItem.VideoItem
    let isActive: Bool
    let isNearby: Bool
    let isMuted: Bool

    var body: some View {
        switch item.source {
        case .youtube, .vimeo:
            PlayerSlide(
                controller: EmbeddedPlayerController(source: item.source, posterURL: item.thumbnailURL),
                // Keeps the slider's mute button and page indicator off the player (YouTube forbids
                // overlays, and provider branding sits at the web view's edges).
                playerInsets: Self.webPlayerInsets,
                isActive: isActive,
                isNearby: isNearby,
                isMuted: isMuted
            )
        case .embed(let pageURL):
            PlayerSlide(
                controller: GenericEmbedController(pageURL: pageURL, embedURL: item.embedURL, posterURL: item.thumbnailURL),
                playerInsets: Self.webPlayerInsets,
                isActive: isActive,
                isNearby: isNearby,
                isMuted: isMuted
            )
        case .direct(let url):
            PlayerSlide(
                controller: NativePlayerController(url: url),
                playerInsets: EdgeInsets(),
                isActive: isActive,
                isNearby: isNearby,
                isMuted: isMuted
            )
        case .unsupported(let url):
            UnsupportedVideoView(url: url)
        }
    }

    private static let webPlayerInsets = EdgeInsets(top: 120, leading: 0, bottom: 110, trailing: 0)
}

/// Shared chrome for any player: poster while loading, native controls, error state, and
/// play/pause/mute driven by whether the page is the visible one.
private struct PlayerSlide<Controller: VideoPlayerController>: View {
    @State private var controller: Controller
    let playerInsets: EdgeInsets
    let isActive: Bool
    let isNearby: Bool
    let isMuted: Bool

    init(controller: Controller, playerInsets: EdgeInsets, isActive: Bool, isNearby: Bool, isMuted: Bool) {
        // Controllers are cheap to create; the player itself is only built in `makePlayerView()`.
        _controller = State(initialValue: controller)
        self.playerInsets = playerInsets
        self.isActive = isActive
        self.isNearby = isNearby
        self.isMuted = isMuted
    }

    var body: some View {
        ZStack {
            Color.black

            if isNearby {
                PlayerHostView(controller: controller)
                    .padding(playerInsets)
            }

            if !isNearby || showsPoster {
                poster
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if case .failed(let message) = controller.state {
                ContentUnavailableView("Video unavailable", systemImage: "play.slash", description: Text(message))
                    .foregroundStyle(.white)
                    .background(.black)
            } else if isNearby, !showsPoster, controller.controlMode == .native {
                PlayerControlsOverlay(controller: controller)
            }
        }
        .animation(.easeOut(duration: 0.25), value: showsPoster)
        .onChange(of: isNearby, initial: true) { syncPlayback() }
        .onChange(of: isActive) { syncPlayback() }
        .onChange(of: isMuted, initial: true) { controller.setMuted(isMuted) }
    }

    /// Poster stays up until the first frame plays (also on neighbouring pages, so a swipe never
    /// reveals a black player). Never drawn over a provider-controlled player such as YouTube,
    /// which shows its own thumbnail and must not be covered.
    private var showsPoster: Bool {
        if case .failed = controller.state { return false }
        return controller.controlMode == .native && !controller.hasStartedPlayback
    }

    private var poster: some View {
        ZStack {
            Color.black
            if let posterURL = controller.posterURL {
                AsyncImage(url: posterURL) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    Color.black
                }
            }
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        }
    }

    private func syncPlayback() {
        if isActive && isNearby {
            controller.play()
        } else {
            controller.pause()
        }
    }
}

private struct UnsupportedVideoView: View {
    let url: URL

    var body: some View {
        ContentUnavailableView {
            Label("Can't play this video here", systemImage: "play.slash")
        } description: {
            Text(url.host() ?? url.absoluteString)
        } actions: {
            Link("Open in Browser", destination: url)
                .buttonStyle(.glass)
        }
        .foregroundStyle(.white)
    }
}
