import CouleurCore
import SwiftUI

struct InspectorView: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor

    private func binding<T>(_ keyPath: WritableKeyPath<SavedColor, T>) -> Binding<T> {
        Binding(get: { store.library.colors.first { $0.id == record.id }?[keyPath: keyPath] ?? record[keyPath: keyPath] },
                set: { value in store.update(record.id) { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    Swatch(value: record.value).frame(height: 152).clipShape(RoundedRectangle(cornerRadius: 10))
                    HStack(alignment: .top) {
                        TextField("Color name", text: binding(\.name), axis: .vertical)
                            .font(.system(size: 19, weight: .medium, design: .serif)).textFieldStyle(.plain)
                            .accessibilityLabel("Color name")
                        Button { store.update(record.id) { $0.favorite.toggle() } } label: {
                            Image(systemName: record.favorite ? "star.fill" : "star").foregroundStyle(record.favorite ? .orange : .secondary).padding(4)
                        }.buttonStyle(.plain).help(record.favorite ? "Remove favorite" : "Add favorite").accessibilityLabel("Favorite color")
                    }
                    ColorPicker("Adjust color", selection: Binding(get: { record.value.color }, set: { color in
                        if let value = ColorValue(NSColor(color)) { store.update(record.id) { $0.value = value } }
                    }), supportsOpacity: true).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("COPY COLOR")
                    HStack {
                        Picker("Format", selection: $store.copyFormat) { ForEach(CopyFormat.allCases) { Text($0.rawValue).tag($0) } }
                            .labelsHidden().frame(width: 100)
                        Spacer()
                        Text("sRGB").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    Button { store.copy(record) } label: {
                        HStack(alignment: .top) {
                            Text(record.value.formatted(store.copyFormat)).font(.system(size: 12, design: .monospaced)).multilineTextAlignment(.leading).textSelection(.disabled)
                            Spacer(minLength: 8)
                            Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(.secondary)
                        }.padding(11).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain).help("Copy \(store.copyFormat.rawValue)")
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("COLLECTION")
                    Picker("Collection", selection: binding(\.collectionID)) {
                        Text("Unfiled").tag(nil as UUID?)
                        ForEach(store.library.collections) { Text($0.name).tag(Optional($0.id)) }
                    }.labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 10) {
                    sectionLabel("THE DISCOVERY")
                    sourceRow("calendar", record.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let app = record.source.appName { sourceRow("app", app) }
                    if let title = record.source.windowTitle, !title.isEmpty { sourceRow("macwindow", title) }
                    if let display = record.source.displayName { sourceRow("display", display) }
                    if let x = record.source.x, let y = record.source.y { sourceRow("scope", "\(Int(x)), \(Int(y)) px") }
                    if record.source.appName == nil { sourceRow("eyedropper", record.source.method) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("SOURCE LINK")
                    TextField("Add a URL…", text: binding(\.sourceURL))
                        .textFieldStyle(.roundedBorder).font(.system(size: 11)).accessibilityLabel("Source URL")
                }
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("NOTES")
                    TextField("What caught your eye?", text: binding(\.notes), axis: .vertical)
                        .lineLimit(3...8).textFieldStyle(.plain).font(.system(size: 12)).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7)).accessibilityLabel("Color notes")
                }
                HStack {
                    Image(systemName: "checkmark.circle").font(.system(size: 10))
                    Text("Changes saved automatically").font(.system(size: 10))
                    Spacer()
                    Button { store.delete(record.id) } label: { Image(systemName: "trash").font(.system(size: 11)) }
                        .buttonStyle(.plain).help("Delete color").accessibilityLabel("Delete color")
                }.foregroundStyle(.tertiary)
            }.padding(20)
        }.background(.primary.opacity(0.012))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium)).tracking(1.1).foregroundStyle(.secondary)
    }
    private func sourceRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).frame(width: 13).foregroundStyle(.tertiary)
            Text(text).textSelection(.enabled).lineLimit(3)
        }.font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
