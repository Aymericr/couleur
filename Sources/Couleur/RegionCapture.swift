import AppKit
import Combine
import CouleurCore

struct ScreenPalette {
    var record: SavedCapture
    let image: PaletteImage
    var id: UUID { record.id }
    var createdAt: Date { record.createdAt }
    var colors: ExtractedPalette { record.palette }

    init(image: PaletteImage, colors: ExtractedPalette, source: ColorSource = ColorSource(method: "Screen capture")) {
        let name = source.windowTitle.flatMap { $0.isEmpty ? nil : $0 }
            ?? source.websiteURL.flatMap(SavedCapture.webURL)?.host()
            ?? "Capture · \(Date().formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
        record = SavedCapture(name: name, width: image.width, height: image.height, source: source, palette: colors)
        self.image = image
    }

    init(record: SavedCapture, image: PaletteImage) { self.record = record; self.image = image }

    func source(proportion: Double? = nil, x: Int? = nil, y: Int? = nil, role: PaletteRole? = nil) -> ColorSource {
        var source = record.source
        source.capture = CaptureSource(id: id, width: image.width, height: image.height,
                                       pixelX: x, pixelY: y, proportion: proportion, suggestedRole: role)
        return source
    }

    func role(for value: ColorValue) -> PaletteRole? { colors.analysis.roles.first { $0.color.value == value }?.role }
}

enum CapturePaletteSelection {
    case roles, dominant, shades, curated
    func colors(in capture: ScreenPalette) -> [PaletteColor] {
        switch self {
        case .roles: capture.colors.analysis.roles.map(\.color)
        case .dominant: capture.colors.dominant
        case .shades: capture.colors.shades
        case .curated: (capture.record.samples ?? []).map { PaletteColor(value: $0.color, proportion: 0) }
        }
    }
}

/// Apple's built-in interactive capture provides the familiar crosshair,
/// rectangle selection, multi-display behavior, and Escape cancellation.
@MainActor
final class RegionCapture: ObservableObject {
    private let store: ColorStore
    private let accessCheck: () -> Bool
    private let accessRequest: () -> Bool
    private let preferences: UserDefaults
    private var process: Process?
    private var task: Task<Void, Never>?
    var beforeCapture: (() -> Void)?
    var afterCapture: ((_ showPalette: Bool) -> Void)?
    var presentHelp: (() -> Void)?
    var pickAfterSetup: (() -> Void)?
    @Published var helpPresented = false
    @Published private(set) var accessGranted: Bool
    @Published private(set) var requestedAccess: Bool
    @Published private(set) var captureFailure: String?
    @Published private(set) var relaunchFailure: String?
    @Published private(set) var checkedAfterSettings = false
    enum AccessPurpose { case pick, capture }
    @Published private(set) var accessPurpose: AccessPurpose = .pick
    private enum AfterHelp { case pick, capture, relaunch }
    private var afterHelp: AfterHelp?
    private var isRelaunching = false

    var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Couleur" }

    init(store: ColorStore, preferences: UserDefaults = .standard,
         accessCheck: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
         accessRequest: @escaping () -> Bool = CGRequestScreenCaptureAccess) {
        self.store = store
        self.preferences = preferences
        self.accessCheck = accessCheck
        self.accessRequest = accessRequest
        accessGranted = accessCheck()
        requestedAccess = preferences.bool(forKey: "screenAccessRequested")
    }

    func showAccessSetup(for purpose: AccessPurpose = .pick) {
        accessPurpose = purpose
        checkAccess()
        showHelp()
    }

    func capture() {
        guard !store.isSampling, !store.readOnly else { return }
        checkAccess()
        guard accessGranted else { showAccessSetup(for: .capture); return }
        accessPurpose = .capture
        captureFailure = nil
        store.isSampling = true
        let selection = CaptureSelection()
        selection.begin()
        beforeCapture?()
        task = Task { [weak self] in
            guard let self else { return }
            var presented = false
            defer {
                selection.stop()
                self.process = nil
                self.store.isSampling = false
                self.store.isExtracting = false
                if !presented { self.afterCapture?(false) }
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Couleur-capture-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                        attributes: [.posixPermissions: 0o700])
                let url = directory.appendingPathComponent("capture.png")
                // Allow the app's window to leave the compositor before selection starts.
                try await Task.sleep(for: .milliseconds(100))
                let result = try await runCapture(to: url)
                selection.stop()
                try Task.checkCancellation()
                guard FileManager.default.fileExists(atPath: url.path) else {
                    // The native selector exits with status 1 on Escape. No history or
                    // clipboard mutation takes place in this app when a capture is canceled.
                    if result.status > 1 || (!result.error.isEmpty && !result.error.localizedCaseInsensitiveContains("cancel")) {
                        throw CaptureFailure.failed(result.error)
                    }
                    return
                }
                let data = try Data(contentsOf: url)
                let windows = ScreenSource.windows()
                self.store.isExtracting = true
                self.store.filter = .capture
                self.store.search = ""
                self.afterCapture?(true)
                presented = true
                let worker = Task.detached(priority: .userInitiated) {
                    let image = try PaletteImage(data: data)
                    return try (image, image.extract())
                }
                let (image, colors) = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                let rect = selection.region(imageURL: url, image: image)
                let sourceWindow = rect.flatMap { ScreenSource.window(for: $0, in: windows) }
                let source = rect.map { ScreenSource.source(at: CGPoint(x: $0.midX, y: $0.midY), window: sourceWindow, method: "Screen capture") }
                    ?? ColorSource(method: "Screen capture")
                let capture = ScreenPalette(image: image, colors: colors, source: source)
                guard self.store.saveCapture(capture, imageData: data) else { self.store.filter = .captures; return }
                if self.store.rememberWebsites, let sourceWindow {
                    Task { [weak store = self.store] in
                        if let website = await BrowserSource.website(for: sourceWindow), store?.rememberWebsites == true {
                            store?.rememberWebsite(website, forCapture: capture.id)
                        }
                    }
                }
            } catch is CancellationError {
                // Quitting or canceling leaves the previous capture and library intact.
            } catch {
                self.captureFailure = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                self.checkAccess()
                self.afterCapture?(false)
                self.showHelp()
                presented = true
            }
        }
    }

    private func showHelp() {
        if let presentHelp { presentHelp() } else { helpPresented = true }
    }

    func checkAccess(explicit: Bool = false) {
        accessGranted = accessCheck()
        if explicit { checkedAfterSettings = true }
    }

    func requestAccess() {
        requestedAccess = true
        preferences.set(true, forKey: "screenAccessRequested")
        _ = accessRequest()
        checkAccess()
    }

    func openSettings() {
        requestedAccess = true
        preferences.set(true, forKey: "screenAccessRequested")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func continueAfterSetup() {
        guard accessGranted else { return }
        captureFailure = nil
        afterHelp = accessPurpose == .capture ? .capture : .pick
        helpPresented = false
    }

    func helpDidDismiss() {
        let action = afterHelp
        afterHelp = nil
        switch action {
        case .pick: pickAfterSetup?()
        case .capture: capture()
        case .relaunch:
            // Dismiss setup before AppKit starts the replacement instance.
            Task {
                do { try await AppRelaunch.perform(captureAfterSetup: accessPurpose == .capture) }
                catch {
                    isRelaunching = false
                    relaunchFailure = "Couldn’t reopen \(appName). \(error.localizedDescription)"
                    showHelp()
                }
            }
        case nil: break
        }
    }

    func relaunch() {
        guard !isRelaunching else { return }
        isRelaunching = true
        relaunchFailure = nil
        afterHelp = .relaunch
        helpPresented = false
    }

    func cancel() {
        task?.cancel()
        if process?.isRunning == true { process?.terminate() }
    }

    private func runCapture(to url: URL) async throws -> (status: Int32, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-s", "-x", "-t", "png", url.path]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        process.standardError = errors
        self.process = process
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { process in
                let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                continuation.resume(returning: (process.terminationStatus, message))
            }
            do { try process.run() }
            catch { process.terminationHandler = nil; continuation.resume(throwing: error) }
        }
    }
}

private enum CaptureFailure: LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let detail): detail.isEmpty ? "macOS did not return an image." : detail }
    }
}
