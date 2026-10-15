import AppKit
import OSLog

/// Local Instruments intervals. Never records colors, app names, titles, or URLs.
/// First draw measures AppKit drawing, not the display's physical presentation.
@MainActor
final class PickPerformance {
    private static let log = Logger(subsystem: "com.aymeric.couleur", category: "Picking")
    private static let signposter = OSSignposter(logger: log)
    private let id = signposter.makeSignpostID()
    private let started = ContinuousClock.now
    private let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
    private var session: OSSignpostIntervalState?
    private var presentation: OSSignpostIntervalState?

    init() {
        session = Self.signposter.beginInterval("PickSession", id: id)
        presentation = Self.signposter.beginInterval("PickToLoupeDraw", id: id)
    }

    func loupeDrawn() {
        guard let presentation else { return }
        Self.signposter.endInterval("PickToLoupeDraw", presentation)
        self.presentation = nil
        report("loupe_draw", since: started)
    }

    func nativeSamplerRequested() {
        endPresentation()
        Self.signposter.emitEvent("NativeSamplerRequested", id: id)
    }

    func measure<T>(_ name: StaticString, _ operation: () throws -> T) rethrows -> T {
        let interval = Self.signposter.beginInterval(name, id: id)
        let start = ContinuousClock.now
        defer {
            Self.signposter.endInterval(name, interval)
            report(name, since: start)
        }
        return try operation()
    }

    func finish() {
        guard let session else { return }
        endPresentation()
        Self.signposter.endInterval("PickSession", session)
        self.session = nil
        // Session length includes time spent choosing; it is not response latency.
        let unchanged = foregroundPID == NSWorkspace.shared.frontmostApplication?.processIdentifier
        Self.log.info("pick_finished foreground_unchanged=\(unchanged) app_active=\(NSApp?.isActive ?? false)")
    }

    private func endPresentation() {
        guard let presentation else { return }
        Self.signposter.endInterval("PickToLoupeDraw", presentation, "ended before drawing")
        self.presentation = nil
    }

    private func report(_ phase: StaticString, since start: ContinuousClock.Instant) {
        let elapsed = start.duration(to: .now).components
        let ms = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
        Self.log.info("pick_phase=\(phase.description, privacy: .public) elapsed_ms=\(ms) app_active=\(NSApp?.isActive ?? false)")
    }
}
