import AppKit
import CouleurCore
import SwiftUI

/// A pocket palette with immediate access to each way of collecting colors.
struct FloatingView: View {
    static let size = NSSize(width: 256, height: 204)
    @ObservedObject var store: ColorStore
    let pick: (Bool) -> Void
    let capture: () -> Void
    let openImage: () -> Void
    let showLibrary: () -> Void
    let close: () -> Void
    let togglePin: () -> Void
    let isPinned: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveringValue = false
    @State private var hoveringWell = false
    @State private var displayedValue: ColorValue?
    @State private var confirmation: ColorFeedback?
    @State private var handledFeedbackID: UUID?

    private var current: SavedColor? { store.selected ?? store.recent.first }
    private var value: ColorValue { current?.value ?? ColorValue(red: 1, green: 1, blue: 1) }
    private var visibleFeedback: ColorFeedback? { store.isSampling ? nil : store.colorFeedback }
    private var confirmed: Bool { confirmation?.colorID == current?.id && confirmation != nil }
    private var compactCode: String {
        switch store.copyFormat {
        case .swiftUI, .nsColor, .uiColor: value.hex
        default: value.formatted(store.copyFormat)
        }
    }
    private var isShortCode: Bool { compactCode.count <= 10 }
    private var canCollect: Bool { !store.isSampling && !store.isExtracting && !store.readOnly }
    private var rimOpacity: Double { contrast == .increased ? 0.35 : (colorScheme == .dark ? 0.15 : 0.10) }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: 32)
            HStack(spacing: 14) {
                colorWell
                valueAndFormat
            }.padding(.horizontal, 16).frame(height: 72)
            history.padding(.horizontal, 16).frame(height: 40)
            actions.padding(.horizontal, 12).frame(height: 48).padding(.bottom, 12)
        }
        .font(.geist(size: 12))
        .frame(width: Self.size.width, height: Self.size.height)
        .modifier(PickerGlass(tint: value.color))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.primary.opacity(rimOpacity), lineWidth: 0.5).allowsHitTesting(false)
        }
        .onAppear {
            displayedValue = value
            handledFeedbackID = store.colorFeedback?.id
        }
        .onChange(of: value) { _, _ in updateDisplayedColor() }
        .onChange(of: store.isSampling) { _, sampling in
            if !sampling { updateDisplayedColor() }
        }
        .task(id: visibleFeedback?.id) {
            guard let event = visibleFeedback, event.id != handledFeedbackID else {
                if visibleFeedback == nil { confirmation = nil }
                return
            }
            handledFeedbackID = event.id
            withAnimation(.easeOut(duration: 0.15)) { confirmation = event }
            do { try await Task.sleep(for: .milliseconds(1500)) } catch { return }
            withAnimation(.easeOut(duration: 0.15)) { confirmation = nil }
        }
    }

    private func updateDisplayedColor() {
        guard !store.isSampling else { return }
        withAnimation(.easeOut(duration: reduceMotion ? 0.10 : 0.20)) { displayedValue = value }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Text("Couleur").font(.geistPixel(size: 13))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                .overlay(WindowDragRegion())
            Button(action: showLibrary) {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11))
                    .foregroundStyle(.secondary).frame(width: 28, height: 28)
            }.buttonStyle(QuietButtonStyle()).help("Open color library · ⌘1").accessibilityLabel("Expand library")
            Button(action: close) {
                Image(systemName: "xmark").font(.geist(size: 8, weight: .medium))
                    .foregroundStyle(.tertiary).frame(width: 24, height: 28)
            }.buttonStyle(QuietButtonStyle()).help("Hide picker · ⌘W").accessibilityLabel("Hide picker")
        }.padding(.leading, 17).padding(.trailing, 11)
    }

    private var colorWell: some View {
        ZStack {
            Swatch(value: displayedValue ?? value).id((displayedValue ?? value).hex).transition(.opacity)
        }.frame(width: 64, height: 64)
            .modifier(SwatchRim(radius: 11))
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.25 : 0.12), radius: 3, y: 2)
            .overlay {
                ZStack {
                    PipetteIcon().frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
                        .scaleEffect(hoveringWell && !reduceMotion ? 1.04 : 1)
                        .opacity(confirmed && confirmation?.origin == .pick ? 0 : 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(wellInk.opacity(0.9))
                        .opacity(confirmed && confirmation?.origin == .pick ? 1 : 0)
                }.allowsHitTesting(false)
            }
            .overlay(PickSurface(action: pick, enabled: canCollect))
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
            Button { if let current { store.copy(current) } else { pick(false) } } label: {
                Text(current == nil ? "Pick a color" : compactCode)
                    .font(.geist(size: current == nil ? 17 : (isShortCode ? 19 : 12), weight: .regular,
                                  design: current == nil ? .default : .monospaced))
                    .tracking(isShortCode ? -0.55 : -0.25)
                    .lineLimit(2).minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle())
                .accessibilityLabel(current == nil ? "Pick a color" : "Copy \(store.copyFormat.rawValue) color")
                .accessibilityValue(confirmed ? (confirmation?.copied == true ? "Copied" : "Picked") : compactCode)
                .help("Copy \(value.formatted(store.copyFormat))")
            HStack(spacing: 8) {
                formatMenu
                HStack(spacing: 3) {
                    Image(systemName: confirmed ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9, weight: .medium))
                    Text(confirmed ? (confirmation?.copied == true ? "Copied" : "Picked") : "Copy")
                        .font(.geist(size: 10, weight: .medium))
                }
                .foregroundStyle(confirmed ? .primary : .secondary)
                .opacity(confirmed || hoveringValue ? 1 : 0)
                .id(confirmation?.id).transition(.opacity)
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
            Toggle("Remember source websites", isOn: $store.rememberWebsites)
            Toggle("Keep on top", isOn: Binding(get: { isPinned }, set: { _ in togglePin() }))
            Divider()
            Button("Paste color from clipboard", action: store.paste)
            Button("Open color library", action: showLibrary)
            if store.error != nil { Button("View save issue…", action: showLibrary) }
        } label: { Text(store.copyFormat.compactName) }
            .font(.geist(size: 10)).foregroundStyle(.secondary)
            .menuStyle(.borderlessButton).menuIndicator(.visible).controlSize(.mini).fixedSize()
            .help("Copy format & options").accessibilityLabel("Copy format and options")
    }

    private var history: some View {
        HStack(spacing: 0) {
            if store.recent.isEmpty {
                Text("Recent colors")
                    .font(.geist(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(store.recent.prefix(6)) { record in
                    RecentSwatch(store: store, record: record, selected: current?.id == record.id)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            CompactAction(title: "Pick color", symbol: "eyedropper", shortcut: "⌃⌥C") { pick(false) }
            CompactAction(title: "Capture area", symbol: "viewfinder", shortcut: "⌘⇧A", action: capture)
            CompactAction(title: "Open image", symbol: "photo", shortcut: "⌘O", action: openImage)
        }.disabled(!canCollect)
    }
}

private struct CompactAction: View {
    let title: String
    let symbol: String
    let shortcut: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Group {
                    if symbol == "eyedropper" { PipetteIcon().frame(width: 19, height: 19) }
                    else { Image(systemName: symbol).font(.system(size: 15, weight: .regular)) }
                }.frame(height: 19)
                Text(title).font(.geist(size: 10, weight: .medium)).lineLimit(1)
            }
            .frame(maxWidth: .infinity).frame(height: 46)
            .background(Color(nsColor: .controlBackgroundColor).opacity(hovered ? 0.95 : 0.65),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .modifier(ShadowBorder(radius: 8, hovered: hovered))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }.buttonStyle(CompactButtonStyle()).onHover { hovered = $0 }
            .accessibilityLabel(title).help("\(title) · \(shortcut)")
    }
}

private struct RecentSwatch: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor
    let selected: Bool
    @State private var hovered = false
    private var copied: Bool { store.copiedColorID == record.id }

    var body: some View {
        Button {
            store.selectedID = record.id
            store.copy(record)
        } label: {
            Swatch(value: record.value).frame(width: 20, height: 20)
                .modifier(SwatchRim(radius: 5, hovered: hovered))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(.primary.opacity(selected ? 0.30 : 0), lineWidth: 1).padding(-2.5)
                }
                .overlay {
                    if copied {
                        Image(systemName: "checkmark").font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 14, height: 14)
                            .background(.black.opacity(0.68), in: Circle())
                            .id(store.colorFeedback?.id).transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: store.colorFeedback?.id)
                .animation(.easeOut(duration: 0.15), value: copied)
                .frame(width: 24, height: 34)
        }.buttonStyle(CompactButtonStyle())
            .help("\(record.displayName) · \(record.value.hex)\n\(ColorProvenance.summary(record))\nClick to copy \(store.copyFormat.rawValue)")
            .accessibilityLabel("Copy recent color \(record.name)")
            .accessibilityValue(copied ? "Copied" : record.value.hex)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Delete color") { store.delete(record.id) }
            .overlay(alignment: .topTrailing) {
                RemoveButton(label: "Delete recent color \(record.name)", revealed: hovered, compact: true, badge: true) {
                    store.delete(record.id)
                }.disabled(store.readOnly)
            }
            .onHover { hovered = $0 }
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
    var action: (Bool) -> Void
    var enabled: Bool
    func makeNSView(context: Context) -> PickTrackingView { PickTrackingView() }
    func updateNSView(_ view: PickTrackingView, context: Context) {
        view.action = action; view.enabled = enabled
        view.toolTip = "Press, drag, and release to save & copy. Hold Shift to collect more colors."
    }
}

@MainActor
final class PickTrackingView: NSView {
    var action: ((Bool) -> Void)?
    var enabled = true
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if enabled { action?(true) } }
    override func resetCursorRects() { if enabled { addCursorRect(bounds, cursor: .crosshair) } }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { "Pick from screen" }
    override func accessibilityPerformPress() -> Bool {
        guard enabled else { return false }; action?(false); return true
    }
}
