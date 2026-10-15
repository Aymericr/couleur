import CouleurCore
import SwiftUI

/// One quiet row for choosing which colors to see. Arrangement lives in the footer.
struct ColorLibraryHeader: View {
    @ObservedObject var store: ColorStore
    @State private var collectionName = ""
    @State private var addingCollection = false
    @State private var renamingCollection = false
    @State private var editingCollection: ColorCollection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 4) {
            filterButton("All colors", filter: .all)
            filterButton("Favorites", filter: .favorites)
            if !store.library.collections.isEmpty {
                Divider().frame(height: 16).padding(.horizontal, 5)
                GeometryReader { geometry in
                    ScrollViewReader { scroll in
                        ScrollView(.horizontal) {
                            HStack(spacing: 4) {
                                filterButton("Unfiled", filter: .unfiled).id(LibraryFilter.unfiled)
                                ForEach(store.library.collections) { collection in
                                    filterButton(collection.name, filter: .collection(collection.id))
                                        .id(LibraryFilter.collection(collection.id))
                                        .contextMenu {
                                            Button("Rename collection…") {
                                                editingCollection = collection; collectionName = collection.name; renamingCollection = true
                                            }.disabled(store.readOnly)
                                            Button("Remove collection", role: .destructive) { store.removeCollection(collection.id) }
                                                .disabled(store.readOnly)
                                        }
                                }
                            }
                        }.scrollIndicators(.hidden)
                            .mask {
                                HStack(spacing: 0) {
                                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                                    Rectangle().fill(.black)
                                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 8)
                                }
                            }
                            .onChange(of: store.filter) { _, filter in scroll.scrollTo(filter) }
                            .onChange(of: geometry.size.width) { _, _ in scroll.scrollTo(store.filter) }
                            .onAppear { scroll.scrollTo(store.filter) }
                    }
                }.frame(height: 30)
            } else { Spacer(minLength: 0) }
            Button { collectionName = ""; addingCollection = true } label: {
                Image(systemName: "plus").font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
            }.buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary)
                .disabled(store.readOnly).accessibilityLabel("New collection").help("New collection")
            detailsButton
        }
        .alert("New Collection", isPresented: $addingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Create") { store.addCollection(collectionName) }
                .disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Collection", isPresented: $renamingCollection) {
            TextField("Collection name", text: $collectionName)
            Button("Rename") {
                if let collection = editingCollection { store.renameCollection(collection.id, name: collectionName) }
            }.disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) {}
        }
    }

    private func filterButton(_ title: String, filter: LibraryFilter) -> some View {
        CatalogChoice(title: title, selected: store.filter == filter) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { store.filter = filter }
        }.help(title)
    }

    private var detailsButton: some View {
        Button { store.detailsVisible.toggle() } label: {
            Image(systemName: store.detailsVisible ? "info.circle.fill" : "info.circle").frame(width: 30, height: 30)
        }.buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary).disabled(store.selected == nil && !store.detailsVisible)
            .accessibilityLabel(store.detailsVisible ? "Hide color details" : "Show color details")
            .help(store.detailsVisible ? "Hide color details" : "Name, organize, and explore the selected color")
    }
}

/// Direct view options share the existing status bar rather than another menu row.
struct ColorLibraryArrangement: View {
    @ObservedObject var store: ColorStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibrarySort.allCases) { sort in
                CatalogChoice(title: sort.rawValue, selected: store.sort == sort, compact: true) {
                    // Only an explicit arrangement change animates the grid.
                    // Search, copying, and arrow-key navigation remain immediate.
                    withAnimation(reduceMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: 0.24)) { store.sort = sort }
                }.help(sort.help).accessibilityLabel("Arrange by \(sort.rawValue)")
            }
        }
        .fixedSize()
        .accessibilityElement(children: .contain).accessibilityLabel("Arrange colors")
    }
}

private struct CatalogChoice: View {
    let title: String
    let selected: Bool
    var compact = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Text(title).font(.geist(size: compact ? 11 : 12, weight: .medium))
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, compact ? 8 : 10).frame(height: 30)
                .foregroundStyle(selected || hovered ? .primary : .secondary)
                .background(.primary.opacity(hovered ? 0.035 : 0), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .bottom) {
                    Capsule().fill(.primary.opacity(selected ? 0.65 : 0))
                        .frame(width: 12, height: 2).padding(.bottom, 1)
                }
                .contentShape(Rectangle())
        }.buttonStyle(QuietButtonStyle()).onHover { hovered = $0 }
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(selected ? "Selected" : "")
            .transaction { $0.animation = nil }
    }
}
