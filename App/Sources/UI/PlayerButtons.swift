import AetherEngine
import AVKit
import SwiftUI

/// AirPlay and picture in picture, in Liquid Glass, while the player's controls show.
struct PlayerButtons: View {
    @ObservedObject var pip: PictureInPicture

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                RoutePicker()
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("AirPlay")
                if pip.possible {
                    Button { pip.toggle() } label: {
                        Image(systemName: pip.isActive ? "pip.exit" : "pip.enter")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Picture in Picture")
                }
            }
        }
    }
}

/// The system's AirPlay picker, which lists TVs first.
struct RoutePicker: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = true
        picker.tintColor = .white
        picker.activeTintColor = UIColor(red: 97 / 255, green: 82 / 255, blue: 223 / 255, alpha: 1)
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// What the engine is playing and how, for the page's statistics.
struct StatsOverlay: View {
    @ObservedObject var engine: AetherEngine

    var body: some View {
        Text(Self.text(engine))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .allowsHitTesting(false)
    }

    static func text(_ engine: AetherEngine) -> String {
        var lines = ["Engine     AetherEngine \(AetherEngine.version)"]
        if let container = engine.sourceContainerFormat { lines.append("Container  \(container)") }
        var video = "Video      \(engine.sourceVideoCodecName ?? "?") \(engine.sourceVideoWidth)×\(engine.sourceVideoHeight)"
        if let fps = engine.sourceVideoFrameRate, fps > 0 { video += String(format: " %.3f fps", fps) }
        if engine.sourceVideoBitrate > 0 { video += String(format: " · %.1f Mbps", Double(engine.sourceVideoBitrate) / 1e6) }
        lines.append(video)
        var colour = "Colour     \(engine.sourceVideoFormat) → \(engine.videoFormat)"
        if let profile = engine.sourceDVProfile { colour += " · Dolby Vision P\(profile)" }
        lines.append(colour)
        lines.append("Route      \(engine.videoRoute)")
        lines.append("Decoder    \(engine.activeVideoDecoder ?? "?")")
        if let audio = engine.audioTracks.first(where: { $0.id == engine.activeAudioTrackIndex }) {
            let channels = audio.isAtmos ? "Atmos" : "\(audio.channels) ch"
            lines.append("Audio      \(audio.codec) \(channels) \(audio.language ?? "")")
        }
        lines.append("Delivery   \(engine.audioDelivery) · \(engine.activeAudioDecoder ?? "?")")
        return lines.joined(separator: "\n")
    }
}

/// AirPlay takes the picture only from the native route: a title the iPhone decodes
/// itself (AV1 or VP9 without hardware decoding, 10-bit H.264, deinterlaced video)
/// sends the receiver its sound alone, and the viewer should know why.
struct AirPlayNotice: View {
    @ObservedObject var engine: AetherEngine

    var body: some View {
        if engine.airPlayPictureStaysLocal {
            Label("Su AirPlay arriva solo l'audio: questo video lo decodifica l'iPhone", systemImage: "airplayvideo")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }
}

/// The AirPlay receiver turned the stream down: say why, and what works instead.
struct AirPlayProblem: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.tv")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text(text)
                .font(.footnote.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 460)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}
