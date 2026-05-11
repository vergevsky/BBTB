import XCTest
@testable import PacketTunnelKit

final class SingBoxConfigLoaderTests: XCTestCase {

    // MARK: Helpers

    private func loadFixture(_ name: String) throws -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).json")
            throw SingBoxConfigError.malformedJSON
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Valid

    func test_acceptsValidVLESSRealityConfig() throws {
        let json = try loadFixture("valid-vless-reality")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_templateLoadsAndValidates_afterPlaceholderReplacement() throws {
        // R1 self-check: bundled template (с ${...} placeholder'ами) после простой подстановки
        // на непустые строки должен пройти validate. Это гарантирует что Wave 4 при импорте vless://
        // получит на выходе R1-compliant конфиг.
        let template = try SingBoxConfigLoader.loadVLESSRealityTemplate()
        let filled = template
            .replacingOccurrences(of: "${SERVER_HOST}", with: "example.com")
            .replacingOccurrences(of: "${VLESS_UUID}", with: "550e8400-e29b-41d4-a716-446655440000")
            .replacingOccurrences(of: "${SNI_DOMAIN}", with: "www.microsoft.com")
            .replacingOccurrences(of: "${UTLS_FINGERPRINT}", with: "chrome")
            .replacingOccurrences(of: "${REALITY_PUBLIC_KEY}", with: "abc123")
            .replacingOccurrences(of: "${REALITY_SHORT_ID}", with: "01234567")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: filled))
    }

    // MARK: R1 — forbidden inbounds (SEC-01)

    func test_rejectsSocksInbound() throws {
        let json = try loadFixture("invalid-socks-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }

    func test_rejectsMixedInbound() throws {
        let json = try loadFixture("invalid-mixed-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("mixed"))
        }
    }

    func test_rejectsTunInbound() throws {
        let json = try loadFixture("invalid-tun-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("tun"))
        }
    }

    func test_rejectsHttpInbound() throws {
        let json = try loadFixture("invalid-http-inbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("http"))
        }
    }

    // MARK: R1 — experimental APIs (SEC-02)

    func test_rejectsClashAPI() throws {
        let json = try loadFixture("invalid-clash-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("clash_api"))
        }
    }

    func test_rejectsV2RayAPI() throws {
        let json = try loadFixture("invalid-v2ray-api")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("v2ray_api"))
        }
    }

    func test_rejectsCacheFile() throws {
        let json = try loadFixture("invalid-cache-file")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .experimentalApiEnabled("cache_file"))
        }
    }

    // MARK: SEC-06 — structure validation

    func test_malformedJSON() throws {
        let json = try loadFixture("malformed")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .malformedJSON)
        }
    }

    func test_noVLESSOutbound() throws {
        let json = try loadFixture("no-vless-outbound")
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .noVLESSOutbound)
        }
    }

    func test_missingOutbounds() throws {
        let json = "{\"outbounds\": [], \"route\": { \"final\": \"x\" }, \"experimental\": {}}"
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: json)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .missingOutbounds)
        }
    }
}
