import XCTest
@testable import ConfigParser

/// VLESS Reality parser tests.
///
/// Phase 4 Plan 02 — `VLESSURIParser.parse` теперь возвращает `AnyParsedConfig`,
/// а не `ParsedVLESS` напрямую. Reality URI распаковывается через `case let .vlessReality(p)`.
final class VLESSURIParserTests: XCTestCase {
    private let validURI = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=abc123-key&sid=01234567&fp=chrome&type=tcp#My%20Test%20Server"

    /// Helper — распакует Reality case из `AnyParsedConfig` (XCTFail если другой case).
    private func unwrapReality(_ uri: String, file: StaticString = #file, line: UInt = #line) throws -> ParsedVLESS {
        let result = try VLESSURIParser.parse(uri)
        guard case let .vlessReality(p) = result else {
            XCTFail("Expected .vlessReality, got \(result)", file: file, line: line)
            // Throw a clearly-marked error so callers see the wrong-case path explicitly
            // instead of falling through with default values.
            throw VLESSURIError.notRealityProtocol("test-unwrap")
        }
        return p
    }

    func test_parse_valid_returnsAllFields() throws {
        let p = try unwrapReality(validURI)
        XCTAssertEqual(p.uuid.uuidString.lowercased(), "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(p.host, "example.com")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.flow, "xtls-rprx-vision")
        XCTAssertEqual(p.security, "reality")
        XCTAssertEqual(p.sni, "www.microsoft.com")
        XCTAssertEqual(p.publicKey, "abc123-key")
        XCTAssertEqual(p.shortId, "01234567")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.networkType, "tcp")
        XCTAssertEqual(p.remarks, "My Test Server")
    }

    func test_parse_withoutReality_routesToTLSBranch() throws {
        // Phase 4 D-02: vless://...?security=tls без pbk → .vlessTLS (НЕ throw).
        // Замещает старый test_parse_withoutReality_throws — поведение изменилось намеренно.
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls&sni=example.com"
        let result = try VLESSURIParser.parse(uri)
        guard case .vlessTLS = result else {
            XCTFail("Expected .vlessTLS for security=tls without pbk, got \(result)")
            return
        }
    }

    func test_parse_wrongEncryption_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=auto&security=reality&pbk=abc"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedEncryption(let e) = err else {
                XCTFail("Expected .unsupportedEncryption, got \(err)")
                return
            }
            XCTAssertEqual(e, "auto")
        }
    }

    func test_parse_invalidUUID_throws() {
        let uri = "vless://not-a-uuid@example.com:443?encryption=none&security=reality&pbk=abc"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingHost_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@:443?encryption=none&security=reality&pbk=abc"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPort_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com?encryption=none&security=reality&pbk=abc"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPbk_publicKeyIsEmpty() throws {
        // explicit security=reality + missing pbk → Reality branch (security=reality triggers Reality precedence).
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality"
        let p = try unwrapReality(uri)
        XCTAssertEqual(p.publicKey, "")
        // ConfigBuilder downstream catches empty publicKey if it's actually invalid for sing-box.
    }

    func test_parse_missingFlow_defaultsToEmpty() throws {
        // Phase 1 W5 lesson: URI без `?flow=xtls-rprx-vision` → flow="" (без Vision).
        // Сервер сам диктует поддерживает ли Vision; клиент не должен hardcode'ить.
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality"
        let p = try unwrapReality(uri)
        XCTAssertEqual(p.flow, "")
    }

    func test_parse_explicitFlow_preserved() throws {
        // URI с явным `?flow=xtls-rprx-vision` → flow="xtls-rprx-vision" (Vision-enabled сервер).
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality&flow=xtls-rprx-vision"
        let p = try unwrapReality(uri)
        XCTAssertEqual(p.flow, "xtls-rprx-vision")
    }

    func test_parse_handlesWhitespace() throws {
        let uri = "  \(validURI)\n"
        let p = try unwrapReality(uri)
        XCTAssertEqual(p.host, "example.com")
    }
}
