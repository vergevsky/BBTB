// LoadFromStoreIdempotencyTests.swift — Phase 6e Wave 1 M10.
//
// Verifies `ServerListViewModel.loadFromStore()` idempotency guard
// (100ms debounce + loadInProgress flag) + `confirmDeleteSubscription`
// single-tail-call refactor:
//
// Part A (collapse): early-exit branch (cascade-delete с уже-удалённой
// subscription row) и normal path конвергируют к ЕДИНСТВЕННОМУ
// `await loadFromStore()` в конце метода. Раньше было 2 calls.
//
// Part B (idempotency guard): второй вызов loadFromStore() в течение 100мс
// возвращается early без full body execution.
//
// Test seam: testing-only `lastLoadAt` / `loadInProgress` exposure через
// @testable import — но мы намеренно НЕ полагаемся на internal state; вместо
// этого считаем side-effect (counter инкремент) через test seam
// `loadFromStoreCallCountForTests`, который в production build inactive.

import XCTest
import Foundation
import SwiftData
@testable import ConfigParser
@testable import VPNCore
@testable import ServerListFeature

@MainActor
final class LoadFromStoreIdempotencyTests: XCTestCase {

    // MARK: - Test doubles

    private final class MockProbe: ServerProbing, @unchecked Sendable {
        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            return AsyncStream { cont in cont.finish() }
        }
    }

    private final class MockFetcher: SubscriptionURLFetching, @unchecked Sendable {
        func fetch(url: URL) async throws -> SubscriptionFetchResult {
            return SubscriptionFetchResult(body: Data(),
                                            metadata: SubscriptionMetadata(title: nil, updateInterval: nil, userInfo: nil),
                                            finalURL: url)
        }
    }

    private final class MockParser: UniversalImportParsing, @unchecked Sendable {
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult {
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: source, metadata: nil)
        }
    }

    private final class MockImporter: ConfigImporting, @unchecked Sendable {
        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: source, metadata: nil)
        }
        func importFromPasteboard() async throws -> ImportResult {
            return try await importFromRawInput("", source: .pasteboard)
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            return try await importFromRawInput("", source: .qrCode)
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? { nil }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            return ServerConfig(id: id, name: "stub", host: "stub", port: 443,
                                protocolID: "vless-reality", keychainTag: keychainTag,
                                isSupported: true, subscriptionID: subscriptionID)
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func makeViewModel(container: ModelContainer) -> ServerListViewModel {
        ServerListViewModel(
            modelContainer: container,
            probeService: MockProbe(),
            importer: MockImporter(),
            fetcher: MockFetcher(),
            parser: MockParser()
        )
    }

    // MARK: - Tests

    /// Test 1 — confirmDeleteSubscription нормальный path: loadFromStore вызывается
    /// ровно один раз (был 2 на cascade-delete normal path до Phase 6e M10).
    func test_confirmDeleteSubscription_calls_loadFromStore_exactly_once() async throws {
        let container = try makeContainer()
        let sub = Subscription(url: "https://sub.example/x", name: "X", lastFetched: nil)
        let srv = ServerConfig(id: UUID(), name: "S1", host: "s.example.com", port: 443,
                                protocolID: "vless-reality", keychainTag: nil,
                                isSupported: true, subscriptionID: sub.id)
        let context = ModelContext(container)
        context.insert(sub)
        context.insert(srv)
        try context.save()

        let vm = makeViewModel(container: container)
        // Сброс test-seam counter в 0 перед operation.
        vm.resetLoadFromStoreCallCountForTests()

        await vm.confirmDeleteSubscription(sub)

        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 1,
                       "confirmDeleteSubscription normal path: ровно ОДИН loadFromStore")
        // Sanity: subscription удалена.
        XCTAssertNil(vm.pendingDeleteSubscription,
                     "pendingDeleteSubscription очищается после confirm")
    }

    /// Test 2 — confirmDeleteSubscription early-exit branch (subscription уже
    /// удалена в другом контексте) — loadFromStore ровно один раз.
    /// До Phase 6e M10: 1 call в early-exit branch (line ~312); теперь tail-call.
    func test_confirmDeleteSubscription_early_exit_branch_calls_loadFromStore_exactly_once() async throws {
        let container = try makeContainer()
        // Создаём subscription через caller-side context. Внутри vm.confirmDeleteSubscription
        // создаётся НОВЫЙ ModelContext (`let context = ModelContext(modelContainer)`),
        // в котором этой subscription нет → early-exit branch.
        let sub = Subscription(url: "https://sub.example/orphan", name: "orphan", lastFetched: nil)
        // НЕ insert в container — caller-side construct без save → confirmDeleteSubscription
        // не найдёт row в фресk ModelContext.

        let vm = makeViewModel(container: container)
        vm.resetLoadFromStoreCallCountForTests()

        await vm.confirmDeleteSubscription(sub)

        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 1,
                       "confirmDeleteSubscription early-exit branch: ровно ОДИН loadFromStore (раньше тоже было 1, но при normal path было 2)")
    }

    /// Test 3 — loadFromStore вызванный дважды подряд в течение 100мс: второй
    /// вызов возвращается через debounce guard и НЕ выполняет full body.
    /// Idempotency guard counter инкрементится только в успешных executions.
    func test_loadFromStore_debounce_within_100ms_skips_second_call() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)
        vm.resetLoadFromStoreCallCountForTests()

        // First call — full body executes.
        await vm.loadFromStoreForTests()
        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 1,
                       "Первый loadFromStore выполняет full body")

        // Second call within 100ms — debounce должен skip-нуть.
        await vm.loadFromStoreForTests()
        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 1,
                       "Второй вызов в течение 100ms debounce window — early-return без body exec")
    }

    /// Test 4 — после 100ms debounce window — следующий вызов loadFromStore
    /// снова выполняет full body.
    func test_loadFromStore_after_100ms_executes_full_body() async throws {
        let container = try makeContainer()
        let vm = makeViewModel(container: container)
        vm.resetLoadFromStoreCallCountForTests()

        await vm.loadFromStoreForTests()
        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 1)

        // Wait > 100ms.
        try await Task.sleep(nanoseconds: 130_000_000) // 130ms

        await vm.loadFromStoreForTests()
        XCTAssertEqual(vm.loadFromStoreCallCountForTests, 2,
                       "После 100ms debounce — снова full body execution")
    }
}
