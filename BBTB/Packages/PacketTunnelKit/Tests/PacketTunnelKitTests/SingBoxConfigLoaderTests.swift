import XCTest
@testable import PacketTunnelKit

final class SingBoxConfigLoaderTests: XCTestCase {

    // MARK: Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).json")
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Valid

    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_templateLoadsAndValidates_afterPlaceholderReplacement() throws {
        // R1 self-check: bundled template (с ${...} placeholder'ами) после простой подстановки
        // на непустые строки должен пройти validate. Это гарантирует что Wave 4 при импорте vless://
        // получит на выходе R1-compliant конфиг.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
    }

    // MARK: R1 — forbidden inbounds (SEC-01)

    func test_rejectsSocksInbound() throws {
        let json = try loadFixture("invalid-socks-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }

    func test_rejectsMixedInbound() throws {
        let json = try loadFixture("invalid-mixed-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("mixed"))
        }
    }

    // MARK: R1 white-list (W3.1) — tun/direct allowed; everything else rejected (default-deny)

    func test_allowsTunInbound() throws {
        let json = try loadFixture("valid-tun-inbound")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_allowsDirectInbound() throws {
        let json = """
        {"inbounds":[{"type":"direct","tag":"d"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_rejectsUnknownInboundType_defaultDeny() throws {
        // Hypothetical future sing-box inbound type that we never reviewed.
        // White-list R1 must reject it without changes to the validator.
        let json = """
        {"inbounds":[{"type":"hypothetical-future-listen-on-localhost","tag":"x"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(
                err as? SingBoxConfigError,
                .forbiddenInboundType("hypothetical-future-listen-on-localhost")
            )
        }
    }

    func test_rejectsInboundWithoutType() throws {
        // Defensive: inbound entry without a "type" key — should still default-deny.
        let json = """
        {"inbounds":[{"tag":"no-type-here"}],"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("<unknown>"))
        }
    }

    func test_rejectsHttpInbound() throws {
        let json = try loadFixture("invalid-http-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("http"))
        }
    }

    // MARK: R1 — experimental APIs (SEC-02)

    func test_rejectsClashAPI() throws {
        let json = try loadFixture("invalid-clash-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("clash_api"))
        }
    }

    func test_rejectsV2RayAPI() throws {
        let json = try loadFixture("invalid-v2ray-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("v2ray_api"))
        }
    }

    func test_rejectsCacheFile() throws {
        let json = try loadFixture("invalid-cache-file")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("cache_file"))
        }
    }

    // MARK: SEC-06 — structure validation

    func test_malformedJSON() throws {
        let json = try loadFixture("malformed")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .malformedJSON)
        }
    }

    func test_noVLESSOutbound() throws {
        let json = try loadFixture("no-vless-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noVLESSOutbound)
        }
    }

    func test_missingOutbounds() throws {
        let json = "{\"outbounds\": [], \"route\": { \"final\": \"x\" }, \"experimental\": {}}"
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .missingOutbounds)
        }
    }

    // MARK: expandConfigForTunnel (W3.1)

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    func test_expandConfigForTunnel_addsTunInbound() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let inbounds = root["inbounds"] as! [[String: Any]]
        XCTAssertEqual(inbounds.count, 1)
        XCTAssertEqual(inbounds[0]["type"] as? String, "tun")
        XCTAssertEqual(inbounds[0]["tag"] as? String, "tun-in")
        XCTAssertEqual(inbounds[0]["auto_route"] as? Bool, false)
        XCTAssertEqual(inbounds[0]["stack"] as? String, "system")
        XCTAssertEqual(inbounds[0]["mtu"] as? Int, 1400)
        XCTAssertEqual(inbounds[0]["address"] as? [String], ["198.18.0.1/30"])
        // sing-box 1.13 removed `sniff` from inbound — must NOT be present.
        XCTAssertNil(inbounds[0]["sniff"], "sniff field is legacy (removed in sing-box 1.13); use route.rules action:sniff instead")
    }

    func test_expandConfigForTunnel_rewritesLegacyDnsOutbound() throws {
        let json = try loadFixture("legacy-dns-outbound")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)

        // dns outbound удалён
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertFalse(outbounds.contains { ($0["type"] as? String) == "dns" })
        XCTAssertEqual(outbounds.count, 2)

        // route.rules[0]: action=hijack-dns, outbound удалён
        let route = root["route"] as! [String: Any]
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertEqual(rules[0]["action"] as? String, "hijack-dns")
        XCTAssertNil(rules[0]["outbound"])
        XCTAssertEqual(rules[0]["protocol"] as? String, "dns")
        // rules[1] (domain_suffix → direct) — нетронуто
        XCTAssertEqual(rules[1]["outbound"] as? String, "direct")
        XCTAssertNil(rules[1]["action"])
    }

    func test_expandConfigForTunnel_isIdempotent() throws {
        let json = try loadFixture("valid-vless-reality")
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first)

        let r1 = try parse(first)
        let r2 = try parse(second)
        let in1 = r1["inbounds"] as! [[String: Any]]
        let in2 = r2["inbounds"] as! [[String: Any]]
        XCTAssertEqual(in1.count, 1)
        XCTAssertEqual(in2.count, 1, "повторный expand не должен дублировать TUN inbound")
        XCTAssertEqual(in1[0]["tag"] as? String, in2[0]["tag"] as? String)
    }

    func test_expandConfigForTunnel_preservesOtherFields() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)

        // dns block нетронут
        XCTAssertNotNil(root["dns"])
        // outbounds: vless-out + direct остались
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertTrue(outbounds.contains { ($0["type"] as? String) == "vless" })
        XCTAssertTrue(outbounds.contains { ($0["type"] as? String) == "direct" })
        // experimental существует (пустой объект OK)
        XCTAssertNotNil(root["experimental"])
    }

    func test_expandConfigForTunnel_outputPassesValidate_fromLegacyInput() throws {
        // Defense-in-depth: чтобы expand не мог сам добавить что-то запрещённое
        // (регрессия) — на любом валидном входе его output должен проходить validate
        // повторно. Это то самое post-expand re-validation что делает BaseSingBoxTunnel.
        let json = try loadFixture("legacy-dns-outbound")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    func test_expandConfigForTunnel_outputPassesValidate_fromCleanInput() throws {
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    func test_expandConfigForTunnel_acceptsTemplate_afterPlaceholderReplacement() throws {
        // Sanity: bundled template после фейкового fill — после expand тоже валиден.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: filled)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }
}
