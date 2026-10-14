import Foundation

/// All stored values are standard, display-independent sRGB, including alpha.
public struct ColorValue: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = Self.clamp(red)
        self.green = Self.clamp(green)
        self.blue = Self.clamp(blue)
        self.alpha = Self.clamp(alpha)
    }

    private static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }

    public var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }

    private func decimal(_ value: Double, places: Int = 3) -> String {
        String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
    }

    public var hex: String {
        let rgb = String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
        return alpha < 1 ? rgb + String(format: "%02X", Int((alpha * 255).rounded())) : rgb
    }

    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let high = max(red, green, blue), low = min(red, green, blue)
        let delta = high - low, lightness = (high + low) / 2
        guard delta > 0 else { return (0, 0, lightness) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double
        if high == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
        else if high == green { hue = (blue - red) / delta + 2 }
        else { hue = (red - green) / delta + 4 }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (hue, saturation, lightness)
    }

    public var oklch: (lightness: Double, chroma: Double, hue: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let chroma = hypot(a, bb)
        let hue = chroma < 0.00001 ? 0 : (atan2(bb, a) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return (lightness, chroma, hue)
    }

    public func formatted(_ format: CopyFormat) -> String {
        let opacity = alpha < 1 ? " / \(decimal(alpha))" : ""
        switch format {
        case .hex: return hex
        case .rgb:
            return "rgb(\(Int((red * 255).rounded())) \(Int((green * 255).rounded())) \(Int((blue * 255).rounded()))\(opacity))"
        case .hsl:
            let h = hsl
            return "hsl(\(decimal(h.hue, places: 1)) \(decimal(h.saturation * 100, places: 1))% \(decimal(h.lightness * 100, places: 1))%\(opacity))"
        case .oklch:
            let o = oklch
            return "oklch(\(decimal(o.lightness * 100, places: 2))% \(decimal(o.chroma, places: 4)) \(decimal(o.hue, places: 2))\(opacity))"
        case .swiftUI:
            return "Color(.sRGB, red: \(decimal(red, places: 4)), green: \(decimal(green, places: 4)), blue: \(decimal(blue, places: 4)), opacity: \(decimal(alpha, places: 4)))"
        case .nsColor:
            return "NSColor(srgbRed: \(decimal(red, places: 4)), green: \(decimal(green, places: 4)), blue: \(decimal(blue, places: 4)), alpha: \(decimal(alpha, places: 4)))"
        case .uiColor:
            return "UIColor(red: \(decimal(red, places: 4)), green: \(decimal(green, places: 4)), blue: \(decimal(blue, places: 4)), alpha: \(decimal(alpha, places: 4)))"
        }
    }

    public static func parse(_ input: String) -> ColorValue? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let raw = text.hasPrefix("#") ? String(text.dropFirst()) : text
        if [3, 4, 6, 8].contains(raw.count), raw.allSatisfy({ $0.isHexDigit }), let number = UInt64(raw, radix: 16) {
            _ = number
            let expanded = raw.count <= 4 ? raw.map { "\($0)\($0)" }.joined() : raw
            let chars = Array(expanded)
            func channel(_ start: Int) -> Double { Double(Int(String(chars[start...start + 1]), radix: 16)!) / 255 }
            return ColorValue(red: channel(0), green: channel(2), blue: channel(4), alpha: chars.count == 8 ? channel(6) : 1)
        }
        guard let start = text.firstIndex(of: "("), text.hasSuffix(")") else { return nil }
        let function = String(text[..<start])
        guard ["rgb", "rgba", "hsl", "hsla"].contains(function) else { return nil }
        let body = String(text[text.index(after: start)..<text.index(before: text.endIndex)])
        let parts = body.replacingOccurrences(of: ",", with: " ").replacingOccurrences(of: "/", with: " ")
            .split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (3...4).contains(parts.count) else { return nil }
        func value(_ token: String, scale: Double) -> Double? {
            let percent = token.hasSuffix("%")
            guard let n = Double(percent ? String(token.dropLast()) : token), n.isFinite else { return nil }
            return n / (percent ? 100 : scale)
        }
        guard let alpha = parts.count == 4 ? value(parts[3], scale: 1) : 1 else { return nil }
        if function.hasPrefix("rgb") {
            guard let r = value(parts[0], scale: 255), let g = value(parts[1], scale: 255), let b = value(parts[2], scale: 255) else { return nil }
            return ColorValue(red: r, green: g, blue: b, alpha: alpha)
        }
        guard parts[1].hasSuffix("%"), parts[2].hasSuffix("%"),
              let hue = Double(parts[0].replacingOccurrences(of: "deg", with: "")), hue.isFinite,
              let saturation = value(parts[1], scale: 1), let lightness = value(parts[2], scale: 1) else { return nil }
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let s = clamp(saturation), l = clamp(lightness)
        let c = (1 - abs(2 * l - 1)) * s, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = l - c / 2
        let rgb: (Double, Double, Double)
        switch h {
        case ..<1: rgb = (c, x, 0)
        case ..<2: rgb = (x, c, 0)
        case ..<3: rgb = (0, c, x)
        case ..<4: rgb = (0, x, c)
        case ..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        return ColorValue(red: rgb.0 + m, green: rgb.1 + m, blue: rgb.2 + m, alpha: alpha)
    }
}

public enum CopyFormat: String, CaseIterable, Codable, Identifiable, Sendable {
    case hex = "HEX", rgb = "RGB", hsl = "HSL", oklch = "OKLCH", swiftUI = "SwiftUI", nsColor = "NSColor", uiColor = "UIColor"
    public var id: String { rawValue }
}
