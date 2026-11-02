import AVFoundation
import SwiftUI

/// The page's subtitle look (`player-style`), in mpv's units.
struct SubtitleStyle: Equatable {
    var scale: Double = 1
    var bold = false
    var color = Color.white
    var outlineColor = Color.black
    var outlineSize: Double = 3
    var shadowSize: Double = 0
    var backColor = Color.clear
    var box = false
    var fontName: String?
    /// Percent of the height, from the top, where the bottom line sits.
    var position: Double = 100

    init() {}

    init(_ look: [String: Any]) {
        scale = AppBridge.number(look["scale"]) ?? 1
        bold = look["bold"] as? Bool ?? false
        color = Self.color(look["color"]) ?? .white
        outlineColor = Self.color(look["outlineColor"]) ?? .black
        outlineSize = AppBridge.number(look["outlineSize"]) ?? 3
        shadowSize = AppBridge.number(look["shadowSize"]) ?? 0
        backColor = Self.color(look["backColor"]) ?? .clear
        box = look["box"] as? Bool ?? false
        position = AppBridge.number(look["position"]) ?? 100
        switch look["font"] as? String {
        case "serif": fontName = "Georgia"
        case "monospace", "serif-monospace": fontName = "Menlo"
        case "casual": fontName = "Chalkboard SE"
        case "cursive": fontName = "Snell Roundhand"
        default: fontName = nil
        }
    }

    /// `#AARRGGBB` or `#RRGGBB`, as mpv takes them.
    static func color(_ value: Any?) -> Color? {
        guard var hex = value as? String, hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        guard let number = UInt64(hex, radix: 16) else { return nil }
        let alpha, red, green, blue: Double
        switch hex.count {
        case 8:
            alpha = Double((number >> 24) & 0xFF) / 255
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
        case 6:
            alpha = 1
            red = Double((number >> 16) & 0xFF) / 255
            green = Double((number >> 8) & 0xFF) / 255
            blue = Double(number & 0xFF) / 255
        default:
            return nil
        }
        return Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// How the video fills the screen (`fit`).
    static func gravity(_ fit: String?) -> AVLayerVideoGravity {
        switch fit {
        case "crop": return .resizeAspectFill
        case "stretch": return .resize
        default: return .resizeAspect
        }
    }
}
