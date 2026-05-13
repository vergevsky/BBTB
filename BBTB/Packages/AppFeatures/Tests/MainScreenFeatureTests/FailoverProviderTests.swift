// FailoverProviderTests.swift — Phase 6 / Plan 06-06 / Wave 6 / Task 1.
//
// Tests for `SwiftDataFailoverProvider`:
//   - Round-robin advance over supported `ServerConfig` rows.
//   - Cursor seeded at the currently-selected server (skipped by .next() advance).
//   - `isSupported == false` rows excluded.
//   - Deterministic ordering by `id.uuidString` ascending.
//   - Single-server edge → nil immediately.
//   - Empty pool → nil silently.
//   - Full cycle exhaustion → nil.
//   - `resetCycle()` empties the snapshot so the next call re-snapshots.
//   - The returned `attempt` closure invokes `provisionTunnelProfile(for:nextID)`.

import XCTest
import Foundation
import SwiftData
import VPNCore
@testable import MainScreenFeature

@MainActor
final class FailoverProviderTests: XCTestCase {

    // MARK: - Test doubles

    /// Records the UUIDs passed to `provisionTunnelProfile(for:)`.
    /// Backed by an actor for async-safe mutation.
    actor CallRecorder {
        var calls: [UUID?] = []
        func append(_ id: UUID?) { calls.append(id) }
        func snapshot() -> [UUID?] { calls }
    }

    final class RecordingProvisioner: ConfigProvisioning, @unchecked Sendable {
        let recorder = CallRecorder()
        func provisionTunnelProfile(for selectedID: UUID?) async throws {
            await recorder.append(selectedID)
        }
        func snapshot() async -> [UUID?] {
            await recorder.snapshot()
        }
    }

    // MARK: - Helpers

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Seed `n` supported servers (with deterministic UUIDs so we can assert
    /// ordering by `id.uuidString`). Returns sorted UUIDs in the expected order.
    @discardableResult
    private func seedSupported(container: ModelContainer, count n: Int, prefix: String = "Server") -> [UUID] {
        let context = ModelContext(container)
        var ids: [UUID] = []
        // UUIDs intentionally generated outside any deterministic prefix; we
        // assert by sorted-uuidString consistency, not by name order.
        for i in 0..<n {
            let cfg = ServerConfig(
                id: UUID(),
                name: "\(prefix)-\(i)",
                host: "h\(i).example.com",
                port: 443,
                protocolID: "vless-reality",
                keychainTag: nil,
                isSupported: true,
                rawURI: nil
            )
            context.insert(cfg)
            ids.append(cfg.id)
        }
        try? context.save()
        return ids.sorted { $0.uuidString < $1.uuidString }
    }

    private func seedUnsupported(container: ModelContainer, count: Int) {
        let context = ModelContext(container)
        for i in 0..<count {
            let cfg = ServerConfig(
                id: UUID(),
                name: "Unsupported-\(i)",
                host: "u\(i).example.com",
                port: 443,
                protocolID: "vmess",
                keychainTag: nil,
                isSupported: false,
                rawURI: nil
            )
            context.insert(cfg)
        }
        try? context.save()
    }

    /// Counter for the single-server-unavailable notifier (replaces the real
    /// `UserNotificationsHelper.notifySingleServerUnavailable` which crashes
    /// in SPM xctest process — UNUserNotificationCenter requires a main bundle).
    actor NotifyCounter {
        var count = 0
        func tick() { count += 1 }
        func snapshot() -> Int { count }
    }

    private func makeProvider(
        container: ModelContainer,
        provisioner: ConfigProvisioning = RecordingProvisioner(),
        currentServerID: UUID? = nil,
        connectClosure: (@Sendable () async throws -> Date)? = nil,
        notifyCounter: NotifyCounter = NotifyCounter()
    ) -> SwiftDataFailoverProvider {
        let connect: @Sendable () async throws -> Date = connectClosure ?? { Date() }
        let idBox = currentServerID
        let counter = notifyCounter
        return SwiftDataFailoverProvider(
            modelContainer: container,
            provisioner: provisioner,
            connect: connect,
            currentServerID: { idBox },
            notifySingleServerUnavailable: { await counter.tick() }
        )
    }

    // MARK: - Tests

    /// Test 1: single supported server → returns nil immediately AND fires
    /// the single-server-unavailable notification (D-08 edge).
    func test_nextServer_single_server_returns_nil() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 1)
        let counter = NotifyCounter()
        let provider = makeProvider(container: container, currentServerID: ids[0], notifyCounter: counter)

        let result = await provider.nextServerAttempt()
        XCTAssertNil(result, "Single-server pool must return nil (D-08 edge)")
        let fired = await counter.snapshot()
        XCTAssertEqual(fired, 1, "notifySingleServerUnavailable must fire once")
    }

    /// Test 2: empty pool → returns nil silently.
    func test_nextServer_zero_servers_returns_nil() async throws {
        let container = try makeContainer()
        let provider = makeProvider(container: container)

        let result = await provider.nextServerAttempt()
        XCTAssertNil(result, "Empty pool must return nil")
    }

    /// Test 3: with current at index 0 of two servers → returns index 1.
    func test_nextServer_returns_next_when_two_servers() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 2)
        let provider = makeProvider(container: container, currentServerID: ids[0])

        let result = await provider.nextServerAttempt()
        XCTAssertNotNil(result)
        // Second call → wrap back to startIndex (0) → nil (cycle exhausted).
        let second = await provider.nextServerAttempt()
        XCTAssertNil(second, "Wrap-back to startIndex must collapse to nil")
    }

    /// Test 4: round-robin over 4 servers — first 3 calls return servers 2/3/4,
    /// fourth call wraps and returns nil.
    func test_nextServer_advances_round_robin_4_servers() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 4)
        // currentServerID = ids[0] (sorted by uuidString → startIndex == 0).
        let provider = makeProvider(container: container, currentServerID: ids[0])

        let r1 = await provider.nextServerAttempt()
        let r2 = await provider.nextServerAttempt()
        let r3 = await provider.nextServerAttempt()
        let r4 = await provider.nextServerAttempt()

        XCTAssertNotNil(r1, "1st call must return next server")
        XCTAssertNotNil(r2, "2nd call must return next-next server")
        XCTAssertNotNil(r3, "3rd call must return last server in pool")
        XCTAssertNil(r4, "4th call wraps back to start → nil")

        // Returned names must match positions 1/2/3 in sorted order.
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        let sorted = all.sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(r1?.serverName, sorted[1].name)
        XCTAssertEqual(r2?.serverName, sorted[2].name)
        XCTAssertEqual(r3?.serverName, sorted[3].name)
    }

    /// Test 5: cursor wraps past start when current is in the middle.
    func test_nextServer_wraps_when_current_is_middle() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 4)
        // Start in the middle (index 2 of sorted ids).
        let provider = makeProvider(container: container, currentServerID: ids[2])

        let r1 = await provider.nextServerAttempt()  // index 3
        let r2 = await provider.nextServerAttempt()  // index 0 (wraps)
        let r3 = await provider.nextServerAttempt()  // index 1
        let r4 = await provider.nextServerAttempt()  // index 2 → wraps to start → nil

        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertNotNil(r3)
        XCTAssertNil(r4)
    }

    /// Test 6: `isSupported == false` rows excluded from cycle.
    func test_nextServer_skips_unsupported() async throws {
        let container = try makeContainer()
        let supportedIDs = seedSupported(container: container, count: 2)
        seedUnsupported(container: container, count: 3)  // 3 unsupported, should be ignored.

        let provider = makeProvider(container: container, currentServerID: supportedIDs[0])
        let r1 = await provider.nextServerAttempt()
        XCTAssertNotNil(r1, "First failover step must succeed")
        let r2 = await provider.nextServerAttempt()
        XCTAssertNil(r2, "Only 2 supported → after first failover, cycle exhausted")
    }

    /// Test 7: deterministic ordering by `id.uuidString` ascending.
    func test_nextServer_deterministic_order() async throws {
        let container = try makeContainer()
        // Insert in random order; provider must still return sorted order.
        let ids = seedSupported(container: container, count: 5)
        // Start at the smallest UUID → next 4 calls return ids[1..4] in order.
        let provider = makeProvider(container: container, currentServerID: ids[0])

        var seenNames: [String] = []
        for _ in 0..<4 {
            if let r = await provider.nextServerAttempt() {
                seenNames.append(r.serverName)
            }
        }
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        let expected = all
            .filter { $0.isSupported }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .dropFirst()  // skip the start element
            .map { $0.name }
        XCTAssertEqual(seenNames, Array(expected))
    }

    /// Test 8: `resetCycle()` empties snapshot → next call re-snapshots fresh.
    func test_resetCycle_starts_fresh_snapshot() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 3)
        let provider = makeProvider(container: container, currentServerID: ids[0])

        _ = await provider.nextServerAttempt()  // advance to index 1
        _ = await provider.nextServerAttempt()  // advance to index 2
        let cursorMid = await provider.currentCursorForTest()
        XCTAssertEqual(cursorMid, 2, "Cursor should have advanced to 2")

        await provider.resetCycle()
        let cursorAfter = await provider.currentCursorForTest()
        let snapshotCountAfter = await provider.currentSnapshotCountForTest()
        XCTAssertEqual(cursorAfter, 0)
        XCTAssertEqual(snapshotCountAfter, 0, "Snapshot should be empty after reset")

        // Next call must re-snapshot (cursor seeded to 0, returns index 1).
        let r = await provider.nextServerAttempt()
        XCTAssertNotNil(r)
        let cursorReseed = await provider.currentCursorForTest()
        XCTAssertEqual(cursorReseed, 1, "Cursor should advance to 1 after re-snapshot")
    }

    /// Test 9: the returned `attempt` closure provisions the next server's UUID.
    func test_nextServer_attempt_closure_provisions_next_uuid() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 3)
        let recorder = RecordingProvisioner()
        let provider = makeProvider(container: container, provisioner: recorder, currentServerID: ids[0])

        let result = await provider.nextServerAttempt()
        XCTAssertNotNil(result)

        _ = try await result?.attempt()

        let calls = await recorder.snapshot()
        XCTAssertEqual(calls.count, 1, "attempt closure must call provisionTunnelProfile exactly once")
        // The provisioned UUID must equal the second sorted ID (the next one
        // after the seeded current at ids[0]).
        XCTAssertEqual(calls[0], ids[1], "Provisioned UUID must equal the next sorted ID")
    }

    /// Test 10: when current ID is nil (Auto mode), cycle starts at 0 — first
    /// call returns index 1 of the sorted pool.
    func test_nextServer_with_nil_current_starts_at_zero() async throws {
        let container = try makeContainer()
        let ids = seedSupported(container: container, count: 3)
        let provider = makeProvider(container: container, currentServerID: nil)

        let r1 = await provider.nextServerAttempt()
        XCTAssertNotNil(r1)
        // Sorted order: ids[0..2]. startIndex==0 (nil current → fallback). r1 = ids[1].
        let context = ModelContext(container)
        let all = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        let sorted = all.sorted { $0.id.uuidString < $1.id.uuidString }
        XCTAssertEqual(r1?.serverName, sorted[1].name)
        _ = ids  // silence unused warning
    }

    /// Test 11: fetch uses fetch-all + Swift filter (D-12 / Pitfall 4).
    /// We verify behavior: provider must return supported servers correctly even
    /// when there are unsupported rows mixed in, demonstrating the filter
    /// happens in Swift (a `#Predicate { isSupported }` would also work here,
    /// but the contract is that the implementation must not rely on `#Predicate`
    /// with UUID lookups anywhere in the failover hot path).
    func test_nextServer_uses_fetchAll_filter_not_predicate() async throws {
        let container = try makeContainer()
        let supportedIDs = seedSupported(container: container, count: 3)
        seedUnsupported(container: container, count: 5)

        let provider = makeProvider(container: container, currentServerID: supportedIDs[0])
        let r1 = await provider.nextServerAttempt()
        let r2 = await provider.nextServerAttempt()
        let r3 = await provider.nextServerAttempt()
        XCTAssertNotNil(r1)
        XCTAssertNotNil(r2)
        XCTAssertNil(r3, "Only 3 supported → after 2 failover steps, exhausted")
    }
}
