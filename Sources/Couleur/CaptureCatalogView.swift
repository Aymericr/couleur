import AppKit
import CouleurCore
import ImageIO
import SwiftUI

struct CaptureCatalogView: View {
    @ObservedObject var store: ColorStore
    let capture: () -> Void

    var body: some View {
        if store.visibleCaptures.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: store.search.isEmpty ? "rectangle.stack" : "magnifyingglass")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                Text(store.search.isEmpty ? "A place for inspiration" : "No matching captures")
                    .font(.system(size: 16, weight: .semibold))
                Text(store.search.isEmpty ? "Capture a piece of your screen.\nIts image and palette stay together." : "Search by name, app, or website.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
                if store.search.isEmpty {
                    Button("Capture an Area", action: capture).padding(.top, 4).disabled(store.readOnly || store.isSampling)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 350), spacing: 20)], alignment: .leading, spacing: 26) {
                    ForEach(store.visibleCaptures) { record in
                        CaptureTile(store: store, record: record)
                    }
                }.padding(22)
            }
        }
    }
}

private struct CaptureTile: View {
    @ObservedObject var store: ColorStore
    let record: SavedCapture
    @State private var hovered = false

    var body: some View {
        Button { store.openCapture(record.id) } label: {
            VStack(alignment: .leading, spacing: 9) {
                CaptureThumbnail(url: store.captureImageURL(record.id))
                    .aspectRatio(1.5, contentMode: .fit)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                HStack(spacing: 0) {
                    ForEach(record.palette.dominant) { color in Swatch(value: color.value) }
                }.frame(height: 9).clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name).font(.system(size: 12, weight: .medium)).lineLimit(1).foregroundStyle(.primary)
                    HStack(spacing: 5) {
                        SourceIcon(source: record.source, size: 12)
                        Text(record.websiteName ?? record.source.appName ?? record.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        Text("\(record.palette.shades.count) shades").monospacedDigit()
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(.horizontal, 1)
            }.contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Open capture \(record.name)")
            .accessibilityHint("Explore the saved image and its palette")
            .accessibilityAction(named: "Delete capture") { store.deleteCapture(record.id) }
            .overlay(alignment: .topTrailing) {
                RemoveButton(label: "Delete capture \(record.name)", revealed: hovered, badge: true) { store.deleteCapture(record.id) }
                    .disabled(store.readOnly || store.isExtracting).padding(8)
            }
            .onHover { hovered = $0 }
            .contextMenu {
                Button("Open capture") { store.openCapture(record.id) }
                if let website = record.website { Link("Open source website", destination: website) }
                Divider()
                Button("Delete capture", role: .destructive) { store.deleteCapture(record.id) }.disabled(store.readOnly)
            }
    }
}

private struct CaptureThumbnail: View {
    let url: URL
    @State private var thumbnail: NSImage?
    var body: some View {
        GeometryReader { geometry in
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().scaledToFit()
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Image(systemName: "photo").font(.system(size: 20, weight: .light)).foregroundStyle(.tertiary)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .task(id: url) {
            let image = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 700
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = image.map { NSImage(cgImage: $0, size: .zero) }
        }
        .accessibilityHidden(true)
    }
}
