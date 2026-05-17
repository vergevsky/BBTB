// ServerDetailViewModelTests.swift — Phase 5 Wave 8 / Task 2.
//
// Tests for ServerDetailViewModel:
//   1. init.selectedTransport == .auto when server.transportOverride == nil
//   2. init.selectedTransport == .ws when server.transportOverride == .ws(...)
//   3. applyTransportSelection(.ws) persists .ws(path:"/", host:"") to SwiftData
//   4. applyTransportSelection(.auto) clears override (nil)
//   5. Uses fetch-all + filter (no #Predicate) — white-box via source code conformance

import XCTest
import SwiftData
import VPNCore
import ConfigParser
@testable import ServerListFeature

// MARK: - Mock ConfigImporting

/// Minimal stub for ConfigImporting — enough for ServerDetailViewModel unit tests.
/// Returns canned `AnyParsedConfig` for reparseAnyParsedConfig; all mutation methods are no-ops.
final class MockConfigImporter: ConfigImporting, @unchecked Sendable {
    var cannedReparsed: AnyParsedConfig?

    func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
        ImportResult(supported: [], unsupported: [], failed: [], subscriptionURL: nil, source: source, metadata: nil)
    }
    func importFromPasteboard() async throws -> ImportResult {
        ImportResult(supported: [], unsupported: [], failed: [], subscriptionURL: nil, source: .pasteboard, metadata: nil)
    }
    func importFromQRCode(_ scanned: String) async throws -> ImportResult {
        ImportResult(supported: [], unsupported: [], failed: [], subscriptionURL: nil, source: .qrCode, metadata: nil)
    }
    func loadActiveServer() -> ServerConfig? { nil }
    func countSupportedConfigs() -> Int { 0 }
    func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? { nil }
    func buildServerConfig(from server: ImportedServer, id: UUID, subscriptionID: UUID, keychainTag: String?) -> ServerConfig {
        ServerConfig(id: id, name: "", host: "", port: 0, protocolID: "", keychainTag: nil)
    }
    func provisionTunnelProfile(for selectedID: UUID?) async throws {}
    func runIsSupportedUpgrade() async {}
    @MainActor
    func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? {
        cannedReparsed
    }
}

// MARK: - Tests

@MainActor
final class ServerDetailViewModelTests: XCTestCase {

    // MARK: Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func insertServer(_ server: ServerConfig, in container: ModelContainer) throws {
        let context = ModelContext(container)
        context.insert(server)
        try context.save()
    }

    private func makeServer(transportOverride: TransportConfig? = nil) -> ServerConfig {
        ServerConfig(
            id: UUID(),
            name: "Test Server",
            host: "example.com",
            port: 443,
            protocolID: "vless-tls",
            keychainTag: "bbtb-test-\(UUID().uuidString)",
            isSupported: true,
            transportOverride: transportOverride
        )
    }

    // MARK: Test 1: init selectedTransport == .auto when transportOverride == nil

    func test_init_selectedTransport_fromOverride_auto() throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: nil)
        try insertServer(server, in: container)

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )
        XCTAssertEqual(vm.selectedTransport, .auto,
                       "selectedTransport should be .auto when transportOverride is nil")
    }

    // MARK: Test 2: init selectedTransport == .ws when transportOverride == .ws(...)

    func test_init_selectedTransport_fromOverride_ws() throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: .ws(path: "/x", host: "h"))
        try insertServer(server, in: container)

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )
        XCTAssertEqual(vm.selectedTransport, .ws,
                       "selectedTransport should be .ws when transportOverride == .ws(...)")
    }

    // MARK: Test 3: applyTransportSelection(.ws) persists .ws(path:"/", host:"") to SwiftData

    func test_applyTransportSelection_ws_persists() async throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: nil)
        try insertServer(server, in: container)

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )

        await vm.applyTransportSelection(.ws)
        XCTAssertEqual(vm.selectedTransport, .ws)

        // Verify persisted to SwiftData by re-fetching
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        guard let persisted = all.first(where: { $0.id == server.id }) else {
            XCTFail("Server not found after save")
            return
        }
        XCTAssertEqual(persisted.transportOverride, .ws(path: "/", host: ""),
                       "WS override should be persisted with default path '/' and empty host")
    }

    // MARK: Test 4: applyTransportSelection(.auto) clears override to nil

    func test_applyTransportSelection_auto_clearsOverride() async throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: .ws(path: "/x", host: "h"))
        try insertServer(server, in: container)

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )
        XCTAssertEqual(vm.selectedTransport, .ws)

        await vm.applyTransportSelection(.auto)
        XCTAssertEqual(vm.selectedTransport, .auto)

        // Verify persisted nil
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        guard let persisted = all.first(where: { $0.id == server.id }) else {
            XCTFail("Server not found after save")
            return
        }
        XCTAssertNil(persisted.transportOverride,
                     "transportOverride should be nil after selecting Auto")
    }

    // MARK: Plan 09 T-C-A6H1 — rollback uses lastPersistedTransport (closes C6-4-001 + A6 FAIL)

    /// **Pre-fix bug:** SwiftUI Picker binding writes `selectedTransport` synchronously
    /// BEFORE `.onChange` fires `applyTransportSelection`. The original Plan 07 code
    /// captured `let previous = selectedTransport` at function entry — which was
    /// already the new value — making rollback a no-op.
    ///
    /// **Test simulates the production flow** by:
    /// 1. Init VM with server (transportOverride=nil → selectedTransport=.auto, lastPersisted=.auto)
    /// 2. **Manually mutate `vm.selectedTransport = .ws`** (simulates Picker binding write)
    /// 3. Remove server from container BEFORE applyTransportSelection → triggers the
    ///    server-not-found rollback path (no save attempt needed)
    /// 4. Call `vm.applyTransportSelection(.ws)` → expect rollback to `.auto`
    ///
    /// Pre-fix: rollback set selectedTransport = previous = .ws (already-mutated value) → BUG.
    /// Post-fix: rollback uses lastPersistedTransport = .auto → CORRECT.
    func test_T_C_A6H1_rollback_usesLastPersistedTransport_onServerNotFound() async throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: nil)
        // Note: server NOT inserted in container — simulates "vanished server" scenario.

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )
        XCTAssertEqual(vm.selectedTransport, .auto, "init: selectedTransport=.auto")

        // Simulate SwiftUI Picker binding synchronous write — moves selectedTransport
        // to .ws BEFORE applyTransportSelection runs (pre-fix this corrupted the
        // captured `previous` value).
        vm.selectedTransport = .ws

        await vm.applyTransportSelection(.ws)

        // Plan 09 fix: rollback uses lastPersistedTransport (=.auto), NOT the
        // already-mutated selectedTransport.
        XCTAssertEqual(vm.selectedTransport, .auto,
                       "Rollback must restore last-persisted value (.auto), not the already-mutated .ws")
        XCTAssertNotNil(vm.persistError, "User-visible error surfaced")
    }

    /// **Regression guard:** after successful save, lastPersistedTransport must update
    /// so subsequent rollback (e.g. failed second save) restores the correct value.
    func test_T_C_A6H1_lastPersisted_updatesOnSuccess_chainedFailureRollsBackToLatestSuccess() async throws {
        let container = try makeContainer()
        let server = makeServer(transportOverride: nil)
        try insertServer(server, in: container)

        let vm = ServerDetailViewModel(
            server: server,
            modelContainer: container,
            configImporter: MockConfigImporter()
        )
        XCTAssertEqual(vm.selectedTransport, .auto)

        // First save: succeeds. lastPersistedTransport должно стать .ws.
        await vm.applyTransportSelection(.ws)
        XCTAssertEqual(vm.selectedTransport, .ws, "Success → selectedTransport=.ws")

        // Now simulate Picker binding write to gRPC, BUT delete server first
        // so applyTransportSelection hits server-not-found rollback path.
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        if let cfg = all.first(where: { $0.id == server.id }) {
            context.delete(cfg)
            try context.save()
        }

        vm.selectedTransport = .grpc  // simulate Picker binding write
        await vm.applyTransportSelection(.grpc)

        // Should rollback to LAST persisted = .ws (not original .auto).
        XCTAssertEqual(vm.selectedTransport, .ws,
                       "Chained failure rollback must restore latest persisted (.ws), not initial (.auto)")
    }

    // MARK: Test 5: all transport options roundtrip through TransportSelection

    func test_transportSelection_allCases_roundtrip() {
        let cases: [(TransportConfig, TransportSelection)] = [
            (.tcp, .tcp),
            (.ws(path: "/p", host: "h"), .ws),
            (.grpc(serviceName: "svc"), .grpc),
            (.http(path: "/p"), .http),
            (.httpUpgrade(path: "/p", host: "h"), .httpUpgrade),
        ]
        for (config, expected) in cases {
            XCTAssertEqual(TransportSelection.from(config), expected,
                           "TransportSelection.from(\(config)) should be .\(expected)")
        }
        // .auto → nil
        XCTAssertNil(TransportSelection.auto.toOverride(),
                     ".auto.toOverride() should return nil")
        // non-auto → non-nil
        XCTAssertNotNil(TransportSelection.ws.toOverride())
        XCTAssertNotNil(TransportSelection.grpc.toOverride())
        XCTAssertNotNil(TransportSelection.http.toOverride())
        XCTAssertNotNil(TransportSelection.httpUpgrade.toOverride())
        XCTAssertNotNil(TransportSelection.tcp.toOverride())
    }
}
