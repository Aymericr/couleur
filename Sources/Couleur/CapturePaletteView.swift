import AppKit
import CouleurCore
import SwiftUI

struct CapturePaletteView: View {
    @ObservedObject var store: ColorStore
    let capture: ScreenPalette
    @State private var sort: PaletteOrder = .amount
    @State private var savePrompt = false
    @State private var dominantOnly = true
    @State private var paletteName = ""
    @State private var hoveredPixel: ImagePixel?
    @State private var selectedPixel: ImagePixel?

    private var shades: [PaletteColor] {
        switch sort {
        case .amount: capture.colors.shades
        case .hue: capture.colors.shades.sorted {
            let a = $0.value.hsl, b = $1.value.hsl
            // Neutrals first, then the spectrum, with lighter shades first.
            let ah = a.saturation < 0.08 ? -1 : a.hue, bh = b.saturation < 0.08 ? -1 : b.hue
            return ah == bh ? a.lightness > b.lightness : ah < bh
        }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Screen palette").font(.system(size: 20, weight: .semibold)).tracking(-0.4)
                    Spacer(minLength: 8)
                    Menu {
                        Button("Dominant colors…") { beginSave(dominantOnly: true) }
                        Button("All \(capture.colors.shades.count) shades…") { beginSave(dominantOnly: false) }
                    } label: { Label("Save palette", systemImage: "folder.badge.plus") }
                        .menuStyle(.borderlessButton).fixedSize().font(.system(size: 11))
                        .disabled(store.readOnly).accessibilityLabel("Save captured palette")
                }
                VStack(spacing: 9) {
                    CaptureImageView(image: capture.image, selectedPixel: selectedPixel, hover: { hoveredPixel = $0 }) { pixel in
                        selectedPixel = pixel
                        store.keepCapturedColor(pixel.color, x: pixel.x, y: pixel.y)
                    }
                    .frame(height: 190)
                    .background(.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.10), lineWidth: 0.5).allowsHitTesting(false))
                    HStack(spacing: 5) {
                        if let pixel = hoveredPixel {
                            Swatch(value: pixel.color).frame(width: 12, height: 12).modifier(SwatchRim(radius: 3))
                            Text(pixel.color.hex).fontDesign(.monospaced)
                            Text("· \(pixel.x), \(pixel.y)").foregroundStyle(.tertiary)
                        } else {
                            Text("\(capture.image.width) × \(capture.image.height) px").monospacedDigit()
                        }
                        Spacer(minLength: 2)
                        Text("Click image to pick").foregroundStyle(.tertiary)
                    }.font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 14)
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Dominant colors", detail: "By area")
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(capture.colors.dominant) { color in
                            CaptureSwatch(store: store, captureID: capture.id, color: color, prominent: true) {
                                selectedPixel = nil
                                store.keepCapturedColor(color.value, proportion: color.proportion)
                            }
                        }
                    }
                    // A continuous strip makes the relative areas legible at a glance.
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            ForEach(capture.colors.dominant) { color in
                                color.value.color.frame(width: geometry.size.width * color.proportion)
                            }
                        }
                    }.frame(height: 5).clipShape(Capsule()).accessibilityHidden(true)
                }
                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Explore shades").font(.system(size: 12, weight: .semibold))
                        Text("\(shades.count)").font(.system(size: 11)).foregroundStyle(.tertiary)
                        Spacer()
                        Picker("Sort captured shades", selection: $sort) {
                            ForEach(PaletteOrder.allCases) { Text($0.rawValue).tag($0) }
                        }.labelsHidden().controlSize(.mini).fixedSize()
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 90), spacing: 10)], spacing: 14) {
                        ForEach(shades) { color in
                            CaptureSwatch(store: store, captureID: capture.id, color: color, prominent: false) {
                                selectedPixel = nil
                                store.keepCapturedColor(color.value, proportion: color.proportion)
                            }
                        }
                    }
                    Text("Similar shades are grouped. Pick from the image for an exact color.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }.padding(22)
        }
        .alert("Save Palette", isPresented: $savePrompt) {
            TextField("Collection name", text: $paletteName)
            Button("Save") { store.saveCapturePalette(name: paletteName, dominantOnly: dominantOnly) }
                .disabled(paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep \(dominantOnly ? capture.colors.dominant.count : capture.colors.shades.count) colors in a named collection.")
        }
    }

    private func beginSave(dominantOnly: Bool) {
        self.dominantOnly = dominantOnly
        paletteName = "Screen palette · \(capture.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
        savePrompt = true
    }
    private func sectionTitle(_ title: String, detail: String) -> some View {
        HStack {
            Text(title).font(.system(size: 12, weight: .semibold))
            Spacer()
            Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

private enum PaletteOrder: String, CaseIterable, Identifiable {
    case amount = "By area", hue = "By hue"
    var id: Self { self }
}

private struct CaptureSwatch: View {
    @ObservedObject var store: ColorStore
    let captureID: UUID
    let color: PaletteColor
    let prominent: Bool
    let action: () -> Void

    private var selected: Bool { store.selected?.source.capture?.id == captureID && store.selected?.value == color.value }
    private var copied: Bool { selected && store.copiedColorID == store.selectedID }
    private var percentage: String {
        color.proportion < 0.01 ? "<1%" : color.proportion.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Swatch(value: color.value).frame(height: prominent ? 66 : 42).modifier(SwatchRim(radius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2).padding(-3)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.primary).frame(width: 21, height: 21)
                            .background(.regularMaterial, in: Circle()).padding(5).opacity(copied ? 1 : 0)
                    }
                Text(color.value.hex).font(.system(size: 10, design: .monospaced))
                    .tracking(-0.3).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.primary)
                if prominent { Text(percentage).font(.system(size: 10)).foregroundStyle(.secondary) }
            }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle())
            .help("Copy & keep \(color.value.hex) · about \(percentage) of the image")
            .accessibilityLabel("\(color.value.hex), \(percentage) of capture")
            .accessibilityValue(copied ? "Copied" : color.value.formatted(store.copyFormat))
            .accessibilityHint("Copy and save color")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct ImagePixel {
    let x: Int
    let y: Int
    let color: ColorValue
}

/// AppKit maps the fitted preview back to full-resolution pixels. Letterboxing
/// is excluded from hit testing, and hover never touches the library or clipboard.
private struct CaptureImageView: NSViewRepresentable {
    let image: PaletteImage
    let selectedPixel: ImagePixel?
    let hover: (ImagePixel?) -> Void
    let pick: (ImagePixel) -> Void
    func makeNSView(context: Context) -> ImageView { ImageView() }
    func updateNSView(_ view: ImageView, context: Context) {
        view.image = image; view.hover = hover; view.pick = pick
        view.selectedPixel = selectedPixel; view.needsDisplay = true
    }

    final class ImageView: NSView {
        var image: PaletteImage?
        var hover: ((ImagePixel?) -> Void)?
        var pick: ((ImagePixel) -> Void)?
        var selectedPixel: ImagePixel?
        private var tracking: NSTrackingArea?
        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        private var imageRect: NSRect {
            guard let image else { return .zero }
            let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
            return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
        }
        override func draw(_ dirtyRect: NSRect) {
            guard let image else { return }
            NSImage(cgImage: image.cgImage, size: .zero).draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1,
                                                          respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            if let pixel = selectedPixel {
                let rect = imageRect
                let point = NSPoint(x: rect.minX + (CGFloat(pixel.x) + 0.5) / CGFloat(image.width) * rect.width,
                                    y: rect.minY + (CGFloat(pixel.y) + 0.5) / CGFloat(image.height) * rect.height)
                let ring = NSBezierPath(ovalIn: NSRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10))
                NSColor.black.withAlphaComponent(0.7).setStroke(); ring.lineWidth = 3; ring.stroke()
                NSColor.white.setStroke(); ring.lineWidth = 1.5; ring.stroke()
            }
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            tracking = NSTrackingArea(rect: .zero, options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self)
            addTrackingArea(tracking!)
        }
        override func resetCursorRects() { addCursorRect(imageRect, cursor: .crosshair) }
        private func pixel(at point: NSPoint) -> ImagePixel? {
            guard let image, imageRect.contains(point) else { return nil }
            let rect = imageRect
            let x = min(image.width - 1, Int((point.x - rect.minX) / rect.width * CGFloat(image.width)))
            let y = min(image.height - 1, Int((point.y - rect.minY) / rect.height * CGFloat(image.height)))
            guard let color = image.color(x: x, y: y) else { return nil }
            return ImagePixel(x: x, y: y, color: color)
        }
        override func mouseMoved(with event: NSEvent) { hover?(pixel(at: convert(event.locationInWindow, from: nil))) }
        override func mouseExited(with event: NSEvent) { hover?(nil) }
        override func mouseDown(with event: NSEvent) {
            if let pixel = pixel(at: convert(event.locationInWindow, from: nil)) { pick?(pixel) }
        }
        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .image }
        override func accessibilityLabel() -> String? { "Captured image. Click to copy and save an exact pixel color." }
    }
}
