import XCTest
@testable import VPNCore

/// Plan 09 LOW-batch-2: deleted tautological `test_versionMatches` (checked
/// literal "0.1.0" === literal "0.1.0"). VPNCore.version был removed as stale
/// (project at v0.13). Marketing version sourced from Info.plist.
///
/// Tests for VPNCore namespace types are в targeted ParsedConfigsTests,
/// TransportConfigTests, ServerConfigTests, etc.
final class VPNCoreTests: XCTestCase {
    /// Smoke test — VPNCore namespace still compiles.
    func test_namespace_compiles() {
        _ = VPNCore.self
    }
}
