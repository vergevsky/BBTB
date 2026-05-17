import Foundation
import Testing
@testable import FrontingEngine

// MARK: - Test helpers

private func makeProfile(
    provider: CDNProvider = .cloudflare,
    connectHost: String = "1.1.1.1",
    connectPort: Int = 443,
    sniHost: String = "cdn.example.com",
    httpHost: String = "cdn.example.com",
    mode: FrontingMode = .domain
) -> FrontingProfile {
    FrontingProfile(
        provider: provider,
        connectHost: connectHost,
        connectPort: connectPort,
        sniHost: sniHost,
        httpHost: httpHost,
        mode: mode
    )
}

/// Wrap a single outbound dict into minimal sing-box JSON with outbounds array.
private func makeRootJSON(outbound: [String: Any]) -> String {
    let root: [String: Any] = ["outbounds": [outbound]]
    let data = try! JSONSerialization.data(withJSONObject: root, options: [])
    return String(data: data, encoding: .utf8)!
}

/// Parse the first outbound dict from sing-box root JSON string.
private func parseFirstOutbound(from json: String) -> [String: Any] {
    let data = json.data(using: .utf8)!
    let root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    return (root["outbounds"] as? [[String: Any]])?.first ?? [:]
}

// MARK: - FrontingConfigApplier tests

@Suite("FrontingConfigApplier — transport overlay")
struct FrontingConfigApplierTests {

    // MARK: Test 1 — WebSocket: Host header override

    @Test("apply WS outbound: overrides server, SNI, transport.headers.Host")
    func test_apply_ws_overrides_host_header() throws {
        let outbound: [String: Any] = [
            "type": "vless",
            "server": "original-server.com",
            "server_port": 443,
            "tls": ["server_name": "original.com"],
            "transport": [
                "type": "ws",
                "path": "/proxy",
                "headers": ["Host": "original.com"]
            ]
        ]
        let profile = makeProfile(connectHost: "1.1.1.1", connectPort: 443, sniHost: "cdn.example.com", httpHost: "cdn.example.com")
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        #expect(ob["server"] as? String == "1.1.1.1")
        #expect(ob["server_port"] as? Int == 443)
        let tls = ob["tls"] as? [String: Any]
        #expect(tls?["server_name"] as? String == "cdn.example.com")
        let transport = ob["transport"] as? [String: Any]
        let headers = transport?["headers"] as? [String: Any]
        #expect(headers?["Host"] as? String == "cdn.example.com")
    }

    // MARK: Test 2 — HTTPUpgrade: host field override

    @Test("apply HTTPUpgrade outbound: overrides transport.host")
    func test_apply_httpupgrade_overrides_host() throws {
        let outbound: [String: Any] = [
            "type": "vless",
            "server": "origin.example.com",
            "server_port": 443,
            "tls": ["server_name": "origin.example.com"],
            "transport": [
                "type": "httpupgrade",
                "host": "original-host.com",
                "path": "/"
            ]
        ]
        let profile = makeProfile(httpHost: "cdn.example.com")
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        let transport = ob["transport"] as? [String: Any]
        #expect(transport?["host"] as? String == "cdn.example.com")
        // path must remain unchanged
        #expect(transport?["path"] as? String == "/")
    }

    // MARK: Test 3 — gRPC: SNI only, service_name unchanged

    @Test("apply gRPC outbound: overrides SNI only, service_name unchanged")
    func test_apply_grpc_overrides_sni_only() throws {
        let outbound: [String: Any] = [
            "type": "vless",
            "server": "grpc-server.com",
            "server_port": 443,
            "tls": ["server_name": "grpc-server.com"],
            "transport": [
                "type": "grpc",
                "service_name": "my-grpc-service"
            ]
        ]
        let profile = makeProfile(sniHost: "cdn.example.com", httpHost: "cdn.example.com")
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        // SNI overridden
        let tls = ob["tls"] as? [String: Any]
        #expect(tls?["server_name"] as? String == "cdn.example.com")
        // service_name must remain untouched
        let transport = ob["transport"] as? [String: Any]
        #expect(transport?["service_name"] as? String == "my-grpc-service")
    }

    // MARK: Test 4 — Reality: noop (blacklist)

    @Test("apply Reality outbound: returns false, outbound unchanged")
    func test_apply_noop_for_reality() throws {
        let outbound: [String: Any] = [
            "type": "vless",
            "server": "reality-server.com",
            "server_port": 443,
            "tls": [
                "server_name": "reality-server.com",
                "reality": ["enabled": true, "public_key": "abc123", "short_id": "01"]
            ]
        ]
        let profile = makeProfile()
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        // Server must be unchanged (not overridden)
        #expect(ob["server"] as? String == "reality-server.com")
        let tls = ob["tls"] as? [String: Any]
        #expect(tls?["server_name"] as? String == "reality-server.com")
    }

    // MARK: Test 5 — TUIC: noop (blacklist)

    @Test("apply TUIC outbound: returns false, outbound unchanged")
    func test_apply_noop_for_tuic() throws {
        let outbound: [String: Any] = [
            "type": "tuic",
            "server": "tuic-server.com",
            "server_port": 443
        ]
        let profile = makeProfile()
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        #expect(ob["server"] as? String == "tuic-server.com")
    }

    // MARK: Test 6 — Hysteria2: noop (blacklist)

    @Test("apply Hysteria2 outbound: returns false, outbound unchanged")
    func test_apply_noop_for_hysteria2() throws {
        let outbound: [String: Any] = [
            "type": "hysteria2",
            "server": "hy2-server.com",
            "server_port": 443
        ]
        let profile = makeProfile()
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: FastlyAdapter.self)
        let ob = parseFirstOutbound(from: result)

        #expect(ob["server"] as? String == "hy2-server.com")
    }

    // MARK: Test 7 — Vision flow: noop (blacklist)

    @Test("apply Vision flow outbound: returns false, outbound unchanged")
    func test_apply_noop_for_vision_flow() throws {
        let outbound: [String: Any] = [
            "type": "vless",
            "server": "vision-server.com",
            "server_port": 443,
            "flow": "xtls-rprx-vision",
            "tls": ["server_name": "vision-server.com"]
        ]
        let profile = makeProfile()
        let json = makeRootJSON(outbound: outbound)
        let result = try FrontingConfigApplier.apply(json: json, profile: profile, adapter: CloudflareAdapter.self)
        let ob = parseFirstOutbound(from: result)

        #expect(ob["server"] as? String == "vision-server.com")
        let tls = ob["tls"] as? [String: Any]
        #expect(tls?["server_name"] as? String == "vision-server.com")
    }

    // MARK: Test 8 — Malformed JSON throws

    @Test("apply malformed JSON throws FrontingError.malformedJSON")
    func test_apply_malformed_json_throws() {
        let badJSON = "not valid json {"
        let profile = makeProfile()
        #expect(throws: FrontingError.malformedJSON) {
            try FrontingConfigApplier.apply(json: badJSON, profile: profile, adapter: CloudflareAdapter.self)
        }
    }

    // MARK: Plan 09 C7-4-001 / A6-FE-3-002 — IPv6 transition prefix SSRF (closes parallel drift к T-C-H3)

    /// **NAT64 well-known prefix `64:ff9b::/96`** (RFC 6052) — ubiquitous на US/EU
    /// cellular. Pre-fix string-based regex missed `64:ff9b::7f00:1` → 127.0.0.1.
    @Test("validateProfile rejects NAT64-embedded loopback")
    func test_validateProfile_rejectsNAT64Loopback() {
        // 64:ff9b::7f00:1 = NAT64 prefix + 127.0.0.1
        let profile = makeProfile(connectHost: "64:ff9b::7f00:1")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// NAT64 embedding RFC1918: `64:ff9b::c0a8:101` = 192.168.1.1.
    @Test("validateProfile rejects NAT64-embedded RFC1918")
    func test_validateProfile_rejectsNAT64RFC1918() {
        let profile = makeProfile(connectHost: "64:ff9b::c0a8:101")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **6to4 prefix `2002::/16`** (RFC 3056) — deprecated but routable.
    /// `2002:7f00:1::` = encodes 127.0.0.1 via bytes[2..5] = 7F 00 00 01.
    @Test("validateProfile rejects 6to4-embedded loopback")
    func test_validateProfile_rejects6to4Loopback() {
        let profile = makeProfile(connectHost: "2002:7f00:1::")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **IPv4-compatible IPv6** `::w.x.y.z` (RFC 4291 deprecated). Apple's parser
    /// still accepts. `::a9fe:1` = `::169.254.0.1` = link-local.
    @Test("validateProfile rejects IPv4-compatible IPv6 link-local")
    func test_validateProfile_rejectsIPv4CompatibleLinkLocal() {
        let profile = makeProfile(connectHost: "::a9fe:1")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **IPv4-mapped IPv6** ::ffff:a.b.c.d — was covered string-based pre-fix
    /// for canonical form but compressed form `::ffff:7f00:1` was missed.
    /// Numeric parser now handles both.
    @Test("validateProfile rejects IPv4-mapped IPv6 (compressed form)")
    func test_validateProfile_rejectsIPv4MappedCompressed() {
        let profile = makeProfile(connectHost: "::ffff:7f00:1")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **Regression-guard:** public CDN IP стабильно accepted (no false-positives).
    /// Cloudflare 1.1.1.1.
    @Test("validateProfile accepts public CDN IP (no false positive)")
    func test_validateProfile_acceptsPublicCDN() {
        let profile = makeProfile(connectHost: "1.1.1.1")
        #expect(throws: Never.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **CGNAT 100.64.0.0/10** — second-octet sensitive (64..127 only).
    /// `100.64.0.1` blocked, but `100.128.0.1` valid public-ish (still uncommon
    /// but not RFC-CGNAT).
    @Test("validateProfile rejects CGNAT 100.64.0.0/10")
    func test_validateProfile_rejectsCGNAT() {
        let profile = makeProfile(connectHost: "100.64.0.1")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }

    /// **IPv6 scope id `%`** — security posture: reject any host containing %.
    @Test("validateProfile rejects IPv6 scope id")
    func test_validateProfile_rejectsScopeId() {
        let profile = makeProfile(connectHost: "fe80::1%en0")
        #expect(throws: FrontingError.self) {
            try FrontingConfigApplier.validateProfile(profile)
        }
    }
}
