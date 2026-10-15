import AppKit
import Testing
@testable import Couleur

@Test @MainActor func screenSetupDefersPickingUntilDismissalAndRunsItOnce() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "CouleurTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let store = ColorStore(directory: folder)
    let capture = RegionCapture(store: store, preferences: preferences, accessCheck: { true }, accessRequest: { true })
    var picks = 0
    capture.pickAfterSetup = { picks += 1 }
    capture.showAccessSetup()
    #expect(capture.helpPresented)
    capture.continueAfterSetup()
    #expect(!capture.helpPresented)
    #expect(picks == 0)
    capture.helpDidDismiss()
    capture.helpDidDismiss()
    #expect(picks == 1)
    #expect(store.library.colors.isEmpty)
}

@Test @MainActor func deniedAccessCannotStartPickingOrDiscardTheSetup() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "CouleurTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    let capture = RegionCapture(store: ColorStore(directory: folder), preferences: preferences, accessCheck: { false }, accessRequest: { false })
    var picks = 0
    capture.pickAfterSetup = { picks += 1 }
    capture.showAccessSetup()
    capture.continueAfterSetup()
    #expect(capture.helpPresented)
    capture.helpPresented = false
    capture.helpDidDismiss()
    #expect(picks == 0)
}

@Test @MainActor func screenAccessRequestRemembersTheRequestAndRechecksOnReturn() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suite = "CouleurTests.\(UUID().uuidString)"
    let preferences = try #require(UserDefaults(suiteName: suite))
    defer { preferences.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
    var allowed = false
    var requests = 0
    let capture = RegionCapture(store: ColorStore(directory: folder), preferences: preferences,
                                accessCheck: { allowed }, accessRequest: { requests += 1; return false })
    capture.capture()
    #expect(capture.helpPresented && capture.accessPurpose == .capture)
    capture.requestAccess()
    #expect(requests == 1 && capture.requestedAccess && !capture.accessGranted)
    #expect(preferences.bool(forKey: "screenAccessRequested"))
    allowed = true
    capture.checkAccess(explicit: true)
    #expect(capture.accessGranted && capture.checkedAfterSettings)
    #expect(capture.accessPurpose == .capture)
}
