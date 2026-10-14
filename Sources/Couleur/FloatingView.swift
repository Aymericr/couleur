import AppKit
import CouleurCore
import SwiftUI

/// The default surface stays small; the library is a separate, expanded workspace.
struct FloatingView: View {
    @ObservedObject var store: ColorStore
    let pick: () -> Void
    let showLibrary: () -> Void
    let togglePin: () -> Void
    let isPinned: Bool

    private var current: SavedColor? { store.selected ?? store.recent.first }
    private var value: ColorValue { current?.value ?? ColorValue(red: 1, green: 1, blue: 1) }
    private var compactCode: String {
        switch store.copyFormat {
        case .swiftUI, .nsColor, .uiColor: return "\(store.copyFormat.rawValue) · \(value.hex)"
        default: return value.formatted(store.copyFormat)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Swatch(value: value)
                .frame(height: 124)
                .overlay(PickSurface(action: pick, enabled: !store.isSampling && !store.readOnly))
                .help("Press, drag to a color, and release to save & copy. Hold Shift for more colors.")
            HStack(spacing: 0) {
                Image(systemName: "eyedropper").font(.system(size: 15))
                    .frame(width: 38, height: 38)
                    .overlay(PickSurface(action: pick, enabled: !store.isSampling && !store.readOnly))
                    .help("Pick a color · ⌃⌥C · Hold Shift to collect more")
                Button {
                    if let current { store.copy(current) }
                } label: {
                    Text(store.message?.hasPrefix("Copied") == true ? "Copied!" : compactCode)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, minHeight: 38).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(current == nil)
                    .help("Copy \(store.copyFormat.rawValue): \(value.formatted(store.copyFormat))")
                    .accessibilityLabel("Copy \(store.copyFormat.rawValue) color")
                Menu {
                    Picker("Copy as", selection: $store.copyFormat) {
                        ForEach(CopyFormat.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Divider()
                    Toggle("Copy automatically", isOn: $store.autoCopy)
                    Button(isPinned ? "✓ Keep on top" : "Keep on top", action: togglePin)
                    Divider()
                    Button("Expand library", action: showLibrary)
                    Button("Paste color from clipboard", action: store.paste)
                    if store.error != nil { Button("View save issue…", action: showLibrary) }
                } label: {
                    Image(systemName: "chevron.down").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 38)
                }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("Copy format & options")
                    .accessibilityLabel("Copy format and options")
            }.background(.primary.opacity(0.05))
            HStack(spacing: 7) {
                ForEach(store.recent.prefix(6)) { record in
                    Button {
                        store.selectedID = record.id
                        store.copy(record)
                    } label: {
                        Swatch(value: record.value).frame(width: 33, height: 33)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(store.selectedID == record.id ? 0.45 : 0.12), lineWidth: store.selectedID == record.id ? 2 : 1))
                    }.buttonStyle(.plain).help("Copy \(record.name) · \(record.value.hex)")
                        .accessibilityLabel("Copy recent color \(record.name)")
                }
                if store.recent.isEmpty {
                    Text("Drag to discover. Click a code to copy.")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(10).frame(height: 53)
        }
        .frame(width: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// Starting the native sampler on mouse-down enables press/drag/release, as well as click-to-pick.
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
