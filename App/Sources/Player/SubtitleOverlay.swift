import AetherEngine
import SwiftUI

/// Draws the engine's subtitle cues over the video, in the page's style, beneath
/// the page so its controls stay on top.
struct SubtitleOverlay: View {
    @ObservedObject var engine: AetherEngine
    @ObservedObject var clock: PlaybackClock
    let style: SubtitleStyle
    let delayMs: Double

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let video = videoRect(in: size)
            let time = clock.sourceTime - delayMs / 1000
            let cues = engine.subtitleCues.filter { $0.startTime <= time && time < $0.endTime }
            ZStack(alignment: .topLeading) {
                ForEach(cues.filter(\.isImage)) { cue in
                    if case .image(let image) = cue.body {
                        let frame = imageFrame(image, in: video)
                        Image(decorative: image.cgImage, scale: 1)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                let texts = cues.filter { !$0.isImage }
                if !texts.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(texts) { cue in line(cue, height: video.height) }
                    }
                    .frame(maxWidth: video.width * 0.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .position(x: video.midX, y: textCenterY(count: texts.count, in: video))
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
    }

    /// mpv's font size: 55 at a 720-line window, scaled by the page's setting.
    private func fontSize(height: CGFloat) -> CGFloat {
        max(13, height * 55 / 720 * 0.8 * style.scale)
    }

    @ViewBuilder
    private func line(_ cue: SubtitleCue, height: CGFloat) -> some View {
        let size = fontSize(height: height)
        let font: Font = style.fontName.map { .custom($0, size: size) } ?? .system(size: size, weight: style.bold ? .bold : .semibold)
        let outline = max(1, style.outlineSize * Double(size) / 55)
        Text(attributed(cue, size: size))
            .font(font)
            .multilineTextAlignment(.center)
            .foregroundStyle(style.color)
            .padding(.horizontal, style.box ? 8 : 0)
            .padding(.vertical, style.box ? 2 : 0)
            .background(style.box ? style.backColor : .clear, in: .rect(cornerRadius: 4))
            .shadow(color: style.outlineColor, radius: 0, x: outline, y: 0)
            .shadow(color: style.outlineColor, radius: 0, x: -outline, y: 0)
            .shadow(color: style.outlineColor, radius: 0, x: 0, y: outline)
            .shadow(color: style.outlineColor, radius: 0, x: 0, y: -outline)
            .shadow(color: .black.opacity(style.shadowSize > 0 ? 0.6 : 0), radius: style.shadowSize, x: 1, y: 1)
    }

    private func attributed(_ cue: SubtitleCue, size: CGFloat) -> AttributedString {
        switch cue.body {
        case .text(let text):
            return AttributedString(text)
        case .richText(let runs):
            var result = AttributedString()
            for run in runs {
                var part = AttributedString(run.text)
                if let color = run.color {
                    part.foregroundColor = Color(red: Double(color.r) / 255, green: Double(color.g) / 255, blue: Double(color.b) / 255)
                }
                var font: Font = .system(size: size, weight: run.isBold || style.bold ? .bold : .semibold)
                if run.isItalic { font = font.italic() }
                part.font = font
                if run.isUnderlined { part.underlineStyle = .single }
                if run.isStruckThrough { part.strikethroughStyle = .single }
                result.append(part)
            }
            return result
        case .image:
            return AttributedString()
        }
    }

    /// The bottom line sits at `position` percent of the height, as mpv's `sub-pos`.
    private func textCenterY(count: Int, in video: CGRect) -> CGFloat {
        let size = fontSize(height: video.height)
        let block = CGFloat(count) * size * 1.3
        let margin = video.height * 22 / 720
        let bottom = video.minY + video.height * style.position / 100 - margin
        return max(video.minY + block / 2, bottom - block / 2)
    }

    /// Where the picture is, fitted into the view.
    private func videoRect(in size: CGSize) -> CGRect {
        let width = CGFloat(engine.sourceVideoWidth)
        let height = CGFloat(engine.sourceVideoHeight)
        guard width > 0, height > 0, size.width > 0, size.height > 0 else {
            return CGRect(origin: .zero, size: size)
        }
        let display = engine.softwareDisplaySize ?? CGSize(width: width, height: height)
        let scale = min(size.width / display.width, size.height / display.height)
        let fitted = CGSize(width: display.width * scale, height: display.height * scale)
        return CGRect(
            x: (size.width - fitted.width) / 2,
            y: (size.height - fitted.height) / 2,
            width: fitted.width,
            height: fitted.height
        )
    }

    /// Picture subtitles carry their place normalized to the video.
    private func imageFrame(_ image: SubtitleImage, in video: CGRect) -> CGRect {
        CGRect(
            x: video.minX + image.position.minX * video.width,
            y: video.minY + image.position.minY * video.height,
            width: image.position.width * video.width,
            height: image.position.height * video.height
        )
    }
}

private extension SubtitleCue {
    var isImage: Bool {
        if case .image = body { return true }
        return false
    }
}
