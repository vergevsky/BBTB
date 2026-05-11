// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeatures",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
        .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
    ],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(path: "../ConfigParser"),
        .package(path: "../KillSwitch"),
        .package(path: "../Protocols/VLESSReality"),
    ],
    targets: [
        .target(
            name: "MainScreenFeature",
            dependencies: [
                "VPNCore", "DesignSystem", "Localization",
                "ConfigParser", "KillSwitch", "VLESSReality",
            ]
        ),
        .target(
            name: "MenuBarFeature",
            dependencies: ["MainScreenFeature", "Localization", "VPNCore"]
        ),
        .testTarget(name: "MainScreenFeatureTests", dependencies: ["MainScreenFeature"]),
    ]
)
