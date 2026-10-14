import AppKit
import Combine
import CouleurCore
import SwiftUI
import UniformTypeIdentifiers

extension ColorValue {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
    init?(_ nsColor: NSColor) {
        guard let rgb = nsColor.usingColorSpace(.sRGB) else { return nil }
        self.init(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
    }
}

@MainActor
final class ColorStore: ObservableObject {
    @Published private(set) var library = ColorLibrary()
    @Published var selectedID: UUID?
    @Published var message: String?
    @Published var error: String?
    @Published private(set) var readOnly = false
    @Published var isSampling = false
    @Published var filter: LibraryFilter = .all
    @Published var search = ""
    @Published var sort: LibrarySort = .newest
    @AppStorage("copyFormat") var copyFormat: CopyFormat = .hex
    @AppStorage("autoCopy") var autoCopy = true
    private let file: LibraryFile

    init(directory: URL? = nil) {
        let folder = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Couleur", isDirectory: true)
        file = LibraryFile(url: folder.appendingPathComponent("library.json"))
        do { library = try file.load(); selectedID = library.colors.first?.id }
        catch { readOnly = true; self.error = "Could not open your library: \(error.localizedDescription) Reveal the library folder to recover it, then relaunch." }
    }

    var selected: SavedColor? { library.colors.first { $0.id == selectedID } }
    var recent: [SavedColor] { Array(library.colors.sorted { $0.createdAt > $1.createdAt }.prefix(8)) }
    var visible: [SavedColor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let colors = library.colors.filter { color in
            let matches: Bool
            switch filter {
            case .all: matches = true
            case .favorites: matches = color.favorite
            case .unfiled: matches = color.collectionID == nil
            case .collection(let id): matches = color.collectionID == id
            }
            return matches && (query.isEmpty || [color.name, color.value.hex, color.notes, color.source.appName ?? "", color.source.windowTitle ?? "", color.sourceURL, collectionName(color.collectionID)]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
        return colors.sorted { a, b in
            switch sort {
            case .newest: return a.createdAt > b.createdAt
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .hue: return a.value.hsl.hue < b.value.hsl.hue
            }
        }
    }

    var filterTitle: String {
        switch filter {
        case .all: "All colors"
        case .favorites: "Favorites"
        case .unfiled: "Unfiled"
        case .collection(let id): collectionName(id)
        }
    }

    func collectionName(_ id: UUID?) -> String { library.collections.first { $0.id == id }?.name ?? "Unfiled" }

    /// Commit only after the disk write succeeds, so the UI never promises a save that failed.
    private func commit(_ edit: (inout ColorLibrary) -> Void) {
        guard !readOnly else { error = "Your library could not be loaded. Reveal the library folder and recover the file before making changes."; return }
        var next = library
        edit(&next)
        do { try file.save(next); library = next }
        catch { self.error = "Could not save: \(error.localizedDescription)" }
    }

    func add(_ value: ColorValue, source: ColorSource) {
        let collectionID: UUID? = if case .collection(let id) = filter { id } else { nil }
        let record = SavedColor(name: value.hex, value: value, collectionID: collectionID, source: source)
        commit { $0.colors.insert(record, at: 0) }
        guard library.colors.contains(where: { $0.id == record.id }) else { return }
        search = ""
        if filter == .favorites { filter = .all }
        selectedID = record.id
        if autoCopy { copy(record) } else { notify("Color saved") }
    }

    func update(_ id: UUID, _ edit: (inout SavedColor) -> Void) {
        commit { library in
            guard let index = library.colors.firstIndex(where: { $0.id == id }) else { return }
            edit(&library.colors[index]); library.colors[index].updatedAt = Date()
        }
    }

    func delete(_ id: UUID) {
        guard let record = library.colors.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(record.name.isEmpty ? "this color" : record.name)?"
        alert.informativeText = "This removes the color and its notes from your library. Export your library first if you want a permanent backup."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Delete Color")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        commit { $0.colors.removeAll { $0.id == id } }
        if selectedID == id && !library.colors.contains(where: { $0.id == id }) { selectedID = visible.first?.id }
    }

    func addCollection(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = library.collections.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            filter = .collection(existing.id); return
        }
        let collection = ColorCollection(name: trimmed)
        commit { $0.collections.append(collection) }
        if library.collections.contains(collection) { filter = .collection(collection.id) }
    }

    func renameCollection(_ id: UUID, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        commit { library in
            guard let index = library.collections.firstIndex(where: { $0.id == id }) else { return }
            library.collections[index].name = name
        }
    }

    func removeCollection(_ id: UUID) {
        commit { library in
            library.collections.removeAll { $0.id == id }
            for index in library.colors.indices where library.colors[index].collectionID == id { library.colors[index].collectionID = nil }
        }
        if !library.collections.contains(where: { $0.id == id }) { filter = .all }
    }

    func copy(_ record: SavedColor, as format: CopyFormat? = nil) {
        let format = format ?? copyFormat
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.value.formatted(format), forType: .string)
        notify("Copied \(format.rawValue)")
    }

    func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), let value = ColorValue.parse(text) else {
            error = "Paste a HEX, RGB, or HSL color. For example, #E87B65 or rgb(232 123 101)."; return
        }
        add(value, source: ColorSource(method: "Pasted color"))
    }

    private var messageTask: Task<Void, Never>?
    func notify(_ text: String) {
        messageTask?.cancel(); message = text
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func revealLibrary() {
        try? FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(file.url.deletingLastPathComponent())
    }

    func exportLibrary() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Couleur-library.json"
        panel.message = "Export all colors, collections, and source history."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Never allow an export to overwrite the live library or its recovery copy.
            guard ![file.url.standardizedFileURL, file.backupURL.standardizedFileURL].contains(url.standardizedFileURL) else {
                error = "Choose a location outside the live library files."; return
            }
            try LibraryFile.encode(library).write(to: url, options: .atomic); notify("Library exported")
        } catch { self.error = error.localizedDescription }
    }

    func importLibrary() {
        guard !readOnly else { error = "Recover your existing library before importing."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Merge a Couleur backup. Your existing colors are kept."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let incoming = try LibraryFile.decode(Data(contentsOf: url))
            commit { library in
                let collectionIDs = Set(library.collections.map(\.id))
                library.collections += incoming.collections.filter { !collectionIDs.contains($0.id) }
                let colorIDs = Set(library.colors.map(\.id))
                library.colors += incoming.colors.filter { !colorIDs.contains($0.id) }
            }
        } catch { self.error = "Could not import: \(error.localizedDescription)" }
    }
}

enum LibraryFilter: Hashable { case all, favorites, unfiled, collection(UUID) }
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest first", name = "Name", hue = "Hue"
    var id: String { rawValue }
}
