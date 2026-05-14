import XCTest
import VPNCore
@testable import TUIC

/// Phase 7a Wave 1 — PROTO-08 TUIC v5 — `TUIC.ConfigBuilder.buildOutbound` invariants.
/// Pool case: dictionary output, R1 strict (no tls.insecure), QUIC-only (transport ignored).
final class BuildOutboundTests: XCTestCase {

    private func defaultParsed(
        host: String = "tuic.example.com",
        port: Int = 443,
        uuid: String = "11111111-2222-3333-4444-555555555555",
        password: String = "tuic-password",
        congestionControl: String = "bbr",
        udpRelayMode: String = "native",
        sni: String = "tuic.example.com",
        alpn: [String] = ["h3"],
        fingerprint: String = "chrome",
        pinSHA256: String? = nil
    ) -> ParsedTUIC {
        ParsedTUIC(
            host: host, port: port, uuid: uuid, password: password,
            congestionControl: congestionControl, udpRelayMode: udpRelayMode,
            sni: sni, alpn: alpn, fingerprint: fingerprint, pinSHA256: pinSHA256, remarks: nil
        )
    }

    func test_basic_outbound_shape() {
        let outbound = ConfigBuilder.buildOutbound(from: defaultParsed(), transport: .tcp, tag: "tuic-0")
        XCTAssertEqual(outbound["type"] as? String, "tuic")
        XCTAssertEqual(outbound["tag"] as? String, "tuic-0")
        XCTAssertEqual(outbound["server"] as? String, "tuic.example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["uuid"] as? String, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(outbound["password"] as? String, "tuic-password")
        XCTAssertEqual(outbound["congestion_control"] as? String, "bbr")
        XCTAssertEqual(outbound["udp_relay_mode"] as? String, "native")
        XCTAssertEqual(outbound["zero_rtt_handshake"] as? Bool, false)
        XCTAssertEqual(outbound["heartbeat"] as? String, "10s")
    }

    // ============================================================
    // R1 STRICT INVARIANT — TUIC v5 НЕ получает Hysteria2-style allowInsecure exception.
    // ============================================================
    func test_outbound_never_has_insecure() {
        // 6 variations including extreme parameter combinations — все должны выдать tls без `insecure`.
        let inputs: [ParsedTUIC] = [
            defaultParsed(),
            defaultParsed(congestionControl: "cubic"),
            defaultParsed(udpRelayMode: "quic"),
            defaultParsed(fingerprint: "safari"),
            defaultParsed(pinSHA256: "abcdef"),
            defaultParsed(alpn: ["h3", "http/1.1"]),  // unusual but allowed
        ]
        for parsed in inputs {
            let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "tuic-x")
            let tls = outbound["tls"] as! [String: Any]
            XCTAssertNil(tls["insecure"], "R1 STRICT — TUIC has no allowInsecure exception")
        }
    }

    func test_tls_block_shape() {
        let outbound = ConfigBuilder.buildOutbound(from: defaultParsed(), transport: .tcp, tag: "t")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["enabled"] as? Bool, true)
        XCTAssertEqual(tls["server_name"] as? String, "tuic.example.com")
        XCTAssertEqual(tls["alpn"] as? [String], ["h3"])
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["enabled"] as? Bool, true)
        XCTAssertEqual(utls["fingerprint"] as? String, "chrome")
    }

    func test_pinSHA256_added() {
        let outbound = ConfigBuilder.buildOutbound(
            from: defaultParsed(pinSHA256: "abc123"), transport: .tcp, tag: "t"
        )
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["abc123"])
    }

    func test_pinSHA256_empty_omitted() {
        let outbound = ConfigBuilder.buildOutbound(
            from: defaultParsed(pinSHA256: ""), transport: .tcp, tag: "t"
        )
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertNil(tls["certificate_public_key_sha256"])
    }

    // D-16 (Phase 5): transport parameter accepted for API consistency, but ignored for TUIC.
    func test_transport_ignored_quic_only() {
        // Pass a non-TCP transport — output should be identical to .tcp call.
        let outboundTCP = ConfigBuilder.buildOutbound(from: defaultParsed(), transport: .tcp, tag: "t1")
        let outboundWS  = ConfigBuilder.buildOutbound(
            from: defaultParsed(), transport: .ws(path: "/x", host: "h"), tag: "t1"
        )
        // The TUIC outbound dict should NOT contain a `transport` key — sing-box's TUIC
        // outbound doesn't have a transport overlay (it's pure QUIC).
        XCTAssertNil(outboundTCP["transport"])
        XCTAssertNil(outboundWS["transport"])
    }

    func test_custom_tag_propagated() {
        let outbound = ConfigBuilder.buildOutbound(from: defaultParsed(), transport: .tcp, tag: "tuic-42")
        XCTAssertEqual(outbound["tag"] as? String, "tuic-42")
    }

    func test_custom_alpn_preserved() {
        let outbound = ConfigBuilder.buildOutbound(
            from: defaultParsed(alpn: ["h3", "h3-29"]), transport: .tcp, tag: "t"
        )
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["alpn"] as? [String], ["h3", "h3-29"])
    }

    func test_all_supported_congestion_controls() {
        for cc in ["cubic", "new_reno", "bbr"] {
            let outbound = ConfigBuilder.buildOutbound(
                from: defaultParsed(congestionControl: cc), transport: .tcp, tag: "t"
            )
            XCTAssertEqual(outbound["congestion_control"] as? String, cc)
        }
    }

    func test_all_supported_udp_relay_modes() {
        for mode in ["native", "quic"] {
            let outbound = ConfigBuilder.buildOutbound(
                from: defaultParsed(udpRelayMode: mode), transport: .tcp, tag: "t"
            )
            XCTAssertEqual(outbound["udp_relay_mode"] as? String, mode)
        }
    }
}
