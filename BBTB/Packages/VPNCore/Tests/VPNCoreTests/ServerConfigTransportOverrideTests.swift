import XCTest
import SwiftData
@testable import VPNCore

/// Phase 5 Wave 8 / Task 1 — SwiftData lightweight migration smoke tests
/// for `ServerConfig.transportOverride: TransportConfig?` (D-19, TRANSP-05).
///
/// Tests:
///   1. Default nil when not specified in init
///   2. Stores non-nil value when specified
///   3. SwiftData in-memory round-trip with non-nil transportOverride
///   4. SwiftData in-memory round-trip with nil transportOverride
final class ServerConfigTransportOverrideTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func makeServer(transportOverride: TransportConfig? = nil) -> ServerConfig {
        ServerConfig(
            id: UUID(),
            name: "Test Server",
            host: "test.example.com",
            port: 443,
            protocolID: "vless-tls",
            keychainTag: "bbtb-test-\(UUID().uuidString)",
            isSupported: true,
            transportOverride: transportOverride
        )
    }

    // MARK: - Test 1: defaults nil

    func test_serverConfig_init_transportOverride_defaultsNil() {
        let server = makeServer()
        XCTAssertNil(server.transportOverride,
                     "transportOverride should default to nil when not specified")
    }

    // MARK: - Test 2: stores value

    func test_serverConfig_init_transportOverride_storesValue() {
        let expected = TransportConfig.ws(path: "/x", host: "h")
        let server = makeServer(transportOverride: expected)
        XCTAssertEqual(server.transportOverride, expected,
                       "transportOverride should store the specified value")
    }

    // MARK: - Test 3: SwiftData round-trip with non-nil value

    @MainActor
    func test_serverConfig_swiftData_roundtrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let expected = TransportConfig.ws(path: "/x", host: "h")
        let server = makeServer(transportOverride: expected)
        let insertedID = server.id
        context.insert(server)
        try context.save()

        // Fetch from same context (in-memory)
        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        guard let retrieved = all.first(where: { $0.id == insertedID }) else {
            XCTFail("Server not found after save")
            return
        }
        XCTAssertEqual(retrieved.transportOverride, expected,
                       "transportOverride .ws should survive SwiftData round-trip")
    }

    // MARK: - Test 4: SwiftData round-trip with nil (existing-data simulation)

    @MainActor
    func test_serverConfig_swiftData_nilOverride_roundtrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let server = makeServer(transportOverride: nil)
        let insertedID = server.id
        context.insert(server)
        try context.save()

        let all = try context.fetch(FetchDescriptor<ServerConfig>())
        guard let retrieved = all.first(where: { $0.id == insertedID }) else {
            XCTFail("Server not found after save")
            return
        }
        XCTAssertNil(retrieved.transportOverride,
                     "nil transportOverride should survive SwiftData round-trip (pre-Phase-5 migration simulation)")
    }
}
