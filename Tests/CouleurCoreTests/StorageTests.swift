import Foundation
import Testing
@testable import CouleurCore

private func withFile(_ body: (LibraryFile) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(LibraryFile(url: directory.appendingPathComponent("library.json")))
}

private func exampleLibrary() -> ColorLibrary {
    var library = ColorLibrary()
    let collection = ColorCollection(name: "Project")
    library.collections = [collection]
    var color = SavedColor(name: "Terracotta", value: ColorValue(red: 0.8, green: 0.4, blue: 0.3, alpha: 0.9),
                           createdAt: Date(timeIntervalSince1970: 1_800_000_000), collectionID: collection.id,
                           source: ColorSource(appName: "Safari", bundleIdentifier: "com.apple.Safari", windowTitle: "Inspiration", displayName: "Built-in", x: 42, y: 90))
    color.updatedAt = color.createdAt; color.favorite = true; color.notes = "Earthy & warm"; color.sourceURL = "https://example.com"
    library.colors = [color]
    return library
}

@Test func persistsAllMetadataAcrossReload() throws {
    try withFile { file in
        #expect(try file.load().colors.isEmpty)
        let library = exampleLibrary()
        try file.save(library)
        #expect(try file.load() == library)
        #expect(try LibraryFile.decode(LibraryFile.encode(library)) == library)
    }
}

@Test func keepsPreviousVersionBackup() throws {
    try withFile { file in
        let first = exampleLibrary()
        try file.save(first)
        var second = first; second.colors[0].name = "Renamed"
        try file.save(second)
        #expect(try LibraryFile.decode(Data(contentsOf: file.backupURL)) == first)
        #expect(try file.load() == second)
    }
}

@Test func refusesToOverwriteCorruptData() throws {
    try withFile { file in
        try FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let corrupt = Data("not a library".utf8)
        try corrupt.write(to: file.url)
        #expect(throws: (any Error).self) { try file.load() }
        #expect(throws: (any Error).self) { try file.save(ColorLibrary()) }
        #expect(try Data(contentsOf: file.url) == corrupt)
    }
}

@Test func rejectsFutureVersionAndInvalidRecords() throws {
    var future = ColorLibrary(); future.version = 999
    #expect(throws: LibraryError.self) { try future.validate() }
    var library = exampleLibrary(); library.colors.append(library.colors[0])
    #expect(throws: LibraryError.self) { try library.validate() }
    library = exampleLibrary(); library.colors[0].value.red = 5
    #expect(throws: LibraryError.self) { try library.validate() }
    library = exampleLibrary(); library.collections = []
    #expect(throws: LibraryError.self) { try library.validate() }
    library = exampleLibrary(); library.colors[0].source.x = 1e300
    #expect(throws: LibraryError.self) { try library.validate() }
}

@Test func olderLibrariesMigrateWithoutLosingColorsOrMetadata() throws {
    let original = exampleLibrary()
    var json = try #require(JSONSerialization.jsonObject(with: LibraryFile.encode(original)) as? [String: Any])
    json["version"] = 1
    json.removeValue(forKey: "captures")
    let data = try JSONSerialization.data(withJSONObject: json)
    let migrated = try LibraryFile.decode(data)
    #expect(migrated.version == 3)
    #expect(migrated.colors == original.colors)
    #expect(migrated.collections == original.collections)
    #expect(migrated.captures.isEmpty)
    #expect(try LibraryArchive.decode(data).library == migrated)
}
