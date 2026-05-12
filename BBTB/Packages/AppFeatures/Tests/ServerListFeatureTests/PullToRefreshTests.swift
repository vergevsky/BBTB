import XCTest
import Foundation
import SwiftData
@testable import ConfigParser
@testable import VPNCore
@testable import ServerListFeature

/// Phase 3 / Plan 04 / Task 1 RED — `ServerListViewModel.pullToRefresh` /
/// `silentForegroundRefresh` поведение по D-12, D-13:
///
/// - 2-phase sequential: ВСЕ fetch завершаются ДО первого probe (D-13).
/// - partial failure — один fetch throws, остальные работают; `subscriptionFetchErrors[sub.id]` set.
/// - all fetch fail → `refreshError != nil`, state == `.refreshError(...)`.
/// - state transitions `.loaded → .refreshing → .loaded`.
/// - silentForegroundRefresh state не меняет.
///
/// Файл должен FAIL до Task 2 (требует `pullToRefresh`/`silentForegroundRefresh`/
/// `subscriptionFetchErrors`/`importer` параметра init + fetcher/parser injection).
@MainActor
final class PullToRefreshTests: XCTestCase {

    // MARK: Test doubles

    /// Mock probe service — записывает probe-events в shared timeline.
    /// Conforms к `ServerProbing` protocol (Plan 04 adds — actor sub-classing невозможно).
    private final class MockProbe: ServerProbing, @unchecked Sendable {
        let timeline: TimelineRecorder
        init(timeline: TimelineRecorder) { self.timeline = timeline }

        nonisolated func probeAll(_ servers: [(id: UUID, host: String, port: Int)])
            -> AsyncStream<(UUID, ProbeAggregate)>
        {
            let tl = self.timeline
            return AsyncStream { cont in
                Task {
                    for s in servers {
                        await tl.record(.probe(id: s.id))
                        let agg = ProbeAggregate(avgLatencyMs: 100, failures: 0, lossRate: 0.0, probedAt: .now)
                        cont.yield((s.id, agg))
                    }
                    cont.finish()
                }
            }
        }
    }

    /// Mock fetcher — захватывает вызов и пишет в timeline.
    private final class MockFetcher: SubscriptionURLFetching, @unchecked Sendable {
        let timeline: TimelineRecorder
        var failingURLs: Set<String>  // URL.absoluteString
        var bodyForURL: [String: String]

        init(timeline: TimelineRecorder,
             failingURLs: Set<String> = [],
             bodyForURL: [String: String] = [:]) {
            self.timeline = timeline
            self.failingURLs = failingURLs
            self.bodyForURL = bodyForURL
        }

        func fetch(url: URL) async throws -> SubscriptionFetchResult {
            await timeline.record(.fetch(url: url.absoluteString))
            if failingURLs.contains(url.absoluteString) {
                throw URLError(.notConnectedToInternet)
            }
            let body = bodyForURL[url.absoluteString] ?? ""
            return SubscriptionFetchResult(
                body: Data(body.utf8),
                metadata: SubscriptionMetadata(title: nil, updateInterval: nil, userInfo: nil),
                finalURL: url
            )
        }
    }

    /// Mock parser — отдаёт пустой ImportResult (без серверов).
    private final class MockParser: UniversalImportParsing, @unchecked Sendable {
        func `import`(rawInput: String, source: ImportSource) async throws -> ImportResult {
            return ImportResult(
                supported: [], unsupported: [], failed: [],
                subscriptionURL: nil, source: source, metadata: nil
            )
        }
    }

    /// Mock ConfigImporting — stubs всех методов протокола Plan 04.
    private final class MockImporter: ConfigImporting, @unchecked Sendable {
        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: source, metadata: nil)
        }
        func importFromPasteboard() async throws -> ImportResult {
            return try await importFromRawInput("", source: .pasteboard)
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            return try await importFromRawInput(scanned, source: .qrCode)
        }
        func loadActiveServer() -> ServerConfig? { return nil }
        func countSupportedConfigs() -> Int { return 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
            switch server {
            case .supported:
                let id = UUID()
                return KeychainPersistResult(id: id, tag: "bbtb-config-\(id.uuidString)")
            case .unsupported, .invalid:
                return nil
            }
        }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig
        {
            return ServerConfig(
                id: id, name: server.displayName, host: "stub.example.com", port: 443,
                protocolID: "vless-reality", keychainTag: keychainTag,
                isSupported: server.isSupportedFlag, subscriptionID: subscriptionID
            )
        }
        // Plan 05 — no-op stub (PullToRefreshTests не covering provision-связанные пути).
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
    }

    /// Timeline recorder — append-only thread-safe log событий.
    private actor TimelineRecorder {
        enum Event {
            case fetch(url: String)
            case probe(id: UUID)
        }
        private(set) var events: [Event] = []
        func record(_ e: Event) { events.append(e) }
        func snapshot() -> [Event] { events }
    }

    /// Mock coordinator (минимальный).
    private final class MockCoordinator: ServerSelectionCoordinating {
        var selectedServerID: UUID? = nil
        var appliedCalls: [UUID?] = []
        var dismissCalls = 0
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

    private func seed(container: ModelContainer,
                     subscriptions: [Subscription],
                     servers: [ServerConfig]) throws
    {
        let context = ModelContext(container)
        for s in subscriptions { context.insert(s) }
        for srv in servers { context.insert(srv) }
        try context.save()
    }

    // MARK: Tests

    func test_pull_to_refresh_two_phase_order() async throws {
        let container = try makeContainer()
        let subA = Subscription(url: "https://sub.example/a", name: "A", lastFetched: nil)
        let subB = Subscription(url: "https://sub.example/b", name: "B", lastFetched: nil)
        let srvA = ServerConfig(
            id: UUID(), name: "A1", host: "a1.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: subA.id
        )
        let srvB = ServerConfig(
            id: UUID(), name: "B1", host: "b1.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: subB.id
        )
        try seed(container: container, subscriptions: [subA, subB], servers: [srvA, srvB])

        let timeline = TimelineRecorder()
        let probe = MockProbe(timeline: timeline)
        let fetcher = MockFetcher(timeline: timeline)
        let parser = MockParser()
        let importer = MockImporter()

        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: probe,
            importer: importer,
            fetcher: fetcher,
            parser: parser
        )

        await vm.pullToRefresh()

        let events = await timeline.snapshot()
        // Find index of первого probe-event и последнего fetch-event.
        var firstProbeIdx: Int? = nil
        var lastFetchIdx: Int? = nil
        for (i, e) in events.enumerated() {
            switch e {
            case .fetch: lastFetchIdx = i
            case .probe: if firstProbeIdx == nil { firstProbeIdx = i }
            }
        }
        let lf = try XCTUnwrap(lastFetchIdx, "Хотя бы один fetch должен быть записан")
        let fp = try XCTUnwrap(firstProbeIdx, "Хотя бы один probe должен быть записан")
        XCTAssertLessThan(lf, fp, "Все fetch события должны произойти ДО первого probe (D-13)")
    }

    func test_pull_to_refresh_partial_fetch_failure() async throws {
        let container = try makeContainer()
        let subA = Subscription(url: "https://sub.example/a-fail", name: "A", lastFetched: nil)
        let subB = Subscription(url: "https://sub.example/b-ok", name: "B", lastFetched: nil)
        let srvB = ServerConfig(
            id: UUID(), name: "B1", host: "b1.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: subB.id
        )
        try seed(container: container, subscriptions: [subA, subB], servers: [srvB])

        let timeline = TimelineRecorder()
        let probe = MockProbe(timeline: timeline)
        let fetcher = MockFetcher(
            timeline: timeline,
            failingURLs: ["https://sub.example/a-fail"]
        )
        let parser = MockParser()
        let importer = MockImporter()

        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: probe,
            importer: importer,
            fetcher: fetcher,
            parser: parser
        )

        await vm.pullToRefresh()

        XCTAssertNotNil(vm.subscriptionFetchErrors[subA.id], "А — должна быть error")
        XCTAssertNil(vm.subscriptionFetchErrors[subB.id], "B — успешно")
        // refreshError == nil (хотя бы один subscription успешный).
        XCTAssertNil(vm.refreshError, "Если есть хоть один OK, общий refreshError = nil")
    }

    func test_pull_to_refresh_all_fetch_fail() async throws {
        let container = try makeContainer()
        let subA = Subscription(url: "https://sub.example/a-fail", name: "A", lastFetched: nil)
        let subB = Subscription(url: "https://sub.example/b-fail", name: "B", lastFetched: nil)
        try seed(container: container, subscriptions: [subA, subB], servers: [])

        let timeline = TimelineRecorder()
        let probe = MockProbe(timeline: timeline)
        let fetcher = MockFetcher(
            timeline: timeline,
            failingURLs: ["https://sub.example/a-fail", "https://sub.example/b-fail"]
        )
        let parser = MockParser()
        let importer = MockImporter()

        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: probe,
            importer: importer,
            fetcher: fetcher,
            parser: parser
        )

        await vm.pullToRefresh()

        XCTAssertNotNil(vm.refreshError, "Все fetch failed → refreshError set")
        if case .refreshError = vm.state {
            // ok
        } else {
            XCTFail("Expected state == .refreshError, got \(vm.state)")
        }
    }

    func test_pull_to_refresh_state_transitions() async throws {
        let container = try makeContainer()
        let sub = Subscription(url: "https://sub.example/x", name: "X", lastFetched: nil)
        let srv = ServerConfig(
            id: UUID(), name: "S1", host: "s.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: sub.id
        )
        try seed(container: container, subscriptions: [sub], servers: [srv])

        let timeline = TimelineRecorder()
        let probe = MockProbe(timeline: timeline)
        let fetcher = MockFetcher(timeline: timeline)
        let parser = MockParser()
        let importer = MockImporter()

        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: probe,
            importer: importer,
            fetcher: fetcher,
            parser: parser
        )

        await vm.pullToRefresh()
        XCTAssertEqual(vm.state, .loaded, "После pullToRefresh state должен быть .loaded")
    }

    func test_silent_foreground_refresh_does_not_set_refreshing_state() async throws {
        let container = try makeContainer()
        let sub = Subscription(url: "https://sub.example/x", name: "X", lastFetched: nil)
        let srv = ServerConfig(
            id: UUID(), name: "S1", host: "s.example.com", port: 443,
            protocolID: "vless-reality", keychainTag: nil, isSupported: true,
            subscriptionID: sub.id
        )
        try seed(container: container, subscriptions: [sub], servers: [srv])

        let timeline = TimelineRecorder()
        let probe = MockProbe(timeline: timeline)
        let fetcher = MockFetcher(timeline: timeline)
        let parser = MockParser()
        let importer = MockImporter()

        let vm = ServerListViewModel(
            modelContainer: container,
            probeService: probe,
            importer: importer,
            fetcher: fetcher,
            parser: parser
        )

        // simulate Plan 03 onAppear-after-load — state == .loaded.
        // Manually wire вместо вызова onAppear (там тоже свой ping flow).
        // Так как pullToRefresh переводит в .loaded, тут просто проверяем что
        // silentForegroundRefresh после .loaded оставляет .loaded.
        await vm.pullToRefresh()
        XCTAssertEqual(vm.state, .loaded)

        await vm.silentForegroundRefresh()
        XCTAssertEqual(vm.state, .loaded,
                       "silentForegroundRefresh НЕ должен переключать state на .refreshing")
    }
}
