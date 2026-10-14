import AppKit
import CouleurCore
import OSLog

@MainActor
final class ScreenPicker {
    private let sampler = NSColorSampler()
    private let store: ColorStore
    private var loupe: ScreenLoupe?
    private var task: Task<Void, Never>?
    var beforePick: (() -> Void)?
    var afterPick: (() -> Void)?

    init(store: ColorStore) { self.store = store }

    func pick(initiatedByPress: Bool = false) {
        guard !store.isSampling, !store.readOnly else { return }
        store.isSampling = true
        let custom = ScreenLoupe.previewImageURL != nil || CGPreflightScreenCaptureAccess() ? ScreenLoupe() : nil
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
            }
            // The quiet loupe uses the screen access already granted for area palettes.
            // Picking still works through AppKit if access is absent or capture fails.
            if let loupe = custom {
                do {
                    try await loupe.run { [weak self] value, point in
                        guard let self else { return }
                        self.store.add(value, source: self.source(at: point))
                    }
                    return
                } catch {
                    self.loupe = nil
                    guard !Task.isCancelled, !loupe.isFinished else { return }
                    Logger(subsystem: "com.aymeric.couleur", category: "ScreenPicker")
                        .error("Screen loupe unavailable; using AppKit sampler: \(error.localizedDescription)")
                }
            }
            // Start during mouse-down for dragging. Menu/keyboard picks wait a frame for our windows to hide.
            if !initiatedByPress { try? await Task.sleep(for: .milliseconds(80)) }
            guard !Task.isCancelled else { return }
            repeat {
                guard let value = await self.sampleValue() else { break }
                let source = self.source(at: NSEvent.mouseLocation)
                self.store.add(value, source: source)
                // Shift is sampled at selection time. Release it for the final pick, or press Esc to finish.
                guard NSEvent.modifierFlags.contains(.shift) else { break }
            } while true
        }
    }

    func cancel() {
        task?.cancel()
        loupe?.cancel()
    }

    private func sampleValue() async -> ColorValue? {
        // Older AppKit SDKs import sample() as nonisolated. Bridge the callback on our main actor
        // instead, and send only the sRGB value across the continuation, never an AppKit object.
        await withCheckedContinuation { continuation in
            sampler.show { color in
                continuation.resume(returning: color.flatMap { ColorValue($0) })
            }
        }
    }

    private func source(at pointer: CGPoint) -> ColorSource {
        // CG window rectangles use a top-left origin on the main display; AppKit uses bottom-left.
        let cgPoint = CGPoint(x: pointer.x, y: CGDisplayBounds(CGMainDisplayID()).height - pointer.y)
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) }
        var source = ColorSource(displayName: screen?.localizedName, x: cgPoint.x, y: cgPoint.y)
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return source }
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Double],
                  let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"],
                  CGRect(x: x, y: y, width: width, height: height).contains(cgPoint) else { continue }
            let app = NSRunningApplication(processIdentifier: pid)
            source.appName = app?.localizedName ?? window[kCGWindowOwnerName as String] as? String
            source.bundleIdentifier = app?.bundleIdentifier
            source.windowTitle = window[kCGWindowName as String] as? String
            break
        }
        return source
    }
}
