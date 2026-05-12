import XCTest
@testable import ConfigParser

/// PROTO-04 — Shadowsocks (SIP002 + SIP022) URI parser tests.
///
/// Plan 04-03 GREEN: dual-decoder (percent-encoded + base64url) + 8-method whitelist.
/// Покрывает SS-2022 (SIP022 percent-encoded и legacy SIP002 base64url variants),
/// Outline access keys (D-11 — same parser), unsupported method routing, malformed input.
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

    /// Fixture: `ss://base64(2022-blake3-aes-128-gcm:YctPFistexppl1SQfixture)@example.com:8388#...`
    func test_2022_base64_parses() throws {
        let uri = loadFixture("ss-2022-aes-128-gcm").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try ShadowsocksURIParser.parse(uri)
        XCTAssertEqual(parsed.method, "2022-blake3-aes-128-gcm")
        XCTAssertEqual(parsed.host, "example.com")
        XCTAssertEqual(parsed.port, 8388)
        XCTAssertEqual(parsed.password, "YctPFistexppl1SQfixture")
        XCTAssertEqual(parsed.remarks, "SS-2022 AES-128-GCM")
    }

    // MARK: PROTO-04 — SIP022 percent-encoded userinfo (AEAD-2022 strict)

    /// Fixture: `ss://2022-blake3-aes-256-gcm:YctP%2BFixt...%3D@vpn.test:8388#...`
    func test_2022_percentEncoded_parses() throws {
        let uri = loadFixture("ss-2022-percent-encoded").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try ShadowsocksURIParser.parse(uri)
        XCTAssertEqual(parsed.method, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(parsed.host, "vpn.test")
        XCTAssertEqual(parsed.port, 8388)
        XCTAssertEqual(parsed.password, "YctP+FixtUreSecre7P4ssw0rdBaSe64Equ=")
        XCTAssertEqual(parsed.remarks, "SS-2022 AES-256-GCM pct")
    }

    // MARK: PROTO-04 — legacy AEAD method via base64url userinfo

    /// Fixture: `ss://base64(chacha20-ietf-poly1305:legacySSpasswordFixture)@legacy.example.com:8388#...`
    func test_legacy_chacha20_parses() throws {
        let uri = loadFixture("ss-legacy-chacha20").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try ShadowsocksURIParser.parse(uri)
        XCTAssertEqual(parsed.method, "chacha20-ietf-poly1305")
        XCTAssertEqual(parsed.host, "legacy.example.com")
        XCTAssertEqual(parsed.port, 8388)
        XCTAssertEqual(parsed.password, "legacySSpasswordFixture")
        XCTAssertEqual(parsed.remarks, "Legacy SS chacha20")
    }

    // MARK: D-11 — Outline access keys = SIP002 ss:// (single parser)

    /// Fixture: `ss://base64(chacha20-ietf-poly1305:outlineFixturePassword123)@outline.example.com:443#...`
    func test_outlineAccessKey_parses() throws {
        let uri = loadFixture("outline-access-key").trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = try ShadowsocksURIParser.parse(uri)
        // D-11 — Outline = чистый SIP002, парсится тем же handler-ом.
        XCTAssertEqual(parsed.method, "chacha20-ietf-poly1305")
        XCTAssertEqual(parsed.host, "outline.example.com")
        XCTAssertEqual(parsed.port, 443)
        XCTAssertEqual(parsed.password, "outlineFixturePassword123")
        XCTAssertEqual(parsed.remarks, "Outline Test Server")
    }

    // MARK: PROTO-04 — unknown method → throws unsupportedMethod

    /// `aes-128-cfb` — stream cipher, выкошенный в 2017. T-04-03-01 mitigation:
    /// whitelist-rejection ДО передачи в pool builder.
    func test_unknownMethod_unsupported() throws {
        // percent-encoded path попадает на whitelist check: `aes-128-cfb` не в whitelist'е →
        // path 1 falls through → path 2 (base64url decode) — `aes-128-cfb:pwd` НЕ валидный
        // base64 → throws malformedUserinfo. Поэтому используем base64-encoded URI для
        // воспроизведения «successful decode + unsupported method» сценария.
        // base64("aes-128-cfb:pwd") = "YWVzLTEyOC1jZmI6cHdk"
        let uri = "ss://YWVzLTEyOC1jZmI6cHdk@host:8388#stream-cfb"
        XCTAssertThrowsError(try ShadowsocksURIParser.parse(uri)) { err in
            guard let ssErr = err as? ShadowsocksURIError,
                  case let .unsupportedMethod(method) = ssErr
            else {
                XCTFail("Expected ShadowsocksURIError.unsupportedMethod, got \(err)")
                return
            }
            XCTAssertEqual(method, "aes-128-cfb")
        }
    }

    // MARK: malformed URI / userinfo rejection

    func test_malformedURI_throws() throws {
        // Нет userinfo вовсе.
        XCTAssertThrowsError(try ShadowsocksURIParser.parse("ss://host:8388")) { err in
            XCTAssertTrue(err is ShadowsocksURIError, "Got: \(err)")
        }
        // Полный мусор — не URI.
        XCTAssertThrowsError(try ShadowsocksURIParser.parse("definitely not a uri"))
        // Wrong scheme.
        XCTAssertThrowsError(try ShadowsocksURIParser.parse("trojan://pwd@host:443"))
        // Нет порта.
        XCTAssertThrowsError(try ShadowsocksURIParser.parse("ss://YWVzLTI1Ni1nY206cHdk@host#no-port")) { err in
            XCTAssertTrue(err is ShadowsocksURIError, "Got: \(err)")
        }
        // userinfo не парсится ни percent-encoded, ни base64url → malformedUserinfo.
        // "abc" (length 3) → padded "abc=" → base64 → 2 bytes без `:` → throws malformedUserinfo.
        XCTAssertThrowsError(try ShadowsocksURIParser.parse("ss://abc@host:8388")) { err in
            XCTAssertEqual(err as? ShadowsocksURIError, .malformedUserinfo)
        }
    }

    // MARK: Whitelist coverage

    /// Все 8 поддерживаемых методов парсятся без ошибки (через base64url userinfo).
    func test_allWhitelistMethods_parse() throws {
        let methods = [
            "2022-blake3-aes-128-gcm",
            "2022-blake3-aes-256-gcm",
            "2022-blake3-chacha20-poly1305",
            "aes-128-gcm",
            "aes-192-gcm",
            "aes-256-gcm",
            "chacha20-ietf-poly1305",
            "xchacha20-ietf-poly1305",
        ]
        for method in methods {
            let userinfo = "\(method):somepwd"
            let b64 = Data(userinfo.utf8).base64EncodedString()
            let uri = "ss://\(b64)@host:8388#test"
            let parsed = try ShadowsocksURIParser.parse(uri)
            XCTAssertEqual(parsed.method, method)
            XCTAssertEqual(parsed.password, "somepwd")
        }
    }
}
