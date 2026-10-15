import AppKit
import SwiftUI

/// Explain access once, then turn the granted state into the next useful action.
struct CaptureAccessView: View {
    @ObservedObject var capture: RegionCapture

    private var ready: Bool { capture.accessGranted && capture.captureFailure == nil }
    private var title: String {
        if ready { return "You’re ready." }
        return capture.accessGranted ? "Let’s try that again." : "Colors from anywhere."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 48, height: 48)
                Text("Couleur").font(.geist(size: 15, weight: .medium)).foregroundStyle(.secondary)
            }.padding(.bottom, 22)
            Text(title).font(.geist(size: 25, weight: .medium)).tracking(-0.7).padding(.bottom, 10)
            Text(description).font(.geist(size: 13)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)

            if capture.accessGranted {
                Label("Screen access is enabled", systemImage: "checkmark.circle.fill")
                    .font(.geist(size: 12, weight: .medium)).foregroundStyle(.green)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 17) {
                    step(1, "Open System Settings", detail: "Privacy & Security → \(settingsName)")
                    step(2, "Turn on \(capture.appName)", detail: "Then come back here. We’ll check automatically.")
                }
                if capture.requestedAccess {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Already turned it on? macOS may need a quick restart of the app.")
                            .font(.geist(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                        Button("Quit & Reopen \(capture.appName)") { capture.relaunch() }
                            .buttonStyle(.link).font(.geist(size: 11))
                        if capture.checkedAfterSettings {
                            DisclosureGroup("Still not working?") {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Remove any older Couleur entry with the minus button, then add this copy with the plus button.")
                                        .font(.geist(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                                    Button("Show Couleur in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                    }.buttonStyle(.link).font(.geist(size: 11))
                                }.padding(.top, 7)
                            }.font(.geist(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                        }
                    }.padding(.top, 22)
                }
            }
            if let failure = capture.relaunchFailure {
                Text(failure).font(.geist(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
            }
            if let failure = capture.captureFailure {
                DisclosureGroup("Capture details") {
                    Text(failure).font(.geist(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }.font(.geist(size: 11)).foregroundStyle(.secondary).padding(.top, 18)
                if capture.accessGranted {
                    Button("Quit & Reopen \(capture.appName)") { capture.relaunch() }
                        .buttonStyle(.link).font(.geist(size: 11)).padding(.top, 10)
                }
            }
            Text("Screen pixels only. No audio. Everything stays on your Mac.")
                .font(.geist(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 24)
            HStack {
                Button(ready ? "Done" : "Not now") { capture.helpPresented = false }
                    .controlSize(.large).keyboardShortcut(.cancelAction)
                Spacer()
                Button(primaryTitle) {
                    if capture.accessGranted { capture.continueAfterSetup() }
                    else if capture.requestedAccess { capture.openSettings() }
                    else { capture.requestAccess() }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }.padding(.top, 22)
        }.padding(28).frame(width: 420)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                capture.checkAccess(explicit: capture.requestedAccess)
            }
    }

    private var description: String {
        if ready { return capture.accessPurpose == .capture ? "Select an area and discover its palette." : "Pick any pixel. We’ll copy the color and keep it in your history." }
        if capture.accessGranted { return "macOS couldn’t return that image. Try again, or reopen Couleur if you just enabled access." }
        return "Allow screen access to pick colors and capture palettes from anything on your screen."
    }
    private var primaryTitle: String {
        if capture.accessGranted {
            if !ready { return "Try again" }
            return capture.accessPurpose == .capture ? "Capture an area" : "Pick a color"
        }
        return capture.requestedAccess ? "Open System Settings" : "Allow screen access"
    }
    private var settingsName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 ? "Screen & System Audio Recording" : "Screen Recording"
    }
    private func step(_ number: Int, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.geist(size: 10, weight: .medium)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).background(.primary.opacity(0.055), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.geist(size: 12, weight: .medium))
                Text(detail).font(.geist(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
