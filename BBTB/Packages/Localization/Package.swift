// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Localization",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Localization", targets: ["Localization"])],
    targets: [
        .target(
            name: "Localization",
            resources: [
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
    ]
)
