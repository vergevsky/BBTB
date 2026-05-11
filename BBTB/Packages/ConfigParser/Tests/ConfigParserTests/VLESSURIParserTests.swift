import XCTest
@testable import ConfigParser

final class VLESSURIParserTests: XCTestCase {
    private let validURI = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=abc123-key&sid=01234567&fp=chrome&type=tcp#My%20Test%20Server"

    func test_parse_valid_returnsAllFields() throws {
        let p = try VLESSURIParser.parse(validURI)
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

    func test_parse_withoutReality_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.notRealityProtocol = err else {
                XCTFail("Expected .notRealityProtocol, got \(err)")
                return
            }
        }
    }

    func test_parse_wrongEncryption_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=auto&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedEncryption(let e) = err else {
                XCTFail("Expected .unsupportedEncryption, got \(err)")
                return
            }
            XCTAssertEqual(e, "auto")
        }
    }

    func test_parse_invalidUUID_throws() {
        let uri = "vless://not-a-uuid@example.com:443?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingHost_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@:443?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPort_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPbk_publicKeyIsEmpty() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality"
        let p = try VLESSURIParser.parse(uri)
        XCTAssertEqual(p.publicKey, "")
        // ConfigBuilder downstream catches empty publicKey if it's actually invalid for sing-box.
    }

    func test_parse_handlesWhitespace() throws {
        let uri = "  \(validURI)\n"
        let p = try VLESSURIParser.parse(uri)
        XCTAssertEqual(p.host, "example.com")
    }
}
