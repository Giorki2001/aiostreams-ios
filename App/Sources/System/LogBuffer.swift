import AetherEngine
import AVFoundation
import Foundation
import UIKit

/// The engine's recent log lines, kept in memory so a viewer can send them when
/// something doesn't play. The engine strips tokens and credentials from every line.
final class LogBuffer: @unchecked Sendable {
    static let shared = LogBuffer()

    private let lock = NSLock()
    private var lines: [String] = []
    private let limit = 3000
    private let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    /// Starts collecting; the engine calls the handler from any thread.
    func install() {
        EngineLog.handler = { line in LogBuffer.shared.append(line) }
    }

    func append(_ line: String) {
        if line.contains("addSourceBuffer"), line.contains("unsupported") {
            Self.receiverRefused(line)
        }
        let stamped = "\(clock.string(from: Date())) \(line)"
        lock.lock()
        lines.append(stamped)
        if lines.count > limit { lines.removeFirst(lines.count - limit) }
        lock.unlock()
    }

    /// A smart TV's AirPlay receiver plays the stream in its own browser engine and says
    /// which formats it turned down only in AVPlayer's error log, which the engine copies here.
    private static func receiverRefused(_ line: String) {
        let codecs = refusedCodecs(in: line)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .airPlayReceiverRefused, object: nil, userInfo: ["codecs": codecs])
        }
    }

    /// `… The type provided ('video/mp4;codecs=avc1.4D4028, ec-3') is unsupported.` → `["avc1.4D4028", "ec-3"]`.
    static func refusedCodecs(in line: String) -> [String] {
        guard let start = line.range(of: "codecs=") else { return [] }
        let rest = line[start.upperBound...]
        let end = rest.firstIndex { $0 == "'" || $0 == ")" } ?? rest.endIndex
        return rest[..<end]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"")) }
            .filter { !$0.isEmpty }
    }

    /// The last `count` lines, oldest first.
    func tail(_ count: Int = .max) -> String {
        lock.lock()
        defer { lock.unlock() }
        return lines.suffix(count).joined(separator: "\n")
    }
}

extension Notification.Name {
    static let airPlayReceiverRefused = Notification.Name("AirPlayReceiverRefused")
}

/// AirPlay receivers that took only AAC audio, by route UID, so the next title goes to them in AAC
/// from the start instead of after a refusal.
enum AirPlayReceivers {
    private static let key = "aacOnlyAirPlayReceivers"

    /// The AirPlay output the sound goes to now, if any.
    static var current: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.outputs.first { $0.portType == .airPlay }
    }

    static var currentTakesAACOnly: Bool {
        guard let uid = current?.uid else { return false }
        return Set(UserDefaults.standard.stringArray(forKey: key) ?? []).contains(uid)
    }

    static func rememberCurrentTakesAACOnly() {
        guard let uid = current?.uid else { return }
        var known = Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
        guard known.insert(uid).inserted else { return }
        UserDefaults.standard.set(Array(known), forKey: key)
    }
}

/// The app's own lines, for what the engine can't see: the audio route and the network.
enum AppLog {
    static func emit(_ line: String) {
        EngineLog.emit("[App] \(line)", category: .engine)
    }

    /// Where the sound goes, e.g. `AirPlay:[LG] webOS TV`.
    static func route() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue):\($0.portName)" }
            .joined(separator: ", ")
        emit("audio route: \(outputs.isEmpty ? "none" : outputs)")
    }
}
