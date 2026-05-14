import XCTest
import PacketTunnelKit
@testable import TUIC

final class ConfigBuilderTests: XCTestCase {

    private func defaultInputs(
        host: String = "example.com",
        port: Int = 443,
        uuid: String = "11111111-2222-3333-4444-555555555555",
        password: String = "tuic-password-secret",
        congestionControl: String = "bbr",
        udpRelayMode: String = "native",
        sni: String = "vpn.example.com",
        fingerprint: String? = nil,
        pinSHA256: String? = nil,
        remark: String? = nil
    ) -> ConfigBuilder.TUICInputs {
        ConfigBuilder.TUICInputs(
            host: host, port: port, uuid: uuid, password: password,
            congestionControl: congestionControl, udpRelayMode: udpRelayMode,
            sni: sni, fingerprint: fingerprint, pinSHA256: pinSHA256, remark: remark
        )
    }

    // MARK: All placeholders substituted + validate passes (R1 self-test)

    func test_buildsConfigWithoutPlaceholders() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        XCTAssertFalse(json.contains("${SERVER_HOST}"))
        XCTAssertFalse(json.contains("${TUIC_UUID}"))
        XCTAssertFalse(json.contains("${TUIC_PASSWORD}"))
        XCTAssertFalse(json.contains("${CONGESTION_CONTROL}"))
        XCTAssertFalse(json.contains("${UDP_RELAY_MODE}"))
        XCTAssertFalse(json.contains("${SNI_DOMAIN}"))
        XCTAssertFalse(json.contains("${UTLS_FINGERPRINT}"))
        XCTAssertFalse(json.contains("${DNS_DETOUR}"))
        XCTAssertTrue(json.contains("example.com"))
        XCTAssertTrue(json.contains("11111111-2222-3333-4444-555555555555"))
        XCTAssertTrue(json.contains("tuic-out"))
        // R1 self-test — generated JSON проходит strict sing-box validation.
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: R1 STRICT — TUIC outbound JSON НЕ содержит tls.insecure

    func test_buildSingBoxJSON_neverHasInsecure() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertNil(tls["insecure"], "TUIC v5 — R1 STRICT, без allowInsecure exception")
    }

    // MARK: ALPN ["h3"] hardcoded (TUIC v5 = QUIC = HTTP/3)

    func test_alpnIsH3() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs())
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        let alpn = tls["alpn"] as! [String]
        XCTAssertEqual(alpn, ["h3"], "TUIC v5 = QUIC = HTTP/3 ALPN")
    }

    // MARK: Congestion control propagation

    func test_congestionControl_cubic() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(congestionControl: "cubic"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["congestion_control"] as? String, "cubic")
    }

    func test_congestionControl_newReno() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(congestionControl: "new_reno"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["congestion_control"] as? String, "new_reno")
    }

    func test_congestionControl_invalid_throws() {
        XCTAssertThrowsError(
            try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(congestionControl: "reno-classic"))
        ) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidCongestionControl("reno-classic"))
        }
    }

    // MARK: udp_relay_mode propagation

    func test_udpRelayMode_quic() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(udpRelayMode: "quic"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["udp_relay_mode"] as? String, "quic")
    }

    func test_udpRelayMode_invalid_throws() {
        XCTAssertThrowsError(
            try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(udpRelayMode: "stream"))
        ) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidUDPRelayMode("stream"))
        }
    }

    // MARK: Custom port mutated

    func test_customPort_mutated() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 8443))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 8443)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }

    // MARK: pinSHA256 → tls.certificate_public_key_sha256 array

    func test_pinSHA256_added() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(pinSHA256: "abcdef1234567890"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["abcdef1234567890"])
    }

    // MARK: Empty / invalid inputs throw

    func test_invalidPort_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 0))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(0))
        }
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(port: 70000))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .invalidPort(70000))
        }
    }

    func test_emptyUUID_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(uuid: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingUUID)
        }
    }

    func test_emptyPassword_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(password: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingPassword)
        }
    }

    func test_emptySNI_throws() {
        XCTAssertThrowsError(try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(sni: ""))) { err in
            XCTAssertEqual(err as? ConfigBuilder.BuilderError, .missingSNI)
        }
    }

    // MARK: Custom fingerprint preserved

    func test_customFingerprint_mutated() throws {
        let json = try ConfigBuilder.buildSingBoxJSON(from: defaultInputs(fingerprint: "firefox"))
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        let tls = outbounds[0]["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "firefox")
    }

    // MARK: Combination — custom port + pin + fingerprint + new_reno + quic

    func test_allOptionalFields_combined() throws {
        let inputs = defaultInputs(
            port: 9443,
            congestionControl: "new_reno",
            udpRelayMode: "quic",
            fingerprint: "safari",
            pinSHA256: "deadbeef"
        )
        let json = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        let root = try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
        let outbounds = root["outbounds"] as! [[String: Any]]
        XCTAssertEqual(outbounds[0]["server_port"] as? Int, 9443)
        XCTAssertEqual(outbounds[0]["congestion_control"] as? String, "new_reno")
        XCTAssertEqual(outbounds[0]["udp_relay_mode"] as? String, "quic")
        let tls = outbounds[0]["tls"] as! [String: Any]
        XCTAssertNil(tls["insecure"], "R1 STRICT")
        XCTAssertEqual(tls["certificate_public_key_sha256"] as? [String], ["deadbeef"])
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "safari")
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json))
    }
}
