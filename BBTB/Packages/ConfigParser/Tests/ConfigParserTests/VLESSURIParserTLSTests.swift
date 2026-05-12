import XCTest
@testable import ConfigParser

/// PROTO-03 — VLESS+TLS (без Reality) parser tests.
///
/// Plan 04-02 GREEN: реальные assertions на новую `VLESSURIParser.parse(_:) throws -> AnyParsedConfig`
/// сигнатуру с двойной веткой (D-02): Reality precedence (`pbk` OR `security=reality`) → vlessReality;
/// `security=tls` без Reality → vlessTLS; иначе throw `.unsupportedSecurity`.
final class VLESSURIParserTLSTests: XCTestCase {

    private func loadFixture(_ name: String, ext: String = "txt") -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).\(ext)")
            return ""
        }
        return ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: D-02 — security=tls без pbk → AnyParsedConfig.vlessTLS

    func test_securityTLS_returnsVlessTLS() throws {
        let uri = loadFixture("vless-tls-no-flow")
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.uuid.uuidString.lowercased(),
                       "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 443)
        XCTAssertEqual(parsed.sni, "example.com")
        XCTAssertEqual(parsed.fingerprint, "chrome")
        XCTAssertEqual(parsed.networkType, "tcp")
        XCTAssertEqual(parsed.alpn, ["h2", "http/1.1"])
        XCTAssertEqual(parsed.remarks, "VLESS-TLS no flow")
    }

    // MARK: D-02 — Vision flow сохраняется в ParsedVLESSTLS.flow

    func test_visionFlow_preserved() throws {
        let uri = loadFixture("vless-tls-vision")
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.flow, "xtls-rprx-vision")
        XCTAssertEqual(parsed.host, "vision.example.com")
        XCTAssertEqual(parsed.sni, "vision.example.com")
    }

    // MARK: D-02 — нет flow → ParsedVLESSTLS.flow == nil

    func test_noFlow_nilField() throws {
        let uri = loadFixture("vless-tls-no-flow")
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertNil(parsed.flow,
                     "URI без ?flow= → ParsedVLESSTLS.flow должно быть nil (не пустая строка)")
    }

    // MARK: D-02 — security=reality + extra TLS markers → Reality precedence (НЕ TLS branch)
    // Pitfall 3: Reality detection ДО TLS branch — иначе Reality URI ошибочно классифицируется как vlessTLS.

    func test_realityWithExtraTLS_returnsReality() throws {
        // pbk присутствует + дополнительно security=tls — некоторые subscription провайдеры
        // добавляют security=tls параллельно к Reality. Это должно сработать как Reality.
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&pbk=abc123-key&sid=01234567&sni=www.microsoft.com&fp=chrome&type=tcp#Reality-with-extra-TLS"
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessReality(parsed) = result else {
            XCTFail("Expected .vlessReality (Pitfall 3 — pbk presence takes precedence over security=tls), got \(result)")
            return
        }
        XCTAssertEqual(parsed.publicKey, "abc123-key")
        XCTAssertEqual(parsed.shortId, "01234567")
    }

    // MARK: D-02 — security=reality без pbk → Reality branch (по explicit security маркеру)

    func test_securityReality_returnsReality() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome#Reality-explicit"
        let result = try VLESSURIParser.parse(uri)
        guard case .vlessReality = result else {
            XCTFail("Expected .vlessReality (explicit security=reality), got \(result)")
            return
        }
    }

    // MARK: D-02 — security=none → throws .unsupportedSecurity

    func test_securityNone_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=none&sni=example.com#none-security"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedSecurity(let s) = err else {
                XCTFail("Expected .unsupportedSecurity, got \(err)")
                return
            }
            XCTAssertEqual(s, "none")
        }
    }

    // MARK: D-02 — security отсутствует в query → throws .unsupportedSecurity

    func test_securityMissing_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none#no-security"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedSecurity = err else {
                XCTFail("Expected .unsupportedSecurity, got \(err)")
                return
            }
        }
    }

    // MARK: ALPN default applied when missing

    func test_alpnDefault_whenMissing() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&sni=example.com#no-alpn"
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS")
            return
        }
        XCTAssertEqual(parsed.alpn, ["h2", "http/1.1"])
    }

    // MARK: Empty pbk (`pbk=`) — not Reality; falls through to TLS branch

    func test_emptyPbk_notReality_treatedAsTLS() throws {
        // Pitfall 3 nuance: `pbk=` (empty value) — НЕ Reality. Только non-empty pbk триггерит Reality.
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&pbk=&sni=example.com&fp=chrome#empty-pbk"
        let result = try VLESSURIParser.parse(uri)
        guard case .vlessTLS = result else {
            XCTFail("Expected .vlessTLS (empty pbk не считается Reality маркером), got \(result)")
            return
        }
    }
}
