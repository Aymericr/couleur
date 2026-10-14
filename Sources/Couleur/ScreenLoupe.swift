import AppKit
import CouleurCore
import OSLog
import ScreenCaptureKit

/// One short-lived screen snapshot per display. The lens and the saved color
/// always read the same pixels, even when the underlying content is moving.
@MainActor
final class ScreenLoupe {
    private let log = Logger(subsystem: "com.aymeric.couleur", category: "ScreenLoupe")
    private struct Snapshot {
        let screen: NSScreen
        let image: PaletteImage
        var grid: ScreenPixelGrid {
            ScreenPixelGrid(frame: screen.frame, width: image.width, height: image.height)
        }
    }

    private var snapshots: [Snapshot] = []
    private var panels: [LoupePanel] = []
    private var lenses: [PixelLoupeView] = []
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var completion: CheckedContinuation<Void, Never>?
    private var onPick: ((ColorValue, CGPoint) -> Void)?
    private var point = CGPoint.zero
    private var pendingRelease: (CGPoint, Bool)?
    private var mouseIsDown = false
    private var finished = false
    private var cursorHidden = false
    var isFinished: Bool { finished }

    static var previewImageURL: URL? {
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.aymeric.couleur.preview",
           let path = Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewLoupeImage") as? String {
            return URL(fileURLWithPath: path)
        }
        #endif
        return nil
    }

    func prepare(initiatedByPress: Bool) {
        point = NSEvent.mouseLocation
        mouseIsDown = initiatedByPress
        startMonitoring()
    }

    func run(onPick: @escaping (ColorValue, CGPoint) -> Void) async throws {
        log.debug("Preparing screen loupe")
        self.onPick = onPick
        defer { cleanUp() }
        guard !finished else { return }

        let captured: [Snapshot]
        if let fixture = Self.previewImageURL, let screen = NSScreen.main {
            captured = [Snapshot(screen: screen, image: try PaletteImage(data: Data(contentsOf: fixture)))]
        } else {
            captured = try await captureScreens()
        }
        guard !finished else { return }
        guard !captured.isEmpty else { throw LoupeFailure.displayUnavailable }
        snapshots = captured

        // A quick drag can finish while ScreenCaptureKit is preparing the image.
        // Preserve its exact release position and modifiers instead of losing it.
        if let (releasePoint, keepPicking) = pendingRelease {
            point = releasePoint
            select(keepPicking: keepPicking)
            guard !finished else { return }
        }
        showPanels()
        guard !finished else { return }
        log.debug("Screen loupe presented")
        await withCheckedContinuation { completion = $0 }
    }

    private func captureScreens() async throws -> [Snapshot] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var captured: [Snapshot] = []
        for screen in NSScreen.screens {
            guard !finished else { return [] }
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else {
                throw LoupeFailure.displayUnavailable
            }
            let excluded = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int((filter.contentRect.width * CGFloat(filter.pointPixelScale)).rounded())
            config.height = Int((filter.contentRect.height * CGFloat(filter.pointPixelScale)).rounded())
            config.showsCursor = false
            config.capturesAudio = false
            config.colorSpaceName = CGColorSpace.sRGB
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            captured.append(Snapshot(screen: screen, image: PaletteImage(cgImage: image)))
        }
        return captured
    }

    func cancel() {
        guard !finished else { return }
        log.debug("Finishing screen loupe")
        finished = true
        completion?.resume()
        completion = nil
        cleanUp()
    }

    private func startMonitoring() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown,
                                                              .leftMouseUp, .rightMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                return self.handle(event) == nil
            }
            return consumed ? nil : event
        }
        for notification in [NSApplication.didResignActiveNotification, NSApplication.didChangeScreenParametersNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.cancel() }
            })
        }
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard !finished else { return event }
        switch event.type {
        case .mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp:
            point = event.window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
            if event.type == .leftMouseDown { mouseIsDown = true }
            if event.type == .leftMouseUp, mouseIsDown {
                mouseIsDown = false
                let keepPicking = event.modifierFlags.contains(.shift)
                if snapshots.isEmpty { pendingRelease = (point, keepPicking) }
                else { select(keepPicking: keepPicking) }
            }
            if !finished { updateLens() }
            return nil
        case .rightMouseDown:
            cancel()
            return nil
        case .keyDown:
            switch event.keyCode {
            case 53: cancel()
            case 36, 76, 49: select(keepPicking: event.modifierFlags.contains(.shift))
            case 123: nudge(x: -1, y: 0)
            case 124: nudge(x: 1, y: 0)
            case 125: nudge(x: 0, y: 1)
            case 126: nudge(x: 0, y: -1)
            default:
                if event.modifierFlags.contains(.command) { cancel(); return event }
            }
            return nil
        default: return event
        }
    }

    private func showPanels() {
        for snapshot in snapshots {
            let panel = LoupePanel(contentRect: snapshot.screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.title = "Pick a color"
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = true
            panel.hasShadow = false
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.animationBehavior = .none
            let surface = FrozenScreenView(image: snapshot.image.cgImage, size: snapshot.screen.frame.size)
            let lens = PixelLoupeView(frame: CGRect(origin: .zero, size: PixelLoupeView.size))
            lens.isHidden = true
            surface.addSubview(lens)
            panel.contentView = surface
            panels.append(panel)
            lenses.append(lens)
            panel.orderFrontRegardless()
        }
        guard !finished, !panels.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        guard !finished, !panels.isEmpty else { return }
        let active = snapshots.firstIndex(where: { $0.grid.pixel(at: point) != nil }) ?? 0
        panels[active].makeKey()
        NSCursor.hide()
        cursorHidden = true
        updateLens()
    }

    private func updateLens() {
        for (index, snapshot) in snapshots.enumerated() where index < lenses.count {
            let lens = lenses[index]
            guard let pixel = snapshot.grid.pixel(at: point) else { lens.isHidden = true; continue }
            let local = CGPoint(x: point.x - snapshot.screen.frame.minX, y: snapshot.screen.frame.maxY - point.y)
            let side = PixelLoupeView.size.width
            lens.setFrameOrigin(CGPoint(x: min(max(0, local.x - side / 2), snapshot.screen.frame.width - side),
                                        y: min(max(0, local.y - side / 2), snapshot.screen.frame.height - side)))
            lens.update(image: snapshot.image, x: pixel.x, y: pixel.y)
            lens.isHidden = false
        }
    }

    private func select(keepPicking: Bool) {
        guard let snapshot = snapshots.first(where: { $0.grid.pixel(at: point) != nil }),
              let pixel = snapshot.grid.pixel(at: point), let value = snapshot.image.color(x: pixel.x, y: pixel.y) else { return }
        onPick?(value, point)
        if !keepPicking { cancel() }
    }

    private func nudge(x: Int, y: Int) {
        guard let snapshot = snapshots.first(where: { $0.grid.pixel(at: point) != nil }),
              let pixel = snapshot.grid.pixel(at: point) else { return }
        point = snapshot.grid.center(x: min(max(0, pixel.x + x), snapshot.image.width - 1),
                                     y: min(max(0, pixel.y + y), snapshot.image.height - 1))
        updateLens()
    }

    private func cleanUp() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        lenses.removeAll()
        snapshots.removeAll()
        if cursorHidden { NSCursor.unhide(); cursorHidden = false }
    }
}

private enum LoupeFailure: Error { case displayUnavailable }

@MainActor
private final class LoupePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class FrozenScreenView: NSView {
    let image: NSImage
    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    init(image: CGImage, size: CGSize) {
        self.image = NSImage(cgImage: image, size: size)
        super.init(frame: CGRect(origin: .zero, size: size))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .copy, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
    }
}

/// The only visible chrome: a hairline circle, a fine grid, and one outlined pixel.
@MainActor
private final class PixelLoupeView: NSView {
    static let size = CGSize(width: 181, height: 181)
    private static let cell: CGFloat = 11
    private var crop: CGImage?
    private var cropRect = CGRect.zero
    private var gridIsDark = true
    override var isFlipped: Bool { true }

    func update(image: PaletteImage, x: Int, y: Int) {
        let region = CGRect(x: x - 8, y: y - 8, width: 17, height: 17)
        let available = region.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        crop = image.cgImage.cropping(to: available)
        cropRect = CGRect(x: available.minX - region.minX, y: available.minY - region.minY,
                          width: available.width, height: available.height)
        if let color = image.color(x: x, y: y) {
            gridIsDark = color.red * 0.2126 + color.green * 0.7152 + color.blue * 0.0722 > 0.45
            setAccessibilityValue(color.hex)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext, let crop else { return }
        let circle = bounds.insetBy(dx: 8, dy: 8)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: NSColor.black.withAlphaComponent(0.16).cgColor)
        context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        context.fillEllipse(in: circle)
        context.restoreGState()

        context.saveGState()
        context.addEllipse(in: circle)
        context.clip()
        let origin = CGPoint(x: circle.midX - Self.cell * 8.5, y: circle.midY - Self.cell * 8.5)
        let destination = CGRect(x: origin.x + cropRect.minX * Self.cell, y: origin.y + cropRect.minY * Self.cell,
                                 width: cropRect.width * Self.cell, height: cropRect.height * Self.cell)
        NSImage(cgImage: crop, size: cropRect.size).draw(in: destination, from: .zero, operation: .copy, fraction: 1,
                                                      respectFlipped: true, hints: [.interpolation: NSImageInterpolation.none.rawValue])
        context.setStrokeColor((gridIsDark ? NSColor.black.withAlphaComponent(0.20) : NSColor.white.withAlphaComponent(0.24)).cgColor)
        context.setLineWidth(0.5)
        for index in 0...17 {
            let offset = CGFloat(index) * Self.cell
            context.move(to: CGPoint(x: origin.x + offset, y: circle.minY))
            context.addLine(to: CGPoint(x: origin.x + offset, y: circle.maxY))
            context.move(to: CGPoint(x: circle.minX, y: origin.y + offset))
            context.addLine(to: CGPoint(x: circle.maxX, y: origin.y + offset))
        }
        context.strokePath()
        context.restoreGState()

        context.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: circle)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.72).cgColor)
        context.setLineWidth(0.75)
        context.strokeEllipse(in: circle)

        let pixel = CGRect(x: circle.midX - Self.cell / 2, y: circle.midY - Self.cell / 2, width: Self.cell, height: Self.cell)
        context.setStrokeColor(NSColor.white.cgColor)
        context.setLineWidth(3)
        context.stroke(pixel)
        context.setStrokeColor(NSColor.black.cgColor)
        context.setLineWidth(1)
        context.stroke(pixel)
    }

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .image }
    override func accessibilityLabel() -> String? { "Color under pointer" }
    override func accessibilityHelp() -> String? { "Move to choose a pixel. Arrow keys refine the selection. Return picks, Shift keeps picking, and Escape cancels." }
}
