import AppKit
import CouleurCore
import SwiftUI

/// Glass belongs to the control layer. Colors and images remain unfiltered.
struct ControlGlass: ViewModifier {
    var radius: CGFloat = 16
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content.background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(.primary.opacity(0.3), lineWidth: 1))
        } else {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            } else { fallback(content) }
            #else
            fallback(content)
            #endif
        }
    }
    private func fallback(_ content: Content) -> some View {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(ShadowBorder(radius: radius))
    }
}

struct StudioSurface: ViewModifier {
    var radius: CGFloat = 28
    func body(content: Content) -> some View {
        content.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(ShadowBorder(radius: radius))
    }
}

/// Native-point version of the craft skill's shadow-border recipe: edge, contact,
/// and ambient light. Dark surfaces need a white edge rather than heavier shadows.
struct ShadowBorder: ViewModifier {
    let radius: CGFloat
    var hovered = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.compositingGroup()
            .shadow(color: .black.opacity(scheme == .light ? (hovered ? 0.08 : 0.06) : 0), radius: 1, y: 0.5)
            .shadow(color: .black.opacity(scheme == .light ? (hovered ? 0.06 : 0.04) : 0), radius: 2, y: 1)
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder((scheme == .dark ? Color.white : .black)
                        .opacity(contrast == .increased ? 0.45 : scheme == .dark ? (hovered ? 0.13 : 0.08) : (hovered ? 0.08 : 0.06)),
                                  lineWidth: contrast == .increased ? 1 : 0.5)
                    .allowsHitTesting(false)
            }
    }
}

/// Swatches show the stored sRGB color without a tint, gradient, or material over it.
struct Swatch: View {
    let value: ColorValue
    var body: some View {
        Canvas { context, size in
            if value.alpha < 1 {
                let side: CGFloat = 8
                for y in stride(from: CGFloat.zero, to: size.height, by: side) {
                    for x in stride(from: CGFloat.zero, to: size.width, by: side) {
                        let shade = (Int(x / side) + Int(y / side)).isMultiple(of: 2) ? 0.94 : 0.80
                        context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(Color(white: shade)))
                    }
                }
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(value.color))
        }.accessibilityLabel(value.hex)
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.55 : 1)
            .contentShape(Rectangle())
    }
}

/// A stationary, neutral close affordance; the swatch keeps its own copy target.
struct RemoveButton: View {
    let label: String
    var revealed = true
    var compact = false
    var badge = false
    let action: () -> Void
    @FocusState private var focused: Bool
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(role: .destructive, action: action) {
            Image(systemName: "xmark")
                .font(.geist(size: compact ? 7 : 9, weight: .medium))
                .foregroundStyle(hovered ? .primary : .secondary)
                .frame(width: compact ? 16 : 24, height: compact ? 16 : 24)
                .background {
                    if badge {
                        Circle().fill(Color(nsColor: .windowBackgroundColor))
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5))
                    } else {
                        Circle().fill(.primary.opacity(hovered ? 0.06 : 0))
                    }
                }
        }.buttonStyle(QuietButtonStyle()).focused($focused)
            .opacity(revealed || focused ? 1 : 0)
            .allowsHitTesting(revealed || focused)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: revealed || focused)
            .accessibilityLabel(label).help("\(label) · ⌘Z to undo")
    }
}

/// A thin rim keeps very light and very dark swatches legible in either appearance.
struct SwatchRim: ViewModifier {
    let radius: CGFloat
    var hovered = false
    func body(content: Content) -> some View {
        content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .modifier(ShadowBorder(radius: radius, hovered: hovered))
    }
}

extension CopyFormat {
    var compactName: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .oklch: "LCH"
        case .swiftUI: "Swift"
        case .nsColor: "AppKit"
        case .uiColor: "UIKit"
        }
    }
}

struct SourceIcon: View {
    let source: ColorSource
    var size: CGFloat = 16
    var body: some View {
        Group {
            if let icon = SourceIcons.shared.icon(for: source.bundleIdentifier) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: source.capture != nil ? "viewfinder" : (source.method == "Pasted color" ? "clipboard" : "app.dashed"))
                    .resizable().scaledToFit().foregroundStyle(.secondary).padding(1)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

@MainActor
private final class SourceIcons {
    static let shared = SourceIcons()
    private var icons: [String: NSImage] = [:]
    private var missing: Set<String> = []
    func icon(for identifier: String?) -> NSImage? {
        guard let identifier, !missing.contains(identifier) else { return nil }
        if let icon = icons[identifier] { return icon }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else {
            missing.insert(identifier); return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[identifier] = icon
        return icon
    }
}
