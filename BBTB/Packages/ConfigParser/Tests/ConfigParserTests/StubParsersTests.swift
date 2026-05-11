import XCTest
@testable import ConfigParser

final class StubParsersTests: XCTestCase {

    private func loadFixture(_ name: String) -> String {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: nil)
            ?? bundle.url(forResource: name, withExtension: "txt", subdirectory: "Fixtures")
        else {
            XCTFail("Fixture not found: \(name).txt")
            return ""
        }
        return ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func test_ss_parsesAsUnsupported() {
        let result = StubParsers.parseAsUnsupported(loadFixture("unsupported-ss-uri"))
        if case let .unsupported(name, scheme, host, port, _, reason) = result {
            XCTAssertEqual(scheme, "ss")
            XCTAssertEqual(host, "example.com")
            XCTAssertEqual(port, 8388)
            XCTAssertEqual(reason, .schemaUnsupportedInPhase2)
            XCTAssertEqual(name, "Test Server")
        } else {
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    func test_vmess_parsesAsUnsupported() {
        let result = StubParsers.parseAsUnsupported(loadFixture("unsupported-vmess-uri"))
        if case let .unsupported(_, scheme, _, _, _, reason) = result {
            XCTAssertEqual(scheme, "vmess")
            XCTAssertEqual(reason, .schemaUnsupportedInPhase2)
        } else {
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    func test_hy2_parsesAsUnsupported() {
        let result = StubParsers.parseAsUnsupported(loadFixture("unsupported-hy2-uri"))
        if case let .unsupported(_, scheme, _, _, _, _) = result {
            XCTAssertEqual(scheme, "hy2")
        } else {
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    func test_wireguard_parsesAsUnsupported() {
        let result = StubParsers.parseAsUnsupported(loadFixture("unsupported-wireguard-uri"))
        if case let .unsupported(_, scheme, _, port, _, _) = result {
            XCTAssertEqual(scheme, "wireguard")
            XCTAssertEqual(port, 51820)
        } else {
            XCTFail("Expected .unsupported, got \(result)")
        }
    }

    func test_malformedURI_returnsInvalid() {
        let result = StubParsers.parseAsUnsupported("???")
        if case .invalid = result {
            // expected
        } else {
            XCTFail("Expected .invalid, got \(result)")
        }
    }

    func test_uriWithoutHost_returnsInvalid() {
        let result = StubParsers.parseAsUnsupported("vmess://")
        if case .invalid = result {
            // expected
        } else {
            XCTFail("Expected .invalid, got \(result)")
        }
    }

    func test_cyrillicRemark_extracted() {
        let result = StubParsers.parseAsUnsupported("ss://abc@host:8388#%D0%92%D0%9C%D0%B5%D1%81%D1%82")
        if case let .unsupported(name, _, _, _, _, _) = result {
            XCTAssertEqual(name, "ВМест")
        } else {
            XCTFail("Expected .unsupported, got \(result)")
        }
    }
}
