import XCTest
import PacketTunnelKit
@testable import ConfigParser

/// W5.T1 — End-to-end integration tests covering 3 import variants + R1 validation.
/// Mocked URLSession via MockURLProtocol (no live network).
final class IntegrationTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func loadFixture(_ name: String, ext: String) -> Data {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture missing: \(name).\(ext)")
            return Data()
        }
        return (try? Data(contentsOf: url)) ?? Data()
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.responder = nil
    }

    private func extractParsed(from result: ImportResult) -> [AnyParsedConfig] {
        result.supported.compactMap { server in
            if case let .supported(_, parsed, _) = server { return parsed }
            return nil
        }
    }

    // MARK: Variant 1 — Subscription URL (base64 + plaintext + JSON responses)

    /// Test 1: subscription URL returning base64-encoded URI list (user fixture sanitized).
    func test_variant1_subscriptionURL_base64() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let body = loadFixture("sub-base64-response", ext: "txt")
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        let result = try await parser.import(rawInput: "https://vpn.example.ru/sub/token")
        XCTAssertEqual(result.supported.count, 2)
        XCTAssertNotNil(result.subscriptionURL)

        let configs = extractParsed(from: result)
        let pool = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: pool))
    }

    /// Test 2: subscription URL returning plain-text URI list (real user 6 URIs sanitized).
    func test_variant1_subscriptionURL_plaintext() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let body = loadFixture("sub-plaintext-response", ext: "txt")
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        let result = try await parser.import(rawInput: "https://vpn.example.ru/sub/token")
        XCTAssertEqual(result.supported.count, 6, "4 VLESS + 2 Trojan = 6 supported")

        let configs = extractParsed(from: result)
        let pool = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: pool))
    }

    // MARK: Variant 2 — Multi-line plain-text paste

    func test_variant2_multilinePaste() async throws {
        let parser = UniversalImportParser()
        // Reuse fixture as if pasted directly (no HTTP).
        let body = loadFixture("sub-plaintext-response", ext: "txt")
        let raw = String(data: body, encoding: .utf8) ?? ""

        let result = try await parser.import(rawInput: raw, source: .pasteboard)
        XCTAssertEqual(result.supported.count, 6)
        XCTAssertNil(result.subscriptionURL, "Multi-line paste does not have subscription URL metadata")
    }

    // MARK: Variant 3 — JSON endpoint

    func test_variant3_jsonEndpoint() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let body = loadFixture("sub-json-response", ext: "json")
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (body, resp)
        }
        let result = try await parser.import(rawInput: "https://1.2.3.4:24527/json/path/token")
        // sub-json-response.json has vless + trojan + selector + direct outbounds;
        // selector/direct are skipped, so 2 supported.
        XCTAssertEqual(result.supported.count, 2)

        let configs = extractParsed(from: result)
        let pool = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: pool))
    }

    // MARK: Variant 3 invalid — R1 rejection

    func test_variant3_invalidJSON_R1Rejection() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let maliciousJSON = """
        {
          "inbounds": [{"type": "socks", "listen": "127.0.0.1", "listen_port": 1080}],
          "outbounds": [{"type": "vless", "tag": "v", "server": "x", "server_port": 443, "uuid": "550e8400-e29b-41d4-a716-446655440000"}],
          "route": {"final": "v"},
          "experimental": {}
        }
        """.data(using: .utf8)!
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (maliciousJSON, resp)
        }
        // UniversalImportParser returns supported parsed configs; R1 check happens
        // when consumer (ConfigImporter) builds pool — at PoolBuilder + validate.
        // For this test we just verify validate rejects.
        let result = try await parser.import(rawInput: "https://example.com/json")
        XCTAssertEqual(result.supported.count, 1)

        // Now if operator tries to pass this malicious config directly to validate:
        let raw = String(data: maliciousJSON, encoding: .utf8)!
        XCTAssertThrowsError(try SingBoxConfigLoader.validate(json: raw)) { err in
            XCTAssertEqual(err as? SingBoxConfigError, .forbiddenInboundType("socks"))
        }
    }
}
