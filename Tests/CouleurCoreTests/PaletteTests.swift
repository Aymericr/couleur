import CoreGraphics
import Foundation
import Testing
@testable import CouleurCore

private func pixels(_ values: [(String, Int)]) -> [UInt8] {
    values.flatMap { hex, count in
        let color = ColorValue.parse(hex)!
        let pixel = [color.red, color.green, color.blue, color.alpha].map { UInt8(($0 * 255).rounded()) }
        return Array(repeating: pixel, count: count).flatMap { $0 }
    }
}

@Test func paletteRanksByAreaAndPreservesExactFlatColors() throws {
    let input = [("#FAFAFA", 500), ("#242424", 250), ("#9D8DF1", 125), ("#DB7A58", 75), ("#A8B39E", 50)]
    let palette = try PaletteExtractor.extract(rgba: pixels(input))
    #expect(palette.dominant.map(\.value.hex) == input.map(\.0))
    #expect(palette.shades.count == 5)
    for (color, (_, count)) in zip(palette.dominant, input) {
        #expect(abs(color.proportion - Double(count) / 1000) < 0.000001)
    }
}

@Test func monochromeAndTransparencyDoNotCreateFillerColors() throws {
    let palette = try PaletteExtractor.extract(rgba: pixels([("#E87B65", 100), ("#00FF0000", 500)]))
    #expect(palette.dominant.count == 1)
    #expect(palette.shades.count == 1)
    #expect(palette.dominant.first?.value.hex == "#E87B65")
    #expect(palette.dominant.first?.proportion == 1)
    #expect(throws: PaletteError.self) { try PaletteExtractor.extract(rgba: [0, 0, 0, 0]) }
    #expect(throws: PaletteError.self) { try PaletteExtractor.extract(rgba: [255, 0, 0]) }
}

@Test func detailedPaletteRetainsAccentsAndIsDeterministic() throws {
    let input = pixels([("#FAFAFA", 500), ("#F8F8F8", 300), ("#000000", 50), ("#FF0000", 40),
                        ("#00FF00", 30), ("#0000FF", 25), ("#FFFF00", 20), ("#FF00FF", 15), ("#00FFFF", 10)])
    let result = try PaletteExtractor.extract(rgba: input)
    #expect(result == (try PaletteExtractor.extract(rgba: input)))
    #expect(result.dominant.count <= 5)
    #expect(result.shades.count > result.dominant.count)
    #expect(result.shades.contains { $0.value.hex == "#00FFFF" })
    #expect(Set(result.shades.map(\.id)).count == result.shades.count)
    #expect(abs(result.dominant.reduce(0) { $0 + $1.proportion } - 1) < 0.000001)
    #expect(abs(result.shades.reduce(0) { $0 + $1.proportion } - 1) < 0.000001)
}

@Test func gradientsHaveBoundedPalettesWithObservedRepresentatives() throws {
    let input = (0..<256).flatMap { value in [UInt8(value), UInt8(255 - value), UInt8(128), UInt8(255)] }
    let result = try PaletteExtractor.extract(rgba: input)
    #expect(result.dominant.count == 5)
    #expect(result.shades.count <= 64)
    for color in result.shades {
        #expect(abs(color.value.red + color.value.green - 1) < 0.000001)
        #expect(color.value.blue == Double(128) / 255)
    }
}

@Test func gradientsDoNotDisplaceTheActualDominantFlatColor() throws {
    var input = (0..<256).flatMap { value in [UInt8(value), UInt8(value), UInt8(value), UInt8(255)] }
    input += pixels([("#242424", 2000)])
    let result = try PaletteExtractor.extract(rgba: input, dominantCount: 1)
    #expect(result.dominant.first?.value.hex == "#242424")
    #expect(result.dominant.first?.proportion == 1)
}

@Test func imagePickingUsesTopLeftPixelCoordinatesAndMatchesExtraction() throws {
    let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255,
                          0, 0, 255, 255, 255, 255, 0, 255]
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    let image = try #require(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32,
                                    bytesPerRow: 8, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                    provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let raster = PaletteImage(cgImage: image)
    #expect(raster.color(x: 0, y: 0)?.hex == "#FF0000")
    #expect(raster.color(x: 1, y: 0)?.hex == "#00FF00")
    #expect(raster.color(x: 0, y: 1)?.hex == "#0000FF")
    #expect(raster.color(x: 1, y: 1)?.hex == "#FFFF00")
    #expect(raster.color(x: 2, y: 1) == nil)
    #expect(raster.color(x: -1, y: 0) == nil)
    let palette = try raster.extract()
    #expect(Set(palette.shades.map(\.id)) == ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"])
    #expect(palette.shades.allSatisfy { $0.proportion == 0.25 })
}

@Test func captureMetadataSurvivesExportAndOldLibrariesStillLoad() throws {
    var source = ColorSource(method: "Screen capture")
    source.capture = CaptureSource(width: 640, height: 480, pixelX: 120, pixelY: 70, proportion: 0.32)
    var library = ColorLibrary()
    library.colors = [SavedColor(name: "Red", value: ColorValue(red: 1, green: 0, blue: 0),
                                 createdAt: Date(timeIntervalSince1970: 1_800_000_000), source: source)]
    #expect(try LibraryFile.decode(LibraryFile.encode(library)) == library)
    library.colors[0].source.capture = nil
    let legacyData = try LibraryFile.encode(library)
    #expect(!String(decoding: legacyData, as: UTF8.self).contains("\"capture\""))
    #expect(try LibraryFile.decode(legacyData) == library)
    library.colors[0].source.capture = CaptureSource(width: 640, height: 480, pixelX: 640)
    #expect(throws: LibraryError.self) { try library.validate() }
}
