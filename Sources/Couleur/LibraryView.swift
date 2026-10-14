import AppKit
import CouleurCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var store: ColorStore
    let pick: () -> Void
    let showFloating: () -> Void
    @State private var collectionName = ""
    @State private var addingCollection = false
    @State private var renamingCollection: ColorCollection?
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 174)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                header
                if store.visible.isEmpty { emptyState }
                else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                            ForEach(store.visible) { record in card(record) }
                        }.padding(24)
                    }
                }
                Divider()
                HStack {
                    Text(footerText)
                    Spacer()
                    Text("Stored on this Mac").foregroundStyle(.tertiary)
                    Image(systemName: "internaldrive").foregroundStyle(.tertiary)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.vertical, 12)
            }.frame(minWidth: 340, maxWidth: .infinity)
            Divider()
            if let record = store.selected {
                InspectorView(store: store, record: record).id(record.id).frame(width: 272)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").font(.title2)
                    Text("Select a color").font(.system(size: 13))
                }.foregroundStyle(.tertiary).frame(width: 272).frame(maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("New collection", isPresented: $addingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Create") { store.addCollection(collectionName); collectionName = "" }
            Button("Cancel", role: .cancel) { collectionName = "" }
        } message: { Text("Give a project, mood, or palette a home.") }
        .alert("Rename collection", isPresented: Binding(get: { renamingCollection != nil }, set: { if !$0 { renamingCollection = nil } })) {
            TextField("Collection name", text: $collectionName)
            Button("Rename") {
                if let collection = renamingCollection { store.renameCollection(collection.id, name: collectionName) }
                renamingCollection = nil; collectionName = ""
            }
            Button("Cancel", role: .cancel) { renamingCollection = nil }
        }
        .alert("Couleur", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
            if store.readOnly { Button("Reveal library folder") { store.revealLibrary() } }
        } message: { Text(store.error ?? "") }
        .onChange(of: store.filter) { _, _ in selectFirstVisible() }
        .onChange(of: store.search) { _, _ in selectFirstVisible() }
        .background {
            Button("") { searchFocused = true }.keyboardShortcut("f").hidden()
        }
    }

    private var footerText: String {
        if let message = store.message { return message }
        let count = store.visible.count
        return "\(count) " + (count == 1 ? "color" : "colors")
    }

    private func selectFirstVisible() {
        if !store.visible.contains(where: { $0.id == store.selectedID }) { store.selectedID = store.visible.first?.id }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 18)).rotationEffect(.degrees(-35))
                Text("Couleur").font(.system(size: 17, weight: .semibold, design: .serif))
            }.padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 24)
            navigationRow("All colors", icon: "square.grid.2x2", filter: .all, count: store.library.colors.count)
            navigationRow("Favorites", icon: "star", filter: .favorites, count: store.library.colors.filter(\.favorite).count)
            navigationRow("Unfiled", icon: "tray", filter: .unfiled, count: store.library.colors.filter { $0.collectionID == nil }.count)
            HStack {
                Text("COLLECTIONS").font(.system(size: 10, weight: .medium)).tracking(1)
                Spacer()
                Button { collectionName = ""; addingCollection = true } label: { Image(systemName: "plus") }
                    .buttonStyle(.plain).help("New collection")
                    .accessibilityLabel("New collection")
            }.foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 28).padding(.bottom, 6)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(store.library.collections) { collection in
                        navigationRow(collection.name, icon: "folder", filter: .collection(collection.id), count: store.library.colors.filter { $0.collectionID == collection.id }.count)
                            .contextMenu {
                                Button("Rename…") { collectionName = collection.name; renamingCollection = collection }
                                Button("Remove collection", role: .destructive) { store.removeCollection(collection.id) }
                            }
                    }
                    if store.library.collections.isEmpty {
                        Text("A little order for\nall your discoveries.")
                            .font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(3)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 6)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: showFloating) { Label("Compact picker", systemImage: "arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.plain).font(.system(size: 12)).padding(.horizontal, 16).padding(.bottom, 10)
            Menu {
                Toggle("Copy automatically after picking", isOn: $store.autoCopy)
                Divider()
                Button("Paste color from clipboard", action: store.paste)
                Divider()
                Button("Import library…", action: store.importLibrary)
                Button("Export library…", action: store.exportLibrary)
                Button("Reveal library folder", action: store.revealLibrary)
            } label: { Label("Library options", systemImage: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.bottom, 20)
        }.background(.primary.opacity(0.025))
    }

    private func navigationRow(_ title: String, icon: String, filter: LibraryFilter, count: Int) -> some View {
        Button { store.filter = filter } label: {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 12)).frame(width: 16)
                Text(title).lineLimit(1)
                Spacer(minLength: 2)
                Text("\(count)").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }.font(.system(size: 12, weight: store.filter == filter ? .medium : .regular))
                .padding(.horizontal, 10).padding(.vertical, 9).contentShape(Rectangle())
                .background(store.filter == filter ? Color.primary.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).padding(.horizontal, 8)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.filterTitle).font(.system(size: 26, weight: .medium, design: .serif)).lineLimit(1)
                    Text("Good colors are worth keeping.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Button(action: pick) { Label("Pick color", systemImage: "eyedropper") }
                    .buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut("p", modifiers: [.command, .shift])
                    .disabled(store.isSampling || store.readOnly).help("Pick from screen · ⌃⌥C")
            }
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search name, HEX, source, or notes", text: $store.search)
                        .textFieldStyle(.plain).focused($searchFocused)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }.font(.system(size: 12)).padding(9).background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                Menu {
                    Picker("Sort colors", selection: $store.sort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }
                } label: { Image(systemName: "arrow.up.arrow.down").frame(width: 24, height: 24) }
                    .menuStyle(.borderlessButton).fixedSize().help("Sort colors").accessibilityLabel("Sort colors")
            }
        }.padding(24).padding(.bottom, 2)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: store.search.isEmpty ? "eyedropper.halffull" : "magnifyingglass")
                .font(.system(size: 36, weight: .ultraLight)).foregroundStyle(.secondary).padding(.bottom, 4)
            Text(store.search.isEmpty ? "A home for your colors" : "No colors found")
                .font(.system(size: 23, weight: .medium, design: .serif))
            Text(store.search.isEmpty ? "Pick something that catches your eye.\nWe’ll remember it for you." : "Try a different name, color code, or app.")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(4)
            if store.search.isEmpty {
                Button("Pick your first color", action: pick).buttonStyle(.bordered).padding(.top, 8).disabled(store.readOnly)
                Text("⌃⌥C from any app · Esc to cancel").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 2)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24)
    }

    private func card(_ record: SavedColor) -> some View {
        Button { store.selectedID = record.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                Swatch(value: record.value).frame(height: 112)
                    .overlay(alignment: .topTrailing) {
                        if record.favorite {
                            Image(systemName: "star.fill").font(.system(size: 10)).padding(6)
                                .background(.regularMaterial, in: Circle()).padding(8)
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(record.name.isEmpty ? "Untitled color" : record.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    HStack {
                        Text(record.value.hex).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        if record.source.appName != nil { Image(systemName: "app").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    }
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(store.selectedID == record.id ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: store.selectedID == record.id ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
            .accessibilityLabel("\(record.name), \(record.value.hex)")
            .help(record.source.appName.map { "Picked from \($0)" } ?? record.source.method)
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
                Button("Delete color…", role: .destructive) { store.delete(record.id) }
            }
    }
}

struct Swatch: View {
    let value: ColorValue
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 10
            if value.alpha < 1 {
            for y in stride(from: CGFloat.zero, to: size.height, by: side) {
                for x in stride(from: CGFloat.zero, to: size.width, by: side) {
                    let shade = (Int(x / side) + Int(y / side)).isMultiple(of: 2) ? 0.9 : 0.75
                    context.fill(Path(CGRect(x: x, y: y, width: side, height: side)), with: .color(Color(white: shade)))
                }
            }
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(value.color))
        }.accessibilityLabel(value.hex)
    }
}
