import AppKit
import CouleurCore
import SwiftUI

/// The everyday picker stays small. Its title bar belongs to AppKit.
struct FloatingView: View {
    static let size = NSSize(width: 272, height: 230)
    @ObservedObject var store: ColorStore
    let pick: () -> Void
    let showLibrary: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hoveringSwatch = false

    private var current: SavedColor? { store.selected ?? store.recent.first }
    private var value: ColorValue { current?.value ?? ColorValue(red: 1, green: 1, blue: 1) }
    private var copied: Bool { store.message?.hasPrefix("Copied") == true }
    private var compactCode: String {
        switch store.copyFormat {
        case .swiftUI, .nsColor, .uiColor: value.hex
        default: value.formatted(store.copyFormat)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            swatch.padding(.horizontal, 10).padding(.top, 8)
            copyRow.padding(.horizontal, 10).frame(height: 47)
            Divider().padding(.horizontal, 12)
            recentColors.frame(height: 48)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .top)
        .background(.regularMaterial)
    }

    private var swatch: some View {
        Swatch(value: value)
            .frame(height: 126)
            .modifier(SwatchRim(radius: 10))
            .overlay {
                if current == nil {
                    VStack(spacing: 7) {
                        Image(systemName: "eyedropper").font(.system(size: 21, weight: .light))
                        Text("Pick a color").font(.system(size: 12, weight: .medium))
                    }.foregroundStyle(.black.opacity(0.45)).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if current != nil && hoveringSwatch {
                    Label("Drag to pick", systemImage: "eyedropper")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.regularMaterial, in: Capsule())
                        .padding(8).transition(.opacity).allowsHitTesting(false)
                }
            }
            .overlay(PickSurface(action: pick, enabled: !store.isSampling && !store.readOnly))
            .onHover { hoveringSwatch = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hoveringSwatch)
            .help("Press, drag to a color, and release. Hold Shift to keep picking.")
    }

    private var copyRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "eyedropper.halffull")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                .overlay(PickSurface(action: pick, enabled: !store.isSampling && !store.readOnly))
                .help("Pick from screen · ⌃⌥C")
            Button { if let current { store.copy(current) } } label: {
                HStack(spacing: 5) {
                    Text(current == nil ? "No color yet" : compactCode)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: copied ? .semibold : .regular))
                        .foregroundStyle(copied ? Color.accentColor : .secondary)
                        .frame(width: 14)
                }.frame(height: 34).contentShape(Rectangle())
            }.buttonStyle(QuietButtonStyle()).disabled(current == nil)
                .accessibilityLabel("Copy \(store.copyFormat.rawValue) color")
                .accessibilityValue(copied ? "Copied" : compactCode)
                .help("Copy \(store.copyFormat.rawValue): \(value.formatted(store.copyFormat))")
            Menu {
                Picker("Copy as", selection: $store.copyFormat) {
                    ForEach(CopyFormat.allCases) { Text($0.rawValue).tag($0) }
                }
                Divider()
                Toggle("Copy automatically", isOn: $store.autoCopy)
                Button("Paste color from clipboard", action: store.paste)
                Divider()
                Button("Open color library", action: showLibrary)
                if store.error != nil { Button("View save issue…", action: showLibrary) }
            } label: {
                Text(store.copyFormat.compactName)
            }.font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .menuStyle(.borderlessButton).menuIndicator(.visible).controlSize(.mini).fixedSize()
                .help("Copy format & options").accessibilityLabel("Copy format and options")
        }
    }

    private var recentColors: some View {
        HStack(spacing: 9) {
            if store.recent.isEmpty {
                Text("Your recent colors, always within reach")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ForEach(store.recent.prefix(6)) { record in
                    Button {
                        store.selectedID = record.id
                        store.copy(record)
                    } label: {
                        Swatch(value: record.value).frame(width: 32, height: 29)
                            .modifier(SwatchRim(radius: 5))
                            .overlay(alignment: .bottom) {
                                Circle().fill(.primary.opacity(0.5))
                                    .frame(width: 3, height: 3).offset(y: 6)
                                    .opacity(current?.id == record.id ? 1 : 0)
                            }
                    }.buttonStyle(QuietButtonStyle())
                        .help("Copy \(record.name) · \(record.value.hex)")
                        .accessibilityLabel("Copy recent color \(record.name)")
                        .accessibilityAddTraits(current?.id == record.id ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }.padding(.horizontal, 17).padding(.bottom, 3)
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
