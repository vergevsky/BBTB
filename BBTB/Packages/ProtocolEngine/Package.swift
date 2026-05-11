// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProtocolEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SingBoxBridge", targets: ["SingBoxBridge"]),
        .library(name: "XrayFallback", targets: ["XrayFallback"]),
    ],
    targets: [
        // Vendored gomobile binding для sing-box 1.13.11.
        // Бинарь положен в Wave 3 (W3-T1 checkpoint). См. BBTB/Vendored/README.md.
        .binaryTarget(
            name: "Libbox",
            path: "../../Vendored/libbox.xcframework"
        ),
        .target(
            name: "SingBoxBridge",
            dependencies: ["Libbox"]
        ),
        .target(
            name: "XrayFallback"  // CORE-09 — Phase 4+, placeholder в Phase 1
        ),
    ]
)
