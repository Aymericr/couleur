import Foundation
import simd

public struct ImageRegion: Equatable, Sendable {
    /// Normalized image coordinates, measured from the top left.
    public let x: Double, y: Double, width: Double, height: Double
}

public struct GradientStop: Equatable, Sendable {
    public let color: ColorValue
    public let location: Double
}

public struct DetectedGradient: Equatable, Identifiable, Sendable {
    public let stops: [GradientStop]
    /// CSS convention: 0 degrees points up, 90 right, 180 down.
    public let angle: Double
    public let region: ImageRegion
    public var id: String { "\(region.x)-\(region.y)-\(region.width)-\(region.height)" }

    public var css: String {
        let values = stops.map { "\($0.color.hex) \(Self.number($0.location * 100))%" }.joined(separator: ", ")
        return "linear-gradient(\(Self.number(angle))deg, \(values))"
    }
    private static func number(_ value: Double) -> String {
        String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value)
    }
    func position(x: Double, y: Double, aspect: Double) -> Double {
        let dx = sin(angle * .pi / 180), dy = -cos(angle * .pi / 180)
        let w = region.width * aspect, h = region.height
        let minimum = min(0, w * dx) + min(0, h * dy)
        let span = abs(w * dx) + abs(h * dy)
        return (((x - region.x) * aspect * dx + (y - region.y) * dy) - minimum) / max(0.000001, span)
    }
    func matches(_ rgb: SIMD3<Double>, x: Double, y: Double, aspect: Double) -> Bool {
        guard x >= region.x, x <= region.x + region.width, y >= region.y, y <= region.y + region.height else { return false }
        return simd_distance(rgb, Self.interpolate(stops, at: position(x: x, y: y, aspect: aspect))) < 0.05
    }
    static func interpolate(_ stops: [GradientStop], at t: Double) -> SIMD3<Double> {
        func rgb(_ c: ColorValue) -> SIMD3<Double> { SIMD3(c.red, c.green, c.blue) }
        guard let first = stops.first, let last = stops.last else { return .zero }
        if t <= first.location { return rgb(first.color) }
        if t >= last.location { return rgb(last.color) }
        let right = stops.firstIndex { $0.location >= t }!
        let a = stops[right - 1], b = stops[right]
        let f = (t - a.location) / max(0.000001, b.location - a.location)
        return rgb(a.color) * (1 - f) + rgb(b.color) * f
    }
}

/// Detect smooth connected regions, then verify that one spatial axis explains
/// their colors. A palette alone never supplies evidence for a gradient.
enum GradientDetector {
    private struct Rect: Equatable {
        var x: Int, y: Int, w: Int, h: Int
        var area: Int { w * h }
    }

    static func detect(in image: AnalysisRaster) throws -> [DetectedGradient] {
        let w = image.width, h = image.height
        guard w >= 12, h >= 8 else { return [] }
        var smooth = [Bool](repeating: false, count: w * h)
        for y in 1..<(h - 1) {
            try Task.checkCancellation()
            for x in 1..<(w - 1) {
                let i = y * w + x
                guard image.opaque[i], image.neighbors(of: i).allSatisfy({ image.opaque[$0] }) else { continue }
                let center = image.rgb[i]
                let dx = (image.rgb[i + 1] - image.rgb[i - 1]) / 2
                let dy = (image.rgb[i + w] - image.rgb[i - w]) / 2
                let amount = max(simd_length(dx), simd_length(dy))
                let curvature = max(simd_length(image.rgb[i + 1] + image.rgb[i - 1] - center * 2),
                                    simd_length(image.rgb[i + w] + image.rgb[i - w] - center * 2))
                smooth[i] = amount > 0.002 && amount < 0.065 && curvature < 0.025
            }
        }
        var candidates = [Rect(x: 0, y: 0, w: w, h: h)]
        var visited = [Bool](repeating: false, count: w * h)
        for start in smooth.indices where smooth[start] && !visited[start] {
            var queue = [start], cursor = 0
            visited[start] = true
            var x0 = start % w, x1 = x0, y0 = start / w, y1 = y0
            while cursor < queue.count {
                let i = queue[cursor]; cursor += 1
                x0 = min(x0, i % w); x1 = max(x1, i % w)
                y0 = min(y0, i / w); y1 = max(y1, i / w)
                for n in image.neighbors(of: i) where smooth[n] && !visited[n] { visited[n] = true; queue.append(n) }
            }
            guard queue.count >= max(48, w * h / 50), x1 - x0 >= 10, y1 - y0 >= 6 else { continue }
            x0 = max(0, x0 - 1); y0 = max(0, y0 - 1); x1 = min(w - 1, x1 + 1); y1 = min(h - 1, y1 + 1)
            let rect = Rect(x: x0, y: y0, w: x1 - x0 + 1, h: y1 - y0 + 1)
            if !candidates.contains(rect) { candidates.append(rect) }
        }
        var results: [DetectedGradient] = []
        for rect in candidates.sorted(by: { $0.area > $1.area }).prefix(12) {
            try Task.checkCancellation()
            guard let gradient = fit(rect, image: image, smooth: smooth) else { continue }
            let r = gradient.region
            if results.contains(where: {
                let a = $0.region
                let overlap = max(0, min(a.x + a.width, r.x + r.width) - max(a.x, r.x))
                    * max(0, min(a.y + a.height, r.y + r.height) - max(a.y, r.y))
                return overlap / min(a.width * a.height, r.width * r.height) > 0.55
            }) { continue }
            results.append(gradient)
            if results.count == 3 { break }
        }
        return results
    }

    private static func fit(_ rect: Rect, image: AnalysisRaster, smooth: [Bool]) -> DetectedGradient? {
        let w = image.width
        var xx = 0.0, yy = 0.0, xy = 0.0, smoothCount = 0
        var indices: [Int] = []
        for y in rect.y..<(rect.y + rect.h) {
            for x in rect.x..<(rect.x + rect.w) {
                let i = y * w + x
                if image.opaque[i] { indices.append(i) }
                guard smooth[i] else { continue }
                let gx = (image.rgb[i + 1] - image.rgb[i - 1]) / 2
                let gy = (image.rgb[i + w] - image.rgb[i - w]) / 2
                xx += simd_dot(gx, gx); yy += simd_dot(gy, gy); xy += simd_dot(gx, gy); smoothCount += 1
            }
        }
        guard Double(indices.count) / Double(rect.area) > 0.95,
              Double(smoothCount) / Double(rect.area) > 0.55 else { return nil }
        let direction = 0.5 * atan2(2 * xy, xx - yy)
        let dx = cos(direction), dy = sin(direction)
        let span = abs(Double(rect.w - 1) * dx) + abs(Double(rect.h - 1) * dy)
        let minimum = min(0, Double(rect.w - 1) * dx) + min(0, Double(rect.h - 1) * dy)
        func position(_ i: Int) -> Double {
            (Double(i % w - rect.x) * dx + Double(i / w - rect.y) * dy - minimum) / max(0.000001, span)
        }
        // Robust bin medians tolerate a small amount of text or an overlaid icon.
        // Each stop is then snapped to an observed pixel, not an invented average.
        var bins = [[Int]](repeating: [], count: 25)
        for i in indices { bins[min(24, max(0, Int((position(i) * 24).rounded())))].append(i) }
        var stops: [GradientStop] = []
        for bin in bins where !bin.isEmpty {
            var median = SIMD3<Double>.zero
            for c in 0..<3 { median[c] = bin.map { image.rgb[$0][c] }.sorted()[bin.count / 2] }
            let best = bin.min {
                let a = simd_distance_squared(image.rgb[$0], median), b = simd_distance_squared(image.rgb[$1], median)
                return a == b ? $0 < $1 : a < b
            }!
            stops.append(GradientStop(color: image.colors[best], location: position(best)))
        }
        guard stops.count >= 12, let first = stops.first, let last = stops.last else { return nil }
        // Endpoints use actual end pixels. Narrow outer bins avoid pulling a 0%
        // stop into the interior of the gradient.
        for (index, target) in [(0, 0.0), (stops.count - 1, 1.0)] {
            let end = indices.min { abs(position($0) - target) < abs(position($1) - target) }!
            stops[index] = GradientStop(color: image.colors[end], location: target)
        }
        guard last.location - first.location > 0.9 else { return nil }
        let range = stops.indices.map { i in stops.map { simd_distance(AnalysisRaster.lab(stops[i].color), AnalysisRaster.lab($0.color)) }.max()! }.max()!
        guard range >= 0.08 else { return nil }
        stops = simplify(stops)
        guard stops.count <= 8 else { return nil }
        var accurate = 0, error = 0.0
        for i in indices {
            let distance = simd_distance(image.rgb[i], DetectedGradient.interpolate(stops, at: position(i)))
            if distance <= 0.045 { accurate += 1 }
            error += min(0.1, distance) * min(0.1, distance)
        }
        guard Double(accurate) / Double(indices.count) >= 0.94, sqrt(error / Double(indices.count)) <= 0.028 else { return nil }
        let angle = (atan2(dx, -dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
        return DetectedGradient(stops: stops, angle: angle,
                                region: ImageRegion(x: Double(rect.x) / Double(image.width), y: Double(rect.y) / Double(image.height),
                                                    width: Double(rect.w) / Double(image.width), height: Double(rect.h) / Double(image.height)))
    }

    private static func simplify(_ stops: [GradientStop]) -> [GradientStop] {
        guard stops.count > 2 else { return stops }
        let endpoints = [stops.first!, stops.last!]
        let worst = (1..<(stops.count - 1)).max { a, b in
            func error(_ i: Int) -> Double {
                let c = stops[i].color
                return simd_distance(SIMD3(c.red, c.green, c.blue), DetectedGradient.interpolate(endpoints, at: stops[i].location))
            }
            return error(a) < error(b)
        }!
        let c = stops[worst].color
        if simd_distance(SIMD3(c.red, c.green, c.blue), DetectedGradient.interpolate(endpoints, at: stops[worst].location)) <= 0.014 { return endpoints }
        return Array(simplify(Array(stops[...worst])).dropLast()) + simplify(Array(stops[worst...]))
    }
}
