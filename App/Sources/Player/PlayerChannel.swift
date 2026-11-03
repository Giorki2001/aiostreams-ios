import AetherEngine
import Combine
import Foundation
import QuartzCore

/// A stretch the page offers to skip, or skips itself when `auto`.
private struct Skip {
    let startMs: Double
    let endMs: Double
    let auto: Bool
}

extension Publisher where Failure == Never {
    /// Delivers on the main actor, where the engine and the page live.
    func onMain(_ action: @escaping @MainActor (Output) -> Void) -> AnyCancellable {
        receive(on: DispatchQueue.main).sink { value in
            MainActor.assumeIsolated { action(value) }
        }
    }
}

/// Carries the page's `player-*` messages to AetherEngine and the engine's
/// reports back, in the terms the desktop and Android apps use.
@MainActor
final class PlayerChannel {
    weak var model: AppModel?
    private let engine: AetherEngine
    private let bridge: AppBridge
    private var cancellables = Set<AnyCancellable>()

    private var loadTask: Task<Void, Never>?
    /// Counts loads, so a superseded one keeps quiet.
    private var generation = 0
    private var active = false
    private var lastLoad: [String: Any]?
    private var headers: [String: String] = [:]

    // What the page set, which each new file takes over.
    private var wantsPause = false
    private var volume: Double = 1
    private var muted = false
    private var speed: Double = 1
    private var audioDelayMs: Double = 0

    private var skips: [Skip] = []
    private var skipped = Set<Int>()
    /// Where subtitles the page added came from, by track id.
    private var addedURLs: [Int: String] = [:]
    private var endedSent = false
    private var firstFrameSeen = false
    private var lastPositionSentAt: CFTimeInterval = 0
    /// The last of every state field, for `player-sync`.
    private var state: [String: Any] = [:]
    /// Whether this title's audio is already AAC for an AirPlay receiver that takes nothing else.
    private var aacForAirPlay = false

    init(engine: AetherEngine, bridge: AppBridge) {
        self.engine = engine
        self.bridge = bridge
        observe()
    }

    // MARK: Page → engine

    /// False for a message that isn't the player's.
    func handle(type: String, message: [String: Any]) -> Bool {
        switch type {
        case "player-load":
            load(message)
        case "player-stop":
            stop()
        case "player-set":
            set(message)
        case "player-seek":
            if let positionMs = AppBridge.number(message["positionMs"]) {
                let engine = engine
                Task { await engine.seek(to: positionMs / 1000) }
            }
        case "player-skips":
            skips = (message["segments"] as? [[String: Any]] ?? []).compactMap { segment in
                guard let start = AppBridge.number(segment["startMs"]),
                      let end = AppBridge.number(segment["endMs"]), end > start else { return nil }
                return Skip(startMs: start, endMs: end, auto: segment["auto"] as? Bool ?? false)
            }
            skipped = []
        case "player-subtitle-add":
            addSubtitle(message)
        case "subtitle-file":
            addSubtitleFile(message)
        case "player-style":
            if let fit = message["fit"] as? String { engine.videoGravity = SubtitleStyle.gravity(fit) }
            if let look = message["subtitles"] as? [String: Any] { model?.subtitleStyle = SubtitleStyle(look) }
        case "player-controls":
            // The native buttons follow the controls in the page itself (PlayerChrome).
            break
        case "player-stats-overlay":
            model?.statsVisible = message["page"] is String
        case "player-stats":
            bridge.send([
                "type": "player-stats", "stats": [String: Any](),
                "cpuMs": 0, "atMs": CACurrentMediaTime() * 1000,
            ])
        case "player-subtitle-index":
            // No index of the file's subtitle lines here.
            bridge.send(["type": "player-subtitle-index", "tracks": NSNull()])
        case "player-thumbnail":
            if let url = message["url"] as? String {
                bridge.send(["type": "player-thumbnail", "url": url, "src": NSNull()])
            }
        case "player-sync":
            sync()
        case "player-settings":
            if let delay = AppBridge.number(message["audioDelayMs"]), delay != audioDelayMs {
                audioDelayMs = delay
                if active { engine.setAudioDelay(delay / 1000) }
            }
        case "player-retry":
            if var message = lastLoad {
                message["startMs"] = engine.clock.currentTime * 1000
                load(message)
            }
        case "player-subtitle-lines", "player-unqueue":
            break
        default:
            return false
        }
        return true
    }

    private func load(_ message: [String: Any]) {
        guard let string = message["url"] as? String,
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "file"].contains(scheme) else {
            return reject("only http(s) urls play")
        }
        lastLoad = message
        headers = message["headers"] as? [String: String] ?? [:]
        let startMs = AppBridge.number(message["startMs"]) ?? 0
        let audioLanguages = Self.strings(message["audioLanguages"])
        let subtitleLanguages = Self.strings(message["subtitleLanguages"])
        let mode = message["subtitleMode"] as? String ?? "default"

        loadTask?.cancel()
        generation += 1
        let current = generation
        active = true
        endedSent = false
        firstFrameSeen = false
        skips = []
        skipped = []
        addedURLs = [:]
        model?.playerActive = true
        model?.airPlayProblem = nil
        event("start")

        var options = LoadOptions()
        options.httpHeaders = headers
        options.preferredAudioLanguages = audioLanguages
        options.prepareNativeSubtitles = true
        options.nativeSubtitlePreferredLanguages = subtitleLanguages
        options.autoplay = !wantsPause
        options.audioDelaySeconds = audioDelayMs / 1000
        aacForAirPlay = AirPlayReceivers.currentTakesAACOnly
        if aacForAirPlay {
            options.audioBridgeMode = .airPlayCompat
            AppLog.emit("AirPlay receiver takes AAC only; loading with AAC audio")
        }

        let engine = engine
        loadTask = Task { [weak self] in
            do {
                try await engine.load(url: url, startPosition: startMs > 0 ? startMs / 1000 : nil, options: options)
                guard let self, current == self.generation, !Task.isCancelled else { return }
                self.loaded(mode: mode, subtitleLanguages: subtitleLanguages)
            } catch {
                guard let self, current == self.generation, !(error is CancellationError) else { return }
                self.ended(reason: "error", error: error.localizedDescription)
            }
        }
    }

    private func loaded(mode: String, subtitleLanguages: [String]) {
        applyVolume()
        if speed != 1 { engine.setRate(Float(speed)) }
        pickSubtitle(mode: mode, languages: subtitleLanguages)
        sendTracks()
        sendChapters()
        report(["paused": engine.state == .paused, "idle": false])
        event("loaded")
    }

    private func stop() {
        loadTask?.cancel()
        generation += 1
        active = false
        engine.stop()
        skips = []
        model?.playerActive = false
        model?.statsVisible = false
        model?.airPlayProblem = nil
        report(["idle": true])
    }

    private func set(_ message: [String: Any]) {
        if let paused = message["paused"] as? Bool {
            wantsPause = paused
            if active, engine.state == .playing || engine.state == .paused {
                paused ? engine.pause() : engine.play()
            }
        }
        if let value = AppBridge.number(message["volume"]) {
            volume = value
            applyVolume()
            report(["volume": value])
        }
        if let value = message["muted"] as? Bool {
            muted = value
            applyVolume()
            report(["muted": value])
        }
        if let value = AppBridge.number(message["speed"]) {
            speed = value
            if active { engine.setRate(Float(value)) }
            report(["speed": value])
        }
        if message.keys.contains("audio"), let id = Self.trackID(message["audio"]) {
            engine.selectAudioTrack(index: id)
        }
        if message.keys.contains("subtitle") {
            if let id = Self.trackID(message["subtitle"]) {
                engine.selectSubtitleTrack(index: id)
            } else {
                engine.clearSubtitle()
                report(["subtitle": NSNull()])
            }
        }
        if let delay = AppBridge.number(message["subtitleDelayMs"]) {
            model?.subtitleDelayMs = delay
            engine.setSoftwareSubtitleDelay(delay / 1000)
        }
    }

    private func applyVolume() {
        engine.volume = muted ? 0 : Float(min(max(volume, 0), 1))
    }

    // MARK: Subtitles

    /// mpv's choice for `alang`/`slang` and the page's subtitle mode, made over the file's tracks.
    private func pickSubtitle(mode: String, languages: [String]) {
        let subtitles = engine.subtitleTracks
        let audioLanguage = engine.audioTracks.first { $0.id == engine.activeAudioTrackIndex }?.language
        let forcedForAudio = subtitles.first { $0.isForced && Languages.same($0.language, audioLanguage) }

        func best() -> TrackInfo? {
            for language in languages {
                let matching = subtitles.filter { Languages.same($0.language, language) && !$0.isForced }
                if let pick = matching.first(where: { !$0.isHearingImpaired && !$0.isCommentary }) ?? matching.first {
                    return pick
                }
            }
            return nil
        }

        let pick: TrackInfo?
        switch mode {
        case "none":
            pick = nil
        case "forced":
            pick = forcedForAudio ?? subtitles.first { $0.isForced }
        case "smart":
            if let audioLanguage, languages.contains(where: { Languages.same($0, audioLanguage) }) {
                pick = forcedForAudio
            } else {
                pick = best() ?? forcedForAudio
            }
        case "always":
            pick = best() ?? subtitles.first { $0.isDefault } ?? subtitles.first
        default:
            pick = best() ?? subtitles.first { $0.isDefault } ?? forcedForAudio
        }
        if let pick {
            engine.selectSubtitleTrack(index: pick.id)
        } else {
            engine.clearSubtitle()
        }
    }

    private func addSubtitle(_ message: [String: Any]) {
        guard let string = message["url"] as? String, let url = URL(string: string) else {
            return reject("only http(s) subtitles load")
        }
        if let existing = addedURLs.first(where: { $0.value == string })?.key {
            return engine.selectSubtitleTrack(index: existing)
        }
        let language = (message["language"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(
            url: url,
            name: message["title"] as? String,
            language: language,
            httpHeaders: headers.isEmpty ? nil : headers
        ))
        addedURLs[track.id] = string
        engine.selectSubtitleTrack(index: track.id)
        sendTracks()
    }

    /// The page never names a path, so the file is written here first.
    private func addSubtitleFile(_ message: [String: Any]) {
        guard let name = message["name"] as? String,
              let encoded = message["data"] as? String,
              let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters) else {
            return reject("subtitle file without data")
        }
        let ext = (name as NSString).pathExtension.lowercased()
        guard ["srt", "vtt", "ass", "ssa", "sub", "sup"].contains(ext) else { return reject("\(name) is not a subtitle file") }
        guard data.count <= 10 << 20 else { return reject("\(name) is too big") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("subtitles", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: file)
        } catch {
            return reject("could not save \(name)")
        }
        let track = engine.addExternalSubtitleTrack(ExternalSubtitleTrack(url: file, name: String(name.prefix(200))))
        engine.selectSubtitleTrack(index: track.id)
        sendTracks()
    }

    // MARK: AirPlay receivers

    /// A smart TV's AirPlay receiver refused the stream: `codecs` is what it was offered. An H.264 picture
    /// with other audio plays once the audio is AAC, so the title reloads where it is with AAC audio and
    /// the receiver is remembered; a picture the TV can't decode can only be explained.
    func receiverRefused(codecs: [String]) {
        guard active else { return }
        let videoPrefixes = ["avc1", "avc3", "hvc1", "hev1", "dvh1", "dvhe", "av01", "dav1", "vp09", "vp08"]
        let video = codecs.first { codec in videoPrefixes.contains { codec.hasPrefix($0) } }
        let audio = codecs.filter { $0 != video }
        let pictureOK = video.map { $0.hasPrefix("avc1") || $0.hasPrefix("avc3") } ?? true

        if !pictureOK {
            let name = video.map { $0.hasPrefix("av01") || $0.hasPrefix("dav1") ? "AV1" : $0.hasPrefix("vp0") ? "VP9" : "HEVC (4K, HDR, Dolby Vision)" } ?? "in questo formato"
            showAirPlayProblem("La TV non accetta video \(name) via AirPlay. Scegli una versione H.264 (x264) o usa l'app sulla TV.")
            return
        }
        if audio.contains(where: { !$0.hasPrefix("mp4a") }) {
            // The same refusal arrives several times in a row; one reload answers all of them.
            guard !aacForAirPlay else { return }
            aacForAirPlay = true
            AirPlayReceivers.rememberCurrentTakesAACOnly()
            AppLog.emit("AirPlay receiver refused audio \(audio); reloading with AAC audio")
            model?.airPlayProblem = nil
            let engine = engine
            Task { [weak self] in
                do {
                    try await engine.reloadAtCurrentPosition { $0.audioBridgeMode = .airPlayCompat }
                } catch {
                    AppLog.emit("AAC reload failed: \(error)")
                    self?.showAirPlayProblem("La TV non accetta l'audio di questo video via AirPlay. Usa la duplicazione schermo o l'app sulla TV.")
                }
            }
            return
        }
        showAirPlayProblem("La TV non accetta questo video via AirPlay. Usa la duplicazione schermo o l'app sulla TV.")
    }

    private func showAirPlayProblem(_ text: String) {
        guard model?.airPlayProblem != text else { return }
        model?.airPlayProblem = text
        AppLog.emit("AirPlay problem shown: \(text)")
    }

    // MARK: Engine → page

    private func observe() {
        engine.$state.onMain { [weak self] state in self?.stateChanged(state) }
            .store(in: &cancellables)
        engine.$isBuffering.removeDuplicates().onMain { [weak self] buffering in
            self?.report(["buffering": buffering])
        }.store(in: &cancellables)
        engine.$isSeeking.removeDuplicates().onMain { [weak self] seeking in
            guard let self else { return }
            self.report(["seeking": seeking])
            if !seeking, self.firstFrameSeen { self.event("restart") }
        }.store(in: &cancellables)
        engine.$hasFirstFrameReadyForDisplay.removeDuplicates().onMain { [weak self] ready in
            guard let self, ready, self.active else { return }
            self.firstFrameSeen = true
            self.event("restart")
        }.store(in: &cancellables)
        engine.$duration.removeDuplicates().onMain { [weak self] duration in
            guard duration > 0, duration.isFinite else { return }
            self?.report(["durationMs": duration * 1000])
        }.store(in: &cancellables)
        engine.clock.$currentTime.onMain { [weak self] time in self?.position(time) }
            .store(in: &cancellables)
        engine.$audioTracks.combineLatest(engine.$subtitleTracks).onMain { [weak self] _ in
            guard let self, self.active else { return }
            self.sendTracks()
        }.store(in: &cancellables)
        engine.$activeAudioTrackIndex.removeDuplicates().onMain { [weak self] id in
            self?.report(["audio": id.map { String($0) as Any } ?? NSNull()])
        }.store(in: &cancellables)
        engine.$activeSubtitleTrackIndex.removeDuplicates().onMain { [weak self] id in
            self?.report(["subtitle": id.map { String($0) as Any } ?? NSNull()])
        }.store(in: &cancellables)
        engine.$mediaChapters.onMain { [weak self] _ in
            guard let self, self.active else { return }
            self.sendChapters()
        }.store(in: &cancellables)
    }

    private func stateChanged(_ state: PlaybackState) {
        switch state {
        case .playing:
            report(["paused": false, "idle": false])
        case .paused:
            report(["paused": true, "idle": false])
            sendPosition(engine.clock.currentTime)
        case .ended:
            ended(reason: "eof", error: nil)
        case .error(let message):
            ended(reason: "error", error: message)
        case .idle:
            report(["idle": true])
        default:
            break
        }
    }

    private func ended(reason: String, error: String?) {
        guard active, !endedSent else { return }
        endedSent = true
        bridge.send(["type": "player-ended", "reason": reason, "error": error.map { $0 as Any } ?? NSNull()])
    }

    /// Positions come ten times a second; they go out at most every 250 ms.
    private func position(_ time: Double) {
        guard active, time.isFinite else { return }
        checkSkips(atMs: time * 1000)
        let now = CACurrentMediaTime()
        guard now - lastPositionSentAt >= 0.25 else { return }
        sendPosition(time)
    }

    private func sendPosition(_ time: Double) {
        guard active, time.isFinite else { return }
        lastPositionSentAt = CACurrentMediaTime()
        var fields: [String: Any] = ["positionMs": time * 1000]
        let buffered = engine.clock.bufferedPosition
        if buffered.isFinite, buffered > time {
            fields["buffered"] = [["startMs": time * 1000, "endMs": buffered * 1000]]
        }
        report(fields)
    }

    private func checkSkips(atMs position: Double) {
        for (index, skip) in skips.enumerated()
        where skip.auto && !skipped.contains(index) && position >= skip.startMs && position < skip.endMs - 1000 {
            skipped.insert(index)
            let engine = engine
            Task { await engine.seek(to: skip.endMs / 1000) }
            return
        }
    }

    private func report(_ fields: [String: Any]) {
        for (key, value) in fields where key != "positionMs" && key != "buffered" {
            state[key] = value
        }
        var message = fields
        message["type"] = "player-state"
        bridge.send(message)
    }

    private func event(_ name: String) {
        bridge.send(["type": "player-event", "name": name])
    }

    private func sync() {
        var message = state
        message["type"] = "player-state"
        bridge.send(message)
        if active {
            sendTracks()
            sendChapters()
        }
    }

    private func sendTracks() {
        var list: [[String: Any]] = []
        for track in engine.audioTracks { list.append(describe(track, type: "audio")) }
        for track in engine.subtitleTracks { list.append(describe(track, type: "subtitle")) }
        bridge.send(["type": "player-tracks", "tracks": list])
    }

    private func describe(_ track: TrackInfo, type: String) -> [String: Any] {
        var fields: [String: Any] = [
            "id": String(track.id),
            "type": type,
            "codec": track.codec,
            "default": track.isDefault,
            "forced": track.isForced,
            "hearingImpaired": track.isHearingImpaired,
            "visualImpaired": track.isVisualImpaired,
            "external": track.isExternal,
        ]
        if !track.name.isEmpty { fields["title"] = track.name }
        if let language = track.language, !language.isEmpty { fields["language"] = language }
        if let url = addedURLs[track.id] { fields["url"] = url }
        return fields
    }

    private func sendChapters() {
        let chapters: [[String: Any]] = engine.mediaChapters.map { chapter in
            var fields: [String: Any] = ["startMs": chapter.startSeconds * 1000]
            if !chapter.name.isEmpty { fields["title"] = chapter.name }
            return fields
        }
        bridge.send(["type": "player-chapters", "chapters": chapters])
    }

    private func reject(_ message: String) {
        bridge.send(["type": "error", "message": message])
    }

    // MARK: Helpers

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).compactMap { $0 as? String }
    }

    /// The page names tracks by their id in digits; `null` is none.
    private static func trackID(_ value: Any?) -> Int? {
        guard let string = value as? String, !string.isEmpty, string.allSatisfy(\.isNumber) else { return nil }
        return Int(string)
    }
}
