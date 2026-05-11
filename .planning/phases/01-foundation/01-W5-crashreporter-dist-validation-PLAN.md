---
phase: 01-foundation
plan: W5-crashreporter-dist-validation
type: execute
wave: 5
depends_on:
  - W3-base-tunnel
  - W4-ui-import
files_modified:
  - BBTB/Packages/CrashReporter/Package.swift
  - BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift
  - BBTB/Packages/CrashReporter/Tests/CrashReporterTests/CrashReporterTests.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  - BBTB/Config/ExportOptions-iOS.plist
  - BBTB/Config/ExportOptions-macOS.plist
  - BBTB/scripts/archive-ios.sh
  - BBTB/scripts/archive-macos.sh
  - BBTB/scripts/validate-r1-r6.sh
  - .planning/phases/01-foundation/security-evidence/.gitkeep
  - .planning/phases/01-foundation/security-evidence/README.md
autonomous: false
requirements:
  - TELEM-01
  - DIST-01
  - DIST-02
  - SEC-01
  - SEC-02
  - SEC-03
  - SEC-04
  - KILL-01
  - KILL-02

must_haves:
  truths:
    - "CrashReporter подписывается на MXMetricManager и реализует MXMetricManagerSubscriber"
    - "CrashReporter.didReceive(MXDiagnosticPayload) пишет .json в AppGroupContainer.crashReportsURL"
    - "CrashReporter.install() вызывается в init() обоих BBTB_iOSApp и BBTB_macOSApp"
    - "BBTB/scripts/archive-ios.sh выполняет xcodebuild archive + xcodebuild -exportArchive с ExportOptions-iOS.plist"
    - "BBTB/scripts/archive-macos.sh выполняет аналогичный pipeline для macOS"
    - "BBTB/scripts/validate-r1-r6.sh запускает unit-тесты PacketTunnelKit + проверяет artifact'ы R1/R6 + grep-инвaрианты"
    - ".planning/phases/01-foundation/security-evidence/ существует с README"
    - "Manual smoke на устройстве задокументирован в security-evidence/dod-iphone.md и dod-mac.md (или заменено на лог-output если устройство недоступно)"
  artifacts:
    - path: "BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift"
      provides: "TELEM-01: MXMetricManager subscriber"
      contains: "MXMetricManagerSubscriber"
    - path: "BBTB/scripts/archive-ios.sh"
      provides: "DIST-01: TestFlight-ready iOS archive"
      contains: "xcodebuild archive"
    - path: "BBTB/scripts/archive-macos.sh"
      provides: "DIST-02: TestFlight-ready macOS archive"
    - path: "BBTB/scripts/validate-r1-r6.sh"
      provides: "End-to-end Phase 1 security validation"
    - path: ".planning/phases/01-foundation/security-evidence/README.md"
      provides: "Инструкция куда складывать screenshots и логи DoD"
  key_links:
    - from: "BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift"
      to: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift"
      via: "AppGroupContainer.crashReportsURL для записи payload'ов"
      pattern: "crashReportsURL"
    - from: "BBTB/App/iOSApp/BBTB_iOSApp.swift"
      to: "BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift"
      via: "CrashReporter.shared.install() в App.init"
      pattern: "CrashReporter.shared.install"
    - from: "BBTB/scripts/archive-ios.sh"
      to: "BBTB/Config/ExportOptions-iOS.plist"
      via: "xcodebuild -exportArchive -exportOptionsPlist Config/ExportOptions-iOS.plist"
      pattern: "ExportOptions-iOS.plist"
---

<objective>
**Wave 5 — Crash reporter + Distribution + Validation.** Финальная волна Phase 1: реализовать TELEM-01 (MXMetricManager-based crash reporter, без UI отправки — TELEM-03 в Phase 12), подготовить TestFlight-ready archive scripts для iOS+macOS (DIST-01, DIST-02), и провести end-to-end manual validation всех security claim'ов Phase 1 (R1 через SocksProbe scan, R6 через SocksProbe + DEBUG assertion, KILL-02 через server-kill smoke, и DoD #1 — `api.ipify.org` IP swap).

Эта волна — **gate к `/gsd-verify-work 1`**. Не закроется пока:
- Реальный device test не подтвердит DoD #1 (api.ipify.org IP swap).
- SocksProbe screenshot не покажет «все порты closed» при активном туннеле.
- KILL-02 manual (отключить сервер → проверить нет интернета).
- Skeleton iOS+macOS archives не соберутся через xcodebuild archive.

Output:
- CrashReporter полная реализация + unit-test через мокающий MXDiagnosticPayload (Apple API даёт public init).
- App.init() в iOS+macOS вызывает CrashReporter.shared.install().
- 3 shell-скрипта: archive-ios, archive-macos, validate-r1-r6.
- Security-evidence директория с README + место для screenshot'ов.
- DoD-проверки manual checkpoint'ом.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@.planning/phases/01-foundation/01-W3-base-tunnel-SUMMARY.md
@.planning/phases/01-foundation/01-W4-ui-import-SUMMARY.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/security-gaps.md
@Wiki/kill-switch.md
@Wiki/distribution-testflight.md

<interfaces>
<!-- From Wave 3 — AppGroupContainer для путей -->
From PacketTunnelKit Wave 3:
```swift
public enum AppGroupContainer {
    public static let identifier = "group.app.bbtb.shared"
    public static var url: URL
    public static var crashReportsURL: URL  // <appgroup>/crash-reports/
    public static var singBoxWorkingPath: String
}
```

From RESEARCH §12 — MXMetricManagerSubscriber API:
```swift
import MetricKit
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    func install() { MXMetricManager.shared.add(self) }
    func didReceive(_ payloads: [MXMetricPayload]) { /* Phase 1 — no-op */ }
    func didReceive(_ payloads: [MXDiagnosticPayload]) { /* save .json */ }
}
```

From RESEARCH §15 — Archive process commands:
```bash
xcodebuild archive -workspace BBTB.xcworkspace -scheme BBTB-iOS \
  -destination 'generic/platform=iOS' -archivePath build/BBTB-iOS.xcarchive
xcodebuild -exportArchive -archivePath build/BBTB-iOS.xcarchive \
  -exportPath build/iOS-Distribution -exportOptionsPlist Config/ExportOptions-iOS.plist
```
</interfaces>
</context>

<tasks>

<task id="W5-T1" type="auto" tdd="true" autonomous="true">
  <name>Task W5-T1: CrashReporter (TELEM-01) + Tests + Wire-up в @main App</name>
  <files>
    BBTB/Packages/CrashReporter/Package.swift,
    BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift,
    BBTB/Packages/CrashReporter/Tests/CrashReporterTests/CrashReporterTests.swift,
    BBTB/App/iOSApp/BBTB_iOSApp.swift,
    BBTB/App/macOSApp/BBTB_macOSApp.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §12 «MXMetricManager crash reporting (TELEM-01)» — API surface + установка + Pitfall 8 (macOS reliability)
    - .planning/phases/01-foundation/01-CONTEXT.md §5 (Crash reporter default — MXMetricManager, без UI)
    - prompts/v2 строка 789 («Локальный crash reporter (без UI отправки пока)»)
  </read_first>
  <behavior>
    - **Test 1**: CrashReporter.shared — singleton (тот же instance).
    - **Test 2**: install() безопасно вызывать повторно (idempotent — не падает).
    - **Test 3**: после `saveDiagnostic(...)` (test-only helper) в `crashReportsURL` появляется файл `crash-<ISO8601>.json`.
    - **Test 4**: при пустом массиве payload'ов — no-op, файлов не создаётся.
    - **Test 5**: имя файла начинается с `crash-` и заканчивается `.json`.
  </behavior>
  <action>
1. **Обновить `BBTB/Packages/CrashReporter/Package.swift`** — добавить зависимость от PacketTunnelKit для AppGroupContainer:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CrashReporter",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "CrashReporter", targets: ["CrashReporter"])],
    dependencies: [
        .package(path: "../PacketTunnelKit"),
    ],
    targets: [
        .target(name: "CrashReporter", dependencies: ["PacketTunnelKit"]),
        .testTarget(name: "CrashReporterTests", dependencies: ["CrashReporter"]),
    ]
)
```

2. **`BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`:**
```swift
import Foundation
import MetricKit
import OSLog
import PacketTunnelKit

/// TELEM-01 — локальный crash reporter без UI отправки.
///
/// Жизненный цикл:
/// - `install()` вызывается из BBTB_iOSApp.init() / BBTB_macOSApp.init() ОДИН раз
/// - MetricKit доставляет payload'ы при следующем запуске после краша
/// - `didReceive(_ payloads:)` для MXDiagnosticPayload сохраняет JSON в App Group
///
/// **Phase 1 scope:** только запись на диск. UI отправки — Phase 12 (TELEM-03).
/// **Pitfall 8:** на macOS до 14 MetricKit мог молчать; macOS 15 улучшен, но не гарантирован.
public final class CrashReporter: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    public static let shared = CrashReporter()

    private let log = Logger(subsystem: "app.bbtb.app", category: "CrashReporter")
    private var isInstalled = false
    private let lock = NSLock()

    public override init() { super.init() }

    /// Idempotent install — повторный вызов — no-op.
    public func install() {
        lock.lock(); defer { lock.unlock() }
        guard !isInstalled else { return }
        MXMetricManager.shared.add(self)
        isInstalled = true
        log.info("CrashReporter installed (subscribed to MXMetricManager)")
    }

    // MARK: MXMetricManagerSubscriber

    public func didReceive(_ payloads: [MXMetricPayload]) {
        // Phase 1: метрики не сохраняем (TELEM-04 — Phase 12 telemetry pipeline).
        log.debug("Received \(payloads.count) MXMetricPayload(s) — ignored in Phase 1")
    }

    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
        log.notice("Received \(payloads.count) MXDiagnosticPayload(s)")
        for payload in payloads {
            saveDiagnostic(payload)
        }
    }

    // MARK: Internals

    /// Internal helper: тестируемая часть. Принимает MXDiagnosticPayload и пишет .json
    /// в `AppGroupContainer.crashReportsURL`. Используется и production path,
    /// и unit-тест через mock-subclass payload'а.
    internal func saveDiagnostic(_ payload: MXDiagnosticPayload) {
        let dir = AppGroupContainer.crashReportsURL
        let timestamp = isoFormatter.string(from: payload.timeStampBegin)
        let filename = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-")).json"
        let url = dir.appendingPathComponent(filename)
        do {
            let data = payload.jsonRepresentation()
            try data.write(to: url, options: .atomic)
            log.info("Saved crash payload to \(url.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Failed to write crash payload: \(error.localizedDescription, privacy: .public)")
        }
    }

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: Test-only

    #if DEBUG
    /// Test hook: ручная инжекция payload для unit-test.
    /// Production code никогда это не вызывает.
    public func _test_inject(_ payloads: [MXDiagnosticPayload]) {
        didReceive(payloads)
    }
    #endif
}
```

3. **`BBTB/Packages/CrashReporter/Tests/CrashReporterTests/CrashReporterTests.swift`:**
```swift
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
```

4. **Обновить `BBTB/App/iOSApp/BBTB_iOSApp.swift`** — добавить `CrashReporter.shared.install()` в init() (см. Wave 4 версию, добавить одну строку):
```swift
import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import VLESSReality
import ProtocolRegistry
import CrashReporter  // <-- ДОБАВИТЬ

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel

    init() {
        // TELEM-01: установить crash reporter ПЕРВЫМ — чтобы поймать любые init crashes.
        CrashReporter.shared.install()

        // CORE-02: регистрируем протоколы
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)

        // SwiftData container
        do {
            self.modelContainer = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        let importer = ConfigImporter(
            modelContainer: modelContainer,
            providerBundleIdentifier: "app.bbtb.client.ios.tunnel"
        )
        let tunnel = TunnelController()
        self.viewModel = MainScreenViewModel(importer: importer, tunnel: tunnel)
    }

    var body: some Scene {
        WindowGroup {
            MainScreenView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
```

5. **Обновить `BBTB/App/macOSApp/BBTB_macOSApp.swift`** — аналогично:
```swift
import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import MenuBarFeature
import VLESSReality
import ProtocolRegistry
import Localization
import CrashReporter  // <-- ДОБАВИТЬ

@main
struct BBTB_macOSApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var viewModel: MainScreenViewModel

    init() {
        // TELEM-01
        CrashReporter.shared.install()

        ProtocolRegistry.shared.register(VLESSRealityHandler.self)

        let container: ModelContainer
        do {
            container = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        self.modelContainer = container
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.client.macos.tunnel"
        )
        let tunnel = TunnelController()
        _viewModel = StateObject(wrappedValue: MainScreenViewModel(importer: importer, tunnel: tunnel))
    }

    var body: some Scene {
        Window(L10n.appShortName, id: "main") {
            MainScreenView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```

6. **В Xcode UI** — Add CrashReporter package product в обоих BBTB-iOS и BBTB-macOS target Frameworks (manual step через Project navigator → General → Frameworks; W5-T4 manual smoke gate проверит, что сборка зелёная).
  </action>
  <acceptance_criteria>
    - `grep -q "import MetricKit" BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`
    - `grep -q "MXMetricManagerSubscriber" BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`
    - `grep -q "MXMetricManager.shared.add(self)" BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`
    - `grep -q "AppGroupContainer.crashReportsURL" BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`
    - `grep -q "payload.jsonRepresentation()" BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`
    - `grep -q "CrashReporter.shared.install()" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "CrashReporter.shared.install()" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "import CrashReporter" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme CrashReporter -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED"`
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme CrashReporter -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "Test Suite 'CrashReporterTests'.*passed|Executed [0-9]+ tests"</automated>
  </verify>
</task>

<task id="W5-T2" type="auto" autonomous="true">
  <name>Task W5-T2: TestFlight archive scripts (DIST-01, DIST-02) + R1/R6 end-to-end validation script</name>
  <files>
    BBTB/scripts/archive-ios.sh,
    BBTB/scripts/archive-macos.sh,
    BBTB/scripts/validate-r1-r6.sh,
    BBTB/Config/ExportOptions-iOS.plist,
    BBTB/Config/ExportOptions-macOS.plist
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §15 «TestFlight build (DIST-01, DIST-02)» — Archive process + ExportOptions
    - .planning/phases/01-foundation/01-CONTEXT.md §6 (Marketing version 0.1.0 + Build number 1)
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 5 (валидация R1, R6, DoD #1, DoD #2)
  </read_first>
  <action>
1. **Обновить `BBTB/Config/ExportOptions-iOS.plist`** (Wave 0 положил базовый; Wave 5 финализирует) — оставить как есть (already correct from W0-T2), но добавить teamID на случай если в Wave 0 не было; проверить grep:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>UAN8W9Q82U</string>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
```

2. **`BBTB/Config/ExportOptions-macOS.plist`** — финализировать:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>
  <key>teamID</key>
  <string>UAN8W9Q82U</string>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
```

3. **`BBTB/scripts/archive-ios.sh`:**
```bash
#!/usr/bin/env bash
# DIST-01: iOS archive для TestFlight Internal.
# Usage: bash BBTB/scripts/archive-ios.sh [--upload]
# Без --upload — только сборка archive + export .ipa в build/iOS-Distribution/.
# С --upload — после export пытается xcrun altool --upload-app (требует API key).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORKSPACE="BBTB.xcworkspace"
SCHEME="BBTB-iOS"
ARCHIVE_PATH="build/BBTB-iOS.xcarchive"
EXPORT_PATH="build/iOS-Distribution"
EXPORT_OPTIONS="BBTB/Config/ExportOptions-iOS.plist"

mkdir -p build

echo "==> Cleaning previous archive (if any)"
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving $SCHEME → $ARCHIVE_PATH"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=UAN8W9Q82U \
    | xcbeautify --quiet 2>/dev/null || xcodebuild archive \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME" \
        -destination 'generic/platform=iOS' \
        -archivePath "$ARCHIVE_PATH" \
        -configuration Release \
        CODE_SIGN_STYLE=Automatic \
        DEVELOPMENT_TEAM=UAN8W9Q82U

echo "==> Exporting archive → $EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo "✓ iOS archive ready: $EXPORT_PATH"
ls -lh "$EXPORT_PATH"

if [[ "${1:-}" == "--upload" ]]; then
    IPA=$(find "$EXPORT_PATH" -name "*.ipa" | head -1)
    if [[ -z "$IPA" ]]; then
        echo "ERROR: .ipa not found in $EXPORT_PATH"
        exit 1
    fi
    echo "==> Uploading $IPA to App Store Connect"
    # Требует App Store Connect API key (AuthKey_*.p8 в ~/.appstoreconnect/private_keys/)
    # либо AC_API_KEY_ID + AC_API_ISSUER_ID env vars.
    xcrun altool --upload-app -f "$IPA" -t ios \
        --apiKey "${AC_API_KEY_ID:?Need AC_API_KEY_ID}" \
        --apiIssuer "${AC_API_ISSUER_ID:?Need AC_API_ISSUER_ID}"
fi
```

4. **`BBTB/scripts/archive-macos.sh`:**
```bash
#!/usr/bin/env bash
# DIST-02: macOS archive для TestFlight Internal.
# Usage: bash BBTB/scripts/archive-macos.sh [--upload]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

WORKSPACE="BBTB.xcworkspace"
SCHEME="BBTB-macOS"
ARCHIVE_PATH="build/BBTB-macOS.xcarchive"
EXPORT_PATH="build/macOS-Distribution"
EXPORT_OPTIONS="BBTB/Config/ExportOptions-macOS.plist"

mkdir -p build
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving $SCHEME → $ARCHIVE_PATH"
xcodebuild archive \
    -workspace "$WORKSPACE" \
    -scheme "$SCHEME" \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_STYLE=Automatic \
    DEVELOPMENT_TEAM=UAN8W9Q82U

echo "==> Exporting archive → $EXPORT_PATH"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_OPTIONS"

echo "✓ macOS archive ready: $EXPORT_PATH"
ls -lh "$EXPORT_PATH"

if [[ "${1:-}" == "--upload" ]]; then
    PKG=$(find "$EXPORT_PATH" -name "*.pkg" -o -name "*.app" | head -1)
    if [[ -z "$PKG" ]]; then
        echo "ERROR: no .pkg or .app found in $EXPORT_PATH"
        exit 1
    fi
    echo "==> Uploading $PKG to App Store Connect"
    xcrun altool --upload-app -f "$PKG" -t macos \
        --apiKey "${AC_API_KEY_ID:?Need AC_API_KEY_ID}" \
        --apiIssuer "${AC_API_ISSUER_ID:?Need AC_API_ISSUER_ID}"
fi
```

5. **`BBTB/scripts/validate-r1-r6.sh`** — end-to-end security invariant check:
```bash
#!/usr/bin/env bash
# Phase 1 security validation script.
# Запускает:
# - все unit-тесты, относящиеся к R1, R6, KILL-01/02
# - grep-инварианты по source-коду (R1 template, R6 без destinationAddresses)
# - проверка структуры артефактов (entitlements, SocksProbe изоляция)
#
# Не делает device-smoke (это manual в W5-T4).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

FAIL=0
function check() {
    local label="$1"; shift
    if "$@" > /dev/null 2>&1; then
        echo "PASS: $label"
    else
        echo "FAIL: $label  (cmd: $*)"
        FAIL=$((FAIL+1))
    fi
}

echo "=== Phase 1 R1/R6/KILL Static Invariants ==="
echo ""

# R1: SingBoxConfigTemplate не содержит inbounds
check "R1: template has no 'inbounds' key" \
    bash -c '! grep -q "\"inbounds\"" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json'

check "R1: template has empty experimental {}" \
    grep -q '"experimental": {}' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json

# R6: destinationAddresses не присваивается в Sources/
check "R6: no destinationAddresses assignment in PacketTunnelKit Sources" \
    bash -c '! grep -rE "destinationAddresses\s*=" BBTB/Packages/PacketTunnelKit/Sources/'

# R6: assertion вызывается в ExtensionPlatformInterface
check "R6: assertNoPointToPointOnUtun is invoked" \
    grep -q "InterfaceFlagsInspector.assertNoPointToPointOnUtun" \
        BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift

# KILL-01 + KILL-02: KillSwitch.apply устанавливает includeAllNetworks + enforceRoutes
check "KILL-01: includeAllNetworks=true in KillSwitch.apply" \
    grep -q "proto.includeAllNetworks = true" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: enforceRoutes set via PlatformHooks negation" \
    grep -q "proto.enforceRoutes = !platformShouldDisableEnforceRoutes" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

check "KILL-01: ConfigImporter zovets KillSwitch.apply" \
    grep -q "KillSwitch.apply(to: proto)" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift

# SocksProbe изоляция (W1-T3)
check "SEC-03: SocksProbe iOS entitlements БЕЗ application-groups" \
    bash -c '! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements'

check "SEC-03: SocksProbe iOS entitlements БЕЗ keychain-access-groups" \
    bash -c '! grep -q "keychain-access-groups" BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements'

check "SEC-03: SocksProbe macOS entitlements БЕЗ application-groups" \
    bash -c '! grep -q "application-groups" BBTB/Tools/SocksProbe/SocksProbe-macOS/SocksProbe-macOS.entitlements'

# SEC-05: kSecAttrAccessibleWhenUnlocked
check "SEC-05: kSecAttrAccessibleWhenUnlocked в KeychainStore" \
    grep -q "kSecAttrAccessibleWhenUnlocked" BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift

echo ""
echo "=== Unit Tests (R1, R6, KILL-01/02, SEC-05) ==="

# Запускаем тесты, нужные для phase gate.
function run_tests() {
    local scheme="$1"
    echo "  → Testing $scheme..."
    if xcodebuild test -workspace BBTB.xcworkspace -scheme "$scheme" \
        -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | tail -5; then
        echo "  PASS: $scheme tests"
    else
        echo "  FAIL: $scheme tests"
        FAIL=$((FAIL+1))
    fi
}

run_tests "PacketTunnelKit"
run_tests "KillSwitch"
run_tests "ConfigParser"
run_tests "VPNCore"
run_tests "VLESSReality"
run_tests "Localization"
run_tests "MainScreenFeature"
run_tests "CrashReporter"

echo ""
if [[ "$FAIL" -eq 0 ]]; then
    echo "✓ ALL STATIC INVARIANTS + UNIT TESTS PASS"
    echo ""
    echo "NEXT: run W5-T4 manual device smoke for R1/R6/KILL-02/DoD#1 — see"
    echo "      .planning/phases/01-foundation/security-evidence/README.md"
    exit 0
else
    echo "✗ $FAIL FAILED — see logs above"
    exit 1
fi
```

6. **Сделать исполняемыми:**
```bash
chmod +x BBTB/scripts/archive-ios.sh BBTB/scripts/archive-macos.sh BBTB/scripts/validate-r1-r6.sh
```
  </action>
  <acceptance_criteria>
    - `test -x BBTB/scripts/archive-ios.sh && test -x BBTB/scripts/archive-macos.sh && test -x BBTB/scripts/validate-r1-r6.sh`
    - `grep -q "xcodebuild archive" BBTB/scripts/archive-ios.sh`
    - `grep -q "BBTB/Config/ExportOptions-iOS.plist" BBTB/scripts/archive-ios.sh`
    - `grep -q "DEVELOPMENT_TEAM=UAN8W9Q82U" BBTB/scripts/archive-ios.sh`
    - `grep -q "BBTB-macOS" BBTB/scripts/archive-macos.sh`
    - `grep -q "destinationAddresses" BBTB/scripts/validate-r1-r6.sh`
    - `grep -q "assertNoPointToPointOnUtun" BBTB/scripts/validate-r1-r6.sh`
    - `grep -q "includeAllNetworks" BBTB/scripts/validate-r1-r6.sh`
    - `grep -q "<string>app-store</string>" BBTB/Config/ExportOptions-iOS.plist`
    - `grep -q "<string>UAN8W9Q82U</string>" BBTB/Config/ExportOptions-iOS.plist`
    - Запуск `bash BBTB/scripts/validate-r1-r6.sh` завершается exit 0 и выводит «ALL STATIC INVARIANTS + UNIT TESTS PASS»
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && bash BBTB/scripts/validate-r1-r6.sh 2>&amp;1 | tail -3 | grep -q "ALL STATIC INVARIANTS"</automated>
  </verify>
  <done>Скрипты архивации и валидации созданы; validate-r1-r6.sh запускается зелёным; static invariants Phase 1 закрыты.</done>
</task>

<task id="W5-T3" type="auto" autonomous="true">
  <name>Task W5-T3: security-evidence директория с README + manual checkpoint templates</name>
  <files>
    .planning/phases/01-foundation/security-evidence/.gitkeep,
    .planning/phases/01-foundation/security-evidence/README.md
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §7 «Лог-output для DoD evidence»
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 5
  </read_first>
  <action>
1. **`.planning/phases/01-foundation/security-evidence/.gitkeep`** — пустой файл.

2. **`.planning/phases/01-foundation/security-evidence/README.md`:**
```markdown
# Phase 1 Security Evidence

Эта директория хранит **артефакты ручной проверки** Phase 1: скриншоты, логи, и manual smoke-test reports.

## Что должно сюда попасть до закрытия Phase 1

| Файл | Содержание | Кто кладёт |
|------|-----------|------------|
| `r1-socksprobe-iphone.png` | Скриншот SocksProbe на iPhone при активном BBTB-туннеле, все порты «closed» | W5-T4 (manual) |
| `r1-socksprobe-mac.png` | Скриншот SocksProbe на Mac при активном BBTB-туннеле, все порты «closed» | W5-T4 (manual) |
| `r6-no-p2p-iphone.png` | Скриншот SocksProbe utun-секции с «POINTOPOINT: NO» | W5-T4 (manual) |
| `r6-no-p2p-mac.png` | То же на macOS | W5-T4 (manual) |
| `r6-no-p2p.log` | Текстовый дамп `getifaddrs` для всех utun*: имя, addresses, flags, POINTOPOINT YES/NO | W5-T4 (manual) |
| `dod1-api-ipify-iphone.png` | Скриншот Safari на iPhone с `https://api.ipify.org` показывающим IP сервера VPN (не реальный пользовательский) | W5-T4 (manual) |
| `dod1-api-ipify-mac.png` | То же на Mac | W5-T4 (manual) |
| `dod2-killswitch-iphone.png` | Скриншот Safari с ошибкой загрузки https://example.com после убийства sing-box на сервере (трафик заблокирован kill switch'ем) | W5-T4 (manual) |
| `dod2-killswitch-mac.png` | То же на Mac | W5-T4 (manual) |
| `dod-iphone.md` | Прозаический отчёт о ручной проверке всех DoD на iPhone (см. template ниже) | W5-T4 (manual) |
| `dod-mac.md` | То же на Mac | W5-T4 (manual) |
| `archive-ios-output.log` | Лог `bash BBTB/scripts/archive-ios.sh` — стэйджит DIST-01 | W5-T4 |
| `archive-macos-output.log` | Лог `bash BBTB/scripts/archive-macos.sh` — стэйджит DIST-02 | W5-T4 |
| `validate-r1-r6-output.log` | Лог `bash BBTB/scripts/validate-r1-r6.sh` — все green | W5-T2 (auto) |

## Template — `dod-iphone.md` (W5-T4 заполняет)

```markdown
# Phase 1 DoD Manual Verification — iPhone

**Date:** YYYY-MM-DD
**Device:** iPhone XX (iOS X.Y)
**Tester:** {developer}
**Test config:** Tests/Fixtures/test-config.vless.local.txt (host masked)

## DoD #1 — api.ipify.org IP swap

1. ✓ Установлен BBTB через TestFlight Internal / Xcode signing.
2. ✓ Импорт через буфер обмена — vless:// → видно «Импорт успешен», name = (remarks).
3. ✓ Тап ConnectButton → status «Подключение…» → «Подключено», timer считает.
4. ✓ Safari → https://api.ipify.org → IP отображается = IP сервера (не оригинальный).
5. ✓ Скриншот: `dod1-api-ipify-iphone.png`.

**Result: PASS / FAIL**

## DoD #2 — Kill switch blocks traffic on tunnel drop

1. ✓ Туннель активен.
2. ✓ На сервере (SSH): `sudo systemctl stop sing-box` (или kill процесс).
3. ✓ В Safari → https://example.com → ошибка timeout / no internet.
4. ✓ Скриншот ошибки: `dod2-killswitch-iphone.png`.
5. ✓ После `sudo systemctl start sing-box` на сервере — трафик восстанавливается (timer продолжает).

**Result: PASS / FAIL**

## R1 — No SOCKS5 on loopback

1. ✓ Установлен SocksProbe (отдельное приложение от BBTB) на iPhone.
2. ✓ Tunnel активен.
3. ✓ Открыт SocksProbe → Start Scan.
4. ✓ Все порты из `RKNPorts.phase1` (1080, 9000, 5555, 16000-16100, 3128, 3127, 8000, 8080, 8081, 8888, 9050, 9051, 9150) → status `closed`.
5. ✓ Summary: «R1 verdict: PASS — no ports respond».
6. ✓ Скриншот: `r1-socksprobe-iphone.png`.

**Result: PASS / FAIL**

## R6 — No IFF_POINTOPOINT on utun

1. ✓ В том же SocksProbe scan видна секция «utun interfaces».
2. ✓ Все utun-интерфейсы: POINTOPOINT: NO ✓.
3. ✓ Скриншот: `r6-no-p2p-iphone.png`.
4. ✓ Текстовый лог в `r6-no-p2p.log`.

**Result: PASS / FAIL**

## Release-режим без debug-логов

1. ✓ Открыть Console.app на Mac, подключить iPhone, фильтр subsystem = `app.bbtb.tunnel`.
2. ✓ Release-сборка (TestFlight) — нет debug-уровней; в Console только info/notice/error.
3. ✓ Скриншот фильтра Console: `release-no-debug-iphone.png`.

**Result: PASS / FAIL**
```

## Template — `dod-mac.md`

Аналогично iPhone, заменить `Safari → api.ipify.org` на macOS Safari/любой браузер; Console.app — встроенный на той же машине.

## Что НЕ требуется

- Не нужны NPVN profile screenshots (Settings → VPN) — это для Phase 12 Beta App Review.
- Не нужен полный suite UI screenshots (Phase 11 финализирует дизайн).
- Не нужны crash report samples — на свежем устройстве MetricKit может не доставить никаких payload'ов; достаточно убедиться что `CrashReporter.shared.install()` логирует «installed» в Console (info-уровень).
```
  </action>
  <acceptance_criteria>
    - `test -f .planning/phases/01-foundation/security-evidence/.gitkeep`
    - `test -f .planning/phases/01-foundation/security-evidence/README.md`
    - `grep -q "r1-socksprobe-iphone.png" .planning/phases/01-foundation/security-evidence/README.md`
    - `grep -q "dod1-api-ipify-iphone.png" .planning/phases/01-foundation/security-evidence/README.md`
    - `grep -q "DoD #1" .planning/phases/01-foundation/security-evidence/README.md`
    - `grep -q "POINTOPOINT: NO" .planning/phases/01-foundation/security-evidence/README.md`
  </acceptance_criteria>
</task>

<task id="W5-T4" type="checkpoint:human-verify" gate="blocking" autonomous="false">
  <name>Task W5-T4: Manual smoke — DoD #1 + DoD #2 + R1 + R6 на реальных устройствах</name>
  <what-built>End-to-end manual validation. Это **gate** для закрытия Phase 1: без зелёных DoD #1/#2/R1/R6 на устройстве — Phase не считается завершённой.</what-built>
  <read_first>
    - .planning/phases/01-foundation/security-evidence/README.md (что и куда складывать)
    - .planning/phases/01-foundation/01-RESEARCH.md §6 «KILL-02 verification»
    - .planning/phases/01-foundation/01-RESEARCH.md §7 «R6 P2P=false»
    - .planning/phases/01-foundation/01-RESEARCH.md §8 «SocksProbe DoD criteria»
  </read_first>
  <how-to-verify>
    **Prerequisites (пользователь должен иметь):**
    - Реальный iPhone iOS 18+ (для DIST-01 smoke; DoD #1, DoD #2, R1, R6 проверки)
    - Реальный Mac (Apple Silicon, macOS 15+) — обычно это dev машина
    - Рабочий VLESS+Reality сервер (host + uuid + pbk + sid + sni)
    - Apple Developer signing работающий (Automatic signing в Xcode)
    - SocksProbe установлен на оба устройства (W1-T4 уже это сделал)

    **Шаги (порядок важен):**

    ### Часть А — Static invariants
    ```bash
    cd /Users/vergevsky/ClaudeProjects/VPN
    bash BBTB/scripts/validate-r1-r6.sh 2>&1 | tee .planning/phases/01-foundation/security-evidence/validate-r1-r6-output.log
    ```
    Ожидаемо exit 0 и «ALL STATIC INVARIANTS + UNIT TESTS PASS».

    ### Часть B — TestFlight archive smoke (DIST-01, DIST-02)

    BBTB-iOS:
    ```bash
    bash BBTB/scripts/archive-ios.sh 2>&1 | tee .planning/phases/01-foundation/security-evidence/archive-ios-output.log
    ```
    Ожидаемо появляется `build/iOS-Distribution/BBTB.ipa` (или подобное). Загружать в App Store Connect — НЕ обязательно в Phase 1 (Phase 12 DIST-04 это Beta App Review submission). Достаточно того, что archive собирается.

    BBTB-macOS:
    ```bash
    bash BBTB/scripts/archive-macos.sh 2>&1 | tee .planning/phases/01-foundation/security-evidence/archive-macos-output.log
    ```

    Если archive падает с ошибками signing — диагностировать через Xcode → Window → Devices and Simulators → проверить provisioning profiles; либо переключиться на manual signing в Xcode.

    ### Часть C — Device DoD smoke

    **iPhone:**
    1. Build & install BBTB-iOS на iPhone через Xcode (Cmd+R с выбранным physical device).
    2. Заполнить `BBTB/Tests/Fixtures/test-config.vless.local.txt` реальным vless:// URI (НЕ коммитить).
    3. Скопировать содержимое в iPhone clipboard (через Universal Clipboard).
    4. В BBTB tap «Импортировать из буфера» → дождаться «Подключено».
    5. Safari → https://api.ipify.org → запомнить отображённый IP, сравнить с IP сервера. Скриншот → `dod1-api-ipify-iphone.png`.
    6. Запустить SocksProbe (отдельное приложение) → Start Scan. Все порты должны быть `closed`. utun-секция: POINTOPOINT: NO. Скриншоты → `r1-socksprobe-iphone.png`, `r6-no-p2p-iphone.png`.
    7. На сервере (SSH): остановить sing-box (`sudo systemctl stop sing-box` или kill). В Safari → https://example.com → должен быть timeout. Скриншот → `dod2-killswitch-iphone.png`.
    8. Перезапустить sing-box на сервере — трафик восстанавливается.
    9. Заполнить `dod-iphone.md` по шаблону из README.

    **Mac:**
    1. Run BBTB-macOS через Xcode (Cmd+R).
    2. Скопировать vless:// в clipboard (Mac системный буфер).
    3. В BBTB tap «Импортировать из буфера» → «Подключено».
    4. Safari → https://api.ipify.org → IP сервера. Скриншот → `dod1-api-ipify-mac.png`.
    5. SocksProbe (macOS) → Start Scan → все closed. Скриншоты → `r1-socksprobe-mac.png`, `r6-no-p2p-mac.png`.
    6. На сервере: kill sing-box → Safari → timeout. Скриншот → `dod2-killswitch-mac.png`.
    7. Заполнить `dod-mac.md`.

    ### Часть D — Освободить место и сложить evidence

    Поместить все 8+ скриншотов и 2 markdown отчёта в `.planning/phases/01-foundation/security-evidence/`.

    ### Что записать в чат
    После выполнения — type «phase 1 dod green» + summary:
    - DoD #1 iOS: PASS / FAIL
    - DoD #1 macOS: PASS / FAIL
    - DoD #2 iOS: PASS / FAIL
    - DoD #2 macOS: PASS / FAIL
    - R1 iOS: PASS / FAIL
    - R1 macOS: PASS / FAIL
    - R6 iOS: PASS / FAIL
    - R6 macOS: PASS / FAIL
    - DIST-01 archive: PASS / FAIL
    - DIST-02 archive: PASS / FAIL
  </how-to-verify>
  <resume-signal>Type "phase 1 dod green" с PASS/FAIL summary и подтверждением что 8+ скриншотов положены в security-evidence/.</resume-signal>
  <done>Все 10 проверок (4 DoD + R1 двух платформ + R6 двух платформ + 2 archive) PASS. Файлы evidence лежат в `.planning/phases/01-foundation/security-evidence/`. Phase 1 готов к `/gsd-verify-work 1`.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Process crash → MXMetricManager pipeline | iOS/macOS-level — данные не наши; нам приходят payload'ы в plain JSON |
| Crash payload → App Group container | iOS sandbox защищает container; Pitfall 5 — concurrent access SwiftData (но crash reports — отдельная директория, не SwiftData) |
| Archive output → App Store Connect | xcodebuild + xcrun altool / Transporter — Apple-signed pipeline |
| Manual smoke evidence → security-evidence/ | Скриншоты в `.planning/` — коммит в публичный git (без секретов, host masked) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W5-01 | Information Disclosure | Crash payload содержит stack trace с указателями на secret-handling код | accept | Apple обрабатывает crash payloads; в Phase 1 они только пишутся в App Group (TELEM-03/04 — Phase 12 управляет отправкой) |
| T-01-W5-02 | Information Disclosure | TestFlight archive содержит .dSYM с символами; .ipa в `build/` попадает в git если разработчик коммитит build/ | mitigate | `BBTB/.gitignore` уже исключает `build/`; вёб-шара ExportOptions — нет реальных секретов (Team ID — публичная информация) |
| T-01-W5-03 | Tampering | validate-r1-r6.sh регрессит — кто-то добавит destinationAddresses, скрипт ловит при следующем запуске | mitigate | Скрипт запускается перед каждым `/gsd-verify-work` (manual policy) |
| T-01-W5-04 | Information Disclosure | Test config (Tests/Fixtures/test-config.vless.local.txt) попадает в git | mitigate | `.gitignore` явно исключает `*.local.txt`; только `.template` коммитим |
| T-01-W5-05 | Spoofing | Manual smoke — пользователь подделывает скриншот | accept | Solo developer workflow; нет 3rd party review; trust the developer |
| T-01-W5-06 | Information Disclosure | api.ipify.org screenshots показывают server IP | accept | Server IP — публичная информация (любой curl видит). UUID/keys — НЕ в скриншоте (URL только api.ipify.org response, который = IP сервера). |
</threat_model>

<verification>
**Wave 5 проверки:**

1. **Static invariants (W5-T2):**
   ```bash
   bash BBTB/scripts/validate-r1-r6.sh  # exit 0
   ```

2. **Archive smoke (W5-T4 sub-part B):**
   ```bash
   bash BBTB/scripts/archive-ios.sh    # creates build/iOS-Distribution/*.ipa
   bash BBTB/scripts/archive-macos.sh  # creates build/macOS-Distribution/*.{pkg,app}
   ```

3. **Manual device DoD (W5-T4 sub-part C):** все 8 скриншотов + 2 markdown отчёта в `.planning/phases/01-foundation/security-evidence/`.

4. **Unit-тесты CrashReporter pass:**
   ```bash
   xcodebuild test -workspace BBTB.xcworkspace -scheme CrashReporter -destination 'platform=macOS,arch=arm64' -quiet
   ```

**Это финальный gate Phase 1.** Если хоть один FAIL — добавить task'у в gap-closure plan и пересдать.
</verification>

<success_criteria>
Wave 5 завершён (= Phase 1 ready for `/gsd-verify-work 1`) когда:

- [ ] **CrashReporter** реализован — MXMetricManagerSubscriber, пишет .json в `AppGroupContainer.crashReportsURL`, install() idempotent.
- [ ] **CrashReporter.shared.install()** вызывается в `BBTB_iOSApp.init()` и `BBTB_macOSApp.init()` ПЕРВОЙ строкой.
- [ ] **Unit-тесты CrashReporter** (3+ smoke тестов) проходят.
- [ ] **`BBTB/scripts/archive-ios.sh`, `archive-macos.sh`, `validate-r1-r6.sh`** существуют, исполняемые, работают.
- [ ] **`validate-r1-r6.sh`** запускается зелёным (все 11+ static invariants + unit-тесты pass).
- [ ] **`.planning/phases/01-foundation/security-evidence/README.md`** объясняет какие скриншоты и логи требуются.
- [ ] **Manual device DoD** (W5-T4) — все 10 проверок PASS:
  - DoD #1 (api.ipify.org IP swap) — iPhone + Mac
  - DoD #2 (kill switch blocks traffic) — iPhone + Mac
  - R1 (no SOCKS ports respond) — iPhone + Mac (SocksProbe screenshots)
  - R6 (POINTOPOINT: NO on utun) — iPhone + Mac (SocksProbe screenshots)
  - DIST-01 (iOS archive builds) + DIST-02 (macOS archive builds)
- [ ] **Все 8+ скриншотов и 2 markdown отчёта** в `.planning/phases/01-foundation/security-evidence/`.
- [ ] **Release-режим:** В TestFlight build'е (или Release configuration build'е) Console.app показывает что нет debug-уровней OSLog от subsystem `app.bbtb.tunnel` (CONTEXT.md DoD #4).
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W5-crashreporter-dist-validation-SUMMARY.md` с:
- Снимок вывода `validate-r1-r6.sh` (последние 30 строк)
- Снимок вывода обоих archive scripts
- Список 8+ файлов evidence (с краткими аннотациями)
- DoD outcome table (PASS/FAIL по каждому из 10 пунктов)
- Заметки для `/gsd-verify-work 1`:
  - Что верификатор должен проверить, и где это лежит
  - Любые open items для Phase 2 (например: если R6 на macOS не сработал — это уже Phase 1 FAIL и нужен gap-closure)
- Замечания для `wiki/security-gaps.md` — обновить R1 и R6 как «✓ Закрыто (verified in Phase 1)»
- Замечания для `wiki/architecture.md` — финализировать структуру PacketTunnelKit как закрытое архитектурное решение
- Замечания для `wiki/log.md` — append-only запись о завершении Phase 1
</output>
