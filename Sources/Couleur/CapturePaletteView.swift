import AppKit
import CouleurCore
import SwiftUI

struct CapturePaletteView: View {
    @ObservedObject var store: ColorStore
    let capture: ScreenPalette
    @State private var sort: PaletteOrder = .amount
    @State private var savePrompt = false
    @State private var saveSelection: CapturePaletteSelection = .roles
    @State private var paletteName = ""
    @State private var selectedPixel: ImagePixel?
    @State private var shownGradientID: String?
    @State private var copiedGradientID: String?
    @State private var gradientFeedbackTask: Task<Void, Never>?
    @State private var analysisExpanded = false
    @State private var sourcePresented = false

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
                HStack(spacing: 8) {
                    Button(action: store.showCaptures) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium)).frame(width: 24, height: 24)
                    }.buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary).help("All captures").accessibilityLabel("Back to captures")
                    TextField("Name this capture", text: Binding(get: { capture.record.name }, set: { name in store.updateCapture(capture.id) { $0.name = name } }))
                        .font(.system(size: 17, weight: .semibold)).tracking(-0.3).textFieldStyle(.plain)
                        .accessibilityLabel("Capture name").disabled(store.readOnly)
                    Spacer(minLength: 8)
                    Button { sourcePresented.toggle() } label: {
                        Image(systemName: "info.circle").frame(width: 24, height: 24)
                    }.buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary)
                        .help("Source details").accessibilityLabel("Capture source details")
                        .popover(isPresented: $sourcePresented) { captureSource.frame(width: 300).padding(20) }
                }
                CapturePaletteEditor(store: store, capture: capture) { beginSave(.curated) }
                DisclosureGroup(isExpanded: $analysisExpanded) {
                VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Text("Suggestions from the image").font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Menu("Save colors…") {
                        Button("Suggested roles…") { beginSave(.roles) }.disabled(capture.colors.analysis.roles.isEmpty)
                        Button("Dominant colors…") { beginSave(.dominant) }
                        Button("All \(capture.colors.shades.count) shades…") { beginSave(.shades) }
                    }.controlSize(.small).fixedSize().disabled(store.readOnly)
                }
                if !capture.colors.analysis.roles.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        sectionTitle("Color roles", detail: "Suggested")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 180), spacing: 14)], alignment: .leading, spacing: 16) {
                            ForEach(capture.colors.analysis.roles) { role in
                                CaptureSwatch(store: store, captureID: capture.id, color: role.color, prominent: false, title: role.role.rawValue) {
                                    selectedPixel = nil
                                    store.keepCapturedColor(role.color.value, proportion: role.color.proportion)
                                }.help(role.reason + " Click to copy and keep.")
                            }
                        }
                        Text("Inferred from color, contrast, and placement. Names stay editable.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if !capture.colors.analysis.gradients.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Gradients", detail: "Estimated · linear")
                        ForEach(capture.colors.analysis.gradients) { gradient in
                            gradientView(gradient)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle("Dominant colors", detail: "By area")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 10, alignment: .topLeading),
                                             count: max(1, capture.colors.dominant.count)), alignment: .leading, spacing: 10) {
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
                }.padding(.top, 18)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.hexagongrid").foregroundStyle(.secondary)
                        Text("Explore more colors").font(.system(size: 12))
                    }
                }
            }.padding(22)
        }
        .alert("Save Palette", isPresented: $savePrompt) {
            TextField("Collection name", text: $paletteName)
            Button("Save") { store.saveCapturePalette(name: paletteName, selection: saveSelection) }
                .disabled(paletteName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keep \(saveSelection.colors(in: capture).count) colors in a named collection.")
        }
        .onDisappear { gradientFeedbackTask?.cancel() }
    }

    private func beginSave(_ selection: CapturePaletteSelection) {
        saveSelection = selection
        paletteName = capture.record.name
        savePrompt = true
    }

    private var captureSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                SourceIcon(source: capture.record.source, size: 14)
                Text(capture.record.source.appName ?? "Screen capture")
                Text("·").foregroundStyle(.tertiary)
                Text(capture.createdAt.formatted(date: .abbreviated, time: .shortened))
                Spacer(minLength: 0)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("Add source website…", text: Binding(get: { capture.record.source.websiteURL ?? "" }, set: { text in
                    store.updateCapture(capture.id) { $0.source.websiteURL = text.isEmpty ? nil : text }
                })).textFieldStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .accessibilityLabel("Capture source website").disabled(store.readOnly)
                    .help("Remembered from supported browsers with Automation access. You can also paste a website here.")
                if let url = capture.record.website {
                    Link(destination: url) { Image(systemName: "arrow.up.right").font(.system(size: 10)) }
                        .help("Open \(capture.record.websiteName ?? "source website")").accessibilityLabel("Open source website")
                }
            }
        }
    }

    private func gradientView(_ gradient: DetectedGradient) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            LinearGradient(stops: gradient.stops.map { .init(color: $0.color.color, location: $0.location) },
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 42).clipShape(RoundedRectangle(cornerRadius: 6)).modifier(SwatchRim(radius: 6))
                .accessibilityLabel("Estimated linear gradient with \(gradient.stops.count) stops")
            HStack {
                Text("\(gradient.angle.formatted(.number.precision(.fractionLength(0))))° · \(gradient.stops.count) stops")
                    .foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                Button("Show region") { shownGradientID = gradient.id }.buttonStyle(.link)
                    .popover(isPresented: Binding(get: { shownGradientID == gradient.id }, set: { if !$0 { shownGradientID = nil } })) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Gradient region").font(.system(size: 12, weight: .semibold))
                            CaptureImageView(image: capture.image, selectedPixel: nil, highlightedRegion: gradient.region, hover: { _ in }) { pixel in
                                store.keepCapturedColor(pixel.color, x: pixel.x, y: pixel.y)
                            }.frame(width: 340, height: 220)
                            Text("Estimated from this area. Click the image to keep an exact color.")
                                .font(.system(size: 10)).foregroundStyle(.secondary)
                        }.padding(16)
                    }
                Button {
                    guard store.copyGradient(gradient) else { return }
                    copiedGradientID = gradient.id
                    gradientFeedbackTask?.cancel()
                    gradientFeedbackTask = Task {
                        try? await Task.sleep(for: .seconds(2))
                        if !Task.isCancelled { copiedGradientID = nil }
                    }
                } label: {
                    Label(copiedGradientID == gradient.id ? "Copied" : "Copy CSS", systemImage: copiedGradientID == gradient.id ? "checkmark" : "doc.on.doc")
                        .frame(minWidth: 72)
                }.buttonStyle(.bordered).controlSize(.small)
            }.font(.system(size: 10))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 86, maximum: 115), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(Array(gradient.stops.enumerated()), id: \.offset) { index, stop in
                    Button {
                        selectedPixel = nil
                        store.keepCapturedColor(stop.color, name: "Gradient stop \(index + 1)")
                    } label: {
                        HStack(spacing: 4) {
                            Swatch(value: stop.color).frame(width: 14, height: 14).modifier(SwatchRim(radius: 3))
                                .overlay {
                                    Image(systemName: "checkmark").font(.system(size: 8, weight: .semibold))
                                        .frame(width: 14, height: 14).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 3))
                                        .opacity(stopWasCopied(stop) ? 1 : 0)
                                }
                            Text(stop.color.hex).font(.system(size: 9, design: .monospaced))
                        }
                    }.buttonStyle(QuietButtonStyle()).help("Copy & keep stop \(index + 1) · \(stop.color.hex)")
                        .accessibilityLabel("Gradient stop \(index + 1), \(stop.color.hex)")
                        .accessibilityValue(stopWasCopied(stop) ? "Copied" : stop.color.formatted(store.copyFormat))
                }
            }
        }
    }
    private func stopWasCopied(_ stop: GradientStop) -> Bool {
        store.selected?.source.capture?.id == capture.id && store.selected?.value == stop.color
            && store.copiedColorID != nil && store.copiedColorID == store.selectedID
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
    var title: String? = nil
    let action: () -> Void

    private var selected: Bool { store.selected?.source.capture?.id == captureID && store.selected?.value == color.value }
    private var copied: Bool { selected && store.copiedColorID == store.selectedID }
    private var percentage: String {
        color.proportion < 0.01 ? "<1%" : color.proportion.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                if let title { Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary) }
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
            .accessibilityLabel("\(title.map { $0 + ", " } ?? "")\(color.value.hex), \(percentage) of capture")
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
    let highlightedRegion: ImageRegion?
    let hover: (ImagePixel?) -> Void
    let pick: (ImagePixel) -> Void
    func makeNSView(context: Context) -> ImageView { ImageView() }
    func updateNSView(_ view: ImageView, context: Context) {
        view.image = image; view.hover = hover; view.pick = pick
        view.selectedPixel = selectedPixel; view.needsDisplay = true
        view.highlightedRegion = highlightedRegion
    }

    final class ImageView: NSView {
        var image: PaletteImage?
        var hover: ((ImagePixel?) -> Void)?
        var pick: ((ImagePixel) -> Void)?
        var selectedPixel: ImagePixel?
        var highlightedRegion: ImageRegion?
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
            if let region = highlightedRegion {
                let rect = NSRect(x: imageRect.minX + region.x * imageRect.width, y: imageRect.minY + region.y * imageRect.height,
                                  width: region.width * imageRect.width, height: region.height * imageRect.height).insetBy(dx: 1, dy: 1)
                let outline = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
                NSColor.black.withAlphaComponent(0.7).setStroke(); outline.lineWidth = 3; outline.stroke()
                NSColor.white.setStroke(); outline.lineWidth = 1; outline.stroke()
            }
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
