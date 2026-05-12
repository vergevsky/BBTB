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
/// Должны падать (RED) до Task 3: требуется `UniversalImportParsing` protocol +
/// `ConfigImporter` init с `parser:` принимающим этот protocol +
/// `TunnelProvisioning` protocol для skip NETunnelProviderManager calls в тестах.
///
/// **Sendable note:** SwiftData @Model classes не Sendable — нельзя возвращать
/// `[ServerConfig]` / `[Subscription]` из `MainActor.run`. Все fetch'ы выполнены
/// внутри блоков, наружу выходят только Sendable-значения (UUID, count, String, Date, Bool).
@MainActor
final class ConfigImporterSubscriptionTests: XCTestCase {

    // MARK: Test doubles

    /// Стаб парсера — возвращает заранее заданный `ImportResult`.
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

    /// Sendable snapshot Subscription row (для возврата из MainActor.run наружу).
    private struct SubscriptionSnapshot: Sendable {
        let id: UUID
        let url: String
        let name: String
        let lastFetched: Date?
    }

    /// Sendable snapshot ServerConfig.
    private struct ServerSnapshot: Sendable {
        let id: UUID
        let name: String
        let isSupported: Bool
        let subscriptionID: UUID?
    }

    // MARK: Fixtures

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func makeSupportedVLESS(name: String) -> ImportedServer {
        let v = ParsedVLESS(
            uuid: UUID(),
            host: "vless.example.com",
            port: 443,
            flow: "",
            security: "reality",
            sni: "vless.example.com",
            publicKey: "fakePublicKeyZ12345678901234567890ABCDEF",
            shortId: "0123abcd",
            fingerprint: "chrome",
            networkType: "tcp",
            remarks: nil
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

    // Helpers — на @MainActor (наследует от класса).
    private func snapshotSubscriptions(in container: ModelContainer) throws -> [SubscriptionSnapshot] {
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<Subscription>())
        return rows.map { SubscriptionSnapshot(id: $0.id, url: $0.url, name: $0.name, lastFetched: $0.lastFetched) }
    }

    private func snapshotServers(in container: ModelContainer) throws -> [ServerSnapshot] {
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        return rows.map { ServerSnapshot(id: $0.id, name: $0.name, isSupported: $0.isSupported, subscriptionID: $0.subscriptionID) }
    }

    // MARK: Tests

    func test_import_subscription_url_creates_new_subscription_when_none() async throws {
        let container = try makeContainer()
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

        let subs = try snapshotSubscriptions(in: container)
        XCTAssertEqual(subs.count, 1, "ровно один Subscription создан")
        XCTAssertEqual(subs.first?.url, "https://x.example/sub-new")
        XCTAssertEqual(subs.first?.name, "BBTB Sub")
        let lf = try XCTUnwrap(subs.first?.lastFetched)
        XCTAssertLessThan(abs(lf.timeIntervalSinceNow), 5.0, "lastFetched должен быть свежий")

        let supported = try snapshotServers(in: container).filter { $0.isSupported }
        XCTAssertEqual(supported.count, 2)
        for srv in supported {
            XCTAssertEqual(srv.subscriptionID, subs.first?.id,
                           "ServerConfig.subscriptionID должен быть равен sub.id")
        }
    }

    func test_import_subscription_url_reuses_existing_subscription_same_url() async throws {
        let container = try makeContainer()
        let url = "https://x.example/sub-existing"
        let oldDate = Date(timeIntervalSinceNow: -3600)

        // Pre-seed: вставляем Subscription с тем же url.
        let preSeedID = UUID()
        do {
            let context = ModelContext(container)
            let existing = Subscription(id: preSeedID, url: url, name: "Old", lastFetched: oldDate)
            context.insert(existing)
            try context.save()
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

        let subs = try snapshotSubscriptions(in: container)
        XCTAssertEqual(subs.count, 1, "повторный импорт того же URL НЕ создаёт второй Subscription")
        XCTAssertEqual(subs.first?.id, preSeedID, "должен переиспользовать существующий row")
        let lf = try XCTUnwrap(subs.first?.lastFetched)
        XCTAssertGreaterThan(lf, oldDate, "lastFetched должен быть обновлён на текущее время")
    }

    func test_import_single_paste_creates_orphan_servers() async throws {
        let container = try makeContainer()
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

        let subs = try snapshotSubscriptions(in: container)
        XCTAssertEqual(subs.count, 0, "single paste НЕ создаёт Subscription")

        let servers = try snapshotServers(in: container)
        XCTAssertEqual(servers.count, 1)
        XCTAssertNil(servers.first?.subscriptionID,
                     "single-paste server должен иметь subscriptionID == nil (orphan)")
    }

    // MARK: T-03-01 sanitization (auto-fix via Rule 2: security correctness)

    func test_subscription_name_sanitized_strips_control_chars_and_clamps_length() async throws {
        // Malicious Profile-Title с control chars и сверхдлинной строкой.
        let evilTitle = "Hello\n\r\tworld" + String(repeating: "X", count: 200)
        let container = try makeContainer()
        let pre = makeImportResult(
            subURL: "https://evil.example/sub",
            title: evilTitle,
            servers: [makeSupportedVLESS(name: "S1")]
        )
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.test.tunnel",
            parser: StubParser(pre),
            tunnelProvisioner: StubTunnelProvisioner()
        )

        _ = try await importer.importFromRawInput("dummy", source: .pasteboard)

        let subs = try snapshotSubscriptions(in: container)
        let name = try XCTUnwrap(subs.first?.name)
        XCTAssertFalse(name.contains("\n"), "T-03-01: newline должен быть выпилен")
        XCTAssertFalse(name.contains("\r"), "T-03-01: carriage return должен быть выпилен")
        XCTAssertFalse(name.contains("\t"), "T-03-01: tab должен быть выпилен")
        XCTAssertLessThanOrEqual(name.count, 100, "T-03-01: name clamped до 100 chars")
    }
}
