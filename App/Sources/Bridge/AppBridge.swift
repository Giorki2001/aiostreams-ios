import AetherEngine
import Foundation
import UIKit
import WebKit

/// The page's `window.aiostreamsApp`: the protocol the AIOStreams desktop and Android
/// apps speak, carried over WebKit's message handlers. Player messages go to
/// `PlayerChannel`, the rest are answered here.
@MainActor
final class AppBridge {
    weak var model: AppModel?
    weak var webView: WKWebView?

    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: Page → app

    func receive(json: String) {
        guard let data = json.data(using: .utf8),
              let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = message["type"] as? String else { return }
        if model?.player.handle(type: type, message: message) == true { return }
        handle(type: type, message: message)
    }

    private func handle(type: String, message: [String: Any]) {
        guard let model else { return }
        switch type {
        case "hello":
            model.pageLoaded()
        case "app-info":
            send([
                "type": "app-info",
                "app": "AIOStreams iOS \(Self.appVersion)",
                "platform": "ios",
                "mpv": NSNull(),
                "ffmpeg": NSNull(),
                "player": "AetherEngine \(AetherEngine.version)",
                "ac3Encoder": false,
            ])
        case "update-check":
            send([
                "type": "update-state", "state": "off", "channel": NSNull(),
                "version": NSNull(), "error": NSNull(),
            ])
        case "links-ready":
            model.pageWantsLinks()
        case "diagnostics":
            send(["type": "diagnostics", "text": diagnostics(web: message["web"] as? String)])
        case "crash-report":
            send(["type": "crash-report"])
        case "player-engine":
            // The page names its setting; this app always plays with AetherEngine.
            send(["type": "player-engine", "name": "mpv"])
        case "fullscreen":
            if let value = message["value"] as? Bool {
                model.setFullscreen(value)
            } else {
                model.setFullscreen(!model.fullscreen)
            }
        case "levels":
            send(model.levels.read())
        case "set-level":
            if let level = message["level"] as? String {
                model.levels.set(level: level, value: Self.number(message["value"]))
            }
        case "save-file":
            Share.file(named: message["name"] as? String ?? "aiostreams.txt", text: message["text"] as? String ?? "")
        case "now-playing":
            let item = message["item"] as? [String: Any]
            model.nowPlaying.set(item: item)
            model.pip.allowed = (item?["pip"] as? Bool) ?? true
        case "external-players":
            send(["type": "external-players", "players": [Any]()])
        case "audio-devices":
            send(["type": "audio-devices", "devices": NSNull()])
        case "video-output":
            send(["type": "video-output", "outputs": [Any](), "running": "system", "chosen": "system"])
        case "download-list", "download-add", "download-control", "download-remove", "download-config":
            send(["type": "download-state", "folder": "", "jobs": [Any]()])
            if type == "download-add" {
                send(["type": "error", "message": "I download non sono ancora disponibili su iPhone"])
            }
        case "mpv-config", "mpv-config-save":
            send(["type": "error", "message": "mpv.conf non esiste su iPhone"])
        case "restart":
            model.reload()
        default:
            break
        }
    }

    // MARK: App → page

    func send(_ message: [String: Any]) {
        guard let webView,
              JSONSerialization.isValidJSONObject(message),
              let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__aiostreamsDeliver && window.__aiostreamsDeliver(\(json));") { _, _ in }
    }

    /// What the page reads from `window.aiostreamsApp` before anything else runs.
    static func identity() -> [String: Any] {
        [
            "version": appVersion,
            "device": UIDevice.current.name,
            "deviceId": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
        ]
    }

    private func diagnostics(web: String?) -> String {
        let device = UIDevice.current
        return [
            "App        AIOStreams iOS \(Self.appVersion)",
            "Engine     AetherEngine \(AetherEngine.version)",
            "Web app    \(web ?? "?")",
            "System     \(device.systemName) \(device.systemVersion)",
            "Device     \(device.model)",
        ].joined(separator: "\n")
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID():
            return n.doubleValue
        case let d as Double:
            return d
        case let i as Int:
            return Double(i)
        default:
            return nil
        }
    }
}
