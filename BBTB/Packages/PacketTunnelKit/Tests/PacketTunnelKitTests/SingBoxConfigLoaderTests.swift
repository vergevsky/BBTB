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
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
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

    func test_noProxyOutbound() throws {
        let json = try loadFixture("no-vless-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noProxyOutbound)
        }
    }

    // MARK: Phase 2 W0.T4 — relaxed validator (RESEARCH §7)

    func test_acceptsTrojanOnlyConfig() throws {
        let json = try loadFixture("valid-trojan-only")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_acceptsPoolWithVlessTrojanUrltest() throws {
        let json = try loadFixture("valid-pool-vless-trojan")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_rejectsConfigWithoutProxyOutbound() throws {
        let json = try loadFixture("invalid-no-proxy-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noProxyOutbound)
        }
    }

    func test_rejectsUrltestWithUnresolvedOutboundRef() throws {
        let json = try loadFixture("invalid-urltest-unresolved-ref")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            guard case let .unresolvedOutboundRef(ref, group) = (err as? SingBoxConfigError) else {
                XCTFail("Expected .unresolvedOutboundRef, got \(err)")
                return
            }
            XCTAssertEqual(ref, "nonexistent-tag")
            XCTAssertEqual(group, "urltest")
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
        XCTAssertEqual(inbounds[0]["stack"] as? String, "gvisor")
        XCTAssertEqual(inbounds[0]["mtu"] as? Int, 1500)
        // Phase 1 (W5 plan B.2): /28 для IPv4.
        // Phase 6 / Wave 2 (D-06): ULA fd00::1/126 для IPv6 blackhole + route_address ["::/0"].
        // Детальные v6 проверки — SingBoxConfigLoaderIPv6Tests.
        XCTAssertEqual(inbounds[0]["address"] as? [String], ["198.18.0.1/28", "fd00::1/126"])
        XCTAssertEqual(inbounds[0]["route_address"] as? [String], ["::/0"])
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

        // route.rules[0] = action:"sniff" (W3.2 injection, см.
        // test_expandConfigForTunnel_injectsSniffAsFirstRule).
        let route = root["route"] as! [String: Any]
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertEqual(rules[0]["action"] as? String, "sniff")
        // Изначальные rules сдвинулись на +1.
        // rules[1]: action=hijack-dns, outbound удалён
        XCTAssertEqual(rules[1]["action"] as? String, "hijack-dns")
        XCTAssertNil(rules[1]["outbound"])
        XCTAssertEqual(rules[1]["protocol"] as? String, "dns")
        // Phase 8 W5: 3 priority rules inserted после hijack-dns (idx 2-4).
        // Legacy rule (domain_suffix → direct) теперь матчится по содержимому, не по index.
        let legacyDirectRule = rules.first {
            ($0["outbound"] as? String) == "direct"
            && ($0["rule_set"] as? String) == nil
        }
        XCTAssertNotNil(legacyDirectRule, "domain_suffix → direct rule должно сохраниться")
        XCTAssertNil(legacyDirectRule?["action"])
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

    // MARK: expandConfigForTunnel — sniff injection (Phase 1 W3.2 DNS fix)

    func test_expandConfigForTunnel_injectsSniffAsFirstRule() throws {
        // sing-box 1.13: `protocol:dns` matcher не работает без предварительного sniff.
        // Корневая причина device debug 2026-05-11 — DNS UDP падал с "UDP not supported".
        // Sniff coexistence с hijack-dns проверяется в test_rewritesLegacyDnsOutbound.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let route = root["route"] as! [String: Any]
        let rules = route["rules"] as! [[String: Any]]
        XCTAssertFalse(rules.isEmpty, "route.rules должны существовать после expand")
        XCTAssertEqual(
            rules[0]["action"] as? String, "sniff",
            "sniff action должен быть ПЕРВЫМ правилом — иначе protocol:dns matcher не сработает"
        )
    }

    func test_expandConfigForTunnel_sniffInjectionIsIdempotent() throws {
        let json = try loadFixture("valid-vless-reality")
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first)
        let r2 = try parse(second)
        let rules = (r2["route"] as! [String: Any])["rules"] as! [[String: Any]]
        let sniffCount = rules.filter { ($0["action"] as? String) == "sniff" }.count
        XCTAssertEqual(sniffCount, 1, "повторный expand не должен дублировать sniff action")
    }

    func test_expandConfigForTunnel_sniffAddedEvenWhenNoExistingRules() throws {
        // Конфиг без route.rules вообще — sniff должен появиться.
        let noRulesConfig = """
        {"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
        """
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: noRulesConfig)
        let root = try parse(expanded)
        let rules = (root["route"] as! [String: Any])["rules"] as! [[String: Any]]
        XCTAssertEqual(rules[0]["action"] as? String, "sniff")
    }

    // MARK: expandConfigForTunnel — log injection (Phase 1 device debug)

    /// Минимальный валидный JSON без log-блока — для изоляции log injection поведения
    /// от того, что несёт fixture `valid-vless-reality.json` (которая ставит log.level=info).
    private let noLogConfig = """
    {"outbounds":[{"type":"vless","tag":"v","server":"x","server_port":443,"uuid":"u"}],"route":{"final":"v"},"experimental":{}}
    """

    func test_expandConfigForTunnel_omitsLog_whenLogPathNil_andNoExistingLog() throws {
        // Production-сборки вызывают expand без logPath → log секция не добавляется,
        // если её не было во входе.
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: noLogConfig)
        let root = try parse(expanded)
        XCTAssertNil(root["log"], "без logPath и без существующего log-блока — не инжектить")
    }

    func test_expandConfigForTunnel_preservesExistingLog_whenLogPathNil() throws {
        // Существующий log-блок (например, из bundled template) не должен изменяться,
        // если logPath не передан.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: json)
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertEqual(log?["level"] as? String, "info")
        XCTAssertNil(log?["output"], "без logPath диагностический output не добавляем")
    }

    func test_expandConfigForTunnel_injectsLog_whenLogPathProvided() throws {
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: noLogConfig,
            logPath: "/tmp/sing-box.log"
        )
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertNotNil(log)
        XCTAssertEqual(log?["output"] as? String, "/tmp/sing-box.log")
        XCTAssertEqual(log?["level"] as? String, "debug")
        XCTAssertEqual(log?["timestamp"] as? Bool, true)
        XCTAssertEqual(log?["disabled"] as? Bool, false)
    }

    func test_expandConfigForTunnel_logInjectionIsIdempotent() throws {
        let first = try SingBoxConfigLoader.expandConfigForTunnel(json: noLogConfig, logPath: "/tmp/a.log")
        let second = try SingBoxConfigLoader.expandConfigForTunnel(json: first, logPath: "/tmp/a.log")
        let r2 = try parse(second)
        let log = r2["log"] as? [String: Any]
        XCTAssertEqual(log?["output"] as? String, "/tmp/a.log")
        XCTAssertEqual(log?["level"] as? String, "debug")
    }

    func test_expandConfigForTunnel_customLogLevel_propagates() throws {
        // Phase 1 W5 device debug (опция Б): callee может задать кастомный logLevel,
        // например "trace" для Vision flow event diff. Default остаётся "debug".
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: noLogConfig,
            logPath: "/tmp/sing-box.log",
            logLevel: "trace"
        )
        let root = try parse(expanded)
        let log = root["log"] as? [String: Any]
        XCTAssertEqual(log?["level"] as? String, "trace")
        XCTAssertEqual(log?["output"] as? String, "/tmp/sing-box.log")
    }

    func test_expandConfigForTunnel_logOutputPassesValidate() throws {
        // log секция не должна влиять на R1/SEC-06 validate.
        let json = try loadFixture("valid-vless-reality")
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(
            json: json,
            logPath: "/tmp/sing-box.log"
        )
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    func test_expandConfigForTunnel_acceptsTemplate_afterPlaceholderReplacement() throws {
        // Sanity: bundled template после фейкового fill — после expand тоже валиден.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: filled)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded))
    }

    // MARK: - Phase 8 W5 (D-01) — rule_set injection tests (RULES-05/06/07 + R10/R1)

    /// Заполняет `${...}` placeholders bundled template'а на валидные значения —
    /// shared helper для всех Phase 8 W5 тестов.
    private func loadFilledTemplate() throws -> String {
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        return template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${VLESS_FLOW}", with: "xtls-rprx-vision")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
            .replacingOccurrences(of: "${DNS_DETOUR}", with: "vless-out")
    }

    /// RULES-05/06/07: 3 `route.rule_set` declarations injected с правильными метаданными
    /// (`type:"local"`, `format:"binary"`, path под App Group `Library/Caches/rules/<tag>.srs`).
    func test_expandConfigForTunnel_injectsThreeRuleSetEntries() throws {
        let baseTemplate = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: baseTemplate)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let ruleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        let tags = ruleSets.compactMap { $0["tag"] as? String }
        XCTAssertEqual(Set(tags), Set(["bbtb-block", "bbtb-never", "bbtb-always"]),
                       "Should inject exactly 3 rule_set declarations")
        for rs in ruleSets {
            XCTAssertEqual(rs["type"] as? String, "local",
                           "rule_set type must be 'local' (sing-box reads from filesystem)")
            XCTAssertEqual(rs["format"] as? String, "binary",
                           "rule_set format must be 'binary' (.srs compiled format)")
            let path = try XCTUnwrap(rs["path"] as? String)
            XCTAssertTrue(path.contains("Library/Caches/rules/"),
                          "Expected App Group rules cache path, got \(path)")
            XCTAssertTrue(path.hasSuffix(".srs"),
                          "rule_set path must end with .srs (compiled rule-set), got \(path)")
        }
    }

    /// RULES-06: priority order block → never → always (sing-box matches first hit
    /// top-down → block доминирует, never override'ит always для same domain).
    func test_expandConfigForTunnel_priorityOrderIsBlockThenNeverThenAlways() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        // Extract just our 3 rule_set references in their order.
        let phase8 = rules.compactMap { $0["rule_set"] as? String }
        XCTAssertEqual(phase8, ["bbtb-block", "bbtb-never", "bbtb-always"],
                       "Phase 8 priority order must be block > never > always (top-down sing-box matching)")

        // block uses action:reject (drops traffic outright)
        let blockRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-block" })
        XCTAssertEqual(blockRule["action"] as? String, "reject")
        XCTAssertNil(blockRule["outbound"], "block rule must NOT have outbound (action:reject only)")

        // never uses outbound:direct (bypass VPN)
        let neverRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-never" })
        XCTAssertEqual(neverRule["outbound"] as? String, "direct")
        XCTAssertNil(neverRule["action"], "never rule must NOT have action")

        // always uses non-direct proxy outbound (forces through VPN)
        let alwaysRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-always" })
        let alwaysOutbound = try XCTUnwrap(alwaysRule["outbound"] as? String)
        XCTAssertNotEqual(alwaysOutbound, "direct",
                          "always category MUST route через VPN, not direct")
        XCTAssertNotEqual(alwaysOutbound, "block")
    }

    /// RULES-07 / firstProxyTag reuse: `always` outbound matches существующий proxy outbound
    /// tag (urltest/selector/vless/trojan — same set как `route.final` fallback в lines 218-225).
    func test_expandConfigForTunnel_alwaysCategoryUsesValidProxyTag() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(expanded.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])
        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let alwaysRule = try XCTUnwrap(rules.first { ($0["rule_set"] as? String) == "bbtb-always" })
        let alwaysOutbound = try XCTUnwrap(alwaysRule["outbound"] as? String)
        // Resolved firstProxyTag must match один из existing proxy outbound tags.
        let outbounds = try XCTUnwrap(parsed["outbounds"] as? [[String: Any]])
        let proxyTags = outbounds.compactMap { o -> String? in
            guard let type = o["type"] as? String,
                  ["vless", "trojan", "shadowsocks", "vmess", "hysteria2", "wireguard", "tuic",
                   "urltest", "selector"].contains(type) else { return nil }
            return o["tag"] as? String
        }
        XCTAssertTrue(proxyTags.contains(alwaysOutbound),
                      "always outbound '\(alwaysOutbound)' should match один из proxy outbound tags \(proxyTags)")
    }

    /// Idempotency: повторный вызов `expandConfigForTunnel` НЕ дублирует rule_set
    /// declarations или priority rules (existing tag / rule_set ref filter).
    func test_expandConfigForTunnel_rulesetInjectionIsIdempotent() throws {
        let template = try loadFilledTemplate()
        let firstExpand = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        let secondExpand = try SingBoxConfigLoader.expandConfigForTunnel(json: firstExpand)
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(secondExpand.utf8)) as? [String: Any])
        let route = try XCTUnwrap(parsed["route"] as? [String: Any])

        let ruleSets = try XCTUnwrap(route["rule_set"] as? [[String: Any]])
        XCTAssertEqual(ruleSets.count, 3,
                       "rule_set entries deduped — exactly 3 после двух expand'ов, not 6")

        let rules = try XCTUnwrap(route["rules"] as? [[String: Any]])
        let bbtbRefs = rules.compactMap { $0["rule_set"] as? String }
        XCTAssertEqual(bbtbRefs.count, 3,
                       "priority rules deduped — exactly 3 после двух expand'ов, not 6")
    }

    /// R10 invariant: post-expand `validate(json:)` MUST pass.
    /// `route.rule_set` declarations и `action:reject` priority rules не пересекаются
    /// ни с одним из R1 / SEC-02 / SEC-06 gates (inbound whitelist, experimental,
    /// proxy outbound presence, urltest reference resolution).
    func test_expandConfigForTunnel_validatePassesAfterRulesetExpansion_R10invariant() throws {
        let template = try loadFilledTemplate()
        let expanded = try SingBoxConfigLoader.expandConfigForTunnel(json: template)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: expanded),
                         "R10 invariant: post-expand validate MUST pass — rule_set injection не должно ломать gate")
    }

    /// R1 invariant (Phase 8 extension): template `SingBoxConfigTemplate.vless-reality.json`
    /// должен оставаться bare — никаких inline `rule_set` keys. Single source of truth
    /// для rule_set injection — runtime `expandConfigForTunnel`.
    func test_template_doesNotContainInlineRuleSetBlock_R1invariant() throws {
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        XCTAssertFalse(template.contains("\"rule_set\""),
                       "Template must NOT embed inline rule_set key — runtime expansion is single source")
        let parsed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(template.utf8)) as? [String: Any])
        if let route = parsed["route"] as? [String: Any] {
            XCTAssertNil(route["rule_set"],
                         "Route block в template must NOT contain rule_set key")
        }
    }
}
