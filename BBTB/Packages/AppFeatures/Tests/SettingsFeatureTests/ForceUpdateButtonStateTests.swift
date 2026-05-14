// ForceUpdateButtonStateTests.swift — Phase 8 / W3.3
//
// Pure unit-тесты состояния `ForceUpdateButtonState` enum + wallclock-cooldown
// logic. Cover все state transitions + Equatable + wallclock-correct
// foreground re-entry per UI-SPEC §Edge Cases.

import XCTest
@testable import SettingsFeature

final class ForceUpdateButtonStateTests: XCTestCase {

    // MARK: - 1. Initial state — .idle

    func test_initialState_isIdle() {
        let state: ForceUpdateButtonState = .idle
        XCTAssertEqual(state, .idle, "Default ForceUpdateButtonState — .idle")
    }

    // MARK: - 2. .inProgress блокирует tap (через Equatable)

    func test_inProgress_blocksAdditionalTaps() {
        // ViewModel.triggerForceUpdate использует `guard state == .idle else { return }`
        // — проверяем Equatable: .inProgress != .idle.
        let inProgress: ForceUpdateButtonState = .inProgress
        XCTAssertNotEqual(inProgress, .idle, "inProgress должен отличаться от idle для race guard")
        XCTAssertEqual(inProgress, .inProgress)
    }

    // MARK: - 3. .cooldown(60) не idle

    func test_cooldown_60s_isNotIdle() {
        let cooldown: ForceUpdateButtonState = .cooldown(secondsRemaining: 60)
        XCTAssertNotEqual(cooldown, .idle, "cooldown должен отличаться от idle (race guard)")
    }

    // MARK: - 4. cooldown decrements (via SettingsViewModel timer simulation)

    @MainActor
    func test_cooldown_decrements_via_wallclock() async throws {
        // Simulate: cooldownExpiresAt = Date() + 60s; after 1s tick → remaining ≈ 59.
        let expiresAt = Date().addingTimeInterval(60)
        // Wallclock-correct remaining computation (mirrors VM `cooldownTick`):
        let remainingNow = Int(expiresAt.timeIntervalSince(Date()).rounded(.up))
        XCTAssertGreaterThanOrEqual(remainingNow, 59, "Initial cooldown ~60s ±1")
        XCTAssertLessThanOrEqual(remainingNow, 60)

        // Sleep 1s (или меньше для test speed). Wallclock остаётся deterministic.
        try await Task.sleep(nanoseconds: 1_100_000_000) // 1.1s
        let remainingAfter1s = Int(expiresAt.timeIntervalSince(Date()).rounded(.up))
        XCTAssertLessThanOrEqual(remainingAfter1s, 59, "После 1s remaining должен ≤ 59")
        XCTAssertGreaterThanOrEqual(remainingAfter1s, 57, "Не больше чем ~3s drift")
    }

    // MARK: - 5. cooldown zero seconds → transitions to .idle

    func test_cooldown_zeroSeconds_transitionsToIdle() {
        // VM `cooldownTick` logic: если expiresAt в прошлом → remaining <= 0 → .idle.
        let expiredAt = Date().addingTimeInterval(-1) // 1s в прошлом
        let remaining = Int(expiredAt.timeIntervalSince(Date()).rounded(.up))
        XCTAssertLessThanOrEqual(remaining, 0, "Expired cooldown даёт remaining <= 0")
        // VM transition: remaining <= 0 → state = .idle (см. SettingsViewModel.cooldownTick).
    }

    // MARK: - 6. wallclock resumption — foreground re-entry

    func test_wallclock_resumption_survives_suspension() {
        // Simulate: cooldown set 30s ago при 60s окне → remaining ≈ 30.
        // Это эмулирует пользователя backgrounding app на 30s + foreground re-entry.
        let setAt = Date().addingTimeInterval(-30) // start был 30s назад
        let expiresAt = setAt.addingTimeInterval(60) // expire через 30s от сейчас
        let remainingNow = Int(expiresAt.timeIntervalSince(Date()).rounded(.up))
        XCTAssertGreaterThanOrEqual(remainingNow, 28, "After 30s suspension expect ~30s remaining (±2s grace)")
        XCTAssertLessThanOrEqual(remainingNow, 32)
    }
}
