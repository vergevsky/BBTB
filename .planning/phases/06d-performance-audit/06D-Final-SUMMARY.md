---
phase: 06d-performance-audit
plan: Final
type: summary
status: closed
date: 2026-05-14
findings_total: 45
findings_closed: 19
findings_carved: 26
commits_total: 46
post_fix_commits: 7
hard_blockers_passed: "7/8 (E deferred → NET-12, C macOS skipped — carry-over)"
---

# Phase 6d — Closure SUMMARY

## Status

**Phase 6d ✅ Closed 2026-05-14.** Performance & Code Quality Audit complete; v0.6.2 patch shipped.

---

## What Phase 6d delivered

### Triple-AI peer review

- **Claude Opus 4.7** (internal thread, identical 7-section brief) — sweeping audit across cold-start / connect-tap / energy / memory / code-quality dimensions.
- **Codex GPT-5.2** (`mcp__codex__codex` sandbox=read-only, identical 7-section brief) — independent pass с фокусом на extension correctness + architectural patterns.
- **Gemini 3.1 Pro** (`mcp__gemini__gemini` sandbox=read-only + fallback chain) — independent pass; consensus matrix.
- Synthesis: `06D-FINDINGS.md` (consolidated, 45 findings total post-filter; 3-AI / 2-AI / 1-AI consensus markers + D-09 invariant filter).

### CHECKPOINT 1 decision

User selected **Option-B** (HIGH only + selected MEDIUM). Variant **D** (skip pre-fix Instruments baseline в пользу velocity; accept descriptive comparison вместо numerical). Budget materialized: **19 findings closed**, **26 carved-out** в backlog.

### Fix cycle (Wave 03a–03h sub-plans)

19 atomic commits, regression gate green между каждым:

| Sub-plan | Findings | Commits | Theme |
|---|---|---|---|
| 03a | H1 | `c2d54ea` | Trace-logging gated за `#if DEBUG` |
| 03b | H2, H3, H8 | `8749985` + `decd7c4` + `acd85fa` | TunnelController XPC consolidation + observer-stream |
| 03c | H4 (×2) | `55bde6c` + `dca8e58` | Bounded concurrency + cached auto-mode snapshot |
| 03d | H5, H7 | `5ef3888` + `b8d9294` | UI re-render savings (ConnectionTimer + cached counts) |
| 03e | H6, M2, M3, M4, M5 | `1d035bb` + `6c89996` + `1099629` + `684fb5a` + `99530f2` | Cold-start residual + Keychain parallel |
| 03f | M1 | `cd4b297` | Cold-start XPC consolidation |
| 03g | H9, M9, M16 | `37e7d34` + `42a908a` + `5a4db9f` | Extension correctness (NWPath + autoDetect + openTun) |
| 03h | M12, M13, M14 | `1621a08` + `61f60a3` + `b6996cb` | Active connectivity + UI consistency + contract |

### Post-fix correctness commits (after Final-a, during/before Final-b)

| Block | Commits | Theme |
|---|---|---|
| Cold-start UI freeze (4 commits) | `bc7bc26` + `1467328` + `9b38796` + `4983cab` | userIntent guard + handleObservedStatus wrapper + UI dedupe + narrow stale-terminal suppression |
| Settings-disable saga (3 commits, final open-source-research-derived) | `5110ae0` + `9122bbd` + `cff3f46` | No NE save in intent-close → App Group marker → sticky marker + Apple-canonical `options["manualStart"]` |

**Total Phase 6d commits:** 46 (planning + audit + 19 fixes + post-fix + Final-a + Final-b).

### Architectural decisions established (DEC-06d-01..06)

См. полный текст в `wiki/performance-baseline.md` + `wiki/architecture.md` Phase 6d additions section:

1. **DEC-06d-01 — Cold-start init defer pattern.** Non-critical inits → `Task.detached(priority: .utility)` или `.onAppear`, не в `BBTB_iOSApp.init` body.
2. **DEC-06d-02 — XPC consolidation в TunnelController.** Connect/disconnect ≤ 2 XPC trips через `applyCurrentStateToCachedManager()`.
3. **DEC-06d-03 — Event-driven status polling.** `AsyncStream<NEVPNStatus>` observer-stream, не `sleep`-based loops.
4. **DEC-06d-04 — Bounded concurrency для probe-style operations.** Limit 4-8 + cancellation-safe defer cleanup.
5. **DEC-06d-05 — Apple-canonical options discriminator.** `options["manualStart"]: NSNumber(true)` + sticky App Group marker (`ExternalVPNStopMarker.isPending`) для Settings-disable correctness.
6. **DEC-06d-06 — PerfSignposter spans** сохранены в production code как standard performance tooling (`ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`).

### Expected user-visible improvements (descriptive, Variant D)

| Path | Mechanism | Expected delta |
|---|---|---|
| Cold launch | H1 trace removal + M1 XPC consolidation + M2 SwiftData migration defer + M3/M4/H6 fetch optimizations | **−500…−1100 мс** |
| Connect tap | H2 XPC consolidation + H3 observer-stream + H4 cached auto-mode + M5 parallel Keychain | **−1000…−3000 мс** |
| Disconnect tap | H8 early-exit polling | **−2500 мс** |
| Energy | H1 trace I/O eliminated + H5 conditional ConnectionTimer | Hard to quantify без Energy Log, но trace logging известно как top-3 battery consumer |
| Memory | H4/H6/H7/M3/M4 fetch + alloc improvements | **−2-5 МБ** baseline + lower peak во время sheets/refresh/connect |

### Correctness wins (non-perf)

- **M12** — VLESS+TLS WS-host fallback to SNI (active connectivity bug fixed).
- **M13** — `pingAllServers` cancellation-safe (UI rows never stuck в `.pinging`).
- **M14** — `OnDemandMigrationTask` posts `bbtbProvisionerDidSave` with `manager` (contract consistency).
- **Settings-disable saga (post-fix)** — `ExternalVPNStopMarker.isPending` + Apple-canonical `options["manualStart"]` discriminator robustly закрывает race между iOS Settings VPN-off и app on-demand retry'ями.

### UAT regression smoke (2026-05-14, iPhone iOS 26.5, commit `cff3f46`)

| # | Scenario | Result |
|---|---|---|
| A | Wi-Fi ↔ LTE handoff | ✅ PASS |
| F-direct | BBTB → ProtonVPN → return → 1-tap Connect | ✅ PASS |
| F-reverse | BBTB → Happ takeover → BBTB stays off | ✅ PASS |
| G | App background 30+ min, no EXC_RESOURCE | ✅ PASS |
| I | Migration smoke (upgrade install) | ✅ PASS |
| Settings-disable | iOS Settings VPN-off → BBTB stays off | ✅ PASS |
| 6d-NEW-1 | Cold start ≤ 2 sec | ✅ PASS |
| 6d-NEW-2 | Connect tap responsive | ✅ PASS |
| E | Soft-kill server | 🔵 Deferred → NET-12 |
| C | macOS sleep/wake | ⏭ Skipped (carry-over from Phase 6c PASS) |
| B/D/H | Non-blocking | ⏭ Skipped |

Hard-blocker scoring: **7/8 PASS, 1 deferred, 1 skipped (carry-over).**

### Wiki long-term memory updates

- **`wiki/performance-baseline.md`** — new page; pre/post (descriptive) + 6 architectural decisions + methodology + 26 carved findings backlog + ExternalVPNStopMarker sub-section.
- **`wiki/index.md`** — link added.
- **`wiki/log.md`** — closure entry 2026-05-14.
- **`wiki/architecture.md`** — Phase 6d additions section (DEC-06d-01..06 краткая выжимка) + ServerProbeService DEC-06d-04 bounded concurrency note.
- **`wiki/tech-stack.md`** — performance instrumentation section (OSSignposter + Periphery 3.7.4).

---

## Verification metrics (final)

| Check | Required | Actual | Status |
|---|---|---|---|
| `swift test --package-path BBTB/Packages/AppFeatures` | 133/133 PASS | 133 tests, 0 failures, 7.2s | ✅ |
| `xcodebuild -scheme BBTB iOS Simulator` | BUILD SUCCEEDED | BUILD SUCCEEDED | ✅ |
| `xcodebuild -scheme BBTB-macOS` | BUILD SUCCEEDED | BUILD SUCCEEDED | ✅ |
| Forbidden symbols grep (≤ 7 carve-out) | ≤ 7 | 0 | ✅ |
| NEVPN observer queue=.main grep | 0 | 0 | ✅ |
| #Predicate UUID? grep | 0 | 0 | ✅ |
| OSSignposter usages | ≥ Wave 02a baseline | 25 | ✅ |
| Phase 6c hard-blocker UAT (A, F-direct, F-reverse, G, I, Settings-disable) | All PASS | All PASS | ✅ |
| Phase 6d NEW scenarios (cold-start, connect-tap) | All PASS | All PASS | ✅ |
| `.trace` binary в git | 0 | 0 | ✅ |
| `wiki/performance-baseline.md` final state | yes | yes | ✅ |
| PERF-01..05 + QUAL-01..03 в REQUIREMENTS.md | Validated | Validated | ✅ |

---

## Architecture confirmations

- All Phase 6c D-09 invariants preserved across 19 fix-commits + 7 post-fix correctness commits:
  - Forbidden symbols (RSM / NetReach / ReconnectStateObserverRelay / lastKnownStatus / wakePending / triggerRecoveryIfNeeded) = 0.
  - NEVPNStatusDidChange observer queue=.main = 0.
  - `#Predicate` with optional UUID = 0.
  - `applyVPNStatus` single authority + Round 5 carve-out (`connectInProgress`/`manualDisconnectInProgress`).
  - Sliding window invariant (`isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`) verified via F-reverse + Settings-disable PASS.
  - No XPC в observer hot path verified via G passive 30+ min без EXC_RESOURCE.
- OSSignposter инструментация (Wave 02a) сохранена в production code — будущие perf audits могут переиспользовать без re-injection.
- Apple-canonical `options["manualStart"]` discriminator + sticky App Group marker (`ExternalVPNStopMarker.isPending`) — new architectural pattern для Settings-disable correctness, derived from open-source research (WireGuard iOS `activationAttemptId` + sing-box-for-apple App Group persist).

---

## Closed findings (full list — 19 commits)

| ID | Title | Severity | Wave | Commit SHA |
|---|---|---|---|---|
| H1 | `logLevel: trace` + `exportSingBoxLogToDocuments` Phase 5 leftover | HIGH | 03a | `c2d54ea` |
| H2 | Redundant XPC trips в `TunnelController.connect()` | HIGH | 03b | `8749985` |
| H3 | Connect polling loop 1s false latency | HIGH | 03b | `decd7c4` |
| H8 | `TunnelController.disconnect` 5s polling sleep | HIGH | 03b | `acd85fa` |
| H4 (×2) | Auto-mode pre-connect probe blocks tap | HIGH | 03c | `55bde6c` + `dca8e58` |
| H5 | `ConnectionTimer` 1Hz Timer.publish alive when disconnected | HIGH | 03d | `5ef3888` |
| H7 | `pendingDeleteSubscriptionServerCount` fetches all rows | HIGH | 03d | `b8d9294` |
| H6 | `countSupportedConfigs()` materialization (residual) | HIGH | 03e | `1d035bb` |
| M2 | SwiftData Phase 3 migration sync в container | MEDIUM | 03e | `6c89996` |
| M3 | `runIsSupportedUpgrade` parser allocation | MEDIUM | 03e | `1099629` |
| M4 | `MainScreenViewModel.refresh()` N+1 SwiftData reads | MEDIUM | 03e | `684fb5a` |
| M5 | Sequential Keychain reads stall pool provisioning | MEDIUM | 03e | `99530f2` |
| M1 | 6+ fire-and-forget XPC tasks из cold start | MEDIUM | 03f | `cd4b297` |
| H9 | NWPathMonitor `semaphore.wait` без timeout | HIGH | 03g | `37e7d34` |
| M9 | `autoDetectControl` ignores `currentInterfaceIndex == 0` | MEDIUM | 03g | `42a908a` |
| M16 | `openTun` 5s semaphore — reduce to 2s | MEDIUM | 03g | `5a4db9f` |
| M12 | VLESS+TLS WS-host fallback to SNI missing | MEDIUM | 03h | `1621a08` |
| M13 | `pingAllServers` rows stuck в `.pinging` | MEDIUM | 03h | `61f60a3` |
| M14 | `OnDemandMigrationTask` posts `object: nil` | MEDIUM | 03h | `b6996cb` |

---

## Carved findings (26 — backlog для Phase 6e)

| Severity | Count | IDs |
|---|---|---|
| MEDIUM (carved) | 6 | M6, M7, M8, M10, M11, M15 |
| LOW | 20 | L1-L20 |

Полный детал — `06D-FINDINGS.md` (git-tracked) и `wiki/performance-baseline.md` § Open follow-ups.

---

## Reference index

- **CHECKPOINT 1 decision**: Option-B + Variant D (no pre-fix Instruments) — recorded в discussion + `06D-COMPARISON.md` methodology note.
- **Multi-AI brief skeleton**: `06D-01-PREFLIGHT.md` (frozen verbatim text), source `06D-RESEARCH.md`.
- **Phase 6c invariants**: `06D-CONTEXT.md` § D-09 + `wiki/auto-reconnect.md`.
- **Phase 6d post-fix Settings-disable architecture**: `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExternalVPNStopMarker.swift` + open-source research (WireGuard iOS `activationAttemptId` pattern).
- **PerfSignposter**: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift` (Wave 02a Commit 2).
- **UAT report**: `06D-UAT.md`.
- **Long-term wiki record**: `wiki/performance-baseline.md`.

---

## Status

**Phase 6d ✅ Closed 2026-05-14.** Next: `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).
