import AppKit
import SwiftUI

/// Explain the permission before asking for it, and recognize a successful grant
/// when the user returns from Settings. A capture error is not a permission denial.
struct CaptureAccessView: View {
    @ObservedObject var capture: RegionCapture

    private var ready: Bool { capture.accessGranted && capture.captureFailure == nil }
    private var title: String {
        if ready { return "Ready to pick and capture" }
        if capture.accessGranted { return "Let’s try that capture again" }
        return "A palette from anywhere"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                    .resizable().frame(width: 48, height: 48)
                Spacer()
                Button { capture.helpPresented = false } label: {
                    Image(systemName: "xmark").font(.geist(size: 10, weight: .medium))
                        .foregroundStyle(.secondary).frame(width: 24, height: 24)
                }.buttonStyle(QuietButtonStyle()).accessibilityLabel("Close capture setup")
                    .keyboardShortcut(.cancelAction)
            }.padding(.bottom, 22)
            Text(title).font(.geist(size: 23, weight: .semibold)).tracking(-0.5).padding(.bottom, 10)
            Text(description).font(.geist(size: 13)).foregroundStyle(.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true).padding(.bottom, 24)

            if capture.accessGranted {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.geist(size: 18))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Screen access is enabled").font(.geist(size: 12, weight: .medium))
                        Text(ready ? "Drag to select an area. Esc cancels." : "Your permission is already set correctly.")
                            .font(.geist(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 17) {
                    step(1, "Open screen access settings", detail: "Privacy & Security → \(settingsName)")
                    step(2, "Enable \(capture.appName)", detail: "Use this exact app name in the list.")
                    step(3, "Come back here", detail: "We’ll check access when you return.")
                }
            }

            if capture.requestedAccess && !capture.accessGranted {
                VStack(alignment: .leading, spacing: 7) {
                    Text(capture.checkedAfterSettings ? "Switch already on?" : "If macOS asks you to reopen")
                        .font(.geist(size: 12, weight: .medium))
                    Text("Reopen \(capture.appName) to apply the change. Your saved colors are safe.")
                        .font(.geist(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                    Button("Quit & Reopen \(capture.appName)") { capture.relaunch() }
                        .buttonStyle(.link).font(.geist(size: 11))
                    if capture.checkedAfterSettings {
                        DisclosureGroup("Access still not detected?") {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("macOS may still list an older copy. Remove that entry with the minus button, then use the plus button to add this copy of \(capture.appName).")
                                    .font(.geist(size: 11)).foregroundStyle(.secondary).lineSpacing(3)
                                Button("Show This App in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                                }.buttonStyle(.link).font(.geist(size: 11))
                            }.padding(.top, 7)
                        }.font(.geist(size: 11)).foregroundStyle(.secondary).padding(.top, 4)
                    }
                }.padding(.top, 22)
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

            Text("Only the area you choose. Processed on this Mac. No audio is recorded.")
                .font(.geist(size: 10)).foregroundStyle(.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 24)
            Divider().padding(.vertical, 18)
            HStack {
                if !capture.accessGranted && capture.requestedAccess {
                    Button("Check Again") { capture.checkAccess(explicit: true) }.controlSize(.large)
                } else {
                    Button("Not Now") { capture.helpPresented = false }.controlSize(.large)
                }
                Spacer()
                Button(primaryTitle) {
                    if capture.accessGranted { capture.continueCapture() }
                    else if capture.requestedAccess { capture.openSettings() }
                    else { capture.requestAccess() }
                }.buttonStyle(.borderedProminent).controlSize(.large).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 430)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                capture.checkAccess()
            }
    }

    private var description: String {
        if ready { return "Pick exact screen pixels with the loupe, or choose an area to find its dominant colors and explore every shade." }
        if capture.accessGranted { return "macOS couldn’t return that image. Try selecting the area again. If you just enabled access, reopen the app first." }
        return "Screen access enables the fine pixel loupe and palettes from any area you select. Allow \(capture.appName) in System Settings to get started."
    }
    private var primaryTitle: String {
        if capture.accessGranted { return ready ? "Capture an Area" : "Try Again" }
        return capture.requestedAccess ? "Open System Settings" : "Enable Screen Capture"
    }
    private var settingsName: String {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 ? "Screen & System Audio Recording" : "Screen Recording"
    }
    private func step(_ number: Int, _ title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.geist(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                .frame(width: 22, height: 22).background(.primary.opacity(0.055), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.geist(size: 12, weight: .medium))
                Text(detail).font(.geist(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
