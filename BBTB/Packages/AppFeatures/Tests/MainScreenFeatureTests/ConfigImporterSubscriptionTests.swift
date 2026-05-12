import XCTest
import Foundation
import SwiftData
import ConfigParser
@testable import VPNCore
@testable import MainScreenFeature

/// Phase 3 Plan 01 / Task 1 — RED tests for ConfigImporter Subscription branch.
///
/// Verifies D-05 + D-06: при `result.subscriptionURL != nil` импортёр создаёт
/// (или переиспользует) `Subscription` row и проставляет `subscriptionID` на каждом
/// persisted `ServerConfig`. Single-paste (`subscriptionURL == nil`) сохраняет Phase 2
/// orphan-behavior.
///
/// Must FAIL до Task 3 (RED): требует `UniversalImportParsing` protocol +
/// `ConfigImporter` init с `parser:` принимающим этот protocol +
/// `TunnelProvisioning` protocol для skip NETunnelProviderManager calls в тестах.
final class ConfigImporterSubscriptionTests: XCTestCase {

    // MARK: Test doubles

    /// Стаб парсера, возвращающий заранее заданный `ImportResult`.
    private final class StubParser: UniversalImportParsing, @unchecked Sendable {
        let pre: ImportResult
        init(_ pre: ImportResult) { self.pre = pre }
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult {
            return pre
        }
    }

    /// Стаб NE provisioning — захватывает вход, ничего не вызывает в OS.
    private final class StubTunnelProvisioner: TunnelProvisioning, @unchecked Sendable {
        var lastJSON: String?
        var lastHost: String?
        func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {
            self.lastJSON = configJSON
            self.lastHost = serverHost
        }
    }

    // MARK: Fixtures

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    /// Build a real `ImportedServer.supported` (VLESS+Reality fixture) — позволяет ConfigImporter
    /// пройти через persistSupported + PoolBuilder без мокания глубокой логики.
    private func makeSupportedVLESS(name: String) -> ImportedServer {
        let v = ParsedVLESS(
            host: "vless.example.com",
            port: 443,
            uuid: UUID(),
            publicKey: "fakePublicKeyZ12345678901234567890ABCDEF",
            shortId: "0123abcd",
            sni: "vless.example.com",
            fingerprint: "chrome",
            flow: ""
        )
        return .supported(name: name, parsed: .vlessReality(v),
                          rawURI: "vless://stub-\(name)")
    }

    private func makeImportResult(subURL: String?, title: String?, servers: [ImportedServer]) -> ImportResult {
        let metadata: SubscriptionMetadata? = (title != nil)
            ? SubscriptionMetadata(title: title, updateInterval: nil, userInfo: nil)
            : nil
        return ImportResult(
            supported: servers,
            unsupported: [],
            failed: [],
            subscriptionURL: subURL,
            source: subURL != nil ? .subscriptionURL(URL(string: subURL!)!) : .pasteboard,
            metadata: metadata
        )
    }

    // MARK: Tests

    func test_import_subscription_url_creates_new_subscription_when_none() async throws {
        let container = try await MainActor.run { try makeContainer() }
        let pre = makeImportResult(
            subURL: "https://x.example/sub-new",
            title: "BBTB Sub",
            servers: [makeSupportedVLESS(name: "S1"), makeSupportedVLESS(name: "S2")]
        )
        let provisioner = StubTunnelProvisioner()
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.test.tunnel",
            parser: StubParser(pre),
            tunnelProvisioner: provisioner
        )

        _ = try await importer.importFromRawInput("dummy", source: .pasteboard)

        let context = await MainActor.run { ModelContext(container) }
        let subs = try await MainActor.run { try context.fetch(FetchDescriptor<Subscription>()) }
        XCTAssertEqual(subs.count, 1, "ровно один Subscription создан")
        XCTAssertEqual(subs.first?.url, "https://x.example/sub-new")
        XCTAssertEqual(subs.first?.name, "BBTB Sub")
        // lastFetched должен быть свежий (в пределах ±5 секунд)
        let lf = try XCTUnwrap(subs.first?.lastFetched)
        XCTAssertLessThan(abs(lf.timeIntervalSinceNow), 5.0)

        let servers = try await MainActor.run {
            try context.fetch(FetchDescriptor<ServerConfig>(
                predicate: #Predicate { $0.isSupported == true }
            ))
        }
        XCTAssertEqual(servers.count, 2)
        for srv in servers {
            XCTAssertEqual(srv.subscriptionID, subs.first?.id,
                           "ServerConfig.subscriptionID должен быть равен sub.id")
        }
    }

    func test_import_subscription_url_reuses_existing_subscription_same_url() async throws {
        let container = try await MainActor.run { try makeContainer() }
        let url = "https://x.example/sub-existing"
        let oldDate = Date(timeIntervalSinceNow: -3600)

        // Pre-seed: вставляем Subscription с тем же url.
        let preSeedID: UUID = try await MainActor.run {
            let context = ModelContext(container)
            let id = UUID()
            let existing = Subscription(id: id, url: url, name: "Old", lastFetched: oldDate)
            context.insert(existing)
            try context.save()
            return id
        }

        let pre = makeImportResult(
            subURL: url,
            title: "New Title",
            servers: [makeSupportedVLESS(name: "S1")]
        )
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.test.tunnel",
            parser: StubParser(pre),
            tunnelProvisioner: StubTunnelProvisioner()
        )

        _ = try await importer.importFromRawInput("dummy", source: .pasteboard)

        let subs = try await MainActor.run {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<Subscription>())
        }
        XCTAssertEqual(subs.count, 1, "повторный импорт того же URL НЕ создаёт второй Subscription")
        XCTAssertEqual(subs.first?.id, preSeedID, "должен переиспользовать существующий row")
        let lf = try XCTUnwrap(subs.first?.lastFetched)
        XCTAssertGreaterThan(lf, oldDate, "lastFetched должен быть обновлён на текущее время")
    }

    func test_import_single_paste_creates_orphan_servers() async throws {
        let container = try await MainActor.run { try makeContainer() }
        let pre = makeImportResult(
            subURL: nil,  // single paste / .singleURI
            title: nil,
            servers: [makeSupportedVLESS(name: "Manual")]
        )
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.test.tunnel",
            parser: StubParser(pre),
            tunnelProvisioner: StubTunnelProvisioner()
        )

        _ = try await importer.importFromRawInput("dummy", source: .pasteboard)

        let subs = try await MainActor.run {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<Subscription>())
        }
        XCTAssertEqual(subs.count, 0, "single paste НЕ создаёт Subscription")

        let servers = try await MainActor.run {
            let context = ModelContext(container)
            return try context.fetch(FetchDescriptor<ServerConfig>())
        }
        XCTAssertEqual(servers.count, 1)
        XCTAssertNil(servers.first?.subscriptionID,
                     "single-paste server должен иметь subscriptionID == nil (orphan)")
    }
}
