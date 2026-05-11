import XCTest
@testable import VPNCore

final class VPNCoreTests: XCTestCase {
    func test_versionMatches() {
        XCTAssertEqual(VPNCore.version, "0.1.0")
    }
}
