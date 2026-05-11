import XCTest
import PacketTunnelKit
@testable import VLESSReality

final class ConfigBuilderTests: XCTestCase {

    func test_buildSingBoxJSON_filled_passesValidate() throws {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com",
            port: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            flow: "xtls-rprx-vision",
            sni: "www.microsoft.com",
            publicKey: "abc123-base64url-key",
            shortId: "01234567",
            fingerprint: "chrome"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        // Все placeholder'ы должны быть заменены
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${VLESS_UUID}"))
        XCTAssertFalse(json.contains("${VLESS_FLOW}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
        XCTAssertFalse(json.contains("${REALITY_PUBLIC_KEY}"))
        XCTAssertFalse(json.contains("${REALITY_SHORT_ID}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("vless-out"))  // DNS detour resolved
        // Контентные проверки
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("550e8400-e29b-41d4-a716-446655440000"))
        XCTAssertTrue(json.contains("www.microsoft.com"))
        XCTAssertTrue(json.contains("xtls-rprx-vision"))
        // R1: пройти validate из PacketTunnelKit
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_buildSingBoxJSON_emptyFlow_passesValidate() throws {
        // Phase 1 W5 lesson: некоторые VLESS+Reality сервера НЕ используют Vision.
        // URI без `?flow=xtls-rprx-vision` → flow="" → outbound.flow="" → matches server.
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com",
            port: 443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            flow: "",
            sni: "www.microsoft.com",
            publicKey: "abc123", shortId: "01234567", fingerprint: "chrome"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["flow"] as? String, "")
        XCTAssertFalse(json.contains("xtls-rprx-vision"))
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_buildSingBoxJSON_nonDefaultPort_mutatesPort() throws {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com", port: 8443,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            flow: "xtls-rprx-vision",
            sni: "www.microsoft.com",
            publicKey: "abc123", shortId: "01234567", fingerprint: "chrome"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        // После mutate'а port = 8443 должен быть в outbounds[0]
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 8443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_buildSingBoxJSON_invalidPort_throws() {
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: "example.com", port: 0,
            uuid: "550e8400-e29b-41d4-a716-446655440000",
            flow: "",
            sni: "x", publicKey: "x", shortId: "x", fingerprint: "chrome"
        )
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: inputs)) { err in
            guard case ConfigBuilder.BuilderError.invalidPort(let p) = err else {
                XCTFail("Expected .invalidPort, got \(err)")
                return
            }
            XCTAssertEqual(p, 0)
        }
    }
}
