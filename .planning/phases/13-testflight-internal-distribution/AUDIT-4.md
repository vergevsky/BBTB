# Pre-TestFlight Fourth Re-Audit — Phase 13 Plan 08

**Date:** 2026-05-17
**Reviewers:** 7 Opus 4.7 + 9 Codex 5.5 attempted = **15 completed** (A6 included; Codex C8 + C9 hit usage limit на Protocols + LOW second-opinion scope — single-source Opus coverage в A6 / A7)
**Baseline:** HEAD `ccbce8a` (post-Plan-07 — 17 atomic fix commits)
**Verdict:** 🟠 **REQUEST CHANGES — Plan 07 introduced 6 cross-validated HIGH regressions plus 4 single-source HIGH.** Internal TestFlight still safe (no CRITICAL), но **External rollout requires Plan 09 fix-up cycle (~3-5h) before broader testing.**

---

## Summary

| Metric | Plan 06 (audit-3) | Plan 08 (audit-4) | Delta |
|---|---|---|---|
| Total findings | ~135 | ~75 | -60 |
| **CRITICAL** | 0 | **0** ✅ | 0 |
| **HIGH (cross-validated)** | 4 | **6** ⚠️ | +2 (NEW regressions) |
| HIGH (single-source) | ~10 | **~7** | -3 (some closed, some new) |
| MEDIUM | ~38 | ~30 | -8 |
| LOW | ~45 | ~25 | -20 |
| Plan 05/07 closures fully verified | 14/16 | 11/18 | 3 regressions in Plan 07 fixes |

**Plan 07 closure quality assessment:**
- ✅ **CV-H3 NAT64 SSRF**: fully closed, 5 tests PASS
- ✅ **CV-H4 VLESS+TLS JSON dispatch**: closed (minor edge case `tls.enabled=missing`)
- ✅ **T-C9' regression / R1**: closed via .disconnected gate
- ✅ **T-A2H1 LockedBool typed lock**: closed
- ✅ **T-C8H1 commitTransaction docs honesty**: closed
- ✅ **T-CD2 PublicKey doc-comment**: closed (minor refinement noted)
- ⚠️ **CV-H1 route.rule_set allowlist**: PASS overall, но symlinks not resolved (M-A1-4-01)
- ⚠️ **CV-H2 ExtensionPlatformInterface stateQueue**: PARTIAL — networkSettings + nwMonitor reads bypass queue (NEW HIGH)
- ⚠️ **CV-H5 BaseSingBoxTunnel lifecycle**: PARTIAL — pi.reset() outside lifecycleQueue + generation check race window (NEW HIGH)
- ⚠️ **T-C-R2 narrow critical section**: PARTIAL — XPC ordering race when older provision overwrites newer (NEW HIGH)
- ⚠️ **T-C-C2H2 single-flight**: PARTIAL — cancellation leak reopens reentrancy race (NEW HIGH)
- ⚠️ **T-C-C3H1 NEVPN coalescing**: PARTIAL — relies on undocumented NotificationCenter serial-delivery claim (NEW HIGH)
- 🛑 **T-C-A6H1 ServerDetail rollback**: FAILS — snapshot captures already-mutated picker value (rollback restores the *new* failed value, not previous) (NEW HIGH)
- 🛑 **T-C-B1 adaptive timeout**: NEVER IMPLEMENTED — code unconditionally 5s, never 5s/2s adaptive (NEW MEDIUM)
- ⚠️ **T-C-B3 identity lowercase**: PARTIAL — SubscriptionMergeService normalized, ServerConfig.identity NOT (asymmetric — same duplicate-row bug T-C-B3 was meant к prevent) (NEW HIGH)
- 🛑 **T-C-B5 octal short-id**: REGRESSION — unquoted DECIMAL-looking hex IDs (`12345678`) get corrupted к `"57060516"` (NEW HIGH)

---

## Cross-Validated HIGH Findings (Plan 07 regressions)

### CV-2-H1: TunnelController single-flight cancellation leak (T-C-C2H2 PARTIAL)
- **Sources:** A3-H-01 (Opus) + C3-4-003 (Codex) — independently identified
- **Location:** `TunnelController.swift` `connect()` / `disconnect()` wrappers
- **Description:** `defer { inFlightConnectTask = nil }` fires when CALLER returns/throws, но inner unstructured `Task { try await self._doConnect() }` keeps running. Caller A cancelled → slot cleared → caller B starts parallel `Task2` → **original reentrancy race re-opened**. Plus connect vs disconnect не arbitrated (could both be in-flight).
- **Why HIGH:** Defeats entire purpose of single-flight. Two concurrent `_doConnect()` Tasks can interleave Keychain reads + XPC saves.
- **Suggested fix:** Tie slot cleanup к inner Task completion via post-completion Task hop + identity check. Add mutex between connect и disconnect.

### CV-2-H2: NEVPN observer pre-hop coalescing race (T-C-C3H1 PARTIAL)
- **Sources:** A3-H-02 (Opus) + C3-4-001 (Codex)
- **Location:** `MainScreenViewModel.swift` NEVPN observer callback
- **Description:** `nonisolated(unsafe) var nevpnObserverLastStatus` + `nevpnObserverLastConnectedDate` accessed без lock from observer callback. Plan 07 docstring claimed «NotificationCenter posts ARE serialized within a notification name on the posting thread» — но Apple does NOT document this contract. If iOS ever delivers concurrently, race window opens (read-compare-write torn).
- **Why HIGH:** Brittle invariant relying on undocumented behavior. Same outcome (MainActor flood) which T-C-C3H1' meant к prevent could regress silently.
- **Suggested fix:** Either (a) drop the pre-hop layer entirely (MainActor `lastAppliedVPNStatus` dedupe already handles flood case), OR (b) protect fields с `os_unfair_lock`.

### CV-2-H3: Provision XPC ordering race after T-C-R2 split
- **Sources:** A3-H-? (Opus) + C3-4-002 (Codex)
- **Location:** `ConfigImporter.provisionTunnelProfile` two-stage split
- **Description:** T-C-R2 moved XPC save outside `provisionSerializer` mutex. Two concurrent provisions can now:
  1. Both enter mutex sequentially, build different `(json, serverHost)` tuples.
  2. Both exit mutex.
  3. Race к `tunnelProvisioner.provisionTunnelProfile` — OLDER provision can win the XPC race, OVERWRITING newer state.
- **Why HIGH:** Selection change → connection establishes к wrong server silently. User UI says «connected to C», traffic actually goes к B.
- **Suggested fix:** Keep XPC inside mutex (revert T-C-R2 partial), OR add per-provision generation counter (newer provision invalidates older mid-XPC).

### CV-2-H4: ExtensionPlatformInterface bypasses stateQueue (T-C-H2 PARTIAL)
- **Sources:** A1-H-02 (Opus) + C1-4-002 (Codex)
- **Location:** `ExtensionPlatformInterface.swift:170` (openTun write), `:485, :495` (clearDNSCache reads), nwMonitor field
- **Description:** Plan 07 T-C-H2' docstring lists `networkSettings` + `nwMonitor` as protected fields, но actual writes/reads at multiple sites bypass the queue. The exact race the queue was supposed к close still exists.
- **Why HIGH:** Torn read of networkSettings → clearDNSCache uses wrong settings → potential traffic disruption on path change.
- **Suggested fix:** Wrap remaining sites в `stateQueue.sync { ... }` OR remove from doc-comment scope.

### CV-2-H5: BaseSingBoxTunnel lifecycle generation gap (T-C-H5 PARTIAL)
- **Sources:** A1-H-01 (Opus) + C1-4-001 (Codex)
- **Location:** `BaseSingBoxTunnel.stopTunnel:404`, `startTunnel async closure:355-365`
- **Description:** Two distinct gaps:
  - `pi.reset()` runs OUTSIDE `lifecycleQueue` в stopTunnel → libbox callbacks (clearDNSCache / autoDetectControl) race с teardown.
  - Generation check race window: closure reads `generation == captured`, queue releases isolation, stopTunnel runs, closure proceeds к `server.close()` between check и call → double-close.
- **Why HIGH:** Generation check intent (prevent double-close) defeated. Extension crash on rapid Connect→Disconnect remains possible.
- **Suggested fix:** Move `pi.reset()` inside lifecycleQueue.sync. Hold generation check + close() в single critical section.

### CV-2-H6: route.rule_set symlink resolution gap (T-C-H1 PARTIAL)
- **Sources:** M-A1-4-01 (Opus) + C1-4-004 (Codex)
- **Location:** `SingBoxConfigLoader.validate` rule_set path check
- **Description:** Plan 07 `NSString.standardizingPath` doesn't resolve symlinks. Operator can place symlink under `rulesCacheDirectory` pointing к arbitrary location — passes allowlist, libbox follows symlink at open time → file read from outside sandbox-permitted area.
- **Why HIGH:** Adjacent gap к T-C-H1; confused-deputy attack via symlink remains.
- **Suggested fix:** `URL.resolvingSymlinksInPath()` + verify result still under cache dir prefix.

---

## Single-Source HIGH Findings

### A2-H3: Probe cancellation downstream amplification
- **Source:** A2 (Opus) + C2-4-001 (Codex parallel)
- **Description:** T-C-A2H2' fixed `probeServerThreeTimes` to return conservative aggregate (`failures: 3, lossRate: 1.0`) on mid-round cancellation, но downstream `refreshProbeScoresInBackground` + `performPreConnectAutoSelect` write to SwiftData WITHOUT `Task.isCancelled` guard → cancellation poisons up to N rows (cap=8) as `isUnreachable=true`. Pre-fix: 1 row falsely "good"; post-fix: N rows falsely "bad". Symmetric site `pingAllServers` HAS the guard.
- **Suggested fix:** Add `if Task.isCancelled { break }` mirror at both write sites.

### A3-H-03: Wrong-server reconnect race
- **Source:** A3 (Opus)
- **Description:** `applySelection` → `reconnectAfterSelectionChange` interaction with new TunnelController single-flight: second selection's `provisionTunnelProfile(C)` writes NE prefs AFTER Task2 already invoked `startVPNTunnel` with B's prefs. UI shows "connected to C" while tunnel actually to B.
- **Suggested fix:** Cancel-and-restart pattern on pending reconnect Task в `applySelection`.

### A4-4-001: SubscriptionMergeService identity asymmetry
- **Source:** A4 (Opus)
- **Description:** T-C-B3 lowercased host в `SubscriptionMergeService.identity` (ImportedServer key), но `ServerConfig.identity` computed property (VPNCore/ServerConfig.swift:135) NOT updated. First case-rotation refresh after v1.0 upgrade reproduces the EXACT duplicate-row bug T-C-B3 was meant к prevent.
- **Suggested fix:** Apply same `.lowercased()` к `ServerConfig.identity` computed property. ~30min.

### A4-4-002: Octal short-id corrupts unquoted decimal-looking hex
- **Source:** A4 (Opus)
- **Description:** Plan 07 T-C-B5 reconstructs octal-from-decimal for `01234567` style. But `12345678` (unquoted) parses as Int via YAML 1.1 normal-decimal rule (not octal — no leading zero), then `String(i, radix: 8) = "57060516"` corrupts the hex. Pre-fix returned `"12345678"` (correct). Affects ~4-15% of randomly-generated short-id values.
- **Suggested fix:** Either (a) revert к `String(i)` decimal preserve + log warning to quote IDs, OR (b) reject unquoted Int short-id with `.unsupported`.

### T-C-A6H1 FAILS: ServerDetail rollback restores failed-new value, not previous
- **Sources:** C6-4-001 (Codex) + A6 broad sweep (Opus) — **independently re-confirmed by Wave 2 reviewer**
- **Location:** `ServerDetailViewModel.applyTransportSelection`
- **Description:** Picker binding mutates `@Published var selectedTransport` SYNCHRONOUSLY before `.onChange` triggers `applyTransportSelection`. Inside the function, `let previous = selectedTransport` reads the ALREADY-MUTATED value. Rollback `selectedTransport = previous` restores the failed new value, NOT the pre-mutation value. T-C-A6H1' fix doesn't actually fix the issue.
- **Suggested fix:** Switch к closure-based `Binding<TransportSelection>` в `ServerDetailView` that captures `oldValue` synchronously at write-time and passes it explicitly к `applyTransportSelection(new:previous:)`. OR maintain `lastPersistedTransport` field that's only updated on save success. ~30min.

### C7-4-001 + A6-FE-3-002: Fronting profile SSRF — NAT64/6to4 IPv6 drift
- **Sources:** C7-4-001 (Codex) + A6-FE-3-002 (Opus broad sweep) — **cross-validated в Wave 2**
- **Description:** Parallel к T-C-H3 NAT64 fix, но в FrontingEngine.isPrivateOrLoopback. Plan 07 noted drift-risk в R25 wiki но не updated code. CDN profile validation still uses string-based regex, misses NAT64/6to4/IPv4-compat prefixes.
- **Suggested fix:** Mirror T-C-H3 numeric IP parser к FrontingEngine. ~30min.

### C6-4-002: IPv4-mapped IPv6 leaks in diagnostics export
- **Source:** C6 (Codex)
- **Description:** DiagnosticsExporter IP-masking (Plan 05 T-A5') handles IPv4-mapped via separate path, но some forms still leak. Different scope from T-C-H3 (SSRF fetcher).

---

## MEDIUM findings (highlights)

- **M-A1-4-04: Adaptive timeout NEVER IMPLEMENTED.** T-C-B1 code unconditionally 5s; the 5s/2s adaptive branch promised в commit message never landed. Either implement properly or revert к 2s + memory note.
- **A4-4-003: VLESS+TLS dispatch misses `tls.enabled` default-true behavior** в sing-box (manifest omits `tls.enabled` for TLS-on-by-default protocols).
- **A4-4-004: SubscriptionPinManager bootstrap** doesn't fall through к bundle resource when cache file is expired/malformed.
- **M-A3-4-02: ProvisionTunnelProfile docstring drift** — docstring says PoolBuilder/validate/CDN outside mutex, but they're INSIDE.
- **C5-4-001: min_app_version not enforced before applying signed manifest** — версия compatibility check should precede content apply.
- **C5-4-002: Bootstrap manifest decoded без signature re-verify** (defense-in-depth gap).
- **M-A5-4-03: RulesManifest.files lacks duplicate-name invariant** — admin compromise could craft duplicate file names → category content swap.
- **C7-4-002: Deep-link routing can run before detached handler registration completes.**
- **C7-4-003: Transport path/host values flow к sing-box без syntax validation.**
- **A2-M5/M6/M7:** Probe cancellation semantic confusion, cancel-inside-await не aborts inflight, connection cleanup gaps.

**A6 new MEDIUM cluster (8 findings, ~2h fix):**
- **A6-SET-3-001:** STUN toggle backdrop dismiss leaves `pendingStunBlock` stale
- **A6-SET-3-002:** `routingRulesEnabled` toggle still lacks live-apply (Plan 06 carry-forward)
- **A6-SET-3-003:** `openTestFlight` persists `dismissedMinAppVersion` even on PLACEHOLDER 404
- **A6-SL-3-001:** LatencyBadge hardcodes "мс" Cyrillic в en locale
- **A6-SL-3-002:** `statusConnected`/`statusEmpty` reused as a11y values for collapse/selection state (semantic mismatch)
- **A6-DL-3-001:** `ImportHandler` accepts arbitrary URL schemes (file://, data://) — defense-in-depth gap
- **A6-KS-3-001:** `KillSwitch.appGroupSuiteName` is `nonisolated(unsafe) static var` — unguarded mutable global
- **A6-TR-3-001:** `TransportRegistry.shared` no `freeze()` discipline

---

## LOW findings (~25 total)

Mostly Plan 06 carry-forwards + 5-7 new doc/code drift items. Notable:

- **L-A3-4-02:** ExternalVPNStopMarker hardcoded key duplication between host + extension с no equality test
- **L-A3-4-06:** `Task.sleep(nanoseconds:)` → `.seconds()` idiom upgrade
- **A7-LOW-001:** DSColor.swift header comment says `15 токенов`, enum doc says `16` (post-`alwaysWhite`)
- **A4-4-005:** VLESS+TLS transport-detection differs from Trojan helper в subtle ways

---

## Plan 07 Closure Index Re-Verification

| Plan 07 Task | Closure Verdict |
|---|---|
| T-C-H1' route.rule_set allowlist | ✅ PASS structurally + 1 NEW MEDIUM (symlinks) |
| T-C-H2' ExtensionPlatformInterface | ⚠️ PARTIAL — networkSettings/nwMonitor bypass queue (NEW HIGH) |
| T-C-H3' NAT64 SSRF | ✅ PASS — 5 tests added |
| T-C-H4' VLESS+TLS JSON | ✅ PASS + 1 edge case MEDIUM |
| T-C-H5' BaseSingBoxTunnel lifecycle | ⚠️ PARTIAL — pi.reset() + gen-check race (NEW HIGH) |
| T-C-R1' T-C9' threshold | ✅ PASS — all 10 paths tested |
| T-C-R2' Narrow critical section | ⚠️ PARTIAL — XPC ordering race (NEW HIGH) |
| T-C-A2H1' LockedBool typed lock | ✅ PASS |
| T-C-A2H2' probe cancellation | ⚠️ PARTIAL — downstream amplification (NEW HIGH) |
| T-C-A6H1' ServerDetail rollback | 🛑 FAIL — captures already-mutated value (NEW HIGH) |
| T-C-C2H1' disconnect resilience | ✅ PASS |
| T-C-C2H2' single-flight | ⚠️ PARTIAL — cancellation leak (NEW HIGH) |
| T-C-C3H1' NEVPN coalescing | ⚠️ PARTIAL — undocumented serialization claim (NEW HIGH) |
| T-C-C3H2' import reentrancy | ✅ PASS |
| T-C-B1 adaptive timeout | 🛑 NEVER IMPLEMENTED (5s only) |
| T-C-B2 failoverDismissTask | ✅ PASS |
| T-C-B3 identity lowercase | ⚠️ PARTIAL — asymmetric vs ServerConfig (NEW HIGH) |
| T-C-B4 PinManager bootstrap expiry | ✅ PASS |
| T-C-B5 octal short-id | 🛑 REGRESSION — corrupts decimal-looking hex (NEW HIGH) |
| T-C-D1 CrashReporter ms timestamp | ✅ PASS |
| T-C-D2 PublicKey doc | ✅ PASS (minor refinement L-A5-4-01) |
| T-C-D3 dead PacketTunnelKit | ✅ PASS |
| T-C-D4 print → TunnelLogger | ✅ PASS |
| T-C-C5H1' commitTransaction docs | ✅ PASS |

**Net Plan 07 quality:** 11/24 fully verified ✅, 9/24 partial ⚠️, 3/24 fail or never landed 🛑. Higher partial/fail rate than Plan 05 (3/21).

---

## Verdict + Recommendation

### 🟠 Internal TestFlight (up to 100 testers) — **SHIP с уже сделанным fb2ff54/ccbce8a baseline ОК**
No CRITICAL surface. Internal testers tolerate edge cases — feedback funds v1.0.1.

### 🛑 External TestFlight / Production — **BLOCK pending Plan 09 fix-up cycle**

**Plan 09 Tier A++ (must fix before external rollout, ~3-5h estimate):**

1. **CV-2-H1** TunnelController single-flight — tie slot cleanup к inner Task completion (~1h)
2. **CV-2-H2** NEVPN coalescing — drop pre-hop layer OR add lock (~30min)
3. **CV-2-H3** Provision XPC ordering — keep XPC inside mutex OR generation counter (~1h)
4. **CV-2-H4** ExtensionPlatformInterface remaining stateQueue gaps (~30min)
5. **CV-2-H5** Lifecycle race — pi.reset() inside queue + gen-check critical section (~1h)
6. **T-C-A6H1 FAIL** ServerDetail rollback — proper previous-value capture (~30min)
7. **T-C-B5 REGRESSION** octal short-id — revert decimal preserve OR reject Int (~30min)

**Plan 09 Tier A (recommended, ~2h):**

8. CV-2-H6 symlink resolution в rule_set
9. A4-4-001 ServerConfig.identity lowercase symmetry
10. C7-4-001 FrontingEngine NAT64 SSRF
11. A2-H3 probe cancellation downstream guard

**Tier B/C** — ~30 MEDIUM + ~25 LOW deferred к v1.0.1 polish.

### Cross-cutting recommendation

**Plan 07 introduced нетривиальный regression rate** (3 outright failures + 6 partial closures из 24 fixes). This suggests:
- More **rigorous post-fix verification** needed — e.g. Codex peer review per fix BEFORE commit, не post-hoc audit.
- More **regression tests** added per fix (some Plan 07 fixes had NO tests — A6'H1, A1'-3-002, C2'-3-001 etc.).
- **Smaller commits** preferred (T-C-H5 + T-C-H2 в один Plan 07 cycle was too much surface to verify).

---

## Plan 08 Reviewer Files

13 files completed (out of 16 attempted):
- `audit-4-reviewers/A1-pkt.md` (351 lines)
- `audit-4-reviewers/A2-vpncore.md` (410 lines)
- `audit-4-reviewers/A3-mainscreen.md` (544 lines)
- `audit-4-reviewers/A4-configparser.md` (409 lines)
- `audit-4-reviewers/A5-rulesengine.md` (405 lines)
- `audit-4-reviewers/A6-medium.md` — ✅ completed (T-C-A6H1' FAIL re-confirmed; 8 new MEDIUM + 18 LOW)
- `audit-4-reviewers/A7-low.md` (203 lines)
- `audit-4-reviewers/C1-pkt.md` through `audit-4-reviewers/C7-infra.md` (Codex)
- `audit-4-reviewers/C8-protocols.md` — Codex usage limit hit; non-critical scope (Protocols), single-source Opus coverage в A6 instead
- `audit-4-reviewers/C9-low.md` — Codex usage limit; single-source Opus A7 covered (clean)

Total reviewer content: ~2638 lines + A6 pending.
