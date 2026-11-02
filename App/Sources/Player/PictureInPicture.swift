import AetherEngine
import AVFoundation
import AVKit
import Combine
import CoreMedia

/// Picture in picture around whichever layer the engine draws into: AVPlayer's on
/// the native route, the sample-buffer layer on the software one. It starts by
/// itself when the app goes to the background while a video plays.
@MainActor
final class PictureInPicture: NSObject, ObservableObject {
    @Published private(set) var possible = false
    @Published private(set) var isActive = false

    /// The page's `now-playing` says whether this item may leave the app in a window.
    var allowed = true {
        didSet { controller?.canStartPictureInPictureAutomaticallyFromInline = allowed }
    }

    private let engine: AetherEngine
    private weak var bridge: AppBridge?
    private var controller: AVPictureInPictureController?
    private var possibleObservation: NSKeyValueObservation?
    private var externalObservation: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()

    init(engine: AetherEngine, bridge: AppBridge) {
        self.engine = engine
        self.bridge = bridge
        super.init()
        engine.$currentAVPlayer.onMain { [weak self] player in
            self?.watchExternalPlayback(player)
            self?.rebuild()
        }.store(in: &cancellables)
        engine.$softwarePiPSource.onMain { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)
    }

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }

    private func rebuild() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        // The window survives the engine's in-place item swaps.
        if controller?.isPictureInPictureActive == true { return }
        let source: AVPictureInPictureController.ContentSource?
        if engine.currentAVPlayer != nil, let layer = engine.nativePlayerLayer {
            source = .init(playerLayer: layer)
        } else if let software = engine.softwarePiPSource {
            source = .init(sampleBufferDisplayLayer: software.layer, playbackDelegate: self)
        } else {
            source = nil
        }
        possibleObservation = nil
        guard let source else {
            controller = nil
            possible = false
            return
        }
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = allowed
        self.controller = controller
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            let possible = controller.isPictureInPicturePossible
            DispatchQueue.main.async { self?.possible = possible }
        }
    }

    /// The engine can't tell a TV from a speaker on the AirPlay route; AVPlayer's
    /// external playback says the receiver shows the video.
    private func watchExternalPlayback(_ player: AVPlayer?) {
        externalObservation = player?.observe(\.isExternalPlaybackActive, options: [.initial, .new]) { [weak self] player, _ in
            let active = player.isExternalPlaybackActive
            AppLog.emit("external playback active=\(active)")
            AppLog.route()
            DispatchQueue.main.async { self?.engine.setAirPlayReceiverShowsVideo(active) }
        }
    }

    private func changed(active: Bool) {
        isActive = active
        engine.pictureInPictureActive = active
        engine.setNativeSubtitleRendering(active)
        bridge?.send(["type": "pip", "value": active])
    }
}

extension PictureInPicture: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { changed(active: true) }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        MainActor.assumeIsolated { changed(active: false) }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(true)
    }
}

extension PictureInPicture: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        MainActor.assumeIsolated { engine.softwarePiPSource?.setPlaying(playing) }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        MainActor.assumeIsolated {
            engine.softwarePiPSource?.timeRange() ?? CMTimeRange(start: .zero, duration: .positiveInfinity)
        }
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        MainActor.assumeIsolated { engine.softwarePiPSource?.isPaused ?? true }
    }

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        didTransitionToRenderSize newRenderSize: CMVideoDimensions
    ) {}

    nonisolated func pictureInPictureController(
        _ controller: AVPictureInPictureController,
        skipByInterval skipInterval: CMTime,
        completion completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated { engine.softwarePiPSource?.skip(by: skipInterval.seconds) }
        completionHandler()
    }
}
