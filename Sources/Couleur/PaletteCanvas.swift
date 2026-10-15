import AppKit
import CouleurCore
import SwiftUI

struct PaletteCanvas: NSViewRepresentable {
    let image: PaletteImage
    let samples: [CaptureSample]
    let selectedID: UUID?
    let enabled: Bool
    let edit: ([CaptureSample], UUID?, Bool) -> Void

    func makeNSView(context: Context) -> CanvasView { CanvasView() }
    func updateNSView(_ view: CanvasView, context: Context) {
        view.image = image; view.samples = samples; view.selectedID = selectedID
        view.enabled = enabled; view.edit = edit; view.needsDisplay = true
    }

    final class CanvasView: NSView {
        var image: PaletteImage?
        var samples: [CaptureSample] = []
        var selectedID: UUID?
        var enabled = true
        var edit: (([CaptureSample], UUID?, Bool) -> Void)?
        private var dragID: UUID?
        private var original: [CaptureSample] = []
        private var grabOffset = CGPoint.zero
        override var isFlipped: Bool { true }
        override var acceptsFirstResponder: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private var geometry: ImageCanvasGeometry {
            ImageCanvasGeometry(width: image?.width ?? 0, height: image?.height ?? 0,
                                bounds: CGRect(x: 18, y: 18, width: max(0, bounds.width - 36), height: max(0, bounds.height - 70)))
        }
        override func resetCursorRects() { if enabled { addCursorRect(geometry.rect, cursor: .crosshair) } }

        override func draw(_ dirtyRect: NSRect) {
            guard let image else { return }
            let rect = geometry.rect
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).addClip()
            NSImage(cgImage: image.cgImage, size: .zero).draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                                                          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.withAlphaComponent(0.10).setStroke()
            let rim = NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 8, yRadius: 8)
            rim.lineWidth = 0.5; rim.stroke()
            for (index, sample) in samples.enumerated() {
                let point = geometry.point(x: sample.x, y: sample.y)
                let selected = selectedID == sample.id
                let radius: CGFloat = selected ? 13 : 10
                let ring = NSBezierPath(ovalIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                NSGraphicsContext.saveGraphicsState()
                let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
                shadow.shadowBlurRadius = 5; shadow.shadowOffset = CGSize(width: 0, height: -1); shadow.set()
                NSColor.white.setFill(); ring.fill()
                NSGraphicsContext.restoreGraphicsState()
                let inner = NSBezierPath(ovalIn: ring.bounds.insetBy(dx: 2, dy: 2))
                NSColor(srgbRed: sample.color.red, green: sample.color.green, blue: sample.color.blue, alpha: 1).setFill(); inner.fill()
                let ink = sample.color.relativeLuminance > 0.4 ? NSColor.black : .white
                let text = NSAttributedString(string: "\(index + 1)", attributes: [.font: NSFont.systemFont(ofSize: selected ? 10 : 9, weight: .semibold), .foregroundColor: ink])
                text.draw(at: CGPoint(x: point.x - text.size().width / 2, y: point.y - text.size().height / 2))
            }
            if let dragID, let sample = samples.first(where: { $0.id == dragID }) { drawLoupe(sample, image: image) }
        }

        private func drawLoupe(_ sample: CaptureSample, image: PaletteImage) {
            let point = geometry.point(x: sample.x, y: sample.y)
            let diameter: CGFloat = 76
            let x = min(bounds.maxX - diameter - 5, max(5, point.x - diameter / 2))
            let y = point.y > diameter + 30 ? point.y - diameter - 24 : point.y + 24
            let rect = CGRect(x: x, y: min(bounds.maxY - diameter - 5, y), width: diameter, height: diameter)
            let side = min(11, image.width, image.height)
            let crop = CGRect(x: max(0, min(image.width - side, sample.x - side / 2)),
                              y: max(0, min(image.height - side, sample.y - side / 2)), width: side, height: side)
            guard let imagePart = image.cgImage.cropping(to: crop) else { return }
            NSGraphicsContext.saveGraphicsState()
            let circle = NSBezierPath(ovalIn: rect)
            circle.addClip()
            NSImage(cgImage: imagePart, size: .zero).draw(in: rect, from: .zero, operation: .copy, fraction: 1,
                                                       respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none])
            let cell = diameter / Double(side)
            let center = CGRect(x: rect.minX + Double(sample.x - Int(crop.minX)) * cell,
                                y: rect.minY + Double(sample.y - Int(crop.minY)) * cell, width: cell, height: cell)
            NSColor.white.setStroke(); let cross = NSBezierPath(rect: center); cross.lineWidth = 2; cross.stroke()
            NSColor.black.setStroke(); cross.lineWidth = 0.75; cross.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.setStroke(); circle.lineWidth = 3; circle.stroke()
            NSColor.black.withAlphaComponent(0.35).setStroke(); circle.lineWidth = 0.5; circle.stroke()
        }

        override func mouseDown(with event: NSEvent) {
            guard enabled, let image else { return }
            window?.makeFirstResponder(self)
            let point = convert(event.locationInWindow, from: nil)
            original = samples; grabOffset = .zero
            // Hit markers before the image boundary, so edge pixels remain draggable.
            if let sample = samples.min(by: { distance($0, point) < distance($1, point) }), distance(sample, point) <= 18 {
                selectedID = sample.id; dragID = sample.id
                let center = geometry.point(x: sample.x, y: sample.y)
                grabOffset = CGPoint(x: point.x - center.x, y: point.y - center.y)
            } else if samples.count < 12, let pixel = geometry.pixel(at: point), let color = image.color(x: pixel.x, y: pixel.y) {
                let sample = CaptureSample(x: pixel.x, y: pixel.y, color: color)
                samples.append(sample); selectedID = sample.id; dragID = sample.id
            } else { return }
            edit?(samples, selectedID, false); needsDisplay = true
        }
        private func distance(_ sample: CaptureSample, _ point: CGPoint) -> Double {
            let center = geometry.point(x: sample.x, y: sample.y)
            return hypot(center.x - point.x, center.y - point.y)
        }
        override func mouseDragged(with event: NSEvent) {
            guard let dragID, let image, let index = samples.firstIndex(where: { $0.id == dragID }) else { return }
            let point = convert(event.locationInWindow, from: nil)
            guard let pixel = geometry.pixel(at: CGPoint(x: point.x - grabOffset.x, y: point.y - grabOffset.y), clamped: true),
                  let color = image.color(x: pixel.x, y: pixel.y) else { return }
            samples[index].x = pixel.x; samples[index].y = pixel.y; samples[index].color = color
            edit?(samples, selectedID, false); needsDisplay = true
        }
        override func mouseUp(with event: NSEvent) {
            guard dragID != nil else { return }
            mouseDragged(with: event)
            dragID = nil; edit?(samples, selectedID, true); needsDisplay = true
        }
        override func keyDown(with event: NSEvent) {
            guard enabled else { return }
            if event.keyCode == 53, dragID != nil {
                samples = original; dragID = nil
                if !samples.contains(where: { $0.id == selectedID }) { selectedID = samples.first?.id }
                edit?(samples, selectedID, false); needsDisplay = true; return
            }
            guard let selectedID, let image, let index = samples.firstIndex(where: { $0.id == selectedID }) else { super.keyDown(with: event); return }
            if event.keyCode == 51 || event.keyCode == 117 {
                samples.remove(at: index); self.selectedID = samples.first?.id
                edit?(samples, self.selectedID, true); needsDisplay = true; return
            }
            let step = event.modifierFlags.contains(.shift) ? 10 : 1
            var x = samples[index].x, y = samples[index].y
            switch event.keyCode {
            case 123: x -= step
            case 124: x += step
            case 125: y += step
            case 126: y -= step
            default: super.keyDown(with: event); return
            }
            x = min(image.width - 1, max(0, x)); y = min(image.height - 1, max(0, y))
            guard let color = image.color(x: x, y: y) else { return }
            samples[index].x = x; samples[index].y = y; samples[index].color = color
            edit?(samples, selectedID, true); needsDisplay = true
        }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .image }
        override func accessibilityLabel() -> String? { "Image palette canvas" }
        override func accessibilityHelp() -> String? { "Click to add a color. Drag numbered points to refine. Arrow keys move a selected point; Shift moves ten pixels. Palette buttons provide keyboard access to every color." }
    }
}
