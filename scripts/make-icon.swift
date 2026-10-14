#!/usr/bin/env swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let colors: [NSColor] = [
    NSColor(srgbRed: 0.91, green: 0.36, blue: 0.34, alpha: 1),
    NSColor(srgbRed: 0.95, green: 0.63, blue: 0.29, alpha: 1),
    NSColor(srgbRed: 0.88, green: 0.77, blue: 0.40, alpha: 1),
    NSColor(srgbRed: 0.39, green: 0.61, blue: 0.48, alpha: 1),
    NSColor(srgbRed: 0.35, green: 0.55, blue: 0.73, alpha: 1),
    NSColor(srgbRed: 0.57, green: 0.45, blue: 0.67, alpha: 1)
]
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let background = NSBezierPath(roundedRect: NSRect(x: 90, y: 90, width: 844, height: 844), xRadius: 190, yRadius: 190)
        let shadow = NSShadow(); shadow.shadowOffset = NSSize(width: 0, height: -12); shadow.shadowBlurRadius = 25; shadow.shadowColor = .black.withAlphaComponent(0.18)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1).setFill(); background.fill()
        NSGraphicsContext.restoreGraphicsState()
        for (index, color) in colors.enumerated() {
            NSGraphicsContext.saveGraphicsState()
            let contextTransform = NSAffineTransform(); contextTransform.translateX(by: 512, yBy: 512)
            contextTransform.rotate(byDegrees: CGFloat(index) * 60 + 15); contextTransform.concat()
            color.setFill()
            NSBezierPath(roundedRect: NSRect(x: -86, y: 14, width: 172, height: 266), xRadius: 82, yRadius: 82).fill()
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(srgbRed: 0.97, green: 0.96, blue: 0.94, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 446, y: 446, width: 132, height: 132)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
