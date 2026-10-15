import CouleurCore
import SwiftUI

struct CapturePaletteEditor: View {
    @ObservedObject var store: ColorStore
    let capture: ScreenPalette
    let save: () -> Void
    @State private var samples: [CaptureSample] = []
    @State private var selectedID: UUID?
    @State private var loading = true
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    @FocusState private var focusedSample: UUID?
    @Environment(\.colorScheme) private var scheme
    private var selected: CaptureSample? { samples.first { $0.id == selectedID } }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 18) {
                canvas.frame(minWidth: 450, maxWidth: .infinity).frame(height: 388)
                palette(compact: false).frame(width: 216)
            }
            VStack(spacing: 16) {
                canvas.frame(height: 285)
                palette(compact: true)
            }
        }
        .task(id: capture.id) {
            if let saved = capture.record.samples {
                samples = saved; selectedID = saved.first?.id; loading = false; return
            }
            do {
                let image = capture.image, colors = capture.colors.dominant.map(\.value)
                let suggested = try await Task.detached(priority: .userInitiated) { try image.samples(matching: colors) }.value
                guard !Task.isCancelled else { return }
                if store.setCaptureSamples(capture.id, samples: suggested, undoable: false) {
                    samples = suggested; selectedID = suggested.first?.id
                }
            } catch { store.error = "Could not place the initial color points: \(error.localizedDescription)" }
            loading = false
        }
        .onChange(of: capture.record.samples) { _, saved in
            samples = saved ?? []
            if !samples.contains(where: { $0.id == selectedID }) { selectedID = samples.first?.id }
        }
        .onChange(of: focusedSample) { _, value in if let value { selectedID = value } }
        .onDisappear { copyTask?.cancel() }
    }

    private var canvas: some View {
        ZStack(alignment: .bottom) {
            PaletteCanvas(image: capture.image, samples: samples, selectedID: selectedID, enabled: !loading && !store.readOnly) { edited, selection, finished in
                samples = edited; selectedID = selection
                if finished { persist() }
            }
            if loading { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
            HStack(spacing: 5) {
                Image(systemName: "cursorarrow.motionlines").font(.system(size: 10))
                Text("Click to add · Drag to refine").font(.system(size: 10, weight: .medium))
            }.padding(.horizontal, 12).padding(.vertical, 8)
                .modifier(ControlGlass(radius: 20)).padding(.bottom, 7).allowsHitTesting(false)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(scheme == .dark ? 0.65 : 0.55))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.06), lineWidth: 0.5).allowsHitTesting(false))
    }

    private func palette(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            HStack(spacing: 7) {
                Text("Your palette").font(.system(size: 13, weight: .semibold))
                Text("\(samples.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(.tertiary)
                Spacer()
                Button(action: addSample) { Image(systemName: "plus").frame(width: 22, height: 22) }
                    .buttonStyle(QuietButtonStyle()).disabled(samples.count >= 12 || loading || store.readOnly)
                    .help("Add a color point · up to 12").accessibilityLabel("Add palette color")
                Button(action: removeSample) { Image(systemName: "minus").frame(width: 22, height: 22) }
                    .buttonStyle(QuietButtonStyle()).disabled(selected == nil || store.readOnly)
                    .help("Remove selected point · ⌘Z to undo").accessibilityLabel("Remove selected palette color")
            }
            if samples.isEmpty {
                Text(loading ? "Placing color points…" : "Click anywhere in the image to begin.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(height: compact ? 42 : 130)
            } else if compact {
                HStack(spacing: 3) { ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in sampleButton(sample, index: index, compact: true) } }
                    .clipShape(RoundedRectangle(cornerRadius: 9))
            } else {
                ScrollView {
                    VStack(spacing: 3) { ForEach(Array(samples.enumerated()), id: \.element.id) { index, sample in sampleButton(sample, index: index, compact: false) } }
                }.frame(maxHeight: 250)
            }
            HStack(spacing: 6) {
                if let selected {
                    if compact { Text(selected.color.suggestedName).fontWeight(.medium).foregroundStyle(.primary) }
                    Text(compact ? selected.color.hex : "\(selected.x), \(selected.y) px").fontDesign(.monospaced)
                    Spacer(minLength: 2)
                } else { Text("Exact colors from this image"); Spacer() }
            }.font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 14)
            HStack(spacing: 8) {
                Button(action: copyPalette) { Label(copied ? "Copied" : "Copy palette", systemImage: copied ? "checkmark" : "doc.on.doc").frame(maxWidth: .infinity) }
                    .controlSize(.small).disabled(samples.isEmpty).help("Copy every color as \(store.copyFormat.rawValue)")
                Button(action: save) { Image(systemName: "folder.badge.plus").frame(width: 20) }
                    .controlSize(.small).disabled(samples.isEmpty || store.readOnly)
                    .help("Save this palette as a collection").accessibilityLabel("Save your palette as a collection")
            }
        }.padding(16).modifier(StudioSurface())
    }

    private func sampleButton(_ sample: CaptureSample, index: Int, compact: Bool) -> some View {
        let active = selectedID == sample.id
        let wasCopied = store.copiedColorID != nil && store.selected?.source.capture?.id == capture.id && store.selected?.value == sample.color
        return Button {
            selectedID = sample.id
            store.keepCapturedColor(sample.color, x: sample.x, y: sample.y)
        } label: {
            HStack(spacing: 10) {
                Swatch(value: sample.color).frame(width: compact ? nil : 32, height: compact ? 42 : 32)
                    .clipShape(RoundedRectangle(cornerRadius: compact ? 0 : 7))
                    .overlay {
                        if compact || active {
                            Text(wasCopied ? "✓" : "\(index + 1)").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(sample.color.relativeLuminance > 0.4 ? .black : .white)
                        }
                    }
                if !compact {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sample.color.suggestedName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(wasCopied ? "Copied" : sample.color.hex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if active { Circle().fill(.primary.opacity(0.4)).frame(width: 4, height: 4) }
                }
            }.padding(compact ? 0 : 6)
                .background(.primary.opacity(active && !compact ? 0.045 : 0), in: RoundedRectangle(cornerRadius: 11))
                .overlay {
                    if active && compact { RoundedRectangle(cornerRadius: 3).strokeBorder(.white.opacity(0.9), lineWidth: 2).padding(3) }
                }
                .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle()).focused($focusedSample, equals: sample.id)
            .accessibilityLabel("Palette color \(index + 1), \(sample.color.suggestedName), \(sample.color.hex)")
            .accessibilityValue(wasCopied ? "Copied" : "Pixel \(sample.x), \(sample.y)")
            .help("Click to copy & keep · Arrow keys refine the point · Shift moves 10 pixels")
            .onMoveCommand { direction in moveSample(sample.id, direction: direction) }
    }

    private func persist() {
        if !store.setCaptureSamples(capture.id, samples: samples) { samples = capture.record.samples ?? [] }
    }
    private func addSample() {
        guard samples.count < 12, let color = capture.image.color(x: capture.image.width / 2, y: capture.image.height / 2) else { return }
        let sample = CaptureSample(x: capture.image.width / 2, y: capture.image.height / 2, color: color)
        samples.append(sample); selectedID = sample.id; persist()
    }
    private func removeSample() {
        samples.removeAll { $0.id == selectedID }; selectedID = samples.last?.id; persist()
    }
    private func moveSample(_ id: UUID, direction: MoveCommandDirection) {
        guard !store.readOnly, let index = samples.firstIndex(where: { $0.id == id }) else { return }
        let step = NSEvent.modifierFlags.contains(.shift) ? 10 : 1
        switch direction {
        case .left: samples[index].x = max(0, samples[index].x - step)
        case .right: samples[index].x = min(capture.image.width - 1, samples[index].x + step)
        case .up: samples[index].y = max(0, samples[index].y - step)
        case .down: samples[index].y = min(capture.image.height - 1, samples[index].y + step)
        default: return
        }
        if let color = capture.image.color(x: samples[index].x, y: samples[index].y) { samples[index].color = color }
        selectedID = id; persist()
    }
    private func copyPalette() {
        guard store.copyValues(samples.map(\.color)) else { return }
        copied = true; copyTask?.cancel()
        copyTask = Task { try? await Task.sleep(for: .seconds(2)); if !Task.isCancelled { copied = false } }
    }
}
