import XCTest
import VPNCore
@testable import Shadowsocks

/// T-A2 (closes C8-007 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path.
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        host: String = "example.com",
        port: Int = 8388,
        method: String = "2022-blake3-aes-256-gcm",
        password: String = "32bytespasswordstringforss2022test"
    ) -> ParsedShadowsocks {
        return ParsedShadowsocks(
            host: host, port: port, method: method, password: password, remarks: nil
        )
    }

    func test_buildOutbound_basic_dictShape() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "ss-0")

        XCTAssertEqual(outbound["type"] as? String, "shadowsocks")
        XCTAssertEqual(outbound["tag"] as? String, "ss-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 8388)
        XCTAssertEqual(outbound["method"] as? String, "2022-blake3-aes-256-gcm")
        XCTAssertEqual(outbound["password"] as? String, "32bytespasswordstringforss2022test")
        XCTAssertEqual(outbound["network"] as? String, "tcp")
    }

    func test_buildOutbound_legacyMethod_passes() {
        let parsed = makeParsed(method: "chacha20-ietf-poly1305")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "ss-0")
        XCTAssertEqual(outbound["method"] as? String, "chacha20-ietf-poly1305")
    }

    func test_buildOutbound_customPort_propagated() {
        let parsed = makeParsed(port: 9443)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "ss-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 9443)
    }

    func test_buildOutbound_R1_noTLSBlock() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "ss-0")
        XCTAssertNil(outbound["tls"],
                     "Shadowsocks outbound MUST NOT contain tls block (encryption на уровне протокола)")
    }
}
