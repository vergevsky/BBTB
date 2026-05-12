import XCTest
import Foundation
import SwiftData
@testable import ConfigParser
@testable import VPNCore
@testable import ServerListFeature

/// Phase 3 / Plan 04 / Task 1 RED — `ServerListViewModel.deleteServer` /
/// `confirmDeleteSubscription` cascade behaviour (D-07).
///
/// - deleteServer удаляет ServerConfig + Keychain entry; clears selection if
///   selectedServerID == id.
/// - confirmDeleteSubscription удаляет Subscription + linked ServerConfigs +
///   Keychain entries; не трогает orphan-серверы; clears selection если selected был в подписке.
///
/// Файл должен FAIL до Task 2: requires `deleteServer` / `confirmDeleteSubscription` /
/// `importer` параметр / fetcher injection.
@MainActor
final class CascadeDeleteTests: XCTestCase {

    // MARK: Test doubles (mirror PullToRefreshTests)

    private final class NoopProbe: ServerProbing, @unchecked Sendable {
        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            return AsyncStream { cont in cont.finish() }
        }
    }

    private final class StubFetcher: SubscriptionURLFetching, @unchecked Sendable {
        func fetch(url: URL) async throws -> SubscriptionFetchResult {
            return SubscriptionFetchResult(
                body: Data(),
                metadata: SubscriptionMetadata(title: nil, updateInterval: nil, userInfo: nil),
                finalURL: url
            )
        }
    }

    private final class StubParser: UniversalImportParsing, @unchecked Sendable {
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult {
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: source, metadata: nil)
        }
    }

    private final class StubImporter: ConfigImporting, @unchecked Sendable {
        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            ImportResult(supported: [], unsupported: [], failed: [], subscriptionURL: nil, source: source, metadata: nil)
        }
        func importFromPasteboard() async throws -> ImportResult {
            try await importFromRawInput("", source: .pasteboard)
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            try await importFromRawInput(scanned, source: .qrCode)
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
            if case .supported = server {
                let id = UUID()
                return KeychainPersistResult(id: id, tag: "bbtb-config-\(id.uuidString)")
            }
            return nil
        }
        func buildServerConfig(from server: ImportedServer, id: UUID,
                                subscriptionID: UUID, keychainTag: String?) -> ServerConfig
        {
            ServerConfig(id: id, name: server.displayName, host: "stub", port: 443,
                         protocolID: "vless-reality", keychainTag: keychainTag,
                         isSupported: server.isSupportedFlag, subscriptionID: subscriptionID)
        }
        // Plan 05 — no-op stub (CascadeDeleteTests не covering provision-связанные пути).
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
        // Phase 5 Wave 8 — no-op stub.
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    private final class MockCoordinator: ServerSelectionCoordinating {
        var selectedServerID: UUID?
        var appliedCalls: [UUID?] = []
        var dismissCalls = 0
        init(selectedServerID: UUID? = nil) { self.selectedServerID = selectedServerID }
        func applySelection(_ id: UUID?) {
            selectedServerID = id
            appliedCalls.append(id)
        }
        func dismissServerList() { dismissCalls += 1 }
    }

    // MARK: Fixtures

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    /// Сохраняет настоящий Keychain entry для tag, чтобы проверить cleanup.
    /// Если KeychainStore.save throws (в CI / некоторых средах) — тест продолжает,
    /// проверяя лишь database cleanup. Реальный Keychain проверяется отдельным тестом
    /// при доступности.
    private func tryStoreKeychain(tag: String) -> Bool {
        do {
            try KeychainStore.save(secret: Data("dummy".utf8), tag: tag)
            return true
        } catch {
            return false
        }
    }

    private func keychainExists(tag: String) -> Bool {
        do {
            _ = try KeychainStore.load(tag: tag)
            return true
        } catch {
            return false
        }
    }

    private func makeViewModel(container: ModelContainer,
                                coordinator: ServerSelectionCoordinating? = nil) -> ServerListViewModel
    {
        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: NoopProbe(),
            importer: StubImporter(),
            fetcher: StubFetcher(),
            parser: StubParser()
        )
        vm.coordinator = coordinator
        return vm
    }

    // MARK: Tests

    func test_delete_serverconfig_removes_keychain() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let tag = "bbtb-config-test-\(UUID().uuidString)"
        let srvID = UUID()
        let srv = ServerConfig(
            id: srvID, name: "S", host: "s.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: tag, isSupported: true
        )
        context.insert(srv)
        try context.save()
        let kcStored = tryStoreKeychain(tag: tag)

        let vm = makeViewModel(container: container)

        await vm.deleteServer(id: srvID)

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 0, "ServerConfig должен быть удалён")
        if kcStored {
            XCTAssertFalse(keychainExists(tag: tag), "Keychain entry должен быть удалён")
        }
    }

    func test_delete_subscription_cascades_to_serverconfigs() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/a", name: "A", lastFetched: nil)
        context.insert(sub)
        var tags: [String] = []
        for i in 0..<3 {
            let tag = "bbtb-config-cascade-\(i)-\(UUID().uuidString)"
            tags.append(tag)
            let srv = ServerConfig(
                id: UUID(), name: "S\(i)", host: "h\(i).example.com", port: 443,
                protocolID: "vless-reality", keychainTag: tag, isSupported: true,
                subscriptionID: sub.id
            )
            context.insert(srv)
        }
        try context.save()
        let kcStoredAll = tags.map { tryStoreKeychain(tag: $0) }

        let vm = makeViewModel(container: container)

        await vm.confirmDeleteSubscription(sub)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ServerConfig>()).count, 0,
                       "Все linked ServerConfig должны быть удалены")
        XCTAssertEqual(try context.fetch(FetchDescriptor<Subscription>()).count, 0,
                       "Subscription должна быть удалена")
        for (tag, stored) in zip(tags, kcStoredAll) {
            if stored {
                XCTAssertFalse(keychainExists(tag: tag), "Keychain entry \(tag) должен быть удалён")
            }
        }
    }

    func test_delete_subscription_does_not_touch_orphan_servers() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/b", name: "B", lastFetched: nil)
        context.insert(sub)
        for i in 0..<2 {
            let srv = ServerConfig(
                id: UUID(), name: "S\(i)", host: "h\(i).example.com", port: 443,
                protocolID: "vless-reality", keychainTag: nil, isSupported: true,
                subscriptionID: sub.id
            )
            context.insert(srv)
        }
        let orphan = ServerConfig(
            id: UUID(), name: "Orphan", host: "orphan.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: nil
        )
        context.insert(orphan)
        try context.save()

        let vm = makeViewModel(container: container)
        await vm.confirmDeleteSubscription(sub)

        let rows = try context.fetch(FetchDescriptor<ServerConfig>())
        XCTAssertEqual(rows.count, 1, "Только orphan должен остаться")
        XCTAssertEqual(rows.first?.host, "orphan.example.com")
    }

    func test_delete_subscription_clears_selected_when_selected() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let sub = Subscription(url: "https://sub.example/c", name: "C", lastFetched: nil)
        context.insert(sub)
        let srvID = UUID()
        let srv = ServerConfig(
            id: srvID, name: "S", host: "s.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: sub.id
        )
        context.insert(srv)
        try context.save()

        let coord = MockCoordinator(selectedServerID: srvID)
        let vm = makeViewModel(container: container, coordinator: coord)

        await vm.confirmDeleteSubscription(sub)

        XCTAssertTrue(coord.appliedCalls.contains(where: { $0 == nil }),
                      "Coordinator должен получить applySelection(nil)")
        XCTAssertNil(coord.selectedServerID)
    }

    func test_delete_single_server_clears_selected_when_selected() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let srvID = UUID()
        let srv = ServerConfig(
            id: srvID, name: "S", host: "s.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true
        )
        context.insert(srv)
        try context.save()

        let coord = MockCoordinator(selectedServerID: srvID)
        let vm = makeViewModel(container: container, coordinator: coord)

        await vm.deleteServer(id: srvID)

        XCTAssertTrue(coord.appliedCalls.contains(where: { $0 == nil }))
        XCTAssertNil(coord.selectedServerID)
    }
}
