import XCTest
import NetworkExtension
@testable import KillSwitch

final class KillSwitchTests: XCTestCase {

    // MARK: enabled=true (KILL-01 default — Phase 1 carry-forward)

    func test_apply_enabled_setsIncludeAllNetworks() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: true)
        XCTAssertTrue(proto.includeAllNetworks, "KILL-01: includeAllNetworks must be true when enabled")
    }

    func test_apply_enabled_setsEnforceRoutes_inPhase1() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: true)
        // R4 default — enforceRoutes=true в Phase 1 (Phase 10 даст macOS-toggle).
        XCTAssertTrue(proto.enforceRoutes, "R4 default: enforceRoutes must be true when enabled (Phase 1)")
    }

    func test_apply_disconnectOnSleep_isFalse() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: true)
        XCTAssertFalse(proto.disconnectOnSleep, "KILL-02: tunnel must persist across sleep")
    }

    func test_apply_excludeLocalNetworks_isFalse() {
        let proto = NETunnelProviderProtocol()
        proto.excludeLocalNetworks = true  // simulate alien code setting it
        KillSwitch.apply(to: proto, enabled: true)
        XCTAssertFalse(proto.excludeLocalNetworks,
                       "Maximum lockdown: excludeLocalNetworks must be false")
    }

    func test_apply_isIdempotent() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: true)
        let snapshot = (
            proto.includeAllNetworks,
            proto.enforceRoutes,
            proto.disconnectOnSleep,
            proto.excludeLocalNetworks
        )
        KillSwitch.apply(to: proto, enabled: true)
        XCTAssertEqual(snapshot.0, proto.includeAllNetworks)
        XCTAssertEqual(snapshot.1, proto.enforceRoutes)
        XCTAssertEqual(snapshot.2, proto.disconnectOnSleep)
        XCTAssertEqual(snapshot.3, proto.excludeLocalNetworks)
    }

    // MARK: enabled=false (KILL-03 — Phase 2)

    func test_apply_disabled_clearsIncludeAllNetworks() {
        let proto = NETunnelProviderProtocol()
        proto.includeAllNetworks = true  // pre-set to simulate stale state
        KillSwitch.apply(to: proto, enabled: false)
        XCTAssertFalse(proto.includeAllNetworks,
                       "KILL-03: includeAllNetworks must be false when kill switch disabled")
    }

    func test_apply_disabled_clearsEnforceRoutes() {
        let proto = NETunnelProviderProtocol()
        proto.enforceRoutes = true  // pre-set to simulate stale state
        KillSwitch.apply(to: proto, enabled: false)
        XCTAssertFalse(proto.enforceRoutes,
                       "KILL-03: enforceRoutes must be false when kill switch disabled")
    }

    func test_apply_disabled_preservesR4Defaults() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: false)
        // R4 defaults should still apply regardless of kill switch state.
        XCTAssertFalse(proto.excludeLocalNetworks, "R4: excludeLocalNetworks must remain false")
        XCTAssertFalse(proto.disconnectOnSleep, "R4: disconnectOnSleep must remain false")
    }
}
