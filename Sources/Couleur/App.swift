import AppKit

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
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var store: ColorStore!
    private var picker: ScreenPicker!
    private var palette: PaletteWindowController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        var directory: URL? = if let index = arguments.firstIndex(of: "--data-directory"), arguments.indices.contains(index + 1) {
            URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        } else { nil }
        var isPreview = false
        #if DEBUG
        if Bundle.main.bundleIdentifier == "com.aymeric.couleur.preview",
           let path = Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewDirectory") as? String {
            directory = URL(fileURLWithPath: path, isDirectory: true)
            isPreview = true
            if let appearance = Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewAppearance") as? String {
                NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
            }
        }
        #endif
        store = ColorStore(directory: directory)
        picker = ScreenPicker(store: store)
        makeMenus()
        palette = PaletteWindowController(store: store) { [weak self] pressed in
            self?.picker.pick(initiatedByPress: pressed)
        }
        if !isPreview { hotKey = HotKey { [weak self] in self?.pickColor() } }
        picker.beforePick = { [weak self] in self?.palette.hideForPicking() }
        picker.afterPick = { [weak self] in self?.palette.restoreAfterPick() }
        if arguments.contains("--library") { showLibrary() } else { showFloating() }
    }

    @objc private func findColors() { palette.findColors() }
    @objc private func showLibrary() { palette.showLibrary() }
    @objc private func showFloating() { palette.showPicker() }
    @objc private func pickColor() { palette.pickColor() }
    @objc private func closeWindow(_ sender: Any?) { (NSApp.keyWindow ?? palette.window)?.performClose(sender) }
    @objc func copy(_ sender: Any?) { if let record = store.selected { store.copy(record) } }
    @objc func paste(_ sender: Any?) { store.paste() }
    @objc private func importLibrary() { palette.showLibrary { [weak self] in self?.store.importLibrary() } }
    @objc private func exportLibrary() { palette.showLibrary { [weak self] in self?.store.exportLibrary() } }
    @objc private func revealLibrary() { store.revealLibrary() }
    @objc private func toggleAutoCopy() { store.autoCopy.toggle() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showFloating(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        // Borderless panels do not advertise AppKit's standard closable style.
        if menuItem.action == #selector(closeWindow(_:)) {
            return (NSApp.keyWindow ?? palette?.window)?.isVisible == true
        }
        return true
    }

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
        file.addItem(item("Close Window", #selector(closeWindow(_:)), key: "w"))
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
