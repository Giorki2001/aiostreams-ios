import AetherEngine
import AVFoundation
import Combine
import MediaPlayer
import UIKit

/// The lock screen, Control Center and the AirPlay card: what plays, from the page's
/// `now-playing`, and their buttons, which go back to the page as `media-key`s.
///
/// The engine owns the Now Playing sessions, because a bare `AVPlayer` is not reliably
/// the system's Now Playing app through the shared centres: on the native route an
/// `MPNowPlayingSession` bound to its player, which publishes time and rate itself; on
/// the software route the shared centres, where the engine answers play, pause, skip
/// and seek directly. The app gives both the title and artwork, and adds what only the
/// page can do (next and previous, and every button on the native route).
@MainActor
final class NowPlaying {
    private let engine: AetherEngine
    private weak var bridge: AppBridge?
    private var item: [String: Any]?
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: String?
    /// The native route's session whose buttons are wired, so a new player's session is wired once.
    private var wiredSession: MPNowPlayingSession?
    /// Next and previous on the shared centre, while the software route plays.
    private var sharedTargets: [(MPRemoteCommand, Any)] = []
    private var cancellables = Set<AnyCancellable>()

    init(engine: AetherEngine, bridge: AppBridge) {
        self.engine = engine
        self.bridge = bridge
        // Read when the engine builds a player, so before the first load.
        engine.ownsVideoNowPlayingSession = true
        engine.ownsSoftwareNowPlaying = true
        engine.remoteSkipInterval = 10
        engine.$currentAVPlayer.onMain { [weak self] _ in self?.wireSession() }
            .store(in: &cancellables)
        engine.$softwareNowPlayingActive.removeDuplicates().onMain { [weak self] active in
            self?.softwareRoute(active: active)
        }.store(in: &cancellables)
    }

    func set(item: [String: Any]?) {
        self.item = item
        if let url = item?["artwork"] as? String {
            if url != artworkURL {
                artworkURL = url
                artwork = nil
                loadArtwork(url)
            }
        } else {
            artworkURL = nil
            artwork = nil
        }
        wireSession()
        enableTrackButtons()
        publish()
    }

    /// Title, episode and picture; the engine adds time, duration and rate.
    private func publish() {
        guard let item else {
            engine.setVideoNowPlayingInfo([:])
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item["title"] as? String ?? "",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
        ]
        if let subtitle = item["subtitle"] as? String, !subtitle.isEmpty {
            info[MPMediaItemPropertyArtist] = subtitle
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        engine.setVideoNowPlayingInfo(info)
    }

    private func loadArtwork(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data)?.preparingForDisplay() else { return }
            guard let self, self.artworkURL == string else { return }
            self.artwork = Self.artwork(image)
            self.publish()
        }
    }

    /// MediaPlayer asks for the picture off the main thread.
    private nonisolated static func artwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    // MARK: Buttons

    private func wireSession() {
        guard let session = engine.videoNowPlayingSession, session !== wiredSession else { return }
        wiredSession = session
        let center = session.remoteCommandCenter
        _ = wire(center, transport: true)
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        session.becomeActiveIfPossible { _ in }
        enableTrackButtons()
        EngineLog.emit("[App] Now Playing session wired for the native route", category: .engine)
    }

    /// The engine serves the transport itself on the software route; the page adds the track buttons.
    private func softwareRoute(active: Bool) {
        for (command, target) in sharedTargets { command.removeTarget(target) }
        sharedTargets = []
        guard active else { return }
        sharedTargets = wire(MPRemoteCommandCenter.shared(), transport: false)
        enableTrackButtons()
    }

    private func wire(_ center: MPRemoteCommandCenter, transport: Bool) -> [(MPRemoteCommand, Any)] {
        var targets: [(MPRemoteCommand, Any)] = []
        func on(_ command: MPRemoteCommand, _ makeKey: @escaping (MPRemoteCommandEvent) -> [String: Any]?) {
            command.isEnabled = true
            let target = command.addTarget { [weak self] event in
                guard let key = makeKey(event) else { return .commandFailed }
                DispatchQueue.main.async { self?.press(key) }
                return .success
            }
            targets.append((command, target))
        }
        if transport {
            on(center.playCommand) { _ in ["action": "play"] }
            on(center.pauseCommand) { _ in ["action": "pause"] }
            on(center.togglePlayPauseCommand) { _ in ["action": "toggle"] }
            on(center.stopCommand) { _ in ["action": "stop"] }
            on(center.skipForwardCommand) { _ in ["action": "skip", "offset": 10_000] }
            on(center.skipBackwardCommand) { _ in ["action": "skip", "offset": -10_000] }
            on(center.changePlaybackPositionCommand) { event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
                return ["action": "seek", "position": event.positionTime * 1000]
            }
        }
        on(center.nextTrackCommand) { _ in ["action": "next"] }
        on(center.previousTrackCommand) { _ in ["action": "previous"] }
        return targets
    }

    private func enableTrackButtons() {
        let next = item?["next"] as? Bool ?? false
        let previous = item?["previous"] as? Bool ?? false
        var centers: [MPRemoteCommandCenter] = []
        if let session = wiredSession { centers.append(session.remoteCommandCenter) }
        if !sharedTargets.isEmpty { centers.append(MPRemoteCommandCenter.shared()) }
        for center in centers {
            center.nextTrackCommand.isEnabled = next
            center.previousTrackCommand.isEnabled = previous
        }
    }

    private func press(_ key: [String: Any]) {
        bridge?.send(["type": "media-key", "key": key])
    }
}
