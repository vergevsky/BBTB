import XCTest
import NetworkExtension
@testable import PacketTunnelKit

/// Phase 6 / Wave 2 — IPv6 blackhole tests (NET-05, NET-06, D-06).
///
/// Закрывает Phase 1 TODO в `TunnelSettings.makeR6Safe`: `settings.ipv6Settings = nil`,
/// который оставлял v6 leak. Канон — 06-RESEARCH.md §1 и §15, Pitfall 1.
///
/// **Конструкция blackhole:**
/// 1. NEIPv6Settings с ULA `fd00::1/128` (RFC 4193) + includedRoutes=[NEIPv6Route.default()]
///    → ОС маршрутизирует ВСЕ v6 destinations в TUN.
/// 2. R6 invariant — `destinationAddresses` НИКОГДА не выставляется (IFF_POINTOPOINT).
/// 3. Внутри TUN sing-box не имеет v6 outbound → пакеты dropпаются.
final class TunnelSettingsIPv6Tests: XCTestCase {

    // MARK: Fixture

    private func makeInputs() -> TunnelSettings.Inputs {
        TunnelSettings.Inputs(
            tunnelIP: "198.18.0.2",
            tunnelSubnetMask: "255.255.255.240",
            serverAddress: "1.2.3.4",
            dnsServers: ["1.1.1.1"],
            mtu: 1420
        )
    }

    // MARK: 1. NEIPv6Settings non-nil (Pitfall 1 invariant)

    func test_TunnelSettings_ipv6_isNotNil() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertNotNil(settings.ipv6Settings,
                        "Phase 6 / D-06 — NEIPv6Settings должен быть НЕ nil чтобы ОС захватила v6 трафик в туннель (см. 06-RESEARCH.md Pitfall 1)")
    }

    // MARK: 2. NEIPv6Settings.addresses

    func test_TunnelSettings_ipv6_addresses_useULA() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertEqual(settings.ipv6Settings?.addresses, ["fd00::1"],
                       "ULA prefix fd00::/8 (RFC 4193) для tunnel-local v6 адреса")
    }

    // MARK: 3. NEIPv6Settings.networkPrefixLengths

    func test_TunnelSettings_ipv6_prefixLengths_are128() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertEqual(settings.ipv6Settings?.networkPrefixLengths, [NSNumber(value: 128)],
                       "/128 — single tunnel-local addr на стороне NE (sing-box получит /126 на своей стороне)")
    }

    // MARK: 4. includedRoutes — default route catches ::/0

    func test_TunnelSettings_ipv6_blackholeRoute_present() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        let routes = settings.ipv6Settings?.includedRoutes ?? []
        XCTAssertEqual(routes.count, 1,
                       "Один маршрут — NEIPv6Route.default() (::/0) — захватывает весь v6 трафик")
    }

    func test_TunnelSettings_ipv6_blackholeRoute_isDefault() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        let route = settings.ipv6Settings?.includedRoutes?.first
        XCTAssertEqual(route?.destinationAddress, "::",
                       "NEIPv6Route.default() имеет destinationAddress = ::")
        XCTAssertEqual(route?.destinationNetworkPrefixLength, 0,
                       "NEIPv6Route.default() имеет prefix = 0 (::/0)")
    }

    // MARK: 5. R6 invariant on v6 — destinationAddresses MUST stay unset

    func test_TunnelSettings_ipv6_noDestinationAddresses() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertNotNil(settings.ipv6Settings, "v6 settings exist")
        // R6 invariant: NEIPv6Settings.destinationAddresses MUST remain unset
        // (создаст IFF_POINTOPOINT на utun*).
        // macOS 26 / iOS 19 SDK скрывает property полностью (как и для NEIPv4Settings) —
        // R6 теперь enforced at compile time. grep по Sources/ в
        // validate-r1-r6.sh — belt-and-suspenders.
    }

    // MARK: 6. excludedRoutes — explicit empty array

    func test_TunnelSettings_ipv6_excludedRoutes_explicitEmpty() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertEqual(settings.ipv6Settings?.excludedRoutes?.count, 0,
                       "excludedRoutes — explicit empty array, не nil (06-RESEARCH §1)")
    }

    // MARK: 7. IPv4 unchanged (regression guard)

    func test_TunnelSettings_ipv4_unchanged() {
        let settings = TunnelSettings.makeR6Safe(makeInputs())
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["198.18.0.2"],
                       "Phase 1 IPv4 поведение сохранено")
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.240"])
        let routes = settings.ipv4Settings?.includedRoutes ?? []
        XCTAssertFalse(routes.isEmpty, "default IPv4 route остаётся")
    }

    // MARK: 8. Convenience overload preserves IPv6 blackhole

    func test_TunnelSettings_convenienceOverload_emitsIPv6Blackhole() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "1.2.3.4")
        XCTAssertNotNil(settings.ipv6Settings,
                        "makeR6Safe(serverAddress:) делегирует в полную форму — v6 blackhole присутствует")
        XCTAssertEqual(settings.ipv6Settings?.addresses, ["fd00::1"])
        XCTAssertEqual(settings.ipv6Settings?.networkPrefixLengths, [NSNumber(value: 128)])
        XCTAssertEqual(settings.ipv6Settings?.includedRoutes?.count, 1)
        // destinationAddresses — compile-time enforced; см.
        // test_TunnelSettings_ipv6_noDestinationAddresses
    }
}
