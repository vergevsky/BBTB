import XCTest
import Foundation
import SwiftData
@testable import ConfigParser
@testable import VPNCore
@testable import MainScreenFeature

/// Phase 3 / Plan 04 / Task 1 RED — `SubscriptionMergeService.merge` поведение по D-14:
/// - merge by server-identity (host:port:protocolID:sni) — preserve `lastLatencyMs`,
///   `lastPingedAt`, `failedProbeCount` при совпадении.
/// - missing-from-fetch → `missingFromLastFetch = true` (не удаляется).
/// - isolation между подписками.
/// - subscription.lastFetched обновляется.
/// - unsupported servers persist'ятся с subscriptionID + keychainTag == nil.
///
/// Файл должен FAIL до Task 2: `SubscriptionMergeService` и
/// `KeychainPersistResult` ещё не существуют.
@MainActor
final class MergeStrategyTests: XCTestCase {

    // MARK: Container

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    // MARK: Helpers — фабрики ImportedServer

    private func makeVLESS(name: String,
                          host: String = "vless.example.com",
                          port: Int = 443,
                          sni: String = "vless.example.com") -> ImportedServer {
        let parsed = ParsedVLESS(
            uuid: UUID(),
            host: host,
            port: port,
            flow: "",
            security: "reality",
            sni: sni,
            publicKey: "publicKeyABC1234567890123456789012345DEFG",
            shortId: "12345678",
            fingerprint: "chrome",
            networkType: "tcp",
            remarks: nil
        )
        return .supported(name: name, parsed: .vlessReality(parsed), rawURI: "vless://stub-\(name)")
    }

    private func makeUnsupported(name: String,
                                  scheme: String = "ss",
                                  host: String = "ss.example.com",
                                  port: Int = 8388) -> ImportedServer {
        return .unsupported(name: name,
                            scheme: scheme,
                            host: host,
                            port: port,
                            rawURI: "\(scheme)://stub-\(name)",
                            reason: .schemaUnsupportedInPhase2)
    }

    // MARK: Closures, замещающие ConfigImporter helpers

    /// `persistKeychain` stub — для supported возвращает свежий KeychainPersistResult,
    /// для unsupported возвращает nil. Реальный Keychain не используем (тест-среда).
    private static func makeStubPersistKeychain() -> (ImportedServer) throws -> KeychainPersistResult? {
        return { server in
            switch server {
            case .supported:
                let id = UUID()
                return KeychainPersistResult(id: id, tag: "bbtb-config-\(id.uuidString)")
            case .unsupported, .invalid:
                return nil
            }
        }
    }

    /// `buildServerConfig` stub — собирает ServerConfig.
    /// Дублирует логику, чтобы не зависеть от concrete `ConfigImporter` в этом тесте.
    private static func makeStubBuildServerConfig() -> (ImportedServer, UUID, UUID, String?) -> ServerConfig {
        return { server, id, subID, tag in
            switch server {
            case let .supported(name, parsed, rawURI):
                let host: String
                let port: Int
                let protocolID: String
                let sni: String?
                let displayName: String
                switch parsed {
                case .vlessReality(let v):
                    host = v.host; port = v.port; sni = v.sni
                    protocolID = "vless-reality"
                    displayName = "VLESS + Reality"
                case .trojan(let t):
                    host = t.host; port = t.port; sni = t.sni
                    protocolID = "trojan"
                    displayName = "Trojan"
                }
                _ = rawURI
                return ServerConfig(
                    id: id, name: name, host: host, port: port,
                    protocolID: protocolID, keychainTag: tag, isSupported: true,
                    subscriptionURL: nil, outboundJSON: "", protocolDisplayName: displayName,
                    sni: sni, rawURI: nil, subscriptionID: subID
                )
            case let .unsupported(name, scheme, host, port, rawURI, _):
                return ServerConfig(
                    id: id, name: name, host: host, port: port,
                    protocolID: scheme, keychainTag: nil, isSupported: false,
                    subscriptionURL: nil, outboundJSON: "",
                    protocolDisplayName: "\(scheme.uppercased()) (не поддерживается)",
                    sni: nil, rawURI: rawURI, subscriptionID: subID
                )
            case .invalid:
                return ServerConfig(
                    id: id, name: "invalid", host: "0.0.0.0", port: 0,
                    protocolID: "invalid", keychainTag: nil, isSupported: false,
                    subscriptionID: subID
                )
            }
        }
    }

    // MARK: Tests

    func test_merge_new_uris_inserts_serverconfig() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sub = Subscription(url: "https://sub.example/a", name: "A", lastFetched: nil)
        context.insert(sub)
        try context.save()

        let fetched = [
            makeVLESS(name: "S1", host: "h1.example.com", port: 443, sni: "h1.example.com"),
            makeVLESS(name: "S2", host: "h2.example.com", port: 443, sni: "h2.example.com"),
        ]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetched,
            fetchedUnsupported: [],
            into: sub,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 2)
        for r in rows {
            XCTAssertEqual(r.subscriptionID, sub.id)
            XCTAssertFalse(r.missingFromLastFetch)
        }
    }

    func test_merge_existing_identity_preserves_latency() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/b", name: "B", lastFetched: nil)
        context.insert(sub)

        // Pre-seed — existing identity host=h1, port=443, protocolID=vless-reality, sni=h1
        let existingID = UUID()
        let existing = ServerConfig(
            id: existingID, name: "OldName", host: "h1.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: "bbtb-config-\(existingID.uuidString)",
            isSupported: true, subscriptionURL: nil, outboundJSON: "",
            protocolDisplayName: "VLESS + Reality", sni: "h1.example.com",
            rawURI: nil, subscriptionID: sub.id
        )
        existing.lastLatencyMs = 42
        existing.lastPingedAt = Date(timeIntervalSinceNow: -60)
        existing.failedProbeCount = 1
        context.insert(existing)
        try context.save()

        let fetched = [
            makeVLESS(name: "RefreshedName", host: "h1.example.com", port: 443, sni: "h1.example.com")
        ]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetched,
            fetchedUnsupported: [],
            into: sub,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 1, "merge by identity не должен дублировать row")
        let merged = try XCTUnwrap(rows.first)
        XCTAssertEqual(merged.id, existingID, "id сохраняется (тот же row)")
        XCTAssertEqual(merged.lastLatencyMs, 42, "latency preserved")
        XCTAssertEqual(merged.failedProbeCount, 1, "failedProbeCount preserved")
        XCTAssertEqual(merged.name, "RefreshedName", "name обновлён на новый displayName")
        XCTAssertFalse(merged.missingFromLastFetch)
    }

    func test_merge_disappeared_uris_marks_missing() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/c", name: "C", lastFetched: nil)
        context.insert(sub)

        let staleID = UUID()
        let stale = ServerConfig(
            id: staleID, name: "Stale", host: "stale.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: "bbtb-config-\(staleID.uuidString)",
            isSupported: true, subscriptionURL: nil, outboundJSON: "",
            protocolDisplayName: "VLESS + Reality", sni: "stale.example.com",
            rawURI: nil, subscriptionID: sub.id
        )
        context.insert(stale)
        try context.save()

        // fetched НЕ содержит stale.example.com
        let fetched = [makeVLESS(name: "Fresh", host: "fresh.example.com", port: 443, sni: "fresh.example.com")]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetched,
            fetchedUnsupported: [],
            into: sub,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 2, "stale row не удалён — он помечается missingFromLastFetch")
        let staleRow = try XCTUnwrap(rows.first(where: { $0.id == staleID }))
        XCTAssertTrue(staleRow.missingFromLastFetch, "stale row должен быть помечен missingFromLastFetch")
        let freshRow = try XCTUnwrap(rows.first(where: { $0.host == "fresh.example.com" }))
        XCTAssertFalse(freshRow.missingFromLastFetch)
    }

    func test_merge_updates_subscription_lastFetched() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let oldDate = Date(timeIntervalSinceNow: -3600)
        let sub = Subscription(url: "https://sub.example/d", name: "D", lastFetched: oldDate)
        context.insert(sub)
        try context.save()

        let fetched = [makeVLESS(name: "S1")]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetched,
            fetchedUnsupported: [],
            into: sub,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let lf = try XCTUnwrap(sub.lastFetched)
        XCTAssertLessThan(abs(lf.timeIntervalSinceNow), 5.0,
                          "lastFetched updated to ~now (was 1 hour ago)")
    }

    func test_merge_isolated_per_subscription() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let subA = Subscription(url: "https://sub.example/A", name: "A", lastFetched: nil)
        let subB = Subscription(url: "https://sub.example/B", name: "B", lastFetched: nil)
        context.insert(subA)
        context.insert(subB)

        // Pre-seed: sub B has a server NOT in any fetch.
        let bServerID = UUID()
        let bServer = ServerConfig(
            id: bServerID, name: "B-server", host: "b.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionURL: nil, outboundJSON: "", protocolDisplayName: "VLESS + Reality",
            sni: "b.example.com", rawURI: nil, subscriptionID: subB.id
        )
        context.insert(bServer)
        try context.save()

        // Merge subA — fetched contains только A-серверы.
        let fetchedForA = [makeVLESS(name: "A-server", host: "a.example.com", port: 443, sni: "a.example.com")]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetchedForA,
            fetchedUnsupported: [],
            into: subA,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let bRow = try XCTUnwrap(
            try context.fetch(FetchDescriptor<ServerConfig>()).first(where: { $0.id == bServerID })
        )
        XCTAssertFalse(bRow.missingFromLastFetch, "merge subA НЕ должен трогать servers из subB")
    }

    func test_merge_unsupported_servers_persist_with_subscriptionID() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/e", name: "E", lastFetched: nil)
        context.insert(sub)
        try context.save()

        let fetchedSupported = [makeVLESS(name: "S1")]
        let fetchedUnsupported = [makeUnsupported(name: "SS-stub")]

        try SubscriptionMergeService.merge(
            fetchedSupported: fetchedSupported,
            fetchedUnsupported: fetchedUnsupported,
            into: sub,
            context: context,
            persistKeychain: Self.makeStubPersistKeychain(),
            buildServerConfig: Self.makeStubBuildServerConfig()
        )
        try context.save()

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 2)
        let unsupported = try XCTUnwrap(rows.first(where: { !$0.isSupported }))
        XCTAssertEqual(unsupported.subscriptionID, sub.id)
        XCTAssertNil(unsupported.keychainTag)
    }
}
