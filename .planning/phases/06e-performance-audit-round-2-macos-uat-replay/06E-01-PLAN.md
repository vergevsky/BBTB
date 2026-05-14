---
phase: 06e
slug: performance-audit-round-2-macos-uat-replay
plan: 01
type: execute
wave: 1
mode: mvp
depends_on: []
autonomous: true
requirements: [QUAL-04]
findings_addressed: [M7, M8, M10, M11, L12, M6, M15]
tags: [scenephase-coalesce, swiftdata-idempotency, validatedat-guard, applyvpnstatus-guard, r10-defense-in-depth, atomic-medium]
files_modified:
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift
  - BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift

must_haves:
  truths:
    - "M7: scenePhase = .active при foreground re-entry запускает РОВНО ОДИН Task `Task { @MainActor in await viewModel.handleForegroundReentry() }`; внутри handleForegroundReentry() — sequential await трёх hooks (runIsSupportedUpgrade через Task.detached(priority: .background) per DEC-06d-01 → tunnelController?.handleForeground() → serverListViewModel?.silentForegroundRefresh())."
    - "M10: ServerListViewModel.loadFromStore() имеет 100мс debounce idempotency guard (loadInProgress + lastLoadAt) и confirmDeleteSubscription вызывает loadFromStore() ровно один раз в конце try/catch (не дважды — было 2 на cascade-delete path)."
    - "M8 + L12: BaseSingBoxTunnel.startTunnel skip-ает pre-expand validate когда providerConfiguration[\"configJSONValidatedAt\"] < 24ч; ConfigImporter записывает этот timestamp после собственного validate. POST-expand validate (R10 defense-in-depth) ОСТАЁТСЯ unconditional — grep -c 'SingBoxConfigLoader.validate' в BaseSingBoxTunnel.swift ≥ 2."
    - "M11: applyVPNStatus(.connecting / .reasserting) ветка начинается с explicit early-return guard `guard state != .connecting else { return }` перед существующим nested switch; outer-level lastAppliedVPNStatus dedupe guard (Phase 6d 9b38796) НЕ удалён."
    - "M6 и M15 — INVALIDATED (subsumed by Phase 6d 1467328 + 9b38796 и 55bde6c соответственно); НЕТ commit-а с code change; bookkeeping documented только в Wave 3 SUMMARY."
    - "Каждый из 4 atomic commits (M7 → M10 → M8 → M11) проходит per-commit regression gate: `swift test --package-path BBTB/Packages/AppFeatures` ≥ 133/133 + iOS xcodebuild + macOS xcodebuild SUCCEEDED."
    - "D-09 invariants preserved после каждого commit: forbidden symbols ≤ 7 (baseline 4), observer queue=.main = 0, #Predicate UUID? = 0, applyVPNStatus single authority = 1 function definition, ExternalVPNStopMarker .consume( callers = 0."
    - "DEC-06d-01 (cold-start defer Task.detached) + DEC-06d-02 (XPC ≤ 2 trips в loadAllFromPreferences) preserved через grep audit."
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift"
      provides: "NEW async method `handleForegroundReentry()` сразу после существующего `handleForeground()`"
      contains: "func handleForegroundReentry"
    - path: "BBTB/App/iOSApp/BBTB_iOSApp.swift"
      provides: "consolidated single-Task scenePhase handler"
      contains: "viewModel.handleForegroundReentry"
    - path: "BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift"
      provides: "loadFromStore идемпотентность (loadInProgress + lastLoadAt) + confirmDeleteSubscription single-call"
      contains: "loadInProgress"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      provides: "pre-expand validate guarded by configJSONValidatedAt timestamp; post-expand validate unchanged"
      contains: "configJSONValidatedAt"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      provides: "writes providerConfiguration[\"configJSONValidatedAt\"] = ISO8601 timestamp after successful pre-save validate"
      contains: "configJSONValidatedAt"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift"
      provides: "applyVPNStatus(.connecting) early-return guard within reactive switch"
      contains: "guard state != .connecting else { return }"
  key_links:
    - from: "BBTB/App/iOSApp/BBTB_iOSApp.swift"
      to: "MainScreenViewModel.handleForegroundReentry"
      via: "scenePhase .onChange handler — `Task { @MainActor in await viewModel.handleForegroundReentry() }`"
      pattern: "viewModel\\.handleForegroundReentry"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "providerConfiguration[\"configJSONValidatedAt\"]"
      via: "ISO8601 timestamp write after SingBoxConfigLoader.validate succeeds"
      pattern: "configJSONValidatedAt"
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift"
      to: "SingBoxConfigLoader.validate(json: expandedJSON)"
      via: "Post-expand R10 defense-in-depth re-validation — UNCHANGED, unconditional"
      pattern: "SingBoxConfigLoader\\.validate\\(json: expandedJSON\\)"
---

<objective>
Phase 6e — Wave 1: 4 атомарных MEDIUM fixes из 26 carved findings Phase 6d. Каждый MEDIUM — отдельный commit + per-commit regression gate (D-04 hybrid closure rigor). Порядок — escalating risk surface: M7 (lowest) → M10 → M8 (R10 critical) → M11 (D-09 applyVPNStatus authority).

**Purpose:** maximally clean baseline перед Phase 7 (Anti-DPI suite + WireGuard family). Карвированный backlog Phase 6d закрывается tactical cleanup-фазой; per-commit gate гарантирует точечную ловлю регрессий.

**Output:**
- 4 atomic commits (M7, M10, M8+L12, M11) в risk-ascending order
- 4 optional new test files (HandleForegroundReentryTests, LoadFromStoreIdempotencyTests, ValidatedAtGuardTests, ApplyVPNStatusGuardTests)
- 4 regression gate passes (AppFeatures + PacketTunnelKit + iOS + macOS)
- M6/M15 bookkeeping rows (NO code change — subsumed by Phase 6d) для Wave 3 SUMMARY

**Scope NOT in this plan:** 20 LOW findings + 3 trivial imports → Wave 2 (06E-02-PLAN.md). Closure documentation → Wave 3 (06E-03-PLAN.md).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-VALIDATION.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md
@wiki/performance-baseline.md
@wiki/security-gaps.md
@wiki/auto-reconnect.md

<interfaces>
<!-- Key contracts the executor needs. Extracted from existing files. -->

From `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:521-560` (canonical handleForeground analog для M7):
- `public func handleForeground() async` — already coalesces loadAllFromPreferences + ManagerSelector filter + applyVPNStatus в один XPC trip.
- M7 introduces sibling: `public func handleForegroundReentry() async` — sequentially awaits 3 hooks.

From `MainScreenViewModel.swift:410-487` (applyVPNStatus reactive driver — D-09 single authority):
- Signature: `internal func applyVPNStatus(_ status: NEVPNStatus, connectedDate: Date? = nil)`
- Outer guard (line 414, Phase 6d post-fix `9b38796`): `guard lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate else { return }`
- Switch cases: `.connecting, .reasserting` / `.connected` / `.disconnecting` / `.disconnected` / `.invalid` / `@unknown default`
- M11 modifies ONLY the `.connecting, .reasserting` branch (lines ~420-436).

From `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift:156-251` (validate gates):
- Line 156-164: pre-expand validate (M8 target — wrap в guard).
- Line 240-251: post-expand validate (R10 defense-in-depth — MUST stay unchanged, unconditional).
- providerConfiguration accessed via `protocolConfig.providerConfiguration` (NETunnelProviderProtocol).

From `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (provisionTunnelProfile path):
- ConfigImporter sets `providerConfiguration["configJSON"]` after own SingBoxConfigLoader.validate succeeds.
- M8 adds: `providerConfiguration["configJSONValidatedAt"] = ISO8601DateFormatter().string(from: Date())` в том же scope.

From `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift`:
- `loadFromStore()` body at line 328-335 (private async); 6 call sites at lines 181, 224, 257, 282, 312, 323.
- `confirmDeleteSubscription(_:)` lines 286-323 — has 2 `await loadFromStore()` calls (early-exit branch line 312 + final line 323) → M10 collapses to single tail-call.
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: M7 — Consolidate scenePhase = .active foreground hooks into single handleForegroundReentry()</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    BBTB/App/iOSApp/BBTB_iOSApp.swift
    BBTB/App/macOSApp/BBTB_macOSApp.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
    BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift
  </files>

  <read_first>
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (lines 521-560 — canonical `handleForeground()` analog для shape match)
    - `BBTB/App/iOSApp/BBTB_iOSApp.swift` (lines 180-227 — current `.onChange(of: scenePhase)` block: 3 параллельных Task'а — `Task.detached(priority: .background)` для runIsSupportedUpgrade + `Task` для tc.handleForeground + `Task` для viewModel.handleForeground)
    - `BBTB/App/macOSApp/BBTB_macOSApp.swift` (mirror handler — same coalescing required)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (lines 79-85 — duplicate `.onChange(of: scenePhase)` for serverListViewModel.silentForegroundRefresh; this 4th Task must be folded into handleForegroundReentry)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 M7 (Evidence + Risk surface)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "M7 — scenePhase consolidation" (Code excerpts + DEC-06d-01 preservation note)
    - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift` (analog test scaffolding: `@MainActor final class … : XCTestCase` + Mock TunnelControlling + Mock ConfigImporting patterns для M7 test)
    - `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_phase6d_architectural_patterns.md` (DEC-06d-01 cold-start defer pattern)
  </read_first>

  <behavior>
    - Test 1 (`test_handleForegroundReentry_invokes_all_three_hooks_in_order`): создать ViewModel с Mock TunnelControlling + Mock ConfigImporting + Mock ServerListVM; вызвать `await viewModel.handleForegroundReentry()`; assert порядок invocations: importer.runIsSupportedUpgrade → tc.handleForeground → serverListVM.silentForegroundRefresh.
    - Test 2 (`test_handleForegroundReentry_skips_runIsSupportedUpgrade_when_connecting`): set vm.state = .connecting; вызвать handleForegroundReentry; assert importer.runIsSupportedUpgrade НЕ вызван (preserves existing M3 guard); assert tc.handleForeground + silentForegroundRefresh ВСЁ ЕЩЁ вызваны (foreground sync обязателен независимо от state).
    - Test 3 (`test_handleForegroundReentry_when_tunnelController_nil_continues_other_hooks`): tunnelController = nil; вызвать; assert no crash + other two hooks invoked.
  </behavior>

  <action>
    Реализация per D-01 + DEC-06d-01 preservation (cold-start defer):

    1) В `MainScreenViewModel.swift` ВНУТРИ существующего класса добавить новый public async метод `handleForegroundReentry()` СРАЗУ ПОСЛЕ существующего `handleForeground()` (около line 560). Метод выполняет SEQUENTIAL await:
       - 1-й шаг: `Task.detached(priority: .background)` для `importer.runIsSupportedUpgrade()` с существующим guard `!isConnecting` (snapshot через MainActor.run; preserve DEC-06d-01 defer pattern — НЕ убирать detach).
       - 2-й шаг: `await tunnelController?.handleForeground()` (sync XPC trip — DEC-06d-02 preserved, 1 trip).
       - 3-й шаг: `await serverListViewModel?.silentForegroundRefresh()` (если non-nil).
       Метод НЕ вызывает `applyVPNStatus` напрямую — это responsibility `handleForeground()` (D-09 single authority preserved).

    2) В `BBTB_iOSApp.swift` (lines 194-220) и в `BBTB_macOSApp.swift` (соответствующий handler) ЗАМЕНИТЬ существующий `.onChange(of: scenePhase)` блок (содержащий 3 Task spawn-а) на ОДИН:
       ```
       .onChange(of: scenePhase) { _, newPhase in
           guard newPhase == .active else { return }
           Task { @MainActor in await viewModel.handleForegroundReentry() }
       }
       ```
       Удалить inline `Task.detached(priority: .background)` block (он переезжает внутрь handleForegroundReentry) + `Task { await tc.handleForeground() }` + `Task { await viewModel.handleForeground() }`.

    3) В `MainScreenView.swift` (lines 79-85) УДАЛИТЬ duplicate `.onChange(of: scenePhase)` для `serverListVM.silentForegroundRefresh()` — этот hook теперь внутри handleForegroundReentry. (Удаление дубликата = вторая часть consolidation.)

    4) Создать NEW test file `HandleForegroundReentryTests.swift` в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/` с тремя test methods описанными в `<behavior>`. Использовать analog шаблон из `AutoSelectIntegrationTests.swift` для @MainActor XCTestCase + Mock TunnelControlling/ConfigImporting/ServerListViewModel. Mock invocation order verify через `[String]` log array. Не использовать XCTKVO; use plain XCTAssertEqual on recorded order.

    5) Commit message: `fix(06e-M7): consolidate scenePhase=.active hooks into MainScreenViewModel.handleForegroundReentry per D-01`. Preserve DEC-06d-01 defer pattern (Task.detached осталась внутри handleForegroundReentry — не removed).

    6) НЕ нарушить:
       - `applyVPNStatus` single authority (D-09): handleForegroundReentry НЕ должен вызывать applyVPNStatus напрямую — только через tc.handleForeground.
       - DEC-06d-02 XPC ≤ 2: handleForeground = 1 XPC trip; new method не добавляет XPC trips сверх.
       - NEVPNStatusDidChange observer queue=nil (`feedback_nevpn_observer_queue_main.md`): handleForegroundReentry не трогает observer registration.
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.HandleForegroundReentryTests</automated>
    Дополнительно (manual, после swift test PASS):
    - `swift test --package-path BBTB/Packages/AppFeatures` (≥ 133+3 = 136/136 — 3 новых теста добавлены)
    - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` SUCCEEDED
    - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` SUCCEEDED
    - `grep -c "viewModel.handleForegroundReentry" BBTB/App/iOSApp/BBTB_iOSApp.swift` = 1
    - `grep -c "viewModel.handleForegroundReentry" BBTB/App/macOSApp/BBTB_macOSApp.swift` = 1
    - `grep -c "silentForegroundRefresh" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` = 0 (duplicate .onChange removed)
    - `grep -n "Task.detached.*priority:" BBTB/App/iOSApp/BBTB_iOSApp.swift | wc -l` = 0 (moved into handleForegroundReentry; check matching baseline 0 OR ≥ 0 depending on other detached usages)
    - `grep -c "Task.detached.*runIsSupportedUpgrade\|runIsSupportedUpgrade.*Task.detached" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` ≥ 1 (DEC-06d-01 preserved inside new method)
  </verify>

  <done>
    - `handleForegroundReentry()` определён в MainScreenViewModel.swift сразу после `handleForeground()`
    - BBTB_iOSApp.swift + BBTB_macOSApp.swift: scenePhase .active handler — ОДИН Task spawn, вызывающий handleForegroundReentry
    - MainScreenView.swift: duplicate .onChange для silentForegroundRefresh удалён
    - HandleForegroundReentryTests.swift: 3 PASS
    - swift test ≥ 136/136; iOS + macOS xcodebuild SUCCEEDED
    - DEC-06d-01 + DEC-06d-02 grep audits pass
    - One commit `fix(06e-M7): ...`
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: M10 — ServerListViewModel.loadFromStore idempotency guard + confirmDeleteSubscription collapse</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift
    BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift
  </files>

  <read_first>
    - `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` (полностью — особенно lines 181, 224, 257, 282, 286-323, 328-335: 6 call sites loadFromStore + body + confirmDeleteSubscription cascade-delete branch lines 312 + 323)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 M10 (Refined fix — Part A + Part B)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "M10 — loadFromStore idempotency" (code excerpts + D-09 #Predicate UUID? = 0 invariant)
    - `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/PullToRefreshTests.swift` (analog для test scaffolding: Mock probe/fetcher/parser + in-memory ModelContainer + `@MainActor final class … : XCTestCase`)
    - `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_swiftdata_uuid_predicate.md` (D-09 #Predicate UUID? = 0 invariant — loadFromStore использует FetchDescriptor без #Predicate; M10 fix не должен resurrect-ить #Predicate UUID?)
  </read_first>

  <behavior>
    - Test 1 (`test_confirmDeleteSubscription_calls_loadFromStore_exactly_once`): set up in-memory ModelContainer + ServerListViewModel with mocked counter wrapper around loadFromStore; вызвать `await vm.confirmDeleteSubscription(sub)` для существующей subscription; assert loadFromStore counter == 1.
    - Test 2 (`test_confirmDeleteSubscription_early_exit_branch_calls_loadFromStore_exactly_once`): set up case где subRowDesc fetch returns nil (subscription уже удалена); вызвать confirmDeleteSubscription; assert loadFromStore counter == 1 (раньше было 1 + 1 на normal path = 2).
    - Test 3 (`test_loadFromStore_debounce_within_100ms_skips_second_call`): вызвать `await vm.loadFromStore()` дважды подряд (через test seam — internal/@testable); assert second call returns immediately без full body execution (counter инкремент происходит только в первом).
    - Test 4 (`test_loadFromStore_after_100ms_executes_full_body`): вызвать loadFromStore, `try await Task.sleep(for: .milliseconds(120))`, вызвать снова; assert second call full body executes.
  </behavior>

  <action>
    Реализация per RESEARCH.md Section 1 M10 (Two-part fix):

    1) **Part A — collapse `confirmDeleteSubscription` double-call:**
       В `ServerListViewModel.swift` lines 286-323 (метод `confirmDeleteSubscription(_:)`):
       - УДАЛИТЬ `await loadFromStore()` из early-exit branch (line ~312).
       - ПЕРЕМЕСТИТЬ единственный `await loadFromStore()` в самый конец метода ПОСЛЕ try/catch (line ~323). Использовать структуру: early-exit branch выполняет state mutations (context.save, applySelection nil, pendingDeleteSubscription = nil), но НЕ вызывает loadFromStore — falls through к финальному tail-call. Если контроль flow требует return после early-exit logic — рефактор: вместо `return` в branch используем `if/else` + единственный финальный tail-call.

    2) **Part B — idempotency guard в `loadFromStore()`:**
       В `ServerListViewModel.swift` body начиная с line 328:
       - Добавить два private @MainActor stored properties в класс (рядом с другими `@Published`/private state):
         ```
         private var loadInProgress: Bool = false
         private var lastLoadAt: Date = .distantPast
         ```
       - В начале `loadFromStore()` body добавить guard pair:
         ```
         if loadInProgress { return }
         if Date().timeIntervalSince(lastLoadAt) < 0.1 { return }
         loadInProgress = true
         defer { loadInProgress = false; lastLoadAt = Date() }
         ```
       - НЕ менять остальной body (FetchDescriptor + groupSections logic preserved).

    3) Создать NEW test file `LoadFromStoreIdempotencyTests.swift` в `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/` с 4 test methods из `<behavior>`. Use analog from `PullToRefreshTests.swift` — Mock probe/fetcher/parser + in-memory `ModelContainer(for: ServerConfig.self, Subscription.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))`. Counter wrapper можно реализовать через test-only @testable property OR через test-specific subclass (если ServerListViewModel допускает). Альтернатива — добавить internal `private(set) var loadFromStoreCallCount: Int` (test-only через @testable import) для simplicity.

    4) Commit message: `fix(06e-M10): ServerListViewModel.loadFromStore idempotency guard + confirmDeleteSubscription single-tail-call per D-01`.

    5) НЕ нарушить:
       - D-09 `#Predicate` UUID? = 0: loadFromStore body использует `FetchDescriptor<Subscription>` + `FetchDescriptor<ServerConfig>` БЕЗ #Predicate — preserve unchanged. Никакого refactor к `#Predicate { $0.id == X }` для UUID-полей (`feedback_swiftdata_uuid_predicate.md`).
       - DEC-06d-04 bounded probe concurrency: loadFromStore не probe-style, не трогаем.
       - applyVPNStatus single authority: loadFromStore не трогает VPN state path.
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures --filter ServerListFeatureTests.LoadFromStoreIdempotencyTests</automated>
    Дополнительно:
    - `swift test --package-path BBTB/Packages/AppFeatures` ≥ 136+4 = 140/140 (M7 tests + M10 tests)
    - `xcodebuild ... -scheme BBTB iOS Simulator build` SUCCEEDED
    - `xcodebuild ... -scheme BBTB-macOS build` SUCCEEDED
    - `grep -c "await loadFromStore()" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` = 5 (было 6; одна удалена из early-exit branch confirmDeleteSubscription)
    - `grep -c "loadInProgress" BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` ≥ 2 (declaration + guard usage)
    - `grep -rn "#Predicate.*UUID?" BBTB --include="*.swift" | wc -l` ≤ 1 (D-09 preserved — comment-only in ConfigImporter)
  </verify>

  <done>
    - confirmDeleteSubscription вызывает loadFromStore() ровно 1 раз
    - loadFromStore() имеет 100ms debounce + in-progress guard
    - LoadFromStoreIdempotencyTests.swift: 4 PASS
    - swift test ≥ 140/140; iOS + macOS xcodebuild SUCCEEDED
    - D-09 #Predicate UUID? grep ≤ 1
    - One commit `fix(06e-M10): ...`
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 3: M8 + L12 — BaseSingBoxTunnel validatedAt cache marker (R10 defense-in-depth preserved)</name>

  <files>
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift
  </files>

  <read_first>
    - `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` (lines 90-260: startTunnel pipeline — pre-expand validate lines 156-164, expandConfigForTunnel call lines 226-238, post-expand validate lines 240-251)
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (find `provisionTunnelProfile` method + locations где providerConfiguration["configJSON"] устанавливается; also `SingBoxConfigLoader.validate` callsite in importer)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 M8 (полностью — Refined fix Option A; R10 invariant preservation; 3 NEW tests)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "M8 — validatedAt timestamp guard" (CRITICAL — R10 preservation requirement)
    - `wiki/security-gaps.md` R10 (TUN inbound expansion + post-expand re-validation defense-in-depth)
    - `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/SingBoxConfigLoaderTests.swift` (analog scaffold для ValidatedAtGuardTests — XCTAssertNoThrow + fixture loader pattern)
  </read_first>

  <behavior>
    - Test 1 (`test_pre_expand_validate_skipped_when_validatedAt_within_24h`): создать BaseSingBoxTunnel-mock-context с providerConfiguration["configJSON"] = валидный JSON + providerConfiguration["configJSONValidatedAt"] = ISO8601 string current Date(); инжектировать counter spy в SingBoxConfigLoader.validate (через test seam или wrapper); вызвать startTunnel path; assert pre-expand validate spy NOT called; assert post-expand validate spy CALLED (R10 preserved).
    - Test 2 (`test_post_expand_validate_always_runs_unconditional`): set fresh validatedAt; vary providerConfiguration scenarios; assert post-expand validate ALWAYS invoked (R10 defense-in-depth invariant).
    - Test 3 (`test_pre_expand_validate_runs_when_validatedAt_missing`): providerConfiguration["configJSONValidatedAt"] = nil; assert pre-expand validate spy CALLED (backward-compat для cold reboot / стариковые providerConfiguration без timestamp).
    - Test 4 (`test_pre_expand_validate_runs_when_validatedAt_stale_over_24h`): providerConfiguration["configJSONValidatedAt"] = ISO8601 25 hours ago; assert pre-expand validate CALLED.
  </behavior>

  <action>
    Реализация per RESEARCH.md Section 1 M8 + PATTERNS.md "M8 — validatedAt timestamp guard". **CRITICAL: R10 defense-in-depth — post-expand validate MUST remain unconditional.**

    1) **ConfigImporter side:** В `ConfigImporter.swift` найти участок где после успешного `SingBoxConfigLoader.validate(json: configJSON)` устанавливается `protocolConfig.providerConfiguration["configJSON"] = configJSON` (provisionTunnelProfile pipeline). В том же scope ДОБАВИТЬ:
       ```
       providerConfiguration["configJSONValidatedAt"] = ISO8601DateFormatter().string(from: Date())
       ```
       Использовать общий ISO8601DateFormatter instance (создать как helper или inline — minimal overhead). Timestamp устанавливается ТОЛЬКО после успешного validate (если validate throws, save не происходит, timestamp не пишется — invariant: timestamp ⇒ JSON validated).

    2) **BaseSingBoxTunnel side:** В `BaseSingBoxTunnel.swift` startTunnel pipeline:
       - ОБЕРНУТЬ pre-expand validate block (lines 156-164) в guard. Compute `skipPreExpand: Bool` локальной let-биндингом ДО do-блока:
         ```
         let skipPreExpand: Bool = {
             guard let validatedAtRaw = providerConfiguration["configJSONValidatedAt"] as? String,
                   let validatedAt = ISO8601DateFormatter().date(from: validatedAtRaw)
             else { return false }
             return Date().timeIntervalSince(validatedAt) < 24 * 3600
         }()
         ```
       - Если `!skipPreExpand` — выполнить ЕХАКТНО существующий do/catch с `SingBoxConfigLoader.validate(json: configJSON)` (preserved as-is). Если skip — логирование `TunnelLogger.lifecycle.info("startTunnel: pre-expand R1/SEC-06 validation skipped (validatedAt within 24h window)")`.
       - **CRITICAL: post-expand validate (lines 240-251) ОСТАЁТСЯ unchanged, unconditional.** Verify post grep: `grep -c "SingBoxConfigLoader.validate" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` ≥ 2 (1 pre-expand guarded + 1 post-expand unconditional).

    3) **L12 bundled:** L12 = LOW-tier версия M8 (pre-expand validate redundant). Один commit покрывает оба finding; в commit message указать `(M8 + L12)`.

    4) Создать NEW test file `ValidatedAtGuardTests.swift` в `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/` с 4 test methods. Для test seam — Mock `providerConfiguration` dictionary через NETunnelProviderProtocol stub OR через test-only public method `BaseSingBoxTunnel.shouldSkipPreExpandValidate(providerConfiguration:)` (extracted helper) — preferred подход для testability. Если executor предпочитает spy-pattern на SingBoxConfigLoader — это тоже valid (depends на existing test infrastructure в SingBoxConfigLoaderTests.swift).

    5) Commit message: `fix(06e-M8 + L12): pre-expand validate guarded by configJSONValidatedAt 24h cache (R10 post-expand preserved)`. **Mandatory:** упомянуть в commit message что R10 defense-in-depth invariant preserved (post-expand validate unconditional).

    6) НЕ нарушить:
       - **R10 defense-in-depth (`wiki/security-gaps.md`):** post-expand validate (lines 240-251) — UNCHANGED, ALWAYS runs. Это catches expand mutations (TUN inbound addition).
       - **R1 (white-list inbound types):** preserved через post-expand.
       - **SEC-06 (валидация структуры):** preserved через post-expand.
       - **DEC-06d-05 (ExternalVPNStopMarker semantics):** M8 fix не трогает marker; verify `grep -rn "ExternalVPNStopMarker" BBTB --include="*.swift" | grep ".consume(" | wc -l` = 0.
       - D-09 forbidden symbols — нет regression (M8 fix локально в extension target).
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/PacketTunnelKit --filter PacketTunnelKitTests.ValidatedAtGuardTests</automated>
    Дополнительно:
    - `swift test --package-path BBTB/Packages/PacketTunnelKit` ≥ 61+4 = 65/65 (baseline 61 + 4 new)
    - `swift test --package-path BBTB/Packages/AppFeatures` ≥ 140/140 (M7+M10 tests preserved)
    - `xcodebuild ... -scheme BBTB iOS Simulator build` SUCCEEDED
    - `xcodebuild ... -scheme BBTB-macOS build` SUCCEEDED
    - **CRITICAL R10 check:** `grep -c "SingBoxConfigLoader.validate" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` ≥ 2 (pre guarded + post unconditional)
    - `grep -n "configJSONValidatedAt" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift | wc -l` ≥ 1 (timestamp setter)
    - `grep -n "configJSONValidatedAt" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift | wc -l` ≥ 1 (guard reader)
    - `grep -rn "ExternalVPNStopMarker" BBTB --include="*.swift" | grep ".consume(" | wc -l` = 0 (DEC-06d-05 preserved)
  </verify>

  <done>
    - ConfigImporter записывает providerConfiguration["configJSONValidatedAt"] после собственного validate
    - BaseSingBoxTunnel skip-ает pre-expand validate когда timestamp < 24h; ALWAYS выполняет post-expand validate (R10)
    - ValidatedAtGuardTests.swift: 4 PASS
    - swift test PacketTunnelKit ≥ 65/65; AppFeatures ≥ 140/140; iOS + macOS xcodebuild SUCCEEDED
    - R10 grep audit: ≥ 2 SingBoxConfigLoader.validate в BaseSingBoxTunnel.swift
    - DEC-06d-05 ExternalVPNStopMarker semantics preserved
    - One commit `fix(06e-M8 + L12): ...` с R10 preservation в commit message
  </done>
</task>

<task type="auto" tdd="true">
  <name>Task 4: M11 — applyVPNStatus(.connecting) explicit early-return guard (D-09 single authority preserved)</name>

  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
    BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift
  </files>

  <read_first>
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (lines 410-487 — `applyVPNStatus(_:connectedDate:)` весь body: outer guard line 414 + nested `.connecting/.reasserting` switch lines ~420-436 + остальные case branches)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 1 M11 (полный текст — current state PARTIALLY-ADDRESSED, refined Option A explicit guard)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "M11 — applyVPNStatus early-return guard" (CRITICAL — D-09 single authority preservation)
    - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/AutoSelectIntegrationTests.swift` (CRITICAL — test_selection_change_during_active_tunnel_reconnects MUST PASS — Phase 6d post-fix `9b38796` armed coverage)
    - `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_observer_queue_main.md` (observer queue=nil invariant — НЕ переименовывать к .main)
    - `wiki/auto-reconnect.md` (Phase 6c R18 sliding window invariant context — applyVPNStatus participant)
  </read_first>

  <behavior>
    - Test 1 (`test_applyVPNStatus_connecting_called_twice_state_stable`): set vm.state = .disconnected; call `vm.applyVPNStatus(.connecting)`; assert state == .connecting; call `vm.applyVPNStatus(.connecting)` second time; assert state == .connecting (idempotent) + assert no internal mutation thrash (lastAppliedVPNStatus outer guard handles primary dedupe; inner guard secondary safety).
    - Test 2 (`test_applyVPNStatus_connecting_then_connected_progresses_state`): set vm.state = .disconnected; call applyVPNStatus(.connecting); assert .connecting; call applyVPNStatus(.connected, connectedDate: Date()); assert .connected — verifies early-return guard НЕ блокирует legitimate transitions.
    - Test 3 (`test_applyVPNStatus_connecting_when_already_connected_falls_through_to_default_branch`): set vm.state = .connected (через предыдущий .connected apply); call applyVPNStatus(.connecting); assert state transitions to .connecting (the default branch of inner switch fires — early-return guards только когда state УЖЕ .connecting).
  </behavior>

  <action>
    Реализация per RESEARCH.md Section 1 M11 Option A + PATTERNS.md M11 application note. **CRITICAL: D-09 applyVPNStatus single authority — exactly ONE function definition; не добавлять новые setter sites.**

    1) В `MainScreenViewModel.swift` методе `applyVPNStatus(_:connectedDate:)` найти ветку `.connecting, .reasserting:` (около line 420). СРАЗУ ПОСЛЕ pattern match (до существующего nested switch) добавить explicit early-return guard:
       ```
       case .connecting, .reasserting:
           // Phase 6e M11: explicit idempotency. Если state уже .connecting —
           // banner / reactive flags не меняем; outer-level lastAppliedVPNStatus
           // dedupe (Phase 6d 9b38796) handles primary dedupe; этот guard —
           // explicit secondary safety, документирующий intent.
           guard state != .connecting else { return }
           switch state {
           // ... existing nested switch ...
           }
           // ... existing branch body (banner mutation etc.) ...
       ```
       Сохранить остальное тело ветки UNCHANGED (banner mutation, etc.).

    2) **CRITICAL preservation:**
       - НЕ удалять outer-level `lastAppliedVPNStatus`/`lastAppliedConnectedDate` guard (line 414 — Phase 6d post-fix `9b38796` 8k-event safety net).
       - НЕ добавлять `state = ...` setters вне applyVPNStatus body.
       - НЕ менять signature applyVPNStatus.

    3) Создать NEW test file `ApplyVPNStatusGuardTests.swift` в `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/` с 3 test methods из `<behavior>`. Use analog from `AutoSelectIntegrationTests.swift` — `@MainActor final class … : XCTestCase` + Mock TunnelControlling + Mock ConfigImporting (если требуется для VM init).

    4) Commit message: `fix(06e-M11): explicit applyVPNStatus(.connecting) early-return guard (D-09 single authority preserved)`.

    5) **Mandatory regression coverage:** AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects (Phase 6d post-fix re-armed `.connected → .disconnected → .connected` transition coverage) MUST PASS. Этот тест критичен — он verifies что guard НЕ блокирует legitimate state transitions.

    6) НЕ нарушить:
       - **D-09 applyVPNStatus single authority:** `grep -c "func applyVPNStatus" MainScreenViewModel.swift` = 1.
       - **NEVPNStatusDidChange observer queue = nil:** M11 fix не трогает observer registration (`grep -rn "NEVPNStatusDidChange.*queue:.*\.main" BBTB --include="*.swift" | wc -l` = 0).
       - **Phase 6c R18 sliding window invariant:** separate surface (OnDemandRulesBuilder.swift), не applyVPNStatus; verify `grep -n "toggle && intent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l` = 2 (line 68 comment + line 113 code).
       - **8k duplicate event coverage:** outer-level `lastAppliedVPNStatus` guard НЕ удалён.
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.ApplyVPNStatusGuardTests</automated>
    Дополнительно:
    - `swift test --package-path BBTB/Packages/AppFeatures --filter MainScreenFeatureTests.AutoSelectIntegrationTests` PASS (CRITICAL — Phase 6d post-fix armed test)
    - `swift test --package-path BBTB/Packages/AppFeatures` ≥ 140+3 = 143/143 (M7+M10+M11 tests)
    - `xcodebuild ... -scheme BBTB iOS Simulator build` SUCCEEDED
    - `xcodebuild ... -scheme BBTB-macOS build` SUCCEEDED
    - **D-09 single authority:** `grep -c "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 1
    - `grep -n "guard state != .connecting" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift | wc -l` ≥ 1 (new guard present)
    - `grep -n "lastAppliedVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift | wc -l` ≥ 2 (outer guard preserved + assignment)
    - `grep -rn "NEVPNStatusDidChange.*queue:.*\.main\b" BBTB --include="*.swift" | wc -l` = 0
    - `grep -n "toggle && intent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l` = 2
  </verify>

  <done>
    - applyVPNStatus `.connecting/.reasserting` ветка имеет explicit early-return guard
    - outer-level lastAppliedVPNStatus guard preserved
    - ApplyVPNStatusGuardTests.swift: 3 PASS
    - AutoSelectIntegrationTests: PASS
    - swift test ≥ 143/143; iOS + macOS xcodebuild SUCCEEDED
    - D-09 single authority grep audit: 1
    - Observer queue=.main grep: 0
    - R18 sliding window: 2 hits preserved
    - One commit `fix(06e-M11): ...`
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| App → PacketTunnelExtension (App Group + providerConfiguration) | M8 changes the validation contract crossing this boundary: app writes `configJSONValidatedAt` timestamp; extension reads it and decides whether to skip pre-expand validate |
| App ↔ NEVPN system (XPC/observer) | M7 consolidates Tasks attaching to scenePhase; M11 modifies state mutation от NEVPNStatusDidChange observer |
| App ↔ SwiftData (in-memory + persistent store) | M10 touches loadFromStore concurrency model |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-6e-01 | Tampering / Elevation of Privilege | M8 — BaseSingBoxTunnel pre-expand validate guard | **mitigate** | R10 defense-in-depth — POST-EXPAND `SingBoxConfigLoader.validate(json: expandedJSON)` MUST остаться unconditional (verified via grep `SingBoxConfigLoader.validate` ≥ 2 в BaseSingBoxTunnel.swift). Attack surface "malformed JSON injected в App Group между save и tunnel start" — local privilege escalation required to write `configJSONValidatedAt`; post-expand validate ловит mutation invariants независимо. HIGH severity if violated — block on grep audit failure. |
| T-6e-02 | Denial of Service / Correctness | M11 + L16 (future) — applyVPNStatus reactive driver | **mitigate** | Early-return guard MUST НЕ блокировать legitimate state transitions (.connected → .disconnected → .connected, .connecting → .connected). Regression coverage через AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects (Phase 6d post-fix armed) — MUST PASS. Phase 6c R18 sliding window invariant в OnDemandRulesBuilder.swift — separate surface, не applyVPNStatus; preserve через `grep 'toggle && intent' = 2`. HIGH severity if state-machine convergence breaks. |
| T-6e-03 | Information Disclosure | M10 — ServerListViewModel.loadFromStore | **accept** | Idempotency guard добавляет 100мс debounce + in-progress flag. Risk surface: SwiftData fetch race с concurrent write. Mitigation: loadInProgress flag prevents concurrent body execution; @MainActor isolation prevents cross-actor races. LOW severity — accept. |
| T-6e-04 | Repudiation | M7 — scenePhase consolidation | **accept** | Sequential await вместо parallel Task spawn — ordering deterministic, easier для diagnostic logs. No new attack surface; cleanup-only. LOW severity — accept. |
</threat_model>

<verification>
**Per-commit regression gate after EACH atomic commit (M7 → M10 → M8 → M11):**
1. `swift test --package-path BBTB/Packages/AppFeatures` ≥ baseline-после-добавленных-тестов (133 → 136 → 140 → 143)
2. `swift test --package-path BBTB/Packages/PacketTunnelKit` ≥ 65/65 (after M8 commit; baseline 61 + 4 new)
3. `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED
4. `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED

**Per-commit D-09 invariant grep (subset, full audit в Wave 3):**
- `grep -rn 'NEVPNStatusDidChange.*queue:.*\.main\b' BBTB --include='*.swift' | wc -l` = 0 (every commit)
- `grep -rn '#Predicate.*UUID?' BBTB --include='*.swift' | wc -l` ≤ 1 (every commit)
- `grep -c "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` = 1 (M11 commit critical)
- `grep -c "SingBoxConfigLoader.validate" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` ≥ 2 (M8 commit critical — R10)
- `grep -rn "ExternalVPNStopMarker" BBTB --include="*.swift" | grep ".consume(" | wc -l` = 0 (every commit)

**D-08 FAIL recovery:** если per-commit gate fails — `git revert <SHA>` + investigate root cause; НЕ "fix forward" (Phase 6c R18 lesson). Если 2+ failures на одном finding — escalate к Architect (`mcp__codex__codex` sandbox=read-only) per CONTEXT.md D-06/D-08.
</verification>

<success_criteria>
- 4 atomic commits в risk-ascending order (M7 → M10 → M8 → M11)
- Каждый commit: regression gate green (AppFeatures + PacketTunnelKit if relevant + iOS + macOS xcodebuild)
- 4 NEW test files created (HandleForegroundReentryTests, LoadFromStoreIdempotencyTests, ValidatedAtGuardTests, ApplyVPNStatusGuardTests) — total 14 new tests
- AppFeatures swift test финальный count ≥ 143/143 после Task 4 commit
- D-09 invariants preserved через grep audit на каждом commit
- DEC-06d-01 (cold-start defer pattern) preserved в M7 — Task.detached(priority: .background) сохранён внутри handleForegroundReentry
- DEC-06d-02 (XPC ≤ 2 trips) preserved — M7 не добавляет XPC trips
- DEC-06d-05 (ExternalVPNStopMarker peek-only) preserved — `.consume(` callers = 0
- R10 defense-in-depth preserved (M8) — post-expand validate unconditional в BaseSingBoxTunnel.swift
- AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects PASS (M11 critical)
- M6, M15 bookkeeping rows для Wave 3 SUMMARY (NO code change в этом плане — subsumed by 6d)
</success_criteria>

<output>
After completion, create `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-01-SUMMARY.md` со следующим:
- 4 atomic commits + their SHAs
- 4 NEW test files + test counts
- Per-commit regression gate results (AppFeatures / PacketTunnelKit / iOS / macOS xcodebuild)
- D-09 grep audit subset results
- Bookkeeping rows для M6, M15 (subsumed-by-6d references — `1467328`/`9b38796` для M6; `55bde6c` для M15)
- Carry-forward для Wave 2: 20 LOW + 3 trivial imports
</output>