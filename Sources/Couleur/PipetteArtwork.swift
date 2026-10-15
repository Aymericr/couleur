import AppKit
import SwiftUI

/// The app's opalescent glass material, distilled into its everyday tool.
enum PipetteArtwork {
    static let image: NSImage = {
        if let url = Bundle.main.url(forResource: "Pipette", withExtension: "png"),
           let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "eyedropper", accessibilityDescription: nil) ?? NSImage()
    }()
}

struct PipetteIcon: View {
    var body: some View {
        Image(nsImage: PipetteArtwork.image)
            .resizable().interpolation(.high).scaledToFit()
            .accessibilityHidden(true)
    }
}
