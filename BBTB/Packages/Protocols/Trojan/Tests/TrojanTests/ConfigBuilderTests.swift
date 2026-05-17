import XCTest
import VPNCore
import TransportRegistry
@testable import Trojan

/// T-A2 (closes C8-005 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path.
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        host: String = "example.com",
        port: Int = 443,
        password: String = "secret",
        sni: String = "vpn.example.ru",
        fingerprint: String = "chrome",
        alpn: [String] = ["h2", "http/1.1"],
        transport: TransportConfig = .tcp
    ) -> ParsedTrojan {
        return ParsedTrojan(
            password: password, host: host, port: port,
            security: "tls", sni: sni, fingerprint: fingerprint,
            alpn: alpn, transport: transport, remarks: nil
        )
    }

    func test_buildOutbound_tcp_dictShape() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "trojan-0")

        XCTAssertEqual(outbound["type"] as? String, "trojan")
        XCTAssertEqual(outbound["tag"] as? String, "trojan-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["password"] as? String, "secret")
        XCTAssertEqual(outbound["network"] as? String, "tcp")

        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["server_name"] as? String, "vpn.example.ru")
        XCTAssertEqual(tls["insecure"] as? Bool, false, "R1: Trojan strict TLS")
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    func test_buildOutbound_ws_transportBlock() {
        let wsTransport: TransportConfig = .ws(path: "/path123", host: "vpn.example.ru")
        let parsed = makeParsed(transport: wsTransport)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: wsTransport, tag: "trojan-0")

        let transport = outbound["transport"] as! [String: Any]
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/path123")
        let headers = transport["headers"] as! [String: Any]
        XCTAssertEqual(headers["Host"] as? String, "vpn.example.ru")
    }

    func test_buildOutbound_ws_emptyHost_usesSNIFallback() {
        // Phase 2 W4 invariant — empty WS host falls back на SNI.
        let wsTransport: TransportConfig = .ws(path: "/p", host: "")
        let parsed = makeParsed(sni: "fallback.example.com", transport: wsTransport)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: wsTransport, tag: "trojan-0")

        let transport = outbound["transport"] as! [String: Any]
        let headers = transport["headers"] as! [String: Any]
        XCTAssertEqual(headers["Host"] as? String, "fallback.example.com")
    }

    func test_buildOutbound_nonDefaultPort_propagated() {
        let parsed = makeParsed(port: 2087)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "trojan-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 2087)
    }

    func test_buildOutbound_R1_insecureFalse() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "trojan-0")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    func test_buildOutbound_ws_stripsH2FromALPN() {
        let wsTransport: TransportConfig = .ws(path: "/p", host: "h.example.com")
        let parsed = makeParsed(alpn: ["h2", "http/1.1"], transport: wsTransport)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: wsTransport, tag: "trojan-0")

        let tls = outbound["tls"] as! [String: Any]
        let alpn = tls["alpn"] as? [String]
        XCTAssertEqual(alpn, ["http/1.1"])
    }

    /// Real user fixture sanity check (sanitized password).
    func test_buildOutbound_realUserFixture() {
        let parsed = ParsedTrojan(
            password: "TEST_PASSWORD_REDACTED",
            host: "185.237.218.81",
            port: 2087,
            security: "tls",
            sni: "vpn.vergevsky.ru",
            fingerprint: "chrome",
            alpn: ["h2", "http/1.1"],
            transport: .tcp,
            remarks: "Латвия — Trojan"
        )
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "trojan-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 2087)
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["server_name"] as? String, "vpn.vergevsky.ru")
    }
}
