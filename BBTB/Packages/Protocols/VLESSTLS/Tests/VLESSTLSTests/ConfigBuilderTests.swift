import XCTest
import VPNCore
import TransportRegistry
@testable import VLESSTLS

/// T-A2 (closes C8-003 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path.
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        port: Int = 443,
        flow: String? = nil,
        sni: String = "vpn.example.ru",
        fingerprint: String = "chrome",
        alpn: [String] = ["h2", "http/1.1"],
        transport: TransportConfig = .tcp
    ) -> ParsedVLESSTLS {
        return ParsedVLESSTLS(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
            host: "example.com",
            port: port,
            flow: flow,
            sni: sni,
            fingerprint: fingerprint,
            alpn: alpn,
            transport: transport,
            remarks: nil
        )
    }

    func test_buildOutbound_basic_dictHasExpectedShape() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")

        XCTAssertEqual(outbound["type"] as? String, "vless")
        XCTAssertEqual(outbound["tag"] as? String, "vless-tls-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["uuid"] as? String, "00000000-0000-0000-0000-00000000abcd")
        XCTAssertEqual(outbound["network"] as? String, "tcp")

        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual(tls["server_name"] as? String, "vpn.example.ru")
        XCTAssertEqual(tls["insecure"] as? Bool, false, "R1: VLESS+TLS strict TLS (no D-08 exception)")
        XCTAssertNil(tls["reality"], "VLESS+TLS MUST NOT include reality block")
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    func test_buildOutbound_visionFlow_setInOutbound() {
        let parsed = makeParsed(flow: "xtls-rprx-vision")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")
        XCTAssertEqual(outbound["flow"] as? String, "xtls-rprx-vision")
    }

    func test_buildOutbound_nilFlow_emptyString() {
        let parsed = makeParsed(flow: nil)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")
        XCTAssertEqual(outbound["flow"] as? String, "")
    }

    func test_buildOutbound_customPort_propagated() {
        let parsed = makeParsed(port: 8443)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 8443)
    }

    func test_buildOutbound_R1_insecureFalse() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-tls-0")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    func test_buildOutbound_ws_stripsH2FromALPN() {
        // Phase 2 W4 invariant — WS upgrade incompatible с h2 ALPN.
        let parsed = makeParsed(alpn: ["h2", "http/1.1"])
        let wsTransport: TransportConfig = .ws(path: "/path", host: "example.com")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: wsTransport, tag: "vless-tls-0")
        let tls = outbound["tls"] as! [String: Any]
        let alpn = tls["alpn"] as? [String]
        XCTAssertEqual(alpn, ["http/1.1"], "WS transport должен strip h2 из ALPN")
    }
}
