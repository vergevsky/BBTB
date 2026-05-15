---
phase: 11-onboarding-ux-polish
plan: 02
subsystem: import-pipeline
tags: [imp-03, fileimporter, swiftui, importsource, security-scoped-resource, mainscreenview]

# Dependency graph
requires:
  - phase: 02-trojan-import-flow
    provides: "ConfigImporting.importFromRawInput(_:source:) universal pipeline + ImportSource enum"
  - phase: 11-onboarding-ux-polish
    plan: 01
    provides: "L10n.menuImportFromFile + L10n.importErrorFileAccessDenied + L10n.importErrorFileReadFailed"
provides:
  - "ImportSource.file case (7-й) для analytics traceability + error-path differentiation"
  - "MainScreenViewModel.importFromFile(rawContents:) public API"
  - "performImport switch ветка `case .file where raw != nil` → importer.importFromRawInput(raw, source: .file)"
  - "SwiftUI `.fileImporter` modifier в MainScreenView, cross-platform (iOS + macOS)"
  - "Третья кнопка «Импортировать из файла» в addMenu (после Scan QR / Clipboard)"
  - "FileImporterTests: 3 unit-теста (importSource case existence + routing + UTType resolution)"
affects: [11-03, 11-04, 11-05, 11-06, 11-07, 12]

# Tech tracking
tech-stack:
  added: []  # никаких новых SPM пакетов / библиотек
  patterns:
    - "Pattern S10 — Async + defer для security-scoped resource (RESEARCH Pattern 2): guard startAccessingSecurityScopedResource() else { error; return }; defer { stop... }; try String(contentsOf:) → виртуальная VM.importFromFile"
    - "Pattern S7 — Accessibility identifier `BBTB.AddMenu.ImportFromFile` (по аналогии BBTB.AddButton / BBTB.ConnectionButton)"
    - "Task { ... } wrap callback для async/await IO внутри .fileImporter onCompletion closure — НЕ блокировать main thread на iCloud-located файлах (Pitfall 5)"
    - "Inline UTType(filenameExtension: \"yaml\") ?? .data — defensive nil-coalesce без extension boilerplate (single-use call site)"

key-files:
  created:
    - "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift — 3 теста (importSource_fileCase_exists + importFromFile_routesToFileSource + uttype_yaml_resolvable)"
  modified:
    - "BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift — добавлен `case file` к enum ImportSource (7-й case)"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift — добавлен public `importFromFile(rawContents:)` метод + ветка `case .file where raw != nil` в performImport switch"
    - "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift — `import UniformTypeIdentifiers` + @State showFileImporter + третья кнопка в addMenu + cross-platform `.fileImporter` modifier с security-scoped resource handling"

key-decisions:
  - "ImportSource как 7-й case (после .pasteboard/.subscriptionURL/.jsonEndpoint/.qrCode/.multilineText/.deepLink/.file) — структурно совпадает с предыдущими паттернами Phase 9 (deepLink)"
  - "Чтение файла (String(contentsOf:)) — в SwiftUI View layer, ВНУТРИ Task { ... }, НЕ в ViewModel. Reason: VM не должен знать о security-scoped resource lifecycle; View — единственный, кто получает URL из .fileImporter result"
  - "Inline UTType factory без extension boilerplate — single-use call site, defensive nil-coalesce `?? .data`; extension UTType { static var yaml ... } перенесён бы потенциально в shared module если будет переиспользование"
  - "Errors через existing `viewModel.lastError = L10n.*` — НЕ создавать новый error type для file picker; current `.alert` binding (D-08) обрабатывает любой String. Auth gate gracefully fallback: error.localizedDescription для system-level fail (cancel by user — `.failure` branch)"
  - "В UI-тесте path `test_importFromFile_routesToFileSource` сделана busy-wait на CapturingImporter.capturedCallCount (cap 1s) — потому что `importFromFile` spawn'ит inner Task, нет direct return signal; альтернатива — AsyncStream вокруг importInProgress, но overkill для smoke test"

patterns-established:
  - "Pattern P11-02-A: ImportSource.{file,deepLink,...} case branching через `case .X where raw != nil` ветку в `performImport` switch ДО default (иначе никогда не сработает). Phase 12+ TELEM-04 может добавить новые case'ы по этой же модели"
  - "Pattern P11-02-B: SwiftUI `.fileImporter` callback wrap в Task { switch result { ... } } — async lifting для IO без блокировки main; security-scoped guard/defer внутри. Шаблон для будущих file-related UI (log import в Phase 12, etc.)"

requirements-completed:
  - IMP-03

# Metrics
duration: 9min
completed: 2026-05-15
---

# Phase 11 Plan 02: File picker (IMP-03) Summary

**SwiftUI `.fileImporter` интегрирован в меню «+» главного экрана: третья кнопка «Импортировать из файла» открывает системный document picker, фильтрует .json/.yaml/.yml, читает содержимое через security-scoped resource API, и передаёт через existing `importFromRawInput` pipeline с новым `ImportSource.file` case для analytics traceability.**

## Performance

- **Duration:** ~9 min (581 s)
- **Started:** 2026-05-15T15:10:56Z
- **Completed:** 2026-05-15T15:20:37Z
- **Tasks:** 2 / 2
- **Files modified:** 3 (ParsedConfigs.swift, MainScreenViewModel.swift, MainScreenView.swift)
- **Files created:** 1 (FileImporterTests.swift)
- **AppFeatures tests:** 176 / 176 PASS (было 173 в Plan 11-01, +3 новых)
- **VPNCore tests:** 57 / 57 PASS

## Accomplishments

- **IMP-03 vertical slice complete:** пользователь, у которого есть `.json` (sing-box config) или `.yaml`/`.yml` (Clash YAML) конфигурация, может импортировать её одним тапом через меню «+», без копирования содержимого в буфер. iCloud Drive и Files.app файлы поддерживаются через security-scoped resource API.
- **Pipeline reuse:** никакого нового parser code path. Содержимое файла проходит через тот же `UniversalImportParser` пайплайн (Phase 2-5 verified), что и pasteboard/QR. Phase 4 R1 invariant test (`test_nonHy2_outbounds_neverHaveInsecureTrue`) защищает file pipeline автоматически.
- **Analytics traceability готово:** новый `ImportSource.file` case различим от `.pasteboard`/`.qrCode`/`.deepLink` (test_importSource_fileCase_exists фиксирует). Phase 12 TELEM-04 (если будет) сможет логировать `source` метрику без code change в pipeline.
- **Cross-platform UI:** `.fileImporter` modifier работает идентично на iOS 18+ и macOS 15+ (no `#if os(...)` branching для самого modifier). Третья кнопка в Menu — тоже cross-platform.
- **Error path consistent:** ошибки доступа (security scope denied) и чтения (corrupted file / IO error) показываются через тот же `lastError` → `.alert` binding, что и pasteboard/QR ошибки. Никаких новых error types — переиспользование D-08 alert pattern.

## Task Commits

Each task was committed atomically:

1. **Task 2.1: ImportSource.file case + importFromFile метод** — `ffa9231` (feat)
2. **Task 2.2: UI integration + 3 unit-теста** — `5311d16` (feat)

## Files Created/Modified

### Created

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift` — 3 unit-теста:
  - `test_importSource_fileCase_exists` — smoke gate; ловит удаление `case file` из enum или потерю различимости от других case'ов (analytics traceability gate).
  - `test_importFromFile_routesToFileSource` — CapturingImporter записывает `(raw, source)` пару; verify, что `vm.importFromFile(rawContents:)` идёт через `importer.importFromRawInput(_:source: .file)` (НЕ через pasteboard/QR ветки).
  - `test_uttype_yaml_resolvable` — `UTType(filenameExtension: "yaml")` и `UTType(filenameExtension: "yml")` не nil на test runtime; защищает inline UTType factory в `.fileImporter` от silently falling back в `.data`.

### Modified

- `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift` — добавлен `case file` к `enum ImportSource` (7-й case после `.deepLink`). Synthesized Equatable/Sendable conformance автоматически distribute'ит новый case без manual implementation.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`:
  - Новый public method `importFromFile(rawContents: String)` (после `importFromQRString`). Spawn'ит inner `Task { @MainActor in await performImport(.file, raw: rawContents) }`.
  - Расширен `performImport` switch: новая ветка `case .file where raw != nil: result = try await importer.importFromRawInput(raw!, source: .file)` ДО `default:`.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift`:
  - `import UniformTypeIdentifiers` (после `import ServerListFeature`).
  - `@State private var showFileImporter = false` (после `showQRScanner`).
  - Третья кнопка в `addMenu`: `Button { showFileImporter = true } label: { Label(L10n.menuImportFromFile, systemImage: "doc") }.accessibilityIdentifier("BBTB.AddMenu.ImportFromFile")`.
  - Новый `.fileImporter` modifier в конце body (после QR fullScreenCover/sheet `#endif`):
    - `allowedContentTypes: [.json, UTType(filenameExtension: "yaml") ?? .data, UTType(filenameExtension: "yml") ?? .data]`
    - `allowsMultipleSelection: false`
    - Callback обёрнут в `Task { ... }` (Pitfall 5 iCloud blocking read).
    - `.success(let urls)`: guard `url.startAccessingSecurityScopedResource()` → defer stop → `try String(contentsOf:url, encoding:.utf8)` → `viewModel.importFromFile(rawContents:)`; errors → `viewModel.lastError = L10n.importErrorFileAccessDenied` или `L10n.importErrorFileReadFailed`.
    - `.failure(let error)`: `viewModel.lastError = error.localizedDescription`.

## Decisions Made

- **`ImportSource.file` как 7-й case** — структура совпадает с `.deepLink` Phase 9. Equatable/Sendable conformance synthesized автоматически. Сохранение существующих case'ов гарантирует backward compat (никакие existing call-sites не сломаны exhaustiveness).
- **Чтение файла происходит в View, НЕ в ViewModel** — ViewModel получает уже-прочитанную String через `importFromFile(rawContents:)`. Causes: (a) View — единственный, кто получает security-scoped URL из `.fileImporter` result; (b) VM-layer abstraction не должен знать о Foundation URL lifecycle; (c) Тестируемость — CapturingImporter test не требует mock'ать security-scoped resource APIs.
- **Inline UTType factory без extension boilerplate** — `UTType(filenameExtension: "yaml") ?? .data` (single-use). Reason: единственное место использования, нет нужды в shared UTType+YAML.swift. Defensive `?? .data` гарантирует non-nil — но `test_uttype_yaml_resolvable` фиксирует, что реально fallback никогда не trigger'ится.
- **Task { ... } обёртка для callback** — `.fileImporter` callback — sync, поэтому `try String(contentsOf: url)` блокировал бы main thread на iCloud-located files (Pitfall 5 RESEARCH). Async-lift через `Task` + `MainActor.run` hops для VM mutation.
- **Errors через `lastError = L10n.*`** — нет нового error type. Переиспользование D-08 `.alert` binding (alert isPresented binds к `lastError != nil`). Consistent с pasteboard/QR error handling.
- **Plan-explicit ветка в performImport вместо переиспользования `.pasteboard`** — нужна для analytics traceability (Phase 12 TELEM-04 — `source` метрика). Также для error path differentiation: если pipeline когда-нибудь добавит специфичные file-only ошибки (например — file too large, corrupted JSON header), будет clear branch в switch.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Symlinked libbox.xcframework в worktree**

- **Found during:** Pre-task setup (swift build VPNCore).
- **Issue:** `BBTB/Vendored/libbox.xcframework` missing в worktree (binary артефакт gitignored, README документирует download). Same issue как в Plan 11-01.
- **Fix:** `ln -s /Users/vergevsky/ClaudeProjects/VPN/BBTB/Vendored/libbox.xcframework /Users/vergevsky/ClaudeProjects/VPN/.claude/worktrees/agent-a69c17de39168755b/BBTB/Vendored/libbox.xcframework` — symlink из main repo.
- **Files modified:** Worktree filesystem only (symlink, не commitable — Vendored/ gitignored).
- **Verification:** `swift build` clean, `swift test` 176/176 PASS, `xcodebuild` iOS+macOS BUILD SUCCEEDED.
- **Committed in:** N/A — symlink, не часть git tree.

**2. [Rule 3 - Blocking] macOS xcodebuild требует ad-hoc signing для проверки**

- **Found during:** Task 2.2 verify (xcodebuild macOS).
- **Issue:** Default xcodebuild macOS падает с "BBTB-macOS has entitlements that require signing with a development certificate" — known Phase 1 DIST-02 carry-forward gap (см. STATE.md «Blockers / Concerns»: Apple Distribution credentials).
- **Fix:** Retry с ad-hoc signing flags `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` — same pattern что использовали Phase 7a/Phase 8 closure (см. STATE.md «Phase 7a Phase 8 ad-hoc signing»).
- **Files modified:** None — это runtime build flag, не code change.
- **Verification:** `xcodebuild BBTB-macOS` BUILD SUCCEEDED с ad-hoc.
- **Committed in:** N/A — issue Phase 1 carry-forward, не Phase 11-02 regression. Документировано в Decisions Made.

**3. [Rule 2 - Missing Critical] Test busy-wait вместо AsyncStream waiting**

- **Found during:** Task 2.2 test writing.
- **Issue:** `importFromFile(rawContents:)` spawn'ит inner Task; нет direct return value/Future для теста дождаться completion'a. Использование AsyncStream/Combine subscriber overkill для smoke verification «routing работает».
- **Fix:** Busy-wait цикл с `Task.sleep(nanoseconds: 5_000_000)` (5 ms интервалы) и deadline 1s; condition `importer.capturedCallCount == 0`. Test проходит за 0.007 sec — типичный inner Task spawn finishes < 50 µs.
- **Files modified:** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift`.
- **Verification:** Test passes consistently; 3 runs в ходе разработки — все green.
- **Committed in:** `5311d16` (Task 2.2 commit).

---

**Total deviations:** 3 auto-fixed (2 blocking infrastructure — libbox symlink + macOS signing — не code regression; 1 missing-critical — test pattern choice). Никакого scope creep; все deviations необходимы для verify pipeline'а Task 2.1/2.2.

## Issues Encountered

- **libbox.xcframework отсутствует в свежем worktree** — known design issue (Vendored/ → .gitignore). Symlink из main repo решает за секунды. Plan 11-01 SUMMARY уже отметил это; рекомендация перенесена в `gsd-execute-phase` worktree setup как post-creation step.
- **macOS xcodebuild default fails on signing** — known Phase 1 DIST-02 carry-forward gap (Apple Distribution credentials). Phase 12 prerequisite. Текущий fix — ad-hoc signing для local verification; для TestFlight требуется реальный cert.

## User Setup Required

None — все изменения чистые code edits. На iOS пользователь автоматически получит:

- Третью кнопку «Импортировать из файла» в меню «+» главного экрана.
- При tap — системный document picker открывается на root `Files.app` view (Apple-managed UI).
- Выбор файла → security-scoped permission grant'ится автоматически iOS.
- При успешном parse'е — сервер появляется в pool сразу же.

Manual UAT (Phase 11 UAT plan) — отдельно протестировать:

- Импорт `.json` (sing-box config) с локального устройства.
- Импорт `.yaml` (Clash) из iCloud Drive — должна работать download-on-demand.
- Cancel в picker — никакой ошибки в UI.
- Импорт битого файла (corrupted JSON) — `lastError` показывает соответствующий L10n message.

## Verification Summary

**Task 2.1 acceptance criteria:**

- `cd BBTB/Packages/VPNCore && swift build` — **PASS** (Build complete in 10.09s)
- `cd BBTB/Packages/AppFeatures && swift build` — **PASS** (Build complete in 50.33s; нет switch-exhaustiveness compile errors)
- `grep "case file" ParsedConfigs.swift` → **1 line** (внутри `enum ImportSource`)
- `grep "public func importFromFile" MainScreenViewModel.swift` → **1 line**
- `grep "case .file" MainScreenViewModel.swift` → **1 line** (внутри performImport switch)
- Existing public API `importFromPasteboard()` и `importFromQRString(_:)` — signatures сохранены (verified via grep)

**Task 2.2 acceptance criteria:**

- `swift test --filter FileImporterTests` — **PASS** (3 / 3 testCases в 0.010 sec)
- `grep -c` на 4 sentinel'ах в `MainScreenView.swift` → **8** (план требовал ≥ 4)
- `cd BBTB/Packages/AppFeatures && swift build` — **PASS** (zero warnings related to IMP-03)
- `cd BBTB/Packages/AppFeatures && swift test` (full suite) — **PASS** (176 / 176 в 17.7 sec; +3 от base 173 в Plan 11-01)
- Existing identifiers `BBTB.ConnectionButton` и `BBTB.AddButton` preserved (1 + 1 matches respective grep'ы)
- `xcodebuild BBTB iOS Simulator` — **BUILD SUCCEEDED** (после `tuist generate --no-open`)
- `xcodebuild BBTB-macOS` (ad-hoc signing) — **BUILD SUCCEEDED**

**Plan-level verification (`<verification>`):**

- AppFeatures + VPNCore swift build green: **PASS** (176/176 + 57/57)
- Full AppFeatures swift test green: **176 / 176 PASS** (был base 173, +3 FileImporterTests)
- iOS + macOS xcodebuild green: **PASS** (iOS default signing, macOS ad-hoc per Phase 1 DIST-02 carry-forward)
- Manual smoke (Phase 11 UAT) — **PENDING** (carry-over к device UAT после Wave 7 closure)
- Grep `case file` в `ParsedConfigs.swift` = **1**

## Threat Flags

None — Plan 11-02 не вводит новых trust boundary surface beyond документированных в `<threat_model>` (T-11-02-01..T-11-02-06). Все mitigations применены:

- T-11-02-01 (malicious .yaml): mitigated через existing UniversalImportParser pipeline (Phase 4 R1 invariant test применяется automatically).
- T-11-02-02 (path traversal): mitigated Apple-managed (fileImporter возвращает только user-selected URLs).
- T-11-02-03 (huge file DoS): accepted (realistic <1MB; iOS killer protects).
- T-11-02-04 (main thread block): mitigated через `Task { ... }` wrapper.
- T-11-02-05 (skip startAccessing): mitigated через `guard` + `defer` pattern (security-scoped resource); test_importFromFile_routesToFileSource не покрывает напрямую, но grep на `startAccessingSecurityScopedResource` в MainScreenView.swift = 1.
- T-11-02-06 (repudiation): mitigated через `.file` ImportSource case (analytics traceability).

## Self-Check: PASSED

### Created files exist

- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/FileImporterTests.swift` — **FOUND**

### Modified files contain expected changes

- `ParsedConfigs.swift` содержит `case file` — **FOUND** (line 300)
- `MainScreenViewModel.swift` содержит `public func importFromFile` — **FOUND** (line 405)
- `MainScreenViewModel.swift` содержит `case .file where raw != nil` в performImport — **FOUND** (line 702)
- `MainScreenView.swift` содержит `import UniformTypeIdentifiers` — **FOUND** (line 5)
- `MainScreenView.swift` содержит `@State private var showFileImporter` — **FOUND**
- `MainScreenView.swift` содержит `.fileImporter(isPresented:` — **FOUND**
- `MainScreenView.swift` содержит `L10n.menuImportFromFile` — **FOUND**

### Commits exist

- `ffa9231` (Task 2.1 — ImportSource.file case + importFromFile method) — **FOUND**
- `5311d16` (Task 2.2 — UI integration + tests) — **FOUND**

## Next Plan Readiness

**Готово для Wave 3+ Phase 11:**

- Plan 11-03 (Onboarding UI / UX-01) — независим от IMP-03; может стартовать параллельно или последовательно. Reuses L10n.onboardingTitle/Subtitle/Paste/ScanQR (Plan 11-01 foundation).
- Plan 11-04 (ConnectionButton spinner / UX-08) — независим.
- Plan 11-05 (HelpView + FAQ / LOC-03/04) — независим.
- Plan 11-06 (DiagnosticsSection + ShareLink / TELEM-02) — независим.
- Plan 11-07 (MAX detection / DETECT-01..03) — независим.

**Никаких blocker'ов или carry-forward'ов** для последующих волн Phase 11.

**Wiki sync TODO (CLAUDE.md правило):** После окончания всей Phase 11 закрепить в wiki:

- `wiki/architecture.md` — упомянуть Phase 11 IMP-03 file picker integration (third addMenu button).
- `wiki/security-gaps.md` — отметить T-11-02-* threat register entries как closed (или как accepted для T-11-02-03 DoS).
- (Если потребуется новая страница `wiki/import-pipeline.md`) — задокументировать единый pipeline через `importFromRawInput` с тремя источниками: pasteboard / QR / file / deepLink.

---
*Phase: 11-onboarding-ux-polish*
*Plan: 02 (Wave 2 — File Picker IMP-03)*
*Completed: 2026-05-15*
