import XCTest
import MetricKit
@testable import CrashReporter

final class CrashReporterTests: XCTestCase {
    func test_shared_isSingleton() {
        XCTAssertTrue(CrashReporter.shared === CrashReporter.shared)
    }

    func test_install_isIdempotent() {
        // Безопасно вызвать несколько раз без падения.
        CrashReporter.shared.install()
        CrashReporter.shared.install()
        CrashReporter.shared.install()
        // Тест проходит если не было crash'а / exception'а.
    }

    func test_empty_didReceive_isNoOp() {
        CrashReporter.shared.didReceive([] as [MXDiagnosticPayload])
        // Файлов не создаётся; тест на отсутствие падения.
    }

    // Note: тестирование saveDiagnostic с реальным MXDiagnosticPayload требует
    // subclass MXDiagnosticPayload и переопределения public init (Apple даёт его).
    // Phase 1 — это smoke; integration (реальный payload через MetricKit) проверяется
    // на устройстве в Wave 5 валидации (вне unit-тестов).
}
