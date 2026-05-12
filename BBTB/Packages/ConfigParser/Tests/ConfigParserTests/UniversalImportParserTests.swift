import XCTest
import VPNCore
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

    // MARK: Test 4 — single ss URI with supported method → supported (Phase 4 Plan 03)

    /// Phase 4 Plan 03 changes the contract: `aes-256-gcm` входит в `ShadowsocksURIParser.supportedSSMethods`,
    /// поэтому `ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host:8388` (base64 от `aes-256-gcm:password`)
    /// теперь маршрутизируется в `.supported(.shadowsocks(...))`. До Plan 03 фаза 2 ставила всё `ss://`
    /// в `.unsupported` (stub-parser); этот тест отслеживает сдвиг behavior'а.
    func test_singleSS_supported() async throws {
        let parser = UniversalImportParser()
        let uri = "ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ=@host:8388#SS-Test"
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 1)
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)
        if case let .supported(name, parsed, _) = result.supported[0] {
            XCTAssertEqual(name, "SS-Test")
            if case let .shadowsocks(ss) = parsed {
                XCTAssertEqual(ss.method, "aes-256-gcm")
                XCTAssertEqual(ss.host, "host")
                XCTAssertEqual(ss.port, 8388)
                XCTAssertEqual(ss.password, "password")
            } else {
                XCTFail("Expected .shadowsocks AnyParsedConfig, got \(parsed)")
            }
        } else {
            XCTFail("Expected .supported ImportedServer")
        }
    }

    // MARK: Test 4b — ss URI with rejected (whitelist-miss) method → unsupported

    /// `aes-128-cfb` — stream cipher, отвергнутый whitelist'ом (T-04-03-01 mitigation).
    func test_singleSS_unsupportedMethod_routedToUnsupported() async throws {
        let parser = UniversalImportParser()
        // base64("aes-128-cfb:pwd") = "YWVzLTEyOC1jZmI6cHdk"
        let uri = "ss://YWVzLTEyOC1jZmI6cHdk@host:8388#SS-stream"
        let result = try await parser.import(rawInput: uri)
        XCTAssertEqual(result.supported.count, 0)
        XCTAssertEqual(result.unsupported.count, 1)
        XCTAssertEqual(result.failed.count, 0)
        if case let .unsupported(_, _, _, _, _, reason) = result.unsupported[0] {
            XCTAssertEqual(reason, .unsupportedSSMethod)
        } else {
            XCTFail("Expected .unsupported ImportedServer")
        }
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
        // Phase 4 Plan 03 — ss://abc@host3:8388 userinfo "abc" is not valid base64url
        // (padded "abc=" decodes to 2 bytes без `:`) и не parses как percent-encoded
        // method:password → throws malformedUserinfo → .failed (not .unsupported).
        // VLESS uuid="uuid" not valid UUID → failed.
        // Trojan valid → supported. Garbage line + invalid VLESS + malformed SS → failed.
        XCTAssertEqual(result.supported.count, 1)  // trojan
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertTrue(result.failed.count >= 2, "Expected >=2 failed entries; got \(result.failed.count)")
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

    // MARK: Plan 04-05 — Clash YAML detection branch (D-13)

    /// Body starting с `proxies:` — должен classify в .clashYAML.
    func test_classify_clashYAML() async {
        let parser = UniversalImportParser()
        let body = """
        proxies:
          - name: test
            type: ss
            server: example.com
            port: 8388
            cipher: aes-256-gcm
            password: pwd
        """
        let cls = await parser.classify(body.trimmingCharacters(in: .whitespacesAndNewlines))
        if case .clashYAML = cls {
            // OK
        } else {
            XCTFail("Expected .clashYAML, got \(cls)")
        }
    }

    /// Body с `mixed-port:` / `allow-lan:` markers — также classify в .clashYAML.
    func test_classify_yamlMarkers() async {
        let parser = UniversalImportParser()
        let body = """
        mixed-port: 7890
        allow-lan: false
        proxies:
          - name: test
            type: ss
            server: example.com
            port: 8388
            cipher: aes-256-gcm
            password: pwd
        """
        let cls = await parser.classify(body.trimmingCharacters(in: .whitespacesAndNewlines))
        if case .clashYAML = cls {
            // OK
        } else {
            XCTFail("Expected .clashYAML for mixed-port: marker, got \(cls)")
        }
    }

    // MARK: Plan 04-05 — Clash YAML end-to-end import

    /// loadFixture clash-mixed-proxies.yaml → import → supported.count >= 5, unsupported.count >= 1.
    func test_import_clashYAML_endToEnd() async throws {
        let parser = UniversalImportParser()
        let body = loadFixture("clash-mixed-proxies", ext: "yaml")
        XCTAssertFalse(body.isEmpty, "Fixture must load")
        let result = try await parser.import(rawInput: body)
        XCTAssertGreaterThanOrEqual(result.supported.count, 5,
                                    "Expected ≥5 supported (ss + trojan + hysteria2 + vless-reality + vless-tls); got \(result.supported.count)")
        XCTAssertGreaterThanOrEqual(result.unsupported.count, 1,
                                    "Expected ≥1 unsupported (vmess); got \(result.unsupported.count)")
        // failed должен быть пустым — Clash YAML body не throws на per-proxy errors.
        XCTAssertEqual(result.failed.count, 0)
    }

    /// Broken Clash YAML body → routing в .failed (не throws на весь import).
    func test_clashYAML_with_brokenYAML() async throws {
        let parser = UniversalImportParser()
        // YAML с unclosed flow-style — Yams.load либо throws, либо возвращает nil cast.
        // Body начинается с `proxies:` (classify → .clashYAML branch), затем broken syntax.
        let body = """
        proxies:
          - name: bad
            type: ss
            server: [unclosed
        """
        let result = try await parser.import(rawInput: body)
        // Один из двух acceptable scenarios:
        //   (a) Yams throws → result.failed = 1; supported=unsupported=0
        //   (b) Yams partially parses → bad proxy skipped → empty results
        XCTAssertEqual(result.supported.count, 0)
        XCTAssertTrue(result.failed.count >= 1 || (result.unsupported.count == 0 && result.failed.count == 0),
                      "Broken YAML → либо failed != empty, либо empty results (graceful)")
    }

    // MARK: Plan 04-05 — IMP-04 integration: все 5 URI schemes маршрутизируются

    /// IMP-04 finish — все 5 schemes (vless/trojan/ss/hy2/hysteria2) → .supported с правильным parsed case.
    func test_routes_all_phase4_protocols() async throws {
        let parser = UniversalImportParser()

        // 1. VLESS+TLS (Plan 04-02 fixture)
        let vlessBody = loadFixture("vless-tls-no-flow", ext: "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let vlessResult = try await parser.import(rawInput: vlessBody)
        XCTAssertEqual(vlessResult.supported.count, 1, "VLESS+TLS должен быть supported")
        if case .supported(_, .vlessTLS, _) = vlessResult.supported[0] {
            // OK
        } else {
            XCTFail("Expected .vlessTLS, got \(vlessResult.supported[0])")
        }

        // 2. Trojan (Phase 2 fixture)
        let trojanBody = loadFixture("trojan-tcp-uri", ext: "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let trojanResult = try await parser.import(rawInput: trojanBody)
        XCTAssertEqual(trojanResult.supported.count, 1, "Trojan должен быть supported")
        if case .supported(_, .trojan, _) = trojanResult.supported[0] {
            // OK
        } else {
            XCTFail("Expected .trojan, got \(trojanResult.supported[0])")
        }

        // 3. Shadowsocks (Plan 04-03 fixture — SS-2022 AES-128-GCM)
        let ssBody = loadFixture("ss-2022-aes-128-gcm", ext: "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let ssResult = try await parser.import(rawInput: ssBody)
        XCTAssertEqual(ssResult.supported.count, 1, "Shadowsocks должен быть supported")
        if case let .supported(_, .shadowsocks(ss), _) = ssResult.supported[0] {
            XCTAssertEqual(ss.method, "2022-blake3-aes-128-gcm")
        } else {
            XCTFail("Expected .shadowsocks, got \(ssResult.supported[0])")
        }

        // 4. Hysteria2 (hy2:// scheme — Plan 04-04 fixture с obfs)
        let hy2Body = loadFixture("hy2-with-obfs", ext: "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let hy2Result = try await parser.import(rawInput: hy2Body)
        XCTAssertEqual(hy2Result.supported.count, 1, "Hysteria2 (hy2://) должен быть supported")
        if case .supported(_, .hysteria2, _) = hy2Result.supported[0] {
            // OK
        } else {
            XCTFail("Expected .hysteria2, got \(hy2Result.supported[0])")
        }

        // 5. Hysteria2 long scheme (hysteria2://) — inline URI чтобы покрыть D-09 dual scheme
        let hysteria2URI = "hysteria2://fictionalAuth@example.com:443?sni=example.com#Hysteria2-long-scheme"
        let hysteria2Result = try await parser.import(rawInput: hysteria2URI)
        XCTAssertEqual(hysteria2Result.supported.count, 1, "hysteria2:// (long scheme) должен быть supported")
        if case .supported(_, .hysteria2, _) = hysteria2Result.supported[0] {
            // OK
        } else {
            XCTFail("Expected .hysteria2 for long-scheme URI, got \(hysteria2Result.supported[0])")
        }
    }

    // MARK: Plan 04-05 — IMP-05 integration: Outline access keys через ss:// path

    /// IMP-05 finish — Outline access key (стандартный SIP002 ss://) → .shadowsocks.
    func test_outlineAccessKey_routes_ss() async throws {
        let parser = UniversalImportParser()
        let body = loadFixture("outline-access-key", ext: "txt").trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await parser.import(rawInput: body)
        XCTAssertEqual(result.supported.count, 1, "Outline access key должен parse в supported .shadowsocks")
        XCTAssertEqual(result.unsupported.count, 0)
        XCTAssertEqual(result.failed.count, 0)
        if case let .supported(_, .shadowsocks(ss), _) = result.supported[0] {
            // Outline = legacy SS (chacha20-ietf-poly1305 в нашем fixture).
            XCTAssertTrue(ShadowsocksURIParser.supportedSSMethods.contains(ss.method),
                          "Outline method '\(ss.method)' must be in whitelist")
        } else {
            XCTFail("Expected .shadowsocks for Outline access key, got \(result.supported[0])")
        }
    }
}
