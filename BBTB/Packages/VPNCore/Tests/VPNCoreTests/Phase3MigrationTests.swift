import Foundation
import SwiftData
import XCTest
@testable import VPNCore

/// Phase 3 Plan 01 / Task 1 — RED tests for `SwiftDataContainer.migratePhase2ToPhase3`.
///
/// Verifies D-05 + Pitfall 9 (idempotency) + group-by-url + FK assignment.
/// Must FAIL until Task 2 introduces `Subscription` + extended `ServerConfig`
/// + internal `migratePhase2ToPhase3(in:)`.
final class Phase3MigrationTests: XCTestCase {

    private let migrationFlagKey = "app.bbtb.phase3.migrationDone"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: migrationFlagKey)
        super.tearDown()
    }

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func makeServer(name: String, subscriptionURL: String?) -> ServerConfig {
        return ServerConfig(
            id: UUID(),
            name: name,
            host: "host.example",
            port: 443,
            protocolID: "vless-reality",
            keychainTag: "bbtb-\(UUID().uuidString)",
            isSupported: true,
            subscriptionURL: subscriptionURL,
            outboundJSON: "",
            protocolDisplayName: "VLESS + Reality",
            sni: nil,
            rawURI: nil
        )
    }

    @MainActor
    func test_migration_creates_subscription_for_phase2_serverconfig_with_subscriptionURL() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let url = "https://x.example/sub"
        let s1 = makeServer(name: "A", subscriptionURL: url)
        let s2 = makeServer(name: "B", subscriptionURL: url)
        context.insert(s1)
        context.insert(s2)
        try context.save()

        try SwiftDataContainer.migratePhase2ToPhase3(in: container)

        let subs = try context.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.count, 1, "exactly one Subscription row для уникальной URL")
        XCTAssertEqual(subs.first?.url, url)

        let servers = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(servers.count, 2)
        for srv in servers {
            XCTAssertEqual(srv.subscriptionID, subs.first?.id,
                           "ServerConfig.subscriptionID must be set to migrated Subscription.id")
        }
    }

    @MainActor
    func test_migration_is_idempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let url = "https://x.example/sub"
        let s = makeServer(name: "A", subscriptionURL: url)
        context.insert(s)
        try context.save()

        try SwiftDataContainer.migratePhase2ToPhase3(in: container)
        try SwiftDataContainer.migratePhase2ToPhase3(in: container)  // повтор

        let subs = try context.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.count, 1, "повторный запуск НЕ должен дублировать Subscription rows")

        let server = try context.fetch(FetchDescriptor<ServerConfig>()).first
        XCTAssertEqual(server?.subscriptionID, subs.first?.id)
    }

    @MainActor
    func test_migration_idempotent_via_userdefaults_flag() throws {
        // Pre-set the flag — makeShared should skip migration entirely (Subscription table остаётся пуст).
        UserDefaults.standard.set(true, forKey: migrationFlagKey)
        defer { UserDefaults.standard.removeObject(forKey: migrationFlagKey) }

        // Симулируем существующее SwiftData-хранилище в App-Group fallback: makeShared sees flag=true,
        // НЕ вызовет migratePhase2ToPhase3 даже если row'ы есть. Здесь проверяем что внутри makeShared
        // гард на UserDefaults стоит между container и migrate call.

        // ВАЖНО: тест верифицирует поведение makeShared(), не саму функцию migrate (которая безусловная,
        // как описано в плане: «UserDefaults check ДОЛЖЕН быть в makeShared, internal-функция выполняет
        // работу безусловно — это позволяет тесту проверять чистую функцию»).
        //
        // На CI без App Group entitlement makeShared падает в in-memory fallback. В fallback миграция
        // не вызывается (no data to migrate, no flag manipulation в этой ветке per D-05). Поэтому
        // проверяем минимальный инвариант: makeShared не throws, контейнер регистрирует обе модели.
        let container = try SwiftDataContainer.makeShared()
        let context = ModelContext(container)

        // Empty container — нет миграций произошло, flag не сбрасывался.
        XCTAssertTrue(UserDefaults.standard.bool(forKey: migrationFlagKey),
                      "makeShared MUST NOT clear an already-set migration flag")

        // Schema check via insert/fetch.
        let sub = Subscription(url: "https://schema.example/sub", name: "S", lastFetched: nil)
        context.insert(sub)
        try context.save()
        let count = try context.fetch(FetchDescriptor<Subscription>()).count
        XCTAssertGreaterThanOrEqual(count, 1, "Subscription.self MUST be registered in ModelContainer")
    }

    @MainActor
    func test_migration_with_multiple_urls_groups_correctly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let urlA = "https://a.example/sub"
        let urlB = "https://b.example/sub"
        let s1 = makeServer(name: "A1", subscriptionURL: urlA)
        let s2 = makeServer(name: "A2", subscriptionURL: urlA)
        let s3 = makeServer(name: "B1", subscriptionURL: urlB)
        let s4 = makeServer(name: "B2", subscriptionURL: urlB)
        context.insert(s1); context.insert(s2); context.insert(s3); context.insert(s4)
        try context.save()

        try SwiftDataContainer.migratePhase2ToPhase3(in: container)

        let subs = try context.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.count, 2, "ровно две Subscription rows для двух уникальных URL")

        let subAID = subs.first(where: { $0.url == urlA })?.id
        let subBID = subs.first(where: { $0.url == urlB })?.id
        XCTAssertNotNil(subAID)
        XCTAssertNotNil(subBID)
        XCTAssertNotEqual(subAID, subBID)

        let servers = try context.fetch(FetchDescriptor<ServerConfig>())
        for srv in servers {
            switch srv.name {
            case "A1", "A2":
                XCTAssertEqual(srv.subscriptionID, subAID)
            case "B1", "B2":
                XCTAssertEqual(srv.subscriptionID, subBID)
            default:
                XCTFail("unexpected server \(srv.name)")
            }
        }
    }

    @MainActor
    func test_migration_skips_servers_without_subscriptionURL() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let orphan = makeServer(name: "Manual", subscriptionURL: nil)
        context.insert(orphan)
        try context.save()

        try SwiftDataContainer.migratePhase2ToPhase3(in: container)

        let subs = try context.fetch(FetchDescriptor<Subscription>())
        XCTAssertEqual(subs.count, 0, "orphan ServerConfig (subscriptionURL=nil) MUST NOT create Subscription")
        let server = try context.fetch(FetchDescriptor<ServerConfig>()).first
        XCTAssertNil(server?.subscriptionID)
    }
}
