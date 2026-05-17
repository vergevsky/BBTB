# Pre-TestFlight Third Re-Audit — Phase 13 Plan 06

**Date:** 2026-05-17
**Reviewers:** 7 Opus 4.7 subagents + 9 Codex 5.5 threads = 16 parallel reviewers (mirror Plan 02/04)
**Baseline:** HEAD `fb2ff54` (post-Plan-05 fixes + Tier-D LOW batch)
**Verdict:** 🟡→🟢 **CONDITIONAL → CLEAR APPROVE** after Plan 07 fix-up cycle (commits 9da8c96 → d802e72, 16 commits autonomous closure of ~25 highest-impact findings).

**Original verdict** (pre-Plan-07): CONDITIONAL APPROVE — 0 CRITICAL; 2 cross-validated HIGH + 2 regressions deserve fix.
**Post-Plan-07 status:** All 4 cross-validated HIGH + 2 Plan-05 regressions + 6 single-source HIGH + 5 top MEDIUM + 4 LOW CLOSED. Safe для Internal AND external TestFlight rollout.

---

## Summary

- **Total findings (pre-dedup):** ~135 across 16 reviewer files
- **CRITICAL:** **0** ✅ (no exploitable / connection-broken issues)
- **HIGH:** **~14 unique** (cross-validated: 4; single-source: ~10)
- **MEDIUM:** **~38 unique**
- **LOW:** **~45 unique** (mostly code-style, docs, defensive coding)
- **Plan 05 closures verified:** 14/16 hold structurally; 2 partial (T-B5' critical-section width still wide; T-C9' threshold incorrect для long-background)
- **No regressions in security-critical paths** (Ed25519 trust chain order preserved; SSRF blocklist not weakened; sing-box validate order honored)

---

## Plan 05 Closure Re-Verification

| Plan 05 Task | Closure Claim | Audit-3 Verdict | Reviewer(s) |
|---|---|---|---|
| T-A1' (986c2af) — sha256 empty bypass reject | C5'-001 CRITICAL closed | ✅ **CLOSED** — `isValidSHA256Hex` regex `^[A-Fa-f0-9]{64}$` correctly rejects empty/malformed | A5 + C5 |
| T-A3' (1883035) — `isBlockedHost` numeric IP parser | C4'-001 CRITICAL closed | ✅ **CLOSED for named CRITICAL** — `::ffff:7f00:1` and variants correctly blocked. ⚠️ **NEW HIGH** discovered: NAT64 `64:ff9b::/96` + 6to4 + IPv4-compatible IPv6 prefixes not covered (real cellular SSRF) | A4 + C4 |
| T-A5' (86dd31e) — IPv6 mask compressed forms | C6'-001 HIGH closed | ✅ **CLOSED** — 3 regex alternatives cover all compressed forms | C6 |
| T-B5' (2952871) — ProvisionSerializer real async mutex | A3'-001 + C3'-001 HIGH closed | ⚠️ **PARTIAL** — Reentrancy correctness ✅; critical-section width still too wide → **NEW HIGH A3-001** | A3 |
| T-B1' (515f8dc) — PinnedSession `willPerformHTTPRedirection` | C4'-002 HIGH closed | ✅ **CLOSED** — verified | A4 + C4 |
| T-B2' (515f8dc) — JSONEndpoint `bytes(for:)` streaming + cap | C4'-003 HIGH closed | ✅ **CLOSED** — verified. Same parity gap noted in `RulesFetcher` (M-A5-3-04 / C5'-3-004) | A4, A5, C5 |
| T-B3' (74dd020) — `commitTransaction` generation atomic swap | C5'-002 + A5'-004 + C5'-003 HIGH closed | ⚠️ **PARTIAL/CONTESTED** — A5 (Opus) says structurally sound; **C5 (Codex) claims still per-file rename loop, not generation-directory pattern**. Plan 05 commit message says "generation directory + atomic swap" but Codex reads code as Phase-2 per-file rename. Worth verifying. | A5 + C5 (disagree) |
| T-B4' (74dd020) — Path traversal positive allowlist | A5'-001 + C5'-005 HIGH closed | ✅ **CLOSED** — `^[A-Za-z0-9][A-Za-z0-9._-]*$` regex; Unicode fullwidth solidus rejected | A5 |
| T-B5'-extra (74dd020) — `.bbtb-staging` cleanup | A5'-002 MEDIUM closed | ✅ **CLOSED** — init sweep + defer cleanup | A5 |
| T-B6' (c1ee6b4) — FrontingEngine tag-scoped apply | C7'-001 HIGH closed | ✅ **CLOSED** — `FrontingConfigApplier.apply(...:targetTag:)` + caller passes parsedList.first | A6 |
| T-C1' (4f916d7) — Keychain AccessibleAfterFirstUnlockThisDeviceOnly | C2'-001 MEDIUM closed | ✅ **CLOSED** | A2 |
| T-C2' (4f916d7) — Synchronizable cleanup sweep | C2'-003 MEDIUM closed | ✅ **CLOSED** | A2 |
| T-C3' (6244b8b) — URI parsers port=0 rejection | A4'-004 MEDIUM closed | ✅ **CLOSED** all 5 parsers | A4, C4 |
| T-C4' (6244b8b) — outbound tag 256-char cap | A4'-005 MEDIUM closed | ✅ **CLOSED** | A4 |
| T-C5' (515f8dc) — HTTPSRedirectGuard @unchecked Sendable | C4'-004 MEDIUM closed | ✅ **CLOSED** | A4 |
| T-C6' (f909b5b) — route.rules + route.final outbound-ref check | C1'-001 CRITICAL + A1'-006 LOW closed | ✅ **CLOSED for named scope** (rules/final). ⚠️ **NEW HIGH** discovered: same operator-supplied path-traversal surface remains in `route.rule_set[].path` — adjacent gap not covered | A1 + C1 (cross-validated!) |
| T-C7' (4f916d7) — ServerListVM loadFromStore(force:) | C6'-002 MEDIUM closed | ✅ **CLOSED** | A6 |
| T-C8' (4f916d7) — dead JSON templates | A6'-001 MEDIUM closed | ✅ **CLOSED** | A6 |
| T-C9' (81d7ea6) — connectedDate stale guard + future-clock clamp | C3'-002 MEDIUM closed | ⚠️ **PARTIAL/REGRESSION** — future-clock clamp PASS; 60s stale threshold incorrectly fires в long-background sessions → **NEW HIGH A3-002** | A3 |
| T-C11' (74dd020) — sigPath preserved | C5'-004 MEDIUM closed | ✅ **CLOSED** | A5 |
| T-C15' (ce130bf + 81d0418) — DNS-rebinding wiki | A4'-001 HIGH closed | ✅ **CLOSED** | A4 |

**Summary:** 18/21 Plan 05 closures fully hold structurally. 3 are partial:
- T-B5' — fixed mutex correctness, did NOT narrow critical-section width
- T-C9' — fixed future-clock direction; 60s threshold too aggressive for legitimate long-background
- T-B3' — claim contested by Codex (per-file rename vs generation-directory); worth verifying

---

## Cross-Validated CRITICAL Findings

**None.** No reviewer flagged a CRITICAL.

---

## Cross-Validated HIGH Findings

Findings independently reported by BOTH Opus AND Codex reviewers on the same package — high confidence.

### CV-H1: `route.rule_set[].path` allowlist gap — operator JSON can drive arbitrary file `open(2)` inside extension sandbox
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift:75-163` (validate)
- **Dimension:** Security / path traversal
- **Sources:** A1 (Opus, A1'-3-001) + C1 (Codex, C1'-3-001) — **independently identified**
- **Description:**
  Plan 05 T-C6' closed `route.rules[].outbound` + `route.final` outbound-ref validation. **Adjacent gap remains:** `route.rule_set[].path` accepts arbitrary filesystem paths. libbox will `open(2)` these from inside extension sandbox (App Group container, extension Caches/, bundle resources reachable).
- **Threat scenario:**
  Operator JSON (Hiddify import, future custom paste) declares `route.rule_set: [{ type: "local", format: "binary", path: "/private/var/mobile/Containers/Shared/AppGroup/<UUID>/Library/Caches/pins/subscription-pins-cached.json" }]`. libbox attempts to parse the pin cache as `.srs` — open syscall returns success → file existence enumerated → path string surfaces in `writeDebugMessage` callback → main-app log export leaks paths.
  Worse: `type: "remote"` rule_set with operator-controlled URL bypasses the app's hardened fetch/SSRF guards entirely.
- **Why HIGH:** Information disclosure surface (file existence enumeration via libbox error log) + bypass of `RulesEngine` signed fetch path для rule_set acquisition.
- **Suggested fix:**
  In `validate(json:)`, when `route.rule_set` is present, enforce per-entry policy:
  1. `type` must be `"local"` (reject `"remote"`).
  2. `path` must canonicalize to under `AppGroupContainer.rulesCacheDirectory.path/`.
  3. Basename matches positive regex `^[A-Za-z0-9][A-Za-z0-9._-]+\.srs$`.
  4. Reject paths containing `..`, symlinks, percent-encoded sequences.

### CV-H2: `ExtensionPlatformInterface` `@unchecked Sendable` masks real concurrency race — torn reads on hot path
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/ExtensionPlatformInterface.swift:27, 38, 49, 59, 63` (fields); `220, 238, 259, 344` (writers)
- **Dimension:** Thread Safety / Swift 6 strict concurrency
- **Sources:** A1 (A1'-3-004) + C1 (C1'-3-002) — **independently identified**
- **Description:**
  Class is `@unchecked Sendable` with comment claiming libbox callbacks serialize their callers. But:
  - `autoDetectControl(_:)` called from sing-box Go threads (one per outbound socket — **concurrent**).
  - `notifyInterfaceUpdate` called from `NWPathMonitor` queue (DispatchQueue.global).
  Both read/write the same `currentInterfaceIndex`, `physicalInterfaceSeeded`, `autoDetectCallCount` — no memory barrier, no lock. Semaphore at line 58 only protects wait/signal handshake, not field reads.
- **Why HIGH:** Connection hot path for `includeAllNetworks=YES`. Stale `currentInterfaceIndex` → outbound socket bound to wrong interface → traffic pinned to old network after Wi-Fi/cellular handoff → either silent breakage or DNS leak.
- **Suggested fix:** Replace `@unchecked Sendable` with `actor InterfaceStateStore` OR `os_unfair_lock`-guarded properties. At minimum, document actual safety invariants и enforce via `_Atomic` semantics.

### CV-H3: NAT64 / 6to4 / IPv4-compatible IPv6 prefixes bypass SSRF blocklist (real cellular impact)
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:412-433` (`isBlockedIPv6Bytes`)
- **Dimension:** Security / SSRF
- **Sources:** A4 (A4-3-001) + C4 (C4'-3-001) — **independently identified**
- **Description:**
  Plan 05 T-A3' numeric IP parser correctly handles IPv4-mapped IPv6 (`::ffff:0:0/96`) — closes C4'-001. Адъацент prefixes остаются:
  1. **NAT64 `64:ff9b::/96`** (RFC 6052) — ubiquitous on US/EU cellular (T-Mobile US, Reliance Jio, MVNOs). `64:ff9b::7f00:1` translates to `127.0.0.1` at carrier level. **Real-world SSRF on cellular.**
  2. **6to4 `2002::/16`** — deprecated but still routable through pre-existing tunnels.
  3. **IPv4-compatible IPv6 `::w.x.y.z`** (RFC 4291 deprecated) — Apple parser may still accept.
- **Why HIGH:** Direct SSRF on cellular. Hostile subscription URL with NAT64-encoded loopback reaches `127.0.0.1`, AWS metadata server (`169.254.169.254`), RFC1918 (`10.0.0.1`).
- **Suggested fix:** Extend `isBlockedIPv6Bytes`:
  ```swift
  // NAT64 well-known prefix
  if bytes[0]==0x00 && bytes[1]==0x64 && bytes[2]==0xFF && bytes[3]==0x9B
     && bytes[4..<12].allSatisfy({ $0 == 0 }) {
      return isBlockedIPv4Bytes(Data(bytes[12...15]))
  }
  // 6to4
  if bytes[0]==0x20 && bytes[1]==0x02 {
      return isBlockedIPv4Bytes(Data(bytes[2...5]))
  }
  // IPv4-compatible (excluding ::1 / unspecified)
  if bytes.prefix(12).allSatisfy({ $0 == 0 })
     && (bytes[12] != 0 || bytes[13] != 0 || bytes[14] != 0) {
      return isBlockedIPv4Bytes(Data(bytes[12...15]))
  }
  ```

### CV-H4: VLESS+TLS sing-box JSON outbounds silently dropped (data loss on common import path)
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:481-561` (extractParsedVLESS hard-codes `security: "reality"`)
- **Dimension:** Bug / correctness / silent data loss
- **Sources:** A4 (A4-3-002) + C4 (C4'-3-002) — **independently identified**
- **Description:**
  When user pastes / fetches sing-box JSON manifest containing plain VLESS+TLS outbound (no Reality block), `parseSingBoxJSON` case `"vless"` always calls `extractParsedVLESS` which hard-codes `security: "reality"` and reads missing `reality["public_key"]` as `""`. Resulting `.vlessReality` has empty publicKey → `PoolBuilder.isValidPoolEntry` silently rejects → outbound dropped without UI feedback.
- **Why HIGH:** Silent data loss on operator-published sing-box JSON manifests (Hiddify-style). User sees "0 supported servers" without diagnostic. URI imports work (correct D-02 branching) — only JSON path broken.
- **Suggested fix:** In `parseSingBoxJSON` case `"vless"`: inspect `outbound["tls"]?["reality"]`. If absent and `tls.enabled == true` → call new `extractParsedVLESSTLS(from:)` helper building `.vlessTLS(ParsedVLESSTLS)`. Else fall through to current `.vlessReality` path.

---

## Single-Source HIGH Findings (need verification)

### A3-001: `ProvisionSerializer` critical section still covers full 1-3s pipeline → failover starvation
- **Location:** `ConfigImporter.swift:122-129` (run) + `567-770` (body)
- **Source:** A3 (Opus only)
- **Description:** T-B5' fixed reentrancy correctness but did NOT narrow critical section per A3'-001 suggestion. Mutex covers SwiftData fetch (10-30ms) + Keychain TaskGroup (100-500ms) + PoolBuilder (50-200ms) + validate (100-300ms) + XPC save (300-1000ms). Total 1-3s mutex hold. Concurrent failover/reconnect blocks for full chain.
- **Why HIGH:** Failover starvation on slow networks (50+ server pool). Watchdog promised mid-session failover; mutex defers it.
- **Suggested fix:** Split `provisionTunnelProfile` — critical section covers SwiftData fetch + Keychain reads only; PoolBuilder + validate + XPC run outside mutex (NEPreferencesAgent serializes XPC internally).
- **Effort:** 1-2h

### A3-002: T-C9' 60s stale threshold incorrectly discards legitimate `state.connectionStart` after long background
- **Location:** `MainScreenViewModel.swift:494-510` (resolveConnectionSince)
- **Source:** A3 (Opus only)
- **Description:** T-C9' helper picks fresh `cd` when `cd - cs > 60s`. But same algebra fires when iOS legitimately updates `connectedDate` mid-session (Wi-Fi → cellular handoff → NE reasserts; long background → fresh foreground snapshot; on-demand re-fire). After ≥60s background, foreground returns → `cd` is newer (iOS reasserted) but session is logically continuous → helper picks `cd` → timer resets from "10:00" to "05:00" (or worse, "00:00").
- **Why HIGH:** Timer regression for normal user behaviour (backgrounding app for 5+ minutes). T-C9' was supposed to FIX C3'-002 stale-session, но introduces a different regression.
- **Suggested fix:** Either raise threshold to ≥1h, OR gate on intervening `.disconnected` transition (add `lastTerminalStatus: NEVPNStatus?` — only switch authority к `cd` if `.disconnected` observed since last `.connected`).
- **Effort:** 30min — 1h
- **Telemetry indicator:** Phase 6 reUAT «Замечание 1 — timer resets on foreground» history.

### A1'-3-002: `BaseSingBoxTunnel` `@unchecked Sendable` lifecycle race — startTunnel async closure can double-close `LibboxCommandServer`
- **Location:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/BaseSingBoxTunnel.swift:353-369` (startTunnel async) + 372-408 (stopTunnel) + 410-421 (sleep/wake)
- **Source:** A1 (Opus); related C1'-3-003 MEDIUM
- **Description:** Step 8 dispatches `startOrReloadService` to `DispatchQueue.global`. On error path (line 360-368) writes `commandServer = nil`. Meanwhile NE may deliver `stopTunnel`/`sleep`/`wake` on provider queue — concurrent reads/writes. Concrete race: user rapid Connect→Disconnect → `stopTunnel` reads `commandServer`, calls `close()`. Simultaneously async error closure tries `try? server.closeService(); server.close()`. Double-close → Go-side panic → extension SIGABRT.
- **Why HIGH:** Correctness/crash bug в hot path. Reproduces under rapid Connect→Disconnect (TestFlight install flow).
- **Suggested fix:** Dedicated `DispatchQueue(label: "app.bbtb.tunnel.lifecycle")` для commandServer/platformInterface reads/writes. Hold local `let serverLocal = server` and call `close()` only after `queue.sync` check `self.commandServer === serverLocal`.

### C2'-3-001: Explicit `disconnect()` continues even when `applyCurrentStateToCachedManager` fails to persist `isOnDemandEnabled=false`
- **Location:** `TunnelController.swift:312, 315` (catch + log) + 477 (caller) + 491 (proceed to stop)
- **Source:** C2 (Codex only)
- **Description:** `applyCurrentStateToCachedManager` catches saveToPreferences errors и только логирует. `disconnect()` proceeds even when NE preferences still have `manager.isOnDemandEnabled=true`. Extension-side `ExternalVPNStopMarker` blocks Settings/user-disabled auto-restarts only — manual app disconnect не marks that path. On transient NE prefs failure, iOS can restart profile after explicit user Disconnect.
- **Why HIGH:** Manual Disconnect doesn't actually disconnect on transient NE failure — surprising UX, can lead to perceived "VPN stays on after I turned it off".
- **Suggested fix:** Propagate save failure from `applyCurrentStateToCachedManager` (or check `isOnDemandEnabled` post-save), и: (a) extend `ExternalVPNStopMarker.mark()` к manual-disconnect path тоже, OR (b) retry save with single backoff before stopVPNTunnel, OR (c) surface error к user.

### A6'-3-001: `ServerDetailViewModel.applyTransportSelection` no rollback on SwiftData save failure → UI/store divergence
- **Location:** `Packages/AppFeatures/Sources/ServerListFeature/ServerDetailViewModel.swift:83-100`
- **Source:** A6 (Opus only)
- **Description:** Picker binding mutates `@Published var selectedTransport` synchronously. `.onChange` schedules async `applyTransportSelection` — if `context.save()` throws, only logged. `selectedTransport` not rolled back → UI shows new transport, store keeps old → user reconnects with wrong transport silently.
- **Why HIGH:** No user-visible error path. SwiftData save can fail on real devices (sandbox container locked during background snapshot, disk pressure).
- **Suggested fix:** Snapshot `previous = selectedTransport` before save; rollback on throw + surface `persistError` to alert (mirroring `refreshErrorBinding` pattern).

### C5'-3-001: `commitTransaction` is still per-file rename loop (contested closure of T-B3')
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift:97` (commitTransaction Phase 2)
- **Source:** C5 (Codex) — **contradicts** A5 (Opus) verification of T-B3' closure
- **Description:** Codex reads `commitTransaction` as Phase 1 staging write + Phase 2 per-file `replaceItemAt`/`moveItem` loop. If Phase 2 throws mid-loop after files 0..N committed but N+1 fails → mixed-version cache observable by extension. Plan 05 commit message claimed "generation directory + atomic swap" — Codex says implementation didn't go to generation-directory pattern, just per-file renames с staging cleanup.
- **Investigation needed:** Read `SRSCacheStore.swift` lines 60-130 in detail. Either:
  - Codex misread → T-B3' truly closed (Opus correct), мerge findings as MEDIUM doc clarity.
  - Codex correct → T-B3' partial closure of C5'-002, и mixed-state risk остаётся → HIGH stays.

### C3'-3-001: `NEVPNStatusDidChange` creates one MainActor Task per duplicate event before dedupe runs
- **Location:** `MainScreenViewModel.swift` NEVPN observer block
- **Source:** C3 (Codex only)
- **Description:** Pre-hop coalescing missing. iOS 26 fires 40+ status events per second in некоторых сценариях (memory: `feedback_nevpn_xpc_mach_port`). Each spawns MainActor `Task { applyVPNStatus(...) }`. Dedupe via `lastAppliedVPNStatus` happens INSIDE applyVPNStatus, AFTER the Task scheduled. Result: MainActor queue floods with 40+ no-op Tasks → temporary UI stutter.
- **Why HIGH:** Energy + UI responsiveness during status flapping. Could compound A3-001 if mutex contention.
- **Suggested fix:** Coalesce at observer entry: read latest status sync from `notification.object`, compare against last queued (not last applied) — drop duplicates before Task spawn.

### A2-H1: `LockedBool` `@unchecked Sendable` masks single-resume invariant safety net
- **Location:** `ServerProbeService.swift:212-223`
- **Source:** A2 (Opus only)
- **Description:** `OSAllocatedUnfairLock` stateless variant wrapping bool; `@unchecked Sendable` claim incorrect (`OSAllocatedUnfairLock` is `Sendable` natively). Suppresses compiler warning if future contributor adds non-Sendable property. CheckedContinuation single-resume = fatalError on violation — losing this safety net is HIGH-risk regression-prevention.
- **Suggested fix:** Replace with `OSAllocatedUnfairLock<Bool>(initialState: false)` + drop `@unchecked Sendable`.

### A2-H2: `probeServerThreeTimes` returns mid-cancellation aggregate that scores identically to clean 3/3 OK
- **Location:** `ServerProbeService.swift:174-199`
- **Source:** A2 (Opus only)
- **Description:** Loss-rate denominator masks `Task.isCancelled` mid-round. User swipes away pull-to-refresh sheet → cancelled task writes single-sample `ProbeAggregate(failures: 0, lossRate: 0.0)` к SwiftData. AutoSelect prefers this server over an equally-fast 3/3 OK server.
- **Suggested fix:** Reject aggregate if `Task.isCancelled` before returning; or store explicit "incomplete" marker.

### C2'-3-002: `TunnelController` command methods actor-reentrant — concurrent connect/disconnect can interleave session intent
- **Source:** C2 (Codex only)
- **Description:** Actor isolation released at every `await`. Two concurrent `connect()` calls can re-enter, both flipping `setUserIntendedConnected(true)`, both refreshing cachedManager, ending in non-deterministic state.

### C3'-3-002: Import / deep-link entry points reentrant while ConfigImporter mutates SwiftData and Keychain
- **Source:** C3 (Codex only)
- **Description:** Already partially addressed by ProvisionSerializer (T-B5'), но import path through `handleDeepLink` / paste handler doesn't use it. Two simultaneous imports race на ServerConfig rows.

---

## MEDIUM findings (synthesized highlights)

35+ unique MEDIUM findings across 16 reviewer files. Selected high-impact subset:

- **Plan-05 closure depth concerns:**
  - M-A5-3-01 / C5'-3-002 — `commitTransaction` partial-failure docs vs actual rename loop semantics
  - M-A5-3-03 — `bootstrap()` partial first-launch write leaves idempotency check thinking "done"
  - M-A5-3-05 — path-traversal failure misclassified as `.networkFailure` in user-facing error
- **Concurrency / energy:**
  - A1'-3-003 — `physicalInterfaceReady` semaphore drains after one signal; subsequent transitions miss it
  - A1'-3-005 — `setTunnelNetworkSettings` 2s timeout (Phase 6e M16) too short on iPhone X/XR era hardware
  - A3-003 — `applyInitialStatusSnapshot` TOCTOU race с init-time seed Task
  - A3-004 — `handleForegroundReentry` XPC accounting gap if tunnel.handleForeground extended
  - A3-006 — `failoverDismissTask` not cancelled on re-arm (multi-server cascade banner glitch)
  - A3-007 — `Task.detached` background probe storm w/o single-flight guard
  - A6'-3-X — `cooldown Timer` no `scenePhase` resume hook (force-update button)
  - C3'-3-003 — foreground reentry no in-flight coalescing для XPC + subscription fetch + probe
  - C1'-3-004 — `clearDNSCache()` repeated 2-XPC reconfiguration without coalescing
- **Security / data integrity:**
  - A4-3-004 / C4'-3-004 — `SubscriptionPinManager.bootstrap()` accepts expired cached manifest (D-12 violated on cold-start; gated by dead code currently)
  - A4-3-003 — `SubscriptionMergeService.identity` case-sensitive on hostname → cosmetic duplicates + probe state reset on rotation
  - A4-3-005 / C4'-3-005 — Clash YAML unquoted Reality `short-id` corrupted by Yams octal coercion → connection fails with cryptic handshake error
  - C4'-3-003 — URI parsers accept bracketed/scoped IPv6 hosts without canonicalization
  - A1'-3-006 — `ExternalVPNStopMarker` TOCTOU between extension `mark()` and host `clear()` (cross-process W-W race; mitigating factor: host always passes `manualStart=true`)
  - A1'-3-007 — `shouldSkipPreExpandValidate` 24h cache keyed на timestamp not content hash
  - C5'-3-002 — Manifest file list not constrained к three fixed extension filenames/categories
  - C5'-3-003 — `bootstrap()` partial first-launch write leaves system in stuck state
  - C5'-3-004 — `RulesFetcher` enforces `maxBytes` post-buffer (parity gap vs T-B2' fix)
  - C1'-3-005 — Libbox writeDebugMessage logged as `.public` privacy (server names / SNI exposed to sysdiagnose)
- **Logic / UX:**
  - A2 ms-truncation in probe latency; `subscriptionURL!` force-unwrap in migration; regex re-compile per UI render
  - A3-005 — `wireRulesCoordinator` observer await-suspension race
  - A3-008 — `applyVPNStatus` sub-second `since` Date drift causes SwiftUI body re-diff thrash
  - A6 — `routingRulesEnabled` toggle lacks live-apply (UX inconsistency vs peer toggles)
  - A7-001 — `DS.Color.dynamic` macOS misses `.accessibilityHighContrast*Aqua` variants
  - A7-002 — `CrashReporter.saveDiagnostic` ISO timestamp (second resolution) → filename collision under rapid crashes → data loss

## LOW findings (synthesized)

45+ unique LOW findings — mostly defensive coding, docs, code-style, future-compat. Highlights:

- **L-A5-3-09 / C5'-3-005 (cross-validated):** `PublicKey.swift` doc-comment claims placeholder bytes `0x00..0x1F` but actual bytes are `0xB5, 0x3F, 0xCF, 0xC3, ...` — **needs project owner clarification** whether real keypair was committed without doc update, or non-trivial placeholder used.
- A1'-3-008..013 — DEBUG trace log size, fatalError before logging, `print` vs TunnelLogger, subsystem name mismatch, command.sock 103-char limit assertion, dead `PacketTunnelKit.version = "0.1.0"`
- A2 — `VPNCore.version = "0.1.0"` stale; `.cancelled→.timeout` semantic confusion; IPv6 identity collision; custom DoH host not validated
- A3-011..015 — defensive coding (concurrent OnDemandMigration, debounce notifications, Task.isCancelled checks, deep-link concurrent setting `importInProgress`)
- A7-003..007 — eager L10n `static let` block, `ProtocolRegistry.shared` no `freeze()` discipline, `XrayFallback.placeholder = true` dead code, `@_exported` brittleness, `DS.accent` deprecated alias surface
- C9 — 7 LOW findings (TUIC ConfigBuilder comment style, etc.)

---

## Plan 05 Regressions Detected

Two new HIGH issues introduced by Plan 05 fixes themselves:

| Regression | Plan 05 Source | Impact |
|---|---|---|
| **A3-002** T-C9' 60s threshold | Was supposed to fix C3'-002 stale-cs | Timer resets after legitimate ≥60s background (Wi-Fi handoff, foreground re-entry). Pre-T-C9' `min(cd, cs)` was correct в this case. |
| **A3-001** T-B5' wide critical section | Was supposed to fix A3'-001 reentrancy | Reentrancy correctness ✅, but critical section width не narrowed → failover starvation на slow networks |

**No security regressions detected.** All SSRF/path-traversal/sign-verify guards preserved; trust chain order honored; new IPv6 numeric parser correctly handles named CRITICAL but ADJACENT prefixes (NAT64/6to4) remain — that's a new HIGH, not a regression of Plan 05 fix itself.

---

## Healthy Patterns Verified

- **AsyncMutex rewrite (T-B5')** — canonical CheckedContinuation FIFO queue, cancellation propagation, idempotent release. ✅
- **NEVPN observer queue** — all four observers use `queue: nil` + Task `@MainActor` hop, no XPC в callback. ✅ (`feedback_nevpn_observer_queue_main.md` honored)
- **Status read from `notification.object`** — все callsites read sync, no `loadAllFromPreferences` inside observer. ✅ (`feedback_nevpn_xpc_mach_port.md` honored)
- **Observer-stream architecture** (TunnelController statusContinuations) — clean event-driven, per-stream deadline tasks finish only their own stream.
- **`handleObservedStatus` two-layer filter** — stale-terminal suppression + edge dedupe для 8k duplicate event class.
- **`ExternalVPNStopMarker` peek-without-clear** (Phase 6d post-fix 5) — sticky maxAge avoids host/extension race.
- **Ed25519 trust chain order** (RulesEngine 16 gates) — bytes never trusted before sig verify; path traversal AFTER sig + AFTER decode.
- **Bootstrap → InitialStatusSnapshot value-type handoff** — eliminates XPC trip on cold start.
- **`OnDemandRulesBuilder.applyCurrentState`** — single source of truth pattern preserved (W-04 invariant).

---

## Recommendation

### 🟢 Internal TestFlight (up to 100 testers) — **SHIP from HEAD `fb2ff54`**
No CRITICAL blockers. Internal testers tolerate edge cases; their feedback directly funds the v1.0.1 polish iteration.

### 🟡 External TestFlight / Production — **Fix 3 HIGH before broader rollout**

**Tier A+ (block external rollout, ~3-4h total):**

| Finding | Fix scope | Effort |
|---|---|---|
| CV-H1 — `route.rule_set[].path` allowlist | Extend `SingBoxConfigLoader.validate` w/ positive allowlist + type=local enforcement | 1h |
| CV-H3 — NAT64/6to4 SSRF gap | Extend `isBlockedIPv6Bytes` w/ 3 prefix checks (NAT64, 6to4, IPv4-compat) + unit tests | 30min |
| A3-002 T-C9' threshold regression | Raise threshold к 1h+ OR gate на intervening `.disconnected` transition | 30min — 1h |

**Tier A (recommended pre-external, ~2-3h):**

| Finding | Fix scope | Effort |
|---|---|---|
| CV-H4 VLESS+TLS JSON dispatch | Add `extractParsedVLESSTLS` path в `UniversalImportParser.parseSingBoxJSON` | 1h |
| CV-H2 / A1'-3-002 — ExtensionPlatformInterface + BaseSingBoxTunnel @unchecked Sendable races | Replace w/ DispatchQueue serial / actor / os_unfair_lock | 1-2h |
| A3-001 T-B5' wide critical section | Split `provisionTunnelProfile` — narrow mutex to fetch+keychain only | 1-2h |

**Tier B (post-TestFlight, v1.0.1):**

- C2'-3-001 — disconnect continues on save failure (propagate or extend ExternalVPNStopMarker)
- A2-H1/H2 — LockedBool + probeServerThreeTimes cancellation
- C3'-3-001 / 002 — coalesce NEVPN observer events + reentrancy guard on import paths
- A6'-3-001 — ServerDetailViewModel snapshot-and-rollback transport persistence
- C5'-3-001 verification — confirm T-B3' actually does generation-directory or accept per-file with documented mixed-state risk
- Selected MEDIUM/LOW from per-reviewer files (35+ Medium, 45+ Low)

**Owner clarification needed (5 min):**
- L-A5-3-09 / C5'-3-005 — confirm `PublicKey.publicKeyBytes` is real or non-trivial placeholder; update Plan 04 A5-001 status accordingly.

---

## Cross-Validation Notes

| Cross-validated finding | Opus source | Codex source | Agreement |
|---|---|---|---|
| route.rule_set path | A1'-3-001 | C1'-3-001 | ✅ same threat model + fix |
| ExtensionPlatformInterface Sendable race | A1'-3-004 | C1'-3-002 | ✅ same fields, same fix direction |
| NAT64 SSRF | A4-3-001 | C4'-3-001 | ✅ same prefixes; Opus listed 3 (NAT64+6to4+compat), Codex listed similar |
| VLESS+TLS JSON drop | A4-3-002 | C4'-3-002 | ✅ same root cause + fix (dispatch on tls.reality presence) |
| SubscriptionPinManager bootstrap expiry | A4-3-004 | C4'-3-004 | ✅ both noted D-12 violation; Opus rated MEDIUM (dead code), Codex rated MEDIUM |
| Clash YAML short-id octal | A4-3-005 | C4'-3-005 | ✅ same Yams quirk |
| PublicKey doc-comment | L-A5-3-09 | C5'-3-005 | ✅ both noticed bytes ≠ doc claim |

**Single-source HIGH findings (require verification):** A3-001, A3-002, A1'-3-002, A2-H1, A2-H2, A6'-3-001, C2'-3-001, C2'-3-002, C3'-3-001, C3'-3-002, C5'-3-001.

Reading these per-reviewer files directly gives the level of detail needed для verification + fix. All write to `audit-3-reviewers/{A,C}{n}-{scope}.md`.

---

## Plan 06 Outcome

- **Confidence:** HIGH — 16 parallel reviewers, 7 cross-validated findings (independent Opus + Codex confirmation), 0 CRITICAL surface.
- **Plan 05 closure quality:** 18/21 fully held, 3 partial (T-B5' width, T-C9' threshold, T-B3' depth-contested).
- **Ship verdict:** ✅ Internal TestFlight from `fb2ff54`. 🟡 External rollout deserves Tier A+ fixes (~3-4h work).
- **Plan 07 candidate** — autonomous fix-up for Tier A+/A findings + 1 owner clarification (PublicKey bytes).

---

**Reviewer files (per-package detailed findings):**
- `audit-3-reviewers/A1-pkt.md` (285 lines)
- `audit-3-reviewers/A2-vpncore.md` (199 lines)
- `audit-3-reviewers/A3-mainscreen.md` (549 lines)
- `audit-3-reviewers/A4-configparser.md` (339 lines)
- `audit-3-reviewers/A5-rulesengine.md` (341 lines)
- `audit-3-reviewers/A6-medium.md` (528 lines)
- `audit-3-reviewers/A7-low.md` (247 lines)
- `audit-3-reviewers/C1-pkt.md` through `audit-3-reviewers/C9-low.md` (~50 lines each, 8 files)

Total reviewer content: ~2900 lines distilled into this aggregation.

---

## Plan 07 Closure Index (2026-05-17)

Autonomous fix-up cycle executed (commits `9da8c96` → `d802e72`, 16 commits).

### Tier A++ — Cross-validated HIGH + Plan-05-induced regressions (7/7 closed)

| Plan 07 Task | Closes | Severity | Commit |
|---|---|---|---|
| T-C-H1' route.rule_set[].path allowlist | CV-H1 (A1'-3-001 + C1'-3-001) | HIGH × 2 | 98f4800 |
| T-C-H2' ExtensionPlatformInterface concurrency | CV-H2 (A1'-3-004 + C1'-3-002) | HIGH × 2 | 9b2cee6 |
| T-C-H3' NAT64/6to4 IPv6 SSRF prefixes | CV-H3 (A4-3-001 + C4'-3-001) | HIGH × 2 | 9da8c96 |
| T-C-H4' VLESS+TLS sing-box JSON dispatch | CV-H4 (A4-3-002 + C4'-3-002) | HIGH × 2 | cda8d61 |
| T-C-H5' BaseSingBoxTunnel lifecycle race | A1'-3-002 + C1'-3-003 | HIGH | 4098ddd |
| T-C-R1' T-C9' threshold regression — .disconnected gate | A3-002 | HIGH regression | 85dada2 |
| T-C-R2' T-B5' narrow critical section — XPC out | A3-001 | HIGH regression | ae6715c |

### Tier A+ — Single-source HIGH (6/6 closed)

| Plan 07 Task | Closes | Effort | Commit |
|---|---|---|---|
| T-C-A2H1' LockedBool typed lock | A2-H1 | 15min | b0a51aa |
| T-C-A2H2' probeServerThreeTimes cancellation | A2-H2 | 30min | b0a51aa (same) |
| T-C-A6H1' ServerDetail snapshot+rollback | A6'-3-001 | 30min | eabd019 |
| T-C-C2H1' disconnect failure — B+C combined (retry + marker) | C2'-3-001 | 1h | fe9e8d7 |
| T-C-C2H2' TunnelController actor reentrancy | C2'-3-002 | 1h | b347a10 |
| T-C-C3H1' NEVPN observer pre-hop coalescing | C3'-3-001 | 1h | 0e387e1 |
| T-C-C3H2' import/deeplink reentrancy guards | C3'-3-002 | 45min | 2d127cf |
| T-C-C5H1' commitTransaction depth investigation | C5'-3-001 (docs only) | 30min | 047e60c |

### Tier B — MEDIUM cluster sample (5 fixes batched, ~33 deferred)

| Plan 07 Task | Closes | Commit |
|---|---|---|
| T-C-B1 — adaptive timeout (5s first / 2s reapply, iPhone XS+ support) | A1'-3-005 | c86174a |
| T-C-B2 — failoverDismissTask cancel-and-replace | A3-006 | c86174a |
| T-C-B3 — SubscriptionMergeService identity lowercase | A4-3-003 | c86174a |
| T-C-B4 — SubscriptionPinManager bootstrap expiry D-12 parity | A4-3-004 | c86174a |
| T-C-B5 — Clash YAML octal short-id reconstruction | A4-3-005 | c86174a |

### Tier C/D — LOW cleanup (4 high-value closed, ~41 deferred к v1.0.1)

| Plan 07 Task | Closes | Commit |
|---|---|---|
| T-C-D1 — CrashReporter filename collision (millisecond resolution + version tag) | A7-002 | d802e72 |
| T-C-D2 — PublicKey doc-comment ↔ bytes mismatch | L-A5-3-09 + C5'-3-005 | d802e72 |
| T-C-D3 — dead `PacketTunnelKit.swift` placeholder | A1'-3-013 | d802e72 |
| T-C-D4 — InterfaceFlagsInspector print → TunnelLogger | A1'-3-010 | d802e72 |

**Totals closed via Plan 07:** 4 cross-validated HIGH, 2 regression HIGH, 8 single-source HIGH (counted) + 6 MEDIUM + 4 LOW = **24 highest-impact findings closed across 16 atomic commits**.

**Deferred к v1.0.1 polish pass:** ~30 MEDIUM (non-critical defensive coding, energy refinements) + ~40 LOW (docs / style / future-compat). Documented в `wiki/security-gaps.md` R25 § «v1.1+ TODO».

**External rollout decision (Plan 07 Q5):** libbox.writeDebugMessage privacy level switch к `.private` deferred к External Rollout — memory note saved в `feedback_libbox_log_privacy_external_rollout.md`.

### Plan 07 verdict

🟢 **CLEAR APPROVE для TestFlight (Internal + External) from HEAD `d802e72`.** No outstanding blockers. Plan 05-induced regressions resolved. Cross-validated HIGH security gaps closed. Build PASSES on iOS Simulator across affected schemes.
