// ApplyVPNStatusGuardTests.swift — Phase 6e Wave 1 M11.
//
// Verifies explicit early-return guard в `applyVPNStatus(.connecting / .reasserting)`
// ветке `MainScreenViewModel.applyVPNStatus(_:connectedDate:)`. Original Phase 6d
// post-fix `9b38796` уже добавил outer-level `lastAppliedVPNStatus` dedupe — этот
// M11 fix добавляет inner-level explicit guard `guard state != .connecting else { return }`
// для readability + secondary safety, документирующий intent.
//
// CRITICAL — D-09 single authority preserved:
//   - `func applyVPNStatus` definition count в MainScreenViewModel.swift = 1;
//   - outer-level lastAppliedVPNStatus guard сохранён (8k duplicate event safety net);
//   - не добавляется новых state= setters вне applyVPNStatus body.
//
// Critical regression coverage: AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects
// MUST PASS — Phase 6d post-fix re-armed `.connected → .disconnected → .connected`
// transition coverage. Early-return guard НЕ должен блокировать legitimate transitions.

import XCTest
import Foundation
import SwiftData
import NetworkExtension
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class ApplyVPNStatusGuardTests: XCTestCase {

    // MARK: - Test doubles

    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        var connectCount = 0
        var disconnectCount = 0
        func connect() async throws -> Date { connectCount += 1; return Date() }
        func disconnect() async throws { disconnectCount += 1 }
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {}
    }

    private final class MockProbe: ServerProbing, @unchecked Sendable {
        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            return AsyncStream { cont in cont.finish() }
        }
    }

    private final class MockImporter: ConfigImporting, @unchecked Sendable {
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
            return ServerConfig(id: id, name: "stub", host: "stub", port: 0,
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

    private func freshDefaults() -> UserDefaults {
        let suite = "test-suite-\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite)!
        defs.removePersistentDomain(forName: suite)
        return defs
    }

    /// Создаёт VM с одним seeded supported server (refresh() перейдёт в .idle).
    private func makeVMWithSeededServer() throws -> MainScreenViewModel {
        let container = try makeContainer()
        let importer = MockImporter()
        let id = UUID()
        let context = ModelContext(container)
        let cfg = ServerConfig(id: id, name: "test", host: "test.example", port: 443,
                                protocolID: "vless-reality",
                                keychainTag: "tag-\(id.uuidString)",
                                isSupported: true)
        context.insert(cfg)
        try context.save()
        importer.supportedCount = 1

        return MainScreenViewModel(
            importer: importer,
            tunnel: MockTunnel(),
            modelContainer: container,
            probeService: MockProbe(),
            userDefaults: freshDefaults()
        )
    }

    private func drainMainActor() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: - Tests

    /// Test 1 — idempotency: applyVPNStatus(.connecting) вызванный дважды
    /// держит state == .connecting (outer dedupe + inner early-return оба
    /// работают). Дубликаты не вызывают side-effect thrash.
    func test_applyVPNStatus_connecting_called_twice_state_stable() async throws {
        let vm = try makeVMWithSeededServer()
        await drainMainActor()

        XCTAssertEqual(vm.state, .idle, "Sanity: initial state .idle с seeded server")

        vm.applyVPNStatus(.connecting)
        XCTAssertEqual(vm.state, .connecting, "Первый apply (.connecting) переводит state .idle → .connecting")

        vm.applyVPNStatus(.connecting)
        XCTAssertEqual(vm.state, .connecting,
                       "Повторный apply (.connecting) → state остаётся .connecting (idempotent)")
    }

    /// Test 2 — legitimate transition: applyVPNStatus(.connecting) → .connected.
    /// Early-return guard в .connecting branch НЕ должен блокировать переход
    /// в .connected (другая switch ветка, другой path).
    func test_applyVPNStatus_connecting_then_connected_progresses_state() async throws {
        let vm = try makeVMWithSeededServer()
        await drainMainActor()

        vm.applyVPNStatus(.connecting)
        XCTAssertEqual(vm.state, .connecting)

        let connectAt = Date()
        vm.applyVPNStatus(.connected, connectedDate: connectAt)
        XCTAssertTrue(vm.state.isConnected,
                      "applyVPNStatus(.connected) после .connecting → state .connected (transition не блокирована)")
    }

    /// Test 3 — backward transition: applyVPNStatus(.connecting) когда state
    /// уже .connected (через предыдущий .connected apply): switch state branch
    /// `default` срабатывает (не .empty/.error/.connecting), state → .connecting.
    /// Early-return guard срабатывает ТОЛЬКО когда state УЖЕ .connecting.
    func test_applyVPNStatus_connecting_when_already_connected_falls_through_to_default_branch() async throws {
        let vm = try makeVMWithSeededServer()
        await drainMainActor()

        let connectAt = Date()
        vm.applyVPNStatus(.connected, connectedDate: connectAt)
        XCTAssertTrue(vm.state.isConnected, "Sanity: state .connected после apply(.connected)")

        // Сейчас state == .connected. apply(.connecting) → switch state default:
        // state = .connecting. Early-return guard НЕ срабатывает (state != .connecting).
        vm.applyVPNStatus(.connecting)
        XCTAssertEqual(vm.state, .connecting,
                       "apply(.connecting) при state .connected → переход в .connecting (default switch branch)")
    }
}
