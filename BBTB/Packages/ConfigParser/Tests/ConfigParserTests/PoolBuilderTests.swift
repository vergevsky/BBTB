import XCTest
import PacketTunnelKit
import VPNCore
import TransportRegistry
@testable import ConfigParser

final class PoolBuilderTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Phase 5 Wave 7 — register all 5 transport handlers before any PoolBuilder tests.
        // Production bootstrap (BBTB_iOSApp / BBTB_macOSApp) does this at app startup.
        // Without registration, TransportRegistry.shared.handler(for:) returns nil,
        // and protocol packages skip the transport block (TCP fallback — still correct, but
        // integration smoke test requires WS block to be present).
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)
    }

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
        transport: TransportConfig = .tcp,
        remarks: String? = nil
    ) -> ParsedVLESSTLS {
        // Phase 5 D-05 — networkType:String мигрировано в transport:TransportConfig.
        return ParsedVLESSTLS(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
            host: host, port: port, flow: flow, sni: sni,
            fingerprint: fingerprint, alpn: alpn, transport: transport, remarks: remarks
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

    private func makeHysteria2(
        host: String = "hy2.example.com",
        port: Int = 443,
        auth: String = "hy2auth",
        sni: String = "hy2.example.com",
        fingerprint: String? = nil,
        obfs: String? = nil,
        obfsPassword: String? = nil,
        allowInsecure: Bool = false,
        pinSHA256: String? = nil,
        remarks: String? = nil
    ) -> ParsedHysteria2 {
        return ParsedHysteria2(
            host: host, port: port, auth: auth, sni: sni,
            fingerprint: fingerprint, obfs: obfs, obfsPassword: obfsPassword,
            allowInsecure: allowInsecure, pinSHA256: pinSHA256, remarks: remarks
        )
    }

    private func makeTrojan(host: String = "trojan-host", port: Int = 443, ws: Bool = false) -> ParsedTrojan {
        // Phase 5 D-06 — ParsedTrojan.TransportType удалён, заменён на TransportConfig.
        let transport: TransportConfig = ws
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

    // MARK: Phase 4 Plan 04 — Hysteria2 outbound builder (R1 EXCEPTION — D-08)

    func test_hysteria2_buildsValidOutbound() throws {
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first {
            ($0["type"] as? String) == "hysteria2" && ($0["tag"] as? String)?.hasPrefix("hy2-") == true
        }
        XCTAssertNotNil(hy2, "Expected outbound type=hysteria2 with tag starting with 'hy2-'")
        XCTAssertEqual(hy2?["server"] as? String, "hy2.example.com")
        XCTAssertEqual(hy2?["server_port"] as? Int, 443)
        XCTAssertEqual(hy2?["password"] as? String, "hy2auth")
        let tls = hy2?["tls"] as? [String: Any]
        XCTAssertEqual(tls?["enabled"] as? Bool, true)
        XCTAssertEqual(tls?["server_name"] as? String, "hy2.example.com")
        XCTAssertEqual(tls?["insecure"] as? Bool, false, "Default allowInsecure=false → strict TLS")
        XCTAssertEqual(tls?["alpn"] as? [String], ["h3"], "Hysteria2 = QUIC = h3 ALPN")
        // R1 self-test — generated pool JSON проходит strict validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_hysteria2_insecureTrue() throws {
        // D-08 R1 EXCEPTION — единственный outbound где tls.insecure=true legitimate.
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2(allowInsecure: true))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first { ($0["type"] as? String) == "hysteria2" }!
        let tls = hy2["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, true,
                       "D-08 R1 EXCEPTION: Hy2 single legit insecure=true в pool outbound")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_hysteria2_insecureFalse_default() throws {
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2(allowInsecure: false))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first { ($0["type"] as? String) == "hysteria2" }!
        let tls = hy2["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false, "Strict TLS default — allowInsecure=false")
    }

    func test_hysteria2_obfsSalamander_present() throws {
        let configs: [AnyParsedConfig] = [
            .hysteria2(makeHysteria2(obfs: "salamander", obfsPassword: "obfspass")),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first { ($0["type"] as? String) == "hysteria2" }!
        let obfs = hy2["obfs"] as? [String: Any]
        XCTAssertNotNil(obfs, "obfs salamander с непустым password → ключ obfs в outbound")
        XCTAssertEqual(obfs?["type"] as? String, "salamander")
        XCTAssertEqual(obfs?["password"] as? String, "obfspass")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_hysteria2_obfsAbsent_omitted() throws {
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2(obfs: nil, obfsPassword: nil))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first { ($0["type"] as? String) == "hysteria2" }!
        XCTAssertNil(hy2["obfs"], "obfs=nil → ключ obfs absent в outbound")
    }

    func test_hysteria2_pinSHA256() throws {
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2(pinSHA256: "abc123"))]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let hy2 = outbounds.first { ($0["type"] as? String) == "hysteria2" }!
        let tls = hy2["tls"] as! [String: Any]
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["abc123"])
    }

    func test_hysteria2_singleServer_degenerate() throws {
        let configs: [AnyParsedConfig] = [.hysteria2(makeHysteria2())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)
        XCTAssertNil((root["outbounds"] as! [[String: Any]]).first { ($0["type"] as? String) == "urltest" },
                     "Single-server pool must NOT have urltest")
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "hy2-0")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: R1 INVARIANT — Pitfall 2 mitigation (CRITICAL)

    /// **R1 invariant test (Pitfall 2 mitigation)** — итерирует ВСЕ outbounds в multi-protocol pool,
    /// и assert'ит что любой outbound с tag НЕ начинающимся с `hy2-` НЕ имеет `tls.insecure==true`.
    ///
    /// Этот тест ловит copy-paste regression: если разработчик скопировал паттерн `tls.insecure:
    /// parsed.allowInsecure` из `buildHysteria2Outbound` в `buildVLESSTLSOutbound` / `buildTrojanOutbound`
    /// / `buildShadowsocksOutbound`, этот тест падает с понятным сообщением.
    ///
    /// Pool намеренно содержит Hy2 с allowInsecure=true (D-08 legitimate exception) — это
    /// доказывает, что test НЕ false-positive: hy2-* outbound может legitimately иметь
    /// insecure=true, но non-hy2 outbounds — никогда.
    func test_nonHy2_outbounds_neverHaveInsecureTrue() throws {
        let pool: [AnyParsedConfig] = [
            .vlessReality(makeVLESS()),
            .vlessTLS(makeVLESSTLS()),
            .trojan(makeTrojan()),
            .shadowsocks(makeShadowsocks()),
            // D-08 — Hy2 ЕДИНСТВЕННЫЙ outbound с legitimate insecure=true.
            .hysteria2(makeHysteria2(allowInsecure: true)),
        ]
        let json = try PoolBuilder.buildSingBoxJSON(from: pool)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]

        var sawHy2Insecure = false
        for outbound in outbounds {
            guard let tag = outbound["tag"] as? String else { continue }
            // direct / urltest — skip (no tls).
            if tag.hasPrefix("hy2-") {
                if let tls = outbound["tls"] as? [String: Any],
                   tls["insecure"] as? Bool == true {
                    sawHy2Insecure = true
                }
                continue
            }
            if let tls = outbound["tls"] as? [String: Any],
               let insecure = tls["insecure"] as? Bool {
                XCTAssertFalse(
                    insecure,
                    "R1 violation: outbound \(tag) has tls.insecure=true (только hy2-* outbound может; D-08)"
                )
            }
        }
        XCTAssertTrue(sawHy2Insecure,
                      "Sanity: pool должен содержать hy2-* outbound с insecure=true (это legitimate D-08 case; "
                      + "его отсутствие означает что invariant test не проверяет реальный сценарий)")
    }

    // MARK: Phase 10 / DPI-09 — uTLS global picker override (App Group UserDefaults)

    // tearDown helper — cleans up App Group key after each test to avoid cross-test pollution.
    // Called after each test method automatically via XCTestCase override.
    override func tearDown() {
        super.tearDown()
        UserDefaults(suiteName: "group.app.bbtb.shared")?.removeObject(forKey: "app.bbtb.utlsFingerprint")
    }

    /// Test 1 (DPI-09): App Group picker = "chrome" — VLESS+TLS with no URI fp (default "random")
    /// should produce outbound.tls.utls.fingerprint = "chrome" (picker override applies).
    func test_buildSingBoxJSON_applies_utls_picker_from_app_group_userDefaults() throws {
        // ARRANGE: set picker to "chrome" in App Group suite.
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        groupDefaults?.set("chrome", forKey: "app.bbtb.utlsFingerprint")
        groupDefaults?.synchronize()

        // VLESS+TLS with fingerprint = "random" (simulates URI with no fp= param = Phase 7a default).
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(fingerprint: "random"))]

        // ACT
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)

        // ASSERT
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        let tls = vlessTLS["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome",
                       "DPI-09: picker 'chrome' must override protocol default 'random' in outbound")
    }

    /// Test 2 (DPI-09): App Group picker = "random" (default) — existing behavior preserved.
    /// When picker is at default, protocol fingerprints are left unchanged.
    func test_buildSingBoxJSON_picker_default_random_preserves_existing_behavior() throws {
        // ARRANGE: set picker explicitly to "random" (same as absent / default).
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        groupDefaults?.set("random", forKey: "app.bbtb.utlsFingerprint")
        groupDefaults?.synchronize()

        // VLESS+TLS with fingerprint = "random".
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(fingerprint: "random"))]

        // ACT
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)

        // ASSERT
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        let tls = vlessTLS["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "random",
                       "DPI-09: picker 'random' (default) must NOT override existing protocol fingerprint")
    }

    /// Test 3 (DPI-09): URI explicitly sets fp=firefox; App Group picker = "chrome".
    /// URI-explicit fingerprint must NOT be overridden by picker (URI parameter priority).
    func test_buildSingBoxJSON_picker_does_not_override_uri_explicit_fp() throws {
        // ARRANGE: set picker to "chrome" in App Group suite.
        let groupDefaults = UserDefaults(suiteName: "group.app.bbtb.shared")
        groupDefaults?.set("chrome", forKey: "app.bbtb.utlsFingerprint")
        groupDefaults?.synchronize()

        // VLESS+TLS where URI explicitly set fingerprint = "firefox" (non-default, URI-provided).
        let configs: [AnyParsedConfig] = [.vlessTLS(makeVLESSTLS(fingerprint: "firefox"))]

        // ACT
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)

        // ASSERT
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vlessTLS = outbounds.first { ($0["tag"] as? String)?.hasPrefix("vless-tls-") == true }!
        let tls = vlessTLS["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "firefox",
                       "DPI-09: URI-explicit fingerprint 'firefox' must NOT be overridden by picker 'chrome'")
    }

    // MARK: Phase 5 Wave 7 — VLESS+TLS+WS integration smoke test

    /// End-to-end test: VLESS+TLS with WS transport produces `transport: {type: "ws", ...}` block.
    /// This is the first test that verifies Phase 5 new behavior — VLESS+TLS gets transport block
    /// via TransportRegistry (D-13). Transport handlers must be registered (done in setUp).
    func test_vlessTLS_ws_poolJson_hasTransportBlock() throws {
        let parsed = makeVLESSTLS(
            host: "example.com",
            port: 443,
            sni: "example.com",
            alpn: ["h2", "http/1.1"],
            transport: .ws(path: "/buy", host: "cdn.example")
        )
        let json = try PoolBuilder.buildSingBoxJSON(from: [.vlessTLS(parsed)])
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        guard let vlessTLSOutbound = outbounds.first(where: { ($0["type"] as? String) == "vless" }) else {
            XCTFail("Expected VLESS outbound in JSON")
            return
        }
        guard let transport = vlessTLSOutbound["transport"] as? [String: Any] else {
            XCTFail("Expected 'transport' block in VLESS+TLS+WS outbound (Phase 5 new behavior)")
            return
        }
        XCTAssertEqual(transport["type"] as? String, "ws",
                       "VLESS+TLS+WS must have transport.type = 'ws'")
        XCTAssertEqual(transport["path"] as? String, "/buy",
                       "WS path must be '/buy'")
        guard let headers = transport["headers"] as? [String: String] else {
            XCTFail("Expected headers in WS transport block")
            return
        }
        XCTAssertEqual(headers["Host"], "cdn.example",
                       "WS Host header must be 'cdn.example'")

        // Also verify ALPN h2-strip applied
        guard let tls = vlessTLSOutbound["tls"] as? [String: Any],
              let alpn = tls["alpn"] as? [String] else {
            XCTFail("Expected tls.alpn in outbound")
            return
        }
        XCTAssertFalse(alpn.contains("h2"), "ALPN h2-strip must apply for WS transport")
    }
}
