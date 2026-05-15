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
