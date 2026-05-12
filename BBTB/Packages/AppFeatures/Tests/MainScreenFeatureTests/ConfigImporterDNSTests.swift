// ConfigImporterDNSTests.swift — Phase 6 / Plan 06-05 / Wave 5 / Task 1.
//
// Tests that `ConfigImporter.buildDNSConfig(for:)` correctly derives a `DNSConfig`
// from `app.bbtb.customDNS` + `app.bbtb.adBlockEnabled` UserDefaults entries and
// from the parsed-server host (bootstrap selection per D-01).
//
// Priority order under test (D-01..D-04):
// 1. customDNS valid → tunnelDNS = .custom; adBlock ignored (D-03).
// 2. customDNS empty & adBlockEnabled → tunnelDNS = .adguard (D-04).
// 3. else → tunnelDNS = .cloudflare (D-02 default).
// Bootstrap (D-01):
// - server host is IPv4 → `tcp://<host>`.
// - server host is hostname / empty pool → `tcp://94.140.14.14` (AdGuard fallback, Pitfall 5).
//
// Integration test runs the full `importFromRawInput` flow and inspects the
// configJSON captured by the stub provisioner to confirm DNS values reach
// sing-box JSON.

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class ConfigImporterDNSTests: XCTestCase {

    // MARK: - Test doubles

    private final class StubParser: UniversalImportParsing, @unchecked Sendable {
        let result: ImportResult
        init(_ result: ImportResult) { self.result = result }
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult { result }
    }

    private final class CaptureProvisioner: TunnelProvisioning, @unchecked Sendable {
        private let lock = NSLock()
        private var _configJSON: String?
        private var _serverHost: String?
        func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {
            store(configJSON: configJSON, serverHost: serverHost)
        }
        private func store(configJSON: String, serverHost: String) {
            lock.lock(); defer { lock.unlock() }
            _configJSON = configJSON
            _serverHost = serverHost
        }
        var configJSON: String? {
            lock.lock(); defer { lock.unlock() }
            return _configJSON
        }
        var serverHost: String? {
            lock.lock(); defer { lock.unlock() }
            return _serverHost
        }
    }

    // MARK: - Helpers

    private static let customDNSKey = "app.bbtb.customDNS"
    private static let adBlockKey = "app.bbtb.adBlockEnabled"

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: Self.customDNSKey)
        UserDefaults.standard.removeObject(forKey: Self.adBlockKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: Self.customDNSKey)
        UserDefaults.standard.removeObject(forKey: Self.adBlockKey)
        try await super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeImporter(container: ModelContainer,
                              parser: UniversalImportParsing? = nil,
                              provisioner: TunnelProvisioning = StubTunnelProvisioner()) -> ConfigImporter {
        let actualParser: UniversalImportParsing = parser ?? StubParser(
            ImportResult(supported: [], unsupported: [], failed: [],
                         subscriptionURL: nil, source: .pasteboard, metadata: nil)
        )
        return ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "test.bundle",
            parser: actualParser,
            tunnelProvisioner: provisioner
        )
    }

    private final class StubTunnelProvisioner: TunnelProvisioning, @unchecked Sendable {
        func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {}
    }

    /// Build a `.vlessReality` AnyParsedConfig with the requested host.
    private func makeVLESSReality(host: String) -> AnyParsedConfig {
        let parsed = ParsedVLESS(
            uuid: UUID(),
            host: host, port: 443,
            flow: "xtls-rprx-vision",
            security: "reality",
            sni: "example.com",
            publicKey: "abcdef",
            shortId: "00",
            fingerprint: "chrome",
            networkType: "tcp",
            remarks: "test"
        )
        return .vlessReality(parsed)
    }

    private func makeShadowsocks(host: String) -> AnyParsedConfig {
        .shadowsocks(ParsedShadowsocks(host: host, port: 8388, method: "chacha20-ietf-poly1305", password: "pw", remarks: "ss"))
    }

    // MARK: - Test 1: Default — empty settings, numeric server host

    func test_buildDNSConfig_defaultEmptySettings_numericHost_usesServerIPBootstrap() throws {
        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.bootstrapAddress, "tcp://1.2.3.4")
        XCTAssertEqual(dns.tunnelDNS, .cloudflare)
    }

    // MARK: - Test 2: Default — empty settings, hostname server host → AdGuard fallback

    func test_buildDNSConfig_defaultEmptySettings_hostnameHost_fallsBackToAdGuardBootstrap() throws {
        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "vps.example.com")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.bootstrapAddress, "tcp://94.140.14.14")
        XCTAssertEqual(dns.tunnelDNS, .cloudflare)
    }

    // MARK: - Test 3: customDNS IPv4 wins; adBlock ignored per D-03

    func test_buildDNSConfig_customDNSIPv4_winsAndIgnoresAdBlock() throws {
        UserDefaults.standard.set("8.8.8.8", forKey: Self.customDNSKey)
        UserDefaults.standard.set(true, forKey: Self.adBlockKey)

        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.bootstrapAddress, "tcp://1.2.3.4")
        XCTAssertEqual(dns.tunnelDNS, .custom(address: "tcp://8.8.8.8"))
    }

    // MARK: - Test 4: customDNS hostname → DoH URL

    func test_buildDNSConfig_customDNSHost_formatsAsDohURL() throws {
        UserDefaults.standard.set("my-doh.example.com", forKey: Self.customDNSKey)

        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.tunnelDNS, .custom(address: "https://my-doh.example.com/dns-query"))
    }

    // MARK: - Test 5: adBlock only

    func test_buildDNSConfig_adBlockOnly_usesAdGuardTunnelDNS() throws {
        UserDefaults.standard.set(true, forKey: Self.adBlockKey)

        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.tunnelDNS, .adguard)
    }

    // MARK: - Test 6: invalid customDNS treated as empty

    func test_buildDNSConfig_invalidCustomDNS_treatedAsEmpty() throws {
        UserDefaults.standard.set("not a host!!", forKey: Self.customDNSKey)
        // adBlock false → fallthrough to cloudflare

        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.tunnelDNS, .cloudflare)
    }

    func test_buildDNSConfig_invalidCustomDNS_withAdBlock_fallsToAdGuard() throws {
        UserDefaults.standard.set("8.8.8.8 has-spaces", forKey: Self.customDNSKey)
        UserDefaults.standard.set(true, forKey: Self.adBlockKey)

        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [makeVLESSReality(host: "1.2.3.4")]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.tunnelDNS, .adguard)
    }

    // MARK: - Test 7: multi-server pool — first server is bootstrap

    func test_buildDNSConfig_multipleServers_usesFirstForBootstrap() throws {
        let container = try makeContainer()
        let importer = makeImporter(container: container)
        let parsed = [
            makeVLESSReality(host: "1.2.3.4"),
            makeShadowsocks(host: "2.3.4.5"),
        ]

        let dns = importer.buildDNSConfig(for: parsed)

        XCTAssertEqual(dns.bootstrapAddress, "tcp://1.2.3.4")
    }

    // MARK: - Test 8: end-to-end integration through importFromRawInput

    func test_importFromRawInput_threadsDNSConfigIntoPoolJSON() async throws {
        let container = try makeContainer()
        let provisioner = CaptureProvisioner()

        let parsed = makeVLESSReality(host: "1.2.3.4")
        let supported: [ImportedServer] = [
            .supported(name: "test-server", parsed: parsed, rawURI: "vless://x@1.2.3.4:443?security=reality")
        ]
        let stubResult = ImportResult(
            supported: supported,
            unsupported: [],
            failed: [],
            subscriptionURL: nil,
            source: .pasteboard,
            metadata: nil
        )

        let importer = makeImporter(
            container: container,
            parser: StubParser(stubResult),
            provisioner: provisioner
        )

        _ = try await importer.importFromRawInput("vless://x@1.2.3.4:443?security=reality", source: .pasteboard)

        let json = try XCTUnwrap(provisioner.configJSON)
        // Bootstrap: server IP because host is numeric (D-01 step 1).
        XCTAssertTrue(json.contains("\"address\":\"tcp:\\/\\/1.2.3.4\"")
                      || json.contains("\"address\": \"tcp:\\/\\/1.2.3.4\"")
                      || json.contains("tcp://1.2.3.4"),
                      "bootstrap addr missing: \(json.prefix(800))")
        // Default tunnel DNS = Cloudflare DoH.
        XCTAssertTrue(json.contains("cloudflare-dns.com"),
                      "tunnel DoH missing: \(json.prefix(800))")
        // Yandex eradicated.
        XCTAssertFalse(json.contains("77.88.8.8"), "Yandex bootstrap leaked into JSON")
    }
}
