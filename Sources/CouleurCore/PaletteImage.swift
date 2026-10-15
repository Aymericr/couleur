import CoreGraphics
import Foundation
import ImageIO

/// Color-managed image access shared by extraction and exact-pixel picking.
public struct PaletteImage: Sendable {
    public let cgImage: CGImage
    public var width: Int { cgImage.width }
    public var height: Int { cgImage.height }

    public init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0,
              image.width <= 100_000, image.height <= 100_000,
              image.width * image.height <= 100_000_000 else { throw PaletteError.invalidPixels }
        let orientation = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyOrientation] as? Int ?? 1
        if orientation != 1 {
            guard let oriented = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(image.width, image.height)
            ] as CFDictionary) else { throw PaletteError.invalidPixels }
            cgImage = oriented
        } else { cgImage = image }
    }

    public init(cgImage: CGImage) { self.cgImage = cgImage }

    public func pngData() throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { throw PaletteError.invalidPixels }
        CGImageDestinationAddImage(destination, cgImage, nil)
        guard CGImageDestinationFinalize(destination) else { throw PaletteError.invalidPixels }
        return data as Data
    }

    public func extract() throws -> ExtractedPalette {
        // Bounded, two-dimensional sampling avoids row-stride bias and keeps
        // large Retina captures responsive. No interpolation invents edge colors.
        let scale = min(1, 256 / Double(max(width, height)))
        let w = max(1, Int((Double(width) * scale).rounded()))
        let h = max(1, Int((Double(height) * scale).rounded()))
        let bytes = try Self.rgba(cgImage, width: w, height: h)
        var palette = try PaletteExtractor.extract(rgba: bytes)
        palette.analysis = try PaletteAnalyzer.analyze(rgba: bytes, width: w, height: h, palette: palette)
        return palette
    }

    public func color(x: Int, y: Int) -> ColorValue? {
        guard (0..<width).contains(x), (0..<height).contains(y),
              let crop = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let bytes = try? Self.rgba(crop, width: 1, height: 1) else { return nil }
        return ColorValue(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255,
                          blue: Double(bytes[2]) / 255, alpha: Double(bytes[3]) / 255)
    }

    /// Locate representative pixels, then read their exact full-resolution color.
    /// A bounded scan keeps photos and large screen captures equally responsive.
    public func samples(matching colors: [ColorValue]) throws -> [CaptureSample] {
        let scale = min(1, 128 / Double(max(width, height)))
        let w = max(1, Int(Double(width) * scale)), h = max(1, Int(Double(height) * scale))
        let bytes = try Self.rgba(cgImage, width: w, height: h)
        var result: [CaptureSample] = []
        for target in colors.prefix(12) {
            var best: (x: Int, y: Int, score: Double)?
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    guard bytes[i + 3] > 0 else { continue }
                    let value = ColorValue(red: Double(bytes[i]) / 255, green: Double(bytes[i + 1]) / 255, blue: Double(bytes[i + 2]) / 255)
                    let score = target.perceptualDistance(to: value) + 0.0001 * (pow(Double(x) / Double(w) - 0.5, 2) + pow(Double(y) / Double(h) - 0.5, 2))
                    if best == nil || score < best!.score { best = (x, y, score) }
                }
            }
            if let best {
                let x = min(width - 1, Int((Double(best.x) + 0.5) * Double(width) / Double(w)))
                let y = min(height - 1, Int((Double(best.y) + 0.5) * Double(height) / Double(h)))
                if let color = color(x: x, y: y), !result.contains(where: { $0.x == x && $0.y == y }) {
                    result.append(CaptureSample(x: x, y: y, color: color))
                }
            }
        }
        return result
    }

    private static func rgba(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw PaletteError.invalidPixels }
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 0 && bytes[i + 3] < 255 {
            let alpha = Double(bytes[i + 3]) / 255
            for channel in 0..<3 { bytes[i + channel] = UInt8(min(255, (Double(bytes[i + channel]) / alpha).rounded())) }
        }
        return bytes
    }
}
