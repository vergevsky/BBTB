import XCTest
import PacketTunnelKit
import VPNCore
import TransportRegistry
@testable import ConfigParser

/// Phase 6 / Wave 1 — coverage for `PoolBuilder.buildSingBoxJSON(from:dns:)`.
///
/// **D-01..D-04 invariants verified:**
/// - Default bootstrap = Cloudflare (`tcp://1.1.1.1`), default tunnel DoH = Cloudflare URL.
/// - Custom bootstrap (e.g. server IP) is threaded into `dns.servers[*].address` of the
///   `dns-bootstrap` tag verbatim.
/// - Tunnel DoH respects `DNSConfig.tunnelDNS` (Cloudflare / AdGuard / custom).
/// - `tcp://77.88.8.8` (Yandex hardcode) NEVER appears in generated JSON for any input.
/// - All Phase 1 R10 invariants (fakeip, strategy=ipv4_only, final=dns-remote,
///   independent_cache=true, experimental={}) preserved.
final class PoolBuilderDNSConfigTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        // Phase 5 Wave 7 — register all 5 transport handlers (analog PoolBuilderTests).
        TransportRegistry.shared.register(TCPTransportHandler.self)
        TransportRegistry.shared.register(WSTransportHandler.self)
        TransportRegistry.shared.register(HTTPTransportHandler.self)
        TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
        TransportRegistry.shared.register(GRPCTransportHandler.self)
    }

    // MARK: - Fixture helpers (copied from PoolBuilderTests style)

    private func makeVLESS(host: String = "vless-host", port: Int = 443) -> ParsedVLESS {
        return ParsedVLESS(
            uuid: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!,
            host: host, port: port, flow: "xtls-rprx-vision",
            security: "reality", sni: "example.com", publicKey: "abc", shortId: "01",
            fingerprint: "chrome", networkType: "tcp", remarks: nil
        )
    }

    private func parse(_ json: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: json.data(using: .utf8)!) as! [String: Any]
    }

    private func dnsServers(from root: [String: Any]) -> [[String: Any]] {
        let dns = root["dns"] as! [String: Any]
        return dns["servers"] as! [[String: Any]]
    }

    private func dnsServer(_ tag: String, in root: [String: Any]) -> [String: Any]? {
        dnsServers(from: root).first { ($0["tag"] as? String) == tag }
    }

    // MARK: - Test 1 — default DNSConfig produces Cloudflare bootstrap + Cloudflare DoH

    func test_defaultDNSConfig_emitsCloudflareBootstrapAndDoH() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        // No `dns:` argument → uses DNSConfig.default (D-02 default).
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        let root = try parse(json)

        let bootstrap = dnsServer("dns-bootstrap", in: root)
        XCTAssertEqual(bootstrap?["address"] as? String, "tcp://1.1.1.1",
                       "Default bootstrap = Cloudflare `tcp://1.1.1.1` (DNSConfig.default)")
        let remote = dnsServer("dns-remote", in: root)
        XCTAssertEqual(remote?["address"] as? String, "https://cloudflare-dns.com/dns-query",
                       "Default tunnel DoH = Cloudflare")
    }

    // MARK: - Test 2 — explicit DNSConfig threads bootstrap address into JSON

    func test_explicitBootstrapAddress_threadedIntoJSON() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let dns = DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .cloudflare)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
        let root = try parse(json)

        XCTAssertEqual(dnsServer("dns-bootstrap", in: root)?["address"] as? String,
                       "tcp://1.2.3.4",
                       "bootstrap address must be threaded verbatim into dns-bootstrap.address")
        XCTAssertEqual(dnsServer("dns-remote", in: root)?["address"] as? String,
                       "https://cloudflare-dns.com/dns-query")
    }

    // MARK: - Test 3 — AdGuard provider produces AdGuard DoH URL (D-04)

    func test_adguardProvider_emitsAdGuardDoH() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let dns = DNSConfig(bootstrapAddress: "tcp://94.140.14.14", tunnelDNS: .adguard)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
        let root = try parse(json)

        XCTAssertEqual(dnsServer("dns-remote", in: root)?["address"] as? String,
                       "https://dns.adguard-dns.com/dns-query",
                       "AdBlock toggle (D-04) → AdGuard DoH")
        XCTAssertEqual(dnsServer("dns-bootstrap", in: root)?["address"] as? String,
                       "tcp://94.140.14.14")
    }

    // MARK: - Test 4 — custom provider passes through (D-03 custom DNS)

    func test_customProvider_emitsUserAddress() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let dns = DNSConfig(
            bootstrapAddress: "tcp://1.2.3.4",
            tunnelDNS: .custom(address: "https://my-doh.example/dns-query")
        )
        let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
        let root = try parse(json)

        XCTAssertEqual(dnsServer("dns-remote", in: root)?["address"] as? String,
                       "https://my-doh.example/dns-query",
                       "Custom DNS (D-03) overrides default and AdBlock provider")
    }

    // MARK: - Test 5 — INVARIANT: no Yandex 77.88.8.8 in JSON for ANY DNSConfig

    func test_invariant_no_yandex_in_generated_json() throws {
        let cases: [DNSConfig] = [
            .default,
            DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .cloudflare),
            DNSConfig(bootstrapAddress: "tcp://94.140.14.14", tunnelDNS: .adguard),
            DNSConfig(bootstrapAddress: "tcp://1.2.3.4",
                      tunnelDNS: .custom(address: "https://my-doh.example/dns-query")),
        ]
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        for dns in cases {
            let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
            XCTAssertFalse(json.contains("77.88.8.8"),
                           "D-01 violation: Yandex bootstrap 77.88.8.8 found in JSON for dns=\(dns)")
        }
    }

    // MARK: - Test 6 — R10 invariants preserved (fakeip / strategy / final / cache)

    func test_R10_invariants_preserved() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let dns = DNSConfig(bootstrapAddress: "tcp://9.9.9.9", tunnelDNS: .adguard)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
        let root = try parse(json)
        let dnsBlock = root["dns"] as! [String: Any]

        XCTAssertEqual(dnsBlock["strategy"] as? String, "ipv4_only",
                       "R10/D-06: dns.strategy must remain ipv4_only")
        XCTAssertEqual(dnsBlock["final"] as? String, "dns-remote",
                       "dns.final must remain dns-remote")
        XCTAssertEqual(dnsBlock["independent_cache"] as? Bool, true,
                       "dns.independent_cache must remain true (Phase 1 R10 invariant)")
        let fakeip = dnsBlock["fakeip"] as! [String: Any]
        XCTAssertEqual(fakeip["enabled"] as? Bool, true)
        XCTAssertEqual(fakeip["inet4_range"] as? String, "100.64.0.0/10")
        XCTAssertEqual(fakeip["inet6_range"] as? String, "fc00::/18")

        // R1 invariant — experimental MUST stay empty.
        let experimental = root["experimental"] as! [String: Any]
        XCTAssertTrue(experimental.isEmpty,
                      "R1 invariant: experimental block must stay empty (no clash_api/v2ray_api/cache_file)")
    }

    // MARK: - Test 7 — backward compat: existing callers (no dns: arg) still produce valid JSON

    func test_backwardCompat_noDNSArg_passesSingBoxValidate() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let json = try PoolBuilder.buildSingBoxJSON(from: configs)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json),
                         "Backward-compat: default DNSConfig must still produce R1-valid JSON")
    }

    func test_backwardCompat_singleOutbound_noDNSArg() throws {
        let json = try PoolBuilder.buildSingleOutboundJSON(from: .vlessReality(makeVLESS()))
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json),
                         "Backward-compat: buildSingleOutboundJSON without dns: arg must work")
        XCTAssertFalse(json.contains("77.88.8.8"),
                       "Single-outbound JSON must also have no Yandex hardcode")
    }

    // MARK: - Test 8 — buildSingleOutboundJSON respects DNSConfig

    func test_singleOutbound_threadsDNSConfig() throws {
        let dns = DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .adguard)
        let json = try PoolBuilder.buildSingleOutboundJSON(from: .vlessReality(makeVLESS()), dns: dns)
        let root = try parse(json)
        XCTAssertEqual(dnsServer("dns-bootstrap", in: root)?["address"] as? String, "tcp://1.2.3.4")
        XCTAssertEqual(dnsServer("dns-remote", in: root)?["address"] as? String,
                       "https://dns.adguard-dns.com/dns-query")
    }

    // MARK: - Test 9 — DNSConfig pool JSON still passes SingBoxConfigLoader.validate

    func test_customDNSConfig_passesSingBoxValidate() throws {
        let configs: [AnyParsedConfig] = [.vlessReality(makeVLESS())]
        let dns = DNSConfig(bootstrapAddress: "tcp://94.140.14.14", tunnelDNS: .adguard)
        let json = try PoolBuilder.buildSingBoxJSON(from: configs, dns: dns)
        XCTAssertNoThrow(try SingBoxConfigLoader.validate(json: json),
                         "DNSConfig-threaded pool JSON must still pass R1/SEC-06 validation")
    }
}
