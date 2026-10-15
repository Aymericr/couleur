import AppKit
import CouleurCore
import Testing
@testable import Couleur

@Test @MainActor func repeatCopyConfirmsEachWriteWithoutChangingTheLibrary() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
    let store = ColorStore(directory: folder, pasteboard: board)
    let record = SavedColor(name: "Rose", value: ColorValue(red: 0.8, green: 0.4, blue: 0.5))
    store.copy(record, as: .hex)
    let first = try #require(store.colorFeedback)
    #expect(board.string(forType: .string) == record.value.hex)
    #expect(first.origin == .copy && first.copied && first.colorID == record.id)
    store.copy(record, as: .rgb)
    #expect(board.string(forType: .string) == record.value.formatted(.rgb))
    #expect(store.colorFeedback?.id != first.id)
    #expect(store.library.colors.isEmpty)
}

@Test @MainActor func pickFeedbackReflectsSaveAndCopyResults() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally(); try? FileManager.default.removeItem(at: folder) }
    let store = ColorStore(directory: folder, pasteboard: board)
    let autoCopy = store.autoCopy
    defer { store.autoCopy = autoCopy }
    store.autoCopy = false
    board.setString("Unchanged", forType: .string)
    let value = ColorValue(red: 0.8, green: 0.4, blue: 0.5)
    let saved = try #require(store.add(value, source: ColorSource(method: "Test")))
    #expect(store.colorFeedback?.colorID == saved && store.colorFeedback?.origin == .pick)
    #expect(store.colorFeedback?.copied == false)
    #expect(board.string(forType: .string) == "Unchanged")
    store.autoCopy = true
    #expect(store.add(value, source: ColorSource(method: "Test")) != nil)
    #expect(store.colorFeedback?.copied == true && store.colorFeedback?.origin == .pick)
    let successful = store.colorFeedback
    // A concurrent damaged catalog cannot produce a new successful-pick event.
    try Data("invalid".utf8).write(to: folder.appendingPathComponent("library.json"))
    #expect(store.add(value, source: ColorSource(method: "Test")) == nil)
    #expect(store.colorFeedback == successful)
}
