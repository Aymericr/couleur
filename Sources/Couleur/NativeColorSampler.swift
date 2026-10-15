import AppKit
import CouleurCore

@MainActor
final class NativeColorSampler {
    private let show: (@escaping (NSColor?) -> Void) -> Void

    init() {
        let sampler = NSColorSampler()
        show = { sampler.show(selectionHandler: $0) }
    }

    init(show: @escaping (@escaping (NSColor?) -> Void) -> Void) { self.show = show }

    func sample() async -> ColorValue? {
        guard !Task.isCancelled else { return nil }
        // Bridge older AppKit SDKs on the main actor and send only an sRGB value
        // across the continuation. AppKit has no public dismissal API; a callback
        // arriving after cancellation must not become a saved or copied color.
        let value: ColorValue? = await withCheckedContinuation { continuation in
            show { continuation.resume(returning: $0.flatMap { ColorValue($0) }) }
        }
        return Task.isCancelled ? nil : value
    }
}
