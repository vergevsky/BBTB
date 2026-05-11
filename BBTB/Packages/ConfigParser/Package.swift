// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ConfigParser",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "ConfigParser", targets: ["ConfigParser"])],
    dependencies: [.package(path: "../VPNCore")],
    targets: [
        .target(name: "ConfigParser", dependencies: ["VPNCore"]),
        .testTarget(name: "ConfigParserTests", dependencies: ["ConfigParser"]),
    ]
)
