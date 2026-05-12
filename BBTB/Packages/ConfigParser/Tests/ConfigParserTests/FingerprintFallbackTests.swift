import XCTest
@testable import ConfigParser

final class FingerprintFallbackTests: XCTestCase {
    func test_emptyFp_defaultsToChrome() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "chrome")
    }
    func test_whitespaceFp_defaultsToChrome() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=%20#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "chrome")
    }
    func test_explicitFp_preserved() throws {
        let uri = "trojan://pwd@h.com:443?security=tls&type=tcp&sni=h.com&fp=firefox#R"
        let p = try TrojanURIParser.parse(uri)
        XCTAssertEqual(p.fingerprint, "firefox")
    }
}
