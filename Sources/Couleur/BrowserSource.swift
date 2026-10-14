import AppKit
import CouleurCore

/// Apple Events read only the selected window's current tab. No browser history,
/// page scripts, Accessibility access, or clipboard interaction is involved.
enum BrowserSource {
    private static let queue = DispatchQueue(label: "com.aymeric.couleur.browser-source", qos: .utility)
    private static let chromium: Set<String> = ["com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
                                              "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser", "com.vivaldi.Vivaldi"]
    private static let safari: Set<String> = ["com.apple.Safari", "com.apple.SafariTechnologyPreview"]

    static func supports(_ identifier: String?) -> Bool {
        identifier.map { chromium.contains($0) || safari.contains($0) } ?? false
    }

    static func website(for window: SourceWindow) async -> String? {
        guard let identifier = window.bundleIdentifier, supports(identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                let result: String? = autoreleasepool {
                    guard let script = NSAppleScript(source: script(for: window)) else { return nil }
                    var error: NSDictionary?
                    let rows = script.executeAndReturnError(&error)
                    guard error == nil, rows.numberOfItems > 0 else { return nil }
                    for index in 1...rows.numberOfItems {
                        guard let row = rows.atIndex(index), row.numberOfItems == 3,
                              let bounds = row.atIndex(1), bounds.numberOfItems == 4,
                              let title = row.atIndex(2)?.stringValue,
                              let text = row.atIndex(3)?.stringValue else { continue }
                        let rect = (1...4).compactMap { bounds.atIndex($0)?.doubleValue }
                        guard window.matches(bounds: rect, title: title) else { continue }
                        return SavedCapture.webURL(text)?.absoluteString
                    }
                    return nil
                }
                continuation.resume(returning: result)
            }
        }
    }

    static func script(for window: SourceWindow) -> String {
        guard let identifier = window.bundleIdentifier, supports(identifier) else { return "return {}" }
        let bounds = [window.bounds.minX, window.bounds.minY, window.bounds.maxX, window.bounds.maxY].map { Int($0.rounded()) }
        let match = bounds.enumerated().map { index, value in
            "(item \(index + 1) of b ≥ \(value - 2) and item \(index + 1) of b ≤ \(value + 2))"
        }.joined(separator: " and ")
        let tab = safari.contains(identifier) ? "current tab" : "active tab"
        let privateGuard = chromium.contains(identifier) ? "if mode of w is \"incognito\" then return {}" : ""
        // Only allowlisted identifiers and numeric bounds enter the script.
        // The returned title is checked again before attaching a URL, so a tab
        // changed after the screenshot cannot silently become its source.
        return """
        if application id "\(identifier)" is not running then return {}
        with timeout of 3 seconds
            tell application id "\(identifier)"
                set matches to {}
                repeat with w in windows
                    try
                        set b to bounds of w
                        if \(match) then
                            \(privateGuard)
                            set end of matches to {b, (name of w) as text, (URL of \(tab) of w) as text}
                        end if
                    end try
                end repeat
                return matches
            end tell
        end timeout
        """
    }
}
