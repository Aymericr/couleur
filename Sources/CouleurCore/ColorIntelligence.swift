import Foundation

public enum ColorFamily: String, CaseIterable, Codable, Identifiable, Sendable {
    case neutral = "Neutrals", red = "Reds", orange = "Oranges", yellow = "Yellows"
    case green = "Greens", teal = "Teals", blue = "Blues", violet = "Violets", pink = "Pinks", earth = "Earth tones"
    public var id: Self { self }
}

public enum ColorHarmony: String, CaseIterable, Identifiable, Sendable {
    case analogous = "Analogous", complementary = "Complementary", triadic = "Triadic", tonal = "Tonal"
    public var id: Self { self }
    public var detail: String {
        switch self {
        case .analogous: "Neighboring hues, a quieter palette."
        case .complementary: "Opposite hues, a stronger contrast."
        case .triadic: "Three evenly spaced hues."
        case .tonal: "One hue, five levels of lightness."
        }
    }
    public func colors(for color: ColorValue) -> [ColorValue] {
        let o = color.oklch
        if self == .tonal {
            return [0.95, 0.82, 0.65, 0.46, 0.28].map {
                ColorValue.perceptual(lightness: $0, chroma: o.chroma, hue: o.hue, alpha: color.alpha)
            }
        }
        let offsets: [Double] = switch self {
        case .analogous: [-30, 0, 30]
        case .complementary: [0, 180]
        case .triadic: [0, 120, 240]
        case .tonal: []
        }
        return offsets.map { $0 == 0 ? color : .perceptual(lightness: o.lightness, chroma: o.chroma, hue: o.hue + $0, alpha: color.alpha) }
    }
}

extension ColorValue {
    /// Stable, local suggestions. Family thresholds and names are editorial,
    /// not assertions about an image's meaning or a formal color standard.
    public var family: ColorFamily {
        let o = oklch
        if o.chroma < 0.025 || o.lightness < 0.12 { return .neutral }
        if (35..<95).contains(o.hue) && o.lightness < 0.64 && o.chroma < 0.15 { return .earth }
        switch o.hue {
        case 15..<45: return .red
        case 45..<80: return .orange
        case 80..<115: return .yellow
        case 115..<170: return .green
        case 170..<225: return .teal
        case 225..<280: return .blue
        case 280..<325: return .violet
        default: return .pink
        }
    }

    public var suggestedName: String {
        if alpha == 0 { return "Transparent" }
        let candidates = Self.nameAnchors.filter { $0.color.family == family }
        let closest = (candidates.isEmpty ? Self.nameAnchors : candidates).min {
            perceptualDistance(to: $0.color) < perceptualDistance(to: $1.color)
        }!
        return closest.name
    }

    public func perceptualDistance(to other: ColorValue) -> Double {
        let a = oklch, b = other.oklch
        let ah = a.hue * .pi / 180, bh = b.hue * .pi / 180
        return sqrt(pow(a.lightness - b.lightness, 2) + pow(a.chroma * cos(ah) - b.chroma * cos(bh), 2)
                    + pow(a.chroma * sin(ah) - b.chroma * sin(bh), 2))
    }

    /// OKLab inverse from Björn Ottosson. Reduce chroma to fit sRGB instead
    /// of clipping individual channels and shifting the intended hue.
    public static func perceptual(lightness: Double, chroma: Double, hue: Double, alpha: Double = 1) -> ColorValue {
        let lightness = min(1, max(0, lightness.isFinite ? lightness : 0))
        let chroma = min(0.5, max(0, chroma.isFinite ? chroma : 0))
        let angle = (hue.isFinite ? hue : 0) * .pi / 180
        func linear(_ c: Double) -> (Double, Double, Double) {
            let a = c * cos(angle), b = c * sin(angle)
            let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
            let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
            let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
            return (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                    -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                    -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        }
        func inGamut(_ rgb: (Double, Double, Double)) -> Bool { [rgb.0, rgb.1, rgb.2].allSatisfy { (-0.0000001...1.0000001).contains($0) } }
        var rgb = linear(chroma)
        if !inGamut(rgb) {
            var low = 0.0, high = chroma
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if inGamut(linear(middle)) { low = middle } else { high = middle }
            }
            rgb = linear(low)
        }
        func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }
        return ColorValue(red: gamma(rgb.0), green: gamma(rgb.1), blue: gamma(rgb.2), alpha: alpha)
    }

    /// WCAG relative luminance. Call on an opaque/composited color.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func composited(over background: ColorValue) -> ColorValue {
        let a = alpha + background.alpha * (1 - alpha)
        guard a > 0 else { return ColorValue(red: 0, green: 0, blue: 0, alpha: 0) }
        func channel(_ c: Double, _ b: Double) -> Double { (c * alpha + b * background.alpha * (1 - alpha)) / a }
        return ColorValue(red: channel(red, background.red), green: channel(green, background.green), blue: channel(blue, background.blue), alpha: a)
    }
    public func contrast(on background: ColorValue) -> Double {
        let surface = background.composited(over: ColorValue(red: 1, green: 1, blue: 1))
        let foreground = composited(over: surface)
        let a = foreground.relativeLuminance, b = surface.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static let nameAnchors: [(name: String, color: ColorValue)] = [
        ("Snow", "FFFFFF"), ("Porcelain", "F4F3F0"), ("Silver", "C8CBCF"), ("Stone", "A6A5A1"),
        ("Slate", "74777D"), ("Graphite", "45474B"), ("Ink", "202124"), ("Midnight", "08090B"),
        ("Crimson", "B8243D"), ("Scarlet", "ED3B35"), ("Coral", "F47E6C"), ("Blush", "EAC5BE"),
        ("Rose", "D783A4"), ("Raspberry", "B42D68"), ("Fuchsia", "E946BD"), ("Petal", "F0D3E8"),
        ("Tangerine", "F28A32"), ("Apricot", "F5BA85"), ("Peach", "F6D0B5"), ("Copper", "B7673C"),
        ("Honey", "D7A33B"), ("Saffron", "F4BE35"), ("Lemon", "F6E669"), ("Cream", "F3E7BB"),
        ("Olive", "7F873E"), ("Sage", "A7B49A"), ("Moss", "586E45"), ("Forest", "265C3E"),
        ("Lime", "A4D849"), ("Mint", "A5DDC1"), ("Emerald", "27946C"), ("Seafoam", "83C9B8"),
        ("Teal", "267F82"), ("Lagoon", "34B5BE"), ("Glacier", "B5DEE6"), ("Cyan", "4ACADD"),
        ("Sky", "87BCE3"), ("Cornflower", "668FD0"), ("Cobalt", "365DE1"), ("Navy", "283C71"),
        ("Periwinkle", "9AABEE"), ("Indigo", "5143AF"), ("Iris", "8262CD"), ("Lavender", "C8B6E6"),
        ("Plum", "794C85"), ("Orchid", "BB77C0"), ("Lilac", "D6B4DB"), ("Aubergine", "4D3058"),
        ("Terracotta", "A65F47"), ("Clay", "BC8B73"), ("Sand", "C9B390"), ("Umber", "77543D"),
        ("Cocoa", "54392E"), ("Espresso", "352820"), ("Taupe", "928278"), ("Burgundy", "772D40")
    ].map { (name: $0.0, color: ColorValue.parse($0.1)!) }
}

extension SavedColor {
    public var displayName: String { name.isEmpty || name.uppercased() == value.hex ? value.suggestedName : name }
}
