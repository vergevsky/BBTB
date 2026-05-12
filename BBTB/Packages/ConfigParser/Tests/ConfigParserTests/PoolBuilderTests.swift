import XCTest
import PacketTunnelKit
@testable import ConfigParser

final class PoolBuilderTests: XCTestCase {

    private func makeVLESS(host: String = "vless-host", port: Int = 443, sni: String = "example.com") -> ParsedVLESS {
        return ParsedVLESS(
            uuid: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            host: host, port: port, flow: "xtls-rprx-vision",
            security: "reality", sni: sni, publicKey: "abc", shortId: "01",
            fingerprint: "chrome", networkType: "tcp", remarks: nil
        )
    }

    private func makeVLESSTLS(
        host: String = "vpn.test",
        port: Int = 443,
        flow: String? = nil,
        sni: String = "vpn.test",
        fingerprint: String = "chrome",
        alpn: [String] = ["h2", "http/1.1"],
        networkType: String = "tcp",
        remarks: String? = nil
    ) -> ParsedVLESSTLS {
        return ParsedVLESSTLS(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
            host: host, port: port, flow: flow, sni: sni,
            fingerprint: fingerprint, alpn: alpn, networkType: networkType, remarks: remarks
        )
    }

    private func makeShadowsocks(
        host: String = "ss.example.com",
        port: Int = 8388,
        method: String = "2022-blake3-aes-256-gcm",
        password: String = "testpasswordhere32bytesbase64encoded=",
        remarks: String? = nil
    ) -> ParsedShadowsocks {
        return ParsedShadowsocks(
            host: host, port: port, method: method, password: password, remarks: remarks
        )
    }

    private func makeTrojan(host: String = "trojan-host", port: Int = 443, ws: Bool = false) -> ParsedTrojan {
        let transport: ParsedTrojan.TransportType = ws
            ? .ws(path: "/p", host: "vpn.example.ru")
            : .tcp
        return ParsedTrojan(
            password: "pwd", host: host, port: port,
            security: "tls", sni: "vpn.example.ru", fingerprint: "chrome",
            alpn: ["h2", "http/1.1"], transport: transport, remarks: nil
        )
    }

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    // MARK: Test 1 — multi-server pool with urltest

    func test_multiServer_generatesUrltest() throws {
        let configs: [AnyParsedConfig] = [
            .vlessReality(makeVLESS(host: "host1")),
            .vlessReality(makeVLESS(host: "host2")),
            .trojan(makeTrojan(host: "host3")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        // 3 supported + urltest + direct = 5
        XCTAssertEqual(outbounds.count, 5)
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }
        XCTAssertNotNil(urltest)
        let urltestRefs = urltest?["outbounds"] as? [String]
        XCTAssertEqual(urltestRefs, ["vless-0", "vless-1", "trojan-2"])
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "urltest-out")
    }

    // MARK: Test 2 — single server: degenerate (no urltest)

    func test_singleServer_degenerate() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        // 1 supported + direct = 2 (no urltest)
        XCTAssertEqual(outbounds.count, 2)
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }
        XCTAssertNil(urltest)
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "vless-0")
    }

    // MARK: Test 3 — zero supported → throws

    func test_noSupported_throws() {
        XCTAssertThrowsError(try PoolBuilder.buildSingBoxJSON(from: [])) { err in
            XCTAssertEqual(err as? PoolBuilder.PoolError, .noSupportedServers)
        }
    }

    // MARK: Test 4 — pool config passes SingBoxConfigLoader.validate

    func test_poolConfig_passesValidate() throws {
        let configs: [AnyParsedConfig] = [
            .vlessReality(makeVLESS(host: "host1")),
            .trojan(makeTrojan(host: "host2", ws: true)),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Test 5 — urltest config has expected fields

    func test_urltest_hasExpectedFields() throws {
        let configs: [AnyParsedConfig] = [
            .vlessReality(makeVLESS(host: "h1")),
            .vlessReality(makeVLESS(host: "h2")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }!
        XCTAssertEqual(urltest["url"] as? String, "https://cp.cloudflare.com/generate_204")
        XCTAssertEqual(urltest["interval"] as? String, "1m")
        XCTAssertEqual(urltest["tolerance"] as? Int, 50)
        XCTAssertEqual(urltest["idle_timeout"] as? String, "30m")
        XCTAssertEqual(urltest["interrupt_exist_connections"] as? Bool, false)
    }

    // MARK: Test 6 — tags are deterministic by index

    func test_tagsAreDeterministic() throws {
        let configs: [AnyParsedConfig] = [
            .vlessReality(makeVLESS()),
            .trojan(makeTrojan()),
            .vlessReality(makeVLESS()),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tags = outbounds.compactMap { $0["tag"] as? String }
        XCTAssertTrue(tags.contains("vless-0"))
        XCTAssertTrue(tags.contains("trojan-1"))
        XCTAssertTrue(tags.contains("vless-2"))
    }

    // MARK: Test 7 — >50 servers truncated to 50

    func test_truncatesAt50Servers() throws {
        let configs: [AnyParsedConfig] = (0..<60).map { _ in .vlessReality(makeVLESS()) }
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        // 50 supported + urltest + direct = 52
        XCTAssertEqual(outbounds.count, 52)
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }!
        let refs = urltest["outbounds"] as! [String]
        XCTAssertEqual(refs.count, 50)
    }

    // MARK: Bonus — DNS detour points to urltest

    func test_dns_detour_isUrltest() throws {
        let configs: [AnyParsedConfig] = [
            .vlessReality(makeVLESS(host: "h1")),
            .vlessReality(makeVLESS(host: "h2")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let dns = root["dns"] as! [String: Any]
        let servers = dns["servers"] as! [[String: Any]]
        let remote = servers.first { ($0["tag"] as? String) == "dns-remote" }!
        XCTAssertEqual(remote["detour"] as? String, "urltest-out")
    }

    // MARK: Test — WS outbound must not contain h2 in ALPN (h2 causes TLS negotiation to
    // h2; server then rejects HTTP/1.1 WebSocket upgrade → i/o timeout)

    func test_trojanWS_alpnExcludesH2() throws {
        let configs: [AnyParsedConfig] = [.trojan(makeTrojan(ws: true))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let trojan = outbounds.first { ($0["type"] as? String) == "trojan" }!
        let tls = trojan["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertFalse(alpn.contains("h2"), "WS transport must not advertise h2 ALPN")
        XCTAssertTrue(alpn.contains("http/1.1"))
    }

    func test_trojanTCP_alpnPreserved() throws {
        let configs: [AnyParsedConfig] = [.trojan(makeTrojan(ws: false))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let trojan = outbounds.first { ($0["type"] as? String) == "trojan" }!
        let tls = trojan["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertTrue(alpn.contains("h2"), "TCP transport may keep h2 in ALPN")
    }

    // MARK: Bonus — single server DNS detour points to single outbound

    func test_singleServer_dns_detour_isOutboundTag() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let dns = root["dns"] as! [String: Any]
        let servers = dns["servers"] as! [[String: Any]]
        let remote = servers.first { ($0["tag"] as? String) == "dns-remote" }!
        XCTAssertEqual(remote["detour"] as? String, "vless-0")
    }

    // MARK: Phase 4 Plan 02 — VLESS+TLS outbound builder

    func test_vlessTLS_buildsValidOutbound() throws {
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first {
            ($0["type"] as? String) == "vless" && ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true
        }
        XCTAssertNotNil(vlessTLS, "Expected outbound type=vless with tag starting with 'vless-tls-'")
        XCTAssertEqual(vlessTLS?["server"] as? String, "vpn.test")
        XCTAssertEqual(vlessTLS?["server_port"] as? Int, 443)
        XCTAssertEqual(vlessTLS?["network"] as? String, "tcp")
        let tls = vlessTLS?["tls"] as? [String: Any]
        XCTAssertEqual(tls?["enabled"] as? Bool, true)
        XCTAssertEqual(tls?["server_name"] as? String, "vpn.test")
        XCTAssertEqual(tls?["insecure"] as? Bool, false, "R1 invariant — VLESS+TLS strict TLS")
        XCTAssertNil(tls?["reality"], "VLESS+TLS pool outbound MUST NOT contain reality block")
        let utls = tls?["utls"] as? [String: Any]
        XCTAssertEqual(utls?["fingerprint"] as? String, "chrome")
        // R1 self-test — generated pool JSON проходит strict validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_vlessTLS_visionFlow_preserved() throws {
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(flow: "xtls-rprx-vision"))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        XCTAssertEqual(vlessTLS["flow"] as? String, "xtls-rprx-vision")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_vlessTLS_nilFlow_handled() throws {
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(flow: nil))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        // flow либо отсутствует, либо пустая строка — оба варианта допустимы для sing-box.
        let flowValue = vlessTLS["flow"] as? String
        XCTAssertTrue(flowValue == nil || flowValue == "",
                      "nil flow → outbound flow либо absent, либо empty string (А1 assumption)")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_vlessTLS_inPool_withTrojan() throws {
        let configs: [AnyParsedConfig] = [
            .vlessTLS(makeVLESSTLS(host: "h1")),
            .trojan(makeTrojan(host: "h2")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }!
        let urltestRefs = urltest["outbounds"] as! [String]
        XCTAssertTrue(urltestRefs.contains(where: { $0.hasPrefix("vless-tls-") }),
                      "urltest selector should reference vless-tls-* tag")
        XCTAssertTrue(urltestRefs.contains("trojan-1"),
                      "urltest selector should reference trojan-1 tag")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_vlessTLS_customALPN_preserved() throws {
        // Кастомный ALPN из ParsedVLESSTLS прокидывается в outbound (не hardcoded в builder'е).
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(alpn: ["http/1.1"]))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        let tls = vlessTLS["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertEqual(alpn, ["http/1.1"])
    }

    // MARK: Phase 4 Plan 03 — Shadowsocks outbound builder

    func test_shadowsocks_buildsValidOutbound() throws {
        let configs: [AnyParsedConfig] = [.shadowsocks(makeShadowsocks())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let ss = outbounds.first {
            ($0["type"] as? String) == "shadowsocks" && ($0["tag"] as? String)?.hasPrefix("ss-") == true
        }
        XCTAssertNotNil(ss, "Expected outbound type=shadowsocks with tag starting 'ss-'")
        XCTAssertEqual(ss?["server"] as? String, "ss.example.com")
        XCTAssertEqual(ss?["server_port"] as? Int, 8388)
        XCTAssertEqual(ss?["method"] as? String, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(ss?["password"] as? String, "testpasswordhere32bytesbase64encoded=")
        XCTAssertEqual(ss?["network"] as? String, "tcp")
        // R1 invariant — Shadowsocks outbound MUST NOT contain tls block (encrypted на
        // уровне протокола; D-08 R1 exception применяется ТОЛЬКО к Hysteria2).
        XCTAssertNil(ss?["tls"], "Shadowsocks outbound MUST NOT contain tls block")
        // R1 self-test — generated pool JSON проходит strict sing-box validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_shadowsocks_legacyMethod_buildsOutbound() throws {
        let configs: [AnyParsedConfig] = [
            .shadowsocks(makeShadowsocks(method: "chacha20-ietf-poly1305", password: "legacyAEADpwd")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let ss = outbounds.first { ($0["type"] as? String) == "shadowsocks" }!
        XCTAssertEqual(ss["method"] as? String, "chacha20-ietf-poly1305")
        XCTAssertEqual(ss["password"] as? String, "legacyAEADpwd")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_shadowsocks_inMultiOutboundPool() throws {
        let configs: [AnyParsedConfig] = [
            .shadowsocks(makeShadowsocks(host: "h1")),
            .trojan(makeTrojan(host: "h2")),
            .vlessTLS(makeVLESSTLS(host: "h3")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        // urltest selector → должен ссылаться на все три тага.
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }!
        let urltestRefs = urltest["outbounds"] as! [String]
        XCTAssertEqual(urltestRefs, ["ss-0", "trojan-1", "vless-tls-2"])
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_shadowsocks_customPort_preserved() throws {
        let configs: [AnyParsedConfig] = [.shadowsocks(makeShadowsocks(port: 9999))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let ss = outbounds.first { ($0["type"] as? String) == "shadowsocks" }!
        XCTAssertEqual(ss["server_port"] as? Int, 9999)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_shadowsocks_singleServer_degenerate() throws {
        // Single SS outbound — degenerate path (no urltest); route.final="ss-0".
        let configs: [AnyParsedConfig] = [.shadowsocks(makeShadowsocks())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertNil(outbounds.first { ($0["type"] as? String) == "urltest" },
                     "Single-server pool must NOT have urltest")
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "ss-0")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
}
