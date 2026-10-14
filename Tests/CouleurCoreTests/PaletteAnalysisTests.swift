import CoreGraphics
import Foundation
import Testing
@testable import CouleurCore

private func analyze(_ width: Int = 96, _ height: Int = 64,
                     pixel: (Int, Int) -> ColorValue) throws -> PaletteAnalysis {
    let bytes = (0..<height).flatMap { y in
        (0..<width).flatMap { x -> [UInt8] in
            let c = pixel(x, y)
            return [c.red, c.green, c.blue, c.alpha].map { UInt8(($0 * 255).rounded()) }
        }
    }
    let palette = try PaletteExtractor.extract(rgba: bytes)
    return try PaletteAnalyzer.analyze(rgba: bytes, width: width, height: height, palette: palette)
}

private func blend(_ a: String, _ b: String, _ t: Double) -> ColorValue {
    let a = ColorValue.parse(a)!, b = ColorValue.parse(b)!
    return ColorValue(red: a.red * (1 - t) + b.red * t, green: a.green * (1 - t) + b.green * t,
                      blue: a.blue * (1 - t) + b.blue * t)
}

@Test(arguments: [false, true]) func spatialRolesRecognizeLightAndDarkDesigns(dark: Bool) throws {
    let background = dark ? "#18181B" : "#FAFAFA", surface = dark ? "#303035" : "#EAEAEA"
    let foreground = dark ? "#EEEEEE" : "#242424"
    let result = try analyze(128, 96) { x, y in
        if x >= 16 && x < 34 && y >= 68 && y < 80 { return ColorValue.parse("#7358F5")! }
        if x >= 16 && x < 86 && y >= 24 && y < 50 && y % 8 < 3 { return ColorValue.parse(foreground)! }
        if x >= 8 && x < 120 && y >= 12 && y < 88 { return ColorValue.parse(surface)! }
        return ColorValue.parse(background)!
    }
    #expect(result.roles.first { $0.role == .background }?.color.value.hex == background)
    #expect(result.roles.first { $0.role == .surface }?.color.value.hex == surface)
    #expect(result.roles.first { $0.role == .foreground }?.color.value.hex == foreground)
    #expect(result.roles.first { $0.role == .accent }?.color.value.hex == "#7358F5")
    #expect(result.gradients.isEmpty)
}

@Test func aSmallCoherentAccentSurvivesAWhiteCanvas() throws {
    let result = try analyze(128, 96) { x, y in
        x >= 60 && x < 66 && y >= 45 && y < 51 ? ColorValue.parse("#F4511E")! : ColorValue.parse("#FAFAFA")!
    }
    #expect(result.roles.contains { $0.role == .accent && $0.color.value.hex == "#F4511E" })
}

@Test func linearGradientHasObservedEndpointsAndCopyableDirection() throws {
    let result = try analyze { x, _ in blend("#F4511E", "#7358F5", Double(x) / 95) }
    let gradient = try #require(result.gradients.first)
    #expect(result.gradients.count == 1)
    #expect(abs(gradient.angle - 90) < 0.1)
    #expect(gradient.stops.first?.color.hex == "#F4511E")
    #expect(gradient.stops.last?.color.hex == "#7358F5")
    #expect(gradient.stops.count == 2)
    #expect(gradient.css == "linear-gradient(90.0deg, #F4511E 0.0%, #7358F5 100.0%)")
    #expect(result.roles.isEmpty)
}

@Test func multiStopGradientIsLocatedInsideAFlatDesign() throws {
    let result = try analyze(128, 96) { x, y in
        guard y >= 64 else { return ColorValue.parse("#FAFAFA")! }
        let t = Double(x) / 127
        return t < 0.5 ? blend("#7358F5", "#DA67BA", t * 2) : blend("#DA67BA", "#F4AF72", (t - 0.5) * 2)
    }
    let gradient = try #require(result.gradients.first)
    #expect(abs(gradient.region.y - 2.0 / 3) < 0.03)
    #expect(gradient.region.height < 0.38)
    #expect(gradient.stops.count >= 3)
    #expect(result.roles.first?.role == .background)
    #expect(!result.roles.contains { $0.role == .accent })
}

@Test func diagonalGradientRespectsPixelAspectRatio() throws {
    let result = try analyze(120, 60) { x, y in
        blend("#0E7490", "#E9D5FF", Double(x + y) / 178)
    }
    let gradient = try #require(result.gradients.first)
    #expect(abs(gradient.angle - 135) < 1)
}

@Test func adjacentColorsAndShuffledRampsAreNotGradients() throws {
    let blocks = try analyze { x, _ in ColorValue.parse(x < 48 ? "#F4511E" : "#7358F5")! }
    #expect(blocks.gradients.isEmpty)
    let shuffled = try analyze { x, _ in blend("#F4511E", "#7358F5", Double((x * 37) % 96) / 95) }
    #expect(shuffled.gradients.isEmpty)
}

@Test func texturedImagesDoNotReceiveInterfaceRolesOrFabricatedGradients() throws {
    let result = try analyze { x, y in
        let n = (x * 73 + y * 131 + x * y * 19) % 97
        return ColorValue(red: 0.25 + Double(n) / 200, green: 0.15 + Double((n * 7) % 97) / 160,
                          blue: 0.1 + Double((n * 13) % 97) / 200)
    }
    #expect(result.gradients.isEmpty)
    #expect(!result.roles.contains { [.background, .surface, .foreground].contains($0.role) })
    #expect(result.roles.contains { $0.role == .main })
    #expect(result.roles.contains { $0.role == .accent })
}

@Test func radialShadingIsNotMislabeledAsALinearGradient() throws {
    let result = try analyze { x, y in
        blend("#F4511E", "#7358F5", min(1, hypot(Double(x) - 48, Double(y) - 32) / 55))
    }
    #expect(result.gradients.isEmpty)
}

@Test func tonalPhotoShadesDoNotBecomeDuplicateAccents() throws {
    let result = try analyze { x, y in
        let t = Double((x * 37 + y * 17 + x * y) % 96) / 95
        return blend("#305A8C", "#80ADD6", t)
    }
    #expect(result.gradients.isEmpty)
    #expect(!result.roles.contains { $0.role == .accent })
    #expect((result.roles.first { $0.role == .main }?.color.proportion ?? 0) > 0.1)
}

@Test func gradientEndpointsAreNotAlsoLabeledAsPhotographicTones() throws {
    let result = try analyze { x, _ in blend("#111111", "#FFFFFF", Double(x) / 95) }
    #expect(result.gradients.count == 1)
    #expect(result.roles.isEmpty)
}

@Test func analysisHandlesMonochromeTransparencyAndInvalidGeometry() throws {
    let flat = try analyze { _, _ in ColorValue.parse("#9D8DF1")! }
    #expect(flat.roles.count == 1)
    #expect(flat.roles.first?.role == .background)
    #expect(flat.gradients.isEmpty)
    let transparent = try analyze { _, _ in ColorValue(red: 1, green: 0, blue: 0, alpha: 0.5) }
    #expect(transparent.roles.isEmpty)
    #expect(transparent.gradients.isEmpty)
    let empty = ExtractedPalette(dominant: [], shades: [])
    #expect(throws: PaletteError.self) { try PaletteAnalyzer.analyze(rgba: [255, 0, 0, 255], width: 2, height: 1, palette: empty) }
}

@Test func imagePipelineKeepsGradientRegionInTopLeftCoordinates() throws {
    let w = 96, h = 64
    let bytes = (0..<h).flatMap { y in (0..<w).flatMap { x -> [UInt8] in
        let c = y < 32 ? ColorValue.parse("#FAFAFA")! : blend("#7358F5", "#F4AF72", Double(x) / 95)
        return [c.red, c.green, c.blue, 1].map { UInt8(($0 * 255).rounded()) }
    } }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let image = try #require(CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider,
                                    decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let palette = try PaletteImage(cgImage: image).extract()
    let gradient = try #require(palette.analysis.gradients.first)
    #expect(abs(gradient.region.y - 0.5) < 0.03)
    #expect(gradient.stops.first?.color.hex == "#7358F5")
    #expect(palette.analysis.roles.first?.color.value.hex == "#FAFAFA")
}
