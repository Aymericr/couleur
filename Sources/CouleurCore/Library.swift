import Foundation

public struct ColorSource: Codable, Equatable, Sendable {
    public var appName: String?
    public var bundleIdentifier: String?
    public var windowTitle: String?
    public var displayName: String?
    public var x: Double?
    public var y: Double?
    public var method: String
    public var capture: CaptureSource?

    public init(appName: String? = nil, bundleIdentifier: String? = nil, windowTitle: String? = nil,
                displayName: String? = nil, x: Double? = nil, y: Double? = nil, method: String = "Screen pick") {
        self.appName = appName; self.bundleIdentifier = bundleIdentifier; self.windowTitle = windowTitle
        self.displayName = displayName; self.x = x; self.y = y; self.method = method
    }
}

/// Additional context for a color taken from a captured image. Pixel coordinates
/// are relative to the top-left of the image, never mistaken for screen coordinates.
public struct CaptureSource: Codable, Equatable, Sendable {
    public var id: UUID
    public var width: Int
    public var height: Int
    public var pixelX: Int?
    public var pixelY: Int?
    public var proportion: Double?

    public init(id: UUID = UUID(), width: Int, height: Int, pixelX: Int? = nil, pixelY: Int? = nil, proportion: Double? = nil) {
        self.id = id; self.width = width; self.height = height
        self.pixelX = pixelX; self.pixelY = pixelY; self.proportion = proportion
    }

    var isValid: Bool {
        (1...100_000).contains(width) && (1...100_000).contains(height)
            && (pixelX.map { (0..<width).contains($0) } ?? true)
            && (pixelY.map { (0..<height).contains($0) } ?? true)
            && (proportion.map { $0.isFinite && (0...1).contains($0) } ?? true)
    }
}

public struct SavedColor: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var value: ColorValue
    public let createdAt: Date
    public var updatedAt: Date
    public var collectionID: UUID?
    public var favorite: Bool
    public var notes: String
    public var sourceURL: String
    public var source: ColorSource

    public init(id: UUID = UUID(), name: String, value: ColorValue, createdAt: Date = Date(),
                collectionID: UUID? = nil, source: ColorSource = ColorSource()) {
        self.id = id; self.name = name; self.value = value; self.createdAt = createdAt; self.updatedAt = createdAt
        self.collectionID = collectionID; self.favorite = false; self.notes = ""; self.sourceURL = ""; self.source = source
    }
}

public struct ColorCollection: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct ColorLibrary: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var colors: [SavedColor] = []
    public var collections: [ColorCollection] = []
    public init() {}

    public func validate() throws {
        guard version == 1 else { throw LibraryError.unsupportedVersion(version) }
        guard colors.allSatisfy({ color in
            color.value.isValid && (color.source.capture?.isValid ?? true)
                && [color.source.x, color.source.y].compactMap { $0 }.allSatisfy { $0.isFinite && abs($0) <= 10_000_000 }
        }), Set(colors.map(\.id)).count == colors.count,
              Set(collections.map(\.id)).count == collections.count,
              colors.allSatisfy({ color in color.collectionID == nil || collections.contains(where: { $0.id == color.collectionID }) })
        else { throw LibraryError.invalidData }
    }
}

public enum LibraryError: LocalizedError {
    case unsupportedVersion(Int), invalidData
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "This library uses version \(version), which this app cannot read. Your file has been left untouched."
        case .invalidData: "This library contains invalid colors or duplicate identifiers. Your file has been left untouched."
        }
    }
}

/// Atomic writes and a previous-version backup. Decode failures are never treated as empty libraries.
public struct LibraryFile: Sendable {
    public let url: URL
    public var backupURL: URL { url.deletingPathExtension().appendingPathExtension("backup.json") }
    public init(url: URL) { self.url = url }

    public static func decode(_ data: Data) throws -> ColorLibrary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let library = try decoder.decode(ColorLibrary.self, from: data)
        try library.validate()
        return library
    }

    public static func encode(_ library: ColorLibrary) throws -> Data {
        try library.validate()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(library)
    }

    public func load() throws -> ColorLibrary {
        guard FileManager.default.fileExists(atPath: url.path) else { return ColorLibrary() }
        return try Self.decode(Data(contentsOf: url))
    }

    public func save(_ library: ColorLibrary) throws {
        let data = try Self.encode(library)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            _ = try Self.decode(existing)
            try existing.write(to: backupURL, options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }
}
