import AppKit
import CouleurCore
import SwiftUI

/// Organization stays local to the color grid; it is not another navigation tree.
private struct ColorLibraryHeader: View {
    @ObservedObject var store: ColorStore
    @State private var collectionName = ""
    @State private var addingCollection = false
    @State private var renamingCollection = false

    private var currentCollection: ColorCollection? {
        guard case .collection(let id) = store.filter else { return nil }
        return store.library.collections.first { $0.id == id }
    }

    var body: some View {
        HStack(spacing: 16) {
            Menu {
                Picker("Show", selection: $store.filter) {
                    Text("All colors").tag(LibraryFilter.all)
                    Text("Favorites").tag(LibraryFilter.favorites)
                    if !store.library.collections.isEmpty {
                        Divider()
                        ForEach(store.library.collections) { collection in
                            Text(collection.name).tag(LibraryFilter.collection(collection.id))
                        }
                    }
                }.pickerStyle(.inline)
                Divider()
                Button("New collection…") { collectionName = ""; addingCollection = true }.disabled(store.readOnly)
                if let collection = currentCollection {
                    Button("Rename collection…") { collectionName = collection.name; renamingCollection = true }.disabled(store.readOnly)
                    Button("Remove collection", role: .destructive) { store.removeCollection(collection.id) }.disabled(store.readOnly)
                }
            } label: {
                HStack(spacing: 7) {
                    Text(store.filterTitle).font(.system(size: 17, weight: .semibold)).tracking(-0.3).foregroundStyle(.primary)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Show colors").help("All colors, favorites, and your collections")
            Spacer(minLength: 8)
            Menu {
                Picker("Sort colors", selection: $store.sort) {
                    ForEach(LibrarySort.allCases) { sort in Text(sort.rawValue).tag(sort) }
                }.pickerStyle(.inline)
            } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 24, height: 24) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Sort colors").help("Sort colors")
            Button { store.detailsVisible.toggle() } label: {
                Image(systemName: store.detailsVisible ? "info.circle.fill" : "info.circle").frame(width: 24, height: 24)
            }.buttonStyle(QuietButtonStyle()).disabled(store.selected == nil)
                .accessibilityLabel(store.detailsVisible ? "Hide color details" : "Show color details")
                .help(store.detailsVisible ? "Hide color details" : "Name, organize, and explore the selected color")
        }.foregroundStyle(.secondary)
            .alert("New Collection", isPresented: $addingCollection) {
                TextField("Collection name", text: $collectionName)
                Button("Create") { store.addCollection(collectionName) }
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
            .alert("Rename Collection", isPresented: $renamingCollection) {
                TextField("Collection name", text: $collectionName)
                Button("Rename") { if let collection = currentCollection { store.renameCollection(collection.id, name: collectionName) } }
                    .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Cancel", role: .cancel) {}
            }
    }
}

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
                        Text("Finding the colors…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let capture = store.screenPalette {
                    CapturePaletteView(store: store, capture: capture).id(capture.id)
                } else { emptyState }
            } else if store.filter == .captures { CaptureCatalogView(store: store, capture: { capture.capture() }) }
            else {
                ColorLibraryHeader(store: store).padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 8)
                if store.visible.isEmpty { emptyState }
                else { colorGrid }
            }
            HStack(spacing: 6) {
                if store.filter == .capture { Text("Saved on this Mac") }
                else if store.filter == .captures { Text("\(store.visibleCaptures.count) \(store.visibleCaptures.count == 1 ? "capture" : "captures")") }
                else { Text("\(store.visible.count.formatted()) \(store.visible.count == 1 ? "color" : "colors")") }
                Spacer()
                if let message = store.message {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
                    Text(message)
                } else {
                    Text(store.filter == .capture ? "Click a palette color to copy & keep" : store.filter == .captures ? "Images and palettes, together" : "Click a color to copy")
                }
            }.font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 22).frame(height: 32)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .sheet(isPresented: $capture.helpPresented, onDismiss: capture.helpDidDismiss) {
            CaptureAccessView(capture: capture)
        }
        .alert("Couleur", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
            if store.readOnly { Button("Reveal library folder") { store.revealLibrary() } }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.filter) { _, _ in selectFirstVisible() }
        .onChange(of: store.search) { _, _ in selectFirstVisible() }
    }

    private var colorGrid: some View {
        GeometryReader { geometry in
            let columns = max(2, Int((geometry.size.width - 32) / 144))
            ScrollViewReader { scroll in
                ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 22) {
                        ForEach(store.visible) { record in
                            ColorTile(store: store, record: record) { store.selectedID = record.id; gridFocused = true }
                                .id(record.id)
                        }
                        }.padding(24)
                }
                .focusable().focused($gridFocused).focusEffectDisabled()
                .onMoveCommand { direction in moveSelection(direction, columns: columns) }
                .onChange(of: store.selectedID) { _, id in if let id { scroll.scrollTo(id) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: store.search.isEmpty ? "eyedropper.halffull" : "magnifyingglass")
                .font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary).padding(.bottom, 2)
            Text(emptyTitle).font(.system(size: 16, weight: .semibold))
            Text(emptyDescription).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(3)
            if store.search.isEmpty && store.filter != .favorites {
                Button("Pick a Color", action: pick).controlSize(.regular).padding(.top, 4)
                    .disabled(store.readOnly || store.isSampling)
                Text("⌃⌥C from any app").font(.system(size: 11)).foregroundStyle(.tertiary)
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
    private func moveSelection(_ direction: MoveCommandDirection, columns: Int) {
        let colors = store.visible
        guard !colors.isEmpty else { return }
        let index = colors.firstIndex { $0.id == store.selectedID } ?? 0
        let offset: Int
        switch direction {
        case .left: offset = -1
        case .right: offset = 1
        case .up: offset = -columns
        case .down: offset = columns
        default: return
        }
        store.selectedID = colors[min(max(0, index + offset), colors.count - 1)].id
    }
}

private struct ColorTile: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor
    let select: () -> Void
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var selected: Bool { store.selectedID == record.id }
    private var copied: Bool { store.copiedColorID == record.id }

    var body: some View {
        Button {
            select()
            store.copy(record)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Swatch(value: record.value).aspectRatio(1.35, contentMode: .fit)
                    .modifier(SwatchRim(radius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
                            .padding(-4)
                    }
                    .overlay(alignment: .topLeading) {
                        if record.favorite {
                            Image(systemName: "star.fill").font(.system(size: 9, weight: .medium))
                                .frame(width: 22, height: 22).background(.regularMaterial, in: Circle()).padding(7)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Label("Copied", systemImage: "checkmark")
                            .font(.system(size: 11, weight: .medium))
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
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1).foregroundStyle(selected ? Color.accentColor : .primary)
                        Spacer(minLength: 0)
                    }
                    Text(record.value.hex)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary).lineLimit(1)
                }.padding(.horizontal, 1)
            }
            .padding(4)
            .background(.primary.opacity(hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle())
            .accessibilityLabel("\(record.displayName), \(record.value.hex)")
            .accessibilityValue(copied ? "Copied" : record.value.formatted(store.copyFormat))
            .accessibilityHint("Click to copy \(store.copyFormat.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Copy color") { store.copy(record) }
            .accessibilityAction(named: "Delete color") { store.delete(record.id) }
            .help("\(record.source.appName.map { "Picked from \($0) · " } ?? "")Click to copy \(store.copyFormat.rawValue)")
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
