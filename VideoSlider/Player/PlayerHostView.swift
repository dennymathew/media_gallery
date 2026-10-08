import SwiftUI
import UIKit

/// Hosts a controller's player view in SwiftUI and releases the player when removed.
struct PlayerHostView: UIViewRepresentable {
    let controller: any VideoPlayerController

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        let playerView = controller.makePlayerView()
        playerView.frame = container.bounds
        playerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(playerView)
        context.coordinator.controller = controller
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.controller?.tearDown()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var controller: (any VideoPlayerController)?
    }
}
