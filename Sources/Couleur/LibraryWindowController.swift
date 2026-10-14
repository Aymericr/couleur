import AppKit
import Combine
import SwiftUI

/// AppKit owns window chrome, toolbar search, split resizing, and sidebar materials.
@MainActor
final class LibraryWindowController: NSWindowController, NSToolbarDelegate, NSSearchFieldDelegate, NSMenuDelegate {
    private let store: ColorStore
    private let pick: () -> Void
    private let compact: () -> Void
    private let split = NSSplitViewController()
    private var inspector: NSSplitViewItem!
    private var observations: Set<AnyCancellable> = []
    private let searchItem = NSSearchToolbarItem(itemIdentifier: .colorSearch)
    private var pickItem: NSToolbarItem?

    init(store: ColorStore, pick: @escaping () -> Void, compact: @escaping () -> Void) {
        self.store = store; self.pick = pick; self.compact = compact
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "All Colors"
        window.minSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none

        let sidebar = NSSplitViewItem(sidebarWithViewController: NSHostingController(rootView: LibrarySidebar(store: store)))
        sidebar.minimumThickness = 175
        sidebar.maximumThickness = 240
        sidebar.preferredThicknessFraction = 0.19
        sidebar.canCollapseFromWindowResize = false
        let content = NSSplitViewItem(viewController: NSHostingController(rootView: LibraryView(store: store, pick: pick)))
        content.minimumThickness = 300
        content.holdingPriority = .defaultLow
        inspector = NSSplitViewItem(inspectorWithViewController: InspectorHost(store: store))
        inspector.minimumThickness = 260
        inspector.maximumThickness = 300
        inspector.preferredThicknessFraction = 0.26
        split.splitView.isVertical = true
        split.splitView.dividerStyle = .thin
        split.addSplitViewItem(sidebar)
        split.addSplitViewItem(content)
        split.addSplitViewItem(inspector)
        window.contentViewController = split

        let toolbar = NSToolbar(identifier: "CouleurLibraryToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        window.center()
        window.setFrameAutosaveName("CouleurLibrary")

        store.objectWillChange.sink { [weak self] in
            // Published sends before the mutation; refresh chrome after the values settle.
            Task { @MainActor [weak self] in self?.refreshChrome() }
        }.store(in: &observations)
        refreshChrome()
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:pick:compact:)") }

    func focusSearch() {
        searchItem.beginSearchInteraction()
        searchItem.searchField.selectText(nil)
    }

    private func refreshChrome() {
        window?.title = store.filter == .all ? "All Colors" : store.filterTitle
        if searchItem.searchField.stringValue != store.search { searchItem.searchField.stringValue = store.search }
        pickItem?.isEnabled = !store.isSampling && !store.readOnly
    }

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        store.search = field.stringValue
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .colorSidebarSeparator, .flexibleSpace, .colorPick, .colorSort, .colorSearch, .colorCompact, .colorInspectorSeparator, .colorInspector]
    }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case .colorSidebarSeparator:
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split.splitView, dividerIndex: 0)
        case .colorInspectorSeparator:
            return NSTrackingSeparatorToolbarItem(identifier: id, splitView: split.splitView, dividerIndex: 1)
        case .toggleSidebar:
            return button(id, "Toggle Sidebar", symbol: "sidebar.left", action: #selector(toggleSidebar))
        case .colorPick:
            let item = button(id, "Pick Color", symbol: "eyedropper", action: #selector(pickColor))
            item.toolTip = "Pick from screen · ⌃⌥C"
            pickItem = item
            return item
        case .colorCompact:
            let item = button(id, "Compact Picker", symbol: "arrow.down.right.and.arrow.up.left", action: #selector(showCompact))
            item.toolTip = "Return to compact picker · ⌘2"
            return item
        case .colorInspector:
            return button(id, "Toggle Inspector", symbol: "sidebar.right", action: #selector(toggleInspector))
        case .colorSort:
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "Sort Colors"
            item.image = NSImage(systemSymbolName: "arrow.up.arrow.down", accessibilityDescription: "Sort colors")
            item.toolTip = "Sort colors"
            let menu = NSMenu()
            menu.delegate = self
            for sort in LibrarySort.allCases {
                let option = NSMenuItem(title: sort.rawValue, action: #selector(changeSort(_:)), keyEquivalent: "")
                option.target = self; option.representedObject = sort.rawValue
                menu.addItem(option)
            }
            item.menu = menu
            return item
        case .colorSearch:
            searchItem.label = "Search Colors"
            searchItem.searchField.placeholderString = "Search colors"
            searchItem.searchField.delegate = self
            searchItem.searchField.sendsSearchStringImmediately = true
            searchItem.preferredWidthForSearchField = 200
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
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items { item.state = item.representedObject as? String == store.sort.rawValue ? .on : .off }
    }
    @objc private func changeSort(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let sort = LibrarySort(rawValue: raw) { store.sort = sort }
    }
    @objc private func pickColor() { pick() }
    @objc private func showCompact() { compact() }
    @objc private func toggleSidebar() { toggle(split.splitViewItems[0]) }
    @objc private func toggleInspector() { toggle(inspector) }
    private func toggle(_ item: NSSplitViewItem) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { item.isCollapsed.toggle() }
        else { item.animator().isCollapsed = !item.isCollapsed }
    }
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
    static let colorSidebarSeparator = Self("ColorSidebarSeparator")
    static let colorInspectorSeparator = Self("ColorInspectorSeparator")
    static let colorPick = Self("ColorPick")
    static let colorSort = Self("ColorSort")
    static let colorSearch = Self("ColorSearch")
    static let colorCompact = Self("ColorCompact")
    static let colorInspector = Self("ColorInspector")
}
