import AppKit
import CouleurCore
import Darwin

struct SourceWindow: Sendable {
    let processID: Int32
    let bundleIdentifier: String?
    let appName: String?
    let title: String?
    let bounds: CGRect

    func matches(bounds candidate: [Double], title: String) -> Bool {
        guard candidate.count == 4 else { return false }
        let expected = [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY]
        guard zip(candidate, expected).allSatisfy({ abs($0 - $1) <= 2 }) else { return false }
        return self.title.map { $0.isEmpty || $0 == title } ?? true
    }
}

@MainActor
enum ScreenSource {
    static func windows() -> [SourceWindow] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let rect = window[kCGWindowBounds as String] as? [String: Double],
                  let x = rect["X"], let y = rect["Y"], let width = rect["Width"], let height = rect["Height"],
                  width > 0, height > 0 else { return nil }
            let app = NSRunningApplication(processIdentifier: pid)
            return SourceWindow(processID: pid, bundleIdentifier: app?.bundleIdentifier,
                                appName: app?.localizedName ?? window[kCGWindowOwnerName as String] as? String,
                                title: window[kCGWindowName as String] as? String,
                                bounds: CGRect(x: x, y: y, width: width, height: height))
        }
    }

    static func cgPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: CGDisplayBounds(CGMainDisplayID()).height - point.y)
    }

    static func source(at point: CGPoint, window: SourceWindow?, method: String = "Screen pick") -> ColorSource {
        let screen = NSScreen.screens.first { $0.frame.contains(cgPoint(point)) }
        return ColorSource(appName: window?.appName, bundleIdentifier: window?.bundleIdentifier,
                           windowTitle: window?.title, displayName: screen?.localizedName,
                           x: point.x, y: point.y, method: method)
    }

    /// A region spanning different windows has no single trustworthy source.
    static func window(for region: CGRect, in windows: [SourceWindow]) -> SourceWindow? {
        for window in windows where window.bounds.intersects(region) {
            return window.bounds.contains(region) ? window : nil
        }
        return nil
    }
}

/// Observes only the screenshot gesture, never keyboard input. macOS's saved
/// rectangle is preferred because users can reposition a selection with Space.
@MainActor
final class CaptureSelection {
    private var monitor: Any?
    private var start: CGPoint?
    private var end: CGPoint?

    func begin() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            MainActor.assumeIsolated {
                if event.type == .leftMouseDown { self?.start = NSEvent.mouseLocation }
                else { self?.end = NSEvent.mouseLocation }
            }
        }
    }

    func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }

    func region(imageURL: URL, image: PaletteImage) -> CGRect? {
        if let rect = Self.metadataRect(imageURL) { return rect }
        guard let start, let end else { return nil }
        let a = ScreenSource.cgPoint(start), b = ScreenSource.cgPoint(end)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        guard rect.width > 0, rect.height > 0,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(end) }),
              abs(rect.width * screen.backingScaleFactor - CGFloat(image.width)) <= 2,
              abs(rect.height * screen.backingScaleFactor - CGFloat(image.height)) <= 2 else { return nil }
        return rect
    }

    static func metadataRect(_ url: URL) -> CGRect? {
        let key = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
        let size = getxattr(url.path, key, nil, 0, 0, 0)
        guard size > 0, size < 4096 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, key, $0.baseAddress, size, 0, 0) }
        guard read == size,
              let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [NSNumber], values.count == 4 else { return nil }
        let numbers = values.map(\.doubleValue)
        guard numbers.allSatisfy({ $0.isFinite && abs($0) <= 100_000 }), numbers[2] > 0, numbers[3] > 0 else { return nil }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }
}
