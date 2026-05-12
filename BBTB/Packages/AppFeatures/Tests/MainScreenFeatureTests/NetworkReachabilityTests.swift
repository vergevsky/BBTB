// NetworkReachabilityTests.swift — Phase 6 / Plan 06-04 / Wave 4 / Task 1.
//
// Tests for `NetworkReachability` actor wrapping `NWPathMonitor`:
// - Physical-interface filter (Wi-Fi / Cellular / WiredEthernet — NOT loopback or utun).
// - 500ms throttle to avoid spam on micro-changes during VPN handshake (Pitfall 2).
// - Dedup via `lastPhysicalType` — same type emits no event.
// - State transitions: `.satisfied`, `.unsatisfied`, `.changed(from:to:)`.
//
// Live `NWPathMonitor` cannot be mocked directly. Tests drive the actor through its
// internal `processPath(_:now:)` entry point with synthesized `NWPathSnapshot`
// values, so we exercise the throttle/dedup/filter logic in isolation from the
// real monitor. See `.planning/phases/06-network-resilience/06-RESEARCH.md` §3.

import XCTest
import Network
@testable import MainScreenFeature

final class NetworkReachabilityTests: XCTestCase {

    // MARK: - Helpers

    /// Listener box that captures emitted events on a serial queue. Sendable-safe.
    private final class EventCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [NetworkReachability.Event] = []

        func append(_ event: NetworkReachability.Event) {
            lock.lock(); defer { lock.unlock() }
            events.append(event)
        }

        func snapshot() -> [NetworkReachability.Event] {
            lock.lock(); defer { lock.unlock() }
            return events
        }
    }

    private func makeReachability(collector: EventCollector) async -> NetworkReachability {
        let r = NetworkReachability()
        await r.setListener { event in
            collector.append(event)
        }
        return r
    }

    private func t(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

    // MARK: - Tests

    func test_reachability_filters_loopback_only_path_no_event() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        // Satisfied but only loopback (physicalType is nil after filter).
        await r.processPath(.init(status: .satisfied, physicalType: nil), now: t(0))
        XCTAssertEqual(collector.snapshot(), [])
    }

    func test_reachability_initial_wifi_emits_satisfied() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        XCTAssertEqual(collector.snapshot(), [.satisfied(physical: .wifi)])
    }

    func test_reachability_filters_utun_VPN_interface() async {
        // utun appears as .other in NWInterface.InterfaceType. Our snapshot extraction
        // (the only producer of NWPathSnapshot) filters with `isPhysical`, so the
        // snapshot we'd get for "satisfied via utun only" has physicalType=nil.
        // Verify processPath does nothing for that case (same behavior as loopback).
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: nil), now: t(0))
        XCTAssertEqual(collector.snapshot(), [])
    }

    func test_reachability_wifi_to_cellular_emits_changed() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        // 1 second later — past throttle.
        await r.processPath(.init(status: .satisfied, physicalType: .cellular), now: t(1))
        XCTAssertEqual(
            collector.snapshot(),
            [.satisfied(physical: .wifi),
             .changed(from: .wifi, to: .cellular)]
        )
    }

    func test_reachability_same_type_consecutive_dedups_to_one_event() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        // 1s later (past throttle), same physical type → no event.
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(1))
        XCTAssertEqual(collector.snapshot(), [.satisfied(physical: .wifi)])
    }

    func test_reachability_throttle_drops_event_within_500ms() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        // 100ms later — inside throttle window → dropped even though physical type changed.
        await r.processPath(.init(status: .satisfied, physicalType: .cellular), now: t(0.1))
        XCTAssertEqual(collector.snapshot(), [.satisfied(physical: .wifi)])
    }

    func test_reachability_throttle_releases_after_500ms() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        // 0.6s later — outside throttle → emit.
        await r.processPath(.init(status: .satisfied, physicalType: .cellular), now: t(0.6))
        XCTAssertEqual(
            collector.snapshot(),
            [.satisfied(physical: .wifi),
             .changed(from: .wifi, to: .cellular)]
        )
    }

    func test_reachability_unsatisfied_from_satisfied_emits_unsatisfied() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        await r.processPath(.init(status: .unsatisfied, physicalType: nil), now: t(1))
        XCTAssertEqual(
            collector.snapshot(),
            [.satisfied(physical: .wifi), .unsatisfied]
        )
    }

    func test_reachability_unsatisfied_when_already_unsatisfied_is_noop() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        // Two consecutive `.unsatisfied` from a fresh actor (lastPhysicalType == nil
        // initially). First should be no-op (we're already at "no physical" baseline);
        // second is also no-op. Net: 0 events.
        await r.processPath(.init(status: .unsatisfied, physicalType: nil), now: t(0))
        await r.processPath(.init(status: .unsatisfied, physicalType: nil), now: t(1))
        XCTAssertEqual(collector.snapshot(), [])
    }

    func test_reachability_stop_clears_listener_so_no_more_events() async {
        let collector = EventCollector()
        let r = await makeReachability(collector: collector)
        await r.processPath(.init(status: .satisfied, physicalType: .wifi), now: t(0))
        await r.stop()
        // After stop, subsequent processPath emits nothing (listener was cleared).
        await r.processPath(.init(status: .satisfied, physicalType: .cellular), now: t(10))
        XCTAssertEqual(collector.snapshot(), [.satisfied(physical: .wifi)])
    }
}
