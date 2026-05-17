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

    // MARK: - Phase 10 / KILL-04 — macOS enforceRoutes toggle

    #if os(macOS)
    /// macOS-only: KillSwitch.apply(to:enabled:true) при macOSDisableEnforceRoutes=true
    /// должен устанавливать enforceRoutes=false (пользователь выключил принудительную маршрутизацию).
    func test_apply_respects_macOS_disable_enforceRoutes_toggle() {
        let suiteKey = "app.bbtb.macOSDisableEnforceRoutes"
        let suiteName = "group.app.bbtb.shared"
        // Cleanup before test
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: suiteKey)

        // Case 1: macOSDisableEnforceRoutes=true → enforceRoutes должен быть false
        UserDefaults(suiteName: suiteName)?.set(true, forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
        let proto1 = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto1, enabled: true)
        XCTAssertFalse(proto1.enforceRoutes,
                       "macOSDisableEnforceRoutes=true → enforceRoutes должен быть false")

        // Case 2: macOSDisableEnforceRoutes=false → enforceRoutes должен быть true
        UserDefaults(suiteName: suiteName)?.set(false, forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
        let proto2 = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto2, enabled: true)
        XCTAssertTrue(proto2.enforceRoutes,
                      "macOSDisableEnforceRoutes=false → enforceRoutes должен быть true")

        // Cleanup after test
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
    }
    #endif

    /// **Plan 09 A6-KS-3-001 (CodeRabbit PR #18 review fix):** value-pin test
    /// для `appGroupSuiteName`. Must match `AppGroupContainer.identifier`
    /// ("group.app.bbtb.shared"). PacketTunnelKit has a matching pin test —
    /// if either drifts independently, one of the two fails.
    ///
    /// Long-term fix (deferred): extract shared constant к VPNCore or new
    /// CommonAppConfig package. Tracked в wiki «v1.1+ TODO».
    func test_A6_KS_3_001_appGroupSuiteName_pinned() {
        XCTAssertEqual(
            KillSwitch.appGroupSuiteName,
            "group.app.bbtb.shared",
            "KillSwitch.appGroupSuiteName MUST match PacketTunnelKit.AppGroupContainer.identifier — " +
            "drift would silently break extension/main-app UserDefaults exchange."
        )
    }

    #if os(iOS)
    /// iOS-only: platformShouldDisableEnforceRoutes() возвращает false независимо от
    /// значения в UserDefaults (iOS не должен читать этот ключ).
    func test_apply_iOS_ignores_disable_toggle() {
        let suiteKey = "app.bbtb.macOSDisableEnforceRoutes"
        let suiteName = "group.app.bbtb.shared"
        // Записать true в suite — iOS должен игнорировать
        UserDefaults(suiteName: suiteName)?.set(true, forKey: suiteKey)
        UserDefaults(suiteName: suiteName)?.synchronize()
        defer {
            UserDefaults(suiteName: suiteName)?.removeObject(forKey: suiteKey)
            UserDefaults(suiteName: suiteName)?.synchronize()
        }

        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto, enabled: true)
        // iOS не должен читать macOSDisableEnforceRoutes → enforceRoutes=true (R4 default)
        XCTAssertTrue(proto.enforceRoutes,
                      "iOS: macOSDisableEnforceRoutes не влияет на enforceRoutes (iOS ignores toggle)")
    }
    #endif
}
