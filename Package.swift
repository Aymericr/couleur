// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Couleur",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Couleur", targets: ["Couleur"])],
    targets: [
        .target(name: "CouleurCore"),
        .executableTarget(name: "Couleur", dependencies: ["CouleurCore"]),
        .testTarget(name: "CouleurCoreTests", dependencies: ["CouleurCore"]),
        .testTarget(name: "CouleurTests", dependencies: ["Couleur", "CouleurCore"])
    ]
)
