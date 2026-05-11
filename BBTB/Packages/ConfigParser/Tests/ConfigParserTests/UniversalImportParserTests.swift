import XCTest
@testable import ConfigParser

final class UniversalImportParserTests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func loadFixture(_ name: String, ext: String) -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")
        else {
            XCTFail("Fixture missing: \(name).\(ext)")
            return ""
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    override func setUp() {
        super.setUp()
        MockURLProtocol.responder = nil
    }

    // MARK: Test 1 — empty input

    func test_empty_throws() async {
        let parser = UniversalImportParser()
        do {
            _ = try await parser.import(rawInput: "  \n  ")
            XCTFail("Expected .empty")
        } catch let err as UniversalImportError {
            XCTAssertEqual(err, .empty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: Test 2 — single VLESS URI

    func test_singleVLESS_parses() async throws {
        let parser = UniversalImportParser()
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@host:443?security=reality&flow=xtls-rprx-vision&sni=example.com&fp=chrome&pbk=abc&sid=ef#VLESS-1"
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 1)
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)
        XCTAssertNil(result.subscriptionURL)
        if case let .supported(_, .vlessReality(parsed), _) = result.supported[0] {
            XCTAssertEqual(parsed.host, "host")
        } else {
            XCTFail("Expected .vlessReality")
        }
    }

    // MARK: Test 3 — single Trojan URI

    func test_singleTrojan_parses() async throws {
        let parser = UniversalImportParser()
        let uri = "trojan://pwd@host:443?security=tls&type=ws&path=/p&sni=example.com#Trojan-1"
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 1)
        if case let .supported(_, .trojan(parsed), _) = result.supported[0] {
            XCTAssertEqual(parsed.host, "host")
        } else {
            XCTFail("Expected .trojan")
        }
    }

    // MARK: Test 4 — single ss URI → unsupported

    func test_singleSS_unsupported() async throws {
        let parser = UniversalImportParser()
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host:8388#SS-Test"
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 0)
        XCTAssertEqual(result.unsupported.count, 1)
    }

    // MARK: Test 5 — multi-line real user fixture (6 supported)

    func test_multiLine_userFixture_6supported() async throws {
        let parser = UniversalImportParser()
        let raw = loadFixture("multi-line-mixed", ext: "txt")
        let result = try await parser.import(rawInput: raw)
        XCTAssertEqual(result.supported.count, 6, "Expected 4 VLESS + 2 Trojan = 6 supported entries")
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)
    }

    // MARK: Test 6 — mix valid + garbage line → no whole-import abort

    func test_multiLine_withGarbageLine_doesNotAbort() async throws {
        let parser = UniversalImportParser()
        let raw = """
        vless://uuid@host:443?security=reality&flow=xtls-rprx-vision&sni=example.com&pbk=a&sid=b
        trojan://pwd@host2:2087?security=tls&type=ws&path=/p&sni=example.com
        hello world this is garbage
        ss://abc@host3:8388
        """
        let result = try await parser.import(rawInput: raw)
        // VLESS uuid is "uuid" not valid UUID → failed. Trojan + ss valid.
        // So actually: 1 trojan supported, 1 ss unsupported, 1 vless failed (invalid UUID),
        // 1 garbage failed.
        XCTAssertEqual(result.supported.count, 1)  // trojan
        XCTAssertEqual(result.unsupported.count, 1)  // ss
        // garbage + invalid vless UUID → failed
        XCTAssertTrue(result.failed.count >= 1)
    }

    // MARK: Test 7 — HTTPS URL with base64 response

    func test_https_base64Response() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let body = "vless://550e8400-e29b-41d4-a716-446655440000@host:443?security=reality&flow=xtls-rprx-vision&sni=example.com&pbk=a&sid=b\ntrojan://pwd@host2:2087?security=tls&type=ws&path=/p&sni=example.com"
        let base64 = Data(body.utf8).base64EncodedString()
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(base64.utf8), resp)
        }
        let result = try await parser.import(rawInput: "https://example.com/sub")
        XCTAssertEqual(result.supported.count, 2)
        XCTAssertNotNil(result.subscriptionURL)
        if case .subscriptionURL = result.source {
            // OK
        } else {
            XCTFail("Expected source=.subscriptionURL")
        }
    }

    // MARK: Test 8 — HTTPS URL with sing-box JSON response

    func test_https_singBoxJSONResponse() async throws {
        let parser = UniversalImportParser(session: makeSession())
        let jsonStr = loadFixture("sub-json-response", ext: "json")
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(jsonStr.utf8), resp)
        }
        let result = try await parser.import(rawInput: "https://example.com/json")
        // sub-json-response.json has vless + trojan outbound (selector/direct skipped).
        XCTAssertEqual(result.supported.count, 2)
    }

    // MARK: Test 9 — HTTPS URL with v2ray JSON → throws

    func test_https_v2rayJSONResponse_throws() async {
        let parser = UniversalImportParser(session: makeSession())
        let v2ray = "{\"outbounds\":[{\"protocol\":\"vless\",\"settings\":{}}]}"
        MockURLProtocol.responder = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: "HTTP/1.1", headerFields: [:])!
            return (Data(v2ray.utf8), resp)
        }
        do {
            _ = try await parser.import(rawInput: "https://example.com/v2")
            XCTFail("Expected .v2rayJSONUnsupported")
        } catch let err as UniversalImportError {
            XCTAssertEqual(err, .v2rayJSONUnsupported)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: Test 10 — trailing whitespace

    func test_singleURI_withWhitespace_trimmed() async throws {
        let parser = UniversalImportParser()
        let uri = "  trojan://pwd@host:443?security=tls#X\n  "
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 1)
    }

    // MARK: Test 11 — base64-encoded URI list directly in pasteboard

    func test_base64InPasteboard_decoded() async throws {
        let parser = UniversalImportParser()
        let raw = "trojan://pwd@host:443?security=tls#X\nvless://550e8400-e29b-41d4-a716-446655440000@host2:443?security=reality&flow=xtls-rprx-vision&sni=example.com&pbk=a&sid=b"
        let base64 = Data(raw.utf8).base64EncodedString()
        let result = try await parser.import(rawInput: base64)
        XCTAssertEqual(result.supported.count, 2)
    }
}
