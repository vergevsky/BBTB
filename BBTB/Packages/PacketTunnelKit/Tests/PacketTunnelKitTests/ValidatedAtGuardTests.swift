// ValidatedAtGuardTests.swift — Phase 6e Wave 1 M8 (+ L12 bundled).
//
// Verifies pre-expand validate cache marker:
//   ConfigImporter writes `providerConfiguration["configJSONValidatedAt"]`
//   = ISO8601 timestamp ПОСЛЕ собственного успешного `SingBoxConfigLoader.validate`.
//   BaseSingBoxTunnel.startTunnel skip-ает pre-expand validate когда timestamp
//   < 24h. POST-expand validate (R10 defense-in-depth, line 240-251) ОСТАЁТСЯ
//   unconditional и обязательно проверяется через `grep -c "SingBoxConfigLoader.validate"
//   BaseSingBoxTunnel.swift` ≥ 2.
//
// Test seam: pure static helper `BaseSingBoxTunnel.shouldSkipPreExpandValidate(
// providerConfiguration:now:)` — testable без NEPacketTunnelProvider lifecycle.
// Helper читает `providerConfiguration["configJSONValidatedAt"]` как ISO8601
// string, парсит, и возвращает true если ISO8601 < 24h до `now`. False иначе
// (включая parse failure / missing key) — backward-compat для cold-reboot.

import XCTest
@testable import PacketTunnelKit

final class ValidatedAtGuardTests: XCTestCase {

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    // MARK: - Tests

    /// Test 1 — validatedAt в пределах 24h окна → skip = true. Pre-expand
    /// validate в production startTunnel будет skip-ed, post-expand validate
    /// (R10 defense-in-depth) выполняется независимо.
    func test_pre_expand_validate_skipped_when_validatedAt_within_24h() throws {
        let now = Date()
        let validatedAt = now.addingTimeInterval(-3600) // 1h назад
        let providerConfig: [String: Any] = [
            "configJSON": "{\"outbounds\":[]}",
            "configJSONValidatedAt": isoFormatter.string(from: validatedAt)
        ]
        XCTAssertTrue(
            BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration: providerConfig, now: now),
            "validatedAt 1h ago → должен skip pre-expand validate"
        )
    }

    /// Test 2 — fresh validatedAt (now) → skip = true. Edge case прямо после
    /// провижионинга через ConfigImporter (timestamp ≈ Date()).
    func test_pre_expand_validate_skipped_when_validatedAt_just_now() throws {
        let now = Date()
        let providerConfig: [String: Any] = [
            "configJSON": "{\"outbounds\":[]}",
            "configJSONValidatedAt": isoFormatter.string(from: now)
        ]
        XCTAssertTrue(
            BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration: providerConfig, now: now),
            "Validated at now → skip"
        )
    }

    /// Test 3 — backward-compat для cold-reboot / старых providerConfiguration
    /// без timestamp: validatedAt missing → skip = false → pre-expand validate
    /// runs (R1/SEC-06 enforcement).
    func test_pre_expand_validate_runs_when_validatedAt_missing() throws {
        let now = Date()
        let providerConfig: [String: Any] = [
            "configJSON": "{\"outbounds\":[]}"
        ]
        XCTAssertFalse(
            BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration: providerConfig, now: now),
            "configJSONValidatedAt missing → pre-expand validate выполняется (backward-compat)"
        )
    }

    /// Test 4 — validatedAt > 24h → skip = false. Стрый stale timestamp защищает
    /// от unbounded trust period — даже если ConfigImporter валидировал давно,
    /// перезапуск extension через сутки → re-validate.
    func test_pre_expand_validate_runs_when_validatedAt_stale_over_24h() throws {
        let now = Date()
        let validatedAt = now.addingTimeInterval(-25 * 3600) // 25 часов назад
        let providerConfig: [String: Any] = [
            "configJSON": "{\"outbounds\":[]}",
            "configJSONValidatedAt": isoFormatter.string(from: validatedAt)
        ]
        XCTAssertFalse(
            BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration: providerConfig, now: now),
            "validatedAt 25h ago → stale → pre-expand validate выполняется"
        )
    }

    /// Test 5 — defensive: malformed ISO8601 string → skip = false (treat as
    /// missing). Защищает от corruption / future format changes.
    func test_pre_expand_validate_runs_when_validatedAt_malformed() throws {
        let now = Date()
        let providerConfig: [String: Any] = [
            "configJSON": "{\"outbounds\":[]}",
            "configJSONValidatedAt": "not-an-iso8601-string"
        ]
        XCTAssertFalse(
            BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration: providerConfig, now: now),
            "Malformed timestamp → treat as missing → pre-expand validate выполняется"
        )
    }
}
