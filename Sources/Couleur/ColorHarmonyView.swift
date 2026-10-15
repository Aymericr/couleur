import CouleurCore
import SwiftUI

struct ColorHarmonyView: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor
    @State private var harmony: ColorHarmony = .analogous
    @State private var expanded = false
    @State private var copiedPalette = false
    @State private var feedbackTask: Task<Void, Never>?
    private var colors: [ColorValue] { harmony.colors(for: record.value) }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Color relationship", selection: $harmony) {
                    ForEach(ColorHarmony.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().controlSize(.small).padding(.top, 10)
                HStack(spacing: 5) {
                    ForEach(Array(colors.enumerated()), id: \.offset) { _, color in
                        Button { store.keepSuggestedColor(color, from: record) } label: {
                            Swatch(value: color).frame(height: 42).modifier(SwatchRim(radius: 7))
                                .overlay {
                                    if store.library.colors.first(where: { $0.id == store.copiedColorID })?.value == color {
                                        Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(color.relativeLuminance > 0.4 ? .black : .white)
                                    }
                                }
                        }.buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                            .accessibilityLabel("Keep \(color.suggestedName), \(color.hex)")
                            .help("\(color.suggestedName) · \(color.hex) · Click to copy & keep")
                    }
                }
                Text(harmony.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button {
                    guard store.copyValues(colors) else { return }
                    copiedPalette = true; feedbackTask?.cancel()
                    feedbackTask = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copiedPalette = false } }
                } label: {
                    Label(copiedPalette ? "Copied palette" : "Copy palette", systemImage: copiedPalette ? "checkmark" : "doc.on.doc")
                }.controlSize(.small)
                Text("Text contrast").font(.system(size: 11, weight: .medium)).padding(.top, 3)
                HStack(spacing: 8) {
                    contrastPreview(on: ColorValue(red: 1, green: 1, blue: 1), name: "White")
                    contrastPreview(on: ColorValue(red: 0.08, green: 0.08, blue: 0.08), name: "Ink")
                }
                Text("WCAG AA: 4.5:1 for normal text, 3:1 for large text. Suggested harmonies use OKLCH; chroma is reduced to fit sRGB.")
                    .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.padding(.bottom, 4)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(.secondary)
                Text("Explore harmonies").font(.system(size: 12, weight: .medium))
            }
        }.onDisappear { feedbackTask?.cancel() }
    }

    private func contrastPreview(on background: ColorValue, name: String) -> some View {
        let ratio = record.value.contrast(on: background)
        let result = ratio >= 4.5 ? "AA" : ratio >= 3 ? "Large text" : "Low contrast"
        return VStack(alignment: .leading, spacing: 5) {
            Text("Aa").font(.system(size: 22, weight: .medium)).foregroundStyle(record.value.color)
                .frame(maxWidth: .infinity).frame(height: 44).background(background.color, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
            Text("\(name) · \(ratio.formatted(.number.precision(.fractionLength(2)))):1").monospacedDigit()
            Text(result).fontWeight(.medium)
        }.font(.system(size: 9)).foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
    }
}
