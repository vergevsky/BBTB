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
