---
phase: 06d-performance-audit
plan: 03c
slice: c
type: execute
wave: 3.3
mode: mvp
depends_on: [03b]
files_modified:
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [H4]
tags: [hot-path, auto-mode, bounded-concurrency, cache-snapshot, swiftdata-fetch-collapse]
status: complete

must_haves:
  truths:
    - "ServerProbeService.probeAll использует bounded concurrency cap=8 (Apple guidance для parallel NWConnection). Все серверы из входного массива probed; cap ограничивает только parallelism."
    - "MainScreenViewModel.refresh() делает ОДИН SwiftData fetch supported серверов; supportedConfigCount + activeServerName + supportedServerSnapshot derived из одного массива (collapsed N+1)."
    - "Auto-mode hot-tap path читает cached snapshot (~µs) вместо probeAll-фан-аута (~500-1500ms на 30-50 серверах). Background refresh spawned после connect."
    - "Slow path (cold-DB OR snapshot.isEmpty OR all-cached-unreachable) делает full pre-connect probe через bounded probeAll (cap=8) — preserves existing AutoSelectIntegrationTests semantics."
    - "applyVPNStatus(_:connectedDate:) function body byte-for-byte identical; nevpnStatusObserver registration не тронут; isOnDemandEnabled formula не тронута."
    - "AppFeatures swift test 133/133 + VPNCore swift test 57/57 + iOS+macOS xcodebuild green после КАЖДОГО commit."
    - "D-09 forbidden-symbol grep (baseline=1) / observer queue=.main grep (=0) clean across both commits."
---

# Wave 06D-03c — H4 auto-mode pre-connect probe refactor

## Цель волны

Закрытие **H4 (3/3 strong consensus)** — Connect-tap latency регрессия из Phase 5: auto-mode pre-connect probe всех supported серверов блокирует tap. Один из крупнейших single-finding refactor'ов в Phase 6d.

Два atomic commits:

1. **`55bde6c`** — bounded concurrency в `ServerProbeService.probeAll` (cap=8).
2. **`dca8e58`** — cache supported-server snapshot, fast-path для hot tap, background refresh.

Каждый коммит с собственным D-09 pre-check + AppFeatures+VPNCore tests + iOS+macOS builds.

## Source consensus (H4)

| Source | Severity | Specifics |
|---|---|---|
| Opus #27 | MEDIUM (synthesis-upgraded → HIGH) | Unbounded fan-out: 1 task × N серверов × 3 probes × 200ms typical = >500ms perceived lag на tap |
| Codex #1 | HIGH | `performPreConnectAutoSelect` runs ON EVERY connect tap, blocks tap |
| Codex #2 | HIGH | Probe all supported серверов on tap — energy drain + tap stall |
| Gemini #4 | HIGH | NWConnection fan-out contends за socket pool / Mach ports |

## D-09 invariant pre-check (sensitive file MainScreenViewModel.swift)

| Invariant | Status across 2 commits |
|---|---|
| `applyVPNStatus(_:connectedDate:)` body byte-for-byte identical | ✅ Commit 1: file untouched. Commit 2: `diff /tmp/applyvpn-PRE.txt /tmp/applyvpn-POST.txt` = 0 lines. |
| `nevpnStatusObserver` registration `(forName:.NEVPNStatusDidChange, object:nil, queue:nil)` unchanged | ✅ Commit 1: file untouched. Commit 2: registration diff filter empty (lines 187-201). |
| No reintroduction ReconnectStateMachine / NetworkReachability / ReconnectStateObserverRelay | ✅ Forbidden-symbol grep = 1 across both commits (pre-existing comment baseline в MainScreenViewModel.swift:81). |
| Observer queue = `nil` (Phase 6c Round 6 invariant) | ✅ `grep NEVPNStatusDidChange .*queue: *\.main` = 0 across both commits. |
| Sliding-window invariant в autoReconnectToggle / isOnDemandEnabled wiring | ✅ Formula lives в TunnelController.swift — не тронут в этом wave; MainScreenViewModel.swift diff не содержит `isOnDemandEnabled` / `userIntendedConnected`. |
| No `#Predicate` UUID? | ✅ Все `#Predicate` в этом diff используют `isSupported == true` (Bool) или `$0.id == id` (UUID == UUID). UUID? case в `subscriptionID` не тронут. |

## Findings & acceptance per commit

### Fix 1 / Commit `55bde6c` — H4 part 1 (bounded concurrency)

**Source consensus:** Opus #27 + Codex #1 + Codex #2 + Gemini #4 (3/3 strong, parallel NWConnection fan-out).

**Concrete fix (BBTB/Packages/VPNCore/Sources/VPNCore/ServerProbeService.swift):**
- Add `private static let maxConcurrentProbes = 8` (Apple guidance для parallel `NWConnection`).
- Replace unbounded `for srv in servers { group.addTask {...} }` (1 task per server) с **pre-spawn up-to-cap + on-finish-spawn-next** pattern:
  - Первые `min(cap, total)` tasks стартуют сразу.
  - `while let result = await group.next()` yield'ит результат continuation'у И стартует следующий task если ещё остались серверы.
  - Invariant: in-flight tasks ≤ cap всегда.
- Все серверы из входного массива получают probe (no drops).
- Cancellation propagation preserved: outer task cancel → `AsyncStream.onTermination` → internal Task cancel → probe-tasks завершаются через `withTaskCancellationHandler` в `probeOnce`.

| Acceptance | Required | Result |
|---|---|---|
| Concurrency cap marker grep | yes | ✅ `grep -nE "withTaskGroup\|maxConcurrent"` shows `maxConcurrentProbes = 8` + `withTaskGroup` + min(cap, total) |
| All input servers probed (no drops) | yes | ✅ Pre-existing test `test_probeAll_yields_results_for_all_servers` (3/3 yields) preserved |
| Cancellation ≤ 2s wall-clock после cancel | yes | ✅ Pre-existing test `test_probeAll_cancellation_via_task_cancel` passes (≤2s budget) |
| VPNCore swift test | 57/57 | ✅ 0.78s, 0 failures |
| AppFeatures swift test | 133/133 | ✅ 6.74s |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild (CODE_SIGNING_ALLOWED=NO) | BUILD SUCCEEDED | ✅ |
| D-09 forbidden symbols / queue=.main / applyVPNStatus diff | clean | ✅ all (MainScreenViewModel untouched) |

**Commit:** `55bde6c fix(06d-03c): bounded concurrency in ServerProbeService.probeAll (H4 part 1)`

### Fix 2 / Commit `dca8e58` — H4 part 2 (cache snapshot, hot-path optimization)

**Source consensus:** ↑ same H4 group.

**Concrete fix (BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift):**

1. **New `SupportedServerSnapshot`** (Sendable value type): `id: UUID`, `name: String`, `lastLatencyMs: Int?`, `failedProbeCount: Int`. Holds derived data без удержания SwiftData @Model references.

2. **`@Published private(set) var supportedServerSnapshot: [SupportedServerSnapshot]`** populated в `refresh()` из ОДНОГО fetch'а ServerConfig rows (collapsed N+1 — раньше count-fetch в `refresh()` + повторный fetch в `performPreConnectAutoSelect`).

3. **`refresh()` rewrite:** при наличии modelContainer — один `context.fetch(supported)`, derives `supportedConfigCount` + `supportedServerSnapshot` + `activeServerName` из same array. Если container nil (Phase 2 backward-compat init) — fallback на старую `countSupportedConfigs()` ветку.

4. **New `resolveServerLineNameFromSnapshot()`** — derive bottom-bar label из cache без отдельного fetch.

5. **New `selectAutoWinner()`** — split path:
   - **Fast path:** cache non-empty AND `hasUsableData` (≥1 сервер с `lastLatencyMs != nil` OR `failedProbeCount > 0`) → winner picked by `lastLatencyMs` ascending, exclude `failedProbeCount >= 3`. После selection — spawn `Task.detached { ... refreshProbeScoresInBackground() }`.
   - **Slow path:** cache empty OR cold-DB (no probe history) OR все-cached-unreachable → старый `performPreConnectAutoSelect()`, который теперь использует bounded probeAll (cap=8, Commit 1).

6. **`performToggleImpl()`** теперь вызывает `selectAutoWinner()` (вместо прямого `performPreConnectAutoSelect()`).

7. **New `refreshProbeScoresInBackground()`** — probes ВСЕ supported серверы (bounded), пишет latency / failedProbeCount / lastPingedAt в SwiftData rows, обновляет @Published snapshot. Spawned via `Task.detached` **после** того, как winner провизионирован и connect tap стартовал.

| Acceptance | Required | Result |
|---|---|---|
| `selectAutoWinner` fast-path bypasses `performPreConnectAutoSelect` when cache hit | yes | ✅ `selectAutoWinner` returns winnerID directly от cache; performPreConnectAutoSelect вызывается только в slow-path |
| Cold-launch fallback path still works | yes | ✅ AutoSelectIntegrationTests 4 tests pass: cold-DB seedServer'ы (lastLatencyMs=nil, failedProbeCount=0) попадают в `hasUsableData == false` → slow path |
| Background refresh не блокирует connect tap | yes | ✅ `Task.detached { await self?.refreshProbeScoresInBackground() }` — fire-and-forget после `provisionTunnelProfile` |
| `applyVPNStatus(_:connectedDate:)` body diff | empty | ✅ `diff /tmp/applyvpn-PRE.txt /tmp/applyvpn-POST.txt` = 0 lines |
| nevpnStatusObserver registration args не тронут | yes | ✅ diff filter `forName:.NEVPNStatusDidChange\|object: *nil\|queue: *nil` пустой |
| `manager.isOnDemandEnabled` formula не тронута | yes | ✅ formula лежит в TunnelController.swift, в этом diff отсутствует |
| AppFeatures swift test | 133/133 | ✅ 6.77s (после bug-fix iteration: ambiguity `ServerSnapshot` → renamed `SupportedServerSnapshot`) |
| VPNCore swift test | 57/57 | ✅ unchanged from Commit 1 baseline |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| D-09 forbidden symbols / queue=.main / #Predicate UUID? | clean | ✅ baseline=1, queue=.main=0, no UUID? predicate added |

**Commit:** `dca8e58 fix(06d-03c): cache auto-mode server snapshot, eliminate hot-path probe (H4 part 2)`

## Expected user-visible delta

- **Auto-mode Connect tap → "connecting" UI flip:**
  - Cold launch (first ever tap): unchanged (slow path с bounded probes — но теперь max 8 параллельных вместо unbounded N, что снижает Mach-port contention).
  - Subsequent taps (cache populated): **500-1500ms faster** на 30-50 серверах. Hot path выбирает winner из cached snapshot за ~µs.
- **Energy / Mach ports:** bounded NWConnection cap=8 устраняет socket-pool contention при probeAll, особенно при больших pool'ах (50+ серверов).
- **No behavioural change** для manual selection mode (`selectedServerID != nil`): прямо `provisionTunnelProfile(for: selectedID)`, без `selectAutoWinner`.

## Architectural changes summary

| Change | File | Type |
|---|---|---|
| Bounded probe concurrency (cap=8) | `ServerProbeService.swift` | Internal performance optimization |
| Public `SupportedServerSnapshot` value type | `MainScreenViewModel.swift` | New Sendable struct (alongside existing `ReconnectBannerState`) |
| `@Published supportedServerSnapshot` | `MainScreenViewModel.swift` | New observable property (backward-compatible additive) |
| Collapsed N+1 fetch в `refresh()` | `MainScreenViewModel.swift` | Hot-path SwiftData round-trip reduction |
| `selectAutoWinner()` split path | `MainScreenViewModel.swift` | New private helper; fast-path bypasses probe fan-out |
| `refreshProbeScoresInBackground()` | `MainScreenViewModel.swift` | New private helper, fire-and-forget post-connect |
| `resolveServerLineNameFromSnapshot()` | `MainScreenViewModel.swift` | New private helper — bottom-bar label without async/SwiftData fetch |

## Commit list

| Commit | Subject |
|---|---|
| `55bde6c` | `fix(06d-03c): bounded concurrency in ServerProbeService.probeAll (H4 part 1)` |
| `dca8e58` | `fix(06d-03c): cache auto-mode server snapshot, eliminate hot-path probe (H4 part 2)` |

## Next

Wave 06D-03d (если решат закрывать) — H5 (`ConnectionTimer` 1Hz publisher без `since`), H6 (`countSupportedConfigs()` → `fetchCount`), H7 (`pendingDeleteSubscriptionServerCount` cache), H9 (`NWPathMonitor` `semaphore.wait()` без timeout). H6 уже частично адресован в Commit 2 (refresh теперь использует один fetch вместо countSupportedConfigs).
