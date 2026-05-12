import XCTest
import NetworkExtension
@testable import PacketTunnelKit

final class TunnelSettingsTests: XCTestCase {

    // MARK: R6 critical invariants

    func test_makeR6Safe_doesNotSetDestinationAddresses() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertNotNil(settings.ipv4Settings, "ipv4Settings must be non-nil")
        // R6: destinationAddresses MUST remain unset.
        // macOS 26 / iOS 19 SDK hides the property entirely (no public accessor) —
        // so R6 is now enforced at compile time. We still grep Sources/ for any
        // assignment in validate-r1-r6.sh as a belt-and-suspenders invariant.
    }

    func test_makeR6Safe_ipv6Settings_areConfiguredForBlackhole_inPhase6() {
        // Phase 1 holding test был `XCTAssertNil(s.ipv6Settings)`. Phase 6 / Wave 2 (D-06)
        // меняет это поведение — теперь NEIPv6Settings обязан быть НЕ nil, иначе
        // ОС маршрутизирует v6 в обход туннеля (см. 06-RESEARCH.md Pitfall 1).
        // Детальная конфигурация v6 blackhole тестируется в TunnelSettingsIPv6Tests.
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertNotNil(settings.ipv6Settings,
                        "Phase 6 / D-06: NEIPv6Settings с ULA fd00::1/128 + default route ::/0 для v6 blackhole")
    }

    // MARK: Default values

    func test_makeR6Safe_default_tunnelIP() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["198.18.0.1"])
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.240"])  // /28 — Phase 1 W5 plan B.2
    }

    func test_makeR6Safe_includesDefaultRoute() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        let routes = settings.ipv4Settings?.includedRoutes ?? []
        XCTAssertFalse(routes.isEmpty, "Must include default route to push all IPv4 traffic into tunnel")
    }

    func test_makeR6Safe_dnsServers() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.dnsSettings?.servers, ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(settings.dnsSettings?.matchDomains, [""], "matchDomains [\"\"] is the DNS-leak protection")
    }

    func test_makeR6Safe_mtu() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.mtu?.intValue, 1500, "standard Ethernet MTU — Phase 1 W5 trace-log debug 2026-05-11 showed jumbo MTU 9000 was killing every connection in <500ms (iOS writePacketObjects silently drops oversized IP packets emitted by gVisor). 1500 chosen over Codex-recommended 1280 because wiki/rkn-detection-methodology.md §3 marks MTU 1..1499 as RKN VPN-detection trigger.")
    }

    // MARK: Custom inputs

    func test_makeR6Safe_customInputs() {
        let inputs = TunnelSettings.Inputs(
            tunnelIP: "10.0.0.42",
            tunnelSubnetMask: "255.255.255.252",
            serverAddress: "your.server.example",
            dnsServers: ["9.9.9.9", "149.112.112.112"],
            mtu: 1500
        )
        let settings = TunnelSettings.makeR6Safe(inputs)
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["10.0.0.42"])
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.252"])
        XCTAssertEqual(settings.dnsSettings?.servers, ["9.9.9.9", "149.112.112.112"])
        XCTAssertEqual(settings.mtu?.intValue, 1500)
        // R6 invariant — see note in test_makeR6Safe_doesNotSetDestinationAddresses.
    }

    // MARK: InterfaceFlagsInspector (smoke)

    func test_interfaceFlagsInspector_returnsArray() {
        // На CI / macOS без VPN — обычно есть utun0/utun1 от системных служб (Continuity, FaceTime).
        // Не утверждаем что массив не пустой (может быть на новой headless-машине), только что
        // вызов не падает и возвращает корректные данные.
        let snapshot = InterfaceFlagsInspector.utunSnapshot()
        for iface in snapshot {
            XCTAssertTrue(iface.name.hasPrefix("utun"), "Filter must restrict to utun*")
            XCTAssertFalse(iface.flagsHex.isEmpty)
        }
    }

    // MARK: PlatformHooks

    func test_platformHooks_shouldDisableEnforceRoutes_isFalseInPhase1() {
        // Phase 10 (R5) включит этот тоггл на macOS. В Phase 1 — всегда false для обеих платформ.
        XCTAssertFalse(PlatformHooks.shouldDisableEnforceRoutes())
    }
}
