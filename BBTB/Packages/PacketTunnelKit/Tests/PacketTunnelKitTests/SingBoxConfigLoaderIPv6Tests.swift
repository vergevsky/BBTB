import XCTest
@testable import PacketTunnelKit

/// Phase 6 / Wave 2 — IPv6 blackhole в sing-box TUN inbound (NET-05, NET-06, D-06).
///
/// Парный тест к `TunnelSettingsIPv6Tests`. NEIPv6Settings (OS routing layer) и
/// `SingBoxConfigLoader.expandConfigForTunnel` (engine layer) ДОЛЖНЫ работать
/// синхронно — иначе v6 пакеты либо обходят TUN (если только OS-сторона),
/// либо попадают в TUN но идут через `direct` outbound на физический интерфейс
/// (если только sing-box-сторона). Канон — 06-RESEARCH.md §2 + §15.
///
/// **Использует unified 1.13 syntax** (`address`, `route_address`) — НЕ
/// deprecated `inet6_address` / `inet6_route_address` (sing-box 1.10 deprecation).
final class SingBoxConfigLoaderIPv6Tests: XCTestCase {

    // MARK: Helpers

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    /// Минимальный input — sing-box JSON без inbounds (expand добавит TUN).
    /// outbounds: один proxy outbound (vless) + direct, чтобы post-expand validate() прошёл.
    private let minimalNoInboundJSON: String = """
    {
      "log": {},
      "outbounds": [
        {"type": "vless", "tag": "vless-out", "server": "1.2.3.4", "server_port": 443, "uuid": "550e8400-e29b-41d4-a716-446655440000"},
        {"type": "direct", "tag": "direct"}
      ],
      "route": {"final": "vless-out", "rules": []},
      "experimental": {}
    }
    """

    // MARK: 1. TUN inbound address включает IPv6 ULA prefix

    func test_SingBoxConfigLoader_ipv6_address_added() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: minimalNoInboundJSON,
            mtu: 1420,
            tunIP: "198.18.0.1"
        )
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.count, 1, "expand добавляет ровно один TUN inbound")
        let address = inbounds[0]["address"] as? [String]
        XCTAssertNotNil(address)
        XCTAssertTrue(address?.contains("198.18.0.1/28") ?? false,
                      "IPv4 prefix сохранён (Phase 1 поведение)")
        XCTAssertTrue(address?.contains("fd00::1/126") ?? false,
                      "Phase 6 — IPv6 ULA fd00::1/126 добавлен для захвата v6 трафика внутри TUN")
    }

    // MARK: 2. route_address: ["::/0"] — blackhole inside sing-box

    func test_SingBoxConfigLoader_ipv6_route_address_blackhole() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: minimalNoInboundJSON,
            mtu: 1420
        )
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds[0]["route_address"] as? [String], ["::/0"],
                       "Phase 6 — sing-box `route_address: [\"::/0\"]` гарантирует что v6 destination не утечёт через direct outbound")
    }

    // MARK: 3. auto_route remains false (R10 invariant)

    func test_SingBoxConfigLoader_ipv6_auto_route_stays_false() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: minimalNoInboundJSON)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds[0]["auto_route"] as? Bool, false,
                       "R10 — auto_route=false (gvisor manual stack)")
    }

    // MARK: 4. stack stays gvisor

    func test_SingBoxConfigLoader_ipv6_stack_stays_gvisor() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: minimalNoInboundJSON)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds[0]["stack"] as? String, "gvisor")
    }

    // MARK: 5. mtu preserved

    func test_SingBoxConfigLoader_ipv6_mtu_preserved() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: minimalNoInboundJSON,
            mtu: 1420
        )
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds[0]["mtu"] as? Int, 1420)
    }

    // MARK: 6. Idempotency — если TUN уже есть, expand НЕ добавляет второй

    func test_SingBoxConfigLoader_ipv6_idempotent_whenTunAlreadyPresent() throws {
        // Input уже имеет TUN inbound (без IPv6). Expand должен оставить как есть
        // (hasTun guard) — мы не "upgrade'им" существующий TUN, мы только добавляем
        // если нет. Это сохраняет R10 idempotency invariant Phase 1.
        let inputWithTun: String = """
        {
          "log": {},
          "inbounds": [{"type": "tun", "tag": "tun-existing", "address": ["198.18.0.1/28"], "mtu": 1420, "auto_route": false, "stack": "gvisor"}],
          "outbounds": [{"type": "vless", "tag": "vless-out", "server": "1.2.3.4", "server_port": 443, "uuid": "550e8400-e29b-41d4-a716-446655440000"}, {"type": "direct", "tag": "direct"}],
          "route": {"final": "vless-out", "rules": []},
          "experimental": {}
        }
        """
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: inputWithTun)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.count, 1, "hasTun guard — не дублировать TUN inbound")
        XCTAssertEqual(inbounds[0]["tag"] as? String, "tun-existing",
                       "существующий TUN inbound оставлен без изменений (Phase 1 idempotency invariant)")
    }

    // MARK: 7. R10 — post-expand validate() остаётся PASS

    func test_SingBoxConfigLoader_validate_post_expand() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: minimalNoInboundJSON)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded),
                         "R10 — post-expand validate() должен пройти (никаких новых inbound types, allow-list `tun`+`direct` не нарушен)")
    }

    // MARK: 8. Никакого deprecated inet6_address / inet6_route_address

    func test_SingBoxConfigLoader_ipv6_noDeprecatedKeys() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: minimalNoInboundJSON)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertNil(inbounds[0]["inet6_address"],
                     "06-RESEARCH §2 — `inet6_address` deprecated в sing-box 1.10; используем unified `address` array")
        XCTAssertNil(inbounds[0]["inet6_route_address"],
                     "06-RESEARCH §2 — `inet6_route_address` deprecated; используем unified `route_address` array")
    }
}
