import CouleurCore
import Foundation

enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Recent", hue = "Color family", app = "App", name = "Name"
    var id: Self { self }
    var help: String {
        switch self {
        case .newest: "Group by day, newest first"
        case .hue: "Group related colors, from light to dark"
        case .app: "Group by source app, newest first in each app"
        case .name: "Arrange all colors alphabetically"
        }
    }
}

struct ColorCatalog {
    struct Group: Identifiable {
        enum ID: Hashable { case day(Date), family(ColorFamily), app(String), names }
        let id: ID
        let title: String?
        let source: ColorSource?
        let colors: [SavedColor]
    }

    enum Entry: Identifiable {
        enum ID: Hashable { case heading(Group.ID), color(UUID) }
        case heading(Group), color(SavedColor)
        var id: ID {
            switch self {
            case .heading(let group): .heading(group.id)
            case .color(let color): .color(color.id)
            }
        }
    }

    enum Direction { case left, right, up, down }
    let groups: [Group]
    var colors: [SavedColor] { groups.flatMap(\.colors) }
    // Keep tiles in one identity scope across arrangements. Changing the group
    // headings then moves the existing tiles instead of recreating their views.
    var entries: [Entry] {
        groups.flatMap { group in
            (group.title == nil ? [] : [Entry.heading(group)]) + group.colors.map(Entry.color)
        }
    }

    init(colors: [SavedColor], sort: LibrarySort, now: Date = Date(), calendar: Calendar = .current) {
        switch sort {
        case .newest:
            let days = Dictionary(grouping: colors) { calendar.startOfDay(for: $0.createdAt) }
            groups = days.keys.sorted(by: >).map { day in
                Group(id: .day(day), title: ColorProvenance.day(day, relativeTo: now, calendar: calendar),
                      source: nil, colors: days[day]!.sorted(by: Self.newest))
            }
        case .hue:
            let families = Dictionary(grouping: colors) { $0.value.family }
            // Walk the spectrum, then earth tones and neutrals. Within a family,
            // perceptual lightness gives the eye a useful, continuous progression.
            let order: [ColorFamily] = [.red, .orange, .yellow, .green, .teal, .blue, .violet, .pink, .earth, .neutral]
            groups = order.compactMap { family in
                guard let members = families[family] else { return nil }
                return Group(id: .family(family), title: family.rawValue, source: nil, colors: members.sorted {
                    let a = $0.value.oklch, b = $1.value.oklch
                    if a.lightness != b.lightness { return a.lightness > b.lightness }
                    if a.chroma != b.chroma { return a.chroma < b.chroma }
                    return Self.newest($0, $1)
                })
            }
        case .app:
            let apps = Dictionary(grouping: colors) { ColorProvenance.appKey($0.source) }
            groups = apps.map { key, members in
                let sorted = members.sorted(by: Self.newest)
                let source = sorted.first(where: { ColorProvenance.nonempty($0.source.appName) != nil })?.source ?? sorted[0].source
                return Group(id: .app(key), title: ColorProvenance.appName(source), source: source, colors: sorted)
            }.sorted {
                let comparison = ($0.title ?? "").localizedStandardCompare($1.title ?? "")
                if comparison != .orderedSame { return comparison == .orderedAscending }
                return ColorProvenance.appKey($0.source!) < ColorProvenance.appKey($1.source!)
            }
        case .name:
            groups = colors.isEmpty ? [] : [Group(id: .names, title: nil, source: nil, colors: colors.sorted {
                let comparison = $0.displayName.localizedStandardCompare($1.displayName)
                return comparison == .orderedSame ? Self.newest($0, $1) : comparison == .orderedAscending
            })]
        }
    }

    /// Arrow keys follow the rendered rows, including short rows at group ends.
    /// This is navigation only: it neither copies nor animates the selection.
    func neighbor(of selection: UUID?, direction: Direction, columns: Int) -> UUID? {
        let colors = colors
        guard let index = colors.firstIndex(where: { $0.id == selection }) else { return colors.first?.id }
        if direction == .left || direction == .right {
            return colors[min(max(0, index + (direction == .left ? -1 : 1)), colors.count - 1)].id
        }
        let columns = max(1, columns)
        let rows = groups.flatMap { group in
            stride(from: 0, to: group.colors.count, by: columns).map {
                Array(group.colors[$0..<min($0 + columns, group.colors.count)])
            }
        }
        guard let row = rows.firstIndex(where: { $0.contains(where: { $0.id == selection }) }),
              let column = rows[row].firstIndex(where: { $0.id == selection }) else { return selection }
        let next = min(max(0, row + (direction == .up ? -1 : 1)), rows.count - 1)
        return rows[next][min(column, rows[next].count - 1)].id
    }

    private static func newest(_ a: SavedColor, _ b: SavedColor) -> Bool {
        a.createdAt == b.createdAt ? a.id.uuidString < b.id.uuidString : a.createdAt > b.createdAt
    }
}

enum ColorProvenance {
    static func nonempty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    static func appName(_ source: ColorSource) -> String {
        if let name = nonempty(source.appName) { return name }
        if source.method == "Pasted color" { return "Clipboard" }
        if source.method == "Imported image" { return "Image" }
        if source.method == "Color harmony" { return "Color harmony" }
        if source.method == "Design preview" { return "Preview" }
        return source.capture == nil ? "Screen" : "Screen capture"
    }

    static func appKey(_ source: ColorSource) -> String {
        if let bundle = nonempty(source.bundleIdentifier) { return "bundle:\(bundle.lowercased())" }
        if let name = nonempty(source.appName) { return "name:\(name.lowercased())" }
        return "source:\(appName(source))"
    }

    static func website(_ record: SavedColor) -> URL? {
        SavedCapture.webURL(record.sourceURL) ?? record.source.websiteURL.flatMap(SavedCapture.webURL)
    }

    static func day(_ date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    static func timestamp(_ date: Date, relativeTo now: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        return "\(day(date, relativeTo: now, calendar: calendar)) at \(formatter.string(from: date))"
    }

    static func summary(_ record: SavedColor, now: Date = Date(), calendar: Calendar = .current) -> String {
        var lines = [appName(record.source), timestamp(record.createdAt, relativeTo: now, calendar: calendar)]
        if let website = website(record) { lines.append(website.absoluteString) }
        if let title = nonempty(record.source.windowTitle) { lines.append(title) }
        return lines.joined(separator: "\n")
    }
}
