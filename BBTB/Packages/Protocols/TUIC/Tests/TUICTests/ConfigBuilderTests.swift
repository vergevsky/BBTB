import XCTest
import VPNCore
@testable import TUIC

/// T-A2 (closes C8-011 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path.
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        host: String = "example.com",
        port: Int = 443,
        uuid: String = "11111111-2222-3333-4444-555555555555",
        password: String = "tuic-password-secret",
        congestionControl: String = "bbr",
        udpRelayMode: String = "native",
        sni: String = "vpn.example.com",
        fingerprint: String = "chrome",
        alpn: [String] = ["h3"],
        pinSHA256: String? = nil
    ) -> ParsedTUIC {
        return ParsedTUIC(
            host: host, port: port,
            uuid: uuid, password: password,
            congestionControl: congestionControl, udpRelayMode: udpRelayMode,
            sni: sni, alpn: alpn,
            fingerprint: fingerprint,
            pinSHA256: pinSHA256,
            remarks: nil
        )
    }

    func test_buildOutbound_basic_dictShape() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")

        XCTAssertEqual(outbound["type"] as? String, "tuic")
        XCTAssertEqual(outbound["tag"] as? String, "tuic-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["uuid"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(outbound["password"] as? String, "tuic-password-secret")
        XCTAssertEqual(outbound["congestion_control"] as? String, "bbr")
        XCTAssertEqual(outbound["udp_relay_mode"] as? String, "native")
        XCTAssertEqual(outbound["zero_rtt_handshake"] as? Bool, false)
        XCTAssertEqual(outbound["heartbeat"] as? String, "10s")

        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["server_name"] as? String, "vpn.example.com")
        XCTAssertEqual(tls["alpn"] as? [String], ["h3"])
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    /// R1 STRICT — TUIC outbound JSON НЕ содержит tls.insecure (no D-08 exception).
    func test_buildOutbound_neverHasInsecure_R1strict() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertNil(tls["insecure"], "TUIC outbound MUST NOT contain tls.insecure (R1 strict)")
    }

    func test_buildOutbound_pinSHA256_inTLS() {
        let pin = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let parsed = makeParsed(pinSHA256: pin)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")
        let tls = outbound["tls"] as! [String: Any]
        let pins = tls["certificate_public_key_sha256"] as? [String]
        XCTAssertEqual(pins, [pin])
    }

    func test_buildOutbound_customPort_propagated() {
        let parsed = makeParsed(port: 8443)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 8443)
    }

    func test_buildOutbound_congestionControl_cubic() {
        let parsed = makeParsed(congestionControl: "cubic")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")
        XCTAssertEqual(outbound["congestion_control"] as? String, "cubic")
    }

    func test_buildOutbound_udpRelayMode_quic() {
        let parsed = makeParsed(udpRelayMode: "quic")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-0")
        XCTAssertEqual(outbound["udp_relay_mode"] as? String, "quic")
    }
}
