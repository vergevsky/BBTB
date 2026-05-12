import XCTest
@testable import ConfigParser
import VPNCore

/// PROTO-03 — VLESS+TLS (без Reality) parser tests.
///
/// Plan 04-02 GREEN: реальные assertions на новую `VLESSURIParser.parse(_:) throws -> AnyParsedConfig`
/// сигнатуру с двойной веткой (D-02): Reality precedence (`pbk` OR `security=reality`) → vlessReality;
/// `security=tls` без Reality → vlessTLS; иначе throw `.unsupportedSecurity`.
///
/// Plan 05-02 / Wave 1: миграция D-05 — `parsed.networkType: String` → `parsed.transport: TransportConfig`.
/// Старые assertions `XCTAssertEqual(parsed.networkType, "tcp")` заменены на
/// `XCTAssertEqual(parsed.transport, .tcp)`. Добавлены WS-tests (Wave 1 vertical slice).
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
        XCTAssertEqual(parsed.transport, .tcp)
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

    // MARK: Wave 1 — VLESS+TLS+WebSocket vertical slice

    /// D-09 — VLESS+TLS URI с `?type=ws&path=/p&host=h` → `.vlessTLS` с
    /// `parsed.transport == .ws(path: "/p", host: "h")`. URI идёт через
    /// `TransportParamParser`, который читает path/host.
    func test_vlessTLS_ws_uri_parsesToWsTransport() throws {
        let uri = loadFixture("vless-tls-ws")
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.transport, .ws(path: "/buy", host: "cdn.example"))
    }

    /// D-10 + Pitfall 10 — неизвестный transport (`type=quic`) → парсер throws
    /// `VLESSURIError.unsupportedTransport`. UniversalImportParser маршрутизирует
    /// эту ошибку в `.unsupported(reason: .transportUnsupported)` с сохранением
    /// URI для UI feedback.
    func test_vlessTLS_unknown_transport_throwsTransportError() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&type=quic&sni=example.com&fp=chrome#unknown-transport"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedTransport(let typeRaw) = err else {
                XCTFail("Expected VLESSURIError.unsupportedTransport, got \(err)")
                return
            }
            XCTAssertEqual(typeRaw, "quic")
        }
    }

    /// End-to-end через UniversalImportParser: unknown VLESS+TLS transport →
    /// `.unsupported(reason: .transportUnsupported)` с сохранением `rawURI` для UI.
    func test_vlessTLS_unknown_transport_routesToUnsupportedViaUniversalImport() async throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&type=quic&sni=example.com&fp=chrome#unknown-transport"
        let parser = UniversalImportParser()
        let result = try await parser.import(rawInput: uri, source: .pasteboard)
        XCTAssertEqual(result.unsupported.count, 1,
                       "VLESS+TLS unknown transport должен попасть в .unsupported")
        XCTAssertEqual(result.supported.count, 0)
        XCTAssertEqual(result.failed.count, 0,
                       "Unknown transport — НЕ malformed, должен быть .unsupported, не .invalid")
        guard case let .unsupported(_, scheme, _, _, rawURI, reason) = result.unsupported[0] else {
            XCTFail("Expected .unsupported case")
            return
        }
        XCTAssertEqual(scheme, "vless")
        XCTAssertEqual(reason, .transportUnsupported)
        XCTAssertEqual(rawURI, uri, "rawURI должен быть сохранён для UI feedback")
    }

    /// URI без `?type=` query-параметра → default `.tcp`
    /// (TransportParamParser fallback per D-10).
    func test_vlessTLS_tcp_default_when_type_absent() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&sni=example.com&fp=chrome#tcp-default"
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.transport, .tcp,
                       "URI без ?type= → transport == .tcp (D-10 fallback)")
    }

    // MARK: Wave 2 — VLESS+TLS+HTTP/2 vertical slice (Plan 05-03)

    /// D-09 — VLESS+TLS URI с `?type=http&path=/api` → `.vlessTLS` с
    /// `parsed.transport == .http(path: "/api")`. URI идёт через
    /// `TransportParamParser`, который умеет http/h2 (Wave 0 функционал).
    /// Фикстура: `vless-tls-http.txt`.
    func test_vlessTLS_http_uri_parses() throws {
        let uri = loadFixture("vless-tls-http")
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.transport, .http(path: "/api"))
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.sni, "example.com")
        XCTAssertEqual(parsed.fingerprint, "chrome")
    }

    /// Pitfall 10 alias — URI с `type=h2` парсится как `.http(path:)`.
    /// V2RayNG / V2Ray-core используют h2 как alias на HTTP/2 transport;
    /// TransportParamParser (Wave 0) приводит h2 → .http(path:) на уровне парсера.
    /// `TransportConfig` enum имеет только `.http`, не `.h2`.
    func test_vlessTLS_h2_alias_parses_as_http() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&type=h2&path=/api&sni=example.com&fp=chrome#h2-alias"
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessTLS(parsed) = result else {
            XCTFail("Expected .vlessTLS, got \(result)")
            return
        }
        XCTAssertEqual(parsed.transport, .http(path: "/api"),
                       "type=h2 должен дешифроваться TransportParamParser-ом как .http (Pitfall 10 alias)")
    }

    /// D-10 — VLESS+TLS URI с `?type=http` без `&path=` → throws
    /// `VLESSURIError.unsupportedTransport`. UniversalImportParser маршрутизирует
    /// в `.unsupported(reason: .transportUnsupported)` (см. routing test
    /// `test_vlessTLS_unknown_transport_routesToUnsupportedViaUniversalImport`).
    /// На уровне парсера: TransportParamParser бросает `.httpMissingPath`,
    /// VLESSURIParser сворачивает структурную ошибку в `unsupportedTransport("http")`.
    func test_vlessTLS_http_missingPath_returnsUnsupported() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&type=http&sni=example.com&fp=chrome#missing-path"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedTransport(let typeRaw) = err else {
                XCTFail("Expected .unsupportedTransport, got \(err)")
                return
            }
            // Парсер сохраняет URI raw type для UI feedback; в case missingPath
            // лейбл — само значение `q["type"]?.lowercased()` (= "http").
            XCTAssertEqual(typeRaw, "http",
                           "raw type должен быть сохранён в throw для UI feedback")
        }
    }
}
