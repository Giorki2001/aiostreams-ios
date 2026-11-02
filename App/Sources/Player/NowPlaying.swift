import AetherEngine
import Combine
import MediaPlayer
import UIKit

/// The lock screen and Control Center: what plays, from the page's `now-playing`,
/// and their buttons, which go back to the page as `media-key`s.
@MainActor
final class NowPlaying {
    private let engine: AetherEngine
    private weak var bridge: AppBridge?
    private var item: [String: Any]?
    private var artwork: MPMediaItemArtwork?
    private var artworkURL: String?
    private var commandsReady = false
    private var cancellables = Set<AnyCancellable>()

    init(engine: AetherEngine, bridge: AppBridge) {
        self.engine = engine
        self.bridge = bridge
        engine.$state.onMain { [weak self] _ in self?.refresh() }.store(in: &cancellables)
        engine.clock.$currentTime
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .onMain { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func set(item: [String: Any]?) {
        self.item = item
        guard let item else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            artwork = nil
            artworkURL = nil
            return
        }
        setUpCommands()
        let center = MPRemoteCommandCenter.shared()
        center.nextTrackCommand.isEnabled = item["next"] as? Bool ?? false
        center.previousTrackCommand.isEnabled = item["previous"] as? Bool ?? false
        if let url = item["artwork"] as? String, url != artworkURL {
            artworkURL = url
            artwork = nil
            loadArtwork(url)
        }
        refresh()
    }

    private func refresh() {
        guard let item else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item["title"] as? String ?? "",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: engine.clock.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: engine.state == .playing ? 1.0 : 0.0,
        ]
        if let subtitle = item["subtitle"] as? String { info[MPMediaItemPropertyArtist] = subtitle }
        if engine.duration > 0, engine.duration.isFinite { info[MPMediaItemPropertyPlaybackDuration] = engine.duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func loadArtwork(_ string: String) {
        guard let url = URL(string: string) else { return }
        Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data) else { return }
            guard let self, self.artworkURL == string else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.refresh()
        }
    }

    private func setUpCommands() {
        guard !commandsReady else { return }
        commandsReady = true
        let center = MPRemoteCommandCenter.shared()
        func on(_ command: MPRemoteCommand, _ key: @escaping (MPRemoteCommandEvent) -> [String: Any]?) {
            command.isEnabled = true
            command.addTarget { [weak self] event in
                guard let key = key(event) else { return .commandFailed }
                MainActor.assumeIsolated { self?.press(key) }
                return .success
            }
        }
        on(center.playCommand) { _ in ["action": "play"] }
        on(center.pauseCommand) { _ in ["action": "pause"] }
        on(center.togglePlayPauseCommand) { _ in ["action": "toggle"] }
        on(center.stopCommand) { _ in ["action": "stop"] }
        on(center.nextTrackCommand) { _ in ["action": "next"] }
        on(center.previousTrackCommand) { _ in ["action": "previous"] }
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.preferredIntervals = [10]
        on(center.skipForwardCommand) { _ in ["action": "skip", "offset": 10_000] }
        on(center.skipBackwardCommand) { _ in ["action": "skip", "offset": -10_000] }
        on(center.changePlaybackPositionCommand) { event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return nil }
            return ["action": "seek", "position": event.positionTime * 1000]
        }
    }

    private func press(_ key: [String: Any]) {
        bridge?.send(["type": "media-key", "key": key])
    }
}
