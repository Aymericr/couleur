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
    @Published private(set) var copiedColorID: UUID?
    @Published var error: String?
    @Published private(set) var readOnly = false
    @Published var isSampling = false
    @Published var isExtracting = false
    @Published var screenPalette: ScreenPalette?
    @Published var filter: LibraryFilter = .all
    @Published var search = ""
    @Published var sort: LibrarySort = .newest
    @Published var copyFormat: CopyFormat = CopyFormat(rawValue: UserDefaults.standard.string(forKey: "copyFormat") ?? "") ?? .hex {
        didSet {
            UserDefaults.standard.set(copyFormat.rawValue, forKey: "copyFormat")
            copiedColorID = nil
        }
    }
    @Published var autoCopy: Bool = UserDefaults.standard.object(forKey: "autoCopy") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCopy, forKey: "autoCopy") }
    }
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
            case .capture: matches = false
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
        case .capture: "Screen Palette"
        case .all: "All colors"
        case .favorites: "Favorites"
        case .unfiled: "Unfiled"
        case .collection(let id): collectionName(id)
        }
    }

    func collectionName(_ id: UUID?) -> String { library.collections.first { $0.id == id }?.name ?? "Unfiled" }

    /// Commit only after the disk write succeeds, so the UI never promises a save that failed.
    @discardableResult
    private func commit(_ edit: (inout ColorLibrary) -> Void) -> Bool {
        guard !readOnly else { error = "Your library could not be loaded. Reveal the library folder and recover the file before making changes."; return false }
        var next = library
        edit(&next)
        do { try file.save(next); library = next; return true }
        catch { self.error = "Could not save: \(error.localizedDescription)"; return false }
    }

    func add(_ value: ColorValue, source: ColorSource) {
        let collectionID: UUID? = if case .collection(let id) = filter { id } else { nil }
        let record = SavedColor(name: value.hex, value: value, collectionID: collectionID, source: source)
        commit { $0.colors.insert(record, at: 0) }
        guard library.colors.contains(where: { $0.id == record.id }) else { return }
        search = ""
        if filter == .favorites || filter == .capture { filter = .all }
        selectedID = record.id
        if autoCopy { copy(record) } else { notify("Color saved") }
    }

    /// A capture swatch is saved on first use. Further clicks copy the same record.
    func keepCapturedColor(_ value: ColorValue, proportion: Double? = nil, x: Int? = nil, y: Int? = nil) {
        guard let capture = screenPalette else { return }
        let existing = library.colors.first { $0.source.capture?.id == capture.id && $0.value == value }
        let record = existing ?? SavedColor(name: value.hex, value: value, createdAt: capture.createdAt,
                                            source: capture.source(proportion: proportion, x: x, y: y))
        if existing == nil {
            guard commit({ $0.colors.insert(record, at: 0) }) else { return }
        }
        selectedID = record.id
        copy(record)
    }

    func saveCapturePalette(name: String, dominantOnly: Bool) {
        guard let capture = screenPalette else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var uniqueName = trimmed
        var suffix = 2
        while library.collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame }) {
            uniqueName = "\(trimmed) (\(suffix))"; suffix += 1
        }
        let collection = ColorCollection(name: uniqueName)
        let colors = dominantOnly ? capture.colors.dominant : capture.colors.shades
        guard commit({ library in
            library.collections.append(collection)
            for color in colors {
                if let index = library.colors.firstIndex(where: {
                    $0.source.capture?.id == capture.id && $0.value == color.value && $0.collectionID == nil
                }) {
                    // Keep names and notes on colors already picked from this capture.
                    library.colors[index].collectionID = collection.id
                    library.colors[index].updatedAt = Date()
                } else {
                    library.colors.insert(SavedColor(name: color.value.hex, value: color.value, createdAt: capture.createdAt,
                                                     collectionID: collection.id, source: capture.source(proportion: color.proportion)), at: 0)
                }
            }
        }) else { return }
        notify("Saved \(colors.count) colors to \(uniqueName)")
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
        guard NSPasteboard.general.setString(record.value.formatted(format), forType: .string) else {
            messageTask?.cancel()
            message = nil
            copiedColorID = nil
            error = "Could not copy the color. Please try again."
            return
        }
        notify("Copied \(format.rawValue)", copiedColorID: record.id)
    }

    func paste() {
        guard let text = NSPasteboard.general.string(forType: .string), let value = ColorValue.parse(text) else {
            error = "Paste a HEX, RGB, or HSL color. For example, #E87B65 or rgb(232 123 101)."; return
        }
        add(value, source: ColorSource(method: "Pasted color"))
    }

    private var messageTask: Task<Void, Never>?
    func notify(_ text: String, copiedColorID: UUID? = nil) {
        messageTask?.cancel()
        message = text
        self.copiedColorID = copiedColorID
        messageTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.copiedColorID = nil
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

enum LibraryFilter: Hashable { case all, favorites, unfiled, collection(UUID), capture }
enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest first", name = "Name", hue = "Hue"
    var id: String { rawValue }
}
