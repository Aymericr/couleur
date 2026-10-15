// Compile with the CouleurCore sources; see docs/picker-responsiveness.md.
import Foundation

@main
enum LibraryBenchmark {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Couleur-benchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        print("Atomic library save, including validation and previous-version backup; 30 measured writes per size")
        for count in [100, 1_000, 10_000] {
            let file = LibraryFile(url: folder.appendingPathComponent("\(count)/library.json"))
            var library = ColorLibrary()
            library.colors = (0..<count).map { index in
                var color = SavedColor(name: "Color \(index)", value: ColorValue(red: Double(index % 256) / 255, green: 0.4, blue: 0.8),
                                       source: ColorSource(appName: "Browser", bundleIdentifier: "example.browser", windowTitle: "Design reference", x: 250, y: 300))
                color.sourceURL = "https://example.com/design"
                return color
            }
            try file.save(library)
            var samples: [Double] = []
            for iteration in 0..<35 {
                library.colors[0].name = "Color \(iteration)"
                let start = ContinuousClock.now
                try file.save(library)
                let elapsed = start.duration(to: .now).components
                if iteration >= 5 { samples.append(Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15) }
            }
            samples.sort()
            print(String(format: "%5d colors: p50 %.2f ms; p95 %.2f ms", count, samples[14], samples[28]))
        }
    }
}
