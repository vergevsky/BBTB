import XCTest
@testable import ConfigParser
import VPNCore

/// PROTO-08 Phase 7a Wave 1 — TUICURIParser tests.
final class TUICURIParserTests: XCTestCase {

    // MARK: Happy path — minimal URI

    func test_minimal_URI() throws {
        let uri = "tuic://11111111-2222-3333-4444-555555555555:secret@example.com:443"
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 443)
        XCTAssertEqual(parsed.uuid, "11111111-2222-3333-4444-555555555555")
        XCTAssertEqual(parsed.password, "secret")
        XCTAssertEqual(parsed.congestionControl, "bbr")  // default
        XCTAssertEqual(parsed.udpRelayMode, "native")    // default
        XCTAssertEqual(parsed.sni, "example.com")        // host fallback
        XCTAssertEqual(parsed.alpn, ["h3"])              // mandatory default
        XCTAssertEqual(parsed.fingerprint, "random")     // Wave 2 — DPI-01 smart default
        XCTAssertNil(parsed.pinSHA256)
    }

    // MARK: Full URI with all parameters

    func test_full_URI() throws {
        let uri = "tuic://uuid-abc:my%20password@vpn.example.com:8443?congestion_control=cubic&udp_relay_mode=quic&sni=front.example.com&alpn=h3,h3-29&fp=firefox&pinSHA256=deadbeef#My%20TUIC%20Server"
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.host, "vpn.example.com")
        XCTAssertEqual(parsed.port, 8443)
        XCTAssertEqual(parsed.uuid, "uuid-abc")
        XCTAssertEqual(parsed.password, "my password")  // URL-decoded
        XCTAssertEqual(parsed.congestionControl, "cubic")
        XCTAssertEqual(parsed.udpRelayMode, "quic")
        XCTAssertEqual(parsed.sni, "front.example.com")
        XCTAssertEqual(parsed.alpn, ["h3", "h3-29"])
        XCTAssertEqual(parsed.fingerprint, "firefox")
        XCTAssertEqual(parsed.pinSHA256, "deadbeef")
        XCTAssertEqual(parsed.remarks, "My TUIC Server")
    }

    // MARK: Default port = 443

    func test_default_port() throws {
        let uri = "tuic://u:p@example.com"
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.port, 443)
    }

    // MARK: R1 STRICT — insecure=1 ignored

    func test_R1_strict_insecure_ignored() throws {
        // URI пытается передать insecure=1 — мы НЕ имеем поля для этого в ParsedTUIC.
        // Поведение: parser просто игнорирует параметр; pinSHA256 единственный путь.
        let uri = "tuic://u:p@example.com:443?insecure=1&allowInsecure=1&skip-cert-verify=1"
        let parsed = try TUICURIParser.parse(uri)
        // ParsedTUIC не имеет поля allowInsecure — он не существует на типовом уровне.
        // Конфигурация JSON не будет содержать tls.insecure (см. BuildOutboundTests).
        XCTAssertEqual(parsed.host, "example.com")  // parsed ok
    }

    // MARK: Congestion control aliases

    func test_congestion_control_aliases() throws {
        // Поддерживаем три варианта написания: snake_case (sing-box), kebab-case (Clash), и "congestion_controller" (некоторые субсcription панели).
        let aliases = ["congestion_control", "congestion-control", "congestion_controller"]
        for alias in aliases {
            let uri = "tuic://u:p@h.com:443?\(alias)=new_reno"
            let parsed = try TUICURIParser.parse(uri)
            XCTAssertEqual(parsed.congestionControl, "new_reno", "alias \(alias)")
        }
    }

    func test_invalid_congestion_control_throws() {
        let uri = "tuic://u:p@h.com:443?congestion_control=ledbat"
        XCTAssertThrowsError(try TUICURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? TUICURIError, .unsupportedCongestionControl("ledbat"))
        }
    }

    // MARK: udp_relay_mode aliases

    func test_udp_relay_mode_aliases() throws {
        let uri1 = "tuic://u:p@h.com:443?udp_relay_mode=quic"
        let uri2 = "tuic://u:p@h.com:443?udp-relay-mode=quic"
        XCTAssertEqual(try TUICURIParser.parse(uri1).udpRelayMode, "quic")
        XCTAssertEqual(try TUICURIParser.parse(uri2).udpRelayMode, "quic")
    }

    func test_invalid_udp_relay_mode_throws() {
        let uri = "tuic://u:p@h.com:443?udp_relay_mode=stream"
        XCTAssertThrowsError(try TUICURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? TUICURIError, .unsupportedUDPRelayMode("stream"))
        }
    }

    // MARK: Malformed URI

    func test_wrong_scheme_throws() {
        XCTAssertThrowsError(try TUICURIParser.parse("hy2://u:p@h.com:443")) { err in
            XCTAssertEqual(err as? TUICURIError, .malformedURI)
        }
    }

    func test_missing_host_throws() {
        XCTAssertThrowsError(try TUICURIParser.parse("tuic://u:p@")) { err in
            XCTAssertEqual(err as? TUICURIError, .malformedURI)
        }
    }

    func test_missing_password_throws() {
        // userinfo only `uuid` без `:password`
        XCTAssertThrowsError(try TUICURIParser.parse("tuic://justuuid@example.com:443")) { err in
            XCTAssertEqual(err as? TUICURIError, .missingPassword)
        }
    }

    func test_empty_password_throws() {
        // userinfo `uuid:` пустой password
        XCTAssertThrowsError(try TUICURIParser.parse("tuic://uuid:@example.com:443")) { err in
            XCTAssertEqual(err as? TUICURIError, .missingPassword)
        }
    }

    // MARK: SNI fallback to host

    func test_sni_fallback_to_host() throws {
        let uri = "tuic://u:p@example.com:443"  // no sni= в query
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.sni, "example.com")
    }

    func test_sni_explicit_in_query() throws {
        let uri = "tuic://u:p@example.com:443?sni=front.fastly.net"
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.sni, "front.fastly.net")
    }

    // MARK: ALPN CSV parsing

    func test_alpn_default_h3() throws {
        let uri = "tuic://u:p@example.com:443"  // no alpn= в query
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.alpn, ["h3"])
    }

    func test_alpn_csv_parsed() throws {
        let uri = "tuic://u:p@example.com:443?alpn=h3,h3-29,h2"
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.alpn, ["h3", "h3-29", "h2"])
    }

    func test_alpn_empty_falls_back_to_h3() throws {
        let uri = "tuic://u:p@example.com:443?alpn="
        let parsed = try TUICURIParser.parse(uri)
        XCTAssertEqual(parsed.alpn, ["h3"])
    }
}
