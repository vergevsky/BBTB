// ResolveConnectionSinceTests.swift — Phase 13 / T-C9' (closes C3'-002 MEDIUM).
//
// Verifies `MainScreenViewModel.resolveConnectionSince(connectedDate:sticky:now:)`
// helper handling intra-session race vs cross-session stale leak:
//
// - Within-session race (WireGuard bug): `cs` slightly later than `cd` (≤ 60s)
//   → min(cd, cs) = cd (preserve A3-002 fix).
// - Cross-session stale: `cs` significantly older than `cd` (> 60s)
//   → trust fresh `cd` instead.
// - cd-nil + stale cs: prefer `now` over hours-old `cs`.
// - cd-nil + recent cs (≤ 60s): preserve `cs` (compatible with WireGuard race
//   where `.connected` event arrives with cd=nil first).
// - cd-only: returns `cd` (legitimate even if old — tunnel restored after suspend).
// - Both nil: returns `now` fallback.

import XCTest
import Foundation
@testable import MainScreenFeature

final class ResolveConnectionSinceTests: XCTestCase {

    private let now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    func test_withinSessionRace_picksEarlier_cd() {
        // WireGuard re-fire scenario: cs (Date() fallback) slightly later than real cd.
        let cd = now.addingTimeInterval(-5)
        let cs = now.addingTimeInterval(-3)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now
        )
        XCTAssertEqual(result, cd, "Within-session race → min(cd, cs) = cd")
    }

    func test_withinSessionRace_picksEarlier_cs() {
        // Reverse case: cd populated later than cs (rare but mathematically possible).
        let cs = now.addingTimeInterval(-10)
        let cd = now.addingTimeInterval(-8)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now
        )
        XCTAssertEqual(result, cs, "Within-session race → min(cd, cs) = cs when cs earlier")
    }

    func test_crossSessionStale_cs_trustsFresh_cd() {
        // C3'-002 fix: stale cs from prev session (hours old) — trust fresh cd.
        let cs = now.addingTimeInterval(-86_400)  // 24h ago — prev session
        let cd = now.addingTimeInterval(-2)        // fresh connect
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now
        )
        XCTAssertEqual(result, cd, "Cross-session stale cs (>60s) → trust fresh cd")
    }

    func test_thresholdBoundary_at60Seconds() {
        // Exactly 60s — boundary. Comparison is `> 60`, так что 60s should still be intra-session.
        let cs = now.addingTimeInterval(-60)
        let cd = now
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now
        )
        XCTAssertEqual(result, cs, "60s delta = boundary, treated as intra-session → min picks cs")
    }

    func test_thresholdBoundary_at61Seconds() {
        let cs = now.addingTimeInterval(-61)
        let cd = now
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now
        )
        XCTAssertEqual(result, cd, "61s delta > threshold → trust fresh cd")
    }

    func test_cdOnly_returnsCd_evenIfOld() {
        // Old cd is OK — tunnel restored after suspend may legitimately have old connectedDate.
        let cd = now.addingTimeInterval(-7_200)  // 2h ago
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: nil, now: now
        )
        XCTAssertEqual(result, cd, "cd-only → return cd, even if old")
    }

    func test_csOnly_recent_returnsCs() {
        // cd=nil scenario (NE временно not populated): cs ≤ 60s old → trust cs.
        let cs = now.addingTimeInterval(-30)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: cs, now: now
        )
        XCTAssertEqual(result, cs, "cd=nil + recent cs → use cs")
    }

    func test_csOnly_stale_returnsNow() {
        // cd=nil + stale cs from prev session — return now, не показываем stale time.
        let cs = now.addingTimeInterval(-86_400)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: cs, now: now
        )
        XCTAssertEqual(result, now, "cd=nil + stale cs (>60s) → return now")
    }

    func test_bothNil_returnsNow() {
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: nil, now: now
        )
        XCTAssertEqual(result, now, "Both nil → return now fallback")
    }
}
