import Foundation
import Testing
@testable import CouleurCore

@Test(arguments: ["#f80", "#FF8800", "FF8800", "rgb(255 136 0)", "rgb(255, 136, 0)", "hsl(32 100% 50%)"])
func parsesOrange(_ input: String) throws {
    let color = try #require(ColorValue.parse(input))
    #expect(color.hex == "#FF8800")
}

@Test func alphaAndPercentages() throws {
    #expect(ColorValue.parse("#f008")?.hex == "#FF000088")
    #expect(ColorValue.parse("#12345678")?.hex == "#12345678")
    #expect(ColorValue.parse("rgb(100% 0% 0% / 50%)")?.hex == "#FF000080")
    #expect(ColorValue.parse("rgba(255, 0, 0, 0.5)")?.hex == "#FF000080")
    #expect(ColorValue.parse("hsla(-120, 100%, 50%, 0.5)")?.hex == "#0000FF80")
    #expect(ColorValue.parse("hsl(720deg 100% 50%)")?.hex == "#FF0000")
}

@Test(arguments: ["", "#ggg", "#12345", "rgb(nan 0 0)", "rgb(inf 0 0)", "hsl(inf 50% 50%)", "url(red)", "red garbage", "rgb(1 2)", "rgb(1 2 3 4 5)", "hsl(0 1 1)"])
func rejectsMalformedInput(_ input: String) { #expect(ColorValue.parse(input) == nil) }

@Test func colorConversions() {
    let red = ColorValue(red: 1, green: 0, blue: 0)
    #expect(red.hsl.hue == 0)
    #expect(red.hsl.saturation == 1)
    #expect(red.hsl.lightness == 0.5)
    #expect(abs(red.oklch.lightness - 0.627955) < 0.00001)
    #expect(abs(red.oklch.chroma - 0.257683) < 0.00001)
    #expect(abs(red.oklch.hue - 29.233885) < 0.0001)
    #expect(ColorValue(red: 0.5, green: 0.5, blue: 0.5).hsl.saturation == 0)
    #expect(ColorValue(red: 0, green: 0, blue: 0).oklch.hue == 0)
}

@Test func roundTripsCSS() throws {
    for r in stride(from: 0.0, through: 1.0, by: 0.2) {
        for g in stride(from: 0.0, through: 1.0, by: 0.2) {
            let original = ColorValue(red: r, green: g, blue: 0.37, alpha: 0.65)
            for format in [CopyFormat.hex, .rgb, .hsl] {
                let parsed = try #require(ColorValue.parse(original.formatted(format)))
                #expect(abs(parsed.red - original.red) < 0.005)
                #expect(abs(parsed.green - original.green) < 0.005)
                #expect(abs(parsed.blue - original.blue) < 0.005)
                #expect(abs(parsed.alpha - original.alpha) < 0.005)
            }
        }
    }
}

@Test func outputFormatsAreExplicitSRGB() {
    let color = ColorValue(red: 0.5, green: 0.25, blue: 1, alpha: 0.5)
    #expect(color.formatted(.swiftUI) == "Color(.sRGB, red: 0.5000, green: 0.2500, blue: 1.0000, opacity: 0.5000)")
    #expect(color.formatted(.nsColor) == "NSColor(srgbRed: 0.5000, green: 0.2500, blue: 1.0000, alpha: 0.5000)")
    #expect(color.formatted(.uiColor) == "UIColor(red: 0.5000, green: 0.2500, blue: 1.0000, alpha: 0.5000)")
    #expect(color.formatted(.rgb) == "rgb(128 64 255 / 0.500)")
}

@Test func clampsOutOfRangeChannels() {
    #expect(ColorValue(red: -1, green: 2, blue: .nan, alpha: .infinity).hex == "#00FF0000")
}
