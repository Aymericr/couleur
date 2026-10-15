import AppKit
import CouleurCore
import Testing
@testable import Couleur

@Test @MainActor func nativeSamplerDiscardsAColorDeliveredAfterCancellation() async {
    var reply: ((NSColor?) -> Void)?
    let sampler = NativeColorSampler { reply = $0 }
    let pick = Task { await sampler.sample() }
    while reply == nil { await Task.yield() }
    pick.cancel()
    reply?(NSColor(srgbRed: 0.8, green: 0.4, blue: 0.2, alpha: 1))
    #expect(await pick.value == nil)
}

@Test @MainActor func nativeSamplerReturnsTheExactSRGBValueOrCancellation() async {
    let color = NSColor(srgbRed: 0.8, green: 0.4, blue: 0.2, alpha: 1)
    let sampler = NativeColorSampler { $0(color) }
    #expect(await sampler.sample() == ColorValue(red: 0.8, green: 0.4, blue: 0.2))
    let dismissed = NativeColorSampler { $0(nil) }
    #expect(await dismissed.sample() == nil)
}

@Test @MainActor func cancellingLoupeBeforePreparationFinishesCannotSaveAColor() async throws {
    let performance = PickPerformance()
    defer { performance.finish() }
    let loupe = ScreenLoupe(performance: performance)
    loupe.prepare(initiatedByPress: true)
    loupe.cancel()
    loupe.cancel()
    var selections = 0
    try await loupe.run { _, _ in selections += 1 }
    #expect(loupe.isFinished)
    #expect(selections == 0)
}
