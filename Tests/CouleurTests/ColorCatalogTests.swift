import CouleurCore
import Foundation
import Testing
@testable import Couleur

private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }
private func record(_ name: String, _ hex: String = "668FD0", at time: String = "2026-10-15T15:00:00Z", source: ColorSource = ColorSource()) -> SavedColor {
    SavedColor(name: name, value: ColorValue.parse(hex)!, createdAt: date(time), source: source)
}

@Test func recentGroupsRespectLocalDaysAcrossTheLongDayAtDSTEnd() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    let now = date("2026-11-02T05:30:00Z")
    let today = record("Today", at: "2026-11-02T05:10:00Z")
    let yesterdayEarly = record("Early yesterday", at: "2026-11-01T04:15:00Z")
    let yesterdayLate = record("Late yesterday", at: "2026-11-02T04:30:00Z")
    let older = record("Older", at: "2026-10-31T12:00:00Z")
    let colors = [older, yesterdayEarly, today, yesterdayLate]
    let catalog = ColorCatalog(colors: colors, sort: .newest, now: now, calendar: calendar)
    #expect(catalog.groups.count == 3)
    #expect(catalog.groups[0].title == "Today")
    #expect(catalog.groups[1].title == "Yesterday")
    #expect(catalog.groups[1].colors == [yesterdayLate, yesterdayEarly])
    #expect(catalog.colors == [today, yesterdayLate, yesterdayEarly, older])
    #expect(ColorCatalog(colors: colors.reversed(), sort: .newest, now: now, calendar: calendar).colors == catalog.colors)
}

@Test func colorFamiliesFollowTheSpectrumAndPerceptualLightness() {
    let red = record("Scarlet", "ED3B35"), gray = record("Silver", "C8CBCF")
    let light = SavedColor(name: "Light blue", value: .perceptual(lightness: 0.85, chroma: 0.10, hue: 260))
    let dark = SavedColor(name: "Dark blue", value: .perceptual(lightness: 0.40, chroma: 0.10, hue: 260))
    let catalog = ColorCatalog(colors: [dark, gray, light, red], sort: .hue)
    #expect(catalog.groups.map(\.id) == [.family(.red), .family(.blue), .family(.neutral)])
    #expect(catalog.groups[1].colors == [light, dark])
    #expect(catalog.colors.count == 4)
}

@Test func appGroupsUseBundleIdentityAndRetainNonAppOrigins() {
    let oldChrome = record("Old", source: ColorSource(appName: "Chrome", bundleIdentifier: "com.google.Chrome"))
    let newChrome = record("New", at: "2026-10-15T16:00:00Z", source: ColorSource(appName: "Google Chrome", bundleIdentifier: "com.google.chrome"))
    let otherBrowser = record("Other", source: ColorSource(appName: "Google Chrome", bundleIdentifier: "org.other.browser"))
    let clipboard = record("Paste", source: ColorSource(method: "Pasted color"))
    let imported = record("Image", source: ColorSource(method: "Imported image"))
    let harmony = record("Harmony", source: ColorSource(method: "Color harmony"))
    let colors = [oldChrome, clipboard, newChrome, otherBrowser, imported, harmony]
    let catalog = ColorCatalog(colors: colors, sort: .app)
    #expect(catalog.groups.count == 5)
    #expect(catalog.groups.first { $0.id == .app("bundle:com.google.chrome") }?.colors == [newChrome, oldChrome])
    #expect(catalog.groups.map(\.title).contains("Clipboard"))
    #expect(catalog.groups.map(\.title).contains("Image"))
    #expect(catalog.groups.map(\.title).contains("Color harmony"))
    #expect(catalog.colors == ColorCatalog(colors: colors.reversed(), sort: .app).colors)
    #expect(Set(catalog.colors.map(\.id)) == Set(colors.map(\.id)))
}

@Test func alphabeticalBrowsingKeepsPersonalNamesAndNaturalNumericOrder() {
    let blue2 = record("Blue 2"), blue10 = record("Blue 10"), amber = record("Amber", "DB7A58")
    let catalog = ColorCatalog(colors: [blue10, blue2, amber], sort: .name)
    #expect(catalog.groups.count == 1)
    #expect(catalog.groups[0].title == nil)
    #expect(catalog.colors == [amber, blue2, blue10])
}

@Test func keyboardNavigationFollowsShortRowsAndGroupBoundaries() {
    let today = (0..<5).map { record("Today \($0)", at: "2026-10-15T15:0\($0):00Z") }.reversed()
    let yesterday = (0..<3).map { record("Yesterday \($0)", at: "2026-10-14T15:0\($0):00Z") }.reversed()
    let colors = Array(today) + Array(yesterday)
    let catalog = ColorCatalog(colors: colors, sort: .newest)
    #expect(catalog.colors == colors)
    #expect(catalog.neighbor(of: colors[2].id, direction: .down, columns: 3) == colors[4].id)
    #expect(catalog.neighbor(of: colors[4].id, direction: .down, columns: 3) == colors[6].id)
    #expect(catalog.neighbor(of: colors[6].id, direction: .up, columns: 3) == colors[4].id)
    #expect(catalog.neighbor(of: colors[5].id, direction: .left, columns: 3) == colors[4].id)
    #expect(catalog.neighbor(of: colors[0].id, direction: .up, columns: 3) == colors[0].id)
    #expect(catalog.neighbor(of: nil, direction: .down, columns: 3) == colors[0].id)
    #expect(ColorCatalog(colors: [], sort: .hue).neighbor(of: nil, direction: .down, columns: 3) == nil)
}

@Test @MainActor func filtersAndSourceSearchApplyBeforeEveryArrangementWithoutWritingTheLibrary() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = LibraryFile(url: folder.appendingPathComponent("library.json"))
    let collection = ColorCollection(name: "Study")
    var first = record("First", "ED3B35", source: ColorSource(appName: "Safari", bundleIdentifier: "com.apple.Safari"))
    first.favorite = true; first.collectionID = collection.id
    first.source.websiteURL = "https://example.com/study"
    var second = record("Second", "668FD0")
    second.collectionID = collection.id
    let third = record("Third", "C8CBCF")
    var library = ColorLibrary(); library.colors = [first, second, third]; library.collections = [collection]
    try file.save(library)
    let original = try Data(contentsOf: file.url)
    let store = ColorStore(directory: folder)
    for sort in LibrarySort.allCases {
        store.sort = sort; store.search = ""; store.filter = .favorites
        #expect(store.visible == [first])
        store.filter = .collection(collection.id)
        #expect(Set(store.visible.map(\.id)) == Set([first.id, second.id]))
        #expect(store.catalog.groups.allSatisfy { !$0.colors.isEmpty })
        store.search = "example.com"
        #expect(store.visible == [first])
        store.filter = .unfiled
        #expect(store.catalog.groups.isEmpty)
        store.search = ""
        #expect(store.visible == [third])
    }
    #expect(store.library == library)
    #expect(try Data(contentsOf: file.url) == original)
}

@Test func hoverProvenanceHasLocalTimeAppWebsiteAndWindowWithoutURLCredentials() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
    var color = record("Coral", source: ColorSource(appName: "Safari", windowTitle: "A color study"))
    color.source.websiteURL = "https://private:secret@example.com/study"
    let summary = ColorProvenance.summary(color, now: date("2026-10-15T20:00:00Z"), calendar: calendar)
    #expect(summary.contains("Safari\nToday at "))
    #expect(summary.contains("11:00"))
    #expect(summary.contains("https://example.com/study"))
    #expect(summary.contains("A color study"))
    #expect(!summary.contains("private") && !summary.contains("secret"))
    color.sourceURL = "https://another.example/page"
    #expect(ColorProvenance.website(color)?.host() == "another.example")
    #expect(ColorProvenance.summary(color, now: date("2026-10-16T20:00:00Z"), calendar: calendar).contains("Yesterday at "))
}
