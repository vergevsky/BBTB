// FileImporterTests.swift — Phase 11 / Wave 2 / IMP-03
//
// Unit-тесты для file picker import flow. Не покрывают саму UI кнопку
// `.fileImporter` (нет XCTest support для system document picker), но
// покрывают три критических non-UI properties:
//
//  1. `ImportSource.file` существует и !=  прочим case'ам (regression
//     guard на удаление 4-го case из enum).
//  2. `MainScreenViewModel.importFromFile(rawContents:)` направляет содержимое
//     через `importer.importFromRawInput(_:source: .file)` — НЕ через
//     pasteboard/QR. Critical для analytics traceability (Phase 12 TELEM-04).
//  3. `UTType(filenameExtension: "yaml" | "yml")` резолвится на test runtime —
//     гарантия что наш inline UTType factory в `.fileImporter` не вернёт nil
//     defensive fallback `.data` (это сломало бы фильтрацию picker).
//
// Реальное чтение файла + security-scoped resource flow — manual UAT (см.
// Phase 11 UAT plan); SwiftUI `.fileImporter` не имеет programmatic API.

import XCTest
import Foundation
import SwiftData
import UniformTypeIdentifiers
import VPNCore
import ConfigParser
@testable import MainScreenFeature

@MainActor
final class FileImporterTests: XCTestCase {

    // MARK: - Test doubles

    /// Stub `ConfigImporting` — captures `(raw, source)` from `importFromRawInput`.
    /// Other methods — empty stubs (см. `MainScreenViewModelDeepLinkTests.MockImporter`
    /// в качестве reference).
    private final class CapturingImporter: ConfigImporting, @unchecked Sendable {
        var capturedRaw: String?
        var capturedSource: ImportSource?
        var capturedCallCount: Int = 0

        func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult {
            capturedRaw = raw
            capturedSource = source
            capturedCallCount += 1
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: source, metadata: nil)
        }
        func importFromPasteboard() async throws -> ImportResult {
            // Если ВМ ошибочно идёт через pasteboard вместо .file ветки — этот
            // путь зафиксирует `nil` source, и test_importFromFile_routesToFileSource
            // упадёт.
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: .pasteboard, metadata: nil)
        }
        func importFromQRCode(_ scanned: String) async throws -> ImportResult {
            return ImportResult(supported: [], unsupported: [], failed: [],
                                subscriptionURL: nil, source: .qrCode, metadata: nil)
        }
        func loadActiveServer() -> ServerConfig? { nil }
        func countSupportedConfigs() -> Int { 0 }
        func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? { nil }
        func buildServerConfig(from server: ImportedServer,
                                id: UUID,
                                subscriptionID: UUID,
                                keychainTag: String?) -> ServerConfig {
            return ServerConfig(id: id, name: "stub", host: "0.0.0.0", port: 0,
                                protocolID: "vless-reality", keychainTag: keychainTag,
                                isSupported: true, subscriptionID: subscriptionID)
        }
        func provisionTunnelProfile(for selectedID: UUID?) async throws {}
        func runIsSupportedUpgrade() async {}
        @MainActor
        func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? { nil }
    }

    /// Minimal mock tunnel — no network calls.
    private final class MockTunnel: TunnelControlling, @unchecked Sendable {
        func connect() async throws -> Date { Date() }
        func disconnect() async throws {}
        func startReachability() async {}
        func stopReachability() async {}
        func handleForeground() async {}
    }

    // MARK: - 1. ImportSource.file case существует

    func test_importSource_fileCase_exists() {
        // Smoke gate: ловит удаление 4-го case (Plan 11-02 Task 2.1).
        let s: ImportSource = .file
        XCTAssertEqual(s, ImportSource.file)
        // Различимость от других case'ов — нужно для analytics traceability
        // (Phase 12 TELEM-04).
        XCTAssertNotEqual(s, .pasteboard)
        XCTAssertNotEqual(s, .qrCode)
        XCTAssertNotEqual(s, .deepLink)
        XCTAssertNotEqual(s, .multilineText)
    }

    // MARK: - 2. importFromFile routes to .file source

    func test_importFromFile_routesToFileSource() async {
        let importer = CapturingImporter()
        let tunnel = MockTunnel()
        let vm = MainScreenViewModel(importer: importer, tunnel: tunnel)

        let payload = "vless://test@example.com:443?security=reality#test-server"
        vm.importFromFile(rawContents: payload)

        // Дать запущенному `Task { @MainActor in await performImport(...) }`
        // времени отработать. importFromFile spawn'ит inner Task; ждём пока
        // CapturingImporter не получит вызов. Cap 1 sec.
        let deadline = Date().addingTimeInterval(1.0)
        while importer.capturedCallCount == 0 && Date() < deadline {
            try? await Task.sleep(nanoseconds: 5_000_000)  // 5 ms
        }

        XCTAssertEqual(importer.capturedCallCount, 1,
                       "importer должен получить ровно один importFromRawInput вызов")
        XCTAssertEqual(importer.capturedSource, .file,
                       "source должен быть .file (НЕ .pasteboard и НЕ .qrCode)")
        XCTAssertEqual(importer.capturedRaw, payload,
                       "raw payload должен пройти неизменённым в importer")
    }

    // MARK: - 3. UTType yaml / yml resolvable

    func test_uttype_yaml_resolvable() {
        // Наш inline UTType factory в MainScreenView fileImporter использует:
        //   UTType(filenameExtension: "yaml") ?? .data
        //   UTType(filenameExtension: "yml")  ?? .data
        // Если runtime не зарегистрировал yaml/yml UTType — fallback .data
        // принял бы ВСЕ файлы (`.data` parent type), и фильтрация
        // picker'a не работала бы. Этот тест зафиксирует регрессию если
        // Apple когда-нибудь изменит resolver behavior.
        XCTAssertNotNil(UTType(filenameExtension: "yaml"),
                        "UTType(filenameExtension: \"yaml\") должен резолвиться на test runtime")
        XCTAssertNotNil(UTType(filenameExtension: "yml"),
                        "UTType(filenameExtension: \"yml\") должен резолвиться на test runtime")
        // Sanity-check: `.json` — это canonical Apple UTType, должен быть identifier "public.json".
        XCTAssertEqual(UTType.json.identifier, "public.json")
    }
}
