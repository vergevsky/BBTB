// ServerListSheetHeightTests.swift — Phase 11 / Plan 07 / Task 7.2 / D-08.
//
// Тесты на pure helper'ы `ServerListSheet.estimatedHeight(sections:)` и
// `ServerListSheet.computeDetents(sections:)`. Оба static, exposed `internal`
// для @testable доступа (см. comment в `ServerListSheet.swift`).
//
// Подход:
// - estimatedHeight тестируется напрямую (вызов с фиксированными секциями).
//   На monotonicity (empty < 1-сервер < 8-серверов) и presence emptyCardH в
//   пустом pool'е.
// - computeDetents тестируется на empty pool (всегда non-empty detents set) и
//   на iOS-specific switch к `.large` когда контент превышает 88% screen.
//
// CONSTRAINTS:
// - НЕ trying snapshot — нет ViewInspector / нет XCTViewController.
// - НЕ trying assert UIScreen.main.bounds в test runner (xctest на CLI macOS
//   target не имеет UIScreen; #if os(iOS) ветка computeDetents проверяется
//   через iOS-target xcodebuild test когда Phase 11 closure UAT происходит).
//
// Pattern: pure-function testing, аналогично `ConnectionButtonTests.isConnecting`.

import XCTest
import SwiftUI
import VPNCore
@testable import ServerListFeature

final class ServerListSheetHeightTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Создаёт тривиальную manual-section (без subscription) с N серверами.
    private func makeManualSection(serverCount: Int) -> ServerListSection {
        let servers = (0..<serverCount).map { idx in
            ServerConfig(
                name: "test-\(idx)",
                host: "1.2.3.\(idx)",
                port: 443,
                protocolID: "vless",
                keychainTag: nil
            )
        }
        return ServerListSection(id: "manual", subscription: nil, servers: servers)
    }

    // MARK: - estimatedHeight tests

    /// Empty pool → высота = headerH + autoCellH + emptyCardH + bottomBuf.
    /// Никаких section header'ов / server row'ов нет.
    func test_estimatedHeight_emptyPool_includesEmptyCard() {
        let h = ServerListSheet.estimatedHeight(sections: [])
        // 81 (header) + 116 (auto) + 220 (empty) + 40 (bottom) = 457.
        XCTAssertEqual(h, 81 + 116 + 220 + 40,
                       "Empty pool height должен включать headerH + autoCellH + emptyCardH + bottomBuf")
    }

    /// Single manual server → высота = headerH + autoCellH + manHeaderH + serverRowH + bottomBuf.
    /// Меньше чем empty (т.к. emptyCardH=220 > manHeaderH+serverRowH=36+80=116).
    func test_estimatedHeight_singleServer_smallerThanEmptyPool() {
        let single = makeManualSection(serverCount: 1)
        let hSingle = ServerListSheet.estimatedHeight(sections: [single])
        let hEmpty = ServerListSheet.estimatedHeight(sections: [])
        XCTAssertLessThan(hSingle, hEmpty,
                          "1 manual server должен иметь меньший estimated height чем empty pool (manHeaderH+serverRowH < emptyCardH)")
    }

    /// 8 серверов → высота должна быть >> 1 сервера (монотонно по count).
    /// D-08 invariant: каждая дополнительная row добавляет serverRowH.
    func test_estimatedHeight_eightServers_largerThanSingleServer() {
        let single = makeManualSection(serverCount: 1)
        let eight  = makeManualSection(serverCount: 8)
        let hSingle = ServerListSheet.estimatedHeight(sections: [single])
        let hEight  = ServerListSheet.estimatedHeight(sections: [eight])
        // Разница ≥ 7 * serverRowH = 560.
        XCTAssertGreaterThanOrEqual(hEight - hSingle, 7 * 80,
                                    "Каждая дополнительная row добавляет serverRowH = 80")
    }

    /// Smoke gate — все 7 height-констант > 0.
    /// Регрессия-guard: если кто-то случайно занулит константу при Figma update
    /// — тест ловит.
    func test_heightConstants_arePositive() {
        XCTAssertGreaterThan(ServerListSheet.headerH,    0, "headerH > 0")
        XCTAssertGreaterThan(ServerListSheet.autoCellH,  0, "autoCellH > 0")
        XCTAssertGreaterThan(ServerListSheet.subHeaderH, 0, "subHeaderH > 0")
        XCTAssertGreaterThan(ServerListSheet.manHeaderH, 0, "manHeaderH > 0")
        XCTAssertGreaterThan(ServerListSheet.serverRowH, 0, "serverRowH > 0")
        XCTAssertGreaterThan(ServerListSheet.emptyCardH, 0, "emptyCardH > 0")
        XCTAssertGreaterThan(ServerListSheet.bottomBuf,  0, "bottomBuf > 0")
    }

    // MARK: - computeDetents tests

    /// Empty pool → detents всегда non-empty (sheet всё равно открывается).
    /// На macOS → ровно [.large]. На iOS → [.height(N)] или [.large] в зависимости
    /// от screen height (в xctest CLI runner на macOS — macOS branch активен).
    func test_computeDetents_emptyPool_returnsNonEmptyDetents() {
        let detents = ServerListSheet.computeDetents(sections: [])
        XCTAssertFalse(detents.isEmpty,
                       "computeDetents для empty pool не должен возвращать пустой set")
        #if os(macOS)
        XCTAssertEqual(detents, [.large],
                       "На macOS computeDetents всегда возвращает [.large]")
        #endif
    }

    /// Множество секций → detents всё равно non-empty. Regression smoke.
    func test_computeDetents_withSections_returnsNonEmptyDetents() {
        let section = makeManualSection(serverCount: 3)
        let detents = ServerListSheet.computeDetents(sections: [section])
        XCTAssertFalse(detents.isEmpty,
                       "computeDetents для 3-server pool не должен возвращать пустой set")
    }
}
