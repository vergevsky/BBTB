import XCTest
@testable import VPNCore

/// Phase 6 / Wave 1 — coverage for shared DNSConfig value type (NET-01..NET-04, D-01..D-04).
///
/// Tests RED-first: written before DNSConfig.swift production code; pass once the
/// production type is added with the contract from `.planning/phases/06-network-resilience/06-RESEARCH.md` §8.
final class DNSConfigTests: XCTestCase {

    // MARK: - Test 1 — default value (D-01 / D-02 default DNS strategy)

    func test_default_usesCloudflareTunnelAndCloudflareBootstrap() {
        let dns = DNSConfig.default
        XCTAssertEqual(dns.bootstrapAddress, "tcp://1.1.1.1",
                       "Default bootstrap = Cloudflare; ConfigImporter overrides with server-IP when available (D-01)")
        XCTAssertEqual(dns.tunnelDNS, .cloudflare,
                       "Default tunnel DNS = Cloudflare DoH (D-02)")
        XCTAssertEqual(dns.dohAddress(), "https://cloudflare-dns.com/dns-query")
    }

    // MARK: - Test 2 — explicit init Cloudflare → DoH URL

    func test_init_cloudflareProvider_returnsCloudflareDoH() {
        let dns = DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .cloudflare)
        XCTAssertEqual(dns.bootstrapAddress, "tcp://1.2.3.4")
        XCTAssertEqual(dns.dohAddress(), "https://cloudflare-dns.com/dns-query")
    }

    // MARK: - Test 3 — AdGuard provider → AdGuard DoH URL (D-04)

    func test_adGuardProvider_returnsAdGuardDoH() {
        let dns = DNSConfig(bootstrapAddress: "tcp://94.140.14.14", tunnelDNS: .adguard)
        XCTAssertEqual(dns.dohAddress(), "https://dns.adguard-dns.com/dns-query",
                       "AdBlock-via-DNS → AdGuard DoH (D-04)")
    }

    // MARK: - Test 4 — custom provider passes through unchanged (D-03)

    func test_customProvider_passesThroughAddress() {
        let custom = "https://my-doh.example/dns-query"
        let dns = DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .custom(address: custom))
        XCTAssertEqual(dns.dohAddress(), custom,
                       "Custom provider returns its address verbatim; caller pre-formats (D-03)")
    }

    // MARK: - Test 5 — Codable round-trip (synthesized Codable, all three provider cases)

    func test_codable_roundtrip_allProviderVariants() throws {
        let cases: [DNSConfig] = [
            DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare),
            DNSConfig(bootstrapAddress: "tcp://94.140.14.14", tunnelDNS: .adguard),
            DNSConfig(bootstrapAddress: "tcp://1.2.3.4",
                      tunnelDNS: .custom(address: "https://example/dns-query")),
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for original in cases {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(DNSConfig.self, from: data)
            XCTAssertEqual(decoded, original, "Codable round-trip failed for \(original)")
        }
    }

    // MARK: - Test 6 — Equatable

    func test_equatable_identicalFieldsAreEqual() {
        let a = DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare)
        let b = DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare)
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentBootstrap_notEqual() {
        let a = DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare)
        let b = DNSConfig(bootstrapAddress: "tcp://1.2.3.4", tunnelDNS: .cloudflare)
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_differentProvider_notEqual() {
        let a = DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare)
        let b = DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .adguard)
        XCTAssertNotEqual(a, b)
    }

    func test_equatable_customAssociatedValueMatters() {
        let a = DNSConfig(bootstrapAddress: "tcp://1.1.1.1",
                          tunnelDNS: .custom(address: "https://a/dns-query"))
        let b = DNSConfig(bootstrapAddress: "tcp://1.1.1.1",
                          tunnelDNS: .custom(address: "https://b/dns-query"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Test 7 — Sendable conformance (compiles only if Sendable)
    //
    // The Sendable conformance is checked at compile time. The closure below references
    // a DNSConfig value across an actor hop; if DNSConfig were not Sendable, Swift 6
    // strict-concurrency would refuse to compile this test target.

    func test_sendable_crossesActorBoundary() async {
        let dns = DNSConfig.default
        await Task { @Sendable in
            _ = dns.dohAddress()  // captured Sendable value
        }.value
    }

    // MARK: - Test 8 — Hashable (Set membership)

    func test_hashable_setMembership_distinguishesProviders() {
        let set: Set<DNSConfig> = [
            DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .cloudflare),
            DNSConfig(bootstrapAddress: "tcp://1.1.1.1", tunnelDNS: .adguard),
            DNSConfig(bootstrapAddress: "tcp://1.1.1.1",
                      tunnelDNS: .custom(address: "https://x/dns-query")),
        ]
        XCTAssertEqual(set.count, 3)
    }

    // MARK: - Test 9 — D-01 elimination — no Yandex hardcoded value reachable via .default

    func test_default_doesNotReferenceYandexBootstrap() {
        let dns = DNSConfig.default
        XCTAssertFalse(dns.bootstrapAddress.contains("77.88.8.8"),
                       "D-01 violation: Yandex 77.88.8.8 must NOT appear in DNSConfig.default")
    }
}
