---
phase: 06d-performance-audit
plan: 02a
subsystem: instrumentation
tags: [wave0-gaps, periphery, signposts, baseline-templates, atomic-commits, instrumentation-only]
dependency_graph:
  requires:
    - Wave 06D-01 (research / multi-AI audit synthesis skeleton)
  provides:
    - PerfSignposter enum (sibling к TunnelLogger)
    - 5 OSSignposter span injection sites (Cold iOS + Cold macOS + ConnectTap + PreConnectProbe + ProvisionProfile + LibboxStart)
    - 6 baseline markdown templates
    - Periphery 3.7.4 tooling
    - ASSUMED-claim verification log (A1/A2/A6/A7/A8 + Open Q #3 + template count)
    - Canonical build commands для Phase 6d
  affects:
    - Wave 06D-02b (synthesis) — input Periphery scan
    - Wave 06D-02c (pre-fix Instruments baseline) — naïve template filling
tech_stack:
  added:
    - Periphery 3.7.4 (GitHub Releases direct install)
    - os.signpost (OSSignposter API, iOS 15+ / macOS 12+)
  patterns:
    - PerfSignposter enum sibling pattern (4 subsystems × performance category)
    - Single-injection-point in BaseSingBoxTunnel для cross-platform LibboxStart span
key_files:
  created:
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift
    - .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md
    - .planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md
    - .planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
    - .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/screenshots/.gitkeep
  modified:
    - BBTB/App/iOSApp/BBTB_iOSApp.swift (+13 lines — ColdLaunch span)
    - BBTB/App/macOSApp/BBTB_macOSApp.swift (+13 lines — ColdLaunch span)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (+30 lines — ConnectTap/PreConnectProbe/ProvisionProfile spans)
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift (+25 lines — LibboxStart span)
    - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift (+5 lines doc-comment marker)
    - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift (+5 lines doc-comment marker)
    - .gitignore (+4 lines — *.trace + traces-local/)
decisions:
  - "D-1 Periphery installed direct from GitHub Releases (homebrew tap stuck on 2.21.2 — published 3.7.4 не доступен через tap)."
  - "D-2 LibboxStart span injected в BaseSingBoxTunnel (single point covers both iOS + macOS extensions) вместо двух override'ов в empty shells."
  - "D-3 Scope-aware adaptation плана: TunnelController.connect() instrumented вместо несуществующего performToggleImpl (план писался под устаревший Phase 6b API)."
  - "D-4 Canonical build commands updated: -workspace (не -project) для iOS scheme; CODE_SIGNING_ALLOWED=NO для macOS на dev-машине без Developer ID."
metrics:
  duration_minutes: 75
  completed_date: 2026-05-14
  commits: 3
  tests_passing: 133
  files_created: 11
  files_modified: 7
---

# Phase 6d Wave 06D-02a Summary

## Что было сделано

Wave 06D-02a закрыла **Wave 0 gaps** — infrastructure prep для Wave 06D-02c (pre-fix Instruments baseline). Три атомарных коммита (per checker WARNING fix):

1. **Commit 1 `7ffb398`** — tooling install. Periphery 3.7.4 (direct GitHub Releases, homebrew tap отстаёт на 2.x), jq 1.7.1, ripgrep 14.1.1, Tuist 4.192.3 verified. Mini-scan через `periphery scan --project BBTB.xcworkspace --schemes BBTB` прошёл — обнаружил 30+ unused-code warnings (вход для Wave 02b synthesis). Regression gate D-08 зелёный.
2. **Commit 2 `64368c6`** — instrumentation. `PerfSignposter.swift` создан как sibling enum к `TunnelLogger` (4 subsystems × `performance` category). Пять OSSignposter spans внедрены:
   - `ColdLaunch` в `BBTB_iOSApp.init` + `BBTB_macOSApp.init` (закрываются в root view `onAppear`).
   - `ConnectTap` (outer) + `PreConnectProbe` (nested, обёртывает XPC `loadAllFromPreferences`) в `TunnelController.connect()`.
   - `ProvisionProfile` в `TunnelController.applyCurrentStateToCachedManager()`.
   - `LibboxStart` в `BaseSingBoxTunnel.startTunnel` — единственная точка, покрывает обе платформы. `PacketTunnelProvider`-shells (iOS + macOS) пусты — добавлены только doc-comment маркеры `LibboxStart` для verify-grep и документации.

   D-09 invariants preserved: `handleStatusChange` НЕ тронут, observer queue остаётся `nil`, никаких ReconnectStateMachine/NetworkReachability/Relay introductions. Regression gate D-08 зелёный.

3. **Commit 3 _(this)_** — scaffolding. 6 пустых baseline markdown templates (cold iOS + cold macOS + connect iOS + energy iOS + allocations iOS host + allocations iOS extension) + `.gitkeep` для screenshots/. `.gitignore` обновлён (`*.trace` + `traces-local/`). `06D-02a-PREFLIGHT.md` расширен с полной ASSUMED-claim verification. `06D-02a-WAVE0-VERIFY.md` фиксирует 3-commit cadence + D-09 grep audit. Regression gate D-08 зелёный.

## Отклонения от плана (deviations)

### Rule 1 — Bug fixes (план ссылается на устаревший API)

1. **План: `TunnelController.performToggleImpl` — этого метода нет** в актуальном коде (это устаревшее имя из Phase 6b до на Phase 6c refactor). Текущий API: `connect()` и `disconnect()` — отдельные методы, без объединяющего toggle.
   **Fix:** ConnectTap outer span внедрён в `TunnelController.connect()` (правильный entry point для connect hot path). Disconnect не инструментирован — не нужен для Phase 6d focus (cold-launch + connect-tap baselines).

2. **План: «PreConnectProbe» nested span обёртывает probe call» — explicit probe call в `connect()` отсутствует.** Probe в плане был частью устаревшего API.
   **Fix:** `PreConnectProbe` span внедрён вокруг XPC `loadAllFromPreferences()` — это functionally **является pre-connect probe** (проверка наличия профиля перед `startVPNTunnel`). Семантически совпадает с intent плана.

3. **План: LibboxStart в `PacketTunnelProvider.swift` (iOS + macOS).** Эти файлы — пустые subclass shells; вся логика в `BaseSingBoxTunnel` (parent class).
   **Fix:** `LibboxStart` span внедрён в `BaseSingBoxTunnel.startTunnel` (one point of instrumentation covers both platforms). В iOS + macOS shells добавлен doc-comment маркер `LibboxStart` (для verify-grep + документации, что инструментация находится в base class). Это idiomatic решение — избегает дублирования.

### Rule 1 — Tool API delta (план писался под Periphery 2.x)

4. **План: `periphery scan --workspace BBTB.xcworkspace --targets BBTB --retain-public --report-exclude '**/Tests/*.swift'`.** Periphery 3.x использует `--project` (single argument для workspace или xcodeproj) + `--schemes` (без `--targets` для scheme-driven indexing).
   **Fix:** Actual command — `periphery scan --project BBTB.xcworkspace --schemes BBTB --retain-public --report-exclude '**/Tests/*.swift' --exclude-tests --disable-update-check`. Zафиксировано в PREFLIGHT.md §2 для использования в Wave 02b.

5. **План: brew install peripheryapp/periphery/periphery.** Homebrew tap отстаёт на 2.21.2; 3.7.4 не доступен через стандартный brew.
   **Fix:** Direct install через GitHub Releases (`https://github.com/peripheryapp/periphery/releases/download/3.7.4/periphery-3.7.4.zip`) + bash wrapper в `/opt/homebrew/bin/periphery` с правильным `DYLD_LIBRARY_PATH` для `libIndexStore.dylib`. Quarantine attribute снят. После публикации tap-update на 3.x можно вернуться к стандартному `brew install`.

### Rule 1 — Build command delta

6. **План: `xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB ...`.** iOS scheme требует SPM resolution через workspace (BBTB.xcodeproj напрямую падает на unresolved packages).
   **Fix:** `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB ...`. Аналогично для macOS scheme.

7. **План: `xcodebuild ... -scheme BBTB-macOS -destination 'platform=macOS' build`.** macOS scheme требует code-signing на чистой dev-машине без активного Developer ID Application cert.
   **Fix:** добавлены `CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`. Build verifies компиляцию (regression gate цели), не deploy.

Все 7 deviations — **Rule 1 (auto-fix bug / API delta)**. Никаких архитектурных изменений; никаких behavioral effects. Документированы в PREFLIGHT.md + WAVE0-VERIFY.md + здесь.

## Known pre-existing findings (NOT introduced)

- **`ConfigImporter.swift:179` — `#Predicate { $0.subscriptionID == subOptID ... }` где `subOptID: UUID?`.** Совпадает с MEMORY anti-pattern «#Predicate с UUID? тихо возвращает empty массивы» (feedback_swiftdata_uuid_predicate.md). **Carry-over из Phase 3+** — не введено инструментацией Commit 2. Деферрено в Wave 02b synthesis backlog. Необходимо обсудить fix в next wave: либо fetch-all + Swift filter, либо guard на `subOptID != nil` перед формированием predicate.

## Self-Check

Будет добавлен после file/commit verification ниже.
