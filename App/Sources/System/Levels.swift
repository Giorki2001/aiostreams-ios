import AVFoundation
import MediaPlayer
import QuartzCore
import SwiftUI
import UIKit

/// The screen's brightness and the system volume, which the player's swipes change.
@MainActor
final class Levels: ObservableObject {
    /// In the view hierarchy while the player is open, so its slider sets the system volume.
    /// It also keeps the system's volume pop-up away, so the app shows its own (`VolumeHUD`).
    let volumeView = MPVolumeView(frame: CGRect(x: -100, y: -100, width: 40, height: 40))
    private var originalBrightness: CGFloat?

    /// The system volume, 0 to 1.
    @Published private(set) var volume: Float = AVAudioSession.sharedInstance().outputVolume
    /// Whether the app's volume pop-up shows: after the volume buttons, while the player is open.
    @Published private(set) var hudVisible = false
    /// True while the player is open, which is when the system's pop-up stays away.
    var hudEnabled = false {
        didSet { if !hudEnabled { hudVisible = false } }
    }
    /// The page shows its own level while a swipe sets the volume.
    private var pageSetAt: CFTimeInterval = 0
    private var hideTask: Task<Void, Never>?
    private var observation: NSKeyValueObservation?

    init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            DispatchQueue.main.async { self?.volumeChanged(value) }
        }
    }

    private func volumeChanged(_ value: Float) {
        volume = value
        guard hudEnabled, CACurrentMediaTime() - pageSetAt > 1 else { return }
        hudVisible = true
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.hudVisible = false
        }
    }

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
            pageSetAt = CACurrentMediaTime()
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

/// The volume, in Liquid Glass, when the volume buttons change it during playback.
struct VolumeHUD: View {
    @ObservedObject var levels: Levels

    var body: some View {
        let level = CGFloat(min(max(levels.volume, 0), 1))
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(level))
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
                .contentTransition(.symbolEffect(.replace))
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule().fill(.white).frame(width: 150 * level)
            }
            .frame(width: 150, height: 6)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .frame(height: 42)
        .glassEffect(.regular, in: .capsule)
        .scaleEffect(levels.hudVisible ? 1 : 0.85)
        .opacity(levels.hudVisible ? 1 : 0)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: levels.hudVisible)
        .animation(.easeOut(duration: 0.15), value: level)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private static func symbol(_ level: CGFloat) -> String {
        switch level {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
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
