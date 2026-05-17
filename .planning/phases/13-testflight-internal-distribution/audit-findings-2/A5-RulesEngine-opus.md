# A5' — RulesEngine RE-AUDIT (Opus 4.7, Plan 03 / commit 55523dd)

**Scope:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/` — 10 files
**T-A1 closure commit:** `b50c2a6`, T-A3 closure commit: `0da0608`
**Total new findings:** 11 (CRITICAL 0, HIGH 2, MEDIUM 5, LOW 4)
**Plan 02 verification:** A5-002/003/005 verified closed (with caveats); C5-001 verified closed

---

## 1. Verification of T-A1 / T-A3 closures

### V-1 — A5-002 / C5-004 path traversal: **CLOSED with reservations**

`hasPathTraversalRisk()` at `RulesEngineCoordinator.swift:585-596` runs in Step 6b (line 366-374) **before** any URL construction or filesystem write. `SRSCacheStore.validateBareFilename(_:)` at line 125-143 runs at filesystem boundary inside `write()` and `commitTransaction()`. Two-layer defence is correct architecture. Patterns blocked: `/`, `\`, `..`, `%2f/%2F`, `%5c/%5C`, `%2e%2e/%2E%2E`, hidden prefix `.`, null `\0`. **Reservations** noted as A5'-001..A5'-003 below — the implementation has substantive Unicode/normalization holes.

### V-2 — A5-003 / C5-002 SHA-256 verification: **CLOSED**

`sha256Hex()` at line 602-605 uses `Crypto.SHA256.hash` with `String(format: "%02x", $0)` → lowercase hex, 64 chars (matches Curve25519 output 32 bytes × 2 hex chars). Comparison at line 407 normalizes both sides with `.lowercased()` (case-insensitive). Empty `entry.sha256` is skipped (line 405) — see A5'-005 below for risk. Logic correctly fails with `lastFailureReason = .signature` on mismatch.

### V-3 — A5-005 / C5-005 group-atomic write: **CLOSED with regressions**

`commitTransaction()` at `SRSCacheStore.swift:85-108` implements two-phase commit:
- Phase 1: `validateBareFilename` all entries (rejects entire batch if any unsafe).
- Phase 2: write all to `<filename>.bbtb-staging` via `Data.write(.atomic)`.
- Phase 3: `FileManager.replaceItemAt(final, withItemAt: stagingURL)` per file.

This is **better than previous** per-file atomic loop and correctly handles partial failures during Phase 2 (final files untouched). However, three concerns are flagged below as A5'-004, A5'-006, A5'-007 — the implementation has new failure modes its predecessor lacked.

### V-4 — C5-001 SSRF guard pre-DNS only (T-A3): **CLOSED**

`RulesFetcher.fetch` lines 129-144 builds an ephemeral guarded session with `HTTPSRedirectGuard()` when caller passed `URLSession.shared` (production path). The guard re-checks HTTPS + `isBlockedHost` on every redirect. Test-injected sessions bypass cleanly. Implementation matches `SubscriptionURLFetcher` / `JSONEndpointFetcher` pattern. ✓ Verified.

---

## 2. New findings

### [HIGH] A5'-001: `hasPathTraversalRisk` misses Unicode "fullwidth solidus", normalization forms NFKC/NFKD, and HFS-Plus decomposed paths — bypass possible on macOS Catalyst hosts and some iOS file APIs

- **Location:** `RulesEngineCoordinator.swift:585-596`, `SRSCacheStore.swift:125-143`
- **Dimension:** security
- **Description:** Both validators do plain substring search after `.lowercased()`. Several Unicode characters render as `/` or `..` after later filesystem-API normalization but bypass the substring check:
  - **U+FF0F FULLWIDTH SOLIDUS (`／`)** — visually identical to `/`. `appendingPathComponent("／foo")` returns a string that contains `／`; **FileManager** treats it as a single character (no path split) but **POSIX paths can be reached through different APIs**, and the visible filename is misleading for any UI showing rule entries.
  - **U+2044 FRACTION SLASH (`⁄`)**, **U+2215 DIVISION SLASH (`∕`)** — similar visual confusion.
  - **NFD-decomposed `..`** — actual `..` is ASCII, safe, but if attacker uses `\u{2024}\u{2024}` (ONE DOT LEADER × 2, looks like `..`) — substring `..` is not present in the raw codepoints. macOS HFS+ NFD normalization converts NFC strings on write, but `..` is single-byte ASCII not affected.
  - **Trailing whitespace** is stripped only for empty-check (line 587-588 `trimmed.isEmpty`), not for the substring search — `" ../foo"` (leading space) still hits `..` due to substring containment, but the empty check is wrongly applied to `trimmed`, not the actual string used for forbidden-list check.
  - **Empty after trim ≠ empty filename** — `"   "` is rejected (good), but `"foo.bbtb-staging "` (trailing space) writes to a file with literal trailing space, breaking the staging-rename pair (line 93 builds `"\(entry.filename).bbtb-staging"` but rename target on line 100 builds `directory.appendingPathComponent(entry.filename)` — both are bytes-exact, so rename works, but filesystem on iOS strips trailing spaces in some APFS scenarios → mismatch).
- **Why it matters:** The risk in A5-002 was "filename = `../../foo` breaks out of `Library/Caches/rules`." The signature-gated trust path means only a compromised signer or buggy admin tooling can supply such names — **but** that's exactly what the T-A1 layer claims to defend against. A fullwidth solidus would still pass `appendingPathComponent` cleanly (no separator parsing on iOS APFS for that codepoint) and write a file named `／foo` inside `rules/` — not a traversal escape, but a filename UI cannot match against the manifest's `entry.name` if any layer normalizes (RULES-09 viewer). Defense-in-depth posture should be **allowlist regex `^[A-Za-z0-9._-]+$`** as Plan 02 suggested at the bottom of A5-002 fix — the implementation chose blocklist, which is fundamentally weaker.
- **Suggested fix:** Replace substring blocklist with an allowlist regex anchored at start/end:
  ```swift
  private static let allowedFilenameRegex = try! NSRegularExpression(
      pattern: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$"
  )
  ```
  Reject anything else. This eliminates the entire Unicode/normalization class of bypasses. The known-valid filenames (`bbtb-baseline-block.srs`, etc.) all match this pattern.

---

### [HIGH] A5'-002: `commitTransaction` does NOT cleanup `.bbtb-staging` files on Phase 2 failure — leaks stale staging across launches; second-run reads can stat them but no recovery code purges

- **Location:** `SRSCacheStore.swift:85-108` (no cleanup branch)
- **Dimension:** atomicity / disk leak
- **Description:** If `entry.data.write(to: staging, options: .atomic)` on line 94 throws halfway through the batch (e.g., disk full after staging file #3 of 8), the `throws` propagates out of `commitTransaction`. Lines 95-104 never run. Three staging files remain on disk as `<name>.bbtb-staging`. On the next refresh:
  - `cache.exists("baseline-rules-manifest.json")` returns true (final file untouched).
  - `commitTransaction` is called again; Phase 2 calls `Data.write(.atomic)` to staging URLs — `.atomic` write overwrites cleanly, so this works, but if the second refresh has a **different filename set** (manifest changed), old staging files from previous batch are orphaned forever.
  - `.bbtb-staging` files are inside `rules/` directory. If sing-box's `route.rule_set.path` ever uses a glob (`*.srs`), it would attempt to parse the staging files — current path is exact-match so safe, but a refactor could trip.
- **Why it matters:** Storage leak on degraded devices. Also confuses any future RULES-09 UI that enumerates `rules/` contents. Phase 1-2's "atomic write" promise is now technically "atomic with potential orphans on failure," which the docstring at lines 76-80 acknowledges ("staging files могут остаться, но final files не тронуты") but does not actively reap.
- **Suggested fix:** Add `defer` cleanup at the start of `commitTransaction`:
  ```swift
  public func commitTransaction(_ files: [...]) throws {
      var stagingURLs: [URL] = []
      defer {
          // Best-effort cleanup of any staging files that didn't get renamed.
          let fm = FileManager.default
          for url in stagingURLs where fm.fileExists(atPath: url.path) {
              try? fm.removeItem(at: url)
          }
      }
      // ... existing logic, append to stagingURLs as you go ...
  }
  ```
  Plus on `SRSCacheStore.init`, sweep any pre-existing `*.bbtb-staging` files from prior interrupted runs.

---

### [MEDIUM] A5'-003: `hasPathTraversalRisk` rejects ALL filenames starting with `.` — but baseline manifest filenames are `bbtb-baseline-block.srs` (dot is intra-string, not prefix), so this is OK today, however the check is **string-prefix** not **path-component-leading-char** — works on simple filenames only

- **Location:** `RulesEngineCoordinator.swift:594` (`if filename.hasPrefix(".") || filename.contains("\0")`)
- **Dimension:** security / logic
- **Description:** The check rejects `.gitignore`-style hidden files at filename level, which is reasonable defence-in-depth. However, an admin manifest entry like `entry.name = "bbtb-..-block.srs"` would NOT trip `hasPathTraversalRisk` (no leading dot, no `/`, no `..` *as substring* would match — wait, this DOES match because `bbtb-..-block.srs` contains substring `..`). Good. But what about an entry like `"bbtb-.x-block.srs"`? Contains `.` and `-`, contains no `..` substring. Safe. What about `"bbtb.x.block.srs"`? Multiple dots, no `..` substring. Safe. So the check is robust against the practical patterns.

  **But** the check is asymmetric between coordinator and cache:
  - Coordinator `hasPathTraversalRisk` returns Bool (just yes/no).
  - Cache `validateBareFilename` throws `WriteError.unsafeFilename(filename)`.
  - If coordinator's check ever drifts from cache's (different blocklists), defence-in-depth becomes single-layer at one end. Currently they have identical blocklists (verified line-by-line) — but there's no shared constant or single source of truth. A code reviewer adding `"|"` to one but not the other would silently regress.
- **Why it matters:** Maintenance fragility. Plan 02 reviewers will likely add the more comprehensive allowlist in v1.1; until then, the two definitions must be kept in lockstep manually.
- **Suggested fix:** Extract `isBareFilename(_:)` as a public static helper in `SRSCacheStore` (or a shared `PathSafety` enum), and have the coordinator call into it instead of duplicating. Single point of truth.

---

### [MEDIUM] A5'-004: `FileManager.replaceItemAt` semantics on iOS — backup file leak and same-volume requirement not asserted

- **Location:** `SRSCacheStore.swift:99-104`
- **Dimension:** atomicity / bugs
- **Description:** `replaceItemAt(_, withItemAt:, backupItemName:, options:)` is the convenience that uses `NSFileManager.replaceItem` under the hood. Three points:
  1. **`backupItemName: nil`** (implicit) — on success, no backup created; on failure, may temporarily create `~final` files. iOS APFS implementation usually skips backup, but Catalyst on macOS HFS+ can leave `~filename` files.
  2. **Same-volume requirement** — `replaceItemAt` requires source and destination on the same volume for atomic rename. The implementation assumes this because `directory` is the App Group container and `staging` is `directory.appendingPathComponent(...)` — same dir, same volume. ✓ OK.
  3. **Partial rename on mid-batch failure** — if rename of file #4 fails (e.g., destination locked by another process — unlikely on iOS but possible if main app + extension both open), files #1-3 are already renamed (new content live), files #4-8 still in `.bbtb-staging` (old final content still live on disk). The "best-effort group atomicity" doc admits this. The 8-file batch is not transactional.
  4. **`_ = try fm.replaceItemAt(...)`** discards the return value `URL?`. On some `NSFileManager` versions, this can return non-nil URL pointing to the **new location** when the rename succeeded but at a slightly different path (e.g., case-folding on case-insensitive volumes). Discarding the URL means the coordinator's in-memory state may not reflect on-disk reality. Low risk since iOS APFS is case-sensitive for App Group containers, but defensive to capture.
- **Why it matters:** Phase 8 W2 assumed `Data.write(.atomic)` = "one file, atomic." T-A1's `commitTransaction` raises this to "many files, best-effort atomic" which is materially weaker on partial-failure paths. The race between `cache.commitTransaction` (writer) and `sing-box libbox` (reader watching mtime) is **not made worse** by this, but it is **not made better either** — libbox reading `bbtb-baseline-block.srs` while files 4-8 are still in `.bbtb-staging` will see the OLD content of file 1 (already renamed to new content) and OLD content of file 4 (rename pending). That's the same exposure as Phase 1's per-file atomic writes — A5'-005 didn't make it worse, just didn't fully fix it.
- **Suggested fix:** Document the partial-rename failure mode explicitly in `commitTransaction` doc. For a true atomic group swap (carry-forward), use the versioned-dir pattern: write all 8 to `rules-v<N>/` and atomic-rename the directory. Same-volume safe via `replaceItemAt` on the directory inode.

---

### [MEDIUM] A5'-005: Empty `entry.sha256` is silently accepted — defeats T-A1 hash verification

- **Location:** `RulesEngineCoordinator.swift:404-414`
- **Dimension:** security / logic
- **Description:** Line 405 reads `if !expectedHex.isEmpty { ... }`. If a manifest has `entry.sha256 = ""` (empty string), the SHA-256 check is **skipped entirely**. A malicious or buggy admin signing flow that omits the hash field (or sets it empty) downgrades back to signature-only trust, which is the pre-T-A1 state. The signed manifest could itself be valid but lack the hash — defeating the layered protection that T-A1 was designed to provide.
- **Why it matters:** Signature alone does not prevent the cross-cache replay attack described in Plan 02 A5-003 ("attacker swaps `.srs` files between manifests"). If the admin pipeline ever ships a manifest with empty sha256 (e.g., during a tooling migration), client silently accepts it. This is a "feature" presented as backward-compat but is actually a security gap.
- **Suggested fix:** Reject empty `entry.sha256` as malformed manifest:
  ```swift
  guard !expectedHex.isEmpty else {
      lastFailureReason = .decode
      RulesEngineLogger.coordinator.error(
          "RulesEngineCoordinator: manifest missing sha256 for \(entry.name, privacy: .public)"
      )
      return false
  }
  ```
  Or: validate at decode time inside `RulesManifest.FileEntry.init(from:)` decoder.

---

### [MEDIUM] A5'-006: Race between concurrent `commitTransaction` calls — actor protects single call but not against bootstrap+refresh interleaving on same filename

- **Location:** `SRSCacheStore.swift:85-108`, `RulesEngineCoordinator.swift:200-252` (`bootstrap`) and `268-473` (`performBackgroundRefresh`)
- **Dimension:** thread-safety
- **Description:** `SRSCacheStore` is an actor → serialization is guaranteed for calls **to the same instance**. The coordinator's `bootstrap()` writes via `cache.write(...)` (per-file atomic), the coordinator's `performBackgroundRefresh()` writes via `cache.commitTransaction(...)` (group). Both run on the same `cache` instance, so they serialize.

  **But:** the `isInFlight` guard in coordinator only prevents concurrent `performBackgroundRefresh` — it does **not** guard against `bootstrap()` running concurrently with `performBackgroundRefresh()`. If both are dispatched from `BBTB_iOSApp` on different `Task.detached` (cold-start may do `bootstrap` then immediately enqueue a `BGAppRefreshTask` handler that calls `performBackgroundRefresh`), they execute serially on the coordinator actor, **but bootstrap can see post-refresh state**.

  Scenario: bootstrap starts, calls `cache.exists("baseline-rules-manifest.json")` → false (first launch). Awaits return through actor hop. Meanwhile (because actor reentrancy at `await` points), a BG-task fires `performBackgroundRefresh`, which writes a server manifest (version 5) to `baseline-rules-manifest.json`. Bootstrap resumes, proceeds to "hydrate baseline" path, **overwrites the server manifest with baseline version 0**.

  This is the exact regression Plan 02 A5-011 warned about ("file naming creates a confusing trail in logs"). T-A1 did not fix it because A5-011 was MEDIUM, not in T-A1 scope.
- **Why it matters:** Cold-start of an app that already has a server manifest could roll back to baseline if `bootstrap` is called eagerly. In Phase 13 TestFlight, BGAppRefreshTask may have already fired in background (iOS keeps registered tasks alive across foreground transitions), so on subsequent foreground entry `bootstrap` could undo it.
- **Suggested fix:** Either (a) gate `bootstrap` on a coordinator-private `didBootstrap: Bool` flag, set by `bootstrap()` on first run regardless of cache state; (b) check `cachedManifest != nil` before overwriting (only write baseline if neither in-memory nor on-disk has anything); (c) decouple baseline filename from server filename per A5-011's suggestion. Lowest-risk fix: add the in-memory `didBootstrap` flag.

---

### [MEDIUM] A5'-007: Notification `NotificationCenter.default.post` from `Task { @MainActor in ... }` — observer waiting on dispatch_queue.main can be dropped if scheduler is blocked

- **Location:** `RulesEngineCoordinator.swift:464-470`
- **Dimension:** thread-safety / minor perf
- **Description:** Documented in Plan 02 A5-010 as accepted. Still flagged because the MainActor hop adds asymmetric latency between "successful refresh" (returns true immediately) and "UI sees notification" (waits for MainActor to drain). Memory note `feedback_nevpn_observer_queue_main` recommends `queue: nil` at observer side + `Task { @MainActor }` inside observer callback — posting from MainActor inverts this pattern. Phase 6c had the same bug and required fix `44a5630`.
- **Why it matters:** If the post is sent during a heavy SwiftUI redraw or during `BGAppRefreshTask` execution (where MainActor may be deprioritized), the notification observer may not fire for seconds. UI toast "rules updated" lags.
- **Suggested fix:** Drop the MainActor hop. `NotificationCenter.default.post(name:object:)` is nonisolated and thread-safe. Document that observers must do the MainActor hop themselves (matches Phase 6c pattern).

---

### [LOW] A5'-008: `lastFailureReason = .decode` for path-traversal violation — wrong semantic bucket; UI cannot surface "manifest contains unsafe filenames"

- **Location:** `RulesEngineCoordinator.swift:368` (`lastFailureReason = .decode  // closest existing`)
- **Dimension:** logic
- **Description:** Comment acknowledges this is a hack (`closest existing — manifest field validation`). The `RefreshFailureReason` enum has no `unsafePath` case. When `forceUpdate` maps `lastFailureReason` to `ForceUpdateOutcome`, `.decode` falls into the `.networkFailure` bucket (line 510-513). User sees "network failure" toast for what was actually "manifest contains a `../` filename."
- **Why it matters:** UAT and debug logs will misclassify the event. A future admin debugging "why is the v0.9 manifest not applying" has to read Console.app for the exact error message instead of seeing it in app diagnostics.
- **Suggested fix:** Add `case unsafeFilename` to `RefreshFailureReason` and map it to `.signatureFailure` in `ForceUpdateOutcome` (since "we got the file but the manifest contents are invalid" is closer to "tampered" than "network failure").

---

### [LOW] A5'-009: `productionMirrors` URLs still use `.example` TLD — same risk as A5-014 in Plan 02; not in T-A1 scope but worth re-flagging

- **Location:** `RulesEngineCoordinator.swift:117-121`
- **Dimension:** configuration
- **Description:** Unchanged since Plan 02. `rules.bbtb.example` is RFC-2606 reserved; DNS fails immediately. Combined with placeholder pubkey (A5-001), this means **the entire pipeline is dead-code in v1.0 TestFlight**. The acknowledged risk is documented in memory (`project_phase13_subscription_pins_prerequisite` analogy). For A5' purposes, just confirming this is intentional and the carry-forward to v1.1+ is recorded.
- **Why it matters:** No security impact (fetch never succeeds). Behavioral impact: every refresh attempt costs DNS resolution + retries on 3 mirrors. Battery cost on a 24-hour BGAppRefreshTask cycle is negligible but real.
- **Suggested fix:** Gate `performBackgroundRefresh` on a build-config flag (`#if RULES_NETWORK_ENABLED`) so v1.0 TestFlight builds skip the network entirely. Re-enable when real URLs published.

---

### [LOW] A5'-010: `fetchWithFailover` `httpStatusError(0)` opaque wrap loses URLError code — Plan 02 A5-013 unchanged

- **Location:** `RulesFetcher.swift:225-232`
- **Dimension:** bugs / debug
- **Description:** Unchanged since Plan 02 A5-013. Non-`FetchError` exceptions (mostly URLErrors from DNS/timeout/connection-refused that aren't caught as `URLError.timedOut`) get mapped to `.httpStatusError(0)`. The aggregated `allMirrorsFailed([.httpStatusError(0), .httpStatusError(0), ...])` strips all root-cause info before reaching the coordinator. Phase 8 W7 debugging will be painful.
- **Why it matters:** Debug-only; no security impact.
- **Suggested fix:** Add `case networkError(URLError.Code)` to `FetchError` and propagate.

---

### [LOW] A5'-011: `commitTransaction` writes to `.bbtb-staging` which is NOT validated as a bare filename — if a legitimate `entry.name` happens to end in `.bbtb-staging` (impossible by allowlist but possible by current blocklist), staging file = final file = corruption

- **Location:** `SRSCacheStore.swift:93`
- **Dimension:** security / logic
- **Description:** Edge case from the blocklist-not-allowlist design (see A5'-001). If a manifest declared `entry.name = "bbtb-block.srs.bbtb-staging"` (passes `hasPathTraversalRisk` — no forbidden tokens), then:
  - Staging URL = `directory + "bbtb-block.srs.bbtb-staging.bbtb-staging"` — distinct from final URL.
  - Final URL = `directory + "bbtb-block.srs.bbtb-staging"`.
  - Rename succeeds: new content at `bbtb-block.srs.bbtb-staging` (final).
  - But if a PREVIOUS refresh had partial state (orphaned staging from A5'-002), the file `bbtb-block.srs.bbtb-staging` may already exist as leftover from a different file. `replaceItemAt` replaces it. Subtle but not corrupting.
- **Why it matters:** Theoretical only — admin won't name files with `.bbtb-staging` suffix. But if A5'-001's allowlist regex is adopted, this whole class disappears.
- **Suggested fix:** Add explicit guard in `validateBareFilename`: `if filename.hasSuffix(".bbtb-staging") { throw ... }`. Or move to allowlist.

---

## 3. Tests & coverage gaps

**Critical observation:** `SRSCacheStoreTests.swift` (Tests 1-6) covers `write/read/mtime/exists` but **has NO tests** for:
- `commitTransaction(_:)` — the new two-phase commit logic.
- `validateBareFilename` — the new path-traversal guard.
- `WriteError.unsafeFilename` — the new throwing path.
- Staging file cleanup on Phase 2 failure (A5'-002).

`RulesEngineCoordinatorTests.swift` tests reference `sha256` correctly in the TestManifest fixture (line 527 — `sha256Hex(entry.srsBytes)`), but there is **no negative test** for SHA mismatch (T-A1's claim that mismatch is detected). Similarly, no test exercises `hasPathTraversalRisk` rejection through `performBackgroundRefresh` (no fake manifest with `entry.name = "../foo"`).

T-A1 commit message claims "41/41 PASS" — that's pre-existing coverage, plus the fixture update. **The actual new T-A1 code paths are largely untested.** This is the highest-priority gap for Tier C / v1.1.

---

## 4. Closure status of Plan 02 findings

| Plan 02 ID | Status | Notes |
|---|---|---|
| A5-001 placeholder pubkey | Carry-forward (real risk zero) | Server URLs `.example` ensure fetch fails. Documented in memory. |
| A5-002 path traversal | **CLOSED with reservations** | T-A1 implemented; see A5'-001/003 for Unicode/allowlist holes. |
| A5-003 SHA-256 not verified | **CLOSED with reservation** | See A5'-005 (empty sha256 skipped). |
| A5-004 minAppVersion not enforced | Carry-forward Tier C | Not in T-A1 scope. |
| A5-005 non-atomic group write | **CLOSED (best-effort)** | See A5'-002, A5'-004 for residual gaps. |
| A5-006 SSRF DNS rebinding | Accepted risk | Documented; pinning deferred v1.1+. |
| A5-007 forceUpdate wallclock cooldown | Carry-forward | Plan 02 MEDIUM; not in T-A1. |
| A5-008 Bundle.module silent failure | Carry-forward | Plan 02 MEDIUM. |
| A5-009 reentrancy gap | Carry-forward Tier C | Subsumed partially by A5'-006. |
| A5-010 notification MainActor hop | Re-flagged as A5'-007 | Inverted pattern from `feedback_nevpn_observer_queue_main`. |
| A5-011 bootstrap idempotency | Re-flagged as A5'-006 | Active regression risk; T-A1 unchanged. |
| A5-012 partial state on write fail | Subsumed by A5'-002 | Better — staging suffix is partly self-healing. |
| A5-013 fetch error wrap | Re-flagged as A5'-010 | Unchanged. |
| A5-014 placeholder URLs | Re-flagged as A5'-009 | Unchanged. |
| C5-001 redirect re-validation | **CLOSED (T-A3)** | Verified ephemeral session + delegate. |
| C5-002 SHA-256 | **CLOSED** | Same as A5-003. |
| C5-003 replay protection | Partial — monotonic version only | Wallclock-signed field deferred. |
| C5-004 path traversal | **CLOSED** | Same as A5-002. |
| C5-005 group atomic | **CLOSED (best-effort)** | Same as A5-005. |
| C5-006 baseline never verified | Carry-forward | Apple code signing covers. |

---

## 5. Summary for parent agent

**Pre-TestFlight verdict for `BBTB/Packages/RulesEngine/`:**

- ✅ T-A1 / T-A3 closures work: path traversal blocked at two layers, SHA-256 verified per file, group-atomic write via staging, redirect re-validation via ephemeral guarded session.
- ⚠️ **2 HIGH new findings** (A5'-001 Unicode allowlist gap, A5'-002 staging file leak on failure) — neither blocks Internal TestFlight (signature gate + placeholder URLs make the pipeline operationally dead-code in v1.0), but both should be fixed before External Testing or any real server URLs ship.
- ⚠️ **5 MEDIUM** findings — most are carry-forward from Plan 02; A5'-005 (empty sha256 skipped) and A5'-006 (bootstrap+refresh race) are new and worth Tier C consideration.
- 🟢 **No new CRITICAL.** No regression from T-A1.
- 🚨 **Test coverage gap is the biggest residual risk**: `commitTransaction`, `validateBareFilename`, `hasPathTraversalRisk`, and SHA mismatch paths have no negative test coverage. Add ~6 unit tests before v1.1 ships with real server URLs.

**Recommendation:** Ship v1.0 Internal TestFlight as-is. Open follow-up issue for A5'-001 + A5'-002 + tests, scope to v1.0.1 or v1.1.
