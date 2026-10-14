import Foundation

public struct PaletteColor: Equatable, Identifiable, Sendable {
    public var value: ColorValue
    /// Fraction of sampled, visible pixels assigned to this color group.
    public var proportion: Double
    public var id: String { value.hex }
}

public struct ExtractedPalette: Equatable, Sendable {
    public var dominant: [PaletteColor]
    public var shades: [PaletteColor]
}

public enum PaletteError: LocalizedError {
    case invalidPixels, emptyImage
    public var errorDescription: String? {
        switch self {
        case .invalidPixels: "The captured image could not be read. Try capturing the area again."
        case .emptyImage: "The captured area has no visible colors. Try a different area."
        }
    }
}

/// Deterministic, population-weighted clustering in perceptual OKLab space.
/// Input is straight-alpha, 8-bit sRGB RGBA. Representatives are sampled colors,
/// rather than invented averages; exact pixel picking remains a separate operation.
public enum PaletteExtractor {
    public static func extract(rgba: [UInt8], dominantCount: Int = 5, shadeCount: Int = 64) throws -> ExtractedPalette {
        guard !rgba.isEmpty, rgba.count.isMultiple(of: 4), dominantCount > 0, shadeCount > 0 else {
            throw PaletteError.invalidPixels
        }
        var exact: [Int: Double] = [:]
        for offset in stride(from: 0, to: rgba.count, by: 4) {
            if offset.isMultiple(of: 4096) { try Task.checkCancellation() }
            let alpha = Double(rgba[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
            exact[(r << 16) | (g << 8) | b, default: 0] += alpha
        }
        var histogram: [Int: Bin] = [:]
        for (rgb, weight) in exact.sorted(by: { $0.key < $1.key }) {
            let r = (rgb >> 16) & 255, g = (rgb >> 8) & 255, b = rgb & 255
            // Six bits per channel keep nearby shades together. Within each bin,
            // use its most frequent real pixel, not whichever edge pixel came first.
            let key = ((r >> 2) << 12) | ((g >> 2) << 6) | (b >> 2)
            if histogram[key] != nil {
                histogram[key]!.weight += weight
                if weight > histogram[key]!.representativeWeight {
                    let color = ColorValue(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                    histogram[key]!.color = color
                    histogram[key]!.lab = Lab(color)
                    histogram[key]!.representativeWeight = weight
                }
            } else {
                let color = ColorValue(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
                histogram[key] = Bin(key: key, color: color, lab: Lab(color), weight: weight, representativeWeight: weight)
            }
        }
        let bins = histogram.values.sorted { $0.key < $1.key }
        guard !bins.isEmpty else { throw PaletteError.emptyImage }
        return try ExtractedPalette(
            dominant: cluster(bins, count: min(dominantCount, 64)),
            shades: cluster(bins, count: min(shadeCount, 128))
        )
    }

    private struct Lab {
        var l: Double
        var a: Double
        var b: Double
        init(_ color: ColorValue) {
            let o = color.oklch
            l = o.lightness
            a = o.chroma * cos(o.hue * .pi / 180)
            b = o.chroma * sin(o.hue * .pi / 180)
        }
        init(l: Double = 0, a: Double = 0, b: Double = 0) { self.l = l; self.a = a; self.b = b }
        func distance(to other: Lab) -> Double {
            pow(l - other.l, 2) + pow(a - other.a, 2) + pow(b - other.b, 2)
        }
    }
    private struct Bin {
        let key: Int
        var color: ColorValue
        var lab: Lab
        var weight: Double
        var representativeWeight: Double
    }

    private static func cluster(_ bins: [Bin], count: Int) throws -> [PaletteColor] {
        let total = bins.reduce(0) { $0 + $1.weight }
        let first = bins.indices.max { bins[$0].weight < bins[$1].weight }!
        var centers = [bins[first].lab]
        var distances = bins.map { $0.lab.distance(to: centers[0]) }
        // Weighted farthest-point seeds keep substantial regions and small, distinct accents.
        while centers.count < min(count, bins.count) {
            try Task.checkCancellation()
            guard let next = bins.indices.filter({ distances[$0] > 0.000025 }).max(by: {
                distances[$0] * bins[$0].weight < distances[$1] * bins[$1].weight
            }) else { break }
            centers.append(bins[next].lab)
            for i in bins.indices { distances[i] = min(distances[i], bins[i].lab.distance(to: centers.last!)) }
        }

        var assignments = Array(repeating: -1, count: bins.count)
        for _ in 0..<12 {
            try Task.checkCancellation()
            var sums = Array(repeating: Lab(), count: centers.count)
            var weights = Array(repeating: 0.0, count: centers.count)
            var changed = false
            for i in bins.indices {
                let nearest = centers.indices.min { bins[i].lab.distance(to: centers[$0]) < bins[i].lab.distance(to: centers[$1]) }!
                if assignments[i] != nearest { changed = true; assignments[i] = nearest }
                let w = bins[i].weight
                sums[nearest].l += bins[i].lab.l * w
                sums[nearest].a += bins[i].lab.a * w
                sums[nearest].b += bins[i].lab.b * w
                weights[nearest] += w
            }
            for c in centers.indices where weights[c] > 0 {
                centers[c] = Lab(l: sums[c].l / weights[c], a: sums[c].a / weights[c], b: sums[c].b / weights[c])
            }
            if !changed { break }
        }

        var colors: [PaletteColor] = []
        for c in centers.indices {
            let members = bins.indices.filter { assignments[$0] == c }
            guard let representative = members.max(by: {
                let lhs = bins[$0].representativeWeight, rhs = bins[$1].representativeWeight
                return lhs == rhs ? bins[$0].lab.distance(to: centers[c]) > bins[$1].lab.distance(to: centers[c]) : lhs < rhs
            }) else { continue }
            let weight = members.reduce(0) { $0 + bins[$1].weight }
            colors.append(PaletteColor(value: bins[representative].color, proportion: weight / total))
        }
        return colors.sorted { $0.proportion == $1.proportion ? $0.id < $1.id : $0.proportion > $1.proportion }
    }
}
