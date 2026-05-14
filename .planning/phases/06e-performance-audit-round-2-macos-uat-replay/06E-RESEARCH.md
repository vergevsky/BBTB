# Phase 6e Research

**Researched:** 2026-05-14
**Status:** READY FOR PLANNING
**Researcher:** gsd-phase-researcher (Claude Opus 4.7, 1M context)
**Phase:** 6e — Performance Audit Round 2 (cleanup of 26 carved-out findings from Phase 6d)
**Mode:** cleanup / remediation (NO new features; NO numerical Instruments capture; NO macOS UAT replay)
**Confidence:** HIGH

---

## Executive Summary

Phase 6e — tactical cleanup-фаза. 26 carved findings (6 MEDIUM + 20 LOW + 3 trivial unused imports) исследованы против post-Phase-6d code state (HEAD = `584fcbd`). Ключевой вывод:

- **2 из 26 findings (M6, M15) уже фактически закрыты** в Phase 6d post-fix commits / в основном fix-cycle и должны быть downgraded к "subsumed-by-6d" (zero code change в Phase 6e, только запись в SUMMARY).
- **2 из 20 LOW findings (L6, L19) automatically resolved** by Phase 6d HIGH fixes (H5 conditional Timer; H7 cached count) — становятся no-op observations.
- **22 carved findings остаются still-applicable** — 4 MEDIUM (M7, M8, M10, M11) + 18 LOW (L1..L20 минус L6, L19) + 3 trivial imports.
- **Risk surface ясно очерчен** — ни один из 22 still-applicable не пересекает forbidden D-09 invariants (sliding window / observer queue / #Predicate UUID? / applyVPNStatus authority / forbidden symbols), но **2 MEDIUM (M8 + M11)** требуют осторожной формулировки тестов, потому что трогают hot paths (cold-start config validation; applyVPNStatus state guards).
- **AppFeatures baseline confirmed:** `swift test --package-path BBTB/Packages/AppFeatures` → **133/133 PASS in 7.20s** (verified 2026-05-14). Regression gate стабилен.

**Primary recommendation для planner:** organize 6e в **2 waves**:
- **Wave 1 (atomic, sequential):** 4 still-applicable MEDIUM (M7 → M10 → M8 → M11) — каждое = atomic commit + полный regression gate. Plus 2 "downgrade only" entries (M6, M15) — `git commit --allow-empty` НЕ нужны; они идут в SUMMARY как narrative.
- **Wave 2 (bundles + closure):** 18 LOW findings разбиты на **4 themed bundle commits** (cleanup-perf, cleanup-correctness, cleanup-maintainability, cleanup-trivial-imports) + 1 final regression gate. Plus Wave 3 (закрытие): SUMMARY + wiki sync.

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01: Findings scope — ALL 26 carved findings.** 6 MEDIUM + 20 LOW + 3 trivial unused imports. Researcher cross-checks vs post-6d code state (this document).
- **D-01a:** Researcher MUST cross-check каждое carved finding против post-Phase-6d code state — некоторые могут быть incidentally addressed одним из 7 post-fix commits. **Этот документ — primary deliverable для D-01a.**
- **D-01b:** Planner может re-organize sub-themes — но individual MEDIUM сохраняются как separate atomic units.
- **D-02: Numerical Instruments baseline — SKIPPED, deferred к Phase 11/12.**
- **D-03: macOS UAT replay — SKIPPED, deferred к Phase 11/12.**
- **D-04: Hybrid closure rigor.** MEDIUM = atomic commit + per-commit regression gate (6 / actual 4 атомика). LOW = bundle commits по theme + single regression gate в конце bundle. Trivial imports = 1 commit.
- **D-04a:** Между MEDIUM commits и LOW bundle — НЕ полагаемся на cumulative gate. Per-MEDIUM gate'ится отдельно.
- **D-05: Closure SUMMARY + wiki sync — compact (не full Phase 6d-style).** `06E-Final-SUMMARY.md` + `wiki/performance-baseline.md` § Open follow-ups update + STATE.md/ROADMAP.md/REQUIREMENTS.md sync + `wiki/log.md` append. Не требуется отдельный `06E-COMPARISON.md`.
- **D-05a: D-09 invariants — final grep audit** перед closure commit.
- **D-06: NO 3-AI peer review re-spawn.** Findings уже triaged в Phase 6d. Architect delegation допустим только если researcher / executor встречает ambiguity в 2+ failed attempts на одном MEDIUM.
- **D-07: PASS criteria для closure** — 9-point checklist (см. CONTEXT.md полностью).
- **D-08: FAIL recovery** — если MEDIUM regression gate FAIL → revert + investigate root cause, НЕ "fix forward" (Phase 6c R18 lesson).

### Claude's Discretion

- **Wave structure** — planner может выбрать 2-3 waves. Researcher recommendation: 2 waves (Wave 1: MEDIUM atomic; Wave 2: LOW bundles + trivial + final gate) + Wave 3 (closure). См. Section 3 ниже.
- **LOW bundle theming** — planner organizes LOW по smart themes. Researcher proposal — Section 2.

### Deferred Ideas (OUT OF SCOPE)

- **Numerical Instruments baseline** — defer к Phase 11/12 (pre-TestFlight obligatory).
- **macOS UAT replay** — defer к Phase 11/12.
- **3-AI re-audit для post-Phase-6e** — Phase 6f «Performance Audit Round 3» если потребуется в Phase 7-10.
- **NET-12 (active liveness probe)** — Phase 7-8 carve-out (Phase 6c R18).
- **Phase 7 readiness signal** — после 6e closure → `/gsd-discuss-phase 7` (Anti-DPI + WireGuard family, v0.7).

---

## Phase Requirements

Phase 6e maintains PERF-01..05 + QUAL-01..03 (Phase 6d Validated). Никаких новых требований не добавляется обязательно (per CONTEXT.md). Planner может опционально добавить:

| Tentative ID | Description | Research Support |
|---|---|---|
| **QUAL-04** (proposed) | Carved-out backlog Phase 6d (26 findings) полностью закрыт; baseline maximally clean перед Phase 7. | Sections 1-2 этого документа подтверждают per-finding scope. |
| **QUAL-05** (proposed) | Periphery dead-code scan на post-Phase-6e baseline — actionable count = 3 (или 0, если imports cleaned). | `06D-PERIPHERY-POST-FIX.md` baseline = 37 warnings (34 false-positive + 3 actionable imports). После Phase 6e Trivial Imports bundle — actionable = 0. |

**Status:** новые требования — на усмотрение planner / discuss-phase решения. Researcher не настаивает.

---

## Section 1: Carved Findings — Current State Assessment

> **Source for всех finding descriptions:** `.planning/phases/06d-performance-audit/06D-FINDINGS.md` lines 64-106 (MEDIUM table) и lines 87-106 (LOW table). All file:line references проверены против post-6d HEAD (`584fcbd`).

### MEDIUM findings (6)

#### M6 — NEVPNStatusDidChange has 3 concurrent observers, each spawns Tasks

- **Original finding (06D-FINDINGS.md row M6):** `TunnelController.swift:222-228` + `MainScreenViewModel.swift:152-168` — 3 concurrent NEVPNStatusDidChange observers (TunnelController + MainScreenViewModel + watchdog) каждый spawns его собственные Task'и при каждой VPN-status notification. Recommended fix (Opus #7): consolidate в single observer owned by TunnelController, expose `AsyncStream<NEVPNStatus>` для VM.
- **Current state:** **PARTIALLY-ADDRESSED-ALREADY → DOWNGRADE к "subsumed by Phase 6d".**
- **Evidence:** Phase 6d Wave 03f + post-fix commits radically refactored observer architecture:
  - Phase 6d `cd4b297` (M1) — TunnelController consolidated cold-start XPC + bootstrap path → single seed of cachedManager.
  - Phase 6d post-fix `1467328` (`fix(06d-post): handleObservedStatus wrapper — stale-suppression + edge dedupe`) — добавлен `handleObservedStatus(_:)` wrapper в TunnelController (line 648) с edge dedupe (`lastHandledStatus`). Это закрывает duplicate-task storm, который и был root cause concern Opus #7.
  - **Current architecture (verified `TunnelController.swift:194-228, 554-577, 648-684`):** TunnelController имеет ОДИН `NEVPNStatusDidChange` observer (line 554, `nevpnObserver`, `queue: nil`). MainScreenViewModel имеет ОДИН observer (line 205, `nevpnStatusObserver`, `queue: nil`). Это **2 observer'а, не 3** — watchdog НЕ подписан напрямую на notification (он получает status через `TunnelController.handleStatusChange` → `await watchdog?.handleStatusChange(...)` line 688).
  - Дальнейшая consolidation (VM → TC AsyncStream) **не выполнена**, но Opus #7's actual concern — "each spawns Tasks per notification, contending for actor queue / Mach ports" — закрыт через edge dedupe (skip identical status, line ~675) + UI dedupe в MainScreenViewModel.applyVPNStatus (`9b38796` line 414).
- **Recommended fix (refined):** **None for Phase 6e.** Финальная архитектура (2 observers + edge dedupe at both ends) — semantically equivalent к "single observer + AsyncStream broadcast" для перформанс-цели (zero duplicate Tasks). Дополнительная consolidation увеличила бы coupling (VM зависит от TC's life cycle) ради нулевого performance gain.
- **Action:** **Document как "Subsumed by Phase 6d post-fix `1467328` + `9b38796`"** в `06E-Final-SUMMARY.md`. Phase 6e НЕ делает code change для M6.
- **Risk surface:** N/A (no code change).
- **Test impact:** N/A.

#### M7 — `BBTBRootView.scenePhase=.active` запускает 3 параллельных foreground tasks

- **Original finding (06D-FINDINGS.md row M7):** `BBTB/App/iOSApp/BBTB_iOSApp.swift:139-153` — when scenePhase → `.active`, 3 параллельных Task'а: (1) `runIsSupportedUpgrade` upgrade, (2) `tunnelController.handleForeground()`, (3) `serverListViewModel.silentForegroundRefresh()`. Recommended fix (Opus #8): coalesce в один `Task { @MainActor in await viewModel.handleForegroundReentry() }`.
- **Current state:** **STILL-APPLICABLE (with refined fix).**
- **Evidence:** Verified `BBTB_iOSApp.swift:194-220` (post-6d):
  - Task 1 (lines 196-213): `Task.detached(priority: .background)` для `runIsSupportedUpgrade`. **Phase 6d M3 fix** (`1099629`) уже defer'нул это к detached background — НЕ контендит за main thread / cooperative pool.
  - Task 2 (lines 217-219): `Task { await tc.handleForeground() }` для tunnel controller foreground hook.
  - Task 3 (`MainScreenView.swift:79-85` — отдельный `.onChange(of: scenePhase)`): `Task { @MainActor in await vm.silentForegroundRefresh() }` для server list refresh.
  - **Итого 3 Task'а** при scenePhase → `.active`. **Финдинг ещё актуален** — Phase 6d затронул только M3's содержимое (deferred к background), а не consolidation tasks.
- **Recommended fix (refined):**
  - **Option A (preserved consolidation per Opus #8 original):** create `viewModel.handleForegroundReentry()` async method в MainScreenViewModel which sequentially `await`'s all 3 hooks (`runIsSupportedUpgrade` → `tc.handleForeground()` → `serverListVM?.silentForegroundRefresh()`). Reduces Task spawn count 3→1, eliminates contention.
  - **Option B (refined, lower-risk):** оставить TaskGroup parallel но **only spawn если scenePhase transitioned from `.background` (not from `.inactive`)** — guard against rapid `.inactive ↔ .active` toggles (notification panel etc.). Дополнительно: skip Task 1 (`runIsSupportedUpgrade`) когда уже в connecting state — current code (line 211) уже делает этот guard, но в snapshot-step после Task.detached spawn (т.е. spawn cost paid). Move guard в `.onChange` body перед Task.detached.
  - **Researcher recommendation:** **Option A** — соответствует Opus #8 original fix; ниже coupling между `BBTB_iOSApp.swift` и `MainScreenView.swift` (currently они оба добавляют свой Task в scenePhase handler); легче добавлять `Task` для будущих foreground hooks.
- **Risk surface:**
  - **DEC-06d-01 (cold-start init defer):** ✓ preserved — handler stays на foreground re-entry, не на cold-start init. Task ordering (sequential vs parallel) — internal детали, не нарушают defer pattern.
  - **DEC-06d-02 (XPC consolidation ≤ 2 trips):** ✓ preserved — `handleForeground` уже Phase 6c-fixed to 1 XPC trip (loadAllFromPreferences + filter + read status). Не добавляет новых XPC trips.
  - **D-09 sliding window invariant:** ✓ preserved — `applyAutoReconnectToManager` НЕ вызывается из foreground hook; sliding window logic в `OnDemandRulesBuilder.applyCurrentState` независим.
  - **No grep regressions expected** — refactor локальный, никакой forbidden symbol не добавляется.
- **Test impact:**
  - Existing tests НЕ покрывают scenePhase transitions напрямую (intentionally — это integration / device-level surface).
  - **Recommended NEW test:** `MainScreenViewModelTests.test_handleForegroundReentry_invokes_all_3_hooks_sequentially()` — мock `tunnelController`, `serverListVM`, `importer` (через DI); verify sequential await через actor count или dispatch trace.
  - **Existing regression coverage:** AppFeatures `swift test` 133/133 ensures no compilation regression. Manual UAT (deferred per D-03) needed для verifying real scenePhase behaviour — но **carved finding fix не блокируется отсутствием UAT** (per CONTEXT.md D-03 rationale: same source code как iOS, не нужно отдельная UAT для refactor этого скоупа).

#### M8 — Tunnel start validates/parses config 3 раза (pre-app + extension pre-expand + post-expand)

- **Original finding (06D-FINDINGS.md row M8):** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift:104-111, 181-187` — `startTunnel` validates JSON pre-expand (line 158, `SingBoxConfigLoader.validate(json: configJSON)`) AND post-expand (line 245, `SingBoxConfigLoader.validate(json: expandedJSON)`). PLUS host's `ConfigImporter.provisionTunnelProfile` уже validates JSON before saving to providerConfiguration. Recommended fix (Opus #30 / Codex #13): cache expanded+validated JSON at provisioning time с schema/version marker; extension validates marker и re-expands только при mismatch.
- **Current state:** **STILL-APPLICABLE.**
- **Evidence:** Verified `BaseSingBoxTunnel.swift:156-249` (post-6d HEAD `584fcbd`):
  - Line 156-164: **Pre-expand validate** — `SingBoxConfigLoader.validate(json: configJSON)` — R1 + SEC-06 enforcement.
  - Line 226-238: `expandConfigForTunnel(json: configJSON, logPath:, logLevel:)` — adds TUN inbound + DNS-hijack migration.
  - Line 240-249: **Post-expand validate (defense-in-depth R10)** — `SingBoxConfigLoader.validate(json: expandedJSON)`.
  - **Both validate'ы остались** — no Phase 6d commit touched validation pattern (см. `git log` для `BaseSingBoxTunnel.swift` в `cf54d6f..HEAD` — `c2d54ea` для H1 trace gating + open-source-research commits для DEC-06d-05; никаких validation-cycle commits).
- **Recommended fix (refined):**
  - **Original Opus #30 / Codex #13 proposal:** schema/version marker в `providerConfiguration["configJSON"]` (e.g., `providerConfiguration["expandedHash": SHA256(configJSON)]`) + skip pre-expand validate если marker match.
  - **Researcher refined recommendation:** **Keep both validates, but skip pre-expand validate when configJSON was just produced by ConfigImporter.** Implementation:
    - Set `providerConfiguration["configJSONValidatedAt"] = ISO8601-timestamp` в ConfigImporter.provisionTunnelProfile **только когда** importer сам выполнил `SingBoxConfigLoader.validate` before save.
    - В BaseSingBoxTunnel.startTunnel: pre-expand validate skipped если `Date.now - validatedAt < 24h` (single-day cache window — handles edge case stale providerConfig from cold reboot).
    - **R10 invariant preserved:** post-expand validate (defense-in-depth) **остаётся всегда** — потому что expandConfigForTunnel mutates JSON (adds TUN inbound), и mutation surface необходимо re-verify.
  - **Alternative (simpler):** remove pre-expand validate entirely **только если** ConfigImporter всегда validates перед save — defense-in-depth теряется на attack surface "malformed JSON injected в App Group between save и tunnel start", но это threat model требует local privilege escalation, не критично.
  - **Researcher rates Option A (validatedAt timestamp) лучше** — preserves defense-in-depth idiomatic защитой "trust-but-verify within window".
- **Risk surface:**
  - **R10 invariant (`wiki/security-gaps.md` R10):** **CRITICAL** — `SingBoxConfigLoader.expandConfigForTunnel` остаётся idempotent + public; post-expand re-validation **MUST stay** (defense-in-depth R10). Pre-expand removal/skip приемлемо при `validatedAt` guard.
  - **R1 invariant (default-deny white-list `{tun, direct}`):** post-expand validate enforces — preserved.
  - **SEC-06 (валидация структуры):** preserved через post-expand validate.
  - **DEC-06d-05 (Apple-canonical options + ExternalVPNStopMarker):** NOT touched — fix локально в startTunnel validate path, не трогает options handling.
  - **Forbidden symbols / D-09 invariants:** NOT touched — startTunnel в extension target, не в AppFeatures.
  - **Risk classification:** **MEDIUM-HIGH** — затрагивает security-critical code path (R10 defense-in-depth). Planner MUST включить security review в Wave 1 review (см. Section 4 Validation Architecture).
- **Test impact:**
  - **Existing tests at risk:** `PacketTunnelKitTests` 61/61 — особенно tests верифицирующие `SingBoxConfigLoader.validate` invariants (R1 — `tests/SingBoxConfigLoaderTests.swift` если существует).
  - **Recommended NEW tests:**
    - `BaseSingBoxTunnelTests.test_pre_expand_validate_skipped_when_validatedAt_recent()` — set `providerConfiguration["configJSONValidatedAt"] = Date()`, verify validate not called twice.
    - `BaseSingBoxTunnelTests.test_post_expand_validate_always_runs()` — R10 defense-in-depth.
    - `BaseSingBoxTunnelTests.test_pre_expand_validate_runs_when_validatedAt_missing()` — cold start backward-compat.
  - **Manual security check:** grep `SingBoxConfigLoader.validate` post-fix — should find ≥ 2 call sites still (1 в ConfigImporter, 1 в BaseSingBoxTunnel post-expand; pre-expand optional).

#### M10 — `ServerListViewModel.loadFromStore` called 4 раза за один `pullToRefresh`

- **Original finding (06D-FINDINGS.md row M10):** `ServerListViewModel.swift:163-198, 213-225, 245-247, 286-287` — pullToRefresh path содержит multiple `await loadFromStore()` calls во время одного refresh cycle. Recommended fix (Opus #12): make `loadFromStore` идемпотентным и call ONCE в конце pullToRefresh; alternatively, use SwiftData ModelContext notifications.
- **Current state:** **STILL-APPLICABLE (with refined count).**
- **Evidence:** Verified `ServerListViewModel.swift:181, 224, 257, 282, 312, 323` (post-6d HEAD `584fcbd`):
  - `await loadFromStore()` calls at lines: **181** (onAppear), **224** (pullToRefresh end), **257** (silentForegroundRefresh), **282** (deleteServer), **312** (cascade-delete subscription early-exit branch), **323** (confirmDeleteSubscription end).
  - **6 call sites total** — finding undercounted (original said 4). **All still present.**
  - `loadFromStore` (line 328) creates new ModelContext + fetches all ServerConfig + all Subscription + groups by section. Cost — каждый call materializes ~100 SwiftData rows.
  - During one user-initiated `pullToRefresh`: only 1 call (line 224, end of refresh). **Original finding overstated impact** — но finding *описывает* паттерн "multiple loadFromStore in lifecycle method" который в `deleteSubscription / confirmDeleteSubscription` действительно даёт 2 calls (cascade-delete: line 312 early-exit + line 323 final).
- **Recommended fix (refined):**
  - **`confirmDeleteSubscription` path** (line 286-323) — 2 calls. Refactor: single final `await loadFromStore()` после try/catch блока. Risk низкий.
  - **Idempotency guard для `loadFromStore`:** добавить `private var loadInProgress: Bool` или `lastLoadVersion: UUID`. Subsequent rapid call within 100ms returns cached sections. Полезно для `onAppear` + `pullToRefresh` race на sheet present.
  - **Researcher recommendation:** **Two-part fix:**
    - Part A: refactor `confirmDeleteSubscription` — collapse 2 calls в 1.
    - Part B: add idempotency guard (debounce 100ms) в `loadFromStore`.
  - **Original Opus #12 SwiftData ModelContext notifications alternative** — significant architectural change (subscribe to `NSManagedObjectContextDidSave` + diff); **REJECT** for Phase 6e — out of scope для cleanup tier.
- **Risk surface:**
  - **DEC-06d-04 (bounded probe concurrency):** NOT touched — loadFromStore не probe-style.
  - **D-09 SwiftData #Predicate UUID? = 0 invariant:** ✓ preserved — `loadFromStore` использует FetchDescriptor без `#Predicate { $0.optionalUUID == X }`.
  - **No applyVPNStatus / TunnelController touches:** ✓ safe.
  - **Risk classification:** **LOW** — локальная refactor в ServerListViewModel; не трогает hot path connect-tap; debounce guard — обычный pattern.
- **Test impact:**
  - **Existing tests:** `ServerListViewModelTests` (если есть) могут протестировать `pullToRefresh` end-state — должны pass без изменений.
  - **Recommended NEW test:** `test_confirmDeleteSubscription_calls_loadFromStore_once()` — mock ModelContext, assert call count.
  - **Manual smoke:** open server list, swipe-delete subscription, verify UI updates без doubled refresh flicker.

#### M11 — `applyVPNStatus(.connecting)` overwrites state, set eagerly by `performToggleImpl`

- **Original finding (06D-FINDINGS.md row M11):** `MainScreenViewModel.swift:281-296, 429-456` — `performToggleImpl` eagerly sets `state = .connecting` (для instant UI feedback), затем reactive `applyVPNStatus(.connecting)` происходит из NEVPNStatusDidChange — overwrites без идемпотентности check. Recommended fix (Opus #13): add guard `guard state != .connecting else { return }` в `.connecting, .reasserting` branch outer switch.
- **Current state:** **PARTIALLY-ADDRESSED → STILL-APPLICABLE (different code structure now).**
- **Evidence:** Verified `MainScreenViewModel.swift:410-470` (post-6d HEAD `584fcbd`):
  - **Line 414 (Phase 6d post-fix `9b38796`):** UI dedupe guard `guard lastAppliedVPNStatus != status || lastAppliedConnectedDate != connectedDate else { return }`. **Это решает половину M11 concern** — duplicate `applyVPNStatus(.connecting)` calls now skip body entirely.
  - **Line 420-436:** `.connecting / .reasserting` branch — nested switch:
    ```swift
    switch state {
    case .empty, .error, .connecting:
        break  // <- уже есть .connecting case guard!
    default:
        state = .connecting
    }
    ```
  - **Так M11 уже фактически закрыт** через post-fix `9b38796` (outer-level guard via lastAppliedVPNStatus) + existing inner switch (line 425 includes `.connecting` в no-op case).
- **Recommended fix (refined):** **Minimal cleanup-only fix, не functional.** Opus #13 original recommendation редундантен после `9b38796`. Possible Phase 6e action:
  - **Option A:** explicit `guard state != .connecting else { return }` early-return для `.connecting` / `.reasserting` switch — readability improvement, semantically equivalent к existing nested switch case `.connecting: break`. Documents intent.
  - **Option B:** leave as-is, **DOWNGRADE M11 к "subsumed by `9b38796`"** в SUMMARY.
  - **Researcher recommendation:** **Option A** — explicit early-return улучшает readability + matches Opus #13's intent literally; minimal code change (3 lines); zero functional risk; helps future maintainers spot the dedupe invariant.
- **Risk surface:**
  - **D-09 applyVPNStatus single authority invariant:** **CRITICAL preservation required.** applyVPNStatus body must remain single source-of-truth для UI state mutation. Early-return guards внутри switch acceptable; новые setters запрещены.
  - **D-09 round 5 carve-out:** preserved — `connectInProgress` / `manualDisconnectInProgress` это TunnelController-side, не VM-side; M11 fix их не трогает.
  - **Sliding window invariant:** NOT touched.
  - **Risk classification:** **MEDIUM** — applyVPNStatus is the reactive UI driver; даже cosmetic changes требуют per-commit gate.
- **Test impact:**
  - **Existing tests at risk:** `AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects` — этот test был перепрошит Phase 6d post-fix `9b38796` для transition pattern `.connected → .disconnected → .connected`. **M11 fix не должен ломать этот test.**
  - **Recommended NEW test:** `test_applyVPNStatus_connecting_called_twice_state_stable()` — verify `state == .connecting` после 2 sequential calls (idempotent).
  - **Regression gate criticality:** **HIGH** — applyVPNStatus pathway has Phase 6c R18 sliding-window dependencies. swift test 133/133 mandatory before commit.

#### M15 — `ServerProbeService.probeOnce` creates 150 NWConnection in parallel при probeAll

- **Original finding (06D-FINDINGS.md row M15):** `ServerProbeService.swift:44-47, 145-160` — `probeAll` spawns N parallel `probeOnce` (no bounded concurrency); 50 servers × 3 probes = 150 simultaneous NWConnection. Recommended fix (Opus #26 / Codex #2): bounded concurrency semaphore size 8 — **already noted as subsumed by H4** в 06D-FINDINGS.md.
- **Current state:** **INVALIDATED → DOWNGRADE к "Subsumed by Phase 6d H4 (Wave 03c, commit `55bde6c`)".**
- **Evidence:** Verified `ServerProbeService.swift:114, 133-171` (post-6d HEAD `584fcbd`):
  - Line 114: `private static let maxConcurrentProbes = 8`.
  - Line 140-163: `probeAll` использует `withTaskGroup` с invariant **in-flight tasks ≤ cap = 8**. Spawning логика: initial 8 tasks; затем по 1 на каждый `await group.next()` until exhaustion.
  - **M15 fully closed** — H4 Part 1 (`55bde6c`) точно бы соответствует Opus #26 recommended fix.
- **Recommended fix (refined):** **None.** M15 = duplicate of H4. Document в SUMMARY как "Subsumed by H4".
- **Action:** Phase 6e НЕ делает code change для M15.
- **Risk surface:** N/A.
- **Test impact:** N/A. (Existing `VPNCoreTests` для `ServerProbeService` cover bounded behaviour; passed in Phase 6d gate.)

---

### LOW findings (20)

Format: **L# — title** | **Current state** | **Evidence** | **Refined fix** | **Risk** | **Test impact**.

#### L1 — `clearDNSCache` blocks 2 semaphore waits (deadlock risk)
- **Current state:** **STILL-APPLICABLE.** Verified `ExtensionPlatformInterface.swift:372-383` (line 427+: `clearDNSCache` exists; line 304/320: `semaphore.wait(timeout: .now() + 2.0)` для openTun-style semaphores — **уже c timeout**). Need to verify `clearDNSCache` specifically has timeout — original finding says no.
- **Refined fix:** add 2s timeout per semaphore wait in `clearDNSCache` (match `openTun`'s 2s pattern from Phase 6d M16 `5a4db9f`). Better: replace `DispatchSemaphore` with `withCheckedContinuation` (true async pattern).
- **Risk:** **LOW** — extension target; не трогает AppFeatures hot paths. NWPathMonitor concurrency intact.
- **Test impact:** PacketTunnelKitTests 61/61 should pass — adding timeout safer than removing.

#### L2 — Trojan WS-host fallback duplicates SNI substitution
- **Current state:** **STILL-APPLICABLE (with potential simplification).** Trojan `ConfigBuilder.swift:159-169` + `WSTransportHandler.swift:36-47` — both have "if WS host empty → substitute SNI" logic. Phase 6d M12 (`1621a08`) fixed VLESS+TLS sibling — duplicated pattern остаётся.
- **Refined fix:** introduce `sniFallback: String?` parameter в `WSTransportHandler.buildTransportBlock`. Move logic из Trojan ConfigBuilder в transport handler. All protocols benefit.
- **Risk:** **LOW-MEDIUM** — затрагивает 5 ConfigBuilders potentially. Existing `TrojanTests` / `VLESSTLSTests` 19+ должны pass; may need update if signature changes.
- **Test impact:** add `WSTransportHandlerTests.test_sniFallback_applied_when_host_empty()`. Cross-protocol regression coverage essential.

#### L3 — All localized strings eagerly initialized (104 `static let` triggered on first L10n access)
- **Current state:** **STILL-APPLICABLE.** L10n.swift contains many `static let` accessors (verification: grep returned no hits для что обычный pattern `static let x = tr(...)` is consistent; planner может verify via `grep -c "static let.*= L10n.tr"`).
- **Refined fix:** convert non-launch-critical keys в `static var x: String { tr("x") }` (lazy computed). Keep `static let` для frequently-accessed initial-render keys (e.g., `appName`, main button labels).
- **Risk:** **LOW** — localization-only; tested through LocalizationTests 3/3.
- **Test impact:** verify `LocalizationTests` 3/3 PASS; no functional change.

#### L4 — `MainScreenView.ImportProgressOverlay` conditional always evaluated в ZStack
- **Current state:** **STILL-APPLICABLE.** Verified `MainScreenView.swift:47-49` (lines 47-49 in post-6d HEAD):
  ```swift
  if viewModel.importInProgress {
      ImportProgressOverlay()
  }
  ```
  — внутри ZStack body; SwiftUI evaluates condition на каждом body refresh.
- **Refined fix:** wrap в `.overlay(viewModel.importInProgress ? ImportProgressOverlay() : nil)` modifier. SwiftUI dependency tracking treats `.overlay` smarter — re-eval triggered только when `importInProgress` changes.
- **Risk:** **LOW** — UI-only refactor. ImportProgressOverlay tests (if any) unaffected.
- **Test impact:** smoke-test via build success.

#### L5 — `UserNotificationsHelper.notifyReconnectFailed`/`notifySingleServerUnavailable` дублируют ~30 LOC
- **Current state:** **STILL-APPLICABLE.** Verified `UserNotificationsHelper.swift:37-80, 87-125` — два similarly-structured functions. Both Phase 6d-introduced, не trivial cleanup.
- **Refined fix:** extract `ensureAuthorized() async -> Bool` + `post(content:identifier:)` helpers. Maintainability win, не perf.
- **Risk:** **LOW** — helper file standalone; no callers depend on internal structure.
- **Test impact:** `UserNotificationsHelperTests` (if any) should still pass; no behavioural change.

#### L6 — `MainScreenView.connectionStartDate` computed на каждом body refresh
- **Current state:** **INVALIDATED — Phase 6d H5 fix `5ef3888` indirectly resolved.**
- **Evidence:** Verified `MainScreenView.swift:152, 162-165` (post-6d):
  - Line 152: `ConnectionTimer(since: connectionStartDate)` — still called.
  - Line 162-165: `private var connectionStartDate: Date?` — computed property.
  - **Original Opus #22 concern:** ConnectionTimer had Timer.publish kept alive in `.disconnected`, causing 60×/min body refresh → 60×/min connectionStartDate recompute.
  - **Phase 6d H5 fix:** ConnectionTimer now conditional — ticks only когда `isConnected`. Body refresh frequency на idle screens dropped к user-driven только.
  - **Net effect:** connectionStartDate now computed rarely (only on real state changes). Optimization is no-op in disconnected state; minor in connected state (computed once per visible tick).
- **Refined fix:** **None.** L6 should be downgraded к "Subsumed by H5". Document.
- **Risk:** N/A.
- **Test impact:** N/A.

#### L7 — `ServerListSheet.estimatedSheetHeight` O(n) на каждом body refresh
- **Current state:** **STILL-APPLICABLE.** Verified `ServerListSheet.swift:45-55` (post-6d HEAD):
  - Lines 45-55: `private var estimatedSheetHeight: CGFloat` computed property — iterates через `viewModel.sections` summing heights.
  - При body refresh (SwiftUI re-diff) — повторно computed.
- **Refined fix:** `@State var detents: Set<PresentationDetent> = [.large]`; update via `.onChange(of: viewModel.sections)` → recompute height.
- **Risk:** **LOW** — UI refactor; sections list update flow already exists.
- **Test impact:** smoke-test sheet opens with correct detent на 1 / 10 / 50-сервер pools.

#### L8 — `QRScannerViewController.session.startRunning()` на `.userInitiated` GCD
- **Current state:** **STILL-APPLICABLE.** Verified `QRScannerViewController.swift:40, 117`: `DispatchQueue.global(qos: .userInitiated).async`.
- **Refined fix:** change to `.userInteractive` per Apple WWDC sample (AVCaptureSession setup).
- **Risk:** **LOW** — QR scanner UI; performance improvement только.
- **Test impact:** manual smoke (not blocked by no-UAT decision; QR scanning ortogonal to Phase 6c/6d invariants).

#### L9 — `dismissReconnectBanner` cannot dismiss `.failover` banner — sticky in `.connected`
- **Current state:** **STILL-APPLICABLE.** Verified `MainScreenViewModel.swift:368-389`. Failover banner sticky logic remains.
- **Refined fix:** add 5s TTL Task в `showFailoverBanner(toServerName:)` — auto-dismiss after 5s if state still `.connected`.
- **Risk:** **LOW-MEDIUM** — touches reconnectBannerState mutation. **MUST not regress R18 (Phase 6c)** — failover banner is part of reactive UI driver; verify через swift test.
- **Test impact:** add `test_showFailoverBanner_auto_dismisses_after_5s()`.

#### L10 — `TunnelWatchdog.fireFailover` calls observer AFTER attempt succeeds
- **Current state:** **STILL-APPLICABLE.** Verified `TunnelWatchdog.swift:250-265` (post-6d) — observer fired **after** `try await next.attempt()`. Recommendation: fire observer **before** awaiting attempt — UI sees pending failover immediately.
- **Refined fix:** reorder. Fire `await observer(next.serverName)` **before** `_ = try await next.attempt()`. If attempt throws, banner stays visible briefly (acceptable UX trade-off).
- **Risk:** **MEDIUM** — TunnelWatchdog is Phase 6c-validated. Carefully verify no D-09 invariant impact.
- **Test impact:** add `TunnelWatchdogTests.test_failoverObserver_fired_before_attempt()`.

#### L11 — `applyAutoReconnectToManager` posts notification PER MANAGER
- **Current state:** **STILL-APPLICABLE.** Verified `SettingsViewModel.swift:185-194` (`BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`):
  ```swift
  for manager in ours {
      OnDemandRulesBuilder.applyCurrentState(to: manager)
      do {
          try await manager.saveToPreferences()
          try await manager.loadFromPreferences()
          NotificationCenter.default.post(name: .bbtbProvisionerDidSave, object: manager)
      } catch { ... }
  }
  ```
  — `post` inside for-loop. Multiple managers → multiple notifications (rare on production — обычно ours.count == 1, но possible).
- **Refined fix:** post notification ONCE outside for-loop, after all saves complete. `object: ours.first` (or `nil` + document multi-manager case).
- **Risk:** **MEDIUM** — `bbtbProvisionerDidSave` consumed by `TunnelController.provisionerObserver` (line 577) — refresh cachedManager. Reducing notification count from N to 1 changes timing semantics. Verify TunnelController observer behaviour with multi-manager edge case.
- **Test impact:** add `SettingsViewModelTests.test_applyAutoReconnectToManager_posts_notification_once()`.

#### L12 — Pre-expand `SingBoxConfigLoader.validate(json:)` redundant
- **Current state:** **STILL-APPLICABLE — RELATED TO M8.**
- **Evidence:** Same code path as M8 (lines 156-164). L12 = LOW-tier version of M8's MEDIUM concern.
- **Refined fix:** **Bundle with M8 fix** — if M8 implements `validatedAt` timestamp guard, L12 automatically resolved. Separate L12 fix не нужен.
- **Risk:** **NONE separately** — same surface as M8.
- **Test impact:** **Bundle with M8.**

#### L13 — 5 `JSONSerialization.data(... .prettyPrinted)` writeback calls add bytes к providerConfiguration
- **Current state:** **STILL-APPLICABLE.** Verified `grep -n "prettyPrinted"` (6 hits total — finding said 5):
  - `Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift:79`
  - `Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift:128, 168` (2 calls)
  - `Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:90`
  - `Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift:98`
  - `Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift:88`
- **Refined fix:** replace `.prettyPrinted` with `[]` (no options). Save ~30% bytes per config (whitespace + indents). Functionally equivalent — sing-box doesn't care about JSON formatting.
- **Risk:** **LOW** — JSON output not consumed by tests as-string (parsed back to dict). Production sing-box consumer parses JSON regardless of formatting.
- **Test impact:** ConfigBuilder tests should pass — but if any test does `XCTAssertEqual` on raw JSON string with pretty formatting, that test breaks. **Need to audit:** `grep -rn "prettyPrinted" Tests/`.

#### L14 — `runIsSupportedUpgrade` uses `print()` вместо OSLog
- **Current state:** **STILL-APPLICABLE.** Verified `ConfigImporter.swift:1010`: `print("runIsSupportedUpgrade: upgraded \(upgradedCount)/\(candidates.count) servers")`.
- **Refined fix:** replace с `Logger(subsystem: "app.bbtb.client", category: "importer-upgrade").info(...)`.
- **Risk:** **NONE** — logging-only.
- **Test impact:** `ConfigImporterTests` — if test captures print output, swap to logger. Otherwise no impact.

#### L15 — `TunnelLogger.lifecycle.notice` formats string на каждом `autoDetectControl` (thousands/min)
- **Current state:** **STILL-APPLICABLE.** Verified `ExtensionPlatformInterface.swift:241, 252, 277, 335`: `.notice` and `.info` levels.
- **Refined fix:** downgrade `autoDetectControl` per-call logs к `.debug` (filterable by `log stream --predicate 'category=="lifecycle" && type >= "info"'`). Keep `.error` for diagnostic.
- **Risk:** **LOW** — logging-only; observability trade-off documented.
- **Test impact:** PacketTunnelKitTests not affected.

#### L16 — `MainScreenViewModel.applyVPNStatus` switch 70 LOC, 3 nested matches — fragile maintenance
- **Current state:** **STILL-APPLICABLE.** Verified `MainScreenViewModel.swift:410-487` (post-6d). 78 LOC, 3 nested switches.
- **Refined fix (Opus #35):** extract pure `reduceState(_:Date?) -> MainScreenState` + `reduceBanner(_:Date?) -> ReconnectBannerState`. Unit test each.
- **Risk:** **MEDIUM-HIGH** — applyVPNStatus is D-09 single-authority. **REFACTOR is high-risk** — extraction must preserve byte-exact behaviour. Code reviewer mode (mcp__codex__codex sandbox=read-only) recommended before commit per CONTEXT.md D-06.
- **Test impact:** all existing AppFeatures tests must pass. Add unit tests for `reduceState` / `reduceBanner` covering all 16 status × current-state combinations.

#### L17 — `TunnelController.handleStatusChange` re-refreshes cachedManager (XPC) для intent-close check
- **Current state:** **STILL-APPLICABLE — BUT touches Phase 6d post-fix code.**
- **Evidence:** Verified `TunnelController.swift:684-727` (post-6d). Phase 6d post-fix `bc7bc26` added `userIntendedConnected` guard, which means current code calls `refreshCachedManager` only когда intent-closing path enters. Original Opus #36 concern about excessive XPC was real PRE-Phase 6d, now mitigated.
- **Evidence (additional):** `refreshCachedManager` called в `handleStatusChange` path only at line 295-314 в old version; in current `handleStatusChange` (lines 684-727), explicit `refreshCachedManager()` call absent — cachedManager state read via `cachedManager?.isEnabled` (synchronous property read on actor; no XPC).
- **Refined fix:** **Reduced scope.** Original L17 Opus #36 fix ("debounce refresh") мостмыслен. Current concern: handleStatusChange does ≥ 1 XPC trip via `await watchdog?.handleStatusChange(...)` AND читает cached manager — но это **not** extra XPC. **Researcher recommendation:** downgrade L17 to "Subsumed by Phase 6d post-fix `bc7bc26` (userIntent guard) + edge dedupe (`1467328`)". Document.
- **Risk:** N/A if downgraded.
- **Test impact:** N/A if downgraded.

#### L18 — `MainScreenViewModel` retains `serverListViewModel` strong
- **Current state:** **STILL-APPLICABLE.** Verified `MainScreenViewModel.swift:97`: `public let serverListViewModel: ServerListViewModel?` — strong reference; created в init (lines 138-173). Not lazy.
- **Refined fix:** make `serverListViewModel` lazy (`private(set) lazy var`); instantiate on first `presentServerList()` или first access.
- **Risk:** **LOW** — VM lifecycle is App-scoped (single MainScreenViewModel exists), so lazy саveing memory только до first list-open. Minor optimization.
- **Test impact:** `MainScreenViewModelTests` covering coordinator wiring (line 252: `serverListViewModel?.coordinator = self`) — need to ensure lazy init triggers wiring on first access.

#### L19 — `ServerListSheet.confirmationDialog.message` always captures `pendingDeleteSubscriptionServerCount`
- **Current state:** **INVALIDATED — Phase 6d H7 fix `b8d9294` indirectly resolved.**
- **Evidence:** Phase 6d H7 closed `pendingDeleteSubscriptionServerCount` fetches all rows on every body refresh. Property now cached `@Published`. Subsequent captures (including `.confirmationDialog.message`) — constant-time read.
- **Refined fix:** **None.** Downgrade к "Subsumed by H7". Document.
- **Risk:** N/A.
- **Test impact:** N/A.

#### L20 — Failed `commandServer.start()` leaves partially initialized objects
- **Current state:** **STILL-APPLICABLE.** Verified `BaseSingBoxTunnel.swift:147 → catch block at line 200-204`:
  ```swift
  } catch {
      TunnelLogger.lifecycle.error("startTunnel: commandServer.start failed: \(error.localizedDescription)")
      endLibboxStart()
      completionHandler(TunnelError.commandServerStartFailed(error)); return
  }
  ```
  — НЕ закрывает `server` (already assigned to `self.commandServer = server` line 194). Codex #17 finding.
- **Refined fix:** в catch: `server.close()` (defensive), set `commandServer = nil`, `platformInterface = nil`.
- **Risk:** **LOW** — extension-only; error path code.
- **Test impact:** PacketTunnelKitTests — if any test simulates `server.start()` failure (likely not), update accordingly.

---

### Trivial unused imports (3)

Per `06D-PERIPHERY-POST-FIX.md` — **AUDIT-VERIFIED 2026-05-14 against post-6d HEAD `584fcbd`:**

| File:Line | Import | Action | Verification |
|-----------|--------|--------|--------------|
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift:18` | `import ConfigParser` | **DELETE** | Confirmed present; no ConfigParser type referenced in file (per Periphery scan). |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift:26` | `import ConfigParser` | **DELETE** | Confirmed present; no ConfigParser type referenced in file. |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift:9` | `import DesignSystem` | **DELETE** | Confirmed present; `DS.*` types used inline (computed via own `DesignSystem` reference chain), but no top-level DesignSystem type referenced. |

**Recommended sed pattern** (for executor):
```bash
# Trivial — exact-line removal of 3 import lines.
# Use sed -i '' with line numbers, or just edit files individually.
```

**Risk:** **NONE** — Periphery scan confirms zero references. Build must succeed without imports.

**Test impact:** AppFeatures swift test 133/133 + iOS xcodebuild + macOS xcodebuild — full regression gate.

---

## Section 1 Summary Table

| ID | Severity | Current State | Action |
|----|----------|---------------|--------|
| M6 | MEDIUM | INVALIDATED (Phase 6d post-fix `1467328` + `9b38796`) | DOWNGRADE: document only |
| M7 | MEDIUM | STILL-APPLICABLE | Atomic fix: consolidate scenePhase tasks |
| M8 | MEDIUM | STILL-APPLICABLE | Atomic fix: validatedAt timestamp guard (preserves R10) |
| M10 | MEDIUM | STILL-APPLICABLE (undercount: 6 calls, not 4) | Atomic fix: collapse confirmDeleteSubscription + idempotency guard |
| M11 | MEDIUM | PARTIALLY-ADDRESSED (Phase 6d `9b38796`) | Atomic fix (cosmetic): explicit early-return guard |
| M15 | MEDIUM | INVALIDATED (Phase 6d H4 `55bde6c`) | DOWNGRADE: document only |
| L1 | LOW | STILL-APPLICABLE | Bundle: cleanup-correctness |
| L2 | LOW | STILL-APPLICABLE | Bundle: cleanup-maintainability |
| L3 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L4 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L5 | LOW | STILL-APPLICABLE | Bundle: cleanup-maintainability |
| L6 | LOW | INVALIDATED (Phase 6d H5) | DOWNGRADE: document only |
| L7 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L8 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L9 | LOW | STILL-APPLICABLE | Bundle: cleanup-correctness |
| L10 | LOW | STILL-APPLICABLE | Bundle: cleanup-correctness |
| L11 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L12 | LOW | STILL-APPLICABLE (related to M8) | Bundled WITH M8 fix |
| L13 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L14 | LOW | STILL-APPLICABLE | Bundle: cleanup-maintainability |
| L15 | LOW | STILL-APPLICABLE | Bundle: cleanup-maintainability |
| L16 | LOW | STILL-APPLICABLE (high-risk extraction) | Bundle: cleanup-maintainability (code reviewer mode recommended) |
| L17 | LOW | INVALIDATED (Phase 6d post-fix `bc7bc26` + `1467328`) | DOWNGRADE: document only |
| L18 | LOW | STILL-APPLICABLE | Bundle: cleanup-perf |
| L19 | LOW | INVALIDATED (Phase 6d H7) | DOWNGRADE: document only |
| L20 | LOW | STILL-APPLICABLE | Bundle: cleanup-correctness |
| Trivial-1 | trivial | STILL-APPLICABLE | Bundle: trivial-imports |
| Trivial-2 | trivial | STILL-APPLICABLE | Bundle: trivial-imports |
| Trivial-3 | trivial | STILL-APPLICABLE | Bundle: trivial-imports |

**Totals:**
- **DOWNGRADED (no code change):** 5 (M6, M15, L6, L17, L19)
- **ATOMIC MEDIUM fixes (Wave 1):** 4 (M7, M8 with L12, M10, M11)
- **LOW bundled fixes (Wave 2):** 14 still-applicable LOW (L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L16, L18, L20) — actually 16 still-applicable LOW. Researcher miscounted above. Let me re-verify:
  - L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L16, L18, L20 = **16 still-applicable LOW**. L12 bundled с M8. L6, L17, L19 = 3 INVALIDATED. **Sum = 16 + 1 (L12 bundled) + 3 (INVALIDATED) = 20 ✓**.
- **TRIVIAL bundle (Wave 2):** 3 imports.

---

## Section 2: LOW Theming Proposal

> 16 still-applicable LOW findings organized in 4 themed bundles. Each theme = 1 commit. Single regression gate в конце всего Wave 2 (per D-04).

### Theme A — cleanup-perf (UI / energy minor wins)
**Findings (6):** L3, L4, L7, L8, L11, L13, L18.

Wait — let me recount. Going through the matrix:
- L3 — L10n lazy: **perf**.
- L4 — ImportProgressOverlay modifier: **perf** (body refresh reduction).
- L7 — estimatedSheetHeight @State: **perf** (avoid O(n) on body diff).
- L8 — QR session qos: **perf** (cold-start of QR).
- L11 — applyAutoReconnectToManager notification once: **perf**.
- L13 — prettyPrinted → []: **perf** (binary footprint).
- L18 — serverListViewModel lazy: **perf** (memory).

= **7 findings.** Bundle commit: `chore(06e): batch perf-cleanup — L3/L4/L7/L8/L11/L13/L18`.

**Rationale:** все 7 = minor UI / memory / startup optimizations с zero functional impact. Logical bundle.
**Risk surface:** L11 touches `bbtbProvisionerDidSave` consumer chain — TunnelController.provisionerObserver (line 577). Code reviewer mode recommended. Other 6 — completely orthogonal local refactors.
**Recommended commit boundary:** один commit. Если L11 raises concern в review — split в `chore(06e): batch perf-cleanup (6 minor)` + `chore(06e): consolidate provisioner notification (L11)`.

### Theme B — cleanup-correctness (error path / timing fixes)
**Findings (4):** L1, L9, L10, L20.

- L1 — clearDNSCache timeout / continuation: extension correctness.
- L9 — failover banner TTL: UI correctness.
- L10 — TunnelWatchdog observer-before-attempt: timing correctness.
- L20 — commandServer.start catch: error path correctness.

**Rationale:** все 4 = correctness fixes с potential user-visible impact. Logical bundle.
**Risk surface:** L9 + L10 touch reactive UI driver и Watchdog actor. **Phase 6c R18 sliding-window invariant MUST be preserved** — failover banner UI behaviour is part of R18 reactive driver. Wave 2 single regression gate caught regressions; but for L9/L10 consider mini-gate (swift test only) ПОСЛЕ их fix внутри bundle commit body. Per D-04 — single gate в конце bundle acceptable, но researcher recommends extra rigor для этих.
**Recommended commit boundary:** один commit OR split L9+L10 (UI reactive driver) от L1+L20 (extension-side).

### Theme C — cleanup-maintainability (refactor / extractions / dead code)
**Findings (5):** L2, L5, L14, L15, L16.

- L2 — WS-host fallback unification (cross-protocol): maintainability.
- L5 — UserNotificationsHelper dedup: maintainability.
- L14 — print() → OSLog: maintainability + observability.
- L15 — autoDetectControl log level downgrade: observability.
- L16 — applyVPNStatus extraction `reduceState`/`reduceBanner`: maintainability (HIGH RISK).

**Rationale:** все 5 = code quality / readability refactors.
**Risk surface:** **L16 is HIGH RISK** — applyVPNStatus is D-09 single-authority (Phase 6c R18). **Recommendation: SPLIT L16 в отдельный commit.** Submit L16 для code reviewer mode (mcp__codex__codex, sandbox=read-only) перед commit per CONTEXT.md D-06.
**Recommended commit boundary:** **SPLIT** в 2 commits:
- `chore(06e): batch maintainability-cleanup — L2/L5/L14/L15` (4 findings, low risk).
- `refactor(06e): extract reduceState/reduceBanner from applyVPNStatus (L16)` (1 finding, high risk, требует code reviewer mode).

### Theme D — cleanup-trivial-imports
**Findings (3 trivial unused imports):**
- `ServerDetailView.swift:18` — `import ConfigParser`
- `ServerListSheet.swift:26` — `import ConfigParser`
- `TransportPicker.swift:9` — `import DesignSystem`

**Rationale:** **per D-04 last bullet** — "3 trivial unused imports → один single commit".
**Risk surface:** zero (Periphery-verified false-zero-references).
**Recommended commit boundary:** один commit: `chore(06e): remove 3 unused imports (Periphery audit)`.

---

### Section 2 Summary: 4 Themes → 5 Commits (with L16 split)

| Theme | Findings | Commits |
|-------|----------|---------|
| A — cleanup-perf | L3, L4, L7, L8, L11, L13, L18 (7) | 1 |
| B — cleanup-correctness | L1, L9, L10, L20 (4) | 1 (или split → 2 if L9+L10 prefer extra gate) |
| C — cleanup-maintainability | L2, L5, L14, L15 (4) + L16 split | **2** (1 for L2/L5/L14/L15; 1 for L16 after code reviewer) |
| D — cleanup-trivial-imports | 3 imports | 1 |
| **TOTAL Wave 2 commits** | **18 finding-actions** | **5 commits** |

**Final regression gate:** runs ONCE after Theme A + Theme B + Theme C (both commits) + Theme D commits land. Per D-04. iOS xcodebuild + macOS xcodebuild + AppFeatures swift test 133/133 + D-09 grep audit.

---

## Section 3: Execution Order Recommendation

### Wave 1 — 4 atomic MEDIUM fixes (atomic commit + per-commit regression gate)

**Sequencing rationale:** order by **escalating risk surface**. Run regression gate after each commit.

1. **M7** (consolidate scenePhase tasks) — **lowest risk**.
   - Touches: `BBTB_iOSApp.swift`, `MainScreenView.swift`, `MainScreenViewModel.swift` (add new method).
   - Risk surface: ZERO grep regressions; no D-09 / DEC-06d invariant touch.
   - Regression gate: AppFeatures 133/133 + iOS + macOS xcodebuild.

2. **M10** (loadFromStore idempotency + confirmDeleteSubscription collapse) — **low risk**.
   - Touches: `ServerListViewModel.swift` (1 file).
   - Risk surface: ZERO D-09 / DEC-06d invariant touch.
   - Regression gate: AppFeatures 133/133 + iOS + macOS xcodebuild.

3. **M8** (validatedAt timestamp guard, bundled with L12) — **medium-HIGH risk** (R10 defense-in-depth).
   - Touches: `BaseSingBoxTunnel.swift`, `ConfigImporter.swift` (in AppFeatures).
   - Risk surface: R10 / R1 / SEC-06 — post-expand validate MUST stay. **Code reviewer mode recommended.**
   - Regression gate: AppFeatures 133/133 + PacketTunnelKit 61/61 + iOS + macOS xcodebuild + grep `SingBoxConfigLoader.validate` confirmation.

4. **M11** (explicit early-return guard) — **medium risk** (D-09 applyVPNStatus authority).
   - Touches: `MainScreenViewModel.swift` (3 lines).
   - Risk surface: D-09 single-authority — preserved (cosmetic guard); existing `lastAppliedVPNStatus` dedupe in `9b38796` provides safety net.
   - Regression gate: AppFeatures 133/133 (especially AutoSelectIntegrationTests) + iOS + macOS xcodebuild.

**M6 & M15 — NO commit needed.** Document как "Subsumed by Phase 6d" в `06E-Final-SUMMARY.md`.

### Wave 2 — LOW bundles + trivial imports (single final regression gate)

5. **Theme A commit:** `chore(06e): batch perf-cleanup — L3/L4/L7/L8/L11/L13/L18`.
6. **Theme B commit:** `chore(06e): batch correctness-cleanup — L1/L9/L10/L20`.
7. **Theme C-1 commit:** `chore(06e): batch maintainability-cleanup — L2/L5/L14/L15`.
8. **Theme C-2 commit:** `refactor(06e): extract reduceState/reduceBanner from applyVPNStatus (L16)` — **after code reviewer mode review**.
9. **Theme D commit:** `chore(06e): remove 3 unused imports (Periphery audit)`.

**Single regression gate** AFTER Wave 2 last commit: AppFeatures 133/133 + iOS + macOS xcodebuild + D-09 forbidden symbols grep + Periphery scan (verify 3 actionable imports → 0).

### Wave 3 — Closure

10. **D-05a final grep audit** — verify Phase 6c invariants intact (`06D-INVARIANT-AUDIT.md` patterns applied to post-6e baseline).
11. **`06E-Final-SUMMARY.md` write** — compact narrative (5 downgraded + 20 actually-fixed across 4+5 commits + downgrade rationale per finding).
12. **Wiki sync** — `wiki/performance-baseline.md` § Open follow-ups → "26 closed in Phase 6e" + new "Open follow-ups (post-6e)" section if anything carried over (researcher: nothing should carry over — Phase 6e closes ALL 26).
13. **STATE.md, ROADMAP.md, REQUIREMENTS.md** sync — Phase 6e → ✓ Closed; QUAL-04..05 → Validated (if planner chose to add).
14. **`wiki/log.md`** — closure entry.

---

## Section 4: Architectural Invariant Map

### Per-DEC-06d Invariant — Risk Cross-Reference

| Invariant | Findings That Touch | Pre-Fix Grep Guard | Post-Fix Grep Audit |
|-----------|---------------------|--------------------|---------------------|
| **DEC-06d-01** (cold-start init defer) | M7 (scenePhase tasks consolidation — defer pattern preserved) | grep `Task.detached.*priority:.*background\|utility` in `BBTB_iOSApp.swift` ≥ 2 | Same; ≥ 2 expected. |
| **DEC-06d-02** (XPC consolidation ≤ 2 trips) | M7 (handleForeground 1 XPC), M11 (no new XPC) | grep `await NETunnelProviderManager.loadAllFromPreferences()` in TunnelController + MSVM ≤ 4 total | Same count expected. |
| **DEC-06d-03** (event-driven status polling) | M11 (applyVPNStatus authority); L9/L10 (failover) | grep `Task.sleep` in TunnelController = 0 OR justified | Same; no `sleep`-based loops added. |
| **DEC-06d-04** (bounded probe concurrency) | M15 (already closed by H4); no new findings touch | grep `maxConcurrentProbes` in ServerProbeService = 1; value = 8 | Same. |
| **DEC-06d-05** (Apple-canonical options + ExternalVPNStopMarker) | None of 26 findings touch | grep `options\["manualStart"\]` in TunnelController + BaseSingBoxTunnel = 2 | Same count. |
| **DEC-06d-06** (PerfSignposter spans) | None of 26 findings touch | grep `PerfSignposter` usages ≥ 25 (Phase 6d baseline) | Same. |

### Per-D-09 Invariant — Risk Cross-Reference

| D-09 Invariant | Findings That Touch | Pre-Fix Grep | Post-Fix Grep |
|----------------|---------------------|--------------|---------------|
| Forbidden symbols (RSM / NetworkReachability / ReconnectStateObserverRelay) ≤ 7 | None of 26 findings touch | `grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay" BBTB --include="*.swift"` ≤ 7 | Same count expected (baseline = 4). |
| Observer queue=`.main` for NEVPN = 0 | M11 (applyVPNStatus authority) — but doesn't touch observer registration | `grep -rn "NEVPNStatusDidChange.*queue:.*\.main" BBTB --include="*.swift"` = 0 | Same. |
| `#Predicate UUID?` resurrection = 0 (1 comment hit acceptable) | M10 (loadFromStore — uses FetchDescriptor; verify no `#Predicate UUID?` added) | `grep -rn "#Predicate.*UUID?" BBTB --include="*.swift"` ≤ 1 (comment-only) | Same. |
| `applyVPNStatus` single authority | M11 (cosmetic guard), L16 (extraction — HIGH RISK) | `grep -n "applyVPNStatus" MainScreenViewModel.swift` — 1 definition + N callers | Same definition signature; same caller count (1 init seed + 1 observer + 1 apply snapshot). |
| Sliding window `toggle && intent` single source-of-truth | None of 26 findings touch | `grep -n "toggle && intent" OnDemandRulesBuilder.swift` = 1 (line 113) | Same. |

### Final Grep Audit Pattern (Wave 3 step 10)

Run before Phase 6e closure commit:

```bash
# 1. Forbidden symbols
grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay" BBTB/Packages BBTB/App --include="*.swift" | grep -v "^.*://" | wc -l
# Expected: 4 (baseline; comments-only).

# 2. NEVPN .main queue
grep -rn "NEVPNStatusDidChange.*queue:.*\.main\)\|OperationQueue\.main" BBTB --include="*.swift" | wc -l
# Expected: 0.

# 3. #Predicate UUID?
grep -rn "#Predicate.*UUID?" BBTB --include="*.swift" | wc -l
# Expected: 1 (comment in ConfigImporter:179).

# 4. applyVPNStatus single authority
grep -n "func applyVPNStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift | wc -l
# Expected: 1.

# 5. Sliding window source
grep -n "toggle && intent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l
# Expected: 2 (line 68 comment + line 113 code).

# 6. PerfSignposter preservation
grep -rn "PerfSignposter" BBTB --include="*.swift" | grep -v Tests | wc -l
# Expected: ≥ 25 (Phase 6d baseline).

# 7. ExternalVPNStopMarker semantics
grep -rn "ExternalVPNStopMarker" BBTB --include="*.swift" | grep -v Tests | wc -l
# Expected: same count as post-Phase-6d (peek-only API preserved).

# 8. Periphery delta
cd BBTB && tuist generate --no-open && periphery scan \
    --project BBTB.xcworkspace --schemes BBTB --retain-public \
    --report-exclude '**/Tests/*.swift' --exclude-tests --disable-update-check
# Expected: 34 warnings (37 baseline − 3 trivial imports removed). All remaining false-positive.
```

---

## Section 5: Open Questions for Planner

### Q1: Should "downgraded" findings still appear в `06E-Final-SUMMARY.md`?

**Recommendation:** YES. Per D-07 PASS criterion 1 — "Все 26 carved findings либо closed (commit SHA), либо explicitly downgraded к 'permanently accepted' (with rationale в SUMMARY)." Downgraded findings (M6, M15, L6, L17, L19) — это "subsumed-by-6d-fix" category, не "permanently accepted", но per D-07 spirit — каждое finding должно быть accounted. SUMMARY должно содержать per-finding row для всех 26 (даже если "no code change в 6e").

### Q2: L11 (`bbtbProvisionerDidSave` notification once-per-applyAutoReconnect) — bundle or atomic?

**Concern:** L11 touches a Phase 6c-validated notification contract. TunnelController.provisionerObserver (line 577) consumes this notification.
**Risk:** moving from N notifications → 1 notification changes timing semantics в edge case `ours.count > 1` (multiple BBTB managers — rare but possible).
**Researcher recommendation:** **bundle с Theme A (cleanup-perf)** for commit boundary; но planner может split в separate commit с per-commit gate если concerned. Either choice is acceptable per D-04.

### Q3: L16 (applyVPNStatus extraction) — выполнять в Phase 6e или defer?

**Concern:** applyVPNStatus is D-09 single-authority + Phase 6c R18 sliding-window invariant participant. Extracting `reduceState` + `reduceBanner` is **non-trivial refactor** (Opus #35 rated MEDIUM — not LOW — but downgraded by Phase 6d synthesis to LOW because cosmetic).
**Researcher recommendation:** **Execute в Phase 6e, with mandatory code reviewer mode review (mcp__codex__codex sandbox=read-only) prior to commit.** Per CONTEXT.md D-06 — code reviewer mode optional но recommended для complex cleanup. L16 точно соответствует "complex cleanup".
**Fallback:** if 2+ failed regression gate attempts на L16 → escalate к architect (mcp__codex__codex) per D-08, или defer L16 в Phase 6f с rationale в SUMMARY.

### Q4: Cross-platform PacketTunnelKit changes (M8, L1, L20) — verify on macOS path?

**Concern:** D-03 deferred macOS UAT replay к Phase 11/12. M8, L1, L20 touch PacketTunnelKit code path, which runs on BOTH iOS PacketTunnelExtension AND macOS PacketTunnelExtension targets.
**Researcher recommendation:** rely на `xcodebuild -scheme BBTB-macOS` regression gate alone. Functional UAT (real tunnel start on macOS) — deferred per D-03. **NOT a blocker.** Researcher confidence: source code identical between targets; static analysis (compilation) caught Phase 6d issues effectively.

### Q5: Should planner add new QUAL-04 / QUAL-05 requirements?

**Concern:** REQUIREMENTS.md has PERF-01..05 + QUAL-01..03 Validated; "новые QUAL-04..XX могут быть added в planning (TBD)".
**Researcher recommendation:** add **at planner discretion**. Suggested:
- **QUAL-04:** "Carved-out backlog Phase 6d (26 findings) полностью закрыт; baseline maximally clean перед Phase 7."
- **QUAL-05:** "Periphery dead-code scan на post-Phase-6e baseline: actionable count = 0 (down from 3 в Phase 6d closure)."

If planner skips — нет downside; Phase 6e closure proceeds via D-07 alone.

---

## Section 6: Validation Architecture (Nyquist)

> Per `.planning/config.json` — `workflow.nyquist_validation` not explicitly false; this section required.

### Test framework

| Property | Value |
|----------|-------|
| Framework | `swift-testing` (Apple Testing Library 1902) + XCTest (mixed; AppFeatures uses both) |
| Config file | `BBTB/Packages/AppFeatures/Package.swift` (test target declaration) |
| Quick run command | `swift test --package-path BBTB/Packages/AppFeatures` |
| Full suite command | All target packages: AppFeatures + VPNCore + ConfigParser + PacketTunnelKit + TransportRegistry + Localization + 5 Protocol packages |
| Cross-package macOS gate | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` |
| Cross-package iOS gate | `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` |
| Baseline (post-6d HEAD `584fcbd`) | **AppFeatures: 133/133 PASS in 7.20s** (verified 2026-05-14). |

### Phase Requirements → Test Map

| Req ID | Behaviour | Test Type | Automated Command | File Exists? |
|--------|-----------|-----------|-------------------|-------------|
| PERF-01..05 (regression) | Phase 6d performance patterns maintained | unit + integration | `swift test --package-path BBTB/Packages/AppFeatures` | ✅ (133 tests baseline) |
| QUAL-01 (D-09 invariants) | Phase 6c invariants preserved | grep audit | (See Section 4 Final Grep Audit) | ✅ (manual script) |
| QUAL-02 (multi-AI pattern) | N/A in Phase 6e (D-06: no 3-AI re-audit) | n/a | n/a | n/a |
| QUAL-03 (ExternalVPNStopMarker) | Apple-canonical options preserved | unit (PacketTunnelKitTests) + grep | `swift test --package-path BBTB/Packages/PacketTunnelKit` | ✅ |
| QUAL-04 (proposed: 26 findings closed) | per-finding state documented | research (this doc) + SUMMARY | researcher narrative + SUMMARY commit refs | ✅ (this doc — Section 1) |
| QUAL-05 (proposed: Periphery → 0 actionable) | scan result | tooling | `periphery scan ...` (Section 4 step 8) | ✅ (script) |

### Phase 6e-Specific Test Surfaces

For each MEDIUM fix:

| Finding | Existing test surface | NEW tests recommended |
|---------|----------------------|-----------------------|
| M7 (scenePhase consolidation) | none (scenePhase = integration-level) | `MainScreenViewModelTests.test_handleForegroundReentry_invokes_all_3_hooks_sequentially()` |
| M8 (validatedAt guard, with L12) | `PacketTunnelKitTests` 61/61 (R1/R10 invariants); `SingBoxConfigLoaderTests` если есть | `BaseSingBoxTunnelTests.test_pre_expand_validate_skipped_when_validatedAt_recent`, `_post_expand_validate_always_runs`, `_pre_expand_validate_runs_when_validatedAt_missing` |
| M10 (loadFromStore idempotency) | `ServerListViewModelTests` (if existing) | `test_confirmDeleteSubscription_calls_loadFromStore_once`, `test_loadFromStore_idempotency_guard_within_100ms` |
| M11 (early-return guard) | `AutoSelectIntegrationTests.test_selection_change_during_active_tunnel_reconnects` (Phase 6d post-fix-modified) | `test_applyVPNStatus_connecting_called_twice_state_stable` |

For LOW bundles:

| Bundle | Tests likely affected | NEW tests recommended |
|--------|----------------------|-----------------------|
| Theme A (perf) | LocalizationTests (L3); ConfigBuilderTests (L13 — audit for string-equality tests on prettyPrinted output) | none mandatory; L11 may benefit from `SettingsViewModelTests.test_applyAutoReconnectToManager_posts_notification_once` |
| Theme B (correctness) | TunnelWatchdogTests (L10) | `test_failoverObserver_fired_before_attempt` (L10); `test_showFailoverBanner_auto_dismisses_after_5s` (L9) |
| Theme C-1 (maintainability) | none | none mandatory |
| Theme C-2 (L16 extraction) | applyVPNStatus indirectly tested через 133 AppFeatures tests | `test_reduceState_all_combinations` (16 combinations: 4 statuses × 4 current states); `test_reduceBanner_all_combinations` |
| Theme D (trivial imports) | build success | n/a |

### Sampling Rate (Nyquist)

| Trigger | Test command | Frequency |
|---------|--------------|-----------|
| Per MEDIUM atomic commit (Wave 1) | AppFeatures swift test + iOS xcodebuild + macOS xcodebuild | 4× (per MEDIUM) |
| Per Wave 2 bundle commit | local quick (`swift build`; быстрое compile-only check optional) | optional, intra-bundle |
| Wave 2 final regression gate | Full suite (AppFeatures + VPNCore + PacketTunnelKit + ConfigParser + Localization + iOS xcodebuild + macOS xcodebuild) + D-09 grep audit (Section 4) + Periphery scan | 1× |
| Wave 3 (closure) final pre-merge | Full suite + grep audit | 1× |

### Wave 0 Gaps

**None.** Phase 6e не требует test framework setup — `swift-testing` + XCTest infrastructure уже установлена через Phase 6d. 133-test AppFeatures baseline ready.

**Optional new test files (per MEDIUM):**
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/HandleForegroundReentryTests.swift` (M7)
- `BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/ValidatedAtGuardTests.swift` (M8 + L12)
- `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/LoadFromStoreIdempotencyTests.swift` (M10)
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ApplyVPNStatusGuardTests.swift` (M11)
- `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReduceStateBannerTests.swift` (L16, if extraction goes ahead)

Planner може decide test file scope при создании PLAN.md.

### Failure Modes (Nyquist Dim 7)

| Failure mode | Detection |
|--------------|-----------|
| Regression in applyVPNStatus authority (M11, L16) | AppFeatures swift test, особенно AutoSelectIntegrationTests + 8k duplicate event coverage from Phase 6d post-fix |
| R10 defense-in-depth violation (M8) | PacketTunnelKit swift test; grep `SingBoxConfigLoader.validate` ≥ 2 sites; manual import-and-connect smoke (deferred к 11/12 per D-03) |
| SwiftData regression (M10) | AppFeatures + ServerListViewModelTests если существуют |
| D-09 forbidden symbol resurrection | Section 4 final grep audit |
| Phase 6c R18 sliding window regression | grep `toggle && intent` = 2 hits in OnDemandRulesBuilder.swift |
| ExternalVPNStopMarker semantics break (peek-only API) | grep `ExternalVPNStopMarker` — verify no new `.consume()` callers added |

### Validation (Nyquist Dim 8)

Final validation = Section 4 grep audit + full suite swift test + iOS + macOS xcodebuild + Periphery delta confirmation. Per D-07.

---

## Section 7: Out-of-Scope Confirmation

Per CONTEXT.md sections `<deferred>` + Section 5 D-02 / D-03 / D-06:

| Item | Status | Researcher verification |
|------|--------|------------------------|
| Numerical Instruments capture | DEFERRED к Phase 11/12 | ✅ Confirmed: not investigated in this RESEARCH; PerfSignposter spans (DEC-06d-06) preserved для future capture |
| macOS UAT replay (5 scenarios A/F-direct/F-reverse/Settings-disable/G) | DEFERRED к Phase 11/12 | ✅ Confirmed: not investigated; macOS xcodebuild regression gate adequate for cleanup-tier per D-03 rationale |
| NET-12 (active liveness probe) | Phase 7-8 carve-out | ✅ Confirmed: out of Phase 6e scope; not analyzed |
| 3-AI re-audit | NOT NEEDED (per D-06) | ✅ Confirmed: researcher used single-pass against post-6d code state; 0 new findings discovered (matches D-06 expectation) |
| Phase 7 readiness signal | Post-6e closure transition | ✅ Confirmed: not analyzed |
| Phase 6 historical UAT (A-I sub-tests) | Subsumed by Phase 6c/6d regression smoke | ✅ Acknowledged |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Periphery scan output из `06D-PERIPHERY-POST-FIX.md` reflects current HEAD `584fcbd` accurately. | Section 1 Trivial Imports | Если Periphery re-run даст different 3 imports — planner adjusts; low risk (re-scan trivial). |
| A2 | `BaseSingBoxTunnelTests` test file exists and covers pre/post-expand validate (verified в Phase 6d closure SUMMARY: PacketTunnelKit 61/61 PASS). | Section 1 M8 | Если testfile отсутствует — Wave 1 M8 fix должна добавить новый file; minor scope adjustment. |
| A3 | `SettingsViewModelTests` and `TunnelWatchdogTests` exist (referenced в 06D INVARIANT AUDIT). | Section 6 Phase 6e-Specific Test Surfaces | Low risk; new test files allowed per D-04. |
| A4 | Production users typically have `ours.count == 1` (single BBTB manager). Multi-manager edge case rare. | Section 1 L11 risk surface | If multi-manager common → L11 fix changes UX timing more visibly; surface через manual testing if Phase 6e adds it. |
| A5 | `loadFromStore` 6-call-site count в ServerListViewModel.swift reflects pullToRefresh lifecycle accurately. | Section 1 M10 | Confirmed via grep verification (lines 181, 224, 257, 282, 312, 323). High confidence. |
| A6 | Phase 6e не добавляет new D-09 invariants; preserves all from Phase 6c + 6d. | Section 4 | If new invariant emerges from research → planner updates. Researcher verified: no new invariants needed. |

**Confidence:** A1-A6 all HIGH (verified via grep / direct file inspection / cross-reference to Phase 6d artifacts). No `[ASSUMED]` claims persist беспроверки.

---

## Research Confidence Breakdown

| Area | Level | Reason |
|------|-------|--------|
| Current state assessment per finding (Section 1) | **HIGH** | Each finding verified via `grep` against post-6d HEAD `584fcbd`; file:line cross-referenced. |
| LOW theming proposal (Section 2) | **HIGH** | Logical groupings; researcher commit boundary recommendations align с D-04 hybrid rigor. |
| Execution order (Section 3) | **HIGH** | Risk-ascending order; matches Phase 6d 03a-h pattern. |
| Architectural invariant map (Section 4) | **HIGH** | Cross-referenced to Phase 6d `06D-INVARIANT-AUDIT.md` + verified all 7 invariants in Section 4. |
| Validation architecture (Section 6) | **HIGH** | swift test baseline confirmed (`133/133 PASS in 7.20s`). |

---

## Sources

### Primary (HIGH confidence)

- `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md` — phase scope decisions D-01..D-08
- `.planning/phases/06d-performance-audit/06D-FINDINGS.md` — 45 findings catalog (lines 50-106 для full table)
- `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md` — Phase 6d closure record + DEC-06d-01..06
- `.planning/phases/06d-performance-audit/06D-PERIPHERY-POST-FIX.md` — 37 Periphery warnings (3 actionable trivial imports)
- `.planning/phases/06d-performance-audit/06D-COMPARISON.md` — 19 closed Phase 6d findings (cross-reference base)
- `.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md` — D-09 grep audit patterns
- `wiki/performance-baseline.md` — DEC-06d-01..06 + Open follow-ups baseline
- `wiki/security-gaps.md` R18 + R19 + ExternalVPNStopMarker semantics
- `.planning/REQUIREMENTS.md` — PERF-01..05 + QUAL-01..03 Validated baseline
- `.planning/STATE.md` — Phase 6e Active state
- `.planning/ROADMAP.md` — Phase 6e entry (line 233+)

### Code references (HIGH confidence — direct grep / file inspection)

- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (lines 169, 222, 554, 577, 648-727)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` (lines 97, 138-173, 185, 205, 410-487)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` (lines 158-160, 233, 250-265)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` (line 1010 — print() L14)
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` (lines 130-160, 194-220)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` (lines 47-49, 79-85, 152, 162-165)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` (lines 26, 45-55, 87-103)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift` (line 18 — trivial import)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/TransportPicker.swift` (line 9 — trivial import)
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift` (lines 181, 224, 257, 282, 312, 323, 328)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/QRScannerViewController.swift` (lines 40-41, 117-118)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/UserNotificationsHelper.swift` (lines 37-80, 87-125)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` (lines 181-203)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift` (lines 90-250)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` (lines 113-130, 220-280, 304-335, 427)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift` (lines 114, 133-171)
- `BBTB/Packages/Protocols/*/Sources/*/ConfigBuilder.swift` (6 prettyPrinted hits — L13)

### Commit references (verified via `git log cf54d6f..HEAD`)

- Phase 6d Wave 03a-h (19 commits): `c2d54ea`..`b6996cb`
- Phase 6d post-fix cold-start UI freeze block (4 commits): `bc7bc26`, `1467328`, `9b38796`, `4983cab`
- Phase 6d post-fix Settings-disable saga (3 commits): `5110ae0`, `9122bbd`, `cff3f46`
- Final state: `584fcbd` (post-Phase-6d checkup)

### Tool verification (HIGH confidence)

- `swift test --package-path BBTB/Packages/AppFeatures` → **133/133 PASS in 7.199s** (verified 2026-05-14T13:38:35Z; baseline стабильна).

---

## Metadata

**Research date:** 2026-05-14
**Valid until:** 2026-05-28 (14 days; code state stable, no Phase 7 changes expected in this window).
**Researcher confidence:** HIGH overall.
**Open Questions:** 5 (Section 5) — all non-blocking; planner может proceed.

---

## RESEARCH COMPLETE
