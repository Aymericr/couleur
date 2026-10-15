import AppKit

/// LaunchServices owns the replacement process. Its AppKit run loop starts
/// immediately, but it waits for this instance to exit before opening the library.
@MainActor
enum AppRelaunch {
    static func perform(captureAfterSetup: Bool = false) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--relaunch-after", String(ProcessInfo.processInfo.processIdentifier), "--capture-help"]
        if captureAfterSetup { configuration.arguments.append("--capture-after-setup") }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--data-directory"), arguments.indices.contains(index + 1) {
            configuration.arguments += ["--data-directory", arguments[index + 1]]
        }

        let replacement = try await NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)

        // terminate() returns when quitting was canceled. Do not leave a second
        // instance waiting, or silently leave the user in a half-finished restart.
        replacement.terminate()
        throw RelaunchError.quitCanceled
    }

    static func waitForPreviousInstance() async -> Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--relaunch-after"),
              arguments.indices.contains(index + 1),
              let pid = Int32(arguments[index + 1]),
              let previous = NSRunningApplication(processIdentifier: pid),
              previous.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        else { return true }

        // Keep AppKit responsive so LaunchServices can finish its launch request
        // and the old instance can quit. Never block main() waiting for that quit.
        let deadline = ContinuousClock.now + .seconds(15)
        while !previous.isTerminated {
            guard ContinuousClock.now < deadline, !Task.isCancelled else {
                previous.activate()
                return false
            }
            do { try await Task.sleep(for: .milliseconds(50)) }
            catch { return false }
        }
        return true
    }

    private enum RelaunchError: LocalizedError {
        case quitCanceled
        var errorDescription: String? {
            "The app could not quit. Close any open dialogs, then try again."
        }
    }
}
