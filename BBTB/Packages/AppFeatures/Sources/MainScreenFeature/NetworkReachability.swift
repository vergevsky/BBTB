// NetworkReachability.swift — Phase 6 / Plan 06-04 / Wave 4 / Task 1.
//
// Actor wrapper around `NWPathMonitor` for the main app. Reports physical-interface
// transitions (Wi-Fi / Cellular / WiredEthernet) to the `ReconnectStateMachine` so it
// can trigger D-07 auto-reconnect on network handoffs (NET-08..NET-10).
//
// Trust boundary mitigations (see plan 06-04 §threat_model T-06-W4-01):
// - 500ms throttle on path callbacks — iOS fires `pathUpdateHandler` 4-10× per
//   real Wi-Fi↔LTE handoff. Throttling prevents reconnect storms.
// - Physical-interface filter mirrors `ExtensionPlatformInterface.isPhysical`
//   (`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift:303-310`).
//   Filtering out `.other` (utun) avoids reacting to our own tunnel coming up
//   (`.planning/phases/06-network-resilience/06-RESEARCH.md` §14 Pitfall 2).
// - Dedup via `lastPhysicalType` — same physical type in a row emits nothing.
//
// Testability: production callers use `start(_:)` to wire the real `NWPathMonitor`.
// Tests bypass the live monitor and drive `processPath(_:now:)` directly with
// synthesized `NWPathSnapshot` values. Both paths share the same throttle/dedup
// core, so tests cover behavior the live monitor would exercise.

import Foundation
import Network
import OSLog

/// Sendable snapshot of an `NWPath` reduced to the fields the actor needs.
/// Extracted in `start(_:)` from the live monitor; constructed directly in tests.
public struct NWPathSnapshot: Sendable, Equatable {
    public let status: NWPath.Status
    /// `nil` when no physical interface is available (loopback-only / utun-only /
    /// truly offline). Set to the first `.wifi` / `.cellular` / `.wiredEthernet`
    /// found in `availableInterfaces`.
    public let physicalType: NWInterface.InterfaceType?

    public init(status: NWPath.Status, physicalType: NWInterface.InterfaceType?) {
        self.status = status
        self.physicalType = physicalType
    }
}

/// Events emitted by `NetworkReachability` to its listener.
public enum NetworkReachabilityEvent: Equatable, Sendable {
    case satisfied(physical: NWInterface.InterfaceType?)
    case unsatisfied
    case changed(from: NWInterface.InterfaceType?, to: NWInterface.InterfaceType?)
}

public actor NetworkReachability {
    public typealias Event = NetworkReachabilityEvent
    public typealias Listener = @Sendable (Event) -> Void

    // MARK: - Configuration

    /// Minimum time between emitted events. 500ms per Pitfall 2.
    private let throttle: TimeInterval = 0.5

    // MARK: - State

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "app.bbtb.reachability", qos: .userInitiated)
    private var lastPhysicalType: NWInterface.InterfaceType?
    private var lastEmittedAt: Date = .distantPast
    private var listener: Listener?
    private var isMonitorStarted: Bool = false
    private let log = Logger(subsystem: "app.bbtb.client", category: "reachability")

    public init() {}

    // MARK: - Public API

    /// Sets (or replaces) the listener without touching the live monitor. Used by
    /// tests so they can call `processPath(_:now:)` directly; also reused by
    /// `start(_:)`.
    public func setListener(_ listener: @escaping Listener) {
        self.listener = listener
    }

    /// Starts the live `NWPathMonitor` and routes updates through `processPath`.
    /// Idempotent — calling twice is a no-op.
    public func start(_ listener: @escaping Listener) {
        self.listener = listener
        guard !isMonitorStarted else { return }
        isMonitorStarted = true

        monitor.pathUpdateHandler = { [weak self] path in
            let physical = path.availableInterfaces.first(where: Self.isPhysical)?.type
            let snapshot = NWPathSnapshot(status: path.status, physicalType: physical)
            let now = Date()
            Task { [weak self] in
                await self?.processPath(snapshot, now: now)
            }
        }
        monitor.start(queue: queue)
        log.notice("NetworkReachability started")
    }

    /// Cancels the live monitor and clears all state. After `stop()`, subsequent
    /// `processPath` calls emit nothing until a new listener is installed.
    public func stop() {
        if isMonitorStarted {
            monitor.cancel()
            isMonitorStarted = false
            log.notice("NetworkReachability stopped")
        }
        listener = nil
        lastPhysicalType = nil
        lastEmittedAt = .distantPast
    }

    // MARK: - Testable Core

    /// Pure event-processing core. Applies throttle, dedup, and the
    /// physical-interface state machine. Both `start(_:)`-installed callbacks and
    /// tests call this entry point, ensuring identical behavior.
    internal func processPath(_ snapshot: NWPathSnapshot, now: Date) {
        // Throttle: drop callbacks closer than `throttle` to the last emission.
        guard now.timeIntervalSince(lastEmittedAt) >= throttle else { return }

        let event: Event
        switch snapshot.status {
        case .unsatisfied, .requiresConnection:
            if lastPhysicalType != nil {
                event = .unsatisfied
            } else {
                // Already at "no physical" baseline → no-op.
                return
            }
        case .satisfied:
            if let phys = snapshot.physicalType {
                if lastPhysicalType == nil {
                    event = .satisfied(physical: phys)
                } else if lastPhysicalType != phys {
                    event = .changed(from: lastPhysicalType, to: phys)
                } else {
                    // Same physical type — dedup.
                    return
                }
            } else {
                // Satisfied but no physical iface (loopback / utun only) — treat as
                // "no usable network for our purposes". No-op unless we were
                // previously on a physical interface (then signal loss).
                if lastPhysicalType != nil {
                    event = .unsatisfied
                } else {
                    return
                }
            }
        @unknown default:
            return
        }

        lastEmittedAt = now
        lastPhysicalType = snapshot.physicalType
        listener?(event)
    }

    // MARK: - Internal helpers

    /// Physical interfaces only — mirrors `ExtensionPlatformInterface.isPhysical`.
    /// Excludes `.loopback`, `.other` (utun), and any future type Apple adds.
    private static func isPhysical(_ iface: NWInterface) -> Bool {
        switch iface.type {
        case .wifi, .cellular, .wiredEthernet:
            return true
        default:
            return false
        }
    }
}
