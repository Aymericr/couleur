import AppKit
import CouleurCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: ColorStore
    @ObservedObject var capture: RegionCapture
    let pick: () -> Void
    @FocusState private var gridFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if store.filter == .capture {
                if store.isExtracting {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("Finding the colors…").font(.geist(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let capture = store.screenPalette {
                    CapturePaletteView(store: store, capture: capture).id(capture.id)
                } else { emptyState }
            } else if store.filter == .captures { CaptureCatalogView(store: store, capture: { capture.capture() }) }
            else {
                ColorLibraryHeader(store: store).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 2)
                if store.visible.isEmpty { emptyState }
                else { colorGrid }
            }
            footer
        }
        .font(.geist(size: 12))
        .background(Color(nsColor: .textBackgroundColor))
        .alert("Couleur", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
            if store.readOnly { Button("Reveal library folder") { store.revealLibrary() } }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.filter) { _, _ in selectFirstVisible() }
        .onChange(of: store.search) { _, _ in selectFirstVisible() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in store.objectWillChange.send() }
    }

    private var isColorLibrary: Bool { store.filter != .capture && store.filter != .captures }

    private var footer: some View {
        HStack(spacing: 10) {
            if isColorLibrary {
                Group {
                    if let message = store.message {
                        Label(message, systemImage: "checkmark")
                    } else {
                        Text("\(store.visible.count.formatted()) \(store.visible.count == 1 ? "color" : "colors")")
                    }
                }.lineLimit(1)
                Spacer(minLength: 8)
                ColorLibraryArrangement(store: store)
            } else {
                if store.filter == .capture { Text("Saved on this Mac") }
                else { Text("\(store.visibleCaptures.count) \(store.visibleCaptures.count == 1 ? "capture" : "captures")") }
                Spacer(minLength: 8)
                if let message = store.message { Label(message, systemImage: "checkmark") }
                else { Text(store.filter == .capture ? "Click a palette color to copy & keep" : "Images and palettes, together") }
            }
        }
        .font(.geist(size: 11)).foregroundStyle(.secondary)
        .padding(.leading, 24).padding(.trailing, isColorLibrary ? 16 : 22)
        .frame(height: isColorLibrary ? 36 : 32)
        .overlay(alignment: .top) {
            if isColorLibrary { Rectangle().fill(.primary.opacity(0.06)).frame(height: 0.5) }
        }
    }

    private var colorGrid: some View {
        GeometryReader { geometry in
            let columns = max(2, Int((geometry.size.width - 32) / 144))
            let catalog = store.catalog
            let compactGroups = store.sort == .hue || store.sort == .app
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: compactGroups ? 14 : 22) {
                        ForEach(catalog.entries) { entry in
                            switch entry {
                            case .color(let record):
                                ColorTile(store: store, record: record, compact: compactGroups) { store.selectedID = record.id; gridFocused = true }
                                    .id(record.id).transition(.opacity)
                            case .heading(let group):
                                Section {} header: {
                                    HStack(spacing: 7) {
                                        if let source = group.source { SourceIcon(source: source, size: 15) }
                                        Text(group.title ?? "").font(.geist(size: 12, weight: .medium))
                                        Text(group.colors.count.formatted()).font(.geist(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                                        Spacer()
                                    }.padding(.horizontal, 4).padding(.top, group.id == catalog.groups.first?.id ? 0 : 10)
                                        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                                        .transition(.opacity)
                                }
                            }
                        }
                    }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
                        .id("catalog-top")
                }
                .focusable().focused($gridFocused).focusEffectDisabled()
                .onMoveCommand { direction in moveSelection(direction, catalog: catalog, columns: columns) }
                .onChange(of: store.selectedID) { _, id in if let id { scroll.scrollTo(id) } }
                .onChange(of: store.sort) { _, _ in withAnimation(nil) { scroll.scrollTo("catalog-top", anchor: .top) } }
                .onChange(of: store.filter) { _, _ in withAnimation(nil) { scroll.scrollTo("catalog-top", anchor: .top) } }
                .onChange(of: store.search) { _, _ in withAnimation(nil) { scroll.scrollTo("catalog-top", anchor: .top) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.search.isEmpty ? "eyedropper.halffull" : "magnifyingglass")
                .font(.geist(size: 30, weight: .light)).foregroundStyle(.tertiary).padding(.bottom, 2)
            Text(emptyTitle).font(.geist(size: 16, weight: .semibold))
            Text(emptyDescription).font(.geist(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
            if store.search.isEmpty && store.filter != .favorites {
                Button("Pick a Color", action: pick).controlSize(.regular).padding(.top, 4)
                    .disabled(store.readOnly || store.isSampling)
                Text("⌃⌥C from any app").font(.geist(size: 11)).foregroundStyle(.tertiary)
            }
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        if !store.search.isEmpty { return "No matching colors" }
        return store.filter == .favorites ? "Your favorites live here" : "A little room for color"
    }
    private var emptyDescription: String {
        if !store.search.isEmpty { return "Search by name, color code, app, or notes." }
        if store.filter == .favorites { return "Star a color to keep it close." }
        return "Pick anywhere on your screen.\nEvery color is remembered."
    }
    private func selectFirstVisible() {
        if store.filter == .captures { store.selectedID = nil; return }
        guard store.filter != .capture else { return }
        if !store.visible.contains(where: { $0.id == store.selectedID }) { store.selectedID = store.visible.first?.id }
    }
    private func moveSelection(_ direction: MoveCommandDirection, catalog: ColorCatalog, columns: Int) {
        let movement: ColorCatalog.Direction
        switch direction {
        case .left: movement = .left
        case .right: movement = .right
        case .up: movement = .up
        case .down: movement = .down
        default: return
        }
        store.selectedID = catalog.neighbor(of: store.selectedID, direction: movement, columns: columns)
    }
}

private struct ColorTile: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor
    let compact: Bool
    let select: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: Bool { store.selectedID == record.id }
    private var copied: Bool { store.copiedColorID == record.id }

    var body: some View {
        let provenance = ColorProvenance.summary(record)
        Button {
            select()
            store.copy(record)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Swatch(value: record.value).aspectRatio(compact ? 2.2 : 1.35, contentMode: .fit)
                    .modifier(SwatchRim(radius: 11, hovered: hovered))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                            .padding(-4)
                    }
                    .overlay(alignment: .topLeading) {
                        if record.favorite {
                            Image(systemName: "star.fill").font(.geist(size: 9, weight: .medium))
                                .frame(width: 22, height: 22).background(.regularMaterial, in: Circle()).padding(7)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Label("Copied", systemImage: "checkmark")
                            .font(.geist(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 0.5))
                            .padding(8)
                            .opacity(copied ? 1 : 0)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: copied)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(record.displayName)
                            .font(.geist(size: 12, weight: .medium))
                            .lineLimit(1).foregroundStyle(selected ? Color.accentColor : .primary)
                        Spacer(minLength: 0)
                    }
                    Text(record.value.hex)
                        .font(.geist(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 4) {
                        SourceIcon(source: record.source, size: 12)
                        Text(ColorProvenance.appName(record.source)).lineLimit(1)
                    }.font(.geist(size: 10)).foregroundStyle(.secondary).padding(.top, 2)
                }.padding(.horizontal, 1)
            }
            .padding(4)
            .background(.primary.opacity(hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle())
            .accessibilityLabel("\(record.displayName), \(record.value.hex)")
            .accessibilityValue(copied ? "Copied" : record.value.formatted(store.copyFormat))
            .accessibilityHint("\(provenance)\nClick to copy \(store.copyFormat.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Copy color") { store.copy(record) }
            .accessibilityAction(named: "Delete color") { store.delete(record.id) }
            .help("\(provenance)\nClick to copy \(store.copyFormat.rawValue)")
            .contextMenu {
                Button("Show details") { store.selectedID = record.id; store.detailsVisible = true }
                Divider()
                Button("Copy \(store.copyFormat.rawValue)") { store.copy(record) }
                Menu("Copy as") { ForEach(CopyFormat.allCases) { format in Button(format.rawValue) { store.copy(record, as: format) } } }
                Divider()
                Button(record.favorite ? "Remove from favorites" : "Add to favorites") { store.update(record.id) { $0.favorite.toggle() } }
                Menu("Move to collection") {
                    Button("Unfiled") { store.update(record.id) { $0.collectionID = nil } }
                    ForEach(store.library.collections) { collection in Button(collection.name) { store.update(record.id) { $0.collectionID = collection.id } } }
                }
                Divider()
                Button("Delete color", role: .destructive) { store.delete(record.id) }
            }
            .overlay(alignment: .topTrailing) {
                RemoveButton(label: "Delete color \(record.name)", revealed: hovered, badge: true) { store.delete(record.id) }
                    .disabled(store.readOnly).padding(10)
            }
            .onHover { hovered = $0 }
    }
}
