import CoreGraphics
import Foundation

public struct CaptureSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var x: Int
    public var y: Int
    public var color: ColorValue
    public init(id: UUID = UUID(), x: Int, y: Int, color: ColorValue) { self.id = id; self.x = x; self.y = y; self.color = color }
}

/// One geometry contract for retina previews, letterboxing, dragging, and zoom.
public struct ImageCanvasGeometry: Sendable {
    public let width: Int
    public let height: Int
    public let rect: CGRect
    public init(width: Int, height: Int, bounds: CGRect) {
        self.width = width; self.height = height
        guard width > 0, height > 0, bounds.width > 0, bounds.height > 0 else { rect = .zero; return }
        let scale = min(bounds.width / Double(width), bounds.height / Double(height))
        let size = CGSize(width: Double(width) * scale, height: Double(height) * scale)
        rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
    }
    public func pixel(at point: CGPoint, clamped: Bool = false) -> (x: Int, y: Int)? {
        guard !rect.isEmpty, point.x.isFinite, point.y.isFinite, clamped || rect.contains(point) else { return nil }
        return (min(width - 1, max(0, Int((point.x - rect.minX) / rect.width * Double(width)))),
                min(height - 1, max(0, Int((point.y - rect.minY) / rect.height * Double(height)))))
    }
    public func point(x: Int, y: Int) -> CGPoint {
        CGPoint(x: rect.minX + (Double(x) + 0.5) / Double(max(1, width)) * rect.width,
                y: rect.minY + (Double(y) + 0.5) / Double(max(1, height)) * rect.height)
    }
}
