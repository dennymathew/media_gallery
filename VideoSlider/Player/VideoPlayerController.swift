import Observation
import UIKit

enum PlaybackState: Equatable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed(String)

    /// True until the player is able to show its own UI / first frame.
    var isLoading: Bool { self == .idle || self == .loading }
    var isPlaying: Bool { self == .playing || self == .buffering }
}

/// Who draws the playback controls.
enum ControlMode: Equatable {
    /// Our SwiftUI overlay drives the player; the player view itself takes no touches.
    case native
    /// The provider's own UI is shown and interactive, and nothing is drawn over the player: either
    /// we couldn't get control of it, or the provider's terms forbid overlays (YouTube).
    case provider
}

/// Common surface for every way we can play a video (official embed adapters, the generic
/// web `<video>` bridge, or native AVPlayer), so the slider doesn't care where a video comes from.
protocol VideoPlayerController: AnyObject, Observable {
    var state: PlaybackState { get }
    /// Becomes true once the player's own view should be revealed (normally the first played frame);
    /// the poster covers it until then.
    var hasStartedPlayback: Bool { get }
    var currentTime: Double { get }
    var duration: Double { get }
    var controlMode: ControlMode { get }
    var posterURL: URL? { get }

    func play()
    func pause()
    func setMuted(_ muted: Bool)
    func seek(to time: Double)

    /// Returns the view rendering the video, creating the underlying player on first call.
    func makePlayerView() -> UIView
    /// Releases the underlying player. `makePlayerView()` may be called again afterwards.
    func tearDown()
}
