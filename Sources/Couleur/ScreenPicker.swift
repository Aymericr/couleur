import AppKit
import CouleurCore

@MainActor
final class ScreenPicker {
    private let sampler = NSColorSampler()
    private let store: ColorStore
    var beforePick: (() -> Void)?
    var afterPick: (() -> Void)?

    init(store: ColorStore) { self.store = store }

    func pick(initiatedByPress: Bool = false) {
        guard !store.isSampling, !store.readOnly else { return }
        store.isSampling = true
        beforePick?()
        Task { @MainActor [weak self] in
            // Start during mouse-down for dragging. Menu/keyboard picks wait a frame for our windows to hide.
            if !initiatedByPress { try? await Task.sleep(for: .milliseconds(80)) }
            guard let self else { return }
            repeat {
                guard let color = await self.sampler.sample() else { break }
                let source = self.sourceAtPointer()
                if let value = ColorValue(color) { self.store.add(value, source: source) }
                // Shift is sampled at selection time. Release it for the final pick, or press Esc to finish.
                guard NSEvent.modifierFlags.contains(.shift) else { break }
            } while true
            self.store.isSampling = false
            self.afterPick?()
        }
    }

    private func sourceAtPointer() -> ColorSource {
        let pointer = NSEvent.mouseLocation
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
