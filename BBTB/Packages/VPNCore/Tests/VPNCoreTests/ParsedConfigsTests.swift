import XCTest
@testable import VPNCore

final class ParsedConfigsTests: XCTestCase {

    func test_ParsedVLESSTLS_init() {
        let uuid = UUID()
        let instance = ParsedVLESSTLS(
            uuid: uuid,
            host: "example.com",
            port: 443,
            flow: nil,
            sni: "example.com",
            fingerprint: "chrome",
            alpn: ["h2", "http/1.1"],
            transport: .tcp,
            remarks: nil
        )
        XCTAssertEqual(instance, instance)
        XCTAssertEqual(instance.uuid, uuid)
        XCTAssertEqual(instance.host, "example.com")
        XCTAssertEqual(instance.port, 443)
        XCTAssertNil(instance.flow)
        XCTAssertEqual(instance.transport, .tcp)
    }

    func test_AnyParsedConfig_cases() {
        let uuid = UUID()
        let vlessReality = AnyParsedConfig.vlessReality(ParsedVLESS(
            uuid: uuid, host: "h", port: 443, flow: "", security: "reality",
            sni: "h", publicKey: "pk", shortId: "", fingerprint: "chrome",
            networkType: "tcp", remarks: nil
        ))
        let vlessTLS = AnyParsedConfig.vlessTLS(ParsedVLESSTLS(
            uuid: uuid, host: "h", port: 443, flow: nil, sni: "h",
            fingerprint: "chrome", alpn: ["h2"], transport: .tcp, remarks: nil
        ))
        let trojan = AnyParsedConfig.trojan(ParsedTrojan(
            password: "pass", host: "h", port: 443, security: "tls", sni: "h",
            fingerprint: "chrome", alpn: ["h2"], transport: .tcp, remarks: nil
        ))
        let shadowsocks = AnyParsedConfig.shadowsocks(ParsedShadowsocks(
            host: "h", port: 8388, method: "chacha20-ietf-poly1305", password: "pw", remarks: nil
        ))
        let hysteria2 = AnyParsedConfig.hysteria2(ParsedHysteria2(
            host: "h", port: 443, auth: "pw", sni: "h", fingerprint: nil,
            obfs: nil, obfsPassword: nil, allowInsecure: false, pinSHA256: nil, remarks: nil
        ))

        var covered = 0
        for config in [vlessReality, vlessTLS, trojan, shadowsocks, hysteria2] {
            switch config {
            case .vlessReality: covered += 1
            case .vlessTLS:     covered += 1
            case .trojan:       covered += 1
            case .shadowsocks:  covered += 1
            case .hysteria2:    covered += 1
            }
        }
        // Exhaustiveness gate: if a new case is added without updating this test, count != 5
        XCTAssertEqual(covered, 5, "All 5 AnyParsedConfig cases must be covered")
    }

    func test_UnsupportedReason_transportUnsupported() {
        let reason = UnsupportedReason.transportUnsupported
        XCTAssertEqual(reason.rawValue, "transportUnsupported")
    }
}
