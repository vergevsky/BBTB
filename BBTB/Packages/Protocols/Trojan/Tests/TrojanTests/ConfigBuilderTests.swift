import XCTest
import PacketTunnelKit
@testable import Trojan

final class ConfigBuilderTests: XCTestCase {

    private func tcpInputs(
        host: String = "example.com",
        port: Int = 443,
        password: String = "secret",
        sni: String = "vpn.example.ru",
        fingerprint: String = "chrome"
    ) -> ConfigBuilder.TrojanInputs {
        ConfigBuilder.TrojanInputs(
            host: host, port: port, password: password, sni: sni,
            fingerprint: fingerprint, alpn: ["h2", "http/1.1"],
            transport: .tcp, remark: nil
        )
    }

    private func wsInputs(
        path: String = "/path123",
        wsHost: String = "vpn.example.ru"
    ) -> ConfigBuilder.TrojanInputs {
        ConfigBuilder.TrojanInputs(
            host: "example.com", port: 443, password: "secret", sni: "vpn.example.ru",
            fingerprint: "chrome", alpn: ["h2", "http/1.1"],
            transport: .ws(path: path, host: wsHost), remark: nil
        )
    }

    // MARK: Tests

    func test_tcp_buildsConfigWithoutPlaceholders() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: tcpInputs())
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${TROJAN_PASSWORD}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("secret"))
        XCTAssertTrue(json.contains("vpn.example.ru"))
        XCTAssertTrue(json.contains("trojan-out"))
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_ws_buildsConfigWithTransportBlock() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: wsInputs(path: "/path123", wsHost: "vpn.example.ru"))
        XCTAssertFalse(json.contains("${WS_PATH}"))
        XCTAssertFalse(json.contains("${WS_HOST}"))
        XCTAssertTrue(json.contains("\"type\": \"ws\"") || json.contains("\"type\":\"ws\""))
        XCTAssertTrue(json.contains("/path123"))
        // Host header
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let trojan = outbounds[0]
        XCTAssertEqual(trojan["type"] as? String, "trojan")
        let transport = trojan["transport"] as! [String: Any]
        XCTAssertEqual(transport["type"] as? String, "ws")
        XCTAssertEqual(transport["path"] as? String, "/path123")
        let headers = transport["headers"] as! [String: Any]
        XCTAssertEqual(headers["Host"] as? String, "vpn.example.ru")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_nonDefaultPort_mutatesPort() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: tcpInputs(port: 2087))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 2087)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    func test_emptyPassword_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: tcpInputs(password: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingPassword)
        }
    }

    func test_emptySNI_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: tcpInputs(sni: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingSNI)
        }
    }

    func test_invalidPort_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: tcpInputs(port: 0))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(0))
        }
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: tcpInputs(port: 70000))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(70000))
        }
    }

    /// Test 7 — real user fixture (sanitized password from CONTEXT `<specifics>`):
    /// `trojan://TEST_PASSWORD_REDACTED@185.237.218.81:2087?security=tls&type=ws&path=/ba0ca9ffa1d4&sni=vpn.vergevsky.ru&fp=chrome#Латвия — Trojan`
    func test_realUserFixture_TCP_passesValidate() throws {
        let inputs = ConfigBuilder.TrojanInputs(
            host: "185.237.218.81",
            port: 2087,
            password: "TEST_PASSWORD_REDACTED",
            sni: "vpn.vergevsky.ru",
            fingerprint: "chrome",
            alpn: ["h2", "http/1.1"],
            transport: .tcp,
            remark: "Латвия — Trojan"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        XCTAssertFalse(json.contains("${"))
        XCTAssertTrue(json.contains("vpn.vergevsky.ru"))
        XCTAssertTrue(json.contains("185.237.218.81"))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 2087)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
}
