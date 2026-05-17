import XCTest
import VPNCore
@testable import Hysteria2

/// T-A2 (closes C8-009 CRITICAL): tests переведены с `buildSingBoxJSON` template path
/// (deleted — JSON-injection unsafe) на dict-based `buildOutbound` path.
final class ConfigBuilderTests: XCTestCase {

    private func makeParsed(
        host: String = "example.com",
        port: Int = 443,
        auth: String = "hy2password32bytesfictional",
        sni: String = "vpn.example.com",
        fingerprint: String? = nil,
        obfs: String? = nil,
        obfsPassword: String? = nil,
        allowInsecure: Bool = false,
        pinSHA256: String? = nil
    ) -> ParsedHysteria2 {
        return ParsedHysteria2(
            host: host, port: port, auth: auth,
            sni: sni,
            fingerprint: fingerprint,
            obfs: obfs, obfsPassword: obfsPassword,
            allowInsecure: allowInsecure,
            pinSHA256: pinSHA256,
            remarks: nil
        )
    }

    func test_buildOutbound_basic_dictShape() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")

        XCTAssertEqual(outbound["type"] as? String, "hysteria2")
        XCTAssertEqual(outbound["tag"] as? String, "hy2-0")
        XCTAssertEqual(outbound["server"] as? String, "example.com")
        XCTAssertEqual(outbound["server_port"] as? Int, 443)
        XCTAssertEqual(outbound["password"] as? String, "hy2password32bytesfictional")

        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["server_name"] as? String, "vpn.example.com")
        XCTAssertEqual(tls["insecure"] as? Bool, false, "Default allowInsecure=false")
        XCTAssertEqual(tls["alpn"] as? [String], ["h3"])
    }

    /// D-08 R1 EXCEPTION — Hysteria2 is the ONLY protocol where insecure=true legit.
    func test_buildOutbound_insecureTrue_D08exception() {
        let parsed = makeParsed(allowInsecure: true)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, true,
                       "D-08 R1 EXCEPTION: Hy2 legit insecure=true")
    }

    func test_buildOutbound_insecureFalse_default() {
        let parsed = makeParsed()
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let tls = outbound["tls"] as! [String: Any]
        XCTAssertEqual(tls["insecure"] as? Bool, false)
    }

    func test_buildOutbound_obfsSalamander_present() {
        let parsed = makeParsed(obfs: "salamander", obfsPassword: "obfspass")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let obfs = outbound["obfs"] as? [String: Any]
        XCTAssertNotNil(obfs)
        XCTAssertEqual(obfs?["type"] as? String, "salamander")
        XCTAssertEqual(obfs?["password"] as? String, "obfspass")
    }

    func test_buildOutbound_obfs_emptyPassword_skipped() {
        let parsed = makeParsed(obfs: "salamander", obfsPassword: "")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        XCTAssertNil(outbound["obfs"])
    }

    func test_buildOutbound_fingerprint_override() {
        let parsed = makeParsed(fingerprint: "firefox")
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let tls = outbound["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "firefox")
    }

    func test_buildOutbound_fingerprint_nil_defaultRandom() {
        // Phase 7a Wave 2 — DPI-01 smart default: "random".
        let parsed = makeParsed(fingerprint: nil)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let tls = outbound["tls"] as! [String: Any]
        let utls = tls["utls"] as! [String: Any]
        XCTAssertEqual(utls["fingerprint"] as? String, "random")
    }

    func test_buildOutbound_pinSHA256_inTLS() {
        let pin = "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
        let parsed = makeParsed(pinSHA256: pin)
        let outbound = ConfigBuilder.buildOutbound(from: parsed, transport: .tcp, tag: "hy2-0")
        let tls = outbound["tls"] as! [String: Any]
        let pins = tls["certificate_public_key_sha256"] as? [String]
        XCTAssertEqual(pins, [pin])
    }
}
