# Phase 13 / Plan 07 — Third Autonomous Fix-Up Cycle

**Type:** Implementation (autonomous code fixes)
**Status:** ✅ COMPLETE 2026-05-17
**Created:** 2026-05-17
**Closed commit range:** `9da8c96` → `d802e72` (16 atomic commits)
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Baseline:** HEAD `~b18b2fe` (post-Plan-06 audit; commit hash placeholder pending merge)

---

## Goal

Закрыть автономно ВСЕ findings Plan 06 audit от CRITICAL до LOW (~135 findings across 16 reviewer files).

**Owner decisions collected:**
- Q1 (PublicKey bytes): **B = non-trivial placeholder** → update doc-comment to match actual bytes.
- Q2 (T-C9' threshold approach): **B = gate на intervening `.disconnected` transition** (точнее чем raise threshold).
- Q3 (timeout 2s→5s): **B = adaptive** (5s первый старт сессии, 2s для in-session reapply). Supports iPhone XS+ / iOS 18+.
- Q4 (disconnect failure): **B + C combined** — silent retry для clean state + ExternalVPNStopMarker safety net.
- Q5 (libbox log privacy): **C для v1.0** (keep `.public` для Internal diagnostics); **memory note** для External rollout switch к A/B.

**Out of scope (deferred к v1.1+):**
- A5-001 — real Ed25519 keys publish (operational; server URLs тоже placeholders).
- A6'-006 — testFlightInviteURL operational URL.
- Tests directory — audit shipping code only.

---

## Tier Breakdown (Plan 06 Closure)

### Tier A++ — Cross-validated HIGH + Plan-05-induced regressions (7 fixes, ~6-8h)

| Task | Closes | Severity | Effort | Files touched |
|---|---|---|---|---|
| **T-C-H1'** route.rule_set[].path allowlist в validate | CV-H1 (A1'-3-001 + C1'-3-001) | HIGH × 2 sources | 1h | `SingBoxConfigLoader.swift` + tests |
| **T-C-H2'** ExtensionPlatformInterface concurrency | CV-H2 (A1'-3-004 + C1'-3-002) | HIGH × 2 | 1.5h | `ExtensionPlatformInterface.swift` |
| **T-C-H3'** NAT64 + 6to4 + IPv4-compat IPv6 SSRF prefixes | CV-H3 (A4-3-001 + C4'-3-001) | HIGH × 2 | 45min | `SubscriptionURLFetcher.swift` + tests |
| **T-C-H4'** VLESS+TLS sing-box JSON dispatch | CV-H4 (A4-3-002 + C4'-3-002) | HIGH × 2 | 1.5h | `UniversalImportParser.swift` + tests |
| **T-C-H5'** BaseSingBoxTunnel lifecycle race | A1'-3-002 (Opus) + C1'-3-003 (Codex MEDIUM) | HIGH | 1.5h | `BaseSingBoxTunnel.swift` |
| **T-C-R1'** T-C9' threshold regression — gate на intervening `.disconnected` | A3-002 (Opus) | HIGH regression | 30min | `MainScreenViewModel.swift` + tests |
| **T-C-R2'** T-B5' narrow critical section | A3-001 (Opus) | HIGH regression | 1.5h | `ConfigImporter.swift` |

### Tier A+ — Single-source HIGH (8 fixes, ~4-6h)

| Task | Closes | Effort | Files |
|---|---|---|---|
| **T-C-A2H1'** LockedBool → typed OSAllocatedUnfairLock<Bool> | A2-H1 | 15min | `ServerProbeService.swift` |
| **T-C-A2H2'** probeServerThreeTimes cancellation reject | A2-H2 | 30min | `ServerProbeService.swift` |
| **T-C-C2H1'** disconnect failure — B+C combined (retry + marker) | C2'-3-001 | 1h | `TunnelController.swift` + `ExternalVPNStopMarker` |
| **T-C-C2H2'** TunnelController actor reentrancy guards | C2'-3-002 | 1h | `TunnelController.swift` |
| **T-C-C3H1'** NEVPN observer pre-hop coalescing | C3'-3-001 | 1h | `MainScreenViewModel.swift` + `TunnelController.swift` |
| **T-C-C3H2'** import/deeplink reentrancy guards | C3'-3-002 | 45min | `ConfigImporter.swift` + `MainScreenViewModel.swift` |
| **T-C-A6H1'** ServerDetailViewModel snapshot+rollback | A6'-3-001 | 30min | `ServerDetailViewModel.swift` |
| **T-C-C5H1'** commitTransaction depth investigation | C5'-3-001 | 30min — 2h | `SRSCacheStore.swift` (investigate first) |

### Tier B — MEDIUM cluster (38 findings, batched by file/area)

**Concurrency / energy:**
- A1'-3-003 — physicalInterfaceReady semaphore one-shot
- A1'-3-005 — setTunnelNetworkSettings adaptive timeout (Q3 decision: 5s first + 2s reapply)
- A3-003 — applyInitialStatusSnapshot TOCTOU
- A3-004 — handleForegroundReentry XPC accounting comment-guard
- A3-006 — failoverDismissTask cancel-and-replace
- A3-007 — single-flight backgroundProbeTask
- C1'-3-004 — clearDNSCache coalescing
- C3'-3-003 — foreground reentry in-flight coalescing
- A6'-X — cooldown Timer scenePhase resume hook

**Security / data integrity:**
- A4-3-004 + C4'-3-004 — SubscriptionPinManager.bootstrap expired manifest reject
- A4-3-003 — SubscriptionMergeService identity lowercase host
- A4-3-005 + C4'-3-005 — Clash YAML short-id Yams octal bug
- C4'-3-003 — URI parsers canonicalize bracketed/scoped IPv6
- A1'-3-006 — ExternalVPNStopMarker TOCTOU mitigation doc
- A1'-3-007 — shouldSkipPreExpandValidate content-hash binding
- C5'-3-002 — manifest file list constraint к fixed extension filenames
- C5'-3-003 — bootstrap partial first-launch recovery
- C5'-3-004 — RulesFetcher streaming + Content-Length fast-path (parity с T-B2')
- C1'-3-005 — libbox writeDebugMessage memory note for External (Q5 decision)

**Logic / UX:**
- A2 — ms-truncation, force-unwrap migration, regex re-compile
- A3-005 — wireRulesCoordinator await-suspension race
- A3-008 — applyVPNStatus sub-second since drift filter
- A6 — routingRulesEnabled live-apply
- A7-001 — DS.Color.dynamic accessibility variants
- A7-002 — CrashReporter ISO timestamp collision

### Tier C — LOW cleanup (45 findings, single batched commit)

Все LOW от A1-A7 + C1-C9 — docs, defensive coding, future-compat, code style.

---

## Execution Strategy

### Discipline (same as Plan 05)

- **Atomic commits per fix-cluster** — never batch unrelated fixes (except Tier C LOW = single batch).
- **Build verify per commit** via `xcodebuild -scheme BBTB build`.
- **Relevant tests** if code touched has tests.
- **Update AUDIT-3.md** inline ✓ markers after each closure.

### Order

1. **Tier A++ first** (cross-validated CRITICAL-tier severity + regressions).
2. **Tier A+** single-source HIGH.
3. **Tier B** MEDIUM grouped by file.
4. **Tier C** LOW batched cleanup.

### Estimated Total Effort

**~15-20 hours focused work** (matches Plan 02 + Plan 04 + Plan 05 totals). Per Plan 05 norm — autonomous execution с batched commits.

### Success Criteria

- All Tier A++ ✅ in AUDIT-3.md
- All Tier A+ ✅ in AUDIT-3.md
- ≥80% Tier B closed (30+ of 38)
- Tier C single batched commit covering ≥80% of 45 LOW
- `xcodebuild -scheme BBTB build` PASS after every cluster
- No test regressions on packages with tests

---

## Risk Mitigation

| Risk | Mitigation |
|---|---|
| **T-B5' narrowing race**: outside-mutex section (PoolBuilder + validate + XPC) might race с concurrent provision | NEPreferencesAgent serializes XPC internally per Apple — verified. SwiftData ModelContext is per-call new (no shared state). PoolBuilder is pure. Safe to move out. |
| **T-C9' B variant**: gate на intervening `.disconnected` requires new state | Add `private var lastTerminalStatus: NEVPNStatus?` — simple boolean-effective flag |
| **ExtensionPlatformInterface refactor**: changing @unchecked Sendable to actor may cascade | Codex consult before implementation; consider DispatchQueue serial as minimal invasive option |
| **VLESS+TLS JSON dispatch**: changing parseSingBoxJSON shape may break existing tests | Add tests FIRST with sample sing-box JSON containing both Reality + plain TLS outbounds |
| **NAT64/6to4 SSRF**: regex patterns may have edge cases | Use IPv6Address.rawValue numeric byte comparison consistently (already pattern in T-A3') |

---

## Owner Decision Memory (for future audits)

1. **PublicKey.swift bytes:** non-trivial placeholder; doc-comment to be updated.
2. **T-C9' threshold:** gate на intervening `.disconnected` is more correct than raising threshold.
3. **Hardware support:** iPhone XS + (iOS 18+); 5s adaptive timeout on first start.
4. **Disconnect failure UX:** silent retry preferred (no scary alert); marker as defence-in-depth.
5. **Production logging:** keep `.public` for v1.0 (Internal diagnostics value); switch к `.private` для External rollout.
