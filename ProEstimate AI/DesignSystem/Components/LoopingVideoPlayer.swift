import AVFoundation
import SwiftUI
import UIKit

/// SwiftUI wrapper around an `AVPlayerLayer` that plays a bundled video
/// silently and loops seamlessly. The looping is implemented with
/// `AVPlayerLooper` over an `AVQueuePlayer` (not by observing
/// `.AVPlayerItemDidPlayToEndTime` and re-seeking) so the wrap-around
/// transition is gapless — the next iteration is queued before the
/// current one ends.
///
/// The player lives inside a UIView whose backing layer is the
/// `AVPlayerLayer`, which guarantees the video tracks the view's bounds
/// without an extra layout pass on every frame.
///
/// `isPlaying` is bound from SwiftUI so the host can pause playback when
/// the parent view disappears (saves battery + decode work). The player
/// auto-resumes whenever the binding flips back to `true`.
struct LoopingVideoPlayer: UIViewRepresentable {
    let resourceName: String
    let resourceExtension: String
    @Binding var isPlaying: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(resourceName: resourceName, resourceExtension: resourceExtension)
    }

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.backgroundColor = .black
        view.attach(coordinator: context.coordinator)
        if isPlaying {
            context.coordinator.play()
        }
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if isPlaying {
            context.coordinator.play()
        } else {
            context.coordinator.pause()
        }
    }

    static func dismantleUIView(_ uiView: PlayerContainerView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    // MARK: - Coordinator

    final class Coordinator {
        private let queuePlayer: AVQueuePlayer
        private var looper: AVPlayerLooper?

        init(resourceName: String, resourceExtension: String) {
            self.queuePlayer = AVQueuePlayer()
            self.queuePlayer.isMuted = true
            self.queuePlayer.actionAtItemEnd = .advance
            self.queuePlayer.automaticallyWaitsToMinimizeStalling = true

            guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
                // Fall through with a no-op player; the layer just renders
                // its background color, so the card still has correct
                // proportions if the asset is ever missing in dev.
                return
            }
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            self.looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        }

        var player: AVPlayer { queuePlayer }

        func play() {
            // `rate == 0` is the only reliable cross-iOS-version check
            // for "currently paused" — `timeControlStatus` flips to
            // `.waitingToPlayAtSpecifiedRate` while buffering, which we
            // don't want to treat as a paused state.
            if queuePlayer.rate == 0 {
                queuePlayer.play()
            }
        }

        func pause() {
            if queuePlayer.rate != 0 {
                queuePlayer.pause()
            }
        }

        func tearDown() {
            queuePlayer.pause()
            queuePlayer.removeAllItems()
            looper = nil
        }
    }

    // MARK: - Container View

    /// `UIView` whose backing layer is `AVPlayerLayer`. Using
    /// `+ layerClass` avoids creating a second sublayer and keeps the
    /// video pinned to the view's bounds via Auto Layout.
    final class PlayerContainerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }

        private var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

        func attach(coordinator: Coordinator) {
            playerLayer.player = coordinator.player
            playerLayer.videoGravity = .resizeAspectFill
        }
    }
}
