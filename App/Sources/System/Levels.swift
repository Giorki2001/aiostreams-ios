import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

/// The screen's brightness and the system volume, which the player's swipes change.
@MainActor
final class Levels {
    /// In the view hierarchy, so its slider sets the system volume and the system's own
    /// volume pop-up stays away while the player shows its own.
    let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 40, height: 40))
    private var originalBrightness: CGFloat?

    private var screen: UIScreen? { Orientation.windowScene?.screen }

    func read() -> [String: Any] {
        [
            "type": "levels",
            "volume": Double(AVAudioSession.sharedInstance().outputVolume),
            "brightness": Double(screen?.brightness ?? 0.5),
        ]
    }

    /// `value` nil gives the brightness back to the system.
    func set(level: String, value: Double?) {
        switch level {
        case "brightness":
            guard let screen else { return }
            if let value {
                if originalBrightness == nil { originalBrightness = screen.brightness }
                screen.brightness = CGFloat(min(max(value, 0), 1))
            } else if let original = originalBrightness {
                screen.brightness = original
                originalBrightness = nil
            }
        case "volume":
            guard let value,
                  let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else { return }
            slider.value = Float(min(max(value, 0), 1))
        default:
            break
        }
    }
}

/// Puts the volume view in the window, out of sight.
struct VolumeViewHost: UIViewRepresentable {
    let levels: Levels

    func makeUIView(context: Context) -> UIView {
        let holder = UIView(frame: .zero)
        holder.isUserInteractionEnabled = false
        holder.alpha = 0.01
        levels.volumeView.frame = CGRect(x: 0, y: 0, width: 40, height: 40)
        holder.addSubview(levels.volumeView)
        return holder
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Hands a file the page made to the system's share sheet.
@MainActor
enum Share {
    static func file(named name: String, text: String) {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(safe.isEmpty ? "aiostreams.txt" : safe)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            return
        }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        Orientation.topController?.present(sheet, animated: true)
    }
}
