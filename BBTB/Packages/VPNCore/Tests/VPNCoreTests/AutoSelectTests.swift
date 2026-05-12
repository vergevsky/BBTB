// AutoSelectTests — D-03: pure-function ServerScore.autoSelect picks min score.
// Phase 3 / Plan 02 — TDD RED phase.

import XCTest
@testable import VPNCore

final class AutoSelectTests: XCTestCase {

    func test_auto_select_picks_min_score() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        let pick = ServerScore.autoSelect([(a, 100.0), (b, 50.0), (c, 200.0)])
        XCTAssertEqual(pick, b, "Должен быть выбран сервер с минимальным score (b=50)")
    }

    func test_auto_select_skips_unreachable() {
        let a = UUID()  // unreachable
        let b = UUID()  // reachable, лучший
        let c = UUID()  // reachable, хуже
        let pick = ServerScore.autoSelect([(a, nil), (b, 80.0), (c, 150.0)])
        XCTAssertEqual(pick, b, "nil-score кандидаты должны фильтроваться")
    }

    func test_auto_select_all_unreachable_returns_nil() {
        let a = UUID()
        let b = UUID()
        let pick = ServerScore.autoSelect([(a, nil), (b, nil)])
        XCTAssertNil(pick, "Если все unreachable → nil (Pitfall 8 fallback)")
    }

    func test_auto_select_empty_input_returns_nil() {
        let pick = ServerScore.autoSelect([])
        XCTAssertNil(pick)
    }

    func test_auto_select_single_reachable() {
        let only = UUID()
        // Не должен быть фильтра «слишком медленно» — score 999 всё равно reachable.
        let pick = ServerScore.autoSelect([(only, 999.0)])
        XCTAssertEqual(pick, only)
    }
}
