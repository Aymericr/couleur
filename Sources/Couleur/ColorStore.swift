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
    @Published var detailsVisible = false
    let undoManager = UndoManager()
    @Published var rememberWebsites = UserDefaults.standard.object(forKey: "rememberWebsites") as? Bool ?? true {
        didSet { UserDefaults.standard.set(rememberWebsites, forKey: "rememberWebsites") }
    }
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
        undoManager.levelsOfUndo = 30
        do { library = try file.load(); selectedID = library.colors.first?.id }
        catch { readOnly = true; self.error = "Could not open your library: \(error.localizedDescription) Reveal the library folder to recover it, then relaunch." }
    }

    var selected: SavedColor? { library.colors.first { $0.id == selectedID } }
    var recent: [SavedColor] { Array(library.colors.sorted { $0.createdAt > $1.createdAt }.prefix(8)) }
    var catalog: ColorCatalog { ColorCatalog(colors: filteredColors, sort: sort) }
    var visible: [SavedColor] { catalog.colors }
    private var filteredColors: [SavedColor] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.colors.filter { color in
            let matches: Bool
            switch filter {
            case .capture, .captures: matches = false
            case .all: matches = true
            case .favorites: matches = color.favorite
            case .unfiled: matches = color.collectionID == nil
            case .collection(let id): matches = color.collectionID == id
            }
            return matches && (query.isEmpty || [color.name, color.displayName, color.value.family.rawValue, color.value.hex, color.notes, ColorProvenance.appName(color.source), color.source.windowTitle ?? "", color.sourceURL, color.source.websiteURL ?? "", collectionName(color.collectionID)]
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    var filterTitle: String {
        switch filter {
        case .capture: screenPalette?.record.name ?? "Screen Palette"
        case .captures: "Captures"
        case .all: "All colors"
        case .favorites: "Favorites"
        case .unfiled: "Unfiled"
        case .collection(let id): collectionName(id)
        }
    }

    var visibleCaptures: [SavedCapture] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.captures.filter { capture in
            query.isEmpty || [capture.name, capture.source.appName ?? "", capture.source.windowTitle ?? "",
                             capture.source.websiteURL ?? ""].contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted { sort == .name ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : $0.createdAt > $1.createdAt }
    }

    func captureImageURL(_ id: UUID) -> URL { file.captureURL(id) }

    @discardableResult
    func saveCapture(_ capture: ScreenPalette, imageData: Data) -> Bool {
        guard !readOnly else { return false }
        if library.captures.contains(where: { $0.id == capture.id }) { openCapture(capture.id); return true }
        do { try file.saveImage(imageData, for: capture.record) }
        catch { self.error = "Could not save the capture: \(error.localizedDescription)"; return false }
        guard commit({ $0.captures.insert(capture.record, at: 0) }) else {
            try? FileManager.default.removeItem(at: file.captureURL(capture.id))
            return false
        }
        screenPalette = capture; filter = .capture; selectedID = nil; search = ""
        notify("Capture saved")
        return true
    }

    func openCapture(_ id: UUID) {
        guard let record = library.captures.first(where: { $0.id == id }) else { return }
        do {
            let image = try PaletteImage(data: Data(contentsOf: file.captureURL(id)))
            guard image.width == record.width && image.height == record.height else { throw CaptureFileError.invalidImage }
            screenPalette = ScreenPalette(record: record, image: image)
            filter = .capture; selectedID = nil
        } catch { self.error = "Could not open this capture: \(error.localizedDescription)" }
    }

    func showCaptures() { filter = .captures; selectedID = nil }

    @discardableResult
    func setCaptureSamples(_ id: UUID, samples: [CaptureSample], undoable: Bool = true) -> Bool {
        guard let capture = screenPalette, capture.id == id,
              let previous = library.captures.first(where: { $0.id == id })?.samples else {
            if !undoable, let index = library.captures.firstIndex(where: { $0.id == id }), library.captures[index].samples == nil {
                return writeCaptureSamples(id, samples: samples)
            }
            return false
        }
        guard samples != previous else { return true }
        guard writeCaptureSamples(id, samples: samples) else { return false }
        if undoable {
            undoManager.registerUndo(withTarget: self) { store in
                MainActor.assumeIsolated {
                    // Undo can be invoked after navigating away from the capture.
                    store.openCapture(id)
                    _ = store.setCaptureSamples(id, samples: previous)
                }
            }
            undoManager.setActionName("Edit Palette")
        }
        return true
    }

    private func writeCaptureSamples(_ id: UUID, samples: [CaptureSample]) -> Bool {
        guard let capture = screenPalette, capture.id == id, samples.count <= 12,
              Set(samples.map(\.id)).count == samples.count else { return false }
        var exact: [CaptureSample] = []
        for sample in samples {
            guard let value = capture.image.color(x: sample.x, y: sample.y) else { return false }
            exact.append(CaptureSample(id: sample.id, x: sample.x, y: sample.y, color: value))
        }
        guard commit({ library in
            guard let index = library.captures.firstIndex(where: { $0.id == id }) else { return }
            library.captures[index].samples = exact
        }) else { return false }
        screenPalette?.record.samples = exact
        return true
    }

    func importImage() {
        guard !readOnly, !isExtracting, !isSampling else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = false
        panel.message = "Explore the colors in an image. A copy stays in your capture library."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isExtracting = true; filter = .capture; selectedID = nil
        Task {
            defer { isExtracting = false }
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    let image = try PaletteImage(data: Data(contentsOf: url))
                    return try (image, image.extract(), image.pngData())
                }.value
                let source = ColorSource(windowTitle: url.deletingPathExtension().lastPathComponent, method: "Imported image")
                let capture = ScreenPalette(image: result.0, colors: result.1, source: source)
                _ = saveCapture(capture, imageData: result.2)
            } catch { self.error = "Could not open this image: \(error.localizedDescription)" }
        }
    }

    func updateCapture(_ id: UUID, _ edit: (inout SavedCapture) -> Void) {
        guard library.captures.contains(where: { $0.id == id }) else { return }
        guard commit({ library in
            guard let index = library.captures.firstIndex(where: { $0.id == id }) else { return }
            edit(&library.captures[index])
        }) else { return }
        if screenPalette?.id == id, let record = library.captures.first(where: { $0.id == id }) { screenPalette?.record = record }
    }

    func rememberWebsite(_ website: String, forCapture id: UUID) {
        guard let url = SavedCapture.webURL(website), library.captures.contains(where: { $0.id == id }) else { return }
        guard commit({ library in
            let index = library.captures.firstIndex { $0.id == id }!
            guard library.captures[index].source.websiteURL == nil else { return }
            library.captures[index].source.websiteURL = url.absoluteString
            for i in library.colors.indices where library.colors[i].source.capture?.id == id {
                if library.colors[i].sourceURL.isEmpty { library.colors[i].sourceURL = url.absoluteString }
                library.colors[i].source.websiteURL = url.absoluteString
            }
        }) else { return }
        if screenPalette?.id == id, let record = library.captures.first(where: { $0.id == id }) { screenPalette?.record = record }
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

    @discardableResult
    func add(_ value: ColorValue, source: ColorSource) -> UUID? {
        let collectionID: UUID? = if case .collection(let id) = filter { id } else { nil }
        let record = SavedColor(name: value.suggestedName, value: value, collectionID: collectionID, source: source)
        commit { $0.colors.insert(record, at: 0) }
        guard library.colors.contains(where: { $0.id == record.id }) else { return nil }
        search = ""
        if filter == .favorites || filter == .capture || filter == .captures { filter = .all }
        selectedID = record.id
        if autoCopy { copy(record) } else { notify("Color saved") }
        return record.id
    }

    func rememberWebsite(_ website: String, forColor id: UUID) {
        guard let url = SavedCapture.webURL(website), library.colors.contains(where: { $0.id == id }) else { return }
        update(id) {
            if $0.sourceURL.isEmpty { $0.sourceURL = url.absoluteString }
            if $0.source.websiteURL == nil { $0.source.websiteURL = url.absoluteString }
        }
    }

    /// A capture swatch is saved on first use. Further clicks copy the same record.
    func keepCapturedColor(_ value: ColorValue, proportion: Double? = nil, x: Int? = nil, y: Int? = nil, name: String? = nil) {
        guard let capture = screenPalette else { return }
        let existing = library.colors.first { $0.source.capture?.id == capture.id && $0.value == value }
        let role = capture.role(for: value)
        let record = existing ?? SavedColor(name: name ?? value.suggestedName, value: value, createdAt: capture.createdAt,
                                            source: capture.source(proportion: proportion, x: x, y: y, role: role))
        if existing == nil {
            guard commit({ $0.colors.insert(record, at: 0) }) else { return }
        }
        selectedID = record.id
        copy(record)
    }

    func saveCapturePalette(name: String, selection: CapturePaletteSelection) {
        guard let capture = screenPalette else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var uniqueName = trimmed
        var suffix = 2
        while library.collections.contains(where: { $0.name.localizedCaseInsensitiveCompare(uniqueName) == .orderedSame }) {
            uniqueName = "\(trimmed) (\(suffix))"; suffix += 1
        }
        let collection = ColorCollection(name: uniqueName)
        let colors = selection.colors(in: capture)
        guard !colors.isEmpty else { return }
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
                    let role = capture.role(for: color.value)
                    let sample = selection == .curated ? capture.record.samples?.first(where: { $0.color == color.value }) : nil
                    library.colors.insert(SavedColor(name: color.value.suggestedName, value: color.value, createdAt: capture.createdAt,
                                                     collectionID: collection.id, source: capture.source(proportion: selection == .curated ? nil : color.proportion, x: sample?.x, y: sample?.y, role: role)), at: 0)
                }
            }
        }) else { return }
        notify("Saved \(colors.count) colors to \(uniqueName)")
    }

    @discardableResult
    func copyValues(_ colors: [ColorValue]) -> Bool {
        guard !colors.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(colors.map { $0.formatted(copyFormat) }.joined(separator: "\n"), forType: .string) else {
            error = "Could not copy the palette. Please try again."; return false
        }
        notify("Copied \(colors.count) colors")
        return true
    }

    func keepSuggestedColor(_ value: ColorValue, from base: SavedColor) {
        let record = library.colors.first(where: { $0.value == value && $0.source.method == "Color harmony" })
            ?? SavedColor(name: value.suggestedName, value: value, source: ColorSource(method: "Color harmony"))
        if !library.colors.contains(where: { $0.id == record.id }) {
            var saved = record
            saved.notes = "Harmony based on \(base.displayName) · \(base.value.hex)"
            guard commit({ $0.colors.insert(saved, at: 0) }) else { return }
        }
        copy(record)
    }

    @discardableResult
    func copyGradient(_ gradient: DetectedGradient) -> Bool {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(gradient.css, forType: .string) else {
            error = "Could not copy the gradient. Please try again."
            return false
        }
        notify("Copied gradient CSS")
        return true
    }

    func update(_ id: UUID, _ edit: (inout SavedColor) -> Void) {
        commit { library in
            guard let index = library.colors.firstIndex(where: { $0.id == id }) else { return }
            edit(&library.colors[index]); library.colors[index].updatedAt = Date()
        }
    }

    func delete(_ id: UUID) {
        guard let index = library.colors.firstIndex(where: { $0.id == id }) else { return }
        let record = library.colors[index], wasSelected = selectedID == id
        guard commit({ $0.colors.removeAll { $0.id == id } }) else { return }
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restoreColor(record, at: index, select: wasSelected) }
        }
        undoManager.setActionName("Delete Color")
        if wasSelected { selectedID = visible.first?.id }
        notify("Color removed · ⌘Z to undo")
    }

    private func restoreColor(_ record: SavedColor, at index: Int, select: Bool) {
        guard !library.colors.contains(where: { $0.id == record.id }) else { return }
        var restored = record
        if let collection = restored.collectionID, !library.collections.contains(where: { $0.id == collection }) { restored.collectionID = nil }
        guard commit({ $0.colors.insert(restored, at: min(index, $0.colors.count)) }) else { return }
        undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.delete(record.id) } }
        undoManager.setActionName("Delete Color")
        if select { selectedID = record.id }
        notify("Color restored")
    }

    func deleteCapture(_ id: UUID) {
        guard !readOnly, !isExtracting, let index = library.captures.firstIndex(where: { $0.id == id }) else { return }
        let record = library.captures[index], wasOpen = screenPalette?.id == id && filter == .capture
        let original = file.captureURL(id)
        var trashURL: NSURL?
        do {
            if FileManager.default.fileExists(atPath: original.path) {
                try FileManager.default.trashItem(at: original, resultingItemURL: &trashURL)
            }
        } catch { self.error = "Could not remove this capture: \(error.localizedDescription)"; return }
        guard commit({ $0.captures.removeAll { $0.id == id } }) else {
            if let trashURL { try? FileManager.default.moveItem(at: trashURL as URL, to: original) }
            return
        }
        let trashedImage = trashURL as URL?
        undoManager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.restoreCapture(record, at: index, imageInTrash: trashedImage, reopen: wasOpen) }
        }
        undoManager.setActionName("Delete Capture")
        if screenPalette?.id == id { screenPalette = nil }
        if filter == .capture { showCaptures() }
        notify("Capture removed · ⌘Z to undo")
    }

    private func restoreCapture(_ record: SavedCapture, at index: Int, imageInTrash: URL?, reopen: Bool) {
        guard !library.captures.contains(where: { $0.id == record.id }) else { return }
        let original = file.captureURL(record.id)
        do {
            if let imageInTrash { try FileManager.default.moveItem(at: imageInTrash, to: original) }
        } catch { self.error = "Could not restore the capture image: \(error.localizedDescription)"; return }
        guard commit({ $0.captures.insert(record, at: min(index, $0.captures.count)) }) else {
            if let imageInTrash { try? FileManager.default.moveItem(at: original, to: imageInTrash) }
            return
        }
        undoManager.registerUndo(withTarget: self) { store in MainActor.assumeIsolated { store.deleteCapture(record.id) } }
        undoManager.setActionName("Delete Capture")
        if reopen { openCapture(record.id) }
        notify("Capture restored")
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
        panel.message = "Export all colors, collections, captures, and original images."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Never allow an export to overwrite the live library or its recovery copy.
            guard ![file.url.standardizedFileURL, file.backupURL.standardizedFileURL].contains(url.standardizedFileURL) else {
                error = "Choose a location outside the live library files."; return
            }
            try file.archive(library).encoded().write(to: url, options: .atomic); notify("Library exported")
        } catch { self.error = error.localizedDescription }
    }

    func importLibrary() {
        guard !readOnly else { error = "Recover your existing library before importing."; return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        panel.message = "Merge a Couleur backup. Your existing colors are kept."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let archive = try LibraryArchive.decode(Data(contentsOf: url))
            let incoming = archive.library
            let captures = incoming.captures.filter { candidate in !library.captures.contains { $0.id == candidate.id } }
            var written: [URL] = []
            var imported = false
            defer { if !imported { for url in written { try? FileManager.default.removeItem(at: url) } } }
            for capture in captures {
                try file.saveImage(archive.images[capture.id.uuidString]!, for: capture)
                written.append(file.captureURL(capture.id))
            }
            imported = commit { library in
                let collectionIDs = Set(library.collections.map(\.id))
                library.collections += incoming.collections.filter { !collectionIDs.contains($0.id) }
                let colorIDs = Set(library.colors.map(\.id))
                library.colors += incoming.colors.filter { !colorIDs.contains($0.id) }
                library.captures += captures
            }
        } catch { self.error = "Could not import: \(error.localizedDescription)" }
    }
}

enum LibraryFilter: Hashable { case all, favorites, unfiled, collection(UUID), capture, captures }
