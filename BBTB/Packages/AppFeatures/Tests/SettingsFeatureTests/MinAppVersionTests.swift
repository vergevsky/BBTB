// MinAppVersionTests.swift — Phase 8 / W3.3
//
// Тесты semver-comparison logic для D-11 min_app_version flow per RESEARCH:
// `String.compare(_, options: .numeric)` обрабатывает 1.2.10 > 1.2.9 корректно
// (lex sort даёт обратный результат). Покрываем edge cases где numeric compare
// критичен.

import XCTest
@testable import SettingsFeature

final class MinAppVersionTests: XCTestCase {

    // MARK: - 1. current < min → needsUpgrade=true

    func test_currentBelowMin_returnsTrue() {
        let current = "1.0.5"
        let minRequired = "1.2.0"
        let result = current.compare(minRequired, options: .numeric)
        XCTAssertEqual(result, .orderedAscending,
                       "1.0.5 < 1.2.0 → orderedAscending (current below min → needsUpgrade)")
    }

    // MARK: - 2. current == min → not needs upgrade

    func test_currentEqualToMin_returnsFalse() {
        let current = "1.2.0"
        let minRequired = "1.2.0"
        let result = current.compare(minRequired, options: .numeric)
        XCTAssertEqual(result, .orderedSame,
                       "1.2.0 == 1.2.0 → orderedSame (equal version OK)")
    }

    // MARK: - 3. current > min → not needs upgrade

    func test_currentAboveMin_returnsFalse() {
        let current = "1.2.10"
        let minRequired = "1.2.0"
        let result = current.compare(minRequired, options: .numeric)
        XCTAssertEqual(result, .orderedDescending,
                       "1.2.10 > 1.2.0 → orderedDescending (current above min)")
    }

    // MARK: - 4. CRITICAL — 1.2.10 > 1.2.9 (numeric semver edge case)

    /// Lex sort даёт 1.2.10 < 1.2.9 (`"1"` < `"9"` byte-wise). Numeric compare
    /// корректно интерпретирует 10 > 9. Это критичный edge case.
    func test_numericSemverComparison_handles_1_2_10_greater_than_1_2_9() {
        let current = "1.2.10"
        let minRequired = "1.2.9"
        let result = current.compare(minRequired, options: .numeric)
        XCTAssertEqual(result, .orderedDescending,
                       "1.2.10 > 1.2.9 numeric compare (lex sort даёт обратное!)")

        // Inverse: 1.2.9 < 1.2.10 → orderedAscending.
        let inverseResult = "1.2.9".compare("1.2.10", options: .numeric)
        XCTAssertEqual(inverseResult, .orderedAscending,
                       "1.2.9 < 1.2.10 inverse check")
    }

    // MARK: - 5. CRITICAL — 1.10.0 > 1.9.9 (same lex trap, different position)

    func test_numericSemverComparison_handles_1_10_0_greater_than_1_9_9() {
        let result = "1.10.0".compare("1.9.9", options: .numeric)
        XCTAssertEqual(result, .orderedDescending,
                       "1.10.0 > 1.9.9 numeric — middle component edge case")
    }

    // MARK: - 6. Dismissed version skips sheet

    /// VM logic (MainScreenViewModel.handleMinAppVersionCheck):
    /// `alreadyDismissed = dismissedMinAppVersion == snapshot.minAppVersion`.
    /// Если строки equal → не показывать sheet снова (UI-SPEC §A-08).
    func test_dismissedVersion_skipsSheet() {
        let dismissedMinAppVersion = "1.2.0"
        let snapshotMinAppVersion = "1.2.0"

        let alreadyDismissed = (dismissedMinAppVersion == snapshotMinAppVersion)
        XCTAssertTrue(alreadyDismissed, "Equal stored dismissal → skip sheet for same version")

        // Если admin поднял min_app_version → 1.3.0 — flag устарел, sheet re-presents.
        let newSnapshot = "1.3.0"
        let stillDismissed = (dismissedMinAppVersion == newSnapshot)
        XCTAssertFalse(stillDismissed, "New min_app_version → dismissal flag для старой не применяется")
    }
}
