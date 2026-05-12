// AutoSelectIntegrationTests.swift — Phase 3 / Plan 05 / Task 1 (RED).
//
// Verifies pre-connect-auto-select + reconnect-on-selection + UserDefaults persist
// + Pitfall-8/Pitfall-10 fallbacks (D-04, D-09, T-03-23, T-03-26).
//
// RED-фаза: до Task 2 в MainScreenViewModel нет:
//   - performPreConnectAutoSelect()
//   - MainScreenError enum (noReachableServers / noSupportedServers)
//   - reconnect-on-selection-change логики в applySelection
//   - UserDefaults persist для selectedServerID
//   - инъекции probeService через init + userDefaults параметр
//   - расширенного ConfigImporting.provisionTunnelProfile(for:)
//
// Тесты падают (compile-fail), пока эти API не реализованы.
//
// **Sendable note:** не возвращаем @Model classes из @MainActor.run наружу — все
// инстансы (ConfigImporter, MainScreenViewModel, ModelContainer) создаются и
// потребляются внутри @MainActor контекста (XCTestCase + @MainActor).

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class AutoSelectIntegrationTests: XCTestCase {

    // MARK: - Test doubles

    /// Mock probe-service. Возвращает заранее заданный набор (UUID → ProbeAggregate)
    /// через AsyncStream. Используется в pre-connect-auto-select сценариях.
    private final class MockProbeService: ServerProbing, @unchecked Sendable {
        let aggregates: [UUID: ProbeAggregate]
        init(_ aggregates: [UUID: ProbeAggregate]) { self.aggregates = aggregates }
        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            let map = self.aggregates
            return AsyncStream { cont in
                for srv in servers {
                    let agg = map[srv.id] ?? ProbeAggregate(
                        avgLatencyMs: nil, lossRate: 1.0, probedAt: Date()
                    )
                    cont.yield((srv.id, agg))
                }
                cont.finish()
            }
        }
    }

    /// Mock tunnel — фиксирует, был ли вызван connect / disconnect. connect возвращает
    /// контролируемую Date (since), disconnect просто отмечается.
    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        var connectCount = 0
        var disconnectCount = 0
        var nextConnectDate: Date = Date()
        var nextConnectError: Error?

        func connect() async throws -> Date {
            connectCount += 1
            if let e = nextConnectError { throw e }
            return nextConnectDate
        }
        func disconnect() async throws {
            disconnectCount += 1
        }
    }

    /// Mock importer — фиксирует последний `provisionTunnelProfile(for:)` UUID-аргумент.
    /// Также реализует остальные `ConfigImporting` методы как no-op.
    private final class MockImporter: ConfigImporting, @unchecked Sendable {
        // Plan 05 — провижионинг: каждый вызов сохраняет переданный selectedID
        // (nil если auto-mode). Capture is per-call (массив, не single var) —
        // тесты могут verify total count и порядок аргументов.
        var provisionCalls: [UUID?] = []
        var provisionError: Error?
        var supportedCount: Int = 0
        var activeServer: ServerConfig?

        // Plan 05 NEW — protocol method.
        func provisionTunnelProfile(for selectedID: UUID?) async throws {
            provisionCalls.append(selectedID)
            if let e = provisionError { throw e }
        }

        // Existing protocol surface — no-op для интеграционных тестов.
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
        func loadActiveServer() -> ServerConfig? { activeServer }
        func countSupportedConfigs() -> Int { supportedCount }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
            nil
        }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig
        {
            return ServerConfig(id: id, name: "stub", host: "0.0.0.0", port: 0,
                                protocolID: "vless-reality", keychainTag: keychainTag,
                                isSupported: true, subscriptionID: subscriptionID)
        }
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    /// Seed supported ServerConfig + return tuple (id, host, port).
    @discardableResult
    private func seedServer(in container: ModelContainer,
                            name: String,
                            host: String,
                            port: Int = 443) throws -> UUID
    {
        let id = UUID()
        let context = ModelContext(container)
        let cfg = ServerConfig(id: id, name: name, host: host, port: port,
                                protocolID: "vless-reality",
                                keychainTag: "tag-\(id.uuidString)",
                                isSupported: true)
        context.insert(cfg)
        try context.save()
        return id
    }

    /// Создаёт isolated UserDefaults suite для теста — гарантирует, что persistance
    /// не утекает между тестами.
    private func freshDefaults() -> UserDefaults {
        let suite = "test-suite-\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite)!
        defs.removePersistentDomain(forName: suite)
        return defs
    }

    private func aggOK(_ ms: Int) -> ProbeAggregate {
        ProbeAggregate(avgLatencyMs: ms, lossRate: 0.0, probedAt: Date())
    }
    private var aggUnreach: ProbeAggregate {
        ProbeAggregate(avgLatencyMs: nil, lossRate: 1.0, probedAt: Date())
    }

    /// Drain pending tasks — viewmodel может вызвать `Task { @MainActor in ... }`
    /// внутри applySelection. Используем `Task.yield()` через короткое ожидание.
    private func drainMainActor() async {
        for _ in 0..<10 {
            await Task.yield()
        }
        // Подождать чуть-чуть на случай asynchronous Task внутри applySelection.
        try? await Task.sleep(nanoseconds: 100_000_000)
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    // MARK: - Tests

    /// T1 — Auto-mode (selectedServerID == nil): pre-connect ping → autoSelect (min score) →
    /// provisionTunnelProfile(for: winnerID) → connect.
    func test_pre_connect_auto_select_picks_min_score_server() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")
        let idB = try seedServer(in: container, name: "B", host: "b.example")
        let idC = try seedServer(in: container, name: "C", host: "c.example")

        let probe = MockProbeService([
            idA: aggOK(100),
            idB: aggOK(50),    // winner
            idC: aggOK(200),
        ])
        let tunnel = MockTunnel()
        let importer = MockImporter()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        // Перенесём state в .idle (refresh() ставит .idle если есть supported).
        await drainMainActor()
        // FORCE state.idle: при наличии supported configs refresh() уже сделает это.

        XCTAssertNil(vm.selectedServerID, "Auto mode — selectedServerID nil")
        vm.toggleConnection()
        await drainMainActor()

        XCTAssertEqual(importer.provisionCalls.count, 1)
        XCTAssertEqual(importer.provisionCalls.first ?? nil, idB,
                       "Auto-select winner = B (min score, 50ms)")
        XCTAssertEqual(tunnel.connectCount, 1)
        XCTAssertTrue(vm.state.isConnected, "State после успешного connect = .connected")
    }

    /// T2 — Pitfall 8: все unreachable → state .error с L10n.serverListNoReachableServers,
    /// connect НЕ вызывается.
    func test_pre_connect_all_unreachable_returns_error() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")
        let idB = try seedServer(in: container, name: "B", host: "b.example")

        let probe = MockProbeService([
            idA: aggUnreach,
            idB: aggUnreach,
        ])
        let tunnel = MockTunnel()
        let importer = MockImporter()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        vm.toggleConnection()
        await drainMainActor()

        XCTAssertEqual(importer.provisionCalls.count, 0,
                       "При всех unreachable provisionTunnelProfile НЕ вызывается")
        XCTAssertEqual(tunnel.connectCount, 0, "Connect НЕ должен быть вызван")
        if case .error(let msg) = vm.state {
            XCTAssertTrue(msg.localizedCaseInsensitiveContains("недоступн")
                          || msg.localizedCaseInsensitiveContains("unreachable")
                          || msg.localizedCaseInsensitiveContains("reachable"),
                          "Сообщение должно сигнализировать «недоступны» (получено: \(msg))")
        } else {
            XCTFail("Ожидался .error, получено: \(vm.state)")
        }
    }

    /// T3 — Manual selection (selectedServerID != nil): provisionTunnelProfile(for: serverX.id)
    /// вызывается напрямую, БЕЗ pre-connect ping всех серверов (autoSelect skipped).
    func test_manual_selected_server_skips_auto_select() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")
        let idB = try seedServer(in: container, name: "B", host: "b.example")

        // Если бы probeService вернул idB как winner — мы бы increment'нули мимо idA.
        // Тест должен показать, что ping вообще не управляет решением.
        let probe = MockProbeService([
            idA: aggUnreach,
            idB: aggOK(10),
        ])
        let tunnel = MockTunnel()
        let importer = MockImporter()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        // Manual selection — idA (даже если probe = unreach).
        vm.applySelection(idA)
        await drainMainActor()
        // applySelection не должен сам connect когда tunnel idle (только запоминает).
        // Сначала зафиксируем counter до toggle:
        let provisionBefore = importer.provisionCalls.count
        let connectBefore = tunnel.connectCount

        vm.toggleConnection()
        await drainMainActor()

        XCTAssertEqual(importer.provisionCalls.count, provisionBefore + 1)
        XCTAssertEqual(importer.provisionCalls.last ?? nil, idA,
                       "Manual selection → provision с manually выбранным idA")
        XCTAssertEqual(tunnel.connectCount, connectBefore + 1)
    }

    /// T4 — applySelection во время active tunnel: disconnect → provision → connect, без alert.
    func test_selection_change_during_active_tunnel_reconnects() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")
        let idB = try seedServer(in: container, name: "B", host: "b.example")

        let probe = MockProbeService([
            idA: aggOK(50),
            idB: aggOK(100),
        ])
        let tunnel = MockTunnel()
        tunnel.nextConnectDate = Date()
        let importer = MockImporter()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        // Initial connect (manual idA):
        vm.applySelection(idA)
        await drainMainActor()
        vm.toggleConnection()
        await drainMainActor()
        XCTAssertEqual(tunnel.connectCount, 1)
        XCTAssertTrue(vm.state.isConnected, "Initial connect успешен")

        // Smena selection во время .connected — должна reconnect автоматически.
        vm.applySelection(idB)
        await drainMainActor()

        // disconnect + connect: счётчики должны increment'иться.
        XCTAssertEqual(tunnel.disconnectCount, 1,
                       "applySelection в .connected → disconnect")
        XCTAssertEqual(tunnel.connectCount, 2,
                       "applySelection в .connected → connect (после disconnect)")
        XCTAssertEqual(importer.provisionCalls.last ?? nil, idB,
                       "provisionTunnelProfile получает новый selectedID = idB")
        XCTAssertTrue(vm.state.isConnected, "После reconnect state снова .connected")
    }

    /// T5 — selectedServerID persists в UserDefaults между instance recreations.
    func test_selectedServerID_persists_via_user_defaults() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")

        let probe = MockProbeService([:])
        let tunnel = MockTunnel()
        let importer = MockImporter()
        let defs = freshDefaults()

        // Instance 1 — set selectedServerID = idA.
        let vm1 = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()
        vm1.applySelection(idA)
        await drainMainActor()
        XCTAssertEqual(vm1.selectedServerID, idA)

        // Instance 2 — same UserDefaults → должен восстановить idA.
        let vm2 = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()
        XCTAssertEqual(vm2.selectedServerID, idA,
                       "Новый instance MainScreenViewModel должен восстановить selectedServerID из UserDefaults")
    }

    /// T6 — Pitfall 10: deleted selected server → reconcileSelectionWithStore() сбрасывает в nil.
    func test_deleted_selected_server_falls_back_to_auto() async throws {
        let container = try makeContainer()
        let idA = try seedServer(in: container, name: "A", host: "a.example")
        _ = try seedServer(in: container, name: "B", host: "b.example")

        let probe = MockProbeService([:])
        let tunnel = MockTunnel()
        let importer = MockImporter()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            probeService: probe,
            userDefaults: defs
        )
        await drainMainActor()

        vm.applySelection(idA)
        await drainMainActor()
        XCTAssertEqual(vm.selectedServerID, idA)

        // Внешний путь: удалить idA напрямую через ModelContext (имитация Phase 11 удаления
        // через context menu — обходит ServerListViewModel.deleteServer).
        do {
            let context = ModelContext(container)
            let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == idA })
            if let row = try context.fetch(desc).first {
                context.delete(row)
                try context.save()
            }
        }

        // Reconcile должен detect'нуть отсутствие idA и сбросить в nil.
        await vm.reconcileSelectionWithStore()
        XCTAssertNil(vm.selectedServerID,
                     "reconcileSelectionWithStore: deleted id → selectedServerID = nil (fallback to Auto)")
    }
}
