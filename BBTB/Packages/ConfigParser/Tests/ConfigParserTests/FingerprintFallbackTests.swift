import XCTest
@testable import ConfigParser

/// Phase 7a Wave 2 — DPI-01 smart default: пустой `fp=` → "random" (было "chrome" в Phase 2/4).
final class FingerprintFallbackTests: XCTestCase {
    func test_emptyFp_defaultsToRandom() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "random", "Phase 7a Wave 2 — DPI-01 smart default")
    }
    func test_whitespaceFp_defaultsToRandom() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=%20#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "random", "Phase 7a Wave 2 — DPI-01 smart default")
    }
    func test_explicitFp_preserved() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=firefox#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "firefox")
    }

    /// Phase 7a Wave 2 — URI override `fp=chrome` honoured даже после default-смены на random.
    func test_explicitChrome_preserved() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=chrome#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "chrome", "URI override переопределяет smart default")
    }
}
