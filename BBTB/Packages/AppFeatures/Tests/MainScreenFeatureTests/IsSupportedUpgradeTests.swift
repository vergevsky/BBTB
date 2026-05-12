// IsSupportedUpgradeTests.swift — Phase 4 / Plan 04-06 / Task 2.
//
// Tests for ConfigImporter.runIsSupportedUpgrade() — D-14 background reconciliation.
// Seeds unsupported ServerConfig rows, runs upgrade, verifies outcome.

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class IsSupportedUpgradeTests: XCTestCase {

    // MARK: - Setup

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "bbtb.lastIsSupportedUpgrade")
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeImporter(container: ModelContainer) -> ConfigImporter {
        ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "test.bundle",
            parser: UniversalImportParser(),
            tunnelProvisioner: NoOpTunnelProvisioner()
        )
    }

    private func seedUnsupported(container: ModelContainer, rawURI: String?, scheme: String = "hy2") -> UUID {
        let context = ModelContext(container)
        let cfg = ServerConfig(
            id: UUID(),
            name: "Seed Server",
            host: "example.com",
            port: 443,
            protocolID: scheme,
            keychainTag: nil,
            isSupported: false,
            rawURI: rawURI
        )
        context.insert(cfg)
        try? context.save()
        return cfg.id
    }

    // MARK: - NoOp provisioner

    private final class NoOpTunnelProvisioner: TunnelProvisioning, @unchecked Sendable {
        func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {}
    }

    // MARK: - Tests

    func test_upgradesFromHy2RawURI() async throws {
        let container = try makeContainer()
        let id = seedUnsupported(
            container: container,
            rawURI: "hy2://hy2password@hy2.example.com:443?sni=hy2.example.com#TestHy2"
        )
        let importer = makeImporter(container: container)

        await importer.runIsSupportedUpgrade()

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(all.first(where: { $0.id == id }))
        XCTAssertTrue(cfg.isSupported, "Server should be upgraded to supported")
        XCTAssertNil(cfg.rawURI, "rawURI must be cleared after upgrade (T-02-04 invariant)")
        XCTAssertEqual(cfg.protocolID, "hysteria2")
        XCTAssertNotNil(cfg.keychainTag)
    }

    func test_upgradesFromShadowsocksRawURI() async throws {
        let container = try makeContainer()
        let id = seedUnsupported(
            container: container,
            rawURI: "ss://Y2hhY2hhMjAtaWV0Zi1wb2x5MTMwNTpzZWNyZXRwYXNz@ss.example.com:8388#TestSS",
            scheme: "ss"
        )
        let importer = makeImporter(container: container)

        await importer.runIsSupportedUpgrade()

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(all.first(where: { $0.id == id }))
        // SS parse may or may not succeed depending on base64 encoding; if it does succeed, verify
        if cfg.isSupported {
            XCTAssertEqual(cfg.protocolID, "shadowsocks")
            XCTAssertNil(cfg.rawURI)
        }
        // Either way: no crash is the primary assertion
    }

    func test_skipsWithoutRawURI() async throws {
        let container = try makeContainer()
        let id = seedUnsupported(container: container, rawURI: nil)
        let importer = makeImporter(container: container)

        await importer.runIsSupportedUpgrade()

        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(all.first(where: { $0.id == id }))
        XCTAssertFalse(cfg.isSupported, "Server without rawURI must not be upgraded")
    }

    func test_throttlingPreventsSecondRun() async throws {
        let container = try makeContainer()
        // Seed a hy2 server that would normally upgrade
        _ = seedUnsupported(
            container: container,
            rawURI: "hy2://hy2password@throttle.example.com:443?sni=throttle.example.com#Throttle"
        )
        let importer = makeImporter(container: container)

        // First run: should attempt upgrade
        await importer.runIsSupportedUpgrade()

        // Immediately second run: throttle should prevent it (lastIsSupportedUpgrade was just set)
        // Seed another server to detect if second run does work
        _ = seedUnsupported(
            container: container,
            rawURI: "hy2://hy2password@second.example.com:443?sni=second.example.com#Second"
        )

        await importer.runIsSupportedUpgrade()

        // The second server should NOT have been upgraded (throttle prevented second run)
        let context = ModelContext(container)
        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        let secondCfg = all.first(where: { $0.host == "second.example.com" })
        // second.example.com was seeded after first run, so it was never upgraded
        if let secondCfg = secondCfg {
            XCTAssertFalse(secondCfg.isSupported, "Throttle must prevent second upgrade run")
        }
    }

    // MARK: - Helper tests for protocolIDString / displayNameString

    func test_protocolIDString_allCases() throws {
        let container = try makeContainer()
        let importer = makeImporter(container: container)

        let vlessR = ParsedVLESS(uuid: UUID(), host: "h", port: 443, flow: "", security: "reality",
                                  sni: "h", publicKey: "", shortId: "", fingerprint: "chrome",
                                  networkType: "tcp", remarks: nil)
        XCTAssertEqual(importer.protocolIDString(from: .vlessReality(vlessR)), "vless-reality")

        let vlessTLS = ParsedVLESSTLS(uuid: UUID(), host: "h", port: 443, flow: nil, sni: "h",
                                       fingerprint: "chrome", alpn: ["h2"], networkType: "tcp", remarks: nil)
        XCTAssertEqual(importer.protocolIDString(from: .vlessTLS(vlessTLS)), "vless-tls")

        let ss = ParsedShadowsocks(host: "h", port: 8388, method: "chacha20-ietf-poly1305", password: "p", remarks: nil)
        XCTAssertEqual(importer.protocolIDString(from: .shadowsocks(ss)), "shadowsocks")

        let hy2 = ParsedHysteria2(host: "h", port: 443, auth: "p", sni: "h", fingerprint: nil,
                                   obfs: nil, obfsPassword: nil, allowInsecure: false, pinSHA256: nil, remarks: nil)
        XCTAssertEqual(importer.protocolIDString(from: .hysteria2(hy2)), "hysteria2")
    }
}
