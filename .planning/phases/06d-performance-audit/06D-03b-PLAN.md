---
phase: 06d-performance-audit
plan: 03b
slice: b
type: execute
wave: 3.2
mode: mvp
depends_on: [03a]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
autonomous: true
requirements: [QUAL-01, PERF-02]
findings_addressed: [H2, H3, H8]
tags: [hot-path, xpc-consolidation, observer-stream, polling-cleanup]
status: complete

must_haves:
  truths:
    - "TunnelController.connect() XPC trips reduced from 5 to 2 (happy path) or 3 (cache miss). Single saveToPreferences+loadFromPreferences cycle commits OnDemandRules.applyCurrentState + manager.isEnabled changes."
    - "TunnelController.connect() polling loop replaced with observer-stream + synchronous early-exit. iOS .connected status surfaces immediately (150-400ms typical) instead of waiting for next 1s tick."
    - "TunnelController.disconnect() polling loop reads status BEFORE sleeping. Early-exit on first iteration when iOS reports .disconnected; max iterations reduced from 10 (5s) to 5 (2.5s)."
    - "handleStatusChange body byte-for-byte identical (diff=empty against pre-Wave-03b HEAD); nevpnObserver registration arguments (forName/object:nil/queue:nil) unchanged."
    - "AppFeatures swift test 133/133 + iOS Simulator + macOS xcodebuild green for each of 3 atomic commits."
    - "D-09 forbidden-symbol grep, observer-queue=.main grep, #Predicate UUID? grep all clean across 3 commits."
---

# Wave 06D-03b — TunnelController hot-path cleanup

## Цель волны

Закрытие 3 hot-path findings из 06D-FINDINGS.md, все в одном sensitive file (TunnelController.swift, 316 LOC post-Phase-6c). Цели:

- **H2** (3/3 strong consensus) — Redundant XPC trips в `connect()`: 5 трипов → 2 (happy path).
- **H3** (2/3 moderate consensus) — 1s false latency в connect polling loop: replaced with observer-stream + synchronous early-exit.
- **H8** (Opus #6 unique) — 5s worst-case disconnect wait: read-first, halved budget, reused observer-stream infrastructure.

Каждое исправление — **отдельный atomic commit** с собственным D-09 pre-check + regression gate.

## D-09 invariant pre-check (sensitive file TunnelController.swift)

| Invariant | Status across 3 commits |
|---|---|
| `handleStatusChange` body byte-for-byte unchanged | ✅ `diff /tmp/hsc-HEAD.txt /tmp/hsc-WORKING.txt` empty after each commit |
| `nevpnObserver` registration `(forName:.NEVPNStatusDidChange, object:nil, queue:nil)` unchanged | ✅ grep-verified post-Fix-2 (only callback body extended with broadcast) |
| No reintroduction ReconnectStateMachine / NetworkReachability / ReconnectStateObserverRelay | ✅ forbidden-symbol count stays at 1 (existing comment baseline) |
| `applyVPNStatus`-equivalent authority logic untouched | ✅ TunnelController has no `applyVPNStatus` symbol; intent-closing path through `handleStatusChange` (unchanged) |
| Sliding-window invariant in autoReconnectToggle / isOnDemandEnabled wiring | ✅ `OnDemandRulesBuilder.applyCurrentState` call sites preserved (still drives intent rules from `connect()` consolidate cycle and `disconnect()`) |
| Observer queue = `nil` (Phase 6c Round 6 invariant) | ✅ `grep NEVPNStatusDidChange.*queue:.*\.main\)` = 0 |
| No `#Predicate` UUID? | ✅ Only the existing `ConfigImporter.swift:175` comment hit (not a real predicate) |

## Findings & acceptance per commit

### Fix 1 / Commit 1 — H2 (XPC consolidation)

**Source consensus:** Opus #16 (HIGH after upgrade), Codex #5 (HIGH), Gemini #3 (HIGH).

**Concrete fix:**
- Removed independent `loadAllFromPreferences()` call inside `connect()` — reuse `cachedManager` (already refreshed via `.bbtbProvisionerDidSave` observer).
- Removed second save+load cycle: `applyCurrentStateToCachedManager()` no longer called from `connect()`; instead `OnDemandRulesBuilder.applyCurrentState(to: manager)` mutates the in-memory manager, then ONE `saveToPreferences()` + `loadFromPreferences()` cycle commits both intent-rules and `isEnabled = true`.
- Skip-when-already-enabled idempotency: `if !manager.isEnabled { manager.isEnabled = true }`.
- `PreConnectProbe` span now wraps `refreshCachedManager()` (executes only on cache miss).
- `ProvisionProfile` span wraps the consolidated save+load cycle.

| Acceptance | Required | Result |
|---|---|---|
| XPC call-site count in `connect()` body (`loadAllFromPreferences \| saveToPreferences \| loadFromPreferences`) | ≤ 3 (was 5) | ✅ 2 on happy path, +1 only on cache miss |
| Single XPC save+load cycle commits both intent + isEnabled | yes | ✅ |
| `.bbtbProvisionerDidSave` semantics preserved (no behavioural change for downstream observers) | yes | ✅ — that notification is not posted by `connect()`; it is only posted by ConfigImporter / SettingsViewModel / OnDemandMigrationTask, so removing `applyCurrentStateToCachedManager` from `connect()` does not break any observer contract |
| AppFeatures swift test | 133/133 | ✅ 6.40s |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| D-09 invariants (forbidden symbols / queue=.main / handleStatusChange body diff) | clean | ✅ all |

**Commit:** `8749985 fix(06d-03b): consolidate XPC trips in TunnelController.connect (H2)`

### Fix 2 / Commit 2 — H3 (1s false latency)

**Source consensus:** Opus #1 (HIGH), Codex #16 (MEDIUM).

**Concrete fix:**
- New `awaitConnectedStatus(manager:started:)` helper replaces the 30×1s polling loop.
- Step 1: synchronous `manager.connection.status` read BEFORE any wait — catches `.connected` race.
- Step 2: subscribe to per-connect `AsyncStream<NEVPNStatus>` fed by `broadcastStatus(_:)` (called from the existing `nevpnObserver` callback alongside `handleStatusChange` — no XPC introduced, observer-queue stays `nil`).
- Step 3: per-stream `deadlineTask` (30s) finishes ONLY this connect's continuation, leaving concurrent listeners untouched. Implemented via `statusContinuations[UUID]` map + `finishStatusContinuation(_:)`.
- Step 4: fallback polling preserved (1s sleep, read-first) when `nevpnObserver == nil` (test mocks bypassing `startReachability()`).
- `.disconnected`/`.invalid` from the stream is re-confirmed against authoritative `manager.connection.status == .connected` before throwing — guards against transient observer events during profile reload.

| Acceptance | Required | Result |
|---|---|---|
| Synchronous read BEFORE any sleep in connect path | yes | ✅ step 1 in `awaitConnectedStatus` |
| `nevpnObserver` callback args identical (forName + object: nil + queue: nil) | yes | ✅ grep-verified |
| No new XPC in observer callback (`broadcastStatus` = in-memory dispatch only) | yes | ✅ |
| `handleStatusChange` body identical | yes | ✅ `diff` empty |
| Test mocks (`TunnelControllerTests`) still pass via fallback path | yes | ✅ 7/7 |
| AppFeatures swift test | 133/133 | ✅ 6.42s |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |

**Commit:** `decd7c4 fix(06d-03b): replace 1s polling loop with observer-stream in connect (H3)`

### Fix 3 / Commit 3 — H8 (5s disconnect wait)

**Source:** Opus #6 (unique-but-valuable).

**Concrete fix:**
- New `awaitDisconnectedStatus(manager:)` helper replaces the `for _ in 0..<10 { sleep; read }` loop.
- Step 1: synchronous read FIRST — return immediately when `.disconnected`/`.invalid`.
- Step 2: observer-stream path — reuses the H3 `makeStatusStream()` / `finishStatusContinuation(_:)` primitives with a 2.5s per-stream deadline (5×500ms ceiling preserved by halving max iterations).
- Step 3: fallback polling for test mocks — read-first, then sleep, max 5 iterations.

| Acceptance | Required | Result |
|---|---|---|
| Read status BEFORE sleep on each iteration | yes | ✅ step 1 (sync) + step 2 (stream-driven) + step 3 (fallback read-first) |
| Reuse observer-stream from H3 infrastructure | yes | ✅ `makeStatusStream()` / `finishStatusContinuation(_:)` shared |
| Max disconnect wait ≤ 2.5s (halved from 5s) | yes | ✅ deadline = 2.5s on stream path; 5×500ms on fallback |
| AppFeatures swift test | 133/133 | ✅ 6.42s |
| iOS Simulator xcodebuild | BUILD SUCCEEDED | ✅ |
| macOS xcodebuild | BUILD SUCCEEDED | ✅ |
| D-09 forbidden symbols / queue=.main / #Predicate UUID? | clean | ✅ |

**Commit:** `acd85fa fix(06d-03b): early-exit disconnect polling on .disconnected status (H8)`

## Expected user-visible delta

- **Connect tap → "connected" UI flip**: 200–800ms faster on first attempt. Pre-fix worst case 1000ms idle; post-fix ~observer latency (~ms) when iOS reaches `.connected` between `startVPNTunnel()` and the first observer broadcast.
- **Disconnect tap → "disconnected" UI flip**: 100–500ms faster on healthy disconnects. Pre-fix forced 500ms minimum; post-fix synchronous exit when iOS already reports `.disconnected`.
- **CPU/Energy**: fewer XPC round-trips per connect tap (sysextd contention reduced).
- **No behavioural change** for any downstream observer (`.bbtbProvisionerDidSave` semantics, watchdog forwarding, intent-closing via `handleStatusChange`).

## Commit list

| Commit | Subject |
|---|---|
| `8749985` | `fix(06d-03b): consolidate XPC trips in TunnelController.connect (H2)` |
| `decd7c4` | `fix(06d-03b): replace 1s polling loop with observer-stream in connect (H3)` |
| `acd85fa` | `fix(06d-03b): early-exit disconnect polling on .disconnected status (H8)` |

## Next

Wave 06D-03c — оставшиеся MEDIUM/LOW findings из 06D-FINDINGS.md (если решат закрывать в Phase 6d).
