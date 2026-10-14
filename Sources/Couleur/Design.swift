import AppKit
import CouleurCore
import SwiftUI

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

/// A thin rim keeps very light and very dark swatches legible in either appearance.
struct SwatchRim: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.12), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
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
                Image(systemName: source.method == "Pasted color" ? "clipboard" : "app.dashed")
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
