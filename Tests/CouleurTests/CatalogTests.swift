import AppKit
import CouleurCore
import ImageIO
import Testing
@testable import Couleur

@MainActor
private func withStore(_ body: (ColorStore, LibraryFile, SavedColor) throws -> Void) throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = LibraryFile(url: folder.appendingPathComponent("library.json"))
    var library = ColorLibrary()
    let collection = ColorCollection(name: "Inspiration")
    var record = SavedColor(name: "Rose", value: ColorValue(red: 0.8, green: 0.4, blue: 0.5),
                            createdAt: Date(timeIntervalSince1970: 1_800_000_000), collectionID: collection.id)
    record.favorite = true; record.notes = "A handwritten note"; record.sourceURL = "https://example.com/design"
    library.colors = [record]; library.collections = [collection]
    try file.save(library)
    let store = ColorStore(directory: folder)
    store.undoManager.groupsByEvent = false
    try body(store, file, record)
}

private func sampleImage() throws -> (PaletteImage, Data) {
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
                                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    let pixels = try #require(bitmap.bitmapData)
    for y in 0..<16 {
        for x in 0..<16 {
            let i = y * bitmap.bytesPerRow + x * 4
            pixels[i] = x < 8 ? 255 : 0; pixels[i + 1] = 0
            pixels[i + 2] = x < 8 ? 0 : 255; pixels[i + 3] = 255
        }
    }
    let data = try #require(bitmap.representation(using: .png, properties: [:]))
    return (try PaletteImage(data: data), data)
}

@Test @MainActor func curatedPalettePersistsUndoRedoAndArchiveWithoutChangingImageOrNames() throws {
    try withStore { store, file, record in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        let seed = try image.samples(matching: capture.colors.dominant.map(\.value))
        #expect(seed.count == 2)
        #expect(seed.allSatisfy { image.color(x: $0.x, y: $0.y) == $0.color })
        #expect(store.setCaptureSamples(capture.id, samples: seed, undoable: false))
        var edited = seed
        edited[0].x = 14; edited[0].y = 4
        // Persist resolves the exact pixel instead of trusting a stale drag color.
        store.undoManager.beginUndoGrouping()
        #expect(store.setCaptureSamples(capture.id, samples: edited))
        store.undoManager.endUndoGrouping()
        #expect(store.screenPalette?.record.samples?.first?.color == image.color(x: 14, y: 4))
        #expect(store.library.colors == [record])
        #expect(try Data(contentsOf: file.captureURL(capture.id)) == data)
        store.showCaptures(); store.undoManager.undo()
        #expect(store.screenPalette?.record.samples == seed)
        store.undoManager.redo()
        #expect(store.screenPalette?.record.samples?.first?.x == 14)
        let reloaded = ColorStore(directory: file.url.deletingLastPathComponent())
        reloaded.openCapture(capture.id)
        #expect(reloaded.screenPalette?.record.samples == store.screenPalette?.record.samples)
        let archive = try LibraryArchive.decode(file.archive(reloaded.library).encoded())
        #expect(archive.library.captures == reloaded.library.captures)
    }
}

@Test @MainActor func removedAllPointsStayEmptyAndFailedEditsLeavePaletteIntact() throws {
    try withStore { store, file, _ in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        let seed = try image.samples(matching: capture.colors.dominant.map(\.value))
        #expect(store.setCaptureSamples(capture.id, samples: seed, undoable: false))
        #expect(!store.setCaptureSamples(capture.id, samples: [CaptureSample(x: -1, y: 0, color: seed[0].color)]))
        #expect(store.screenPalette?.record.samples == seed)
        store.undoManager.beginUndoGrouping()
        #expect(store.setCaptureSamples(capture.id, samples: []))
        store.undoManager.endUndoGrouping()
        store.openCapture(capture.id)
        #expect(store.screenPalette?.record.samples == [])
        store.undoManager.removeAllActions()
        try Data("broken library".utf8).write(to: file.url)
        #expect(!store.setCaptureSamples(capture.id, samples: seed))
        #expect(store.screenPalette?.record.samples == [])
        #expect(!store.undoManager.canUndo)
    }
}

@Test @MainActor func familyAndNameSearchDoNotRewriteExistingRecords() throws {
    try withStore { (store, file, record) throws in
        store.search = record.displayName
        #expect(store.visible == [record])
        store.search = record.value.family.rawValue
        #expect(store.visible == [record])
        #expect(try file.load().colors == [record])
    }
}

@Test func importedPhotoOrientationAndPNGArchiveAgreeOnPixels() throws {
    let (original, _) = try sampleImage()
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, "public.jpeg" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, original.cgImage, [kCGImagePropertyOrientation: 6] as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    let oriented = try PaletteImage(data: bytes as Data)
    let top = try #require(oriented.color(x: 8, y: 2)), bottom = try #require(oriented.color(x: 8, y: 13))
    #expect(top.red > 0.8 && top.blue < 0.2)
    #expect(bottom.blue > 0.8 && bottom.red < 0.2)
    let roundTrip = try PaletteImage(data: oriented.pngData())
    #expect(roundTrip.color(x: 8, y: 2) == top)
    #expect(roundTrip.color(x: 8, y: 13) == bottom)
}

@Test @MainActor func versionTwoCapturesMigrateAndInvalidSampleCoordinatesAreRejected() throws {
    try withStore { store, file, record in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        var json = try #require(JSONSerialization.jsonObject(with: LibraryFile.encode(store.library)) as? [String: Any])
        json["version"] = 2
        let migrated = try LibraryFile.decode(JSONSerialization.data(withJSONObject: json))
        #expect(migrated.version == 3)
        #expect(migrated.colors == [record])
        #expect(migrated.captures == [capture.record])
        var invalid = migrated
        invalid.captures[0].samples = [CaptureSample(x: image.width, y: 0, color: record.value)]
        #expect(throws: LibraryError.self) { try invalid.validate() }
        for (width, height) in [(-1, 16), (16, -1), (0, 16), (Int.max, 16)] {
            var malformed = SavedCapture(name: "Invalid dimensions", width: width, height: height, palette: capture.colors)
            malformed.samples = [CaptureSample(x: 0, y: 0, color: record.value)]
            invalid.captures = [malformed]
            #expect(throws: LibraryError.self) { try invalid.validate() }
        }
        #expect(try file.load().captures == [capture.record])
    }
}

@Test @MainActor func colorDeletionUndoPreservesMetadataAndWritesDisk() throws {
    try withStore { (store, file, record) throws in
        store.undoManager.beginUndoGrouping()
        store.delete(record.id)
        store.undoManager.endUndoGrouping()
        #expect(store.library.colors.isEmpty)
        #expect(store.selectedID == nil)
        #expect(try file.load().colors.isEmpty)
        store.undoManager.undo()
        #expect(store.library.colors == [record])
        #expect(store.selectedID == record.id)
        #expect(try file.load().colors == [record])
        store.undoManager.redo()
        #expect(try file.load().colors.isEmpty)
    }
}

@Test @MainActor func undoAfterCollectionRemovalRestoresColorUnfiled() throws {
    try withStore { store, file, record in
        store.undoManager.beginUndoGrouping(); store.delete(record.id); store.undoManager.endUndoGrouping()
        store.removeCollection(try #require(record.collectionID))
        store.undoManager.undo()
        #expect(store.selected?.id == record.id)
        #expect(store.selected?.collectionID == nil)
        #expect(store.selected?.notes == record.notes)
        try file.load().validate()
    }
}

@Test @MainActor func failedDeletionKeepsSelectionAndRegistersNoUndo() throws {
    try withStore { store, file, record in
        try Data("unreadable library".utf8).write(to: file.url)
        store.delete(record.id)
        #expect(store.selected == record)
        #expect(!store.undoManager.canUndo)
        #expect(store.error != nil)
        #expect(try String(contentsOf: file.url, encoding: .utf8) == "unreadable library")
    }
}

@Test @MainActor func captureSurvivesRelaunchWithImagePaletteAndWebsite() throws {
    try withStore { store, file, _ in
        let (image, data) = try sampleImage()
        var source = ColorSource(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Color study", method: "Screen capture")
        source.websiteURL = "https://example.com/study"
        let capture = ScreenPalette(image: image, colors: try image.extract(), source: source)
        #expect(store.saveCapture(capture, imageData: data))
        let reloaded = ColorStore(directory: file.url.deletingLastPathComponent())
        #expect(reloaded.library.captures == [capture.record])
        reloaded.openCapture(capture.id)
        #expect(reloaded.screenPalette?.colors == capture.colors)
        #expect(reloaded.screenPalette?.image.color(x: 3, y: 4) == image.color(x: 3, y: 4))
        #expect(reloaded.screenPalette?.record.websiteName == "example.com")
        let archive = try LibraryArchive.decode(file.archive(reloaded.library).encoded())
        #expect(archive.library == reloaded.library)
        #expect(archive.images[capture.id.uuidString] == data)
        #expect(try Data(contentsOf: file.url).count < data.count + 10_000)
    }
}

@Test @MainActor func captureDeletionUndoRestoresImageAndKeepsSavedColors() throws {
    try withStore { store, file, record in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        store.update(record.id) { $0.source.capture = CaptureSource(id: capture.id, width: image.width, height: image.height) }
        let keptColors = store.library.colors
        store.undoManager.beginUndoGrouping(); store.deleteCapture(capture.id); store.undoManager.endUndoGrouping()
        #expect(store.library.captures.isEmpty)
        #expect(store.library.colors == keptColors)
        #expect(!FileManager.default.fileExists(atPath: file.captureURL(capture.id).path))
        #expect(store.filter == .captures)
        store.undoManager.undo()
        #expect(store.library.captures == [capture.record])
        #expect(store.screenPalette?.id == capture.id)
        #expect(try Data(contentsOf: file.captureURL(capture.id)) == data)
        #expect(try file.load().captures == [capture.record])
    }
}

@Test @MainActor func failedCaptureCommitLeavesNoPhantomEntryOrImage() throws {
    try withStore { store, file, record in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        try Data("broken library".utf8).write(to: file.url)
        #expect(!store.saveCapture(capture, imageData: data))
        #expect(store.library.captures.isEmpty)
        #expect(store.library.colors == [record])
        #expect(!FileManager.default.fileExists(atPath: file.captureURL(capture.id).path))
    }
}

@Test @MainActor func failedCaptureDeletionReturnsImageFromTrash() throws {
    try withStore { store, file, _ in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        try Data("broken library".utf8).write(to: file.url)
        store.deleteCapture(capture.id)
        #expect(store.screenPalette?.id == capture.id)
        #expect(store.library.captures == [capture.record])
        #expect(try Data(contentsOf: file.captureURL(capture.id)) == data)
        #expect(!store.undoManager.canUndo)
        #expect(store.error != nil)
    }
}

@Test @MainActor func repeatedCaptureDeliveryKeepsTheOriginalImage() throws {
    try withStore { store, file, _ in
        let (image, data) = try sampleImage()
        let capture = ScreenPalette(image: image, colors: try image.extract())
        #expect(store.saveCapture(capture, imageData: data))
        #expect(store.saveCapture(capture, imageData: Data("a failed duplicate delivery".utf8)))
        #expect(store.library.captures == [capture.record])
        #expect(try Data(contentsOf: file.captureURL(capture.id)) == data)
    }
}

@Test @MainActor func websiteAttributionRejectsOtherWindowsAndChangedTabs() {
    let browser = SourceWindow(processID: 123, bundleIdentifier: "com.google.Chrome", appName: "Chrome", title: "Design reference",
                               bounds: CGRect(x: -1200, y: 80, width: 1000, height: 700))
    #expect(browser.matches(bounds: [-1200, 80, -200, 780], title: "Design reference"))
    #expect(!browser.matches(bounds: [0, 80, 1000, 780], title: "Design reference"))
    #expect(!browser.matches(bounds: [-1200, 80, -200, 780], title: "A different tab"))
    let overlapping = SourceWindow(processID: 456, bundleIdentifier: "com.apple.finder", appName: "Finder", title: "Documents",
                                   bounds: CGRect(x: -500, y: 100, width: 700, height: 600))
    #expect(ScreenSource.window(for: CGRect(x: -900, y: 120, width: 200, height: 200), in: [overlapping, browser])?.processID == 123)
    #expect(ScreenSource.window(for: CGRect(x: -900, y: 120, width: 600, height: 200), in: [overlapping, browser]) == nil)
}

@Test func sourceLinksUseWebSchemesAndRemoveCredentials() {
    #expect(SavedCapture.webURL("javascript:alert(1)") == nil)
    #expect(SavedCapture.webURL("file:///etc/passwd") == nil)
    #expect(SavedCapture.webURL("https://name:secret@example.com/design?q=colors#palette")?.absoluteString == "https://example.com/design?q=colors#palette")
}

@Test @MainActor func browserScriptsCompileAgainstInstalledDictionaries() throws {
    for identifier in ["com.apple.Safari", "com.google.Chrome"] {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) != nil else { continue }
        let window = SourceWindow(processID: 0, bundleIdentifier: identifier, appName: nil, title: "Example",
                                  bounds: CGRect(x: -1200, y: 80, width: 1000, height: 700))
        let script = try #require(NSAppleScript(source: BrowserSource.script(for: window)))
        var error: NSDictionary?
        let compiled = script.compileAndReturnError(&error)
        #expect(compiled, "\(error?.description ?? "")")
    }
}
