import Foundation

/// Every successful action gets its own identity, including copying the same
/// color twice. Presentation can wait until a hidden picker is visible again.
struct ColorFeedback: Identifiable, Equatable {
    enum Origin { case copy, pick }
    let id = UUID()
    let colorID: UUID
    let origin: Origin
    let copied: Bool
}
