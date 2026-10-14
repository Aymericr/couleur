import CoreGraphics

/// Maps AppKit's global, bottom-left screen coordinates to top-left image pixels.
/// Image dimensions, rather than an assumed Retina scale, determine the mapping.
public struct ScreenPixelGrid: Sendable {
    public let frame: CGRect
    public let width: Int
    public let height: Int

    public init(frame: CGRect, width: Int, height: Int) {
        self.frame = frame
        self.width = width
        self.height = height
    }

    public func pixel(at point: CGPoint) -> (x: Int, y: Int)? {
        guard width > 0, height > 0, frame.width > 0, frame.height > 0,
              point.x >= frame.minX, point.x < frame.maxX,
              point.y >= frame.minY, point.y < frame.maxY else { return nil }
        let x = Int((point.x - frame.minX) / frame.width * Double(width))
        let y = Int((frame.maxY - point.y) / frame.height * Double(height))
        return (min(width - 1, x), min(height - 1, y))
    }

    public func center(x: Int, y: Int) -> CGPoint {
        CGPoint(x: frame.minX + (Double(x) + 0.5) / Double(width) * frame.width,
                y: frame.maxY - (Double(y) + 0.5) / Double(height) * frame.height)
    }
}
