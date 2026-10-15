import AppKit
import Combine
import SwiftUI

/// A small setup window keeps the permission flow independent of the library.
/// Dismiss before picking or relaunching, so neither action runs behind a sheet.
@MainActor
final class CaptureSetupController: NSWindowController, NSWindowDelegate {
    private let capture: RegionCapture
    private var observation: AnyCancellable?
    private var presented = false
    var beforeShow: (() -> Void)?
    var afterDismiss: (() -> Void)?

    init(capture: RegionCapture) {
        self.capture = capture
        let host = NSHostingController(rootView: CaptureAccessView(capture: capture))
        host.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: host)
        window.title = "Screen access"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        super.init(window: window)
        window.delegate = self
        observation = capture.$helpPresented.removeDuplicates().sink { [weak self] visible in
            self?.present(visible)
        }
    }

    required init?(coder: NSCoder) { fatalError("Use init(capture:)") }

    private func present(_ visible: Bool) {
        guard visible != presented else { return }
        presented = visible
        if visible {
            beforeShow?()
            window?.center()
            NSApp.activate(ignoringOtherApps: true)
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderOut(nil)
            // Combine publishes before the property's setter finishes. Wait
            // until helpPresented is false before the picker checks that gate.
            Task { @MainActor [weak self] in
                self?.afterDismiss?()
                self?.capture.helpDidDismiss()
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        capture.helpPresented = false
        return false
    }
}
