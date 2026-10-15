import AppKit
import CouleurCore
import OSLog

@MainActor
final class ScreenPicker {
    private let sampler = NativeColorSampler()
    private let store: ColorStore
    private var loupe: ScreenLoupe?
    private var task: Task<Void, Never>?
    var beforePick: (() -> Void)?
    var afterPick: (() -> Void)?

    init(store: ColorStore) { self.store = store }

    func pick(initiatedByPress: Bool = false) {
        guard !store.isSampling, !store.readOnly else { return }
        let performance = PickPerformance()
        store.isSampling = true
        let sourceWindows = performance.measure("SourceWindows") { ScreenSource.windows() }
        var useLoupe = ScreenLoupe.previewImageURL != nil || CGPreflightScreenCaptureAccess()
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.aymeric.couleur.preview",
           Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewNativeSampler") as? Bool == true { useLoupe = false }
        #endif
        let custom = useLoupe ? ScreenLoupe(performance: performance) : nil
        loupe = custom
        // Install input tracking during mouse-down, before asynchronous capture
        // preparation can miss a quick drag's release.
        custom?.prepare(initiatedByPress: initiatedByPress)
        beforePick?()
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.loupe = nil
                self.task = nil
                self.store.isSampling = false
                self.afterPick?()
                performance.finish()
            }
            // The quiet loupe uses the screen access already granted for area palettes.
            // Picking still works through AppKit if access is absent or capture fails.
            if let loupe = custom {
                do {
                    try await loupe.run { [weak self] value, point in
                        guard let self, !Task.isCancelled else { return }
                        self.keep(value, at: point, windows: sourceWindows, performance: performance)
                    }
                    return
                } catch {
                    self.loupe = nil
                    guard !Task.isCancelled, !loupe.isFinished else { return }
                    Logger(subsystem: "com.aymeric.couleur", category: "ScreenPicker")
                        .error("Screen loupe unavailable; using AppKit sampler: \(error.localizedDescription)")
                }
            }
            // Keep the system sampler's established presentation timing. Drag
            // picks start during mouse-down; menu picks allow our window to hide.
            if !initiatedByPress { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled else { return }
            repeat {
                performance.nativeSamplerRequested()
                guard let value = await self.sampler.sample(), !Task.isCancelled else { break }
                self.keep(value, at: NSEvent.mouseLocation, windows: sourceWindows, performance: performance)
                // Shift is sampled at selection time. Release it for the final pick, or press Esc to finish.
                guard NSEvent.modifierFlags.contains(.shift) else { break }
            } while true
        }
    }

    func cancel() {
        task?.cancel()
        loupe?.cancel()
    }

    private func keep(_ value: ColorValue, at pointer: CGPoint, windows: [SourceWindow], performance: PickPerformance) {
        let point = ScreenSource.cgPoint(pointer)
        let window = windows.first { $0.bounds.contains(point) }
        let source = ScreenSource.source(at: point, window: window)
        let id = performance.measure("KeepPickedColor") { store.add(value, source: source, performance: performance) }
        guard let id, store.rememberWebsites, let window else { return }
        Task { [weak store] in
            if let website = await BrowserSource.website(for: window), store?.rememberWebsites == true {
                store?.rememberWebsite(website, forColor: id)
            }
        }
    }
}
