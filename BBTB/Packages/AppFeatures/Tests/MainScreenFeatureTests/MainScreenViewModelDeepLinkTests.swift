// MainScreenViewModelDeepLinkTests.swift — Phase 9 / Wave 3 / Task 3.3
//
// Integration test покрывает `MainScreenViewModel.handleDeepLink(_:router:)`
// error path: ошибка из DeepLinkRouter → `lastError` populated → `importInProgress`
// cleared via `defer { importInProgress = false }`.
//
// Scaffold mirrors `HandleForegroundReentryTests.swift` (фаза 6e Wave 1) —
// тот же MockImporter / MockTunnel / makeContainer / freshDefaults паттерн.

import XCTest
import Foundation
import SwiftData
import VPNCore
import ConfigParser
import DeepLinks
@testable import MainScreenFeature

@MainActor
final class MainScreenViewModelDeepLinkTests: XCTestCase {

    // MARK: - Test doubles

    /// Fake handler — always throws `unhandled` so VM error path is exercised.
    struct AlwaysThrowsHandler: DeepLinkHandler {
        static let identifier = "always-throws"
        func canHandle(_ url: URL) -> Bool { true }
        func handle(_ url: URL) async throws {
            throw DeepLinkError.unhandled(url: url)
        }
    }

    /// Minimal mock importer — no real I/O. Satisfies ConfigImporting contract.
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
            return ServerConfig(id: id, name: "stub", host: "0.0.0.0", port: 0,
                                protocolID: "vless-reality", keychainTag: keychainTag,
                                isSupported: true, subscriptionID: subscriptionID)
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    /// Minimal mock tunnel — no network calls.
    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        func connect() async throws -> Date { Date() }
        func disconnect() async throws {}
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {}
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ServerConfig.self, Subscription.self, configurations: config)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "test-deep-link-\(UUID().uuidString)"
        let defs = UserDefaults(suiteName: suite)!
        defs.removePersistentDomain(forName: suite)
        return defs
    }

    /// Wait until `condition()` returns true or timeout (default 1 second).
    private func waitFor(
        timeout: TimeInterval = 1.0,
        step: TimeInterval = 0.01,
        _ condition: @MainActor () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
        }
        throw NSError(
            domain: "waitFor",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "condition not met within \(timeout)s"]
        )
    }

    // MARK: - Tests

    /// Test: error path → lastError populated + importInProgress cleared.
    ///
    /// Constructs a DeepLinkRouter with AlwaysThrowsHandler (always throws `.unhandled`),
    /// calls handleDeepLink, awaits until lastError is set (via predicate-based poll),
    /// then asserts lastError != nil AND importInProgress == false (defer restored it).
    func test_handleDeepLink_errorPath_setsLastError() async throws {
        let container = try makeContainer()
        let importer = MockImporter()
        let tunnel = MockTunnel()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            userDefaults: defs
        )

        // Build router with always-throws handler.
        let router = DeepLinkRouter()
        await router.register(AlwaysThrowsHandler())

        let url = URL(string: "bbtb://import?url=https%3A%2F%2Fexample.com%2Fsub")!

        // Trigger deep link handling — fires Task internally.
        vm.handleDeepLink(url, router: router)

        // Wait for the Task to complete (MainActor hop + actor await).
        try await waitFor { vm.lastError != nil }

        XCTAssertNotNil(vm.lastError, "lastError should be populated after deep-link router throws")
        XCTAssertFalse(vm.importInProgress, "defer should have cleared importInProgress to false")
    }

    /// Test: success path — importInProgress is cleared, lastError stays nil.
    ///
    /// Constructs a no-op handler (succeeds silently) and verifies no error is set
    /// and import spinner is cleared after the call.
    func test_handleDeepLink_successPath_clearsImportInProgress() async throws {
        let container = try makeContainer()
        let importer = MockImporter()
        let tunnel = MockTunnel()
        let defs = freshDefaults()

        let vm = MainScreenViewModel(
            importer: importer,
            tunnel: tunnel,
            modelContainer: container,
            userDefaults: defs
        )

        // No-op handler that always succeeds.
        struct NoOpHandler: DeepLinkHandler {
            static let identifier = "noop"
            func canHandle(_ url: URL) -> Bool { true }
            func handle(_ url: URL) async throws {}
        }

        let router = DeepLinkRouter()
        await router.register(NoOpHandler())

        let url = URL(string: "bbtb://import?url=https%3A%2F%2Fexample.com%2Fsub")!
        vm.handleDeepLink(url, router: router)

        // Wait for importInProgress to settle back to false.
        try await waitFor { !vm.importInProgress }

        XCTAssertNil(vm.lastError, "lastError should remain nil on success")
        XCTAssertFalse(vm.importInProgress, "defer should have cleared importInProgress to false")
    }
}
