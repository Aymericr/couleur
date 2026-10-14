import Foundation
import simd

public enum PaletteRole: String, Codable, Sendable {
    case background = "Background", surface = "Surface", foreground = "Foreground"
    case main = "Main color", accent = "Accent"
    case shadow = "Shadows", highlight = "Highlights"
}

public struct RoleColor: Equatable, Identifiable, Sendable {
    public let role: PaletteRole
    public let color: PaletteColor
    public let reason: String
    public var id: String { "\(role.rawValue)-\(color.id)" }
}

public struct PaletteAnalysis: Equatable, Sendable {
    public var roles: [RoleColor] = []
    public var gradients: [DetectedGradient] = []
}

/// Spatial evidence supplements quantization. Roles are suggestions, not object
/// recognition: textured images deliberately do not receive UI surface/text labels.
public enum PaletteAnalyzer {
    public static func analyze(rgba: [UInt8], width: Int, height: Int,
                               palette: ExtractedPalette) throws -> PaletteAnalysis {
        let raster = try AnalysisRaster(rgba: rgba, width: width, height: height)
        let gradients = try GradientDetector.detect(in: raster)
        guard !palette.shades.isEmpty else { return PaletteAnalysis(gradients: gradients) }
        let candidates = palette.shades
        let labs = candidates.map { AnalysisRaster.lab($0.value) }
        var labels = [Int](repeating: -1, count: raster.colors.count)
        var counts = [Double](repeating: 0, count: candidates.count)
        var borders = counts, flat = counts, centers = counts, largest = counts, outsideGradients = counts
        var cache: [Int: Int] = [:]
        var flatPixels = [Bool](repeating: false, count: labels.count)
        var total = 0.0, totalBorder = 0.0
        for i in labels.indices where raster.opaque[i] {
            if i.isMultiple(of: 1024) { try Task.checkCancellation() }
            let rgb = raster.rgb[i]
            let key = Int((rgb.x * 255).rounded()) << 16 | Int((rgb.y * 255).rounded()) << 8 | Int((rgb.z * 255).rounded())
            let label: Int
            if let cached = cache[key] { label = cached }
            else {
                label = labs.indices.min { simd_distance_squared(labs[$0], raster.labs[i]) < simd_distance_squared(labs[$1], raster.labs[i]) }!
                cache[key] = label
            }
            labels[i] = label; counts[label] += 1; total += 1
            let x = i % raster.width, y = i / raster.width
            let nx = Double(x) / Double(max(1, raster.width - 1)), ny = Double(y) / Double(max(1, raster.height - 1))
            centers[label] += 1 - min(1, hypot(nx - 0.5, ny - 0.5) / 0.71)
            if nx < 0.04 || nx > 0.96 || ny < 0.04 || ny > 0.96 { borders[label] += 1; totalBorder += 1 }
            let isGradient = gradients.contains { $0.matches(rgb, x: nx, y: ny, aspect: Double(raster.width) / Double(raster.height)) }
            if !isGradient { outsideGradients[label] += 1 }
            let neighbors = raster.neighbors(of: i)
            let isFlat = !isGradient && neighbors.allSatisfy {
                raster.opaque[$0] && simd_distance_squared(raster.labs[$0], raster.labs[i]) < 0.000036
            }
            flatPixels[i] = isFlat
            if isFlat { flat[label] += 1 }
        }
        guard total > 0 else { return PaletteAnalysis(gradients: gradients) }

        // Connected flat areas distinguish a canvas or card from dispersed colors
        // in a photograph, and prevent a bright speck from becoming an accent.
        var visited = [Bool](repeating: false, count: labels.count)
        for start in labels.indices where flatPixels[start] && !visited[start] {
            var queue = [start], cursor = 0
            visited[start] = true
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                for n in raster.neighbors(of: i) where !visited[n] && flatPixels[n] && labels[n] == labels[start] {
                    visited[n] = true; queue.append(n)
                }
            }
            largest[labels[start]] = max(largest[labels[start]], Double(queue.count))
        }
        let graphic = flat.reduce(0, +) / total > 0.45
        var roles: [RoleColor] = []
        var used = Set<Int>()
        func append(_ i: Int, _ role: PaletteRole, _ reason: String) {
            roles.append(RoleColor(role: role, color: PaletteColor(value: candidates[i].value, proportion: counts[i] / total), reason: reason))
            used.insert(i)
        }
        let background = candidates.indices.filter {
            largest[$0] / total >= 0.10 && flat[$0] / max(1, counts[$0]) > 0.55 && borders[$0] / max(1, totalBorder) >= 0.25
        }.max { borders[$0] + largest[$0] * 0.25 < borders[$1] + largest[$1] * 0.25 }
        if let background { append(background, .background, "A large, flat region reaching the image edges.") }

        if graphic, let background {
            let bg = candidates[background].value
            if let surface = candidates.indices.filter({
                !used.contains($0) && largest[$0] / total >= 0.025 && candidates[$0].value.oklch.chroma < 0.10
                    && contrast(bg, candidates[$0].value) > 1.06 && contrast(bg, candidates[$0].value) < 3
            }).max(by: { largest[$0] < largest[$1] }) {
                append(surface, .surface, "A separate flat region with gentle contrast against the background.")
            }
            if let foreground = candidates.indices.filter({
                !used.contains($0) && counts[$0] / total >= 0.001 && counts[$0] / total < 0.30
                    && candidates[$0].value.oklch.chroma < 0.065 && contrast(bg, candidates[$0].value) >= 3
            }).max(by: { contrast(bg, candidates[$0].value) * sqrt(counts[$0]) < contrast(bg, candidates[$1].value) * sqrt(counts[$1]) }) {
                append(foreground, .foreground, "A contrasting neutral used in foreground details; this is not text recognition.")
            }
        }
        func appendGroup(_ color: PaletteColor, _ role: PaletteRole, _ reason: String) {
            roles.append(RoleColor(role: role, color: color, reason: reason))
            if let index = candidates.firstIndex(where: { $0.value == color.value }) { used.insert(index) }
        }
        if background == nil, gradients.isEmpty, let main = palette.dominant.first {
            // Photo roles use broad populations: a single fine shade covering 3%
            // is not an honest summary of a blue sky covering most of the image.
            appendGroup(main, .main, "The largest broad color group in this image.")
        }
        if !graphic && gradients.isEmpty {
            let main = roles.first?.color.value
            if let shadow = palette.dominant.first(where: { $0.value != main && $0.value.oklch.lightness < 0.32 && $0.proportion >= 0.02 }) {
                appendGroup(shadow, .shadow, "A substantial group of dark tones.")
            }
            if let highlight = palette.dominant.first(where: { $0.value != main && $0.value.oklch.lightness > 0.88 && $0.proportion >= 0.02 }) {
                appendGroup(highlight, .highlight, "A substantial group of light tones.")
            }
        }

        let reference = background.map { candidates[$0].value } ?? roles.first?.color.value
        func distinctHue(_ a: ColorValue, _ b: ColorValue) -> Bool {
            let a = a.oklch, b = b.oklch
            guard a.chroma >= 0.04, b.chroma >= 0.04 else { return true }
            let delta = abs(a.hue - b.hue)
            return min(delta, 360 - delta) >= 25
        }
        func accentScore(_ i: Int) -> Double {
            let chroma = candidates[i].value.oklch.chroma
            let prominence = sqrt(counts[i] / total) * (0.6 + centers[i] / max(1, counts[i]))
            let separation = reference.map { min(3, contrast($0, candidates[i].value)) } ?? 1
            return chroma * prominence * separation
        }
        let accents = candidates.indices.filter { i in
            !used.contains(i) && candidates[i].value.oklch.chroma >= 0.065 && counts[i] / total >= 0.001
                && (graphic ? largest[i] >= max(3, total * 0.0005) : counts[i] / total >= 0.006)
                && outsideGradients[i] >= max(3, counts[i] * 0.5)
                && (reference.map { distinctHue($0, candidates[i].value) } ?? true)
        }.sorted { accentScore($0) == accentScore($1) ? $0 < $1 : accentScore($0) > accentScore($1) }
        var selectedAccents: [Int] = []
        for i in accents {
            // Preserve distinct accents, rather than labeling three nearby shades.
            guard selectedAccents.allSatisfy({ simd_distance_squared(labs[$0], labs[i]) > 0.0064
                && distinctHue(candidates[$0].value, candidates[i].value) }) else { continue }
            append(i, .accent, graphic ? "A distinct chromatic color in a coherent region." : "A chromatic color with visual presence, weighted by area and position.")
            selectedAccents.append(i)
            if selectedAccents.count == 3 { break }
        }
        return PaletteAnalysis(roles: roles, gradients: gradients)
    }

    private static func contrast(_ a: ColorValue, _ b: ColorValue) -> Double {
        func luminance(_ c: ColorValue) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c.red) + 0.7152 * linear(c.green) + 0.0722 * linear(c.blue)
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

struct AnalysisRaster {
    let width: Int, height: Int
    let colors: [ColorValue]
    let rgb: [SIMD3<Double>]
    let labs: [SIMD3<Double>]
    let opaque: [Bool]

    init(rgba: [UInt8], width sourceWidth: Int, height sourceHeight: Int) throws {
        guard sourceWidth > 0, sourceHeight > 0, sourceWidth <= 100_000, sourceHeight <= 100_000,
              sourceWidth * sourceHeight <= 1_048_576, rgba.count == sourceWidth * sourceHeight * 4 else { throw PaletteError.invalidPixels }
        let scale = min(1, 160 / Double(max(sourceWidth, sourceHeight)))
        width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var colors: [ColorValue] = []
        for y in 0..<height {
            try Task.checkCancellation()
            let sy = y * (sourceHeight - 1) / max(1, height - 1)
            for x in 0..<width {
                let sx = x * (sourceWidth - 1) / max(1, width - 1), i = (sy * sourceWidth + sx) * 4
                colors.append(ColorValue(red: Double(rgba[i]) / 255, green: Double(rgba[i + 1]) / 255,
                                         blue: Double(rgba[i + 2]) / 255, alpha: Double(rgba[i + 3]) / 255))
            }
        }
        self.colors = colors
        rgb = colors.map { SIMD3($0.red, $0.green, $0.blue) }
        labs = colors.map(Self.lab)
        opaque = colors.map { $0.alpha >= 0.95 }
    }
    static func lab(_ c: ColorValue) -> SIMD3<Double> {
        let o = c.oklch, angle = o.hue * .pi / 180
        return SIMD3(o.lightness, o.chroma * cos(angle), o.chroma * sin(angle))
    }
    func neighbors(of i: Int) -> [Int] {
        let x = i % width, y = i / width
        return [x > 0 ? i - 1 : nil, x + 1 < width ? i + 1 : nil,
                y > 0 ? i - width : nil, y + 1 < height ? i + width : nil].compactMap { $0 }
    }
}
