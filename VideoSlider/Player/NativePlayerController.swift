import AVFoundation
import Combine
import Foundation
import Observation
import UIKit

/// Plays direct media URLs (HLS / MP4) with AVPlayer, looping.
@Observable
final class NativePlayerController: VideoPlayerController {
    let url: URL
    private(set) var state: PlaybackState = .idle {
        didSet { if state == .playing { hasStartedPlayback = true } }
    }
    private(set) var hasStartedPlayback = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    let controlMode: ControlMode = .native
    let posterURL: URL? = nil

    @ObservationIgnored private var player: AVQueuePlayer?
    @ObservationIgnored private var looper: AVPlayerLooper?
    @ObservationIgnored private var cancellables: Set<AnyCancellable> = []
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var wantsPlay = false
    @ObservationIgnored private var isMuted = true

    init(url: URL) {
        self.url = url
    }

    func play() {
        wantsPlay = true
        player?.play()
    }

    func pause() {
        wantsPlay = false
        player?.pause()
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
        player?.isMuted = muted
    }

    func seek(to time: Double) {
        currentTime = time
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func makePlayerView() -> UIView {
        let view = PlayerLayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player ?? makePlayer()
        return view
    }

    func tearDown() {
        cancellables.removeAll()
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
        hasStartedPlayback = false
        state = .idle
    }

    private func makePlayer() -> AVQueuePlayer {
        let player = AVQueuePlayer()
        player.isMuted = isMuted
        let looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        state = .loading

        // KVO can fire off the main thread; hop to main before touching state.
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in self?.update(timeControlStatus: status) }
            .store(in: &cancellables)
        looper.publisher(for: \.status)
            .filter { $0 == .failed }
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak looper] _ in
                self?.state = .failed(looper?.error?.localizedDescription ?? "Couldn't load the video.")
            }
            .store(in: &cancellables)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let player = self.player else { return }
                self.currentTime = time.seconds
                if let itemDuration = player.currentItem?.duration.seconds, itemDuration.isFinite {
                    self.duration = itemDuration
                }
            }
        }

        self.player = player
        self.looper = looper
        if wantsPlay { player.play() }
        return player
    }

    private func update(timeControlStatus: AVPlayer.TimeControlStatus) {
        if case .failed = state { return }
        switch timeControlStatus {
        case .playing: state = .playing
        case .waitingToPlayAtSpecifiedRate: state = state.isLoading ? .loading : .buffering
        case .paused: state = state.isLoading ? .loading : .paused
        @unknown default: break
        }
    }
}

private final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
