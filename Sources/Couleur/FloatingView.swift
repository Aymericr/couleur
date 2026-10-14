import AppKit
import CouleurCore
import SwiftUI

/// A pocket palette: one color well, one value, and a quiet row of recent picks.
struct FloatingView: View {
    static let size = NSSize(width: 256, height: 158)
    @ObservedObject var store: ColorStore
    let pick: () -> Void
    let capture: () -> Void
    let showLibrary: () -> Void
    let close: () -> Void
    let togglePin: () -> Void
    let isPinned: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveringValue = false
    @State private var hoveringWell = false

    private var current: SavedColor? { store.selected ?? store.recent.first }
    private var value: ColorValue { current?.value ?? ColorValue(red: 1, green: 1, blue: 1) }
    private var copied: Bool { current != nil && store.copiedColorID == current?.id }
    private var compactCode: String {
        switch store.copyFormat {
        case .swiftUI, .nsColor, .uiColor: value.hex
        default: value.formatted(store.copyFormat)
        }
    }
    private var isShortCode: Bool { compactCode.count <= 10 }
    private var surface: Color { colorScheme == .dark ? Color(white: 0.115) : Color(white: 0.985) }
    private var rimOpacity: Double { contrast == .increased ? 0.35 : (colorScheme == .dark ? 0.15 : 0.10) }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 36)
            HStack(spacing: 14) {
                colorWell
                valueAndFormat
            }.padding(.horizontal, 16).frame(height: 70)
            history.padding(.horizontal, 16).frame(height: 52)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(rimOpacity), lineWidth: 0.5).allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Couleur").font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(WindowDragRegion())
            Button(action: capture) {
                Image(systemName: "viewfinder").font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary).frame(width: 26, height: 24)
            }.buttonStyle(QuietButtonStyle()).help("Capture a palette · ⌘⇧A").accessibilityLabel("Capture screen palette")
                .disabled(store.isSampling || store.readOnly)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary).frame(width: 20, height: 24)
            }.buttonStyle(QuietButtonStyle()).help("Hide picker · ⌘W").accessibilityLabel("Hide picker")
        }.padding(.leading, 17).padding(.trailing, 11)
    }

    private var colorWell: some View {
        Swatch(value: value).frame(width: 64, height: 64)
            .modifier(SwatchRim(radius: 11))
            .overlay {
                Image(systemName: "eyedropper")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(wellInk.opacity(hoveringWell ? 0.85 : 0.55))
                    .allowsHitTesting(false)
            }
            .overlay(PickSurface(action: pick, enabled: !store.isSampling && !store.readOnly))
            .onHover { hoveringWell = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringWell)
            .help("Press, drag, and release to pick · ⌃⌥C · Hold Shift for more")
    }

    private var wellInk: Color {
        // Composite against the checkerboard's average for translucent colors.
        let luminance = (value.red * 0.2126 + value.green * 0.7152 + value.blue * 0.0722) * value.alpha + 0.87 * (1 - value.alpha)
        return luminance > 0.55 ? .black : .white
    }

    private var valueAndFormat: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { if let current { store.copy(current) } else { pick() } } label: {
                Text(current == nil ? "Pick a color" : compactCode)
                    .font(.system(size: current == nil ? 17 : (isShortCode ? 19 : 12), weight: .regular,
                                  design: current == nil ? .default : .monospaced))
                    .tracking(isShortCode ? -0.55 : -0.25)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle())
                .accessibilityLabel(current == nil ? "Pick a color" : "Copy \(store.copyFormat.rawValue) color")
                .accessibilityValue(copied ? "Copied" : compactCode)
                .help("Copy \(value.formatted(store.copyFormat))")
            HStack(spacing: 8) {
                formatMenu
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
                    .opacity(copied || hoveringValue ? 1 : 0)
                    .accessibilityHidden(true)
                Spacer(minLength: 0)
            }.frame(height: 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onHover { hoveringValue = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringValue)
    }

    private var formatMenu: some View {
        Menu {
            Picker("Copy as", selection: $store.copyFormat) {
                ForEach(CopyFormat.allCases) { Text($0.rawValue).tag($0) }
            }
            Divider()
            Toggle("Copy automatically", isOn: $store.autoCopy)
            Toggle("Keep on top", isOn: Binding(get: { isPinned }, set: { _ in togglePin() }))
            Divider()
            Button("Paste color from clipboard", action: store.paste)
            Button("Open color library", action: showLibrary)
            if store.error != nil { Button("View save issue…", action: showLibrary) }
        } label: { Text(store.copyFormat.compactName) }
            .font(.system(size: 10)).foregroundStyle(.secondary)
            .menuStyle(.borderlessButton).menuIndicator(.visible).controlSize(.mini).fixedSize()
            .help("Copy format & options").accessibilityLabel("Copy format and options")
    }

    private var history: some View {
        HStack(spacing: 7) {
            if store.recent.isEmpty {
                Text("Drag the color well to pick")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.recent.prefix(6)) { record in
                    Button {
                        store.selectedID = record.id
                        store.copy(record)
                    } label: {
                        Swatch(value: record.value).frame(width: 20, height: 20)
                            .modifier(SwatchRim(radius: 5))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(.primary.opacity(current?.id == record.id ? 0.30 : 0), lineWidth: 1)
                                    .padding(-2.5)
                            }
                            .frame(width: 24, height: 28)
                    }.buttonStyle(QuietButtonStyle())
                        .help("Copy \(record.name) · \(record.value.hex)")
                        .accessibilityLabel("Copy recent color \(record.name)")
                        .accessibilityAddTraits(current?.id == record.id ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            Button(action: showLibrary) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
                    .frame(width: 24, height: 28)
            }.buttonStyle(QuietButtonStyle()).help("Open color library · ⌘1").accessibilityLabel("Expand library")
        }
    }
}

/// The quiet header provides native window dragging; the well retains mouse-down picking.
private struct WindowDragRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
    final class DragView: NSView {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

/// Begin on mouse-down so the sampler can finish on the same drag's release.
struct PickSurface: NSViewRepresentable {
    var action: () -> Void
    var enabled: Bool
    func makeNSView(context: Context) -> PickTrackingView { PickTrackingView() }
    func updateNSView(_ view: PickTrackingView, context: Context) {
        view.action = action; view.enabled = enabled
        view.toolTip = "Press, drag, and release to save & copy. Hold Shift to collect more colors."
    }
}

@MainActor
final class PickTrackingView: NSView {
    var action: (() -> Void)?
    var enabled = true
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if enabled { action?() } }
    override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .crosshair) } }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Pick from screen" }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }; action?(); return true
    }
}
