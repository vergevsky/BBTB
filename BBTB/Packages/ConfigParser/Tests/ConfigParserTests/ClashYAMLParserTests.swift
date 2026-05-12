import XCTest
@testable import ConfigParser

/// IMP-05 / D-12 / D-13 — Clash YAML subscription parser tests.
///
/// Plan 04-05 GREEN: реальные assertions для `ClashYAMLParser.parse(_:) throws -> [ImportedServer]`
/// через Yams 6.2.1 (`Yams.load` → `[String: Any]` → manual cast).
/// Покрывает per-proxy error isolation (T-04-05-04), Pitfall 4 (alpn dual-type),
/// и mapping 6 типов из `clash-mixed-proxies.yaml`.
final class ClashYAMLParserTests: XCTestCase {

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

    // MARK: IMP-05 — proxies: extraction (Wave 0 fixture)

    func test_extractsProxies() throws {
        let body = loadFixture("clash-mixed-proxies", ext: "yaml")
        XCTAssertFalse(body.isEmpty, "Fixture clash-mixed-proxies.yaml must be non-empty")
        let results = try ClashYAMLParser.parse(body)
        // Fixture содержит 6 proxies: ss-2022, trojan, hysteria2, vmess, vless-reality, vless-tls.
        XCTAssertEqual(results.count, 6, "Expected 6 ImportedServer entries (1 per proxy)")
        let supported = results.filter { $0.isSupportedFlag }
        let unsupported = results.filter {
            if case .unsupported = $0 { return true } else { return false }
        }
        XCTAssertEqual(supported.count, 5, "Expected 5 supported (ss/trojan/hysteria2/vless-reality/vless-tls)")
        XCTAssertEqual(unsupported.count, 1, "Expected 1 unsupported (vmess)")
    }

    // MARK: IMP-05 — mixed types correctly classified per AnyParsedConfig case

    func test_mixedProxies_classifiedCorrectly() throws {
        let body = loadFixture("clash-mixed-proxies", ext: "yaml")
        let results = try ClashYAMLParser.parse(body)
        XCTAssertEqual(results.count, 6)

        // Per-name accumulator → точное соответствие fixture (порядок не критичен).
        var byName: [String: AnyParsedConfig] = [:]
        var unsupportedSchemes: [String] = []
        for entry in results {
            if case let .supported(n, parsed, _) = entry {
                byName[n] = parsed
            } else if case let .unsupported(_, scheme, _, _, _, _) = entry {
                unsupportedSchemes.append(scheme)
            }
        }

        // SS-2022: cipher 2022-blake3-aes-256-gcm в whitelist'е → .shadowsocks
        guard case let .shadowsocks(ss) = byName["SS-2022 fixture"] else {
            return XCTFail("Expected SS-2022 fixture → .shadowsocks; got \(String(describing: byName["SS-2022 fixture"]))")
        }
        XCTAssertEqual(ss.method, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(ss.host, "ss.example.com")
        XCTAssertEqual(ss.port, 8388)

        // Trojan
        guard case let .trojan(tr) = byName["Trojan fixture"] else {
            return XCTFail("Expected Trojan fixture → .trojan")
        }
        XCTAssertEqual(tr.host, "trojan.example.com")
        XCTAssertEqual(tr.sni, "trojan.example.com")

        // Hysteria2 + skip-cert-verify: true → allowInsecure=true (D-08 R1 EXCEPTION)
        guard case let .hysteria2(hy) = byName["Hysteria2 fixture"] else {
            return XCTFail("Expected Hysteria2 fixture → .hysteria2")
        }
        XCTAssertEqual(hy.host, "hy2.example.com")
        XCTAssertTrue(hy.allowInsecure, "skip-cert-verify: true → allowInsecure=true")

        // VLESS Reality (есть reality-opts с public-key + short-id)
        guard case let .vlessReality(vr) = byName["VLESS Reality fixture"] else {
            return XCTFail("Expected VLESS Reality fixture → .vlessReality")
        }
        XCTAssertEqual(vr.publicKey, "fictionalRealityPublicKey")
        // short-id в fixture написан как unquoted `01234567` — Yams parsит как Int (octal!).
        // stringValue() normalizes; точное значение depends on Yams interpretation, главное —
        // non-empty (Reality detection требует non-empty short-id).
        XCTAssertFalse(vr.shortId.isEmpty, "Reality short-id must be non-empty")
        XCTAssertEqual(vr.flow, "xtls-rprx-vision")

        // VLESS TLS (tls: true без reality-opts)
        guard case let .vlessTLS(vt) = byName["VLESS TLS fixture"] else {
            return XCTFail("Expected VLESS TLS fixture → .vlessTLS")
        }
        XCTAssertEqual(vt.host, "tls.example.com")
        XCTAssertEqual(vt.sni, "tls.example.com")
        XCTAssertEqual(vt.alpn, ["h2", "http/1.1"], "Pitfall 4 — YAML array alpn parsed correctly")

        // VMess → unsupported
        XCTAssertTrue(unsupportedSchemes.contains("vmess"),
                      "Expected vmess in unsupported schemes; got \(unsupportedSchemes)")
    }

    // MARK: A6 — broken YAML returns empty array OR throws gracefully

    func test_brokenYAML_returnsEmpty() throws {
        // YAML с unclosed flow-style array — Yams.load обычно throws.
        // Behavior contract: ClashYAMLParser.parse либо возвращает [], либо throws.
        // Empty result and throw оба acceptable; критично что вызов не крешит и не
        // зависает. Здесь проверяем что один из двух scenario выполняется без UB.
        let broken = "this is not yaml: [unclosed"
        do {
            let results = try ClashYAMLParser.parse(broken)
            XCTAssertTrue(results.isEmpty,
                          "Broken YAML без proxies: section → empty results; got \(results.count)")
        } catch {
            // throws тоже acceptable — UniversalImportParser ловит и маршрутизирует в .failed
            // (см. routing branch в UniversalImportParser.swift).
        }
    }

    // MARK: Pitfall 4 — alpn dual-type: YAML array vs CSV string

    func test_alpnStringVsArray_handled() throws {
        // Inline YAML с двумя trojan proxies:
        //   - первый — alpn как CSV string: `alpn: "h2,http/1.1"`
        //   - второй — alpn как YAML array
        let body = """
        proxies:
          - name: "Trojan CSV"
            type: trojan
            server: csv.example.com
            port: 443
            password: fixturePwd1
            sni: csv.example.com
            alpn: "h2,http/1.1"
          - name: "Trojan Array"
            type: trojan
            server: array.example.com
            port: 443
            password: fixturePwd2
            sni: array.example.com
            alpn:
              - h2
              - http/1.1
        """
        let results = try ClashYAMLParser.parse(body)
        XCTAssertEqual(results.count, 2)

        var byName: [String: ParsedTrojan] = [:]
        for entry in results {
            if case let .supported(n, .trojan(t), _) = entry {
                byName[n] = t
            }
        }
        guard let csv = byName["Trojan CSV"], let arr = byName["Trojan Array"] else {
            return XCTFail("Both trojan entries must parse as .trojan; got \(byName.keys)")
        }
        XCTAssertEqual(csv.alpn, ["h2", "http/1.1"],
                       "Pitfall 4 — CSV alpn must split into [\"h2\", \"http/1.1\"]")
        XCTAssertEqual(arr.alpn, ["h2", "http/1.1"],
                       "Pitfall 4 — YAML array alpn must preserve as [\"h2\", \"http/1.1\"]")
    }

    // MARK: Per-proxy error isolation (T-04-05-04 mitigation)

    func test_perProxyError_isolation() throws {
        // YAML с тремя proxies:
        //   - валидный ss (cipher whitelisted)
        //   - невалидный trojan (отсутствует password — guard let fail) → skipped
        //   - валидный hysteria2 → supported
        let body = """
        proxies:
          - name: "Valid SS"
            type: ss
            server: ss.example.com
            port: 8388
            cipher: aes-256-gcm
            password: validPwd
          - name: "Bad Trojan"
            type: trojan
            server: bad.example.com
            port: 443
            sni: bad.example.com
          - name: "Valid Hy2"
            type: hysteria2
            server: hy.example.com
            port: 443
            password: hy2Auth
            sni: hy.example.com
        """
        let results = try ClashYAMLParser.parse(body)
        // Bad trojan → skipped (per-proxy guard let fail) — не throws на весь YAML.
        // Допустимо: 2 entries (skipped) ИЛИ 3 entries (bad как unsupported).
        XCTAssertGreaterThanOrEqual(results.count, 2,
                                    "Expected at least 2 entries (bad trojan может быть skipped или unsupported)")
        let supportedNames = results.compactMap { entry -> String? in
            if case let .supported(n, _, _) = entry { return n }
            return nil
        }
        XCTAssertTrue(supportedNames.contains("Valid SS"), "Valid SS must be in supported")
        XCTAssertTrue(supportedNames.contains("Valid Hy2"), "Valid Hy2 must be in supported")
    }
}
