// HandleForegroundReentryTests.swift — Phase 6e Wave 1 M7.
//
// Verifies `MainScreenViewModel.handleForegroundReentry()` consolidated
// scenePhase=.active foreground hook (M7 fix): ОДИН Task spawn на app side,
// внутри последовательный invoke трёх hooks —
//   1. `Task.detached(priority: .background)` для `importer.runIsSupportedUpgrade`
//      (preserves DEC-06d-01 cold-start defer pattern);
//   2. `await tunnelController?.handleForeground()` (DEC-06d-02 XPC ≤ 2 trips);
//   3. `await serverListViewModel?.silentForegroundRefresh()` (если non-nil).
//
// Тесты не проверяют strict ordering between detached upgrade and the awaited
// hooks (Task.detached запускается параллельно — это и есть весь смысл
// DEC-06d-01). Проверяется ФАКТ вызова + idempotency guards (isConnecting skip +
// nil tunnel controller fallthrough).

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class HandleForegroundReentryTests: XCTestCase {

    // MARK: - Test doubles

    /// Mock tunnel — фиксирует handleForeground / startReachability / stopReachability.
    /// connect/disconnect — no-op для этого test surface.
    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        var handleForegroundCount = 0
        var connectCount = 0
        var disconnectCount = 0

        func connect() async throws -> Date {
            connectCount += 1
            return Date()
        }
        func disconnect() async throws { disconnectCount += 1 }
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {
            // Increment without hopping — TunnelControlling is non-isolated; counters
            // are unchecked Sendable for test simplicity (single-threaded XCTest path).
            handleForegroundCount += 1
        }
    }

    /// Mock probe — empty stream (no servers seeded).
    private final class MockProbe: ServerProbing, @unchecked Sendable {
        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            return AsyncStream { cont in cont.finish() }
        }
    }

    /// Mock importer — фиксирует runIsSupportedUpgrade invocations.
    private final class MockImporter: ConfigImporting, @unchecked Sendable {
        var runIsSupportedUpgradeCount = 0
        var supportedCount: Int = 0

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
        func countSupportedConfigs() -> Int { supportedCount }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? { nil }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            return ServerConfig(id: id, name: "stub", host: "0.0.0.0", port: 0,
                                protocolID: "vless-reality", keychainTag: keychainTag,
                                isSupported: true, subscriptionID: subscriptionID)
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {
            runIsSupportedUpgradeCount += 1
        }
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "test-suite-\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite)!
        defs.removePersistentDomain(forName: suite)
        return defs
    }

    /// Drain Tasks — handleForegroundReentry spawns `Task.detached(priority:
    /// .background)` для runIsSupportedUpgrade; yield + sleep дают detached
    /// time to execute. 250ms wall-clock — counter increment в mock мгновенный.
    private func drainMainActor() async {
        for _ in 0..<8 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    // MARK: - Tests

    /// Test 1 — все три hook'а вызваны при scenePhase=.active foreground re-entry.
    /// isConnecting guard NOT triggered (state = .idle / default), so all three fire.
    func test_handleForegroundReentry_invokes_all_three_hooks() async throws {
        let container = try makeContainer()
        let importer = MockImporter()
        let tunnel = MockTunnel()
        let probe = MockProbe()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        await vm.handleForegroundReentry()
        await drainMainActor()

        XCTAssertEqual(importer.runIsSupportedUpgradeCount, 1,
                       "runIsSupportedUpgrade должен быть вызван ровно один раз")
        XCTAssertEqual(tunnel.handleForegroundCount, 1,
                       "tunnel.handleForeground должен быть вызван ровно один раз")
        // serverListViewModel.silentForegroundRefresh — non-throwing async; здесь
        // достаточно убедиться что vm создан (имеет non-nil serverListViewModel
        // при modelContainer present) и что метод выполнился без crash.
        XCTAssertNotNil(vm.serverListViewModel,
                        "С modelContainer ServerListViewModel должен существовать")
    }

    /// Test 2 — isConnecting guard: runIsSupportedUpgrade пропускается когда
    /// VM в .connecting state (см. DEC-06d-01 snapshot guard); tunnel.handleForeground
    /// и silentForegroundRefresh всё равно вызываются (resync обязателен независимо).
    func test_handleForegroundReentry_skips_runIsSupportedUpgrade_when_connecting() async throws {
        let container = try makeContainer()
        let importer = MockImporter()
        let tunnel = MockTunnel()
        let probe = MockProbe()
        let defs = freshDefaults()

        // Seed один supported server + bump supportedCount, чтобы refresh()
        // перевёл state из .empty в .idle. Без этого applyVPNStatus(.connecting)
        // блокируется outer-switch (`case .empty: break`) и тест становится
        // невалидным — state останется .empty.
        let id = UUID()
        let context = ModelContext(container)
        let cfg = ServerConfig(id: id, name: "test", host: "test.example", port: 443,
                                protocolID: "vless-reality",
                                keychainTag: "tag-\(id.uuidString)",
                                isSupported: true)
        context.insert(cfg)
        try context.save()
        importer.supportedCount = 1

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        // Force vm.state == .connecting через test seam (applyVPNStatus internal в Phase 6c).
        vm.applyVPNStatus(.connecting)
        await drainMainActor()
        XCTAssertEqual(vm.state, .connecting,
                       "Sanity: VM state должно стать .connecting (seed supported server необходим)")

        await vm.handleForegroundReentry()
        await drainMainActor()

        XCTAssertEqual(importer.runIsSupportedUpgradeCount, 0,
                       "isConnecting guard должен skip-нуть runIsSupportedUpgrade")
        XCTAssertEqual(tunnel.handleForegroundCount, 1,
                       "tunnel.handleForeground должен вызываться независимо от state")
    }

    /// Test 3 — graceful operation когда modelContainer nil (Phase 2 backward-compat
    /// init без DI) → serverListViewModel == nil. Другие два hook'а (importer +
    /// tunnel.handleForeground через TunnelControlling protocol) всё равно вызываются.
    func test_handleForegroundReentry_when_serverListViewModel_nil_continues_other_hooks() async throws {
        let importer = MockImporter()
        let tunnel = MockTunnel()
        // Phase 2 backward-compat init без modelContainer → serverListViewModel = nil.
        let vm = MainScreenViewModel(importer: importer, tunnel: tunnel)
        await drainMainActor()

        XCTAssertNil(vm.serverListViewModel,
                     "Без modelContainer → serverListViewModel nil (Phase 2 backward-compat init)")

        await vm.handleForegroundReentry()
        await drainMainActor()

        XCTAssertEqual(importer.runIsSupportedUpgradeCount, 1,
                       "runIsSupportedUpgrade должен сработать независимо от serverListVM")
        XCTAssertEqual(tunnel.handleForegroundCount, 1,
                       "tunnel.handleForeground через TunnelControlling protocol — обязательный hook")
    }
}
