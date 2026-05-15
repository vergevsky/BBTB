---
phase: 11-onboarding-ux-polish
plan: 05
subsystem: settings-feature
tags: [telem-02, diagnostics, log-export, share-link, ip-masking, app-group, swiftui]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: "AppGroupContainer.singBoxLogPath (extension пишет, main app читает); group.app.bbtb.shared"
  - phase: 11-onboarding-ux-polish (Plan 01)
    provides: "L10n.diagnosticsSection / diagnosticsExportLog / diagnosticsShareLog / diagnosticsLast24h / diagnosticsPreparing / diagnosticsNoLogsTitle / diagnosticsNoLogsMessage / diagnosticsVersionFormat + L10n.actionOK"
provides:
  - "DiagnosticsExporter.swift — public async prepareLog() + internal maskIPv4 + internal anonymousDeviceID"
  - "DiagnosticsSection.swift — SwiftUI компонент с тремя состояниями (idle/preparing/ready) + alert на пустой лог"
  - "DiagnosticsExporterTests.swift — 6 unit-тестов (maskIPv4 ×4, anonymousDeviceID ×1, prepareLog nil-path ×1)"
  - "SettingsFeature → PacketTunnelKit dependency wire-up в Package.swift"
  - "Интеграция DiagnosticsSection в SettingsView (после Advanced row, в существующем Form)"
affects: [11-06, 11-07]  # последующие планы Phase 11 могут переиспользовать паттерн ShareLink

# Tech tracking
tech-stack:
  added: []  # никаких новых SPM-пакетов; PacketTunnelKit уже в проекте
  patterns:
    - "ShareLink(item: URL) — cross-platform iOS 16+/macOS 13+ как замена UIActivityViewController + NSSharingServicePicker (наш минимум iOS 18/macOS 15 покрывает с запасом)"
    - "Stateless enum-namespace для file-I/O сервисов (DiagnosticsExporter) — параллельно AppGroupContainer паттерну"
    - "internal-параметр прокидывается в public async API для unit-test inject (prepareLog(logPath:)) — public wrapper без аргументов использует production константу"
    - "ISO8601 timestamp в имени temp файла с `:` → `-` substitution для Files.app-friendliness"
    - "Anonymous device-id через UUID + UserDefaults (не identifierForVendor) — privacy-respecting, per-install не cross-correlatable"
    - "IPv4 masking через NSRegularExpression backref `$1xxx` — IPv6 представления остаются нетронутыми (D-12 covers IPv4 only)"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift — 133 строки, public enum + 1 public async API + 2 internal helpers"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsSection.swift — 96 строк, public View + 2 private string helpers, 3-state UI (idle/preparing/ready) + alert"
    - "BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/DiagnosticsExporterTests.swift — 70 строк, 6 тестов с UserDefaults setUp/tearDown"
  modified:
    - "BBTB/Packages/AppFeatures/Package.swift — добавлен `.package(path: \"../PacketTunnelKit\")` + target dep `PacketTunnelKit` для SettingsFeature"
    - "BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift — внутри Form добавлен `DiagnosticsSection()` после Advanced Section (без outer Section wrapper)"

key-decisions:
  - "DiagnosticsExporter как **enum-namespace stateless**, не actor — все операции либо async file-IO (без shared state), либо pure transforms (maskIPv4, anonymousDeviceID), либо thread-safe UserDefaults. Actor дал бы overhead без выгоды."
  - "**testable inject через перегрузку**: public `prepareLog()` ⟶ internal `prepareLog(logPath:)`. Без default-параметра в public API — чтобы view-layer не имел способа подсунуть нестандартный путь. Тест передаёт несуществующий `/tmp/bbtb-test-nonexistent-<UUID>.log` и проверяет nil-return."
  - "**ShareLink вместо UIActivityViewController/NSSharingServicePicker** — CONTEXT D-11 говорит «UIActivity (iOS) / NSSharing (macOS)», но <specifics> рекомендует ShareLink как нативный cross-platform wrapper над тем же Share Sheet. Минимум iOS 18 / macOS 15 полностью покрывает ShareLink iOS 16+ / macOS 13+. Суть D-11 («без backend, system Share Sheet») сохраняется."
  - "**DiagnosticsSection напрямую в Form, без outer Section wrapper** — компонент возвращает Section на верхнем уровне body. Вложение Section-in-Section в SwiftUI Form даёт визуально неожиданные эффекты (двойные header/inset). Комментарий в SettingsView явно фиксирует это правило для будущих maintainers."
  - "**`identifierForVendor` отвергнут** — на iOS он сбрасывается при удалении всех app разработчика (Anti-Pattern в RESEARCH). UUID + UserDefaults стабильнее в пределах одной установки, а D-11 spec намеренно не требует cross-install correlation (per-install достаточно для одного debug-чата с разработчиком)."
  - "**2 MB tail вместо «последних 24 часов»** — sing-box.log не имеет structured timestamps, фильтрация по времени требует парсинга строк. Pragmatic proxy: 2 MB ≈ несколько часов активной сессии (Open Question 2 RESOLVED). Time-based filter — Phase 12+ задача если появится потребность."

patterns-established:
  - "ShareLink-based export Sheet через подготовленный URL (паттерн переиспользуем для будущих TELEM-* features в Phase 12+)"
  - "Three-state SwiftUI section (idle button → preparing spinner → ready ShareLink) — обобщается на любой async-prepare → share flow"
  - "Async-friendly stateless file exporter (enum, не actor) — применимо к другим экспортным сервисам"

# Metrics
metrics:
  start: "2026-05-15T15:35:00Z"
  end: "2026-05-15T15:42:39Z"
  duration: "~8 минут (auto-mode, без UAT)"
  completed: "2026-05-15"
  tasks_completed: 2
  files_created: 3
  files_modified: 2
  tests_added: 6
  tests_total_passing: 190
---

# Phase 11 Plan 05: TELEM-02 Diagnostics Log Export — Summary

**One-liner:** Реализован TELEM-02 — кнопка «Подготовить лог» в Settings → async сбор sing-box.log из App Group → 2 MB tail + IPv4 masking + metadata header → ShareLink на системный Share Sheet (iOS + macOS native, без backend).

## What was built

Phase 11 Plan 05 закрывает требование **TELEM-02** (последний оставшийся TELEM-* в Phase 11 — остальные TELEM-03..09 отложены на Phase 12+):

1. **`DiagnosticsExporter`** (`SettingsFeature/DiagnosticsExporter.swift`, 133 строки):
   - Public async `prepareLog() async -> URL?` — high-level API для UI.
   - Internal `prepareLog(logPath:) async -> URL?` — testable inject.
   - Internal `maskIPv4(_:) -> String` — regex замена последнего октета на `xxx`.
   - Internal `anonymousDeviceID() -> String` — lazily-generated UUID, persisted в UserDefaults `app.bbtb.anonymousDeviceID`.
   - Imports: `Foundation`, `os` (Logger), `PacketTunnelKit` (для `AppGroupContainer.singBoxLogPath`).

2. **`DiagnosticsSection`** (`SettingsFeature/DiagnosticsSection.swift`, 96 строк):
   - Public View с three-state UI:
     - **Idle** — Button «Подготовить лог» с `doc.text.magnifyingglass` SF symbol → запускает Task.
     - **Preparing** — HStack { ProgressView spinner + «Подготовка лога...» text }.
     - **Ready** — `ShareLink(item: url)` с `square.and.arrow.up` SF symbol → системный Share Sheet.
   - `.alert` «Нет данных» при `prepareLog() → nil` (Pitfall 8: пользователь ещё не подключался к VPN).
   - Footer: `L10n.diagnosticsLast24h` + `L10n.diagnosticsVersionFormat(appVer, osVer)`.
   - A11Y identifiers: `BBTB.Settings.DiagnosticsExportButton`, `BBTB.Settings.DiagnosticsShareLink`.

3. **`DiagnosticsExporterTests`** (`SettingsFeatureTests/DiagnosticsExporterTests.swift`, 70 строк, 6 тестов):
   - `test_maskIPv4_replacesLastOctet` — `192.168.1.42` → `192.168.1.xxx`.
   - `test_maskIPv4_preservesNonIP` — `user@host:8080` без изменений.
   - `test_maskIPv4_multipleInOneString` — 2 IP в одной строке оба маскируются.
   - `test_maskIPv4_handlesIPv6Untouched` — `::1`, `fe80::1` без изменений (D-12 covers IPv4 only).
   - `test_anonymousDeviceID_stable` — 2 вызова возвращают одинаковую строку + UUID format check (36 chars, 4 hyphens).
   - `test_prepareLog_returnsNilWhenLogAbsent` — async, передаёт несуществующий `/tmp/bbtb-test-nonexistent-<UUID>.log`, ожидает nil.

4. **`Package.swift`**:
   - Добавлен `.package(path: "../PacketTunnelKit")` в `dependencies` array.
   - В `SettingsFeature` target dependencies добавлен `"PacketTunnelKit"` (нужен для `AppGroupContainer.singBoxLogPath`).
   - Сейчас в Package.swift `PacketTunnelKit` встречается 4 раза (package dep + SettingsFeature target dep + 2 комментария — verification ≥3 PASS).

5. **`SettingsView.swift`**:
   - Внутри Form после `Advanced` Section добавлен `DiagnosticsSection()` напрямую — БЕЗ outer Section wrapper (компонент сам возвращает Section, double-wrap создаёт визуальные артефакты).

## Verification results

**swift build (AppFeatures):** GREEN (✓ 51.5s cold, ~2.3s incremental после Task 5.2).

**swift test (AppFeatures, full suite):** **190/190 PASS** (включая 6 новых DiagnosticsExporterTests + все pre-existing tests — никаких regression'ов).

**iOS xcodebuild:**
- `cd BBTB && tuist generate --no-open` → ✔ Success.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' -quiet build` → **BUILD SUCCEEDED**.

**macOS xcodebuild:**
- Без code-signing: BUILD FAILED с error «BBTB-macOS has entitlements that require signing with a development certificate» — пре-существующий infrastructure gap (memory `phase12_distribution_creds_prerequisite`: Distribution cert + profiles запланированы как пред-требование Phase 12 TestFlight).
- С `CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED** — функциональная компиляция кода и линковка прошли, проблема только в signing certificates (не в коде Phase 11).

**Sentinel grep'ы:**
- `grep -c "PacketTunnelKit" Package.swift` = **4** (≥3 OK).
- `grep -c sentinel DiagnosticsExporter.swift` = **16** (≥5 OK).
- `grep -c sentinel DiagnosticsSection.swift` = **11** (≥5 OK).
- `grep -c "DiagnosticsSection()" SettingsView.swift` = **1** (OK).
- `wc -l DiagnosticsExporter.swift` = **133** (≥90 OK).
- `wc -l DiagnosticsExporterTests.swift` = **70** (≥60 OK).
- `wc -l DiagnosticsSection.swift` = **96** (≥50 OK).
- `grep -c "UIActivityViewController\|NSSharingServicePicker" DiagnosticsExporter.swift` = **0** (OK — нет UI кода в service layer).

## Deviations from Plan

**Незначительные — все согласованы с plan instructions:**

1. **ISO8601 timestamp в имени файла** — добавлено `.replacingOccurrences(of: ":", with: "-")` для Files.app-friendly имени (`:` в FAT-derived filesystems проблематично). Plan не уточнял, но Files.app и macOS Finder корректно показывают `bbtb-log-2026-05-15T15-42-39Z.txt`. Это не deviation в смысле rules 1-4 — это нормализация side-effect.

2. **Тест IPv6** — реализован «optional» 6-й тест (`test_maskIPv4_handlesIPv6Untouched`), который plan указал как «optional, опустить если parser сложен». Тест простой (2 assertEqual), поэтому добавлен — даёт regression guard на случай если кто-то расширит regex и сломает IPv6.

3. **macOS code-signing** — pre-existing infrastructure issue, не вызван этим планом. Documented в acceptance criteria fallback.

**Auto-fixed issues:** Нет (Rule 1/2/3 ничего не сработало — plan описание было полным и точным).

## Authentication gates

Нет. План полностью автономный, никаких auth-gates не возникало.

## Known Stubs

Нет.

## Threat Flags

Нет новых трактов поверх `<threat_model>` плана (T-11-05-01..07 покрыты как описано).

## Self-Check: PASSED

**Files exist:**
- ✓ `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift`
- ✓ `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsSection.swift`
- ✓ `BBTB/Packages/AppFeatures/Tests/SettingsFeatureTests/DiagnosticsExporterTests.swift`
- ✓ `BBTB/Packages/AppFeatures/Package.swift` (modified)
- ✓ `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` (modified)

**Commits exist:**
- ✓ `bbf6033` — `feat(11-05): add DiagnosticsExporter for TELEM-02 log export` (Task 5.1).
- ✓ `c7f8d65` — `feat(11-05): add DiagnosticsSection UI + integrate into SettingsView` (Task 5.2).

**Build & tests:**
- ✓ `swift build` — green.
- ✓ `swift test` — 190/190 PASS.
- ✓ iOS `xcodebuild` — BUILD SUCCEEDED.
- ✓ macOS `xcodebuild` — BUILD SUCCEEDED with CODE_SIGNING_ALLOWED=NO (pre-existing infra gap).

## Manual UAT (Wave 5 closure)

Этот план не запускает manual UAT — UAT отложен на Wave 5 phase closure:

1. **Happy-path:** Connect to VPN → generate активность → Settings → Диагностика → tap «Подготовить лог» → Share Sheet opens → save to Files → проверить content: header (App/OS/ID), masked IPs (last octet = `xxx`), disclaimer.
2. **Empty-log path:** Fresh install (или после удалить App Group) → tap «Подготовить лог» → alert «Нет данных» с OK.
3. **iOS + macOS parity:** Share Sheet на обеих платформах открывает корректные actions (Mail/Messages/AirDrop на iOS; Mail/AirDrop/Notes на macOS).

---

*Phase: 11-onboarding-ux-polish*
*Plan: 05 (Wave 3)*
*Executor: Claude Opus 4.7 (1M context)*
*Date: 2026-05-15*
