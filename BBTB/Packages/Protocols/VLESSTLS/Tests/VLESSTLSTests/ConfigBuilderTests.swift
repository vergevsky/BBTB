import XCTest
import PacketTunnelKit
@testable import VLESSTLS

final class ConfigBuilderTests: XCTestCase {

    private func defaultInputs(
        host: String = "example.com",
        port: Int = 443,
        flow: String? = nil,
        sni: String = "vpn.example.ru",
        fingerprint: String = "chrome"
    ) -> ConfigBuilder.VLESSTLSInputs {
        ConfigBuilder.VLESSTLSInputs(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD")!,
            host: host, port: port, flow: flow, sni: sni,
            fingerprint: fingerprint, alpn: ["h2", "http/1.1"], remark: nil
        )
    }

    // MARK: All placeholders substituted + validate passes (R1 self-test)

    func test_buildsConfigWithoutPlaceholders() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${VLESS_UUID}"))
        XCTAssertFalse(json.contains("${VLESS_FLOW}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("vpn.example.ru"))
        XCTAssertTrue(json.contains("vless-out"))
        // R1 self-test — generated JSON проходит strict validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Vision flow preserved in outbound

    func test_visionFlowSet() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(flow: "xtls-rprx-vision"))
        XCTAssertTrue(json.contains("xtls-rprx-vision"))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["flow"] as? String, "xtls-rprx-vision")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: nil flow → "" в JSON, validate всё равно passes (A1 assumption)

    func test_nilFlow_handled() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(flow: nil))
        XCTAssertFalse(json.contains("${VLESS_FLOW}"))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["flow"] as? String, "")
        // A1 assumption — пустой flow legal для sing-box VLESS outbound (server без Vision).
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Custom port mutated

    func test_customPort() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 8443))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 8443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: R1 invariant — insecure: false hardcoded в template

    func test_insecureIsFalse_R1() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false, "R1: VLESS+TLS strict TLS (no D-08 exception)")
        XCTAssertNil(tls["reality"], "VLESS+TLS template MUST NOT contain reality block")
    }

    // MARK: Invalid port throws

    func test_invalidPort_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 0))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(0))
        }
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 70000))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(70000))
        }
    }

    // MARK: Empty SNI throws (R1 invariant)

    func test_emptySNI_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(sni: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingSNI)
        }
    }
}
