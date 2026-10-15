import AppKit
import CoreText
import Foundation
import Testing
@testable import Couleur

@Test @MainActor func bundledGeistFontsRegisterUnderTheirRealNames() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let directory = root.appendingPathComponent("Resources/Fonts")
    #expect(AppTypography.registerFonts(in: directory).isEmpty)
    for name in AppTypography.faces {
        let font = try #require(NSFont(name: name, size: 13))
        #expect(font.fontName == name)
        let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromURL(directory.appendingPathComponent(name + ".ttf") as CFURL) as? [CTFontDescriptor])
        #expect(descriptors.contains { CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String == name })
    }
    let mono = AppTypography.native(size: 19, monospaced: true)
    #expect(mono.fontName == "GeistMono-Regular")
    let digits = NSAttributedString(string: "111111", attributes: [.font: mono]).size().width
    let letters = NSAttributedString(string: "FFFFFF", attributes: [.font: mono]).size().width
    #expect(abs(digits - letters) < 0.01)
}
