import XCTest
@testable import ConfigParser

/// PROTO-05 — Hysteria2 (hy2:// + hysteria2://) URI parser tests.
///
/// Wave 0 (Plan 04-01): этот файл создан как RED-scaffold. Все test methods —
/// XCTFail placeholders. Plan 04-04 заменит placeholders на реальные assertions
/// и реализует `Hysteria2URIParser.parse(_:) throws -> ParsedHysteria2`
/// per 04-RESEARCH.md Pattern 1 (Hysteria2 example), включая D-08 (insecure=1
/// R1 exception) и D-09 (multi-port reject).
final class Hysteria2URIParserTests: XCTestCase {

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

    // MARK: D-09 — оба URI scheme aliases работают

    func test_bothSchemes_parse() throws {
        XCTFail("Pending Plan 04-04: Hysteria2URIParser.parse(hy2://...) === Hysteria2URIParser.parse(hysteria2://...) (same ParsedHysteria2 fields)")
    }

    // MARK: D-08 — insecure=1 → allowInsecure=true (R1 EXCEPTION только для Hysteria2)

    func test_insecureFlag_setsAllowInsecure() throws {
        XCTFail("Pending Plan 04-04: hy2-insecure.txt → ParsedHysteria2.allowInsecure == true (D-08 R1 EXCEPTION)")
    }

    // MARK: D-09 — multi-port (443,8443) throws multiPortNotSupported

    func test_multiPort_rejects() throws {
        XCTFail("Pending Plan 04-04: hy2-multi-port.txt → Hysteria2URIError.multiPortNotSupported (D-09: sing-box один порт)")
    }

    // MARK: PROTO-05 — obfs=salamander valid

    func test_obfsSalamander_parses() throws {
        XCTFail("Pending Plan 04-04: hy2-with-obfs.txt → ParsedHysteria2.obfs == \"salamander\", obfsPassword extracted")
    }

    // MARK: PROTO-05 — obfs не salamander → throws unsupportedObfs

    func test_obfsNotSalamander_throws() throws {
        XCTFail("Pending Plan 04-04: hy2://...?obfs=xxx → Hysteria2URIError.unsupportedObfs (\"salamander\" only supported)")
    }
}
