---
phase: 06d-performance-audit
plan: Final-a
type: comparison
status: complete
date: 2026-05-14
mode: variant-d-no-instruments
findings_closed: 19
findings_carved_to_backlog: 26
phase_6d_start_sha: cf54d6f
phase_6d_end_sha: 8e6e660
---

# Phase 6d — Pre-fix vs Post-fix Comparison (Variant D, no Instruments baseline)

## Methodology note

Per user decision at **CHECKPOINT 1** (post-Wave-02b synthesis), Wave 06D-02c (pre-fix Instruments baseline на iPhone) был **skipped**. Comparison ниже — **descriptive** (что fix делает, какой expected user-visible delta), **не numerical**. Для numerical confirmation в будущем — снять baseline на физическом устройстве **сейчас** (post-fix), сравнить с future baseline после Phase 6e/больших изменений.

**Why no Instruments в Phase 6d:**
1. User scope priority — закрыть 19 findings до запуска UAT-цикла, не задерживаться на 6-12h Instruments capture.
2. Pre-fix delta невозможно зафиксировать numerically — все 19 fixes уже landed; нельзя «откатить и переснять» без потери backlog.
3. Numerical confirmation possible later — single capture на physical device post-Phase-6d даст baseline для будущих регрессий.

**What this document IS:** catalogue of all 19 closed findings + expected user-visible delta per fix + commit SHA mapping + regression gate evidence.

**What this document IS NOT:** numerical pre-vs-post Time Profiler / Allocations / Energy comparison table.

---

## Closed findings index — 19 commits (Phase 6d Option-B scope)

| ID | Title | Severity | Wave | Commit SHA | Type |
|---|---|---|---|---|---|
| H1 | `logLevel: trace` + `exportSingBoxLogToDocuments` Phase 5 leftover | HIGH | 03a | `8b7ff37` | Cold-start + Energy |
| H2 | Redundant XPC trips в `TunnelController.connect()` | HIGH | 03b | `8749985` | Connect-tap |
| H3 | Connect polling loop 1s false latency | HIGH | 03b | `decd7c4` | Connect-tap |
| H8 | `TunnelController.disconnect` 5s polling sleep | HIGH | 03b | `acd85fa` | Disconnect-tap |
| H4 | Auto-mode pre-connect probe blocks tap (Part 1) | HIGH | 03c | `55bde6c` | Connect-tap |
| H4 | Auto-mode pre-connect probe blocks tap (Part 2) | HIGH | 03c | `dca8e58` | Connect-tap |
| H5 | `ConnectionTimer` 1Hz Timer.publish alive when disconnected | HIGH | 03d | `5ef3888` | Energy + UI re-render |
| H7 | `pendingDeleteSubscriptionServerCount` fetches all rows | HIGH | 03d | `b8d9294` | Cold-start + UI re-render |
| H6 | `countSupportedConfigs()` materialization (residual) | HIGH | 03e | `1d035bb` | Cold-start |
| M2 | SwiftData Phase 3 migration sync в container | MEDIUM | 03e | `6c89996` | Cold-start (upgrade users) |
| M3 | `runIsSupportedUpgrade` parser allocation + scene-active trigger | MEDIUM | 03e | `1099629` | Cold-start + memory |
| M4 | `MainScreenViewModel.refresh()` N+1 SwiftData reads | MEDIUM | 03e | `684fb5a` | Cold-start |
| M5 | Sequential Keychain reads stall pool provisioning | MEDIUM | 03e | `99530f2` | Connect-tap |
| M1 | 6-8 fire-and-forget XPC tasks из cold start | MEDIUM | 03f | `cd4b297` | Cold-start XPC contention |
| H9 | NWPathMonitor `semaphore.wait` без timeout | HIGH | 03g | `37e7d34` | Connect correctness |
| M9 | `autoDetectControl` ignores `currentInterfaceIndex == 0` | MEDIUM | 03g | `42a908a` | Connect correctness |
| M16 | `openTun` 5s semaphore — reduce to 2s | MEDIUM | 03g | `5a4db9f` | Connect failure latency |
| M12 | VLESS+TLS WS-host fallback to SNI missing | MEDIUM | 03h | `1621a08` | Active connectivity bug |
| M13 | `pingAllServers` rows stuck в `.pinging` | MEDIUM | 03h | `61f60a3` | UI consistency |
| M14 | `OnDemandMigrationTask` posts `object: nil` | MEDIUM | 03h | `b6996cb` | Contract consistency |

**Total: 19 findings closed.** (8 HIGH × 9 actually closed because H4 split into 2 commits + 1 HIGH being H8 disconnect + H9 NWPath, + 10 MEDIUM.)

---

## Cold-start path (D-01 primary target)

Cold-start span `BBTB_iOSApp.init` → first SwiftUI render is the **primary D-01 dimension** в Phase 6d (см. `06D-CONTEXT.md` § Performance targets).

### Direct cold-start wins

| Finding | Wave | Mechanism | Expected user-visible delta |
|---------|------|-----------|------------------------------|
| **H1** | 03a | Удалён shipping `logLevel: trace` + remove `exportSingBoxLogToDocuments(_:)` call в App.init (был копирующий multi-MB sing-box log file в Documents синхронно при каждом cold-start). | **−200 to −500 ms** на cold start (file copy on main thread). +Energy savings (no continuous trace I/O в Release). |
| **M1** | 03f | 6+ fire-and-forget `Task { ... XPC ... }` в `BBTB_iOSApp.init` → 1 ordered `await TunnelController.bootstrap()` chain. | **−50 to −150 ms** Mach port contention. App responsiveness on first frame значительно лучше (no idle queue thrash). |
| **M2** | 03e | SwiftData Phase 3 migration (`migratePhase2ToPhase3`) deferred from `SwiftDataContainer.makeShared()` (sync на main thread) → background `Task.detached` с `priority: .utility`. | **−200 ms+** для upgrade users (Phase 2 → 3 migration runs once but blocked main thread). Fresh installs unaffected (no Phase 2 store). |
| **H6** | 03e | `countSupportedConfigs()` использовал `fetchDescriptor.fetch().count` (materializing all `ServerConfig` rows) → `fetchCount(fetchDescriptor)` (SQL `COUNT(*)`). | **−50 to −100 ms** на 50-сервер store. Quadratic improvement scaling с количеством servers. |
| **M4** | 03e | `MainScreenViewModel.refresh()` имел N+1 SwiftData reads (1 fetch all subscriptions + N fetches per subscription для server count) → inline `selectionReconcile` снижает N+1 до 1 fetch с group-by. | **−50 to −150 ms** на cold start + every subscription delta. Visible как «мгновенный» main screen. |
| **M3** | 03e | `runIsSupportedUpgrade` allocated `UniversalImportParser` per call (на scene-active trigger ×N rows + on cold start) → single shared instance + deferred from cold-start hot-path в `Task.detached` after first idle frame. | **−30 to −80 ms** cold-start. **Memory −2-5 MB** на cold start (parser internals не materialized на init). |

### Indirect cold-start wins (energy/re-render savings)

| Finding | Wave | Mechanism | Expected delta |
|---------|------|-----------|----------------|
| **H5** | 03d | `ConnectionTimer` had `Timer.publish(every: 1, on: .main)` constantly active (even when disconnected). Replaced with conditional publisher — ticks only when `isConnected`. | Reduced SwiftUI body diff на idle screens **−100% когда disconnected**. Lower battery drain on idle (auto-mode off). |
| **H7** | 03d | `pendingDeleteSubscriptionServerCount` was computed via SwiftData fetch-all on every body refresh. Cached as `@Published` property; recomputed only on data change. | No fetch-all during sheet animations. Smoother UI transitions. |

**Total expected cold-start improvement:** **−500 ms to −1100 ms** (conservative), depending on store size + upgrade-user vs fresh-install + cold cache state.

---

## Connect-tap path (D-01 primary target)

`TunnelController.connect()` → `.connected` status — primary actionable user-perceived latency.

### Direct connect-tap wins

| Finding | Wave | Mechanism | Expected delta |
|---------|------|-----------|----------------|
| **H2** | 03b | `TunnelController.connect()` делал 6 XPC trips (saveToPreferences + loadFromPreferences twice, isOnDemandEnabled mutation + save, ...). Consolidated в ≤ 2 trips через `applyCurrentStateToCachedManager()` single save+load. | **−200 ms+** на tap. Critical for D-01 perceived speed. |
| **H3** | 03b | Connect post-startVPNTunnel polling использовал 1s `sleep` loop ожидая `.connected` status (false latency baseline). Replaced with `AsyncStream<NEVPNStatus>` observer-stream + immediate fall-through on `.connected`. | **−800 ms** typical Wi-Fi connect (was bounded by `sleep(1s)` × retries; now event-driven). |
| **H4** | 03c | Auto-mode pre-connect probe (`pingAllServers` for ranking) blocked tap waiting for ALL servers ping completion. Part 1: bounded concurrency in `ServerProbeService.probeAll` (limit 8 simultaneous). Part 2: cached auto-mode snapshot fast path — connect uses cached ranking if recent (< 30s old). | **−500 ms to −1500 ms** on tap. Critical for D-01 на slow networks. |
| **M5** | 03e | `provisionTunnelProfile` читал 3-5 Keychain entries последовательно (`reuid`, `flow`, `serverName`, `port`, …). Refactored в parallel `TaskGroup` — все reads concurrent. | **−100 to −500 ms** для pool provisioning, especially on cold Keychain (after device unlock). |

### Connect-tap correctness fixes (perf + correctness)

| Finding | Wave | Mechanism | Expected impact |
|---------|------|-----------|------------------|
| **H9** | 03g | `NWPathMonitor.start()` followed by `semaphore.wait()` (no timeout) в extension. If callback never fired (NW kernel bug, exotic interface state) → extension hung indefinitely → tunnel stuck connecting → user-visible failure with no error. Added 2s bounded wait. | **Eliminates extension hang on missing NWPathMonitor callback.** Failed connect surfaces в ≤ 2s rather than indefinite. |
| **M9** | 03g | `autoDetectControl` accepted `currentInterfaceIndex == 0` (sentinel for "no interface"). Iterated socket creation in unbounded loop. Now: reject when no physical interface available. | **Eliminates unbound socket loop** on edge networks (airplane mode mid-transition). |
| **M16** | 03g | `openTun` semaphore timeout 5s → 2s. Faster failure surface allows retry to next server в failover chain. | **Faster failure → retry** chain. Helpful on poor Wi-Fi where one TUN socket open hangs while another would succeed. |

**Total expected connect-tap improvement:** **−1000 ms to −3000 ms** на typical Wi-Fi tap (auto-mode), depending on cached vs cold path + slow/poor network conditions.

---

## Disconnect-tap

| Finding | Wave | Mechanism | Expected delta |
|---------|------|-----------|----------------|
| **H8** | 03b | `TunnelController.disconnect()` polled `NEVPNStatus` waiting for `.disconnected` with `sleep(0.5s)` × 10 (fixed 5s window). Replaced с early-exit if `manager.connection.status == .disconnected` уже до polling start (common case в `applyCurrentStateToCachedManager → isOnDemandEnabled=false` path). | **−2500 ms** на immediate disconnect (when on-demand-disable already disconnected). For active VPN — equivalent поведение. |

---

## Energy

| Finding | Wave | Mechanism | Expected delta |
|---------|------|-----------|----------------|
| **H1** | 03a | Eliminated continuous `trace` log I/O в Release (was writing multi-line entries per packet). | **Significant battery savings.** Hard to quantify без Energy Log baseline, но trace logging известно как top-3 battery consumer для VPN apps. |
| **H5** | 03d | `ConnectionTimer` no longer ticks при `.disconnected` → no Timer.publish callbacks fire → no SwiftUI body diff cycle на idle screens. | **Lower GPU + main actor work** when app on idle screen (auto-mode disabled or manual mode disconnected). |

---

## Correctness fixes (non-perf, user-visible)

| Finding | Wave | Impact |
|---------|------|--------|
| **M12** | 03h | VLESS+TLS WS handler fell back to `host=server` when `&host=` query param omitted в connection string. **Was breaking active connectivity** for servers без explicit `&host=`. Now: fallback to SNI value (which is always set). |
| **M13** | 03h | `pingAllServers` was non-cancellation-safe — Task cancelled mid-stream left UI rows stuck в `.pinging` state forever (no `.completed` transition). Now: `defer { setPingStateCompleted }` in each row's task. |
| **M14** | 03h | `OnDemandMigrationTask` posted `bbtbProvisionerDidSave` with `object: nil` — contract drift vs other 3 emitters (всегда passed `manager`). Now: includes `manager` to maintain consumer API consistency. |

---

## Memory

| Finding | Wave | Mechanism | Expected delta |
|---------|------|-----------|----------------|
| H4 | 03c | Cached auto-mode snapshot replaces per-tap fetch + materialize ×N servers. | **Less peak memory** during connect-tap. |
| H6 | 03e | `fetchCount` vs `fetch().count` — SwiftData no longer materializes N `ServerConfig` objects for count. | **Less peak memory** на init + sheet open. |
| H7 | 03d | `pendingDeleteSubscriptionServerCount` cached — no fetch-all per body. | **Less peak memory** during sheet animations. |
| M4 | 03e | N+1 → 1 fetch in refresh. | **Less peak memory** на refresh. |
| M3 | 03e | `UniversalImportParser` singleton vs N instances. | **−2-5 MB** baseline. |

**Backlog (separate cleanup):** `serverListViewModel` lazy init in MainScreenViewModel — carved as **L18** в `06D-FINDINGS.md`. Не Phase 6d scope.

---

## Backlog summary (26 carved-out findings)

Phase 6d closed 19 of 45 originally-triaged findings (см. `06D-FINDINGS.md` Wave 02b synthesis). Remaining 26 — carved to backlog для future cleanup waves:

| Severity | Count | IDs |
|---|---|---|
| MEDIUM (carved) | 6 | M6, M7, M8, M10, M11, M15 |
| LOW | 20 | L1-L20 |

Все 26 finding документированы в `06D-FINDINGS.md` (git-tracked) с file:line + fix recommendation + rationale почему carve-out. Можно вернуться через отдельную **Phase «Performance Audit Round 2»** или, если low-effort, через `wiki/performance-baseline-followup.md` (Phase 6d Wave Final-b создаст этот placeholder).

**Carve-out rationale per Variant D:**
- M-tier carved: user-impact unclear without instruments baseline OR fix-effort high relative to expected delta.
- L-tier carved by definition (code quality / minor cleanup — backlog forever).
- 3 trivial unused imports (L-trivial-imports — see `06D-PERIPHERY-POST-FIX.md`): 3-line cleanup, candidate for Phase 6e bundle.

---

## Regression gate stability

Все 19 fix-commits passed D-08 gate (canonical commands из `06D-02a-PREFLIGHT.md` §3):

```bash
swift test --package-path BBTB/Packages/AppFeatures
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB \
    -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS \
    -destination 'platform=macOS' build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

| Suite | Per-commit count | Final (post-Wave-Final-a) |
|---|---:|---:|
| AppFeatures tests | 133 | **133/133 PASS** |
| VPNCore tests | 57 | 57/57 PASS (where touched) |
| VLESSTLS tests | 19 → 20 (M12 added) | 20/20 PASS |
| PacketTunnelKit tests | 61 | 61/61 PASS (H9/M9/M16 touched) |
| TransportRegistry tests | 42 | 42/42 PASS |
| iOS Simulator xcodebuild | required | **BUILD SUCCEEDED** на каждом commit |
| macOS xcodebuild | required | **BUILD SUCCEEDED** на каждом commit |

**Никаких регрессий across 19 fixes.** D-09 invariants preserved (см. `06D-INVARIANT-AUDIT.md` §5 — все 7 invariants ✅ PASS).

---

## Numerical baseline opportunity (post-Phase-6d)

Хотя pre-fix Instruments baseline был skipped (Variant D), сейчас можно снять **single post-fix capture** на iPhone для future regression detection:

- **Cold launch** Time Profiler — fix candidates currently invisible (M6, M7 — backlog).
- **Connect-tap** spans (PerfSignposter уже инъекетирован Wave 02a Commit 2 — `ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`).
- **Energy Log** на 5-min idle session.
- **Allocations** host + extension processes.

→ Опционально для Wave Final-b (UAT smoke combined). Сейчас НЕ блокирует closure.

---

## Next

**Wave 06D-Final-b** — UAT smoke on iPhone (cold-start + import VLESS-Reality + connect + disconnect + auto-mode + restart) + wiki sync (`wiki/performance-baseline.md` final + `wiki/log.md` append + `wiki/index.md` link + STATE.md backlog row для 26 carved findings) + Phase 6d closure SUMMARY.

**Wave Final-b STOP POINT** — UAT требует физического устройства; user input нужен для execute этой части.

Wave Final-a Task 3 status: ✅ **COMPLETE.**
