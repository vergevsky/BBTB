import XCTest
import VPNCore
@testable import VLESSReality

/// T-A2 (closes C8-001 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path. Production
/// path: ConfigImporter → PoolBuilder.buildSingleOutboundJSON → buildSingBoxJSON(from:[parsed])
/// (dict-based, JSONSerialization-safe).
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        port: Int = 443,
        flow: String = "xtls-rprx-vision",
        publicKey: String = "abc123-base64url-key",
        shortId: String = "01234567"
    ) -> ParsedVLESS {
        return ParsedVLESS(
            uuid: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            host: "example.com",
            port: port,
            flow: flow,
            security: "reality",
            sni: "www.microsoft.com",
            publicKey: publicKey,
            shortId: shortId,
            fingerprint: "chrome",
            networkType: "tcp",
            remarks: nil
        )
    }

    func test_buildOutbound_filled_dictContainsAllFields() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-0")

        XCTAssertEqual(outbound["type"] as? String, "vless")
        XCTAssertEqual(outbound["tag"] as? String, "vless-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["uuid"] as? String, "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(outbound["flow"] as? String, "xtls-rprx-vision")
        XCTAssertEqual(outbound["network"] as? String, "tcp")

        let tls = outbound["tls"] as? [String: Any]
        XCTAssertNotNil(tls)
        XCTAssertEqual(tls?["enabled"] as? Bool, true)
        XCTAssertEqual(tls?["server_name"] as? String, "www.microsoft.com")
        let utls = tls?["utls"] as? [String: Any]
        XCTAssertEqual(utls?["fingerprint"] as? String, "chrome")
        let reality = tls?["reality"] as? [String: Any]
        XCTAssertEqual(reality?["enabled"] as? Bool, true)
        XCTAssertEqual(reality?["public_key"] as? String, "abc123-base64url-key")
        XCTAssertEqual(reality?["short_id"] as? String, "01234567")
    }

    func test_buildOutbound_emptyFlow_emittedAsEmptyString() {
        // Phase 1 W5 lesson: некоторые VLESS+Reality сервера НЕ используют Vision.
        let parsed = makeParsed(flow: "")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-0")
        XCTAssertEqual(outbound["flow"] as? String, "")
    }

    func test_buildOutbound_nonDefaultPort_propagated() {
        let parsed = makeParsed(port: 8443)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-0")
        XCTAssertEqual(outbound["server_port"] as? Int, 8443)
    }

    func test_buildOutbound_emptyPublicKey_skipsRealityBlock() {
        // T-A2: when publicKey empty, tls.reality block omitted (degradation behavior
        // documented в C8-002). PoolBuilder.isValidPoolEntry теперь rejects empty
        // publicKey before this code runs, но buildOutbound остаётся defence-in-depth
        // safe для programmatic callers.
        let parsed = makeParsed(publicKey: "")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "vless-0")
        let tls = outbound["tls"] as? [String: Any]
        XCTAssertNotNil(tls)
        XCTAssertNil(tls?["reality"])  // reality block dropped
    }
}
