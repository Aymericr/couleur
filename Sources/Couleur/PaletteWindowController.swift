import AppKit
import QuartzCore
import SwiftUI

@MainActor
private final class PalettePanel: NSPanel {
    var expanded = false
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { expanded }
    override func performClose(_ sender: Any?) { orderOut(sender) }
}

/// Both presentations live in one panel. Its frame stays on screen throughout
/// the transition; only the content and native window chrome change.
@MainActor
final class PaletteWindowController: NSWindowController, NSWindowDelegate {
    private let store: ColorStore
    private let pick: (Bool) -> Void
    private let capture: RegionCapture
    private let panel: PalettePanel
    private var library: LibraryController!
    private var compact: NSHostingView<FloatingView>!
    private var expanded = false
    private var requestedExpanded = false
    private var transitioning = false
    private var queuedPick = false
    private var queuedCapture = false
    private var libraryActions: [() -> Void] = []
    private var compactFrame = NSRect.zero
    private var expandedSize = NSSize(width: 1040, height: 700)
    private var restoreAfterPicking = false

    private var pinned: Bool {
        get { UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pinned") }
    }
    private static let compactStyle: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
    private static let expandedStyle: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel]
    private static let minimumLibrarySize = NSSize(width: 760, height: 560)

    init(store: ColorStore, pick: @escaping (Bool) -> Void, capture: RegionCapture) {
        self.store = store
        self.pick = pick
        self.capture = capture
        panel = PalettePanel(contentRect: NSRect(origin: .zero, size: FloatingView.size),
                             styleMask: Self.compactStyle, backing: .buffered, defer: false)
        super.init(window: panel)
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.animationBehavior = .none
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.tabbingMode = .disallowed
        library = LibraryController(window: panel, store: store,
            captureManager: capture,
            pick: { [weak self] in self?.pickColor() }, capture: { [weak self] in self?.capturePalette() },
            compact: { [weak self] in self?.showPicker() })
        refreshCompact()
        install(expanded: false)
        panel.center()
        panel.setFrameUsingName("CouleurPicker")
        let restored = panel.frame
        compactFrame = fitted(NSRect(x: restored.minX, y: restored.maxY - FloatingView.size.height,
                                     width: FloatingView.size.width, height: FloatingView.size.height))
        panel.setFrame(compactFrame, display: false)
        if let saved = UserDefaults.standard.string(forKey: "librarySize") {
            let size = NSSizeFromString(saved)
            expandedSize = NSSize(width: max(Self.minimumLibrarySize.width, size.width),
                                  height: max(Self.minimumLibrarySize.height, size.height))
        }
        panel.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:pick:)") }

    func showLibrary(then action: (() -> Void)? = nil) {
        if let action { libraryActions.append(action) }
        show(expanded: true)
    }

    func showPicker() { show(expanded: false) }
    func reveal() { show(expanded: requestedExpanded) }
    func findColors() { showLibrary { [weak self] in self?.library.focusSearch() } }

    func pickColor(initiatedByPress: Bool = false) {
        guard !transitioning else { queuedPick = true; return }
        pick(initiatedByPress)
    }

    func capturePalette() {
        guard !transitioning else { queuedCapture = true; return }
        capture.capture()
    }

    func hideForPicking() {
        restoreAfterPicking = panel.isVisible
        panel.orderOut(nil)
    }

    func restoreAfterPick() {
        if restoreAfterPicking { panel.orderFrontRegardless() }
    }

    private func show(expanded: Bool) {
        requestedExpanded = expanded
        if !expanded { libraryActions.removeAll() }
        if panel.isMiniaturized { panel.deminiaturize(nil) }
        if expanded { NSApp.activate(ignoringOtherApps: true) }
        // Showing is only necessary after hiding the app, never between modes.
        if !panel.isVisible { panel.makeKeyAndOrderFront(nil) }
        else { panel.orderFrontRegardless() }
        settlePresentation()
    }

    private func settlePresentation() {
        guard !transitioning else { return }
        guard expanded != requestedExpanded else {
            let actions = libraryActions
            libraryActions.removeAll()
            if expanded { actions.forEach { $0() } }
            if queuedPick { queuedPick = false; pick(false) }
            if queuedCapture { queuedCapture = false; capture.capture() }
            return
        }
        transition(to: requestedExpanded)
    }

    private func refreshCompact() {
        let root = FloatingView(store: store,
            pick: { [weak self] pressed in self?.pickColor(initiatedByPress: pressed) },
            capture: { [weak self] in self?.capturePalette() },
            openImage: { [weak self] in self?.showLibrary { [weak self] in self?.store.importImage() } },
            showLibrary: { [weak self] in self?.showLibrary() },
            close: { [weak self] in self?.panel.performClose(nil) },
            togglePin: { [weak self] in self?.togglePin() }, isPinned: pinned)
        if let compact { compact.rootView = root }
        else {
            compact = NSHostingView(rootView: root)
            compact.sizingOptions = []
            compact.safeAreaRegions = []
        }
    }

    private func togglePin() {
        pinned.toggle()
        refreshCompact()
        if !expanded { panel.level = pinned ? .floating : .normal }
    }

    private func install(expanded: Bool) {
        panel.expanded = expanded
        panel.isFloatingPanel = !expanded
        panel.level = expanded ? .normal : (pinned ? .floating : .normal)
        panel.collectionBehavior = expanded ? [.managed, .fullScreenNone] : [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.styleMask = expanded ? Self.expandedStyle : Self.compactStyle
        panel.minSize = expanded ? Self.minimumLibrarySize : FloatingView.size
        panel.maxSize = expanded ? NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude) : FloatingView.size
        if expanded {
            panel.backgroundColor = .windowBackgroundColor
            library.install()
        } else {
            panel.title = "Couleur"
            panel.toolbar = nil
            panel.backgroundColor = .clear
            panel.contentViewController = nil
            panel.contentView = compact
        }
        panel.contentView?.alphaValue = 1
        panel.invalidateShadow()
    }

    private func transition(to targetExpanded: Bool) {
        transitioning = true
        panel.makeFirstResponder(nil)
        let sourceFrame = panel.frame
        if !expanded {
            compactFrame = sourceFrame
            panel.saveFrame(usingName: "CouleurPicker")
        } else {
            expandedSize = sourceFrame.size
            UserDefaults.standard.set(NSStringFromSize(expandedSize), forKey: "librarySize")
        }
        let targetFrame = targetExpanded
            ? fitted(NSRect(x: compactFrame.minX, y: compactFrame.maxY - expandedSize.height,
                            width: expandedSize.width, height: expandedSize.height))
            : fitted(compactFrame)

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, panel.isVisible else {
            finishTransition(to: targetExpanded, frame: targetFrame, fadeIn: false)
            return
        }

        // The outgoing content keeps its original geometry, so text never
        // stretches or reflows while the rounded surface changes size.
        let outgoing = panel.contentView!
        let surface = MorphSurface(frame: NSRect(origin: .zero, size: sourceFrame.size))
        panel.contentViewController = nil
        panel.toolbar = nil
        panel.styleMask = Self.compactStyle
        panel.minSize = .zero
        panel.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        panel.backgroundColor = .clear
        panel.contentView = surface
        outgoing.translatesAutoresizingMaskIntoConstraints = true
        outgoing.autoresizingMask = [.minYMargin]
        outgoing.frame = NSRect(x: 0, y: surface.bounds.height - sourceFrame.height,
                                width: sourceFrame.width, height: sourceFrame.height)
        surface.addSubview(outgoing)
        panel.setFrame(sourceFrame, display: true)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().setFrame(targetFrame, display: true)
            outgoing.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                outgoing.removeFromSuperview()
                outgoing.alphaValue = 1
                self.finishTransition(to: targetExpanded, frame: targetFrame, fadeIn: true)
            }
        }
    }

    private func finishTransition(to targetExpanded: Bool, frame: NSRect, fadeIn: Bool) {
        // Commit native chrome and content together, without displaying the
        // intermediate sizes AppKit computes when attaching a toolbar.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            install(expanded: targetExpanded)
            panel.setFrame(frame, display: false)
            panel.contentView?.alphaValue = fadeIn ? 0 : 1
            panel.contentView?.layoutSubtreeIfNeeded()
        }
        if panel.isVisible {
            panel.makeKeyAndOrderFront(nil)
            if targetExpanded { panel.makeMain() }
        }
        expanded = targetExpanded
        guard fadeIn, let content = panel.contentView else { transitionFinished(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.10
            content.animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in self?.transitionFinished() }
        }
    }

    private func transitionFinished() {
        transitioning = false
        panel.invalidateShadow()
        settlePresentation()
    }

    private func fitted(_ frame: NSRect) -> NSRect {
        guard let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return frame }
        let size = NSSize(width: min(frame.width, visible.width), height: min(frame.height, visible.height))
        return NSRect(x: max(visible.minX, min(frame.minX, visible.maxX - size.width)),
                      y: max(visible.minY, min(frame.minY, visible.maxY - size.height)),
                      width: size.width, height: size.height)
    }

    func windowDidMove(_ notification: Notification) { saveGeometry() }
    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? { store.undoManager }
    func windowDidResize(_ notification: Notification) { saveGeometry() }
    private func saveGeometry() {
        guard !transitioning else { return }
        if expanded {
            expandedSize = panel.frame.size
            UserDefaults.standard.set(NSStringFromSize(expandedSize), forKey: "librarySize")
        } else {
            compactFrame = panel.frame
            panel.saveFrame(usingName: "CouleurPicker")
        }
    }
}

/// A continuous, opaque surface gives the resize a stable silhouette and shadow.
@MainActor
private final class MorphSurface: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 0.5
        updateLayer()
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = NSColor(white: dark ? 0.115 : 0.985, alpha: 1).cgColor
        layer?.borderColor = NSColor(white: dark ? 1 : 0, alpha: dark ? 0.15 : 0.10).cgColor
    }
}
