import XCTest
@testable import ConfigParser

/// PROTO-04 — Shadowsocks (SIP002 + SIP022) URI parser tests.
///
/// Wave 0 (Plan 04-01): этот файл создан как RED-scaffold. Все test methods —
/// XCTFail placeholders. Plan 04-03 заменит placeholders на реальные assertions
/// и реализует `ShadowsocksURIParser.parse(_:) throws -> ParsedShadowsocks` +
/// dual-decoder (base64url SIP002 + percent-encoded SIP022) per 04-RESEARCH.md
/// Example 2 / Pitfall 1.
final class ShadowsocksURIParserTests: XCTestCase {

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

    // MARK: PROTO-04 — SIP002 base64url userinfo (legacy + 2022-blake3 fallback)

    func test_2022_base64_parses() throws {
        XCTFail("Pending Plan 04-03: ShadowsocksURIParser.parse(ss-2022-aes-128-gcm.txt) → ParsedShadowsocks with method=2022-blake3-aes-128-gcm")
    }

    // MARK: PROTO-04 — SIP022 percent-encoded userinfo (AEAD-2022 strict)

    func test_2022_percentEncoded_parses() throws {
        XCTFail("Pending Plan 04-03: ShadowsocksURIParser.parse(ss-2022-percent-encoded.txt) → method=2022-blake3-aes-256-gcm")
    }

    // MARK: PROTO-04 — legacy AEAD method

    func test_legacy_chacha20_parses() throws {
        XCTFail("Pending Plan 04-03: ShadowsocksURIParser.parse(ss-legacy-chacha20.txt) → method=chacha20-ietf-poly1305")
    }

    // MARK: PROTO-04 — unknown method → throws unsupportedMethod / .unsupported via UniversalImportParser

    func test_unknownMethod_unsupported() throws {
        XCTFail("Pending Plan 04-03: ss://aes-128-cfb:pwd@h:port → ShadowsocksURIError.unsupportedMethod (aes-128-cfb not in supportedSSMethods)")
    }

    // MARK: D-11 — Outline access keys = SIP002 ss://

    func test_outlineAccessKey_parses() throws {
        XCTFail("Pending Plan 04-03: outline-access-key.txt parses через тот же ShadowsocksURIParser (D-11: no special handler нужен)")
    }

    // MARK: malformed URI rejection

    func test_malformedURI_throws() throws {
        XCTFail("Pending Plan 04-03: ss://invalid-userinfo-no-colon@h:port → ShadowsocksURIError.malformedURI / .malformedUserinfo")
    }
}
