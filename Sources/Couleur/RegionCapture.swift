import AppKit
import Combine
import CouleurCore

struct ScreenPalette {
    let id = UUID()
    let createdAt = Date()
    let image: PaletteImage
    let colors: ExtractedPalette

    func source(proportion: Double? = nil, x: Int? = nil, y: Int? = nil) -> ColorSource {
        var source = ColorSource(method: "Screen capture")
        source.capture = CaptureSource(id: id, width: image.width, height: image.height,
                                       pixelX: x, pixelY: y, proportion: proportion)
        return source
    }
}

/// Apple's built-in interactive capture provides the familiar crosshair,
/// rectangle selection, multi-display behavior, and Escape cancellation.
@MainActor
final class RegionCapture: ObservableObject {
    private let store: ColorStore
    private var process: Process?
    private var task: Task<Void, Never>?
    var beforeCapture: (() -> Void)?
    var afterCapture: ((_ showPalette: Bool) -> Void)?
    var presentHelp: (() -> Void)?
    @Published var helpPresented = false
    @Published private(set) var accessGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var requestedAccess = UserDefaults.standard.bool(forKey: "screenAccessRequested")
    @Published private(set) var captureFailure: String?
    @Published private(set) var relaunchFailure: String?
    @Published private(set) var checkedAfterSettings = false
    private enum AfterHelp { case capture, relaunch }
    private var afterHelp: AfterHelp?
    private var isRelaunching = false

    var appName: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Couleur" }

    init(store: ColorStore) { self.store = store }

    func capture() {
        guard !store.isSampling, !store.readOnly else { return }
        checkAccess()
        guard accessGranted else { showHelp(); return }
        captureFailure = nil
        store.isSampling = true
        beforeCapture?()
        task = Task { [weak self] in
            guard let self else { return }
            var presented = false
            defer {
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
                self.store.screenPalette = ScreenPalette(image: image, colors: colors)
                self.store.selectedID = nil
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
        accessGranted = CGPreflightScreenCaptureAccess()
        if explicit { checkedAfterSettings = true }
    }

    func requestAccess() {
        requestedAccess = true
        UserDefaults.standard.set(true, forKey: "screenAccessRequested")
        _ = CGRequestScreenCaptureAccess()
        checkAccess()
    }

    func openSettings() {
        requestedAccess = true
        UserDefaults.standard.set(true, forKey: "screenAccessRequested")
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func continueCapture() {
        captureFailure = nil
        afterHelp = .capture
        helpPresented = false
    }

    func helpDidDismiss() {
        let action = afterHelp
        afterHelp = nil
        switch action {
        case .capture: capture()
        case .relaunch:
            // SwiftUI's sheet must finish closing before AppKit will accept quit.
            Task {
                do { try await AppRelaunch.perform() }
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
