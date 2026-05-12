import XCTest
import PacketTunnelKit
@testable import Shadowsocks

final class ConfigBuilderTests: XCTestCase {

    private func defaultInputs(
        host: String = "example.com",
        port: Int = 8388,
        method: String = "2022-blake3-aes-256-gcm",
        password: String = "32bytespasswordstringforss2022test",
        remark: String? = nil
    ) -> ConfigBuilder.ShadowsocksInputs {
        ConfigBuilder.ShadowsocksInputs(
            host: host, port: port, method: method, password: password, remark: remark
        )
    }

    // MARK: All placeholders substituted + validate passes (R1 self-test)

    func test_buildsConfigWithoutPlaceholders() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${SS_METHOD}"))
        XCTAssertFalse(json.contains("${SS_PASSWORD}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("2022-blake3-aes-256-gcm"))
        XCTAssertTrue(json.contains("shadowsocks-out"))
        // R1 self-test — generated JSON проходит strict sing-box validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Method substituted

    func test_methodSubstituted() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(method: "aes-256-gcm"))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["type"] as? String, "shadowsocks")
        XCTAssertEqual(outbounds[0]["method"] as? String, "aes-256-gcm")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Password substituted

    func test_passwordSubstituted() throws {
        let inputs = defaultInputs(password: "uniquePasswordTestFixture123!")
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        XCTAssertTrue(json.contains("uniquePasswordTestFixture123!"))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["password"] as? String, "uniquePasswordTestFixture123!")
    }

    // MARK: Legacy AEAD method works (whitelist'ом проверено в parser; здесь — builder доверяет)

    func test_legacyMethod_buildsConfig() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(method: "chacha20-ietf-poly1305"))
        XCTAssertTrue(json.contains("chacha20-ietf-poly1305"))
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: Custom port mutated

    func test_customPort_mutated() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 9443))
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 9443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: R1 invariant — НЕТ tls block в outbound[0]

    func test_noTLSBlock_inOutbound() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["type"] as? String, "shadowsocks")
        XCTAssertNil(outbounds[0]["tls"],
                     "Shadowsocks outbound MUST NOT contain tls block (encrypted на уровне протокола)")
    }

    // MARK: Network is TCP (Phase 4 — UDP не реализован)

    func test_networkIsTCP() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let data = json.data(using: .utf8)!
        let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["network"] as? String, "tcp")
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

    // MARK: Empty method throws

    func test_emptyMethod_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(method: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingMethod)
        }
    }

    // MARK: Empty password throws

    func test_emptyPassword_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(password: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingPassword)
        }
    }
}
