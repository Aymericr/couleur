import AppKit
import Combine
import SwiftUI

/// Two destinations, one canvas, and an optional inspector.
@MainActor
final class LibraryController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuDelegate {
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
    private var addItem: NSToolbarItem?
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
        addItem?.isEnabled = !store.isSampling && !store.isExtracting && !store.readOnly
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        if store.filter == .capture { store.filter = .captures }
        store.search = field.stringValue
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.colorDestinations, .flexibleSpace, .colorSearch, .colorAdd, .colorCompact]
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
        case .colorAdd:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Add"
            item.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add a color or image")
            item.toolTip = "Add a color or image"
            item.autovalidates = false
            let menu = NSMenu()
            menu.delegate = self
            menu.autoenablesItems = false
            for (title, symbol, action) in [("Pick color", "eyedropper", #selector(pickColor)),
                                          ("Capture area", "viewfinder", #selector(capturePalette)),
                                          ("Open image…", "photo", #selector(importImage))] {
                let option = NSMenuItem(title: title, action: action, keyEquivalent: "")
                option.target = self
                option.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
                menu.addItem(option)
            }
            item.menu = menu
            addItem = item
            return item
        case .colorSearch:
            searchItem.label = "Search Colors"
            searchItem.searchField.placeholderString = "Search colors"
            searchItem.searchField.delegate = self
            searchItem.searchField.sendsSearchStringImmediately = true
            searchItem.preferredWidthForSearchField = 180
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

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            item.isEnabled = !store.isSampling && !store.isExtracting && !store.readOnly
        }
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
    static let colorAdd = Self("ColorAdd")
    static let colorSearch = Self("ColorSearch")
    static let colorCompact = Self("ColorCompact")
}
