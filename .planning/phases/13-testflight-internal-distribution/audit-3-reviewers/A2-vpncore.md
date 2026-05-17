# A2 — VPNCore audit (Opus 4.7)

**Reviewer:** A2
**Scope:** `BBTB/Packages/VPNCore/Sources/VPNCore/` (13 files)
**Baseline:** `fb2ff54` (Plan 05 + Tier-D LOW batch closed)
**Focus:** Thread Safety + Logic/Bugs + Security
**Mode:** Read-only, single-pass.

---

## Scope clarification

The task brief lists "TunnelController, NEVPNStatus state machine, OnDemandRulesBuilder, KillSwitch policy, KeychainStore". Verified at baseline `fb2ff54`: **only `KeychainStore` lives in VPNCore**. `TunnelController`, on-demand rules, kill-switch enforcement and the `NEVPNStatusDidChange` handler all live in `AppFeatures/MainScreenFeature` and `PacketTunnelKit`. I therefore audited the 13 VPNCore files actually present (TunnelController etc. are presumably covered by A3'/C3' on MainScreenFeature). The four memory files listed are still relevant for cross-reference but no in-scope file calls `NEVPNConnection`, schedules reconnects, or manages user intent flags.

VPNCore files in scope: `VPNCore.swift`, `KeychainStore.swift`, `KeychainPersistResult.swift`, `ServerConfig.swift`, `Subscription.swift`, `SwiftDataContainer.swift`, `DNSConfig.swift`, `TransportConfig.swift`, `ParsedConfigs.swift`, `ServerProbeService.swift`, `ProbeResult.swift`, `ServerScore.swift`, `VPNProtocolHandler.swift`.

---

## Verdict

🟢 **CLEAR** for TestFlight from a VPNCore standpoint. Plan 05 Keychain hardening (T-C1' + T-C2') landed correctly. No CRITICAL findings. Two HIGH findings about state-machine/edge-case logic, four MEDIUM, six LOW. All HIGH findings are bounded — they can move connection state to an inconsistent UI display but do not exfiltrate secrets nor break the tunnel for a typical Internal-TestFlight user.

---

## Plan 05 closure verification

| Plan 05 task | File:line | Status |
|---|---|---|
| **T-C1'** — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | `KeychainStore.swift:89` | ✅ **CLOSED** — `addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` set only on add path. Lookup/delete queries omit `kSecAttrAccessible` (correct — accessibility is not a lookup predicate). |
| **T-C2'** — Synchronizable cleanup sweep | `KeychainStore.swift:75-77` | ✅ **CLOSED** — sweep query with `kSecAttrSynchronizableAny` runs **before** the non-sync `SecItemDelete` on every `save()` call. Status return value is intentionally discarded (`_ = SecItemDelete(...)`) — correct: not-found is the common case and not actionable. |
| Plan 02 T-B3 (lookup/add separation, `kSecAttrSynchronizable=false` pinned, safe-cast in `accessibleFlag`) | `KeychainStore.swift:64-92, 152-154` | ✅ Confirmed closed |

Per the audit-2 doc I am instructed not to re-report `C2'-001` and `C2'-003`. I confirm they are closed at this baseline.

---

## HIGH findings (2)

### A2-H1 — `LockedBool` uses `os.OSAllocatedUnfairLock` without explicit `import os.lock` — `OSAllocatedUnfairLock` is technically `os.lock.OSAllocatedUnfairLock` and is silently `@unchecked Sendable` here

- **Severity:** HIGH (concurrency correctness, single-shot bug class)
- **File:** `ServerProbeService.swift:212-223`
- **Description:** The class declares `private let lock = OSAllocatedUnfairLock()`. The file imports `os` (line 18). `OSAllocatedUnfairLock` was introduced in macOS 13 / iOS 16 and lives in the `os` module — so the import is sufficient at the symbol level. However the `LockedBool` class is marked `@unchecked Sendable` with the explanation «компилятор не видит OSAllocatedUnfairLock как synchronization». That comment is incorrect for current SDKs: `OSAllocatedUnfairLock` is itself `Sendable` (an `~Copyable` struct wrapping a stored state), so the wrapper does not need `@unchecked Sendable` — the unchecked annotation defeats the compiler's ability to flag a future regression (e.g. if someone adds a non-Sendable stored property). More importantly, `OSAllocatedUnfairLock()` is the **stateless** variant that protects an unrelated boolean held outside the lock. The `flipped` property is mutated *inside* `lock.withLock { ... }` block, so the lock is functioning, but the pattern is fragile: any future contributor who adds a `flipped = true` *outside* `withLock` will compile cleanly because `@unchecked Sendable` suppresses the warning.
- **Why HIGH:** Single-resume invariant for `CheckedContinuation<ProbeResult, Never>` is *critical*. A double-resume is `fatalError` in Swift runtime — the app crashes. Today the code is correct, but the `@unchecked Sendable` mask removes the safety net.
- **Repro path:** None today; this is a regression-prevention finding.
- **Suggested fix:** Replace with `OSAllocatedUnfairLock<Bool>(initialState: false)` and `lock.withLock { state in guard !state else { return false }; state = true; return true }`. Drop `@unchecked Sendable` (the typed variant is `Sendable` automatically). Two-line change.
- **Effort:** 10 min.

### A2-H2 — `ServerProbeService.probeServerThreeTimes` loss-rate denominator silently masks `Task.isCancelled` in the middle of a 3-probe round

- **Severity:** HIGH (logic, autoSelect correctness)
- **File:** `ServerProbeService.swift:174-199`
- **Description:** The function does 3 sequential probes with `if Task.isCancelled { break }` between them, then computes:
  ```swift
  let totalAttempts = max(1, latencies.count + failures)
  let lossRate = Double(failures) / Double(totalAttempts)
  ```
  If the outer task is cancelled after iteration 0 returned `.ok`, the function returns `ProbeAggregate(avgLatencyMs: <one sample>, failures: 0, lossRate: 0.0, probedAt: now)`. That aggregate is then **persisted to SwiftData** (Phase 3 Plan 02 sites) and **used in `ServerScore.autoSelect`**. A cancelled-after-one-OK probe scores **identically** to a clean 3/3-OK probe — `score = ms × 1.0`. AutoSelect will therefore prefer the cancelled server over an equally-fast server that completed 3/3 with `failures: 0`.
  
  Worst case: a pull-to-refresh that the user cancels by swiping away the sheet ends up writing single-sample `failedProbeCount = 0` rows to SwiftData, polluting future autoSelect for the lifetime of the row (until next manual refresh).
- **Why HIGH:** Silent correctness bug on the auto-select hot path. The aggregate looks legitimate to downstream code.
- **Suggested fix:** Either return `nil` aggregate / a `wasCancelled: Bool` flag and skip the SwiftData write at the consumer, or set `avgLatencyMs = nil` whenever `latencies.count + failures < 3` to mark the row unreachable rather than "best in pool".
- **Effort:** 30 min including 2 unit tests.

---

## MEDIUM findings (4)

### A2-M1 — `ServerProbeService.probeOnce` returns latency rounded **down** with attosecond truncation; sub-ms probes report `1ms` indistinguishable from real 1ms

- **Severity:** MEDIUM (telemetry quality, autoSelect tie-breaking)
- **File:** `ServerProbeService.swift:60-64`
- **Description:**
  ```swift
  let ms = Int(comps.seconds * 1000) + Int(comps.attoseconds / 1_000_000_000_000_000)
  cont.resume(returning: .ok(latencyMs: max(1, ms)))
  ```
  `Duration.components.seconds` is `Int64`, so `* 1000` truncates. `attoseconds / 1e15` gives milliseconds but **floors**, not rounds. A 0.999ms probe and a 0.001ms probe both report `1ms` (clamped by `max(1, ms)`). For typical LAN/loopback probes this collapses real latency differences. For autoSelect this means servers within the local data centre tie-break arbitrarily by SwiftData insertion order.
- **Why MEDIUM:** Visible in unit tests on a local mock server. In production over real WAN, probes are 30-300ms so this hides 1-3% precision, not a regression for TestFlight.
- **Suggested fix:** Use `Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15` then `Int(round(...))`, or simpler: `elapsed.formatted(.units(allowed: [.milliseconds]))` numeric path.
- **Effort:** 10 min.

### A2-M2 — `SwiftDataContainer.migratePhase2ToPhase3` force-unwraps `subscriptionURL!` inside `Dictionary(grouping:by:)` — predicate-guarded but fragile to SwiftData predicate evaluation quirks

- **Severity:** MEDIUM (defensive depth, SwiftData edge case)
- **File:** `SwiftDataContainer.swift:98-99`
- **Description:**
  ```swift
  let descriptor = FetchDescriptor<ServerConfig>(
      predicate: #Predicate { $0.subscriptionURL != nil }
  )
  let rows = try context.fetch(descriptor)
  // ...
  let grouped = Dictionary(grouping: rows) { $0.subscriptionURL! }
  ```
  Memory `feedback_swiftdata_uuid_predicate.md` documents a known SwiftData quirk: `#Predicate` with nullable fields can return inconsistent results on certain platforms. The comment claims the predicate filters nil but the project itself has a documented case of SwiftData predicates silently returning the wrong set. If `subscriptionURL` happens to come back nil for any row that the predicate engine evaluated wrong, this migration **crashes the migration Task** — which is run from a *detached background Task* (`runMigrationsIfNeeded`) and the error path is caught by `do/catch`, but a force-unwrap is `fatalError`, not throwing, so it terminates the process.
- **Why MEDIUM:** A crash during deferred migration is a hard launch-loop bug. Probability is low (SwiftData predicate on non-optional `!= nil` is well-tested for `String?`) but the consequence is severe.
- **Suggested fix:** `let grouped = Dictionary(grouping: rows.compactMap { row in row.subscriptionURL.map { (row, $0) } }) { $1 }` (preserve the row alongside the non-nil URL). Or simpler: `let grouped = Dictionary(grouping: rows) { $0.subscriptionURL ?? "" }; grouped.removeValue(forKey: "")`.
- **Effort:** 15 min.

### A2-M3 — `KeychainStore.accessGroup` reads `Bundle.main.infoDictionary["AppIdentifierPrefix"]` synchronously every call from any thread — no caching, no thread-safety contract documented

- **Severity:** MEDIUM (perf + concurrency smell)
- **File:** `KeychainStore.swift:34-40, 161-174`
- **Description:** Every call to `save/load/delete/accessibleFlag` invokes `teamIdentifierPrefix()` which reads `Bundle.main.infoDictionary`. `Bundle.main` is documented thread-safe but `infoDictionary` materialises an `NSDictionary` snapshot — repeated calls on hot paths (e.g. extension-side bulk read on tunnel start) traverse the dict each time. More importantly, the *fallback path* (production = entitlement misconfiguration) emits an `os.Logger.warning` **every call** — under a tight loop this floods unified logging and the operator sees the same warning thousands of times. There's no rate-limiting or one-shot guard.
- **Why MEDIUM:** Not a correctness bug. Slight perf and observability degradation. In a misconfigured build the log spam could mask other warnings.
- **Suggested fix:** Add `private static let cachedPrefix: String? = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String` and emit the warning **once** via `dispatch_once`-style `static let didWarn: Void = { logger.warning(...) }()`. Then `accessGroup` becomes a pure constant computed once per process.
- **Effort:** 15 min.

### A2-M4 — `ServerProbeService.probeOnce` accepts host strings without any validation (IPv6 literal, IDN, empty, control chars)

- **Severity:** MEDIUM (defence-in-depth)
- **File:** `ServerProbeService.swift:39-44`
- **Description:** `host: String` is passed straight to `NWEndpoint.Host(host)`. Empty string, whitespace-only string, IDN forms — all silently produce an `NWEndpoint.Host` that may either crash inside Network.framework or fail with an opaque `.failed` state. There is no input contract documented. Phase 13 audit-2 closed `A4'-004 URI port=0` and `A4'-005 outbound-tag 256 cap` for the parser side, but `probeOnce` is now called from `ServerProbeService.probeServerThreeTimes` with `(host: srv.host, port: srv.port)` — `host` comes directly from `ServerConfig.host` which is whatever the user pasted. Port has a `1..<65536` check at line 40, but host has none.
- **Why MEDIUM:** Doesn't compromise security (probe is TCP SYN, not data) but a malformed host can stall a slot in the `cap=8` semaphore for the full 500ms timeout. Hostile pasted subscription with 30 empty-string hosts → ~2s of useless slot occupancy on every pull-to-refresh.
- **Suggested fix:** At the top of `probeOnce`: `guard !host.isEmpty, host.count < 256, !host.contains(where: \.isNewline) else { return .error("invalid host") }`.
- **Effort:** 10 min.

---

## LOW findings (6)

### A2-L1 — `VPNCore.version` is `"0.1.0"` (Phase 1 marker) at the brink of TestFlight v1.0 upload

- **File:** `VPNCore.swift:4`
- The package-level version constant is unused anywhere I could find (no other file references `VPNCore.version`), but if it ever surfaces in diagnostics it will mislead. Bump to a meaningful number or remove. **Effort: 2 min.**

### A2-L2 — `ServerProbeService.probeOnce` `.cancelled` branch interprets cancellation as `.timeout` — semantic confusion

- **File:** `ServerProbeService.swift:78-84`
- The comment says «cancel мог прийти от outer Task или от нашего же manual timeout». If outer-Task cancellation enters `.cancelled` state-change first and the timeout `Task` hasn't run yet, the returned value is `.timeout`. But `Task.isCancelled` is true, so the consumer (`probeServerThreeTimes`) will `break` out of the 3-probe loop *after* recording the `.timeout` as `failures += 1`. That fake-failure goes into `ProbeAggregate.failures` (per A2-H2 above).
- **Fix:** Have `.cancelled` branch return `.error("cancelled")` and skip incrementing failures upstream, or peek `Task.isCancelled` inside the branch.
- **Effort: 10 min.**

### A2-L3 — `ServerConfig.identity = "host:port:protocolID"` collides for IPv6 hosts

- **File:** `ServerConfig.swift:134-136`
- IPv6 host `2001:db8::1` paired with port 443 yields identity `"2001:db8::1:443:vless-reality"` — indistinguishable from a host literally named `"2001:db8:"` on port `1` with the rest as `":443:vless-reality"`. Phase 3 Plan 04 merge-by-identity (D-14) could mis-merge two distinct IPv6 servers.
- **Suggested fix:** `"\(host)|\(port)|\(protocolID)"` (pipe-delimit) or bracket the IPv6 host. **Effort: 5 min.**

### A2-L4 — `ServerConfig.countryFlag` regex `^[A-Za-z]{2}$` re-compiled on every UI render

- **File:** `ServerConfig.swift:111-122`
- Called from list cells. `NSRegularExpression` compilation per row × scroll = wasted CPU. Use `code.allSatisfy(\.isLetter) && code.count == 2`. **Effort: 5 min.**

### A2-L5 — `DNSConfig.dohAddress()` returns user-supplied `.custom(address:)` verbatim — no length/scheme cap

- **File:** `DNSConfig.swift:69-71`
- Doc comment says «Caller обязан pre-formated» but VPNCore is the type owner and an attacker (subscription with crafted custom DNS) could push a 100KB string through to sing-box config rendering. ConfigImporter likely validates; verifying contract belongs here too. **Effort: 10 min (add `init` validation).**

### A2-L6 — `SwiftDataContainer.runMigrationsIfNeeded` race on `migrationDoneKey` flag

- **File:** `SwiftDataContainer.swift:70-81`
- If the app launches and crashes between `try migratePhase2ToPhase3` returning and `UserDefaults.set(true, ...)` completing, the migration **re-runs** on next launch. That's per-row idempotent (line 106-114 `if let existing = ... { reuse }`) so no duplicate `Subscription` rows, but UserDefaults set is not transactional with the SwiftData write — the inverse case (UD set succeeds but SwiftData rollback) leaves a "migrated" flag with un-migrated data. Practically zero impact for Internal TestFlight (no rollback semantic exists in `migratePhase2ToPhase3`), but logically the flag should be set inside the same SwiftData transaction or use a sentinel row in SwiftData instead of UserDefaults.
- **Effort: 30 min if pursued; suggest defer to v1.1+.**

---

## What I explicitly did NOT find

- **Force-cast `as!`** — only one removed in T-B3 (`accessibleFlag`), no others. ✅
- **`Yandex`/`yandex` strings** — Phase 6 cleanup held. `grep -rn yandex VPNCore/` = 0. ✅
- **Hardcoded secrets / PII in `os.Logger`** — `keychainLogger.warning` formats OSStatus only (no tag, no secret). `probe waiting/failed` log emits `err.debugDescription` with `privacy: .public` — `NWError.debugDescription` does **not** leak hostnames, only category. ✅
- **Synchronizable iCloud Keychain leak** — pinned `false` in all four query call sites (`save` × 2, `load`, `delete`, `accessibleFlag`). T-C2' sweep additionally cleans legacy items. ✅
- **App Group identifier drift** — `"group.app.bbtb.shared"` matches the documented value in `feedback_extension_toggle_app_group_suite.md`. ✅
- **`@Model` Sendable misuse** — `ServerConfig`, `Subscription` are not crossed actor boundaries inside VPNCore; only `(UUID, host, port)` tuples leave the actor in `ServerProbeService.probeAll`. ✅ (Pitfall 4 respected.)
- **Two-phase init / actor-actor cycles** — none of the 13 VPNCore files hold actor-actor references. `ServerProbeService` is a standalone actor. ✅
- **`#Predicate` with `UUID?`** — only one `#Predicate` in scope (`SwiftDataContainer.swift:93,103`), both on `String?` not `UUID?`. The known UUID quirk does not apply. ✅

---

## Files reviewed (13)

| File | LOC | Notable |
|---|---|---|
| `VPNCore.swift` | 6 | Stale 0.1.0 version (A2-L1) |
| `KeychainStore.swift` | 175 | T-C1' + T-C2' verified; A2-M3 caching smell |
| `KeychainPersistResult.swift` | 20 | Clean |
| `ServerConfig.swift` | 137 | A2-L3 IPv6 identity collision, A2-L4 regex compile |
| `Subscription.swift` | 37 | Clean |
| `SwiftDataContainer.swift` | 126 | A2-M2 force-unwrap, A2-L6 flag race |
| `DNSConfig.swift` | 73 | A2-L5 custom DoH unvalidated |
| `TransportConfig.swift` | 49 | Clean |
| `ParsedConfigs.swift` | 302 | Clean (struct types, no behaviour) |
| `ServerProbeService.swift` | 223 | A2-H1 LockedBool, A2-H2 cancellation loss-rate, A2-M1 ms truncation, A2-M4 host validation, A2-L2 cancelled→timeout |
| `ProbeResult.swift` | 53 | Clean |
| `ServerScore.swift` | 23 | Clean (pure function) |
| `VPNProtocolHandler.swift` | 38 | Clean (protocol-only) |

---

## Recommendation

**No findings block TestFlight upload.** All HIGH findings are correctness / robustness improvements in non-fatal paths. Suggested triage:

- **Pre-TestFlight (optional, ~45 min total):** A2-H1 (typed `OSAllocatedUnfairLock<Bool>`) + A2-H2 (cancellation drops aggregate). Both are 1-file changes with unit-test coverage already present in `ServerProbeServiceTests`.
- **v1.1+ backlog:** A2-M1..M4, A2-L1..L6.

Net: **VPNCore is shippable at `fb2ff54`** for Internal TestFlight.
