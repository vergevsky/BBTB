// DiagnosticsExporterTests.swift — Phase 11 / 11-05 / TELEM-02
//
// Unit-тесты для `DiagnosticsExporter`:
// - maskIPv4: happy path / preserve non-IP / multiple matches / IPv6 untouched.
// - anonymousDeviceID: stable across calls + UUID-формат.
// - prepareLog: возвращает nil для несуществующего log path (Pitfall 8).
//
// UserDefaults setUp/tearDown очищает `app.bbtb.anonymousDeviceID` per Pattern S9 —
// чтобы тесты не загрязняли default suite и не зависели от порядка запуска.

import XCTest
@testable import SettingsFeature

final class DiagnosticsExporterTests: XCTestCase {

    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: DiagnosticsExporter.anonymousDeviceIDKey)
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: DiagnosticsExporter.anonymousDeviceIDKey)
        try await super.tearDown()
    }

    // MARK: - maskIPv4

    func test_maskIPv4_replacesLastOctet() {
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("192.168.1.42"), "192.168.1.xxx")
    }

    func test_maskIPv4_preservesNonIP() {
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("user@host:8080"), "user@host:8080")
    }

    func test_maskIPv4_multipleInOneString() {
        let input = "connect 10.0.0.1 -> 8.8.8.8"
        let out = DiagnosticsExporter.maskIPv4(input)
        XCTAssertEqual(out, "connect 10.0.0.xxx -> 8.8.8.xxx")
    }

    /// D-12 spec покрывает только IPv4 — IPv6 представления должны проходить без изменений.
    func test_maskIPv4_handlesIPv6Untouched() {
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("::1"), "::1")
        XCTAssertEqual(DiagnosticsExporter.maskIPv4("fe80::1"), "fe80::1")
    }

    // MARK: - Plan 09 C6-4-002 — maskDottedIPv6 (closes IPv4-mapped IPv6 leak HIGH)

    /// IPv4-mapped IPv6 dotted form `::ffff:N.N.N.N`. Pre-fix leaked
    /// network prefix as `[ipv6:xxx].2.3.xxx` after maskIPv4 + maskIPv6.
    /// Post-fix: whole substring → `[ipv6:xxx]`.
    func test_maskDottedIPv6_ipv4Mapped() {
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("remote=::ffff:1.2.3.4"),
                       "remote=[ipv6:xxx]")
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("remote=::FFFF:192.168.1.1"),
                       "remote=[ipv6:xxx]")
    }

    /// NAT64 well-known prefix `64:ff9b::N.N.N.N` (RFC 6052).
    func test_maskDottedIPv6_nat64() {
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("via 64:ff9b::127.0.0.1"),
                       "via [ipv6:xxx]")
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("via 64:FF9B::8.8.8.8"),
                       "via [ipv6:xxx]")
    }

    /// IPv4-compatible IPv6 `::N.N.N.N` (RFC 4291 deprecated but Apple still parses).
    func test_maskDottedIPv6_ipv4Compatible() {
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("addr=::169.254.0.1"),
                       "addr=[ipv6:xxx]")
    }

    /// **End-to-end pipeline test:** verify maskDottedIPv6 + maskIPv4 + maskIPv6
    /// chain replaces dotted forms completely. Pre-fix produced
    /// `[ipv6:xxx].168.1.xxx`-style leaks.
    func test_C6_4_002_pipelineReplacesDottedIPv6_completely() {
        let pipeline: (String) -> String = { input in
            DiagnosticsExporter.maskIPv6(
                DiagnosticsExporter.maskIPv4(
                    DiagnosticsExporter.maskDottedIPv6(input)
                )
            )
        }
        XCTAssertEqual(pipeline("connect ::ffff:192.168.1.1"),
                       "connect [ipv6:xxx]")
        XCTAssertEqual(pipeline("nat64 path 64:ff9b::10.0.0.1"),
                       "nat64 path [ipv6:xxx]")
        XCTAssertEqual(pipeline("compat ::8.8.8.8"),
                       "compat [ipv6:xxx]")
    }

    /// Regression-guard: timestamps + non-IP strings must NOT match.
    func test_maskDottedIPv6_doesNotFalseMatch() {
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("time=12:34:45"),
                       "time=12:34:45")
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("clean text"),
                       "clean text")
    }

    /// Regression-guard: plain IPv4 (no IPv6 prefix) must pass through
    /// untouched by maskDottedIPv6 (subsequent maskIPv4 handles it).
    func test_maskDottedIPv6_passesPlainIPv4Untouched() {
        XCTAssertEqual(DiagnosticsExporter.maskDottedIPv6("addr=192.168.1.1"),
                       "addr=192.168.1.1")
    }

    // MARK: - anonymousDeviceID

    func test_anonymousDeviceID_stable() {
        let id1 = DiagnosticsExporter.anonymousDeviceID()
        let id2 = DiagnosticsExporter.anonymousDeviceID()
        XCTAssertEqual(id1, id2, "ID должен быть стабилен между вызовами (persisted в UserDefaults)")

        // UUID-формат: 36 символов, hyphenated 8-4-4-4-12.
        XCTAssertEqual(id1.count, 36)
        XCTAssertEqual(id1.filter { $0 == "-" }.count, 4)
    }

    // MARK: - prepareLog

    func test_prepareLog_returnsNilWhenLogAbsent() async {
        // Inject заведомо несуществующий путь — Pitfall 8 path.
        // Это избавляет тест от зависимости от content `AppGroupContainer.singBoxLogPath`
        // в test runner sandbox (см. RESEARCH § Validation Architecture).
        let nonexistent = "/tmp/bbtb-test-nonexistent-\(UUID().uuidString).log"
        let url = await DiagnosticsExporter.prepareLog(logPath: nonexistent)
        XCTAssertNil(url, "Должен вернуть nil когда файла лога нет")
    }
}
