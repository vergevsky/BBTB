// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "KillSwitch",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "KillSwitch", targets: ["KillSwitch"])],
    targets: [
        .target(name: "KillSwitch"),
        .testTarget(name: "KillSwitchTests", dependencies: ["KillSwitch"]),
    ]
)
