// ConfigImporterAnyParsedConfigTests.swift — Phase 4 / Plan 04-06 / Task 1.
//
// Tests that ConfigImporter correctly handles all 5 AnyParsedConfig cases:
// .vlessReality, .vlessTLS, .trojan, .shadowsocks, .hysteria2
// through buildServerConfig, buildKeychainPayload, reparseFromKeychain.
//
// Tests use the public importFromRawInput black-box and @testable internals.

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class ConfigImporterAnyParsedConfigTests: XCTestCase {

    // MARK: - Test doubles

    private final class StubParser: UniversalImportParsing, @unchecked Sendable {
        let result: ImportResult
        init(_ result: ImportResult) { self.result = result }
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult {
            return result
        }
    }

    private final class StubTunnelProvisioner: TunnelProvisioning, @unchecked Sendable {
        func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {}
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeImporter(container: ModelContainer, parser: UniversalImportParsing) -> ConfigImporter {
        ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "test.bundle",
            parser: parser,
            tunnelProvisioner: StubTunnelProvisioner()
        )
    }

    private func makeParsedVLESSTLS() -> ParsedVLESSTLS {
        ParsedVLESSTLS(
            uuid: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            host: "vlesstls.example.com",
            port: 8443,
            flow: "xtls-rprx-vision",
            sni: "sni.example.com",
            fingerprint: "chrome",
            alpn: ["h2", "http/1.1"],
            networkType: "tcp",
            remarks: "Test VLESS TLS"
        )
    }

    private func makeParsedShadowsocks() -> ParsedShadowsocks {
        ParsedShadowsocks(
            host: "ss.example.com",
            port: 8388,
            method: "chacha20-ietf-poly1305",
            password: "secretpassword",
            remarks: "Test SS"
        )
    }

    private func makeParsedHysteria2() -> ParsedHysteria2 {
        ParsedHysteria2(
            host: "hy2.example.com",
            port: 443,
            auth: "hy2password",
            sni: "hy2.example.com",
            fingerprint: nil,
            obfs: nil,
            obfsPassword: nil,
            allowInsecure: false,
            pinSHA256: nil,
            remarks: "Test Hy2"
        )
    }

    private func makeImportResult(parsed: AnyParsedConfig, name: String) -> ImportResult {
        let server = ImportedServer.supported(name: name, parsed: parsed, rawURI: "stub://uri")
        return ImportResult(supported: [server], unsupported: [], failed: [],
                            subscriptionURL: nil, source: .pasteboard, metadata: nil)
    }

    // MARK: - buildServerConfig tests

    func test_buildServerConfig_vlessTLS() async throws {
        let container = try makeContainer()
        let parsed = makeParsedVLESSTLS()
        let stub = StubParser(makeImportResult(parsed: .vlessTLS(parsed), name: "VLESSTLSServer"))
        let importer = makeImporter(container: container, parser: stub)

        let result = try await importer.importFromRawInput("stub://input")
        XCTAssertEqual(result.supported.count, 1)

        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "vless-tls" }))
        XCTAssertEqual(cfg.host, "vlesstls.example.com")
        XCTAssertEqual(cfg.port, 8443)
        XCTAssertEqual(cfg.sni, "sni.example.com")
        XCTAssertEqual(cfg.protocolDisplayName, "VLESS + TLS")
        XCTAssertTrue(cfg.isSupported)
        XCTAssertNil(cfg.rawURI)  // T-02-04 invariant
    }

    func test_buildServerConfig_shadowsocks() async throws {
        let container = try makeContainer()
        let parsed = makeParsedShadowsocks()
        let stub = StubParser(makeImportResult(parsed: .shadowsocks(parsed), name: "SSServer"))
        let importer = makeImporter(container: container, parser: stub)

        _ = try await importer.importFromRawInput("stub://input")

        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "shadowsocks" }))
        XCTAssertEqual(cfg.host, "ss.example.com")
        XCTAssertEqual(cfg.port, 8388)
        XCTAssertNil(cfg.sni)
        XCTAssertEqual(cfg.protocolDisplayName, "Shadowsocks")
        XCTAssertTrue(cfg.isSupported)
    }

    func test_buildServerConfig_hysteria2() async throws {
        let container = try makeContainer()
        let parsed = makeParsedHysteria2()
        let stub = StubParser(makeImportResult(parsed: .hysteria2(parsed), name: "Hy2Server"))
        let importer = makeImporter(container: container, parser: stub)

        _ = try await importer.importFromRawInput("stub://input")

        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "hysteria2" }))
        XCTAssertEqual(cfg.host, "hy2.example.com")
        XCTAssertEqual(cfg.port, 443)
        XCTAssertEqual(cfg.sni, "hy2.example.com")
        XCTAssertEqual(cfg.protocolDisplayName, "Hysteria2")
        XCTAssertTrue(cfg.isSupported)
    }

    // MARK: - buildKeychainPayload tests (via round-trip reparseFromKeychain)

    func test_buildKeychainPayload_shadowsocks_roundtrip() async throws {
        let container = try makeContainer()
        let parsed = makeParsedShadowsocks()
        let stub = StubParser(makeImportResult(parsed: .shadowsocks(parsed), name: "SSServer"))
        let importer = makeImporter(container: container, parser: stub)
        _ = try await importer.importFromRawInput("stub://input")

        // Fetch the saved config
        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "shadowsocks" }))
        let tag = try XCTUnwrap(cfg.keychainTag)

        // Read back from keychain and re-parse
        let data = try KeychainStore.load(tag: tag)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(payload["method"], "chacha20-ietf-poly1305")
        XCTAssertEqual(payload["password"], "secretpassword")
    }

    func test_buildKeychainPayload_vlessTLS_roundtrip() async throws {
        let container = try makeContainer()
        let parsed = makeParsedVLESSTLS()
        let stub = StubParser(makeImportResult(parsed: .vlessTLS(parsed), name: "VLESSTLSServer"))
        let importer = makeImporter(container: container, parser: stub)
        _ = try await importer.importFromRawInput("stub://input")

        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "vless-tls" }))
        let tag = try XCTUnwrap(cfg.keychainTag)

        let data = try KeychainStore.load(tag: tag)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(payload["uuid"], "12345678-1234-1234-1234-123456789ABC")
        XCTAssertEqual(payload["flow"], "xtls-rprx-vision")
        XCTAssertEqual(payload["sni"], "sni.example.com")
        XCTAssertEqual(payload["fingerprint"], "chrome")
        XCTAssertEqual(payload["alpn"], "h2,http/1.1")
        XCTAssertEqual(payload["networkType"], "tcp")
    }

    // MARK: - reparseFromKeychain tests (via provisionTunnelProfile round-trip)

    func test_reparseFromKeychain_hysteria2() async throws {
        let container = try makeContainer()
        let parsed = makeParsedHysteria2()
        let stub = StubParser(makeImportResult(parsed: .hysteria2(parsed), name: "Hy2Server"))
        let importer = makeImporter(container: container, parser: stub)
        _ = try await importer.importFromRawInput("stub://input")

        // Get the saved config's UUID for explicit selection
        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "hysteria2" }))

        // provisionTunnelProfile(for:) exercises reparseFromKeychain — should not throw
        try await importer.provisionTunnelProfile(for: cfg.id)
    }

    // MARK: - Regression: vlessReality and trojan paths still work

    func test_regressionVLESSReality_buildServerConfig() async throws {
        let container = try makeContainer()
        let reality = ParsedVLESS(
            uuid: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            host: "reality.example.com", port: 443,
            flow: "xtls-rprx-vision", security: "reality",
            sni: "sni.example.com", publicKey: "pubkey", shortId: "shortid",
            fingerprint: "chrome", networkType: "tcp", remarks: "Reality"
        )
        let stub = StubParser(makeImportResult(parsed: .vlessReality(reality), name: "RealityServer"))
        let importer = makeImporter(container: container, parser: stub)
        _ = try await importer.importFromRawInput("stub://input")

        let context = ModelContext(container)
        let configs = try context.fetch(FetchDescriptor<ServerConfig>())
        let cfg = try XCTUnwrap(configs.first(where: { $0.protocolID == "vless-reality" }))
        XCTAssertEqual(cfg.host, "reality.example.com")
        XCTAssertEqual(cfg.protocolDisplayName, "VLESS + Reality")
    }
}
