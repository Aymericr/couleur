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
        cgImage = image
    }

    public init(cgImage: CGImage) { self.cgImage = cgImage }

    public func extract() throws -> ExtractedPalette {
        // Bounded, two-dimensional sampling avoids row-stride bias and keeps
        // large Retina captures responsive. No interpolation invents edge colors.
        let scale = min(1, 256 / Double(max(width, height)))
        let w = max(1, Int((Double(width) * scale).rounded()))
        let h = max(1, Int((Double(height) * scale).rounded()))
        return try PaletteExtractor.extract(rgba: Self.rgba(cgImage, width: w, height: h))
    }

    public func color(x: Int, y: Int) -> ColorValue? {
        guard (0..<width).contains(x), (0..<height).contains(y),
              let crop = cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let bytes = try? Self.rgba(crop, width: 1, height: 1) else { return nil }
        return ColorValue(red: Double(bytes[0]) / 255, green: Double(bytes[1]) / 255,
                          blue: Double(bytes[2]) / 255, alpha: Double(bytes[3]) / 255)
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
