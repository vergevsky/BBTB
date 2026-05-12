import XCTest
import PacketTunnelKit
@testable import Hysteria2

final class ConfigBuilderTests: XCTestCase {

    private func defaultInputs(
        host: String = "example.com",
        port: Int = 443,
        password: String = "hy2password32bytesfictional",
        sni: String = "vpn.example.com",
        fingerprint: String? = nil,
        obfs: String? = nil,
        obfsPassword: String? = nil,
        allowInsecure: Bool = false,
        pinSHA256: String? = nil,
        remark: String? = nil
    ) -> ConfigBuilder.Hysteria2Inputs {
        ConfigBuilder.Hysteria2Inputs(
            host: host, port: port, password: password, sni: sni,
            fingerprint: fingerprint, obfs: obfs, obfsPassword: obfsPassword,
            allowInsecure: allowInsecure, pinSHA256: pinSHA256, remark: remark
        )
    }

    // MARK: All placeholders substituted + validate passes (R1 self-test)

    func test_buildsConfigWithoutPlaceholders() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${HY2_PASSWORD}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${ALLOW_INSECURE}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("hy2password32bytesfictional"))
        XCTAssertTrue(json.contains("hysteria2-out"))
        // R1 self-test — generated JSON проходит strict sing-box validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: R1 default — allowInsecure=false → tls.insecure: false (strict TLS)

    func test_validate_strictDefault() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(allowInsecure: false))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["type"] as? String, "hysteria2")
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false, "Default allowInsecure=false → tls.insecure=false")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: D-08 R1 EXCEPTION — allowInsecure=true → tls.insecure: true (legitimately)

    func test_insecureTrue() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(allowInsecure: true))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, true, "D-08 R1 EXCEPTION: Hy2 single legit insecure=true")
        // Sing-box validate должен пройти — R1 invariant в SingBoxConfigLoader проверяет
        // только inbound, outbound `insecure: true` разрешён.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: insecure=false default — tls.insecure: false (повтор для явности контракта)

    func test_insecureFalse_default() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    // MARK: obfs salamander с непустым password → outbound.obfs dictionary

    func test_obfsSalamander_present() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(
            from: defaultInputs(obfs: "salamander", obfsPassword: "obfspass")
        )
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let obfs = outbounds[0]["obfs"] as? [String: Any]
        XCTAssertNotNil(obfs, "obfs dictionary должен быть добавлен в outbound")
        XCTAssertEqual(obfs?["type"] as? String, "salamander")
        XCTAssertEqual(obfs?["password"] as? String, "obfspass")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: obfs nil → НЕТ obfs key в outbound

    func test_obfsAbsent_omitted() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(obfs: nil, obfsPassword: nil))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertNil(outbounds[0]["obfs"], "obfs=nil → ключ obfs отсутствует в outbound")
    }

    // MARK: Custom fingerprint mutated

    func test_customFingerprint_mutated() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(fingerprint: "firefox"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "firefox")
    }

    // MARK: pinSHA256 → tls.certificate_public_key_sha256 array

    func test_pinSHA256_added() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(pinSHA256: "abcdef1234567890"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["abcdef1234567890"])
    }

    // MARK: Custom port mutated

    func test_customPort_mutated() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 8443))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 8443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
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

    // MARK: Empty SNI throws (R1)

    func test_emptySNI_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(sni: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingSNI)
        }
    }

    // MARK: Empty password throws

    func test_emptyPassword_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(password: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingPassword)
        }
    }

    // MARK: ALPN ["h3"] hardcoded (Hysteria2 = QUIC = HTTP/3)

    func test_alpnIsH3() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertEqual(alpn, ["h3"], "Hysteria2 = QUIC = HTTP/3 ALPN")
    }

    // MARK: Combination — obfs + pin + fingerprint + custom port + insecure=true

    func test_allOptionalFields_combined() throws {
        let inputs = defaultInputs(
            port: 9443,
            fingerprint: "safari",
            obfs: "salamander",
            obfsPassword: "obfs!secret",
            allowInsecure: true,
            pinSHA256: "deadbeef"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 9443)
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, true)
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["deadbeef"])
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "safari")
        let obfs = outbounds[0]["obfs"] as! [String: Any]
        XCTAssertEqual(obfs["type"] as? String, "salamander")
        XCTAssertEqual(obfs["password"] as? String, "obfs!secret")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
}
