import CoreGraphics
import Foundation
import Testing
@testable import CouleurCore

@Test func perceptualConversionRoundTripsAndMapsGamutWithoutClippingHue() throws {
    for hex in ["FF0000", "00FF00", "0000FF", "FFFFFF", "000000", "5287C4", "BC8B73"] {
        let value = try #require(ColorValue.parse(hex)), o = value.oklch
        let roundTrip = ColorValue.perceptual(lightness: o.lightness, chroma: o.chroma, hue: o.hue)
        #expect(abs(value.red - roundTrip.red) < 0.0001)
        #expect(abs(value.green - roundTrip.green) < 0.0001)
        #expect(abs(value.blue - roundTrip.blue) < 0.0001)
    }
    let mapped = ColorValue.perceptual(lightness: 0.7, chroma: 0.5, hue: 180)
    #expect(mapped.isValid)
    #expect(abs(mapped.oklch.lightness - 0.7) < 0.00001)
    #expect(abs(mapped.oklch.hue - 180) < 0.001)
    #expect(mapped.oklch.chroma < 0.5)
}

@Test func namesAndFamiliesHandleNeutralsAndKeepPersonalNames() throws {
    #expect(try #require(ColorValue.parse("FAFAFA")).family == .neutral)
    #expect(try #require(ColorValue.parse("5287C4")).family == .blue)
    #expect(try #require(ColorValue.parse("77543D")).family == .earth)
    #expect(try #require(ColorValue.parse("365DE1")).suggestedName == "Cobalt")
    let value = try #require(ColorValue.parse("365DE1"))
    #expect(SavedColor(name: "Client's primary", value: value).displayName == "Client's primary")
    #expect(SavedColor(name: value.hex, value: value).displayName == "Cobalt")
    #expect(ColorValue(red: 1, green: 0, blue: 0, alpha: 0).suggestedName == "Transparent")
}

@Test func harmoniesPreserveBaseAndTonalLightnessIsOrdered() throws {
    let base = try #require(ColorValue.parse("5287C4"))
    let opposite = ColorHarmony.complementary.colors(for: base)
    #expect(opposite.count == 2 && opposite[0] == base)
    let difference = abs(opposite[0].oklch.hue - opposite[1].oklch.hue)
    #expect(abs(difference - 180) < 0.001)
    for harmony in ColorHarmony.allCases { #expect(harmony.colors(for: base).allSatisfy { $0.isValid }) }
    let tonal = ColorHarmony.tonal.colors(for: base)
    #expect(tonal.count == 5)
    #expect(zip(tonal, tonal.dropFirst()).allSatisfy { $0.oklch.lightness > $1.oklch.lightness })
    #expect(abs(tonal.first!.oklch.lightness - 0.95) < 0.00001)
    #expect(abs(tonal.last!.oklch.lightness - 0.28) < 0.00001)
}

@Test func contrastUsesActualAlphaCompositing() {
    let white = ColorValue(red: 1, green: 1, blue: 1), black = ColorValue(red: 0, green: 0, blue: 0)
    #expect(abs(black.contrast(on: white) - 21) < 0.000001)
    #expect(abs(white.contrast(on: white) - 1) < 0.000001)
    let transparent = ColorValue(red: 0, green: 0, blue: 0, alpha: 0)
    #expect(abs(transparent.contrast(on: white) - 1) < 0.000001)
    let halfBlack = ColorValue(red: 0, green: 0, blue: 0, alpha: 0.5)
    #expect(abs(halfBlack.contrast(on: white) - 3.976653) < 0.00001)
}

@Test func canvasCoordinatesRespectLetterboxingEdgesAndRetinaResolution() throws {
    let fit = ImageCanvasGeometry(width: 600, height: 300, bounds: CGRect(x: 0, y: 0, width: 300, height: 200))
    #expect(fit.rect == CGRect(x: 0, y: 25, width: 300, height: 150))
    #expect(fit.pixel(at: CGPoint(x: 20, y: 20)) == nil)
    let last = try #require(fit.pixel(at: fit.point(x: 599, y: 299)))
    #expect(last.x == 599 && last.y == 299)
    let first = try #require(fit.pixel(at: fit.point(x: 0, y: 0)))
    #expect(first.x == 0 && first.y == 0)
    let outside = try #require(fit.pixel(at: CGPoint(x: -50, y: 500), clamped: true))
    #expect(outside.x == 0 && outside.y == 299)
    #expect(ImageCanvasGeometry(width: 0, height: 0, bounds: .zero).pixel(at: .zero) == nil)
}
