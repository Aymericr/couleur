import Foundation

/// Lightweight catalog metadata. Original image bytes live beside the library,
/// so naming a color never rewrites all of the user's screenshots.
public struct SavedCapture: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let createdAt: Date
    public let width: Int
    public let height: Int
    public var source: ColorSource
    public let palette: ExtractedPalette
    public var samples: [CaptureSample]?

    public init(id: UUID = UUID(), name: String, createdAt: Date = Date(), width: Int, height: Int,
                source: ColorSource = ColorSource(method: "Screen capture"), palette: ExtractedPalette) {
        self.id = id; self.name = name
        self.createdAt = Date(timeIntervalSince1970: createdAt.timeIntervalSince1970.rounded(.down))
        self.width = width; self.height = height; self.source = source; self.palette = palette
    }

    public var website: URL? { source.websiteURL.flatMap(Self.webURL) }
    public var websiteName: String? { website?.host()?.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression) }

    /// Source links are web pages, never executable URL schemes or credentials.
    public static func webURL(_ text: String) -> URL? {
        guard var parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty else { return nil }
        parts.user = nil; parts.password = nil
        return parts.url
    }

    var isValid: Bool {
        guard (1...100_000).contains(width), (1...100_000).contains(height), width * height <= 100_000_000 else { return false }
        if let samples {
            guard samples.count <= 12, Set(samples.map(\.id)).count == samples.count,
                  samples.allSatisfy({ (0..<width).contains($0.x) && (0..<height).contains($0.y) && $0.color.isValid }) else { return false }
        }
        guard (1...64).contains(palette.shades.count), (1...5).contains(palette.dominant.count),
              palette.analysis.roles.count <= 64, palette.analysis.gradients.count <= 64,
              [source.x, source.y].compactMap({ $0 }).allSatisfy({ $0.isFinite && abs($0) <= 10_000_000 }) else { return false }
        let colors = palette.shades + palette.dominant + palette.analysis.roles.map(\.color)
        guard colors.allSatisfy({ $0.value.isValid && $0.proportion.isFinite && (0...1).contains($0.proportion) }),
              Set(palette.shades.map(\.id)).count == palette.shades.count,
              Set(palette.dominant.map(\.id)).count == palette.dominant.count,
              Set(palette.analysis.roles.map(\.id)).count == palette.analysis.roles.count,
              Set(palette.analysis.gradients.map(\.id)).count == palette.analysis.gradients.count else { return false }
        return palette.analysis.gradients.allSatisfy { gradient in
            let r = gradient.region
            return gradient.angle.isFinite && (2...64).contains(gradient.stops.count)
                && [r.x, r.y, r.width, r.height].allSatisfy { $0.isFinite && (0...1).contains($0) }
                && r.width > 0 && r.height > 0 && r.x + r.width <= 1.000001 && r.y + r.height <= 1.000001
                && gradient.stops.allSatisfy { $0.color.isValid && $0.location.isFinite && (0...1).contains($0.location) }
                && zip(gradient.stops, gradient.stops.dropFirst()).allSatisfy { $0.location < $1.location }
        }
    }
}

/// Portable JSON exports include original images; normal library writes do not.
public struct LibraryArchive: Codable, Sendable {
    public var library: ColorLibrary
    public var images: [String: Data]

    public init(library: ColorLibrary, images: [String: Data]) { self.library = library; self.images = images }

    public static func decode(_ data: Data) throws -> LibraryArchive {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let archive: LibraryArchive
        if root?["library"] != nil { archive = try decoder.decode(Self.self, from: data) }
        else {
            let library = try LibraryFile.decode(data)
            guard library.captures.isEmpty else { throw CaptureFileError.incompleteArchive }
            archive = Self(library: library, images: [:])
        }
        try archive.validate()
        return archive
    }

    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    private func validate() throws {
        try library.validate()
        guard Set(images.keys) == Set(library.captures.map { $0.id.uuidString }) else { throw CaptureFileError.incompleteArchive }
        for capture in library.captures {
            let image = try PaletteImage(data: images[capture.id.uuidString]!)
            guard image.width == capture.width && image.height == capture.height else { throw CaptureFileError.invalidImage }
        }
    }
}

public enum CaptureFileError: LocalizedError {
    case invalidImage, incompleteArchive
    public var errorDescription: String? {
        switch self {
        case .invalidImage: "A saved capture's image does not match its catalog entry."
        case .incompleteArchive: "This backup is missing capture images. Export the library from Couleur to include them."
        }
    }
}

extension LibraryFile {
    public var captureDirectory: URL { url.deletingLastPathComponent().appendingPathComponent("captures", isDirectory: true) }
    public func captureURL(_ id: UUID) -> URL { captureDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("png") }

    public func saveImage(_ data: Data, for capture: SavedCapture) throws {
        let image = try PaletteImage(data: data)
        guard image.width == capture.width && image.height == capture.height else { throw CaptureFileError.invalidImage }
        try FileManager.default.createDirectory(at: captureDirectory, withIntermediateDirectories: true)
        try data.write(to: captureURL(capture.id), options: .atomic)
    }

    public func archive(_ library: ColorLibrary) throws -> LibraryArchive {
        let images = try Dictionary(uniqueKeysWithValues: library.captures.map {
            ($0.id.uuidString, try Data(contentsOf: captureURL($0.id)))
        })
        return LibraryArchive(library: library, images: images)
    }
}
