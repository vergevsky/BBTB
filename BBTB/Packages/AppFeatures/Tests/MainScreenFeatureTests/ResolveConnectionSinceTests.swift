// ResolveConnectionSinceTests.swift — Phase 13 / T-C9' (closes C3'-002 MEDIUM)
//   + T-C-R1' (closes A3-002 regression of T-C9').
//
// Verifies `MainScreenViewModel.resolveConnectionSince(connectedDate:sticky:now:sawTerminalStatus:)`
// helper:
//
// - Within-session race (WireGuard bug): `cs` slightly later than `cd` (≤ 60s)
//   → min(cd, cs) = cd (preserve A3-002 fix).
// - Cross-session stale: intervening `.disconnected` observed → trust fresh `cd`.
// - Long-background WITHIN session (T-C-R1' regression fix): NO intervening
//   `.disconnected` → preserve min(cd, cs) даже если cs significantly older
//   than cd (legitimate Wi-Fi handoff / NE reassert / foreground re-entry).
// - 24h safety net: missed-event regressions still get treated as cross-session
//   even when sawTerminalStatus=false.

import XCTest
import Foundation
@testable import MainScreenFeature

/// Plan 09 drive-by fix: `@MainActor` required because `MainScreenViewModel.resolveConnectionSince`
/// is main-actor isolated. Without this annotation, Swift 6 strict concurrency rejects the
/// synchronous-nonisolated-context call. Pre-existing on main; surfaced когда я попытался
/// запустить ServerListFeature tests через `AppFeatures-Package` scheme.
@MainActor
final class ResolveConnectionSinceTests: XCTestCase {

    private let now: Date = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Within-session race (WireGuard bug history, A3-002 invariant)

    func test_withinSessionRace_picksEarlier_cd() {
        // WireGuard re-fire scenario: cs (Date() fallback) slightly later than real cd.
        let cd = now.addingTimeInterval(-5)
        let cs = now.addingTimeInterval(-3)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cd, "Within-session race + no intervening terminal → min(cd, cs) = cd")
    }

    func test_withinSessionRace_picksEarlier_cs() {
        let cs = now.addingTimeInterval(-10)
        let cd = now.addingTimeInterval(-8)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cs, "Within-session race → min(cd, cs) = cs when cs earlier")
    }

    // MARK: - T-C-R1' regression fix: intervening-terminal gate (closes A3-002)

    func test_interveningTerminal_trustsFreshCd() {
        // User connects (cs=T0), disconnects (.disconnected observed), reconnects (cd=T1).
        // sawTerminalStatus=true → switch authority к fresh cd.
        let cs = now.addingTimeInterval(-3600)  // 1h ago — prev session
        let cd = now.addingTimeInterval(-2)     // fresh
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: true
        )
        XCTAssertEqual(result, cd, "Intervening .disconnected → trust fresh cd")
    }

    func test_noInterveningTerminal_preservesCs_longBackground() {
        // T-C-R1' KEY CASE: long-background session WITHOUT .disconnected.
        // User connects (cs=T0), backgrounds app for 5 min, foregrounds.
        // iOS updates connectedDate (cd=T0+5min) but session is logically
        // continuous → preserve cs (oldest = real start), NOT fresh cd.
        let cs = now.addingTimeInterval(-3600)        // T0 = 1h ago
        let cd = now.addingTimeInterval(-3300)        // iOS reasserted 5min later
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cs, "Long-background within-session → preserve cs (original connect time)")
    }

    func test_noInterveningTerminal_preservesCs_evenAfterHours() {
        // Pre-T-C-R1', T-C9' threshold ошибочно switched к cd here. Fixed:
        // без intervening .disconnected — это logically same session.
        let cs = now.addingTimeInterval(-7200)  // 2h ago — legitimate
        let cd = now.addingTimeInterval(-1800)  // 30min ago — iOS reassert
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cs, "2h legitimate session → preserve original cs")
    }

    // MARK: - 24h safety net (missed-event protection)

    func test_safetyNet_24hExceeded_trustsFreshCd() {
        // Even without sawTerminalStatus=true, if cd-cs > 24h, treat as
        // cross-session (catches missed `.disconnected` events from race
        // conditions where applyVPNStatus deduped duplicate event).
        let cs = now.addingTimeInterval(-90_000)  // 25h ago — definitely prev session
        let cd = now.addingTimeInterval(-2)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cd, "24h safety net: missed-event protection")
    }

    // MARK: - cd-only / cs-only branches

    func test_cdOnly_returnsCd() {
        let cd = now.addingTimeInterval(-7_200)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: cd, sticky: nil, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cd, "cd-only → return cd")
    }

    func test_csOnly_recent_preserved() {
        let cs = now.addingTimeInterval(-30)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, cs, "cd=nil + recent cs + no terminal → preserve cs")
    }

    func test_csOnly_interveningTerminal_returnsNow() {
        // cd=nil + intervening .disconnected → cs is from prev session.
        let cs = now.addingTimeInterval(-3600)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: cs, now: now, sawTerminalStatus: true
        )
        XCTAssertEqual(result, now, "cd=nil + sawTerminal → now (cs assumed stale)")
    }

    func test_csOnly_24h_safetyNet() {
        let cs = now.addingTimeInterval(-90_000)
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: cs, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, now, "cd=nil + 24h stale cs → now (safety net)")
    }

    func test_bothNil_returnsNow() {
        let result = MainScreenViewModel.resolveConnectionSince(
            connectedDate: nil, sticky: nil, now: now, sawTerminalStatus: false
        )
        XCTAssertEqual(result, now, "Both nil → now fallback")
    }
}
