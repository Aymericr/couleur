// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Couleur",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Couleur", targets: ["Couleur"])],
    dependencies: [
        .package(
            url: "https://github.com/sparkle-project/Sparkle",
            exact: "2.10.0"
        )
    ],
    targets: [
        .target(name: "CouleurCore"),
        .executableTarget(name: "Couleur", dependencies: ["CouleurCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "CouleurCoreTests", dependencies: ["CouleurCore"]),
        .testTarget(name: "CouleurTests", dependencies: ["Couleur", "CouleurCore"])
    ]
)
