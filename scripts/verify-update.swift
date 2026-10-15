import Foundation
import CryptoKit

final class Feed: NSObject, XMLParserDelegate {
    var enclosures: [[String: String]] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "enclosure" { enclosures.append(attributes) }
    }
}
do {
    guard CommandLine.arguments.count == 4 else { throw CocoaError(.fileReadInvalidFileName) }
    let infoData = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
    let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as! [String: Any]
    let archiveURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let bytes = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
    let parser = XMLParser(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[3])))
    let feed = Feed(); parser.delegate = feed
    guard parser.parse(), feed.enclosures.count == 1, let enclosure = feed.enclosures.first,
          let keyText = info["SUPublicEDKey"] as? String, let keyData = Data(base64Encoded: keyText),
          let signatureText = enclosure["sparkle:edSignature"], let signature = Data(base64Encoded: signatureText),
          Int(enclosure["length"] ?? "") == bytes.count,
          let version = info["CFBundleShortVersionString"] as? String,
          enclosure["url"] == "https://github.com/Aymericr/couleur/releases/download/v\(version)/\(archiveURL.lastPathComponent)"
    else { throw CocoaError(.fileReadCorruptFile) }
    let key = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard key.isValidSignature(signature, for: bytes) else { throw CocoaError(.fileReadCorruptFile) }
    print("Sparkle archive signature, length and download URL verified against the app's public key.")
} catch {
    fputs("Update verification failed. Do not publish these artifacts.\n", stderr)
    exit(1)
}
