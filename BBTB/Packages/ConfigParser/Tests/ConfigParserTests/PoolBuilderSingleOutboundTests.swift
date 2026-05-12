// PoolBuilderSingleOutboundTests.swift — Phase 3 / Plan 05 / Task 1 (RED).
//
// Тестирует Plan 05 helper `PoolBuilder.buildSingleOutboundJSON(from: AnyParsedConfig)`,
// который собирает 1-outbound pool (degenerate-case, без urltest). Используется в
// MainScreenViewModel.performToggle для pre-connect-auto-select winner deployment +
// manual selection path (D-04, D-09).
//
// RED-фаза: до Task 2 функция `buildSingleOutboundJSON` не существует — тесты не
// компилируются ("Cannot find 'buildSingleOutboundJSON' in scope ...").

import XCTest
import VPNCore
import TransportRegistry
@testable import ConfigParser

final class PoolBuilderSingleOutboundTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Phase 5 Wave 7 — register all 5 transport handlers before any PoolBuilder tests.
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)
    }

    // MARK: Fixtures

    private func makeVLESS(host: String = "vless-host", port: Int = 443) -> ParsedVLESS {
        return ParsedVLESS(
            uuid: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            host: host, port: port,
            flow: "xtls-rprx-vision",
            security: "reality",
            sni: "example.com",
            publicKey: "fakePublicKeyZ12345678901234567890ABCDEF",
            shortId: "01234567",
            fingerprint: "chrome",
            networkType: "tcp",
            remarks: nil
        )
    }

    private func makeTrojanWS(host: String = "trojan.example", port: Int = 443) -> ParsedTrojan {
        return ParsedTrojan(
            password: "pwd-xyz",
            host: host, port: port,
            security: "tls",
            sni: "vpn.example.ru",
            fingerprint: "chrome",
            alpn: ["h2", "http/1.1"],
            transport: .ws(path: "/cfg", host: "vpn.example.ru"),
            remarks: nil
        )
    }

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    // MARK: Tests

    /// Test 1 — 1-outbound pool НЕ содержит urltest selector; route.final = outbound tag.
    func test_buildSingleOutboundJSON_returns_pool_with_no_urltest() throws {
        let parsed: AnyParsedConfig = .trojan(makeTrojanWS())
        let json = try PoolBuilder.buildSingleOutboundJSON(from: parsed)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        // 1 supported + direct = 2 (urltest НЕ создаётся)
        XCTAssertEqual(outbounds.count, 2, "1-outbound pool: только сам outbound + direct")
        let urltest = outbounds.first { ($0["type"] as? String) == "urltest" }
        XCTAssertNil(urltest, "urltest selector НЕ должен присутствовать при count=1")
        let tags = outbounds.compactMap { $0["tag"] as? String }
        XCTAssertTrue(tags.contains("trojan-0"))
        XCTAssertTrue(tags.contains("direct"))
        let route = root["route"] as! [String: Any]
        XCTAssertEqual(route["final"] as? String, "trojan-0", "route.final = единственный outbound tag")
    }

    /// Test 2 — `buildSingleOutboundJSON(p)` структурно эквивалентен `buildSingBoxJSON([p])`.
    /// String equality сравнить нельзя — JSONSerialization не гарантирует порядок ключей
    /// в dictionary. Сравниваем через decode-and-NSDictionary.isEqual (recursive deep equal).
    func test_buildSingleOutboundJSON_equals_buildSingBoxJSON_with_one_element_array() throws {
        let parsed: AnyParsedConfig = .vlessReality(makeVLESS())
        let single = try PoolBuilder.buildSingleOutboundJSON(from: parsed)
        let multi = try PoolBuilder.buildSingBoxJSON(from: [parsed])
        let singleObj = try parse(single) as NSDictionary
        let multiObj = try parse(multi) as NSDictionary
        XCTAssertEqual(singleObj, multiObj,
                       "buildSingleOutboundJSON — thin wrapper над buildSingBoxJSON degenerate-case path (структурный equality)")
    }

    /// Test 3 — protocol-specific fields VLESS-Reality preserved в output.
    func test_buildSingleOutboundJSON_preserves_protocol_specific_settings_vless() throws {
        let parsed: AnyParsedConfig = .vlessReality(makeVLESS(host: "reality-host", port: 8443))
        let json = try PoolBuilder.buildSingleOutboundJSON(from: parsed)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let vless = outbounds.first { ($0["type"] as? String) == "vless" }!
        XCTAssertEqual(vless["server"] as? String, "reality-host")
        XCTAssertEqual(vless["server_port"] as? Int, 8443)
        XCTAssertEqual(vless["uuid"] as? String, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(vless["flow"] as? String, "xtls-rprx-vision")
        let tls = vless["tls"] as! [String: Any]
        XCTAssertEqual(tls["server_name"] as? String, "example.com")
        let reality = tls["reality"] as! [String: Any]
        XCTAssertEqual(reality["public_key"] as? String, "fakePublicKeyZ12345678901234567890ABCDEF")
        XCTAssertEqual(reality["short_id"] as? String, "01234567")
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    /// Test 4 — protocol-specific fields Trojan-WS preserved (path, host, ALPN h2-strip).
    func test_buildSingleOutboundJSON_preserves_protocol_specific_settings_trojan_ws() throws {
        let parsed: AnyParsedConfig = .trojan(makeTrojanWS(host: "tj.example", port: 9443))
        let json = try PoolBuilder.buildSingleOutboundJSON(from: parsed)
        let root = try parse(json)
        let outbounds = root["outbounds"] as! [[String: Any]]
        let trojan = outbounds.first { ($0["type"] as? String) == "trojan" }!
        XCTAssertEqual(trojan["server"] as? String, "tj.example")
        XCTAssertEqual(trojan["server_port"] as? Int, 9443)
        XCTAssertEqual(trojan["password"] as? String, "pwd-xyz")
        let transport = trojan["transport"] as! [String: Any]
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/cfg")
        let headers = transport["headers"] as! [String: Any]
        XCTAssertEqual(headers["Host"] as? String, "vpn.example.ru")
        // ALPN: WS-транспорт должен strip'нуть h2 (см. PoolBuilder.buildTrojanOutbound).
        let tls = trojan["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertFalse(alpn.contains("h2"), "WS transport: h2 strip'нут из ALPN")
        XCTAssertTrue(alpn.contains("http/1.1"))
    }

    /// Test 5 — DNS detour должен указывать на единственный outbound tag.
    func test_buildSingleOutboundJSON_dns_detour_points_to_outbound() throws {
        let parsed: AnyParsedConfig = .trojan(makeTrojanWS())
        let json = try PoolBuilder.buildSingleOutboundJSON(from: parsed)
        let root = try parse(json)
        let dns = root["dns"] as! [String: Any]
        let servers = dns["servers"] as! [[String: Any]]
        let remote = servers.first { ($0["tag"] as? String) == "dns-remote" }!
        XCTAssertEqual(remote["detour"] as? String, "trojan-0",
                       "single-outbound pool: dns-remote.detour = outbound tag (НЕ urltest-out)")
    }
}
