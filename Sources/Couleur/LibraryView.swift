import AppKit
import CouleurCore
import SwiftUI

struct LibrarySidebar: View {
    @ObservedObject var store: ColorStore
    @State private var collectionName = ""
    @State private var addingCollection = false
    @State private var renamingCollection: ColorCollection?

    private var selection: Binding<LibraryFilter?> {
        Binding(get: { store.filter }, set: { if let value = $0 { store.filter = value } })
    }

    var body: some View {
        VStack(spacing: 0) {
            List(selection: selection) {
                if store.screenPalette != nil || store.isExtracting {
                    Section {
                        Label("Screen Palette", systemImage: "viewfinder").font(.system(size: 13))
                            .padding(.vertical, 3).tag(LibraryFilter.capture)
                    }
                }
                Section("Library") {
                    row("All Colors", icon: "square.grid.2x2", filter: .all, count: store.library.colors.count)
                    row("Captures", icon: "rectangle.stack", filter: .captures, count: store.library.captures.count)
                    row("Favorites", icon: "star", filter: .favorites, count: store.library.colors.filter(\.favorite).count)
                    row("Unfiled", icon: "tray", filter: .unfiled, count: store.library.colors.filter { $0.collectionID == nil }.count)
                }
                Section("Collections") {
                    ForEach(store.library.collections) { collection in
                        row(collection.name, icon: "folder", filter: .collection(collection.id), count: store.library.colors.filter { $0.collectionID == collection.id }.count)
                            .contextMenu {
                                Button("Rename…") { collectionName = collection.name; renamingCollection = collection }
                                Button("Remove collection", role: .destructive) { store.removeCollection(collection.id) }
                            }
                    }
                    if store.library.collections.isEmpty {
                        Text("No collections yet").font(.system(size: 12)).foregroundStyle(.tertiary)
                            .selectionDisabled()
                    }
                }
            }.listStyle(.sidebar)
            HStack {
                Button { collectionName = ""; addingCollection = true } label: {
                    Label("New Collection", systemImage: "plus")
                }.buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                Spacer(minLength: 2)
                Menu {
                    Toggle("Copy automatically after picking", isOn: $store.autoCopy)
                    Toggle("Remember source websites", isOn: $store.rememberWebsites)
                    Divider()
                    Button("Paste color from clipboard", action: store.paste)
                    Divider()
                    Button("Import library…", action: store.importLibrary)
                    Button("Export library…", action: store.exportLibrary)
                    Button("Reveal library folder", action: store.revealLibrary)
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .help("Library options").accessibilityLabel("Library options")
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(14)
        }
        .alert("New Collection", isPresented: $addingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Create") { store.addCollection(collectionName); collectionName = "" }
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { collectionName = "" }
        }
        .alert("Rename Collection", isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } })) {
            TextField("Collection name", text: $collectionName)
            Button("Rename") {
                if let collection = renamingCollection { store.renameCollection(collection.id, name: collectionName) }
                renamingCollection = nil; collectionName = ""
            }
            Button("Cancel", role: .cancel) { renamingCollection = nil }
        }
    }

    private func row(_ title: String, icon: String, filter: LibraryFilter, count: Int) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
            Spacer(minLength: 3)
            Text(count.formatted()).font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
        }.font(.system(size: 13)).padding(.vertical, 3).tag(filter)
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
            else if store.visible.isEmpty { emptyState }
            else { colorGrid }
            HStack(spacing: 6) {
                if store.filter == .capture { Text("Saved on this Mac") }
                else if store.filter == .captures { Text("\(store.visibleCaptures.count) \(store.visibleCaptures.count == 1 ? "capture" : "captures")") }
                else { Text("\(store.visible.count.formatted()) \(store.visible.count == 1 ? "color" : "colors")") }
                Spacer()
                if let message = store.message {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .medium))
                    Text(message)
                } else {
                    Text(store.filter == .capture ? "Click a color to copy & keep" : store.filter == .captures ? "Images and palettes, together" : "Click a color to copy")
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
            let columns = max(1, Int((geometry.size.width - 32) / 152))
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: columns), spacing: 22) {
                        ForEach(store.visible) { record in
                            ColorTile(store: store, record: record) { store.selectedID = record.id; gridFocused = true }
                                .id(record.id)
                        }
                    }.padding(22)
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
    private var named: Bool { !record.name.isEmpty && record.name != record.value.hex }

    var body: some View {
        Button {
            select()
            store.copy(record)
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                Swatch(value: record.value).aspectRatio(1.25, contentMode: .fit)
                    .modifier(SwatchRim(radius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
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
                        Text(record.name.isEmpty ? record.value.hex : record.name)
                            .font(.system(size: 12, weight: .medium, design: named ? .default : .monospaced))
                            .lineLimit(1).foregroundStyle(selected ? Color.accentColor : .primary)
                        Spacer(minLength: 0)
                        SourceIcon(source: record.source, size: 13)
                    }
                    Text(named ? record.value.hex : (record.source.appName ?? record.source.method))
                        .font(.system(size: 10, design: named ? .monospaced : .default))
                        .foregroundStyle(.secondary).lineLimit(1)
                }.padding(.horizontal, 1)
            }
            .padding(4)
            .background(.primary.opacity(hovered ? 0.025 : 0), in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle())
            .accessibilityLabel("\(record.name), \(record.value.hex)")
            .accessibilityValue(copied ? "Copied" : record.value.formatted(store.copyFormat))
            .accessibilityHint("Click to copy \(store.copyFormat.rawValue)")
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityAction(named: "Copy color") { store.copy(record) }
            .accessibilityAction(named: "Delete color") { store.delete(record.id) }
            .help("\(record.source.appName.map { "Picked from \($0) · " } ?? "")Click to copy \(store.copyFormat.rawValue)")
            .contextMenu {
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
                RemoveButton(label: "Delete color \(record.name)", revealed: hovered || selected, badge: true) { store.delete(record.id) }
                    .disabled(store.readOnly).padding(10)
            }
            .onHover { hovered = $0 }
    }
}
