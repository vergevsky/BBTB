import XCTest
import VPNCore
@testable import ConfigParser

/// Phase 5 Wave 7 — tests for applyTransportOverride helper (D-19 / Pitfall 5).
///
/// Tests cover:
/// - nil override returns parsed unchanged (all 5 cases)
/// - .vlessTLS override replaces transport
/// - .trojan override replaces transport
/// - .vlessReality ignores override (D-03 invariant)
/// - .shadowsocks ignores override (D-16 invariant)
/// - .hysteria2 ignores override (D-16 invariant)
final class TransportOverrideTests: XCTestCase {

    // MARK: - Helpers

    private func makeVLESSTLS(transport: TransportConfig = .tcp) -> AnyParsedConfig {
        .vlessTLS(ParsedVLESSTLS(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            host: "vpn.example.com", port: 443,
            flow: nil, sni: "vpn.example.com", fingerprint: "chrome",
            alpn: ["h2", "http/1.1"], transport: transport, remarks: nil
        ))
    }

    private func makeTrojan(transport: TransportConfig = .tcp) -> AnyParsedConfig {
        .trojan(ParsedTrojan(
            password: "pass", host: "trojan.example.com", port: 443,
            security: "tls", sni: "trojan.example.com", fingerprint: "chrome",
            alpn: ["h2", "http/1.1"], transport: transport, remarks: nil
        ))
    }

    private func makeVLESSReality() -> AnyParsedConfig {
        .vlessReality(ParsedVLESS(
            uuid: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            host: "reality.example.com", port: 443,
            flow: "xtls-rprx-vision", security: "reality",
            sni: "reality.example.com", publicKey: "pubkey", shortId: "01",
            fingerprint: "chrome", networkType: "tcp", remarks: nil
        ))
    }

    private func makeShadowsocks() -> AnyParsedConfig {
        .shadowsocks(ParsedShadowsocks(
            host: "ss.example.com", port: 8388,
            method: "2022-blake3-aes-256-gcm", password: "pass", remarks: nil
        ))
    }

    private func makeHysteria2() -> AnyParsedConfig {
        .hysteria2(ParsedHysteria2(
            host: "hy2.example.com", port: 443, auth: "auth",
            sni: "hy2.example.com", fingerprint: nil, obfs: nil, obfsPassword: nil,
            allowInsecure: false, pinSHA256: nil, remarks: nil
        ))
    }

    // MARK: - nil override → identity

    func test_applyOverride_nilOverride_vlessTLS_returnsUnchanged() {
        let parsed = makeVLESSTLS(transport: .tcp)
        let result = applyTransportOverride(parsed, nil)
        XCTAssertEqual(result, parsed)
    }

    func test_applyOverride_nilOverride_trojan_returnsUnchanged() {
        let parsed = makeTrojan(transport: .tcp)
        let result = applyTransportOverride(parsed, nil)
        XCTAssertEqual(result, parsed)
    }

    func test_applyOverride_nilOverride_vlessReality_returnsUnchanged() {
        let parsed = makeVLESSReality()
        let result = applyTransportOverride(parsed, nil)
        XCTAssertEqual(result, parsed)
    }

    func test_applyOverride_nilOverride_shadowsocks_returnsUnchanged() {
        let parsed = makeShadowsocks()
        let result = applyTransportOverride(parsed, nil)
        XCTAssertEqual(result, parsed)
    }

    func test_applyOverride_nilOverride_hysteria2_returnsUnchanged() {
        let parsed = makeHysteria2()
        let result = applyTransportOverride(parsed, nil)
        XCTAssertEqual(result, parsed)
    }

    // MARK: - vlessTLS override replaces transport

    func test_applyOverride_vlessTLS_replacesTransport() {
        let parsed = makeVLESSTLS(transport: .tcp)
        let override: TransportConfig = .ws(path: "/x", host: "cdn.example.com")
        let result = applyTransportOverride(parsed, override)

        guard case .vlessTLS(let mutated) = result else {
            XCTFail("Expected .vlessTLS after override")
            return
        }
        XCTAssertEqual(mutated.transport, override, "Transport must be replaced with override")
        // Other fields must be preserved
        if case .vlessTLS(let original) = parsed {
            XCTAssertEqual(mutated.uuid, original.uuid)
            XCTAssertEqual(mutated.host, original.host)
            XCTAssertEqual(mutated.sni, original.sni)
            XCTAssertEqual(mutated.alpn, original.alpn)
        }
    }

    func test_applyOverride_vlessTLS_tcpOverride_replacesTCP() {
        let parsed = makeVLESSTLS(transport: .ws(path: "/old", host: "old.example.com"))
        let result = applyTransportOverride(parsed, .tcp)
        guard case .vlessTLS(let mutated) = result else {
            XCTFail("Expected .vlessTLS")
            return
        }
        XCTAssertEqual(mutated.transport, .tcp)
    }

    // MARK: - trojan override replaces transport

    func test_applyOverride_trojan_replacesTransport() {
        let parsed = makeTrojan(transport: .tcp)
        let override: TransportConfig = .ws(path: "/y", host: "cdn.example.com")
        let result = applyTransportOverride(parsed, override)

        guard case .trojan(let mutated) = result else {
            XCTFail("Expected .trojan after override")
            return
        }
        XCTAssertEqual(mutated.transport, override, "Transport must be replaced with override")
        // Other fields must be preserved
        if case .trojan(let original) = parsed {
            XCTAssertEqual(mutated.password, original.password)
            XCTAssertEqual(mutated.host, original.host)
            XCTAssertEqual(mutated.sni, original.sni)
        }
    }

    // MARK: - D-03/D-16 invariants: override ignored

    func test_applyOverride_vlessReality_ignoresOverride() {
        let parsed = makeVLESSReality()
        let result = applyTransportOverride(parsed, .ws(path: "/x", host: "cdn.example.com"))
        XCTAssertEqual(result, parsed, "D-03: VLESSReality must ignore transport override")
    }

    func test_applyOverride_shadowsocks_ignoresOverride() {
        let parsed = makeShadowsocks()
        let result = applyTransportOverride(parsed, .ws(path: "/x", host: "cdn.example.com"))
        XCTAssertEqual(result, parsed, "D-16: Shadowsocks must ignore transport override")
    }

    func test_applyOverride_hysteria2_ignoresOverride() {
        let parsed = makeHysteria2()
        let result = applyTransportOverride(parsed, .ws(path: "/x", host: "cdn.example.com"))
        XCTAssertEqual(result, parsed, "D-16: Hysteria2 must ignore transport override")
    }
}
