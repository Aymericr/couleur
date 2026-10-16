import AppKit
import CouleurCore
import Sparkle

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
    private var regionCapture: RegionCapture!
    private var captureSetup: CaptureSetupController!
    private var palette: PaletteWindowController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    private var updater: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            guard await AppRelaunch.waitForPreviousInstance() else { NSApp.terminate(nil); return }
            finishLaunching()
        }
    }

    private func finishLaunching() {
        AppTypography.registerBundledFonts()
        // Use this build's artwork even while macOS retains an older icon cache.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApp.applicationIconImage = icon
        }
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
        // Development and isolated previews must never replace themselves with a public build.
        if !isPreview, Bundle.main.object(forInfoDictionaryKey: "CouleurUpdatesEnabled") as? Bool == true {
            updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
        picker = ScreenPicker(store: store)
        regionCapture = RegionCapture(store: store)
        #if DEBUG
        if isPreview, let state = Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewAccess") as? String,
           let preferences = UserDefaults(suiteName: "com.aymeric.couleur.preview.access") {
            preferences.set(state == "restart", forKey: "screenAccessRequested")
            regionCapture = RegionCapture(store: store, preferences: preferences,
                                          accessCheck: { state == "ready" }, accessRequest: { false })
        }
        #endif
        makeMenus()
        palette = PaletteWindowController(store: store, pick: { [weak self] pressed in
            self?.picker.pick(initiatedByPress: pressed)
        }, capture: regionCapture)
        if !isPreview { hotKey = HotKey { [weak self] in self?.pickColor() } }
        picker.beforePick = { [weak self] in self?.palette.hideForPicking() }
        picker.afterPick = { [weak self] in self?.palette.restoreAfterPick() }
        regionCapture.beforeCapture = { [weak self] in self?.palette.hideForPicking() }
        regionCapture.afterCapture = { [weak self] showPalette in
            self?.palette.restoreAfterPick()
            if showPalette { self?.palette.showLibrary() }
        }
        regionCapture.presentHelp = { [weak self] in
            self?.regionCapture.helpPresented = true
        }
        regionCapture.pickAfterSetup = { [weak self] in self?.palette.pickColor() }
        captureSetup = CaptureSetupController(capture: regionCapture)
        captureSetup.beforeShow = { [weak self] in self?.palette.hideForPicking() }
        captureSetup.afterDismiss = { [weak self] in self?.palette.restoreAfterPick() }
        #if DEBUG
        if isPreview, Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewAccess") != nil {
            showFloating()
            regionCapture.showAccessSetup()
            return
        }
        if isPreview, !arguments.contains("--capture-help"),
           let path = Bundle.main.object(forInfoDictionaryKey: "CouleurPreviewImage") as? String {
            store.filter = .capture
            store.isExtracting = true
            palette.showLibrary()
            Task {
                do {
                    let result = try await Task.detached(priority: .userInitiated) {
                        let image = try PaletteImage(data: Data(contentsOf: URL(fileURLWithPath: path)))
                        return try (image, image.extract())
                    }.value
                    let imageData = try Data(contentsOf: URL(fileURLWithPath: path))
                    let capture = ScreenPalette(image: result.0, colors: result.1, source: ColorSource(method: "Design preview"))
                    _ = store.saveCapture(capture, imageData: imageData)
                } catch { store.error = error.localizedDescription }
                store.isExtracting = false
            }
            return
        }
        #endif
        if arguments.contains("--capture-help") {
            showFloating()
            regionCapture.checkAccess(explicit: true)
            regionCapture.showAccessSetup(for: arguments.contains("--capture-after-setup") ? .capture : .pick)
        } else if arguments.contains("--library") { showLibrary() } else { showFloating() }
        if !isPreview, !arguments.contains("--capture-help"), store.library.colors.isEmpty,
           !regionCapture.accessGranted, !UserDefaults.standard.bool(forKey: "hasSeenScreenAccessSetup") {
            UserDefaults.standard.set(true, forKey: "hasSeenScreenAccessSetup")
            regionCapture.showAccessSetup()
        }
    }

    @objc private func findColors() { palette.findColors() }
    @objc private func showLibrary() { palette.showLibrary() }
    @objc private func showFloating() { palette.showPicker() }
    @objc private func pickColor() { palette.pickColor() }
    @objc private func capturePalette() { palette.capturePalette() }
    @objc private func closeWindow(_ sender: Any?) { (NSApp.keyWindow ?? palette.window)?.performClose(sender) }
    @objc func copy(_ sender: Any?) { if let record = store.selected { store.copy(record) } }
    @objc func paste(_ sender: Any?) { store.paste() }
    @objc private func importLibrary() { palette.showLibrary { [weak self] in self?.store.importLibrary() } }
    @objc private func importImage() { palette.showLibrary { [weak self] in self?.store.importImage() } }
    @objc private func exportLibrary() { palette.showLibrary { [weak self] in self?.store.exportLibrary() } }
    @objc private func revealLibrary() { store.revealLibrary() }
    @objc private func showScreenAccess() {
        regionCapture.showAccessSetup()
    }
    @objc private func toggleAutoCopy() { store.autoCopy.toggle() }
    @objc private func toggleRememberWebsites() { store.rememberWebsites.toggle() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock activation and returning from Settings preserve the current view
        // and the setup window. Never reveal our window inside a screen selection.
        if let store, !store.isSampling, !regionCapture.helpPresented { palette.reveal() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { picker?.cancel(); regionCapture?.cancel() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutoCopy) { menuItem.state = store.autoCopy ? .on : .off }
        if menuItem.action == #selector(toggleRememberWebsites) { menuItem.state = store.rememberWebsites ? .on : .off }
        // Borderless panels do not advertise AppKit's standard closable style.
        if menuItem.action == #selector(closeWindow(_:)) {
            return (NSApp.keyWindow ?? palette?.window)?.isVisible == true
        }
        if menuItem.action == #selector(pickColor) || menuItem.action == #selector(capturePalette) || menuItem.action == #selector(importImage) {
            return !store.isSampling && !store.isExtracting && !store.readOnly && !regionCapture.helpPresented
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
        if let updater {
            let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            updateItem.target = updater
            app.addItem(updateItem)
        }
        app.addItem(.separator())
        app.addItem(item("Copy After Picking", #selector(toggleAutoCopy)))
        app.addItem(item("Remember Source Websites", #selector(toggleRememberWebsites)))
        app.addItem(.separator())
        app.addItem(item("Screen Access…", #selector(showScreenAccess)))
        app.addItem(item("Reveal Library Folder", #selector(revealLibrary)))
        app.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Couleur", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(hide)
        app.addItem(NSMenuItem(title: "Quit Couleur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        let appRoot = NSMenuItem(); appRoot.submenu = app; main.addItem(appRoot)

        let file = NSMenu(title: "File")
        file.addItem(item("Pick Color", #selector(pickColor), key: "p", modifiers: [.command, .shift]))
        file.addItem(item("Capture Screen Palette", #selector(capturePalette), key: "a", modifiers: [.command, .shift]))
        file.addItem(item("Open Image…", #selector(importImage), key: "o"))
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
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.insertItem(redo, at: 1)
        edit.addItem(.separator())
        edit.addItem(item("Find Colors", #selector(findColors), key: "f"))
        let editRoot = NSMenuItem(); editRoot.submenu = edit; main.addItem(editRoot)

        let window = NSMenu(title: "Window")
        window.addItem(item("Color Library", #selector(showLibrary), key: "1"))
        window.addItem(item("Floating Picker", #selector(showFloating), key: "2"))
        let windowRoot = NSMenuItem(); windowRoot.submenu = window; main.addItem(windowRoot)
        let help = NSMenu(title: "Help")
        help.addItem(item("Couleur Website", #selector(openWebsite)))
        help.addItem(item("Privacy & Legal", #selector(openPrivacy)))
        help.addItem(item("License", #selector(openLicense)))
        let helpRoot = NSMenuItem(); helpRoot.submenu = help; main.addItem(helpRoot)
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
        NSApp.helpMenu = help

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "eyedropper.halffull", accessibilityDescription: "Couleur")
        let statusMenu = NSMenu()
        let pickItem = item("Pick Color   ⌃⌥C", #selector(pickColor))
        statusMenu.addItem(pickItem)
        statusMenu.addItem(item("Capture Screen Palette", #selector(capturePalette)))
        statusMenu.addItem(item("Floating Picker", #selector(showFloating)))
        statusMenu.addItem(item("Color Library", #selector(showLibrary)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit Couleur", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        statusItem.menu = statusMenu
    }

    @objc private func showAbout() {
        var options: [NSApplication.AboutPanelOptionKey: Any] = [
            .applicationName: "Couleur",
            .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            .credits: NSAttributedString(string: "A home for the colors you find.\nFree and open source. Made by Aymeric Rabot.\naymeric.dev/couleur\nInspired by Couleurs by Laurent Baumann.")
        ]
        if let icon = NSApp.applicationIconImage { options[.applicationIcon] = icon }
        NSApp.orderFrontStandardAboutPanel(options: options)
    }

    @objc private func openWebsite() {
        NSWorkspace.shared.open(URL(string: "https://www.aymeric.dev/couleur")!)
    }

    @objc private func openPrivacy() {
        NSWorkspace.shared.open(URL(string: "https://www.aymeric.dev/legal")!)
    }

    @objc private func openLicense() {
        if let url = Bundle.main.url(forResource: "LICENSE", withExtension: "txt") {
            NSWorkspace.shared.open(url)
        }
    }
}
