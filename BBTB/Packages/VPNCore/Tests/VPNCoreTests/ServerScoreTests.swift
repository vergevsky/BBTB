// ServerScoreTests — D-01: ProbeAggregate score formula = avg × (1 + lossRate)
// Phase 3 / Plan 02 — TDD RED phase.

import XCTest
@testable import VPNCore

final class ServerScoreTests: XCTestCase {

    func test_aggregate_score_zero_loss() {
        let agg = ProbeAggregate(avgLatencyMs: 100, lossRate: 0.0, probedAt: Date())
        XCTAssertNotNil(agg.score)
        XCTAssertEqual(agg.score ?? .nan, 100.0, accuracy: 0.0001,
                       "Zero loss → score == avgLatencyMs")
        XCTAssertFalse(agg.isUnreachable)
    }

    func test_aggregate_score_with_loss() {
        // avg=100ms, lossRate=1/3 → score = 100 × (1 + 0.333…) ≈ 133.333…
        let agg = ProbeAggregate(avgLatencyMs: 100, lossRate: 1.0 / 3.0, probedAt: Date())
        XCTAssertNotNil(agg.score)
        XCTAssertEqual(agg.score!, 100.0 * (1.0 + 1.0 / 3.0), accuracy: 0.01,
                       "score formula = avg × (1 + lossRate)")
        XCTAssertFalse(agg.isUnreachable, "2/3 success ещё не unreachable")
    }

    func test_aggregate_score_full_loss_nil_avg() {
        let agg = ProbeAggregate(avgLatencyMs: nil, lossRate: 1.0, probedAt: Date())
        XCTAssertNil(agg.score, "Full loss с nil avg → score == nil")
        XCTAssertTrue(agg.isUnreachable)
    }

    func test_aggregate_isUnreachable_only_when_avg_nil() {
        // 2 из 3 fail, но 1 success → avgLatencyMs != nil → reachable
        let agg = ProbeAggregate(avgLatencyMs: 500, lossRate: 2.0 / 3.0, probedAt: Date())
        XCTAssertFalse(agg.isUnreachable,
                       "isUnreachable должен возвращать true ТОЛЬКО когда avgLatencyMs == nil")
        XCTAssertNotNil(agg.score)
    }
}
