import CouleurCore
import SwiftUI

struct InspectorContainer: View {
    @ObservedObject var store: ColorStore
    var body: some View {
        VStack(spacing: 0) {
            if let record = store.selected {
                InspectorView(store: store, record: record).id(record.id)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 24, weight: .light))
                    Text("Select a color").font(.system(size: 12))
                }.foregroundStyle(.tertiary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct InspectorView: View {
    @ObservedObject var store: ColorStore
    let record: SavedColor

    private func binding<T>(_ keyPath: WritableKeyPath<SavedColor, T>) -> Binding<T> {
        Binding(get: { store.library.colors.first { $0.id == record.id }?[keyPath: keyPath] ?? record[keyPath: keyPath] },
                set: { value in store.update(record.id) { $0[keyPath: keyPath] = value } })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                preview
                copyValue
                Divider()
                organization
                Divider()
                source
                notes
                HStack(spacing: 4) {
                    Image(systemName: store.error == nil ? "checkmark" : "exclamationmark.circle")
                    Text(store.error == nil && !store.readOnly ? "Saved on this Mac" : "Check library status")
                    Spacer()
                    Button { store.delete(record.id) } label: { Image(systemName: "trash").frame(width: 24, height: 24) }
                        .buttonStyle(QuietButtonStyle()).help("Delete color").accessibilityLabel("Delete color")
                        .disabled(store.readOnly)
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(20)
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Color").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                ColorPicker("Adjust color", selection: Binding(get: { record.value.color }, set: { color in
                    if let value = ColorValue(NSColor(color)) { store.update(record.id) { $0.value = value } }
                }), supportsOpacity: true).labelsHidden().controlSize(.mini)
                    .help("Adjust color").disabled(store.readOnly)
                Button { store.update(record.id) { $0.favorite.toggle() } } label: {
                    Image(systemName: record.favorite ? "star.fill" : "star")
                        .font(.system(size: 13)).foregroundStyle(record.favorite ? Color.orange : .secondary)
                        .frame(width: 24, height: 22)
                }.buttonStyle(QuietButtonStyle()).disabled(store.readOnly)
                    .help(record.favorite ? "Remove favorite" : "Add favorite").accessibilityLabel("Favorite color")
                    .accessibilityValue(record.favorite ? "Favorite" : "Not a favorite")
            }
            Swatch(value: record.value).frame(height: 122).modifier(SwatchRim(radius: 8))
            TextField("Name this color", text: binding(\.name), axis: .vertical)
                .font(.system(size: 17, weight: .semibold)).textFieldStyle(.plain).lineLimit(1...3)
                .accessibilityLabel("Color name").disabled(store.readOnly)
        }
    }

    private var copyValue: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Copy format", selection: $store.copyFormat) {
                    ForEach(CopyFormat.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().controlSize(.small).fixedSize()
                Spacer()
                Text("sRGB").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Button { store.copy(record) } label: {
                HStack(alignment: .top, spacing: 10) {
                    Text(record.value.formatted(store.copyFormat))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: store.message?.hasPrefix("Copied") == true ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 14)
                }.padding(11)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
            }.buttonStyle(QuietButtonStyle()).help("Copy \(store.copyFormat.rawValue) · ⌘C")
                .accessibilityLabel("Copy \(store.copyFormat.rawValue) value")
                .accessibilityValue(record.value.formatted(store.copyFormat))
        }
    }

    private var organization: some View {
        HStack {
            Text("Collection").font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Picker("Collection", selection: binding(\.collectionID)) {
                Text("Unfiled").tag(nil as UUID?)
                ForEach(store.library.collections) { Text($0.name).tag(Optional($0.id)) }
            }.labelsHidden().controlSize(.small).frame(maxWidth: 140).disabled(store.readOnly)
        }
    }

    private var source: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("Picked from")
            HStack(spacing: 9) {
                SourceIcon(source: record.source, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.source.appName ?? record.source.method).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(record.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let title = record.source.windowTitle, !title.isEmpty {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(3).textSelection(.enabled)
            }
            if record.source.displayName != nil || record.source.bundleIdentifier != nil || record.source.x != nil {
                DisclosureGroup("Details") {
                    VStack(alignment: .leading, spacing: 7) {
                        if let bundle = record.source.bundleIdentifier { sourceRow("app", bundle) }
                        if let display = record.source.displayName { sourceRow("display", display) }
                        if let x = record.source.x, let y = record.source.y { sourceRow("scope", "\(Int(x)), \(Int(y)) px") }
                    }.padding(.top, 6)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var notes: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Source link")
                TextField("Add a URL…", text: binding(\.sourceURL))
                    .textFieldStyle(.roundedBorder).font(.system(size: 11)).controlSize(.small)
                    .accessibilityLabel("Source URL").disabled(store.readOnly)
            }
            VStack(alignment: .leading, spacing: 7) {
                sectionLabel("Notes")
                TextField("Add a note…", text: binding(\.notes), axis: .vertical)
                    .lineLimit(3...8).textFieldStyle(.plain).font(.system(size: 12)).padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.07), lineWidth: 0.5))
                    .accessibilityLabel("Color notes").disabled(store.readOnly)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
    private func sourceRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: icon).frame(width: 13).foregroundStyle(.tertiary)
            Text(text).textSelection(.enabled).lineLimit(3)
        }.font(.system(size: 10)).foregroundStyle(.secondary)
    }
}
