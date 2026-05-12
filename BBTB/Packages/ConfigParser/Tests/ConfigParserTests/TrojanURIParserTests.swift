import XCTest
@testable import ConfigParser
import VPNCore

/// Plan 05-02 / Wave 1 — миграция D-06: `ParsedTrojan.TransportType` enum удалён,
/// `parsed.transport` теперь `TransportConfig` из VPNCore. Pattern matches типа
/// `if case let .ws(path, host) = parsed.transport` сохраняются — `.ws` case label
/// совпадает в обоих enum'ах.
final class TrojanURIParserTests: XCTestCase {

    private func loadFixture(_ name: String, ext: String = "txt") -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).\(ext)")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: Test 1 — real user fixture (sanitized; CONTEXT <specifics>)

    func test_realUserFixture_WSparsedCorrectly() throws {
        let uri = loadFixture("trojan-ws-user-fixture").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.password, "TEST_PASSWORD_REDACTED")
        XCTAssertEqual(p.host, "185.237.218.81")
        XCTAssertEqual(p.port, 2087)
        XCTAssertEqual(p.security, "tls")
        XCTAssertEqual(p.sni, "vpn.vergevsky.ru")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.alpn, ["h2", "http/1.1"])
        if case let .ws(path, host) = p.transport {
            XCTAssertEqual(path, "/ba0ca9ffa1d4")
            XCTAssertEqual(host, "vpn.vergevsky.ru")  // fallback to SNI when ws host absent
        } else {
            XCTFail("Expected .ws transport, got \(p.transport)")
        }
        XCTAssertEqual(p.remarks, "Латвия — Trojan")
    }

    // MARK: Test 2 — minimal TCP+TLS

    func test_tcpMinimal_parses() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@host:443?security=tls#TCP")
        XCTAssertEqual(p.password, "pwd")
        XCTAssertEqual(p.host, "host")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.transport, .tcp)
        XCTAssertEqual(p.sni, "host")  // fallback to authority host
        XCTAssertEqual(p.remarks, "TCP")
    }

    // MARK: Test 3 — missing sni → fallback to host

    func test_missingSNI_fallsBackToHost() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@example.com:443?security=tls")
        XCTAssertEqual(p.sni, "example.com")
    }

    // MARK: Test 4 — missing sni and peer → fallback to host

    func test_missingSNIandPeer_fallsBackToHost() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@host:443?security=tls")
        XCTAssertEqual(p.sni, "host")
    }

    // MARK: Test 5 — peer fallback (clash-extension)

    func test_peerWithoutSNI_usesPeer() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@host:443?security=tls&peer=foo.com")
        XCTAssertEqual(p.sni, "foo.com")
    }

    // MARK: Test 6 — security=none throws

    func test_securityNone_throws() {
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host:443?security=none")) { err in
            XCTAssertEqual(err as? TrojanURIError, .notTLSSecurity("none"))
        }
    }

    // MARK: Test 7 — security missing → throws (strict, D-08)

    func test_securityMissing_throws() {
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host:443")) { err in
            XCTAssertEqual(err as? TrojanURIError, .notTLSSecurity(nil))
        }
    }

    // MARK: Test 8 — type=ws without path → throws

    func test_wsWithoutPath_throws() {
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host:443?security=tls&type=ws")) { err in
            XCTAssertEqual(err as? TrojanURIError, .invalidTransport("ws-missing-path"))
        }
    }

    // MARK: Test 9 — type=h2 → throws

    func test_typeH2_throws() {
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host:443?security=tls&type=h2")) { err in
            XCTAssertEqual(err as? TrojanURIError, .invalidTransport("h2"))
        }
    }

    // MARK: Test 10 — allowInsecure=1 ignored

    func test_allowInsecure_isIgnored() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@host:443?security=tls&allowInsecure=1")
        XCTAssertEqual(p.security, "tls")  // not changed
    }

    // MARK: Test 11 — empty userinfo (no password) → malformedURI

    func test_emptyPassword_throws() {
        // Empty userinfo means URLComponents fails to parse — malformedURI.
        // (URLComponents requires non-empty userinfo when '@' is present.)
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://@host:443?security=tls")) { err in
            // Either .malformedURI (URLComponents reject) или .missingPassword (if URL parsed
            // but user is empty string). Both are acceptable rejections.
            switch err as? TrojanURIError {
            case .malformedURI, .missingPassword:
                break  // OK
            default:
                XCTFail("Expected .malformedURI or .missingPassword, got \(err)")
            }
        }
    }

    // MARK: Test 12 — missing port → throws

    func test_missingPort_throws() {
        // No port — URLComponents.port is nil — malformedURI.
        XCTAssertThrowsError(try TrojanURIParser.parse("trojan://pwd@host?security=tls")) { err in
            XCTAssertEqual(err as? TrojanURIError, .malformedURI)
        }
    }

    // MARK: Test 13 — percent-encoded cyrillic remark

    func test_percentEncodedCyrillicRemark() throws {
        let uri = "trojan://pwd@host:443?security=tls#%D0%9B%D0%B0%D1%82%D0%B2%D0%B8%D1%8F"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.remarks, "Латвия")
    }

    // MARK: Wave 1 — Trojan ws-minimal (host fallback от SNI)

    /// Phase 2 backward-compat: `?type=ws&path=/x` без `&host=` → fallback host от sni.
    /// Это сохраняет существующее поведение (см. `test_realUserFixture_WSparsedCorrectly`),
    /// которое полагается на SNI-as-Host-header при отсутствии явного `host`-параметра.
    /// Plan 05-02 §2 alternative — Trojan parser применяет fallback (TrojanURIParser-specific,
    /// reviewer choice); VLESSURIParser fallback не применяет (host="").
    func test_trojan_ws_minimal_uri_parses() throws {
        let p = try TrojanURIParser.parse("trojan://pwd@example.com:443?security=tls&type=ws&path=/x&sni=example.com")
        XCTAssertEqual(p.transport, .ws(path: "/x", host: "example.com"),
                       "Trojan ws-без-host применяет SNI fallback (Phase 2 backward-compat)")
    }

    // MARK: Wave 2 — Trojan+HTTP/2 vertical slice (Plan 05-03)

    /// D-09 — Trojan URI с `?type=http&path=/api` → `.http(path: "/api")`.
    /// HTTP transport не имеет host-параметра в URI (sing-box подставит
    /// tls.server_name как :authority при сборке outbound в Wave 5),
    /// поэтому SNI-fallback не нужен. Фикстура: `trojan-http.txt`.
    func test_trojan_http_uri_parses() throws {
        let uri = loadFixture("trojan-http").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.password, "trojan-test-password")
        XCTAssertEqual(p.host, "example.com")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.security, "tls")
        XCTAssertEqual(p.sni, "example.com")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.alpn, ["h2"])
        XCTAssertEqual(p.transport, .http(path: "/api"),
                       "Trojan ?type=http&path=/api → .http(path: \"/api\")")
        XCTAssertEqual(p.remarks, "Trojan-HTTP-Test")
    }

    // MARK: Wave 3 — Trojan+HTTPUpgrade vertical slice (Plan 05-04)

    /// D-09 — Trojan URI с `?type=httpupgrade&path=/upgrade&host=h.example.com`
    /// → `.httpUpgrade(path: "/upgrade", host: "h.example.com")`. В отличие от
    /// WS, HTTPUpgrade transport имеет явный host в URI и не требует SNI-fallback —
    /// host передаётся как-есть в sing-box transport блок (Pitfall 7: host —
    /// STRING, не array). Фикстура: `trojan-httpupgrade.txt` (alpn=http%2F1.1
    /// — URL-encoded `http/1.1`, single-value CSV).
    func test_trojan_httpUpgrade_uri_parses() throws {
        let uri = loadFixture("trojan-httpupgrade").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.password, "trojan-test-password")
        XCTAssertEqual(p.host, "example.com")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.security, "tls")
        XCTAssertEqual(p.sni, "example.com")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.alpn, ["http/1.1"])
        XCTAssertEqual(p.transport, .httpUpgrade(path: "/upgrade", host: "h.example.com"),
                       "Trojan ?type=httpupgrade&path=/upgrade&host=h.example.com → .httpUpgrade(path:host:)")
        XCTAssertEqual(p.remarks, "Trojan-HTTPUpgrade-Test")
    }

    // MARK: Wave 4 — Trojan+gRPC vertical slice (Plan 05-05)

    /// D-09 — Trojan URI с `?type=grpc&serviceName=tunsvc` → `.grpc(serviceName:
    /// "tunsvc")`. **Pitfall 6 нюанс**: URI param `serviceName` (camelCase per
    /// V2Ray стандарт) → парсер хранит как Swift label `.grpc(serviceName:)`
    /// camelCase; преобразование к snake_case `service_name` происходит в
    /// `GRPCTransportHandler` при emit'е sing-box JSON-блока (Wave 5
    /// integration). В отличие от WS, gRPC не имеет host-параметра — SNI
    /// fallback здесь не применяется. ALPN — `["h2"]` (gRPC требует HTTP/2,
    /// в отличие от HTTPUpgrade с `http/1.1`). Фикстура: `trojan-grpc.txt`.
    func test_trojan_grpc_uri_parses() throws {
        let uri = loadFixture("trojan-grpc").trimmingCharacters(in: .whitespacesAndNewlines)
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.password, "trojan-test-password")
        XCTAssertEqual(p.host, "example.com")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.security, "tls")
        XCTAssertEqual(p.sni, "example.com")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.alpn, ["h2"])
        XCTAssertEqual(p.transport, .grpc(serviceName: "tunsvc"),
                       "Trojan ?type=grpc&serviceName=tunsvc → .grpc(serviceName: \"tunsvc\") (URI camelCase preserved as Swift label)")
        XCTAssertEqual(p.remarks, "Trojan-gRPC-Test")
    }
}
