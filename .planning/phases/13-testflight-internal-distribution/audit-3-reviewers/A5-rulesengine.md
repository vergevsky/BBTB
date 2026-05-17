# A5 — RulesEngine package audit (Opus 4.7 reviewer #5)

**Baseline:** `fb2ff54` (Tier-D LOW batch close).
**Scope:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/` — 10 Swift files (~1290 LOC).
**Lens:** Security (Ed25519 signing trust chain, RulesFetcher SSRF, atomic cache writes, allowlist regex) + Thread safety (actor isolation, NotificationCenter pattern) + Logic (manifest validation, generation atomic swap edges, `.bbtb-staging` cleanup).
**Plan 05 closures (T-A1', T-B3', T-B4', T-B5'-extra, T-C11') treated as PRIOR ART — not re-reported unless I find a hole in the patch.**

---

## Verdict

**🟢 APPROVE for TestFlight Internal** (with operational caveats inherited from Plan 04 — placeholder Ed25519 key + placeholder mirror URLs).

Plan 05 closures all hold up on re-read. The RulesEngine module is structurally clean — actor isolation is consistent, the trust chain (signature → sha256 → atomic write) is enforced before any disk mutation, and the `bbtbRulesEngineDidUpdate` NotificationCenter usage follows the `queue: nil` + MainActor-hop discipline (memory `feedback_nevpn_observer_queue_main`).

Re-audit findings: **0 CRITICAL, 0 HIGH, 6 MEDIUM, 8 LOW**. Most are defence-in-depth recommendations or test-coverage holes (not shipping bugs). Three notable items:

1. **M-A5-3-01** — `T-B3' commitTransaction` partial-failure semantics: if Phase 3 rename succeeds for files `0..i-1` then throws at `i`, the already-renamed final files stay committed while the rest stay old. Caller (`RulesEngineCoordinator`) doesn't see the partial-success state — `cachedManifest` is **not** updated (the throw bubbles through), so reader sees mixed-old-new but in-memory manifest still claims OLD. **Mismatch window** but bounded: extension's libbox SRS verify will reject mismatched sha256 ⇒ defence in depth. **Recommend**: document explicitly in commitTransaction doc-comment that group atomicity is **best-effort** and that callers MUST treat partial-failure as "cache may be in mixed state until next successful refresh".
2. **M-A5-3-02** — `commitTransaction` does NOT fsync the directory after rename. On unexpected power loss (iOS device reboot kill during refresh), POSIX rename can be reordered relative to file content writes ⇒ committed `final` may point to zero-byte inode. Theoretically out-of-scope for iOS app sandboxed environment but bears documenting.
3. **M-A5-3-03** — `Step 8` batch order writes manifest LAST. Good (defensive). But on **failure of the very last manifest rename**, in-memory `cachedManifest` is still updated to `newManifest` AFTER the throw bubbles — wait, re-reading: no, `cachedManifest = newManifest` is on line 474, **AFTER** the do-block — so a thrown `commitTransaction` short-circuits to the catch + return false ⇒ in-memory stays at OLD version. ✅ correct. Not a finding. (Removing.)

Tests coverage gap: **no test exercises `commitTransaction` directly** (`SRSCacheStoreTests.swift` only covers `write/read/mtime/exists`). The integration tests in `RulesEngineCoordinatorTests` exercise the happy path via `performBackgroundRefresh`, but partial-failure paths (Phase 2 throws on 3rd staging, Phase 3 throws on 2nd rename) are uncovered. Recommend adding `SRSCacheStoreTests.test_commitTransaction_phase3_partialFailure` before v1.1+ refactor to versioned directory swap.

---

## Plan 05 closure verification

| Plan 05 task | What I checked | Status |
|---|---|---|
| **T-A1' (986c2af)** — `isValidSHA256Hex` reject empty/malformed | `RulesEngineCoordinator.swift:618-624` — exactly 64 chars + every char `isHexDigit`. Called from line 414 BEFORE `actualHex` compare. Empty / 63-char / non-hex all rejected via `lastFailureReason = .signature` ⇒ `ForceUpdateOutcome.signatureFailure`. | ✅ **HOLDS** |
| **T-B3' (74dd020)** — generation directory + atomic swap | `SRSCacheStore.commitTransaction` lines 78-119. Two-phase (stage all, then rename all). Phase-3 partial-failure cleaned via `defer { cleanupStagingFiles() }`. | ✅ **HOLDS** with caveats — see M-A5-3-01 below (best-effort, NOT true atomic swap). Doc-comment lines 73-77 explicitly acknowledges. |
| **T-B4' (74dd020)** — positive allowlist regex `^[A-Za-z0-9][A-Za-z0-9._-]*$` | `SRSCacheStore.validateBareFilename` lines 146-167. Regex applied first; explicit `..` reject second; 256-char cap. | ✅ **HOLDS** — comprehensive (also rejects Unicode fullwidth solidus `／` which fails the ASCII regex). |
| **T-B5'-extra (74dd020)** — `.bbtb-staging` cleanup | `SRSCacheStore.cleanupStagingFiles` lines 37-43. Called from init (line 32) AND `defer` in `commitTransaction` (line 85). | ✅ **HOLDS** |
| **T-C11' (74dd020)** — manifest-declared sigPath preserved | `RulesEngineCoordinator.swift:380, 429, 460` — tuple now carries `sigPath: String` as 5th field; batch writes `(payload.sig, payload.sigPath)` instead of derived `"\(basename).sig"`. | ✅ **HOLDS** |

**No regressions** detected from these closures.

---

## Findings (re-audit)

### MEDIUM

#### M-A5-3-01 — `commitTransaction` Phase 3 partial-failure: callers see undocumented mixed-state cache

- **File:** `SRSCacheStore.swift:94-115`
- **Severity:** MEDIUM (logic + integrity caveat)
- **Description:** Phase 3 renames each staged file to its final destination sequentially. If renaming files `0..N-1` succeeds but file `N` throws (POSIX `rename(2)` failure — e.g., readonly mount, ENOSPC), the function rethrows the error. **Already-renamed final files stay committed** (`replaceItemAt` is atomic per file; there is no rollback). Remaining stagings get nuked by `defer cleanupStagingFiles()`. Caller in `RulesEngineCoordinator.performBackgroundRefresh:464` catches the error, **does not update `cachedManifest`**, returns `false`. Now the on-disk state has:
  - Files `0..N-1` = new bytes
  - Files `N..end` = old bytes (or missing for first-time write)
  - `baseline-rules-manifest.json` on disk = OLD (it was scheduled LAST in `batch` ⇒ not yet renamed when failure occurred)
  - In-memory `cachedManifest` = OLD
  
  **End state:** Extension `libbox` rule-set watcher (PacketTunnelProvider) sees mtime changes on files `0..N-1`, attempts to reload, but its own sha256 verify against the OLD on-disk manifest entries will mismatch (because the new bytes have new sha256s and the manifest is still OLD). So in practice the extension rejects and keeps using the previous in-memory rule-set. Defence in depth holds. **But this depends on extension-side sha256 enforcement which I cannot confirm in this scope.** If extension does NOT verify sha256 from manifest, mixed-state is exploitable for partial rule-bypass.
  
- **Impact (best case):** Extension stays on stale rules ⇒ user-visible "rules didn't update" but no security regression.
- **Impact (worst case if extension trusts on-disk SRS without re-checking manifest hash):** Mixed-old-new rule-set ⇒ unpredictable routing for the inconsistent file slot until the next successful refresh.
- **Suggested fix (Tier C, post-v1.0):** Move to a real "versioned directory + atomic pointer" scheme (the doc-comment already mentions this as a v1.1 target). Until then, **document in the doc-comment**: "Group atomicity is BEST-EFFORT. Partial Phase 3 failure leaves cache in a mixed state. Extension MUST re-verify each SRS sha256 against currently-cached manifest before accepting rules." Add a sentinel file write at the start of `commitTransaction` (e.g., `.commit-in-progress`) and clear it on success — extension can use this as a "do not read" signal.
- **Why not HIGH:** Real-world iOS deployment — POSIX rename on App Group container almost never fails post-staging (single-volume, container always writable for owning app). Probability of triggering is low. And the integrity chain holds **if** extension re-verifies — which it should per architecture (the verification doc lines 256-267 explicitly state this defense-in-depth model).

#### M-A5-3-02 — No `fsync` between stage write and rename ⇒ power-loss can leak zero-byte finals

- **File:** `SRSCacheStore.swift:91, 103, 105`
- **Severity:** MEDIUM (durability)
- **Description:** `entry.data.write(to: staging, options: .atomic)` writes bytes but does not guarantee they're flushed to stable storage. On iOS this is mostly academic — the app process being killed before flush is rare, but unexpected device reboot (battery yank, kernel panic) during a refresh CAN result in: rename ordering visible (final exists), data ordering not visible (final is zero-byte or contains old inode pointing nowhere).
- **Impact:** Next launch — extension reads a corrupted SRS file ⇒ libbox rule-set load fails ⇒ defense layers reject and user keeps old behavior. User-visible glitch only.
- **Suggested fix (Tier D, post-v1.0):** Wrap final rename in a `FileHandle` `synchronize()` call on the directory after Phase 2 completes. Or use `Data.WritingOptions` that include `.atomicWrite` semantics (already done) plus explicit `fsync` on the staging file before rename:
  ```swift
  let fh = try FileHandle(forWritingTo: staging)
  try fh.synchronize()
  try fh.close()
  ```
- **Why not HIGH:** iOS sandbox lifecycle makes this extremely unlikely to trigger in production. Worst case is recoverable via the next successful refresh.

#### M-A5-3-03 — `RulesEngineCoordinator.bootstrap()` failure path leaves cache in undefined partial state

- **File:** `RulesEngineCoordinator.swift:226-251`
- **Severity:** MEDIUM (logic — first-launch recovery)
- **Description:** `bootstrap()` writes 8 files sequentially using `cache.write(_:filename:)` (single-file atomic). If write #5 throws (e.g., disk full mid-bootstrap on a near-full device), files 1-4 are committed and files 5-8 are missing. Comment line 249-250 acknowledges fail-soft: "currentSnapshot() returns nil; UI displays 'rules not loaded' state." But `await store.exists(filename: "baseline-rules-manifest.json")` on next launch (line 202) MIGHT return `true` (manifest was first in the loop, line 229) ⇒ idempotency check thinks "already bootstrapped" ⇒ partial baseline stays, never recovers.
- **Impact:** Pathological corner case — only triggers if disk fills exactly during first-launch bootstrap (extremely rare on iOS devices that pre-check free space). Recoverable by user deleting and reinstalling app. No security implication (signature verification still gates any new writes; missing files = no rules in that category = sing-box default routing).
- **Suggested fix (Tier D):** Wrap bootstrap in `commitTransaction` (which it should have been from the start, given Plan 05 added it). Single batch of 8 files = group-atomic-ish under the same best-effort semantics, AND consistent with refresh code path.
- **Why not HIGH:** Real impact is "user sees no rules until uninstall+reinstall" — annoying, not insecure.

#### M-A5-3-04 — RulesFetcher ephemeral session created per-fetch in mirror loop = no connection reuse

- **File:** `RulesFetcher.swift:129-144`
- **Severity:** MEDIUM (performance, not security)
- **Description:** Each call to `RulesFetcher.fetch(url:session:maxBytes:)` with `session === URLSession.shared` creates a fresh ephemeral `URLSession` (lines 131-140). `fetchWithFailover` iterates mirrors sequentially — for each mirror this is a NEW TLS handshake + DNS lookup. Manifest+sig+3×SRS+3×SRS-sig = 8 fetches × (TLS + DNS) = noticeably slow. Worse on a flaky network where a single connection could pool retries.
- **Impact:** Performance: cold rules refresh likely takes 2-4× longer than necessary. Not security.
- **Suggested fix (Tier C):** Lift session creation to `fetchWithFailover` and reuse across the failover loop. Even better — make `RulesFetcher` hold an actor-isolated shared session, invalidated on `deinit`. **Defensive note:** for HTTPSRedirectGuard to remain effective, the session MUST still go through the guard delegate — which is already wired. Just hoist the session lifecycle.
- **Cross-check:** `SubscriptionURLFetcher` has the same per-fetch session creation pattern (lines 147-162) and is in scope for a separate audit. Not a duplicate finding here, but the same fix pattern applies.

#### M-A5-3-05 — `RulesEngineCoordinator.performBackgroundRefresh` `Step 6b` uses `.decode` for path-traversal rejection — misleading failure classification

- **File:** `RulesEngineCoordinator.swift:368`
- **Severity:** MEDIUM (logic + UX)
- **Description:** When manifest contains a malicious filename, `lastFailureReason = .decode` is set, which maps to `.networkFailure` in `forceUpdate` outcome (line 530). User sees "network error" toast when the actual cause is **a signed manifest that contains a path-traversal attempt** — a much more serious operational signal that should be distinguishable. Should set `.signature` (which would map to `.signatureFailure` — accurate per security model: signed manifest with rejected content = signature trust breach).
- **Impact:** Operators (admin) cannot distinguish "VPS published malicious manifest" from "user has bad WiFi" in user-reported logs.
- **Suggested fix (Tier C, 1-line):**
  ```swift
  // Step 6b
  lastFailureReason = .signature  // was .decode
  ```
- **Why not HIGH:** Strictly cosmetic for UX; security gate still works (the refresh is rejected). But this hides a critical operational signal.

#### M-A5-3-06 — `BaselineRulesLoader.loadSRS` ignores `category` in sigData filename → defensive but wasteful pattern

- **File:** `BaselineRulesLoader.swift:50-62`
- **Severity:** LOW-MEDIUM (code clarity)
- **Description:** The CodingKey trick on line 60 — `loadResource(name: "\(basename).srs", ext: "sig")` — works because `Bundle.module.url(forResource:withExtension:)` strips the extension. It's correct but non-obvious. If someone refactors `loadResource` to use `name + "." + ext` directly, this breaks silently (would look up `bbtb-baseline-block.srs.sig` as `name` ⇒ `bbtb-baseline-block.srs.sig.sig` ⇒ nil).
- **Impact:** Minor — refactor hazard. No security implication.
- **Suggested fix (Tier D):** Add a unit test in `BaselineRulesLoaderTests.swift` (does not exist — gap) asserting that `.sig` files load correctly for all three categories. The current test suite has zero coverage of `BaselineRulesLoader`.
- **Cross-reference:** No test file exists for `BaselineRulesLoader` — only integration via `RulesEngineCoordinatorTests.test_bootstrap_*`.

---

### LOW

#### L-A5-3-01 — `cleanupStagingFiles` swallows `removeItem` errors silently

- **File:** `SRSCacheStore.swift:40-42`
- **Severity:** LOW
- **Description:** `try? fm.removeItem(at: url)` on line 41 ignores all errors. If a `.bbtb-staging` file is locked (e.g., another process holds an open file descriptor — unlikely on iOS but possible during a debugger session), it stays around and pollutes future enumerations.
- **Suggested fix:** Log at `.debug` level when cleanup fails. Single-line addition.

#### L-A5-3-02 — `RulesEngineCoordinator.bootstrap()` does NOT cleanup `.bbtb-staging` from prior crashed refresh on a fresh install

- **File:** `RulesEngineCoordinator.swift:200-220`
- **Severity:** LOW
- **Description:** A bootstrap-only install (refresh never ran) won't see `.bbtb-staging` files. But if a user uninstalls during a refresh-in-flight on TestFlight build N, then installs build N+1 from a snapshot backup, stagings may persist. `SRSCacheStore.init` line 32 calls `cleanupStagingFiles()` — covers this. ✅ actually fine. (Removing from findings list — false alarm on re-read.)

(L-A5-3-02 retracted upon re-verification.)

#### L-A5-3-03 — `RulesEngineCoordinator.materializeSnapshot` does not deduplicate or sort domains/CIDRs

- **File:** `RulesEngineCoordinator.swift:550-559`
- **Severity:** LOW
- **Description:** `materializeSnapshot` passes through `manifest.blockCompletely.domains ?? []` verbatim. A malicious-or-buggy admin could submit a manifest with duplicate entries (`["max.ru", "max.ru", "max.ru"]`) which would render in the UI viewer (RULES-09) as confusing repeats. Sing-box itself handles dedup internally for routing, but the UI display is gross.
- **Suggested fix (Tier D):** `Array(Set(bodies?.domains ?? [])).sorted()` — uniqueify + alphabetize before passing to snapshot.
- **Why LOW:** Cosmetic only.

#### L-A5-3-04 — `RulesFetcher.fetch` lacks Content-Length header fast-path (already implemented in SubscriptionURLFetcher)

- **File:** `RulesFetcher.swift:147-176`
- **Severity:** LOW (performance + DoS hardening)
- **Description:** `RulesFetcher.fetch` uses `session.data(for:)` which buffers the full body before returning. The pre-flight `data.count <= maxBytes` check (line 171) happens **after** the full payload is buffered ⇒ hostile mirror serving 50MB chunked response will OOM the app before the size check fires. The sibling `SubscriptionURLFetcher` was patched in T-B2' to use `bytes(for:)` streaming + Content-Length fast-path; the same fix should apply here.
- **Impact:** A compromised mirror (or a TLS-stripped MITM somehow bypassing HTTPS — impossible in normal threat model) could OOM-kill the app on rules refresh. Realistic threat: low (HTTPS + signature verify is the gate). Defence-in-depth though.
- **Cross-reference:** `JSONEndpointFetcher` was patched with this exact fix in T-B2' (515f8dc); RulesFetcher was not. Consistent treatment recommended.
- **Suggested fix (Tier C-D):** Mirror the SubscriptionURLFetcher streaming pattern (lines 163-182 of that file).
- **Why LOW not MEDIUM:** Rules manifest is ≤5MB cap pre-flight enforced via `maxBytes` parameter; total exposure window is small. SubscriptionURLFetcher was MEDIUM/HIGH because its bodies are user-pasted URLs with attacker-controlled targets.

#### L-A5-3-05 — `PublicKey.publicKey` materializer uses `try!` — fatal-error path on rotation typo

- **File:** `PublicKey.swift:57-59`
- **Severity:** LOW
- **Description:** `try! Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))` will crash if `publicKeyBytes` is ever not exactly 32 bytes (e.g., during operational rotation, a developer adds an extra `0xNN,` line). Doc-comment lines 55-58 acknowledges this — calls it a "build bug" — but in practice the failure mode is "app launches → fatalError → device crash loop on cold start" which is bad UX for users mid-rotation.
- **Suggested fix (Tier C, pre-v1.1+ key rotation):** Replace `try!` with a build-time assertion via a static computed property guarded by `#if DEBUG`, and a runtime fallback to "rules disabled" in release builds:
  ```swift
  static let publicKey: Curve25519.Signing.PublicKey? = {
      try? Curve25519.Signing.PublicKey(rawRepresentation: Data(publicKeyBytes))
  }()
  ```
  And handle the `nil` case in `RulesSigner.verify` as `return false` (deny-by-default).
- **Why LOW:** Currently 32 bytes confirmed. Only matters for v1.1+ when key rotation happens.

#### L-A5-3-06 — `RulesSigner` has no test using real Ed25519 keypair against `PublicKey.publicKey`

- **File:** `Tests/RulesEngineTests/RulesSignerTests.swift` (not read but referenced earlier)
- **Severity:** LOW
- **Description:** Tests inject test-only keypair (good for decoupling), but no test asserts that the production `PublicKey.publicKey` constant correctly parses as a valid Ed25519 32-byte representation. If a future commit accidentally inserts a non-canonical byte sequence (e.g., a 31-byte truncation, or all-zero rejected by CryptoKit), CI would not catch it.
- **Suggested fix (Tier D):** Add `test_publicKey_constructsValidEd25519Key()` that calls `_ = PublicKey.publicKey` and asserts no fatalError (or uses the safe-init pattern in L-A5-3-05).

#### L-A5-3-07 — `RulesEngineCoordinator` does NOT log mirror identity on success — diagnostic gap

- **File:** `RulesEngineCoordinator.swift:476-479, 297-308`
- **Severity:** LOW
- **Description:** When refresh succeeds, the log line "performBackgroundRefresh: success, version=N" does not record WHICH mirror served the manifest. `FetchResult.mirrorURL` is available but discarded. In production triage ("user X says rules updated but stale" or "mirror Y is serving wrong manifest version"), knowing which mirror was used for the successful fetch is critical.
- **Suggested fix (Tier D):** Add `mirrorURL: \(manifestRes.mirrorURL.absoluteString, privacy: .public)` to the success log.

#### L-A5-3-08 — `isInFlight` guard does not differentiate from genuine concurrent refresh — UI may misreport

- **File:** `RulesEngineCoordinator.swift:269-276`
- **Severity:** LOW
- **Description:** If a user taps "force update" (RULES-10) while a BGAppRefreshTask-triggered `performBackgroundRefresh` is already in-flight, `performBackgroundRefresh` returns `false` immediately. `forceUpdate()` (line 511) then maps this through `lastFailureReason` — but `lastFailureReason` was never set in the rejected call ⇒ falls through to `.none` case ⇒ returns `.networkFailure` ⇒ user sees "network error" toast when the actual cause is "we're already refreshing."
- **Suggested fix (Tier D):** Add `case inFlight` to `RefreshFailureReason` and a new `ForceUpdateOutcome.refreshInFlight` (or fold into `.networkFailure` with explicit log). At minimum, set `lastFailureReason = .network` inside the in-flight guard so the contract is consistent.
- **Why LOW:** Real-world race window (background refresh overlapping with user tap) is small; user can just tap again 1s later. But the failure-mode obscurity is bad operationally.

---

## Thread-safety re-verification

| Concern | Verification | Status |
|---|---|---|
| `RulesEngineCoordinator` is `actor` ⇒ all mutable state isolated | Lines 110-184 — `cachedManifest`, `lastFetchedAt`, `lastForceUpdateAt`, `isInFlight`, `lastFailureReason` all actor-isolated | ✅ |
| Re-entry guard `isInFlight` prevents concurrent refresh | Lines 269-276 — early return + `defer { isInFlight = false }` | ✅ — but see L-A5-3-08 for UX gap |
| `Task { @MainActor }` notification post on line 482-487 | Hops to MainActor for `NotificationCenter.default.post`. Notification.Name is `Sendable`. Object is `RulesSnapshot` (declared `Sendable` on line 18 of RulesSnapshot.swift). | ✅ — matches the `feedback_nevpn_observer_queue_main` pattern (observers use `queue: nil` + their own MainActor hop, verified in SettingsViewModel.swift:408 and MainScreenViewModel.swift:1060) |
| `SRSCacheStore` is `actor` ⇒ serialized I/O | `public actor SRSCacheStore` line 18 | ✅ |
| `cleanupStagingFiles` is `nonisolated` — safe? | Line 37 — `private nonisolated func cleanupStagingFiles()`. Accesses `self.directory` (declared `nonisolated let` line 21). No mutation of actor state. FileManager operations are thread-safe per Apple docs. | ✅ — correct use of `nonisolated`; safe to call from init (`actor` init is non-isolated) AND from `defer` inside an isolated method (since `defer` runs in caller context which IS isolated, calling nonisolated method is always safe). |
| `validateBareFilename` is `internal static` — race-free? | Lines 146-167 — pure function over String + uses local `NSRegularExpression` (created per-call ⇒ no shared mutable state). | ✅ — could optimize by caching the regex as `private static let`, but no correctness issue. |
| `DefaultRulesFetcher` is `Sendable` struct, no state | RulesFetcher.swift:257-262 | ✅ |
| `DefaultRulesSigner` is `Sendable` struct, no state | RulesSigner.swift:21-26 | ✅ |
| `HTTPSRedirectGuard` is `@unchecked Sendable` (T-C5' closure) | Verified in SubscriptionURLFetcher.swift:445 — class has no stored mutable state | ✅ |

**No actor-isolation or Sendable bugs found.**

---

## Security re-verification — Ed25519 trust chain

The full trust chain audit (manifest fetch → manifest verify → manifest decode → per-file fetch → per-file verify → per-file sha256 → atomic commit) is **structurally sound**. Each gate is correctly ordered:

1. **HTTPS-only** (RulesFetcher line 94) — refuses `http://`, `file://`, etc.
2. **SSRF blocklist** (RulesFetcher line 108) — delegates to T-A3' patched `SubscriptionURLFetcher.isBlockedHost` (Network.framework numeric IP parser handles IPv4-mapped IPv6, IPv6 compressed forms).
3. **HTTP redirect re-validation** (RulesFetcher line 131-141) — ephemeral session with `HTTPSRedirectGuard` for `URLSession.shared` callers. Tests with mocked sessions skip this (acceptable — tests don't redirect).
4. **HTTP status check** (RulesFetcher line 162-167).
5. **Payload size cap** (RulesFetcher line 171-176) — see L-A5-3-04 for the post-buffer-not-pre-buffer concern.
6. **Manifest signature verify** (Coordinator line 311) — `DefaultRulesSigner` → `RulesSigner.verify` → `Curve25519.Signing.PublicKey.isValidSignature`. Public key is placeholder per `PublicKey.publicKeyBytes` line 44-49 (b5 3f cf c3 ... — NOT 0x00..0x1F sequential as doc-comment claims; let me re-check).

Wait — **doc-comment mismatch**:

- `PublicKey.swift:22` doc says `publicKeyBytes` is filled with sequential `0x00..0x1F`.
- `PublicKey.swift:44-49` actual bytes are `0xB5, 0x3F, 0xCF, 0xC3, 0x90, 0x4C, 0x73, 0xBE, 0xC0, 0x51, ...` — these look like real, random-distributed bytes, NOT a placeholder sequence.

This is a **previously-undocumented mismatch** — either:
(a) the doc-comment is stale and was never updated when a real keypair was generated, OR
(b) a real keypair was committed but Plan 04/05 still references the placeholder.

Per Plan 04 carry-forward `A5-001 placeholder Ed25519 keys deferred к v1.1+ (operational task)` and per memory `project_phase13_subscription_pins_prerequisite` ("real pinning + cert replacement → v1.1+"), it appears option (a) — bytes were committed but doc-comment was not updated. This is a **doc bug** not a security bug. But should be tagged:

#### L-A5-3-09 — `PublicKey.swift` doc-comment claims placeholder bytes `0x00..0x1F` but actual bytes are real-looking random values

- **File:** `PublicKey.swift:22-23, 41-49`
- **Severity:** LOW (doc accuracy)
- **Description:** Doc-comment says "**PLACEHOLDER** sequence `0x00..0x1F`" but actual array starts `0xB5, 0x3F, 0xCF, 0xC3, ...`. Mismatch indicates either: (a) real key was generated and committed but doc not updated, OR (b) bytes were tampered with intentionally and doc lies.
- **Investigation needed:** Verify with project owner whether `b5 3f cf c3 90 4c 73 be c0 51 f5 20 ba a1 06 ae b4 35 ec fa 25 89 c2 48 99 06 f7 c2 43 a3 15 99` is a real production public key (in which case private key MUST be secured on VPS) or a non-trivial placeholder for testing.
- **Cross-reference:** Plan 04 carry-forward `A5-001` claims keys are still placeholder. Either Plan 04 is wrong OR this commit silently introduced real keys without updating Plan 04. Worth a 30-second clarification with the project owner.
- **If keys ARE real:** Verify private key is NOT in the repo (it shouldn't be — `git log --all -p -S "publicKeyBytes"` should be clean). Verify VPS-side signing setup matches.
- **If keys are still placeholder:** Update doc-comment to match actual bytes, or replace bytes with the claimed `0x00..0x1F` for consistency.

7. **Manifest decode** (Coordinator line 322) — JSONDecoder on already-verified bytes. ✅
8. **srs_format_version cap** (Coordinator line 332). ✅
9. **Monotonic version** (Coordinator line 342) — replay protection. ✅
10. **Total size cap** (Coordinator line 351). ✅
11. **Path-traversal pre-validation** (Coordinator line 366-374) — uses T-B4' allowlist via `hasPathTraversalRisk` → `SRSCacheStore.validateBareFilename`. ✅
12. **Per-file signature verify** (Coordinator line 395). ✅
13. **Per-file sha256 verify** (Coordinator line 413-428) — uses T-A1' `isValidSHA256Hex`. ✅
14. **Group-atomic write** (Coordinator line 464 → SRSCacheStore.commitTransaction). ✅ best-effort, see M-A5-3-01.
15. **In-memory state update** (Coordinator line 474-475) — only after disk commit. ✅
16. **Notification post** (Coordinator line 482-487) — MainActor hop, `Sendable` payload. ✅

**Order-of-operations is correct.** No TOCTOU windows. No place where bytes are trusted before signature verify. Path traversal check happens AFTER manifest signature verify AND AFTER decode — meaning the malicious filename would have to come in a properly-signed manifest, which means either: (a) attacker has admin's private key (catastrophic — fix by rotation, out of code-level scope), OR (b) admin is hostile (out of threat model). ✅

---

## Logic re-verification

| Path | Check | Status |
|---|---|---|
| Bootstrap idempotency via `await cache.exists(filename: "baseline-rules-manifest.json")` | Line 202 — only the manifest is checked; if a prior bootstrap crashed after manifest write but before SRS writes (see M-A5-3-03), idempotency falsely thinks "done". | ⚠️ Tracked in M-A5-3-03. |
| Cached manifest recovery on cold-start (line 210-218) | Reads manifest from disk, decodes via JSONDecoder. **No signature re-verify on disk read.** This is intentional per architecture — disk-cached manifests were signature-verified at write time, integrity via Apple App Group sandbox (no other process can write to App Group container of this app). ✅ but worth highlighting. |
| `materializeSnapshot` for nil `cachedManifest` returns nil | Line 542-545 ✅ |
| `forceUpdate` records `lastForceUpdateAt = clock.now()` BEFORE `performBackgroundRefresh` | Line 509 — even failed refresh resets cooldown ⇒ DoS mitigation per D-10. ✅ |
| `forceUpdate` outcome mapping | Lines 518-531 — `.staleVersion → .alreadyLatest`, `.signature → .signatureFailure`, etc. `.decode / .formatVersion / .fileError` all fold to `.networkFailure`. M-A5-3-05 (decode misuse for path-traversal) → distorts this. |
| `isPayloadError` recursion through `.allMirrorsFailed` | Line 580-587 — `contains(where:)` on inner errors. Correct ✅. |
| `RulesFetcher.fetchWithFailover` empty-URL guard | Line 203-206 ✅ |
| `fetchWithFailover` short-circuits on success | Line 218 — correct sequential semantics ✅ |
| `fetchWithFailover` collects errors in mirror order | Line 223 — `collectedErrors.append(err)` per mirror ✅ |

**No logic bugs found beyond those flagged in MEDIUM/LOW.**

---

## Test-coverage gaps

These are not findings (no shipping bugs), but documenting for v1.1+ test-hardening:

1. `commitTransaction` partial-failure paths not covered (`SRSCacheStoreTests.swift` only tests `write/read/mtime/exists`).
2. `BaselineRulesLoader` has no dedicated test file (only integration via coordinator tests).
3. `validateBareFilename` regex edge cases not directly tested at the SRSCacheStore unit level (Unicode fullwidth solidus, leading dot, `..`, length cap, percent-encoded sequences) — only indirectly via integration.
4. `cleanupStagingFiles` correctness not asserted (no test creates a fake `.bbtb-staging` file then asserts init removes it).
5. `RulesEngineCoordinator.bootstrap()` partial-failure recovery (M-A5-3-03) untested.
6. `RulesEngineCoordinator.performBackgroundRefresh` in-flight reentry (L-A5-3-08) untested — would need two concurrent Tasks awaiting same coordinator.
7. `PublicKey.publicKey` constructs successfully (L-A5-3-06) — trivial test, absent.

---

## Cross-references with prior audits

- **Plan 04 A5'-001** (path traversal allowlist) ✅ closed via T-B4' — verified.
- **Plan 04 A5'-002** (`.bbtb-staging` cleanup) ✅ closed via T-B5'-extra — verified.
- **Plan 04 A5'-003** (`hasPathTraversalRisk` re-implementation) ✅ closed — verified line 596-603 delegates to canonical `validateBareFilename`.
- **Plan 04 A5'-004** (commitTransaction validation duplicated) ✅ — `commitTransaction` line 79-82 validates all filenames once before any disk write; single source of truth.
- **Plan 04 A5'-005 / C5'-005** (sigPath preservation) ✅ closed via T-C11' — verified.
- **Plan 04 C5'-001 CRITICAL** (sha256 empty bypass) ✅ closed via T-A1' — verified.
- **Plan 04 C5'-002** (commitTransaction Phase 2 partial commit) ✅ closed via T-B3' BUT with caveats acknowledged in M-A5-3-01.
- **Plan 04 C5'-003** (replaceItemAt requires destination exists) ✅ closed via T-C3'-extra (`fm.fileExists` + `moveItem` fallback line 102-106).
- **Plan 04 C5'-004** (sigPath not used) ✅ closed via T-C11'.

**All Plan 05 closures hold.**

---

## Recommendation

**Ship to TestFlight Internal.** The RulesEngine module is structurally sound, all Plan 05 closures verified, no CRITICAL or HIGH defects in the post-closure code.

**Tier C for v1.1+ (post-TestFlight feedback):**
- M-A5-3-01 documentation update on `commitTransaction` partial-failure semantics
- M-A5-3-03 — wrap `bootstrap()` in `commitTransaction` for consistency
- M-A5-3-04 — hoist session lifecycle in RulesFetcher for performance
- M-A5-3-05 — 1-line fix for path-traversal failure classification
- L-A5-3-04 — streaming + Content-Length fast-path for RulesFetcher (parity with SubscriptionURLFetcher post T-B2')
- L-A5-3-05 — safe-init pattern for `PublicKey.publicKey`
- L-A5-3-09 — **CLARIFY with project owner** whether `PublicKey.publicKeyBytes` is real keypair or non-trivial placeholder; update doc accordingly.

**Tier D (cleanup pass):**
- L-A5-3-01, L-A5-3-03, L-A5-3-06, L-A5-3-07, L-A5-3-08
- Test-coverage gaps 1-7 above

---

**Reviewer:** Opus 4.7 A5
**Date:** 2026-05-17
**Baseline:** `fb2ff54`
**Files audited:**
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` (625 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift` (197 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift` (262 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift` (80 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` (60 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift` (71 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift` (158 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift` (85 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/Clock.swift` (16 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift` (17 lines)
- `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/baseline-rules-manifest.json`

**Cross-checked:**
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:1060` (notification subscriber pattern)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:408` (notification subscriber pattern)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:352, 445` (`isBlockedHost` post-T-A3', `HTTPSRedirectGuard` post-T-C5')
