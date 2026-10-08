import SwiftUI

/// Native playback controls drawn over any player (web or AVPlayer), so every source looks the same.
/// Tap toggles visibility; while playing they auto-hide after a few seconds.
struct PlayerControlsOverlay<Controller: VideoPlayerController>: View {
    let controller: Controller

    @State private var isVisible = true
    @State private var scrubTime: Double?
    @State private var interactions = 0

    private var isPlaying: Bool { controller.state.isPlaying }
    private var displayedTime: Double { scrubTime ?? controller.currentTime }

    var body: some View {
        ZStack {
            // Full-size tap target; also keeps touches away from the (non-interactive) player.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { setVisible(!isVisible) }

            if isVisible {
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title)
                        .frame(width: 56, height: 56)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(isPlaying ? "Pause" : "Play")
                .transition(.opacity)

                VStack {
                    Spacer()
                    scrubber
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .task(id: AutoHideKey(isVisible: isVisible, isPlaying: isPlaying, interactions: interactions)) {
            guard isVisible, isPlaying, scrubTime == nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { isVisible = false }
        }
    }

    private var scrubber: some View {
        HStack(spacing: 12) {
            Text(Self.format(displayedTime))
            Slider(
                value: Binding(get: { displayedTime }, set: { scrubTime = $0 }),
                in: 0...max(controller.duration, 1)
            ) { editing in
                if !editing, let scrubTime {
                    controller.seek(to: scrubTime)
                    self.scrubTime = nil
                }
                interactions += 1
            }
            .disabled(controller.duration <= 0)
            Text("-" + Self.format(max(controller.duration - displayedTime, 0)))
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: .capsule)
        .padding(.horizontal, 16)
        // Clear of the slider's page indicator and the home indicator.
        .padding(.bottom, 100)
    }

    private func togglePlayback() {
        isPlaying ? controller.pause() : controller.play()
        interactions += 1
    }

    private func setVisible(_ visible: Bool) {
        isVisible = visible
        interactions += 1
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

private struct AutoHideKey: Equatable {
    let isVisible: Bool
    let isPlaying: Bool
    let interactions: Int
}
