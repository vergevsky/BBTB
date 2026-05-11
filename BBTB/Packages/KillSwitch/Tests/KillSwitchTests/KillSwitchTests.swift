import XCTest
import NetworkExtension
@testable import KillSwitch

final class KillSwitchTests: XCTestCase {

    func test_apply_setsIncludeAllNetworks() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        XCTAssertTrue(proto.includeAllNetworks, "KILL-01: includeAllNetworks must be true")
    }

    func test_apply_setsEnforceRoutes_inPhase1() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        // R4 default — enforceRoutes=true в Phase 1 (Phase 10 даст macOS-toggle).
        XCTAssertTrue(proto.enforceRoutes, "R4 default: enforceRoutes must be true in Phase 1")
    }

    func test_apply_disconnectOnSleep_isFalse() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        XCTAssertFalse(proto.disconnectOnSleep, "KILL-02: tunnel must persist across sleep")
    }

    func test_apply_excludeLocalNetworks_isFalse() {
        let proto = NETunnelProviderProtocol()
        proto.excludeLocalNetworks = true  // simulate alien code setting it
        KillSwitch.apply(to: proto)
        XCTAssertFalse(proto.excludeLocalNetworks,
                       "Maximum lockdown: excludeLocalNetworks must be false")
    }

    func test_apply_isIdempotent() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        let snapshot = (
            proto.includeAllNetworks,
            proto.enforceRoutes,
            proto.disconnectOnSleep,
            proto.excludeLocalNetworks
        )
        KillSwitch.apply(to: proto)
        XCTAssertEqual(snapshot.0, proto.includeAllNetworks)
        XCTAssertEqual(snapshot.1, proto.enforceRoutes)
        XCTAssertEqual(snapshot.2, proto.disconnectOnSleep)
        XCTAssertEqual(snapshot.3, proto.excludeLocalNetworks)
    }
}
