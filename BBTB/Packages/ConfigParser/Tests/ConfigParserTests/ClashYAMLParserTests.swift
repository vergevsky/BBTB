import XCTest
@testable import ConfigParser

/// IMP-05 — Clash YAML subscription parser tests.
///
/// Wave 0 (Plan 04-01): этот файл создан как RED-scaffold. Все test methods —
/// XCTFail placeholders. Plan 04-05 заменит placeholders на реальные assertions
/// и реализует `ClashYAMLParser.parse(_:) throws -> [ImportedServer]` через
/// Yams 6.2.1 (`Yams.load` → `[String: Any]` → manual cast), per 04-RESEARCH.md
/// Pattern 4.
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

    // MARK: IMP-05 — proxies: extraction

    func test_extractsProxies() throws {
        XCTFail("Pending Plan 04-05: ClashYAMLParser.parse(clash-mixed-proxies.yaml) → ≥6 ImportedServer entries")
    }

    // MARK: IMP-05 — mixed types correctly classified

    func test_mixedProxies_classifiedCorrectly() throws {
        XCTFail("Pending Plan 04-05: clash-mixed-proxies.yaml → ss/trojan/hysteria2/vless-reality/vless-tls → .supported; vmess → .unsupported")
    }

    // MARK: A6 — broken YAML returns empty array (или throws → empty handled gracefully)

    func test_brokenYAML_returnsEmpty() throws {
        XCTFail("Pending Plan 04-05: ClashYAMLParser.parse(\"not: valid: yaml: :\") → returns [] (A6 verified — Yams throws, handler catches)")
    }

    // MARK: Pitfall 4 — alpn поле в Clash YAML: string vs array

    func test_alpnStringVsArray_handled() throws {
        XCTFail("Pending Plan 04-05: alpn как YAML array (`- h2`) и как single string (`alpn: h2`) — оба → ParsedVLESSTLS.alpn = [\"h2\"]")
    }
}
