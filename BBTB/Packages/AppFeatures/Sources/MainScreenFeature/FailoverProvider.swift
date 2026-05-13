// FailoverProvider.swift — Phase 6 / Plan 06-06 / Wave 6 / Task 1.
//
// SwiftData-backed `FailoverProviding` impl. Replaces the Wave 5
// `NoFailoverProvider` stub: maintains a round-robin cursor across all
// `ServerConfig` rows where `isSupported == true`, sorted by `id.uuidString`
// (project-wide deterministic ordering — same convention used by Phase 3
// ConfigImporter and ServerListSheet).
//
// Cycle semantics (D-08, see `.planning/phases/06-network-resilience/06-CONTEXT.md`):
//   - First call to `nextServerAttempt()` snapshots the supported-server list
//     and seeds the cursor at the index of the currently-selected server
//     (passed via `currentServerID` closure). The cursor then advances by one
//     and returns the **next** server (round-robin).
//   - Each subsequent call advances by one more. When the cursor wraps back
//     to the original starting index, the cycle is exhausted → returns nil
//     (the upstream `ReconnectStateMachine.allFailed` state then triggers
//     the "all servers unreachable" notification wired in Wave 5).
//   - Single-server pool (`cycleSnapshot.count <= 1`) → returns nil
//     immediately AND fires `UserNotificationsHelper.notifySingleServerUnavailable()`.
//   - Empty pool → returns nil silently.
//
// Reset triggers (Pitfall 4 / D-08):
//   - Manual disconnect: `TunnelController.disconnect()` calls `resetCycle()`.
//   - 30s+ stable `.connected` session: `TunnelController.handleStatusChange(.connected)`
//     schedules a `Task { try? clock.sleep(30); resetCycle() }` guarded by the
//     `startedAt` timestamp — see TunnelController for the race-free pattern.
//   - Empty `cycleSnapshot` ≠ "first call" — `resetCycle()` empties the snapshot,
//     so the NEXT `nextServerAttempt()` re-snapshots from SwiftData. This means
//     a freshly imported server picks up on the next cycle (T-06-W6-03: accepted).
//
// SwiftData fetch pattern: **fetch-all + Swift filter**, NOT `#Predicate`.
// `ServerConfig.id` is non-optional `UUID`, but the project-wide ban on
// `#Predicate` with `UUID` lookups (PROJECT.md D-12 / `feedback_swiftdata_uuid_predicate.md`)
// is observed defensively here — on real devices `#Predicate` with `UUID`
// predicates has silently returned empty results in past phases, and the
// failover hot path must NOT be subject to that bug.
//
// Concurrency: `actor SwiftDataFailoverProvider` — `cursor` + `cycleSnapshot`
// are actor-isolated. The `connect` and `provisioner` closures/refs are
// captured at construction time (caller passes `[weak tunnelController]`
// to break the cycle — see `MainScreenViewModel` wiring).

import Foundation
import SwiftData
import VPNCore
import OSLog

/// Snapshot of a `ServerConfig` row used inside the cycle. We do NOT carry
/// the live `@Model` instance across actor boundaries — `ServerConfig` is a
/// `@Model` class and not `Sendable`. Instead we snapshot only the `id` +
/// `name` at fetch time (Pitfall: SwiftData @Model classes aren't Sendable
/// per `ServerProbeService.swift` precedent).
private struct ServerSnapshot: Sendable, Equatable {
    let id: UUID
    let name: String
}

public actor SwiftDataFailoverProvider: FailoverProviding {

    // MARK: Dependencies

    private let modelContainer: ModelContainer
    private let provisioner: any ConfigProvisioning
    private let connect: @Sendable () async throws -> Date
    private let currentServerID: @Sendable () -> UUID?
    /// Injected single-server-unavailable notifier. Production wires the real
    /// `UserNotificationsHelper.notifySingleServerUnavailable`. Tests inject
    /// a no-op (UNUserNotificationCenter is not available in SPM xctest
    /// process — `bundleProxyForCurrentProcess is nil` crash).
    private let notifySingleServerUnavailable: @Sendable () async -> Void
    private let log = Logger(subsystem: "app.bbtb.client", category: "failover")

    // MARK: State

    /// Cursor index into `cycleSnapshot`. Updated on each `nextServerAttempt()`.
    private var cursor: Int = 0

    /// Snapshot taken at the start of a cycle. Empty `[]` means "no cycle in
    /// progress" — the next `nextServerAttempt()` will re-snapshot from SwiftData.
    private var cycleSnapshot: [ServerSnapshot] = []

    /// Index of the originally-selected server inside `cycleSnapshot` at the
    /// time the cycle started. Used to detect "full circle" — when `cursor`
    /// wraps back to `startIndex` we've exhausted all alternative servers.
    private var startIndex: Int = 0

    // MARK: Init

    /// - Parameters:
    ///   - modelContainer: SwiftData container holding `ServerConfig` rows.
    ///   - provisioner: indirection to `ConfigImporter.provisionTunnelProfile(for:)`.
    ///   - connect: closure that drives `TunnelController.connect()` (returns the
    ///     timestamp of successful `.connected` transition). Caller is expected
    ///     to pass `[weak tunnelController]` to break the VM↔TunnelController cycle.
    ///   - currentServerID: closure read on each cycle start — returns the
    ///     UUID of the user-selected server (from `@AppStorage selectedServerID`),
    ///     or nil in Auto mode.
    public init(
        modelContainer: ModelContainer,
        provisioner: any ConfigProvisioning,
        connect: @escaping @Sendable () async throws -> Date,
        currentServerID: @escaping @Sendable () -> UUID?,
        notifySingleServerUnavailable: @escaping @Sendable () async -> Void = {
            await UserNotificationsHelper.notifySingleServerUnavailable()
        }
    ) {
        self.modelContainer = modelContainer
        self.provisioner = provisioner
        self.connect = connect
        self.currentServerID = currentServerID
        self.notifySingleServerUnavailable = notifySingleServerUnavailable
    }

    // MARK: FailoverProviding

    public func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
        // Fresh cycle → snapshot supported servers + seed cursor at current ID.
        if cycleSnapshot.isEmpty {
            let snapshots = await fetchSupportedSnapshots()
            if snapshots.isEmpty {
                log.notice("failover: empty pool — returning nil")
                return nil
            }
            if snapshots.count == 1 {
                log.notice("failover: single-server pool — firing notifySingleServerUnavailable")
                // Edge case D-08: notify user and return nil.
                await notifySingleServerUnavailable()
                return nil
            }
            cycleSnapshot = snapshots
            // Seed cursor at the currently-selected server's position, or 0 if
            // current is unknown/missing. This is the "origin" — the cycle is
            // exhausted when we wrap back here.
            let currentID = currentServerID()
            startIndex = snapshots.firstIndex(where: { $0.id == currentID }) ?? 0
            cursor = startIndex
            log.notice("failover: new cycle seeded — pool=\(snapshots.count, privacy: .public) startIndex=\(self.startIndex, privacy: .public)")
        }

        // Defensive — should never hit (we returned nil above for <2).
        guard cycleSnapshot.count >= 2 else {
            log.notice("failover: cycleSnapshot shrunk below 2 between calls — exhausted")
            return nil
        }

        // Advance cursor by one (wrapping). If we wrap back to startIndex → exhausted.
        cursor = (cursor + 1) % cycleSnapshot.count
        if cursor == startIndex {
            log.notice("failover: full circle completed — returning nil (state machine maps to .allFailed)")
            return nil
        }

        let next = cycleSnapshot[cursor]
        let nextID = next.id
        let nextName = next.name
        let provisioner = self.provisioner
        let connect = self.connect
        let logger = self.log

        let attempt: @Sendable () async throws -> Date = {
            logger.notice("failover: attempting \(nextName, privacy: .public) (\(nextID, privacy: .public))")
            try await provisioner.provisionTunnelProfile(for: nextID)
            return try await connect()
        }
        return (serverName: nextName, attempt: attempt)
    }

    public func resetCycle() async {
        if !cycleSnapshot.isEmpty || cursor != 0 || startIndex != 0 {
            log.notice("failover: cycle reset")
        }
        cycleSnapshot = []
        cursor = 0
        startIndex = 0
    }

    // MARK: - Test seams

    internal func currentCursorForTest() -> Int { cursor }
    internal func currentStartIndexForTest() -> Int { startIndex }
    internal func currentSnapshotCountForTest() -> Int { cycleSnapshot.count }

    // MARK: - Private helpers

    /// Fetch all supported `ServerConfig` rows and project to sendable snapshots,
    /// sorted by `id.uuidString` ascending (project-wide convention).
    ///
    /// Implementation note: uses **fetch-all + Swift filter** (not `#Predicate`).
    /// See `PROJECT.md` D-12 / `feedback_swiftdata_uuid_predicate.md` — `#Predicate`
    /// with UUID lookups silently returns empty results on real devices in past
    /// phases (Phase 3 bug). Failover hot path must not be subject to that bug.
    private func fetchSupportedSnapshots() async -> [ServerSnapshot] {
        // ModelContext mutation is bound to the context's actor — for in-memory
        // tests this is the MainActor; for production it's whatever invoked us.
        // We perform the fetch on MainActor to align with SwiftData expectations.
        let container = self.modelContainer
        return await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ServerConfig>()
            guard let all = try? context.fetch(descriptor) else {
                return [] as [ServerSnapshot]
            }
            return all
                .filter { $0.isSupported }
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map { ServerSnapshot(id: $0.id, name: $0.name) }
        }
    }
}

// MARK: - ConfigProvisioning

/// Minimal protocol for the failover-relevant slice of `ConfigImporting`.
/// `ConfigImporter` already conforms (it has `provisionTunnelProfile(for:)`),
/// and tests inject lightweight mocks without dragging in the full importer
/// surface area (Keychain, parsers, etc.).
public protocol ConfigProvisioning: Sendable {
    func provisionTunnelProfile(for selectedID: UUID?) async throws
}

extension ConfigImporter: ConfigProvisioning {}
