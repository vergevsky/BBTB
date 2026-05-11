// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "VPNCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "VPNCore", targets: ["VPNCore"])],
    targets: [
        .target(name: "VPNCore"),
        .testTarget(name: "VPNCoreTests", dependencies: ["VPNCore"]),
    ]
)
