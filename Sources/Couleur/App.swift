import AppKit
import CouleurCore
import SwiftUI

@main
@MainActor
enum CouleurApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var store: ColorStore!
    private var picker: ScreenPicker!
    private var libraryWindow: NSWindow!
    private var libraryController: LibraryWindowController!
    private var floatingPanel: FloatingPanel!
    private var pinButton: NSButton!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var restoreLibrary = false
    private var restorePanel = false
    private var pinned: Bool {
        get { UserDefaults.standard.object(forKey: "pinned") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "pinned") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        let directory: URL? = if let index = arguments.firstIndex(of: "--data-directory"), arguments.indices.contains(index + 1) {
            URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else { nil }
        store = ColorStore(directory: directory)
        picker = ScreenPicker(store: store)
        makeMenus()
        makeWindows()
        hotKey = HotKey { [weak self] in self?.pickColor() }
        picker.beforePick = { [weak self] in
            guard let self else { return }
            self.restoreLibrary = self.libraryWindow.isVisible
            self.restorePanel = self.floatingPanel.isVisible
            self.libraryWindow.orderOut(nil); self.floatingPanel.orderOut(nil)
        }
        picker.afterPick = { [weak self] in
            guard let self else { return }
            if self.restoreLibrary { self.libraryWindow.orderFrontRegardless() }
            if self.restorePanel { self.floatingPanel.orderFrontRegardless() }
        }
        if arguments.contains("--library") { showLibrary() } else { showFloating() }
    }

    private func makeWindows() {
        libraryController = LibraryWindowController(store: store,
            pick: { [weak self] in self?.pickColor() }, compact: { [weak self] in self?.showFloating() })
        libraryWindow = libraryController.window
        libraryWindow.delegate = self

        floatingPanel = FloatingPanel(contentRect: NSRect(origin: .zero, size: FloatingView.size), styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        floatingPanel.title = "Couleur"
        floatingPanel.isFloatingPanel = true
        floatingPanel.hidesOnDeactivate = false
        floatingPanel.isReleasedWhenClosed = false
        floatingPanel.titlebarAppearsTransparent = true
        floatingPanel.titleVisibility = .visible
        floatingPanel.isMovableByWindowBackground = true
        floatingPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        floatingPanel.delegate = self
        let accessory = NSTitlebarAccessoryViewController()
        accessory.layoutAttribute = .right
        let controls = NSView(frame: NSRect(x: 0, y: 0, width: 53, height: 24))
        pinButton = NSButton(image: NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Keep on top")!, target: self, action: #selector(togglePin))
        pinButton.bezelStyle = .inline
        pinButton.isBordered = false
        pinButton.frame = NSRect(x: 0, y: 0, width: 24, height: 24)
        pinButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
        controls.addSubview(pinButton)
        let expand = NSButton(image: NSImage(systemSymbolName: "arrow.up.left.and.arrow.down.right", accessibilityDescription: "Expand library")!, target: self, action: #selector(showLibrary))
        expand.bezelStyle = .inline
        expand.isBordered = false
        expand.frame = NSRect(x: 25, y: 0, width: 26, height: 24)
        expand.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        expand.toolTip = "Expand library · ⌘1"
        controls.addSubview(expand)
        accessory.view = controls
        floatingPanel.addTitlebarAccessoryViewController(accessory)
        updateFloatingPanel()
        floatingPanel.center()
        floatingPanel.setFrameAutosaveName("CouleurPicker")
        floatingPanel.setContentSize(FloatingView.size)
    }

    private func updateFloatingPanel() {
        floatingPanel.level = pinned ? .floating : .normal
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "Keep on top")
        pinButton.contentTintColor = pinned ? .secondaryLabelColor : .tertiaryLabelColor
        pinButton.toolTip = pinned ? "Keep on top is on" : "Keep on top is off"
        pinButton.setAccessibilityValue(pinned ? "On" : "Off")
        floatingPanel.contentView = NSHostingView(rootView: FloatingView(store: store,
            pick: { [weak self] in self?.picker.pick(initiatedByPress: true) }, showLibrary: { [weak self] in self?.showLibrary() }))
    }

    @objc private func togglePin() { pinned.toggle(); updateFloatingPanel() }
    @objc private func findColors() { showLibrary(); libraryController.focusSearch() }

    @objc private func showLibrary() {
        floatingPanel?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        libraryWindow.makeKeyAndOrderFront(nil)
    }
    @objc private func showFloating() {
        libraryWindow?.orderOut(nil)
        floatingPanel.makeKeyAndOrderFront(nil)
        floatingPanel.orderFrontRegardless()
    }
    @objc private func pickColor() { picker.pick() }
    @objc func copy(_ sender: Any?) { if let record = store.selected { store.copy(record) } }
    @objc func paste(_ sender: Any?) { store.paste() }
    @objc private func importLibrary() { showLibrary(); store.importLibrary() }
    @objc private func exportLibrary() { showLibrary(); store.exportLibrary() }
    @objc private func revealLibrary() { store.revealLibrary() }
    @objc private func toggleAutoCopy() { store.autoCopy.toggle() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showFloating(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func item(_ title: String, _ action: Selector?, key: String = "", modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self; item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func makeMenus() {
        let main = NSMenu()
        let app = NSMenu(title: "Couleur")
        app.addItem(item("About Couleur", #selector(showAbout)))
        app.addItem(.separator())
        app.addItem(item("Reveal Library Folder", #selector(revealLibrary)))
        app.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Couleur", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(hide)
        app.addItem(NSMenuItem(title: "Quit Couleur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appRoot = NSMenuItem(); appRoot.submenu = app; main.addItem(appRoot)

        let file = NSMenu(title: "File")
        file.addItem(item("Pick Color", #selector(pickColor), key: "p", modifiers: [.command, .shift]))
        file.addItem(item("Paste Color into Library", #selector(paste(_:)), key: "v", modifiers: [.command, .shift]))
        file.addItem(.separator())
        file.addItem(item("Import Library…", #selector(importLibrary)))
        file.addItem(item("Export Library…", #selector(exportLibrary), key: "e", modifiers: [.command, .shift]))
        file.addItem(.separator())
        file.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        let fileRoot = NSMenuItem(); fileRoot.submenu = file; main.addItem(fileRoot)

        let edit = NSMenu(title: "Edit")
        for (title, action, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"), ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"), ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.addItem(.separator())
        edit.addItem(item("Find Colors", #selector(findColors), key: "f"))
        let editRoot = NSMenuItem(); editRoot.submenu = edit; main.addItem(editRoot)

        let window = NSMenu(title: "Window")
        window.addItem(item("Color Library", #selector(showLibrary), key: "1"))
        window.addItem(item("Floating Picker", #selector(showFloating), key: "2"))
        let windowRoot = NSMenuItem(); windowRoot.submenu = window; main.addItem(windowRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: "Couleur")
        let statusMenu = NSMenu()
        let pickItem = item("Pick Color   ⌃⌥C", #selector(pickColor))
        statusMenu.addItem(pickItem)
        statusMenu.addItem(item("Floating Picker", #selector(showFloating)))
        statusMenu.addItem(item("Color Library", #selector(showLibrary)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit Couleur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = statusMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Couleur",
            .applicationVersion: "1.0",
            .credits: NSAttributedString(string: "A home for the colors you find.\nBuilt for personal use. Inspired by Couleurs by Laurent Baumann.")
        ])
    }
}
