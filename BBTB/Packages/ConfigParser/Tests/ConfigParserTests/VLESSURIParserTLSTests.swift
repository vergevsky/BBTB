import XCTest
@testable import ConfigParser

/// PROTO-03 — VLESS+TLS (без Reality) parser tests.
///
/// Wave 0 (Plan 04-01): этот файл создан как RED-scaffold. Все test methods —
/// XCTFail placeholders. Plan 04-02 заменит placeholders на реальные assertions
/// и расширит `VLESSURIParser.parse(_:) throws -> AnyParsedConfig` веткой D-02
/// (Reality detection vs `security=tls` branch → `ParsedVLESSTLS`).
///
/// Note: `ParsedVLESSTLS` уже определён в Plan 04-01 (Task 1). Placeholder
/// может ссылаться на тип, но parser изменения — Plan 04-02.
final class VLESSURIParserTLSTests: XCTestCase {

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

    // MARK: D-02 — security=tls без pbk → AnyParsedConfig.vlessTLS

    func test_securityTLS_returnsVlessTLS() throws {
        XCTFail("Pending Plan 04-02: VLESSURIParser.parse(vless-tls-no-flow.txt) → AnyParsedConfig.vlessTLS(ParsedVLESSTLS) — security=tls + нет pbk → TLS branch")
    }

    // MARK: D-02 — Vision flow сохраняется в ParsedVLESSTLS.flow

    func test_visionFlow_preserved() throws {
        XCTFail("Pending Plan 04-02: vless-tls-vision.txt → ParsedVLESSTLS.flow == \"xtls-rprx-vision\"")
    }

    // MARK: D-02 — нет flow → ParsedVLESSTLS.flow == nil

    func test_noFlow_nilField() throws {
        XCTFail("Pending Plan 04-02: vless-tls-no-flow.txt → ParsedVLESSTLS.flow == nil (NOT empty string)")
    }

    // MARK: D-02 — security=reality + extra TLS markers → Reality precedence (НЕ TLS branch)

    func test_realityWithExtraTLS_returnsReality() throws {
        XCTFail("Pending Plan 04-02: vless://...?security=reality&pbk=abc&... → .vlessReality (приоритет pbk над любыми TLS-маркерами per D-02)")
    }
}
