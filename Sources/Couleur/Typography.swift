import AppKit
import CoreText
import SwiftUI

/// Bundled, process-scoped fonts; nothing is installed into the user's font library.
enum AppTypography {
    static let faces = ["Geist-Regular", "Geist-Medium", "Geist-SemiBold", "Geist-Bold",
                        "GeistMono-Regular", "GeistMono-Medium", "GeistMono-SemiBold", "GeistPixel-Square"]

    @MainActor static func registerBundledFonts() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts") else { return }
        let failures = registerFonts(in: directory)
        if !failures.isEmpty { NSLog("Could not register bundled fonts: %@", failures.joined(separator: ", ")) }
    }

    @MainActor @discardableResult static func registerFonts(in directory: URL) -> [String] {
        faces.filter { face in
            let url = directory.appendingPathComponent(face).appendingPathExtension("ttf")
            guard FileManager.default.fileExists(atPath: url.path) else { return true }
            var error: Unmanaged<CFError>?
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return false }
            // Tests or previews may already have registered this face in their process.
            return error.map { CFErrorGetCode($0.takeRetainedValue()) != CTFontManagerError.alreadyRegistered.rawValue } ?? true
        }
    }

    static func face(weight: Font.Weight, monospaced: Bool) -> String {
        let family = monospaced ? "GeistMono" : "Geist"
        if weight == .bold || weight == .heavy || weight == .black { return monospaced ? "GeistMono-SemiBold" : "Geist-Bold" }
        if weight == .semibold { return "\(family)-SemiBold" }
        if weight == .medium { return "\(family)-Medium" }
        return "\(family)-Regular"
    }

    @MainActor static func native(size: CGFloat, weight: Font.Weight = .regular, monospaced: Bool = false) -> NSFont {
        NSFont(name: face(weight: weight, monospaced: monospaced), size: size) ?? .systemFont(ofSize: size)
    }
}

extension Font {
    static func geist(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .custom(AppTypography.face(weight: weight, monospaced: design == .monospaced), fixedSize: size)
    }
    static func geistPixel(size: CGFloat) -> Font { .custom("GeistPixel-Square", fixedSize: size) }
}
