import AppKit
import Combine
import SwiftUI

/// Two destinations, one canvas, and an optional inspector.
@MainActor
final class LibraryController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    private weak var window: NSWindow?
    private let store: ColorStore
    private let pick: () -> Void
    private let capture: () -> Void
    private let compact: () -> Void
    private let split = NSSplitViewController()
    private var inspector: NSSplitViewItem!
    private var observations: Set<AnyCancellable> = []
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .colorSearch)
    private let libraryToolbar = NSToolbar(identifier: "CouleurLibraryToolbar")
    private let destinations = NSSegmentedControl(labels: ["Colors", "Captures"], trackingMode: .selectOne, target: nil, action: nil)
    private var utilityButtons: [NSToolbarItem.Identifier: NSButton] = [:]
    private var lastColorFilter: LibraryFilter = .all

    init(window: NSWindow, store: ColorStore, captureManager: RegionCapture, pick: @escaping () -> Void,
         capture: @escaping () -> Void, compact: @escaping () -> Void) {
        self.store = store; self.pick = pick; self.compact = compact
        self.capture = capture
        self.window = window
        super.init()

        let content = NSSplitViewItem(viewController: NSHostingController(rootView: LibraryView(store: store, capture: captureManager, pick: pick)))
        content.minimumThickness = 360
        content.holdingPriority = .defaultLow
        inspector = NSSplitViewItem(inspectorWithViewController: InspectorHost(store: store))
        inspector.minimumThickness = 260
        inspector.maximumThickness = 300
        inspector.preferredThicknessFraction = 0.26
        inspector.isCollapsed = true
        // Keep the utility actions across the whole window when details open.
        inspector.allowsFullHeightLayout = false
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(content)
        split.addSplitViewItem(inspector)
        libraryToolbar.delegate = self
        libraryToolbar.displayMode = .iconOnly
        libraryToolbar.allowsUserCustomization = false
        destinations.target = self
        destinations.action = #selector(changeDestination)
        destinations.segmentStyle = .rounded
        destinations.font = AppTypography.native(size: 13, weight: .medium)
        destinations.setAccessibilityLabel("Library")

        store.objectWillChange.sink { [weak self] in
            // Published sends before the mutation; refresh chrome after the values settle.
            Task { @MainActor [weak self] in self?.refreshChrome() }
        }.store(in: &observations)
        refreshChrome()
    }

    func install() {
        guard let window else { return }
        // NSWindow adopts a controller's existing view size on assignment.
        // Prepare it at the final size so installing the split does not snap
        // the just-expanded window back to the split's minimum dimensions.
        split.view.frame = NSRect(origin: .zero, size: window.contentView?.bounds.size ?? window.frame.size)
        window.contentViewController = split
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.titlebarSeparatorStyle = .none
        window.toolbar = libraryToolbar
        refreshChrome()
    }

    func focusSearch() {
        if store.filter == .capture { store.filter = .captures }
        searchItem.beginSearchInteraction()
        searchItem.searchField.selectText(nil)
    }

    private func refreshChrome() {
        let searchingCaptures = store.filter == .captures || store.filter == .capture
        let collapseDetails = searchingCaptures || !store.detailsVisible
        if inspector.isCollapsed != collapseDetails {
            if window?.contentViewController === split && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                inspector.animator().isCollapsed = collapseDetails
            } else { inspector.isCollapsed = collapseDetails }
        }
        destinations.selectedSegment = searchingCaptures ? 1 : 0
        if !searchingCaptures { lastColorFilter = store.filter }
        searchItem.searchField.placeholderString = searchingCaptures ? "Search captures" : "Search colors"
        searchItem.searchField.setAccessibilityLabel(searchingCaptures ? "Search captures" : "Search colors")
        if window?.contentViewController === split {
            window?.title = store.filter == .all ? "All Colors" : store.filterTitle
        }
        if searchItem.searchField.stringValue != store.search { searchItem.searchField.stringValue = store.search }
        utilityButtons.values.forEach { $0.isEnabled = !store.isSampling && !store.isExtracting && !store.readOnly }
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if store.filter == .capture { store.filter = .captures }
        store.search = field.stringValue
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.colorDestinations, .flexibleSpace, .colorPick, .colorCapture, .colorImport, .colorSearch, .colorCompact]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .colorDestinations:
            let item = NSToolbarItem(itemIdentifier: id)
            item.label = "Library"
            item.view = destinations
            item.visibilityPriority = .high
            return item
        case .colorCompact:
            let item = button(id, "Compact Picker", symbol: "arrow.down.right.and.arrow.up.left", action: #selector(showCompact))
            item.toolTip = "Return to compact picker · ⌘2"
            item.visibilityPriority = .high
            return item
        case .colorPick:
            return collectionButton(id, "Pick color", symbol: "eyedropper", shortcut: "⌃⌥C", action: #selector(pickColor))
        case .colorCapture:
            return collectionButton(id, "Capture area", symbol: "viewfinder", shortcut: "⌘⇧A", action: #selector(capturePalette))
        case .colorImport:
            return collectionButton(id, "Open image", symbol: "photo", shortcut: "⌘O", action: #selector(importImage))
        case .colorSearch:
            searchItem.label = "Search Colors"
            searchItem.searchField.placeholderString = "Search colors"
            searchItem.searchField.delegate = self
            searchItem.searchField.font = AppTypography.native(size: 12)
            searchItem.searchField.sendsSearchStringImmediately = true
            searchItem.preferredWidthForSearchField = 140
            searchItem.visibilityPriority = .low
            searchItem.searchField.setAccessibilityLabel("Search colors")
            return searchItem
        default: return nil
        }
    }

    private func button(_ id: NSToolbarItem.Identifier, _ title: String, symbol: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = title
        item.toolTip = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        item.target = self
        item.action = action
        item.autovalidates = false
        return item
    }

    private func collectionButton(_ id: NSToolbarItem.Identifier, _ title: String, symbol: String,
                                  shortcut: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: id)
        let control = NSButton(title: title, target: self, action: action)
        control.bezelStyle = .texturedRounded
        control.font = AppTypography.native(size: 12, weight: .medium)
        if symbol == "eyedropper", let artwork = PipetteArtwork.image.copy() as? NSImage {
            artwork.size = NSSize(width: 19, height: 19)
            control.image = artwork
        } else {
            control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        control.imagePosition = .imageLeading
        control.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        control.toolTip = "\(title) · \(shortcut)"
        control.setAccessibilityLabel(title)
        control.isEnabled = !store.isSampling && !store.isExtracting && !store.readOnly
        control.heightAnchor.constraint(equalToConstant: 30).isActive = true
        item.label = title
        item.view = control
        item.autovalidates = false
        item.visibilityPriority = .high
        utilityButtons[id] = control
        return item
    }
    @objc private func changeDestination() {
        store.search = ""
        if destinations.selectedSegment == 1 { store.showCaptures() }
        else {
            if case .collection(let id) = lastColorFilter, !store.library.collections.contains(where: { $0.id == id }) { lastColorFilter = .all }
            store.filter = lastColorFilter
        }
        window?.makeFirstResponder(nil)
    }
    @objc private func pickColor() { pick() }
    @objc private func capturePalette() { capture() }
    @objc private func importImage() { store.importImage() }
    @objc private func showCompact() { compact() }
}

/// A single AppKit safe-area boundary prevents the window and SwiftUI's root
/// scroll view from both applying the titlebar inset to the inspector.
@MainActor
private final class InspectorHost: NSViewController {
    private let content: NSHostingView<InspectorContainer>
    init(store: ColorStore) {
        content = NSHostingView(rootView: InspectorContainer(store: store))
        content.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:)") }
    override func loadView() {
        view = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }
}

private extension NSToolbarItem.Identifier {
    static let colorDestinations = Self("ColorDestinations")
    static let colorPick = Self("ColorPick")
    static let colorCapture = Self("ColorCapture")
    static let colorImport = Self("ColorImport")
    static let colorSearch = Self("ColorSearch")
    static let colorCompact = Self("ColorCompact")
}
