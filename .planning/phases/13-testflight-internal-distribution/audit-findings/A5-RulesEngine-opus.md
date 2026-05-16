# A5 — RulesEngine audit (Opus 4.7)

**Scope:** BBTB/Packages/RulesEngine/Sources/
**Files audited:** 10 (BaselineRulesLoader, Clock, PublicKey, RulesEngineCoordinator, RulesEngineLogger, RulesFetcher, RulesManifest, RulesSigner, RulesSnapshot, SRSCacheStore)
**Total findings:** 14 (CRITICAL: 2, HIGH: 4, MEDIUM: 5, LOW: 3)

## Findings

### [CRITICAL] A5-001: Placeholder Ed25519 public key shipped — all signature verifies fail OR (worse) sig forgery is trivial if anyone discovers the pattern

- **Location:** `RulesEngine/Sources/RulesEngine/PublicKey.swift:44-49`
- **Dimension:** security
- **Description:** The constant `publicKeyBytes` is documented as a "PHASE 8 W1 placeholder" (lines 22-23, 33, 41-43, 56). The 32 bytes currently in the file (`0xB5, 0x3F, ... 0x99`) appear non-sequential but the docblock (line 41) still states "PLACEHOLDER sequence 0x00..0x1F. Replace before shipping production builds" — meaning either the bytes were updated without updating the doc, or these bytes are still placeholder values whose corresponding private key may be checked into git history, posted in chat logs, or otherwise non-secret. There is no `validate-r1-r6.sh` R12 guard mentioned at line 24 — search shows no enforcement. The doc comment also states "NOT for production until replacement on real bytes" and explicitly names this as a TestFlight blocker.
- **Why it matters:** If the matching private key is exposed (placeholder origin), any attacker can sign rogue rules that:
  - Add malicious domains to `block_completely` (DoS legitimate sites)
  - Add attacker-controlled CIDRs to `always_through_vpn` (force traffic through their network if combined with rogue server)
  - Add user's legitimate banking domains to `never_through_vpn` (exfil-friendly bypass of VPN)
  Conversely, if no one has the right private key, every server fetch will hit `signatureFailure` and the app silently falls back to baseline forever, meaning rules **never** update — the entire Phase 8 pipeline is dead code in TestFlight.
- **Suggested fix:** **BLOCKER for TestFlight:** (1) Generate real Ed25519 keypair on hardened admin machine (per the `openssl` recipe in lines 27-29), (2) replace `publicKeyBytes` with real public bytes, (3) verify private key is NOT in git history (`git log --all -S "<first 8 bytes hex>"`), (4) add the deferred R12 guard in `validate-r1-r6.sh` (rejects sequential / monotonic byte patterns), (5) document private key storage location (1Password vault / HSM). If shipping placeholder for v1.0 is intentional and rules updates are deferred, **document explicitly** in `wiki/rules-engine.md` and SECURITY.md that signed-rules pipeline is disabled and only baseline applies.

---

### [CRITICAL] A5-002: `entry.name` / `entry.sigPath` from server-controlled manifest written to filesystem without path-traversal validation

- **Location:**
  - `RulesEngineCoordinator.swift:362-369` (URL construction)
  - `RulesEngineCoordinator.swift:401-402` (write call)
  - `SRSCacheStore.swift:57-59` (`write` body — no validation)
- **Dimension:** security
- **Description:** `RulesManifest.FileEntry.name` and `FileEntry.sigPath` are decoded directly from server JSON and used as:
  1. `manifestURL.deletingLastPathComponent().appendingPathComponent(entry.name)` — for the **fetch URL**
  2. `cache.write(payload.srs, filename: payload.basename)` where `payload.basename = entry.name`, which inside `SRSCacheStore.write` does `directory.appendingPathComponent(filename)` and then `Data.write(to: target, options: .atomic)`
  No code in the package validates that `entry.name` is a bare filename. A malicious (or compromised) server can ship a manifest with `entry.name = "../../../../tmp/poisoned.dylib"` or `"../../bbtb-tunnel.config.json"`. `URL.appendingPathComponent` does NOT normalize `..` — it just concatenates. After `.atomic` write the file lands wherever the resolved path points. Within the App Group container this could overwrite `sing-box.log`, `subscription-pins-cached.json`, `cdn-failure-cache.json`, or — depending on App Group container layout — other tunnel state.
  Note: this is **gated by Ed25519 signature** (server controls the signature), so an honest server cannot be MITM-exploited to do this. But if A5-001's private key is compromised, or if a future admin makes a mistake when authoring a manifest, **any** path is written without sandboxing.
- **Why it matters:** Defense-in-depth: signature verification is "trust the signer," but path traversal turns a compromised signer into "overwrite arbitrary App Group state" rather than just "ship bad rules." In a TestFlight context where the signing key may not be hardened, this turns key compromise from "users get bad routing rules" into "users get tunnel state corruption / extension crash loop / potential code execution if attacker can stage a libbox config replacement."
- **Suggested fix:** Add validation in `RulesEngineCoordinator.performBackgroundRefresh` Step 7 (before fetching each file) and in `SRSCacheStore.write`:
  ```swift
  private static let allowedFilenameRegex = try! NSRegularExpression(
      pattern: "^[A-Za-z0-9._-]+$"  // no slashes, no .., no null bytes
  )
  guard isValidBareFilename(entry.name), isValidBareFilename(entry.sigPath) else {
      throw RefreshFailureReason.malformedManifest
  }
  // Also reject leading "." files (.git, .DS_Store style) and reserve known names
  ```
  Or simpler: enforce a fixed allowlist `["bbtb-block.srs", "bbtb-never.srs", "bbtb-always.srs"]` + `entry.category` mapping, since the manifest's `category` enum already constrains the universe.

---

### [HIGH] A5-003: `entry.sha256` field decoded but never verified — pre-signature integrity tier missing

- **Location:**
  - `RulesManifest.swift:107-109` (field declared with documentation "W2.3 coordinator verifies hash after fetch + before signature verify")
  - `RulesEngineCoordinator.swift:371-381` (only `signer.verify(message: srsRes.body, signature: sigRes.body)` is called — no SHA-256 check)
- **Dimension:** security / logic
- **Description:** The manifest schema includes a per-file `sha256: String` field, and the `RulesManifest.swift` doc-comment says "W2.3 coordinator verifies hash after fetch + before signature verify (cheap pre-filter)." Yet `RulesEngineCoordinator.performBackgroundRefresh` never computes a SHA-256 of `srsRes.body` or compares it against `entry.sha256`. The hash field is dead weight in the schema.
- **Why it matters:** The Ed25519 signature alone is technically sufficient (it covers `srsRes.body` end-to-end), so the absence of SHA verification is not a direct vulnerability. However:
  1. **The doc lies** — readers / future maintainers will assume hash verification happens. Any maintenance that depends on hash-as-cheap-prefilter (e.g. "skip download if hash matches cached") will be broken.
  2. **Schema mismatch consequence:** If admin tooling generates an `entry.sha256` that does **not** match the actual `.srs` payload (e.g. tooling bug where hash is computed pre-compression but `.srs` is post-compression), the client will not detect it and quiet bytes-vs-hash drift will go unnoticed.
  3. **Cross-cache rebind risk:** If an attacker swaps `.srs` files between manifests (replacing `bbtb-block.srs` with the OLD signed body of `bbtb-never.srs` — both legitimately signed by the admin), the per-file signature still verifies. The `manifest.files[].sha256` would prevent this rebind attack, but only if checked. Without it, signed-but-stale individual SRS files can be replayed across categories.
- **Suggested fix:** Add after line 373 (between fetch and signature verify):
  ```swift
  let computedHex = SHA256.hash(data: srsRes.body)
      .map { String(format: "%02x", $0) }.joined()
  guard computedHex.lowercased() == entry.sha256.lowercased() else {
      lastFailureReason = .signature  // or new .sha256Mismatch
      RulesEngineLogger.coordinator.error("SHA mismatch for \(entry.name): expected=\(entry.sha256) got=\(computedHex)")
      return false
  }
  ```

---

### [HIGH] A5-004: `minAppVersion` decoded but never enforced — old clients accept newer manifests intended for future schema

- **Location:**
  - `RulesEngineCoordinator.swift:329-356` (Step 4-6 sanity gates — no `minAppVersion` check)
  - `RulesManifest.swift:33-35` (field doc says "compared via String.compare(_:options: .numeric) (RULES-08)")
- **Dimension:** logic / security
- **Description:** Manifest carries `minAppVersion: String` (e.g. `"0.8.0"`) but `performBackgroundRefresh` only checks `srsFormatVersion <= 4`, `version > cachedVersion`, and `totalSizeBytes <= 5 MB`. There is no compare against the current app's `CFBundleShortVersionString`. The field flows through to `RulesSnapshot.minAppVersion` (line 498) where Phase 8 W4 BG-task was supposed to gate apply (per doc on `RulesSnapshot.swift:39-41`) — but I find no such gate in this package.
- **Why it matters:** Phase 8 W4 was scoped to enforce this via BG-task; if W4 wasn't completed before TestFlight, the v1.0 client may apply a v1.5-flavoured manifest that, for example, includes new category fields the v1.0 sing-box config builder doesn't understand. Worst case: malformed `route.rules` causes extension to fail on `start` → users stuck in `disconnected` state. Less bad case: silent acceptance of partial config.
- **Suggested fix:** Add Step 4.5 after line 337:
  ```swift
  let currentAppVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
  if newManifest.minAppVersion.compare(currentAppVersion, options: .numeric) == .orderedDescending {
      RulesEngineLogger.coordinator.error("manifest minAppVersion=\(newManifest.minAppVersion) > current=\(currentAppVersion); refusing apply")
      lastFailureReason = .formatVersion  // map to existing bucket or add new
      return false
  }
  ```
  For TestFlight, even if W4's UI gate is absent, this minimal coordinator-side gate prevents extension crash.

---

### [HIGH] A5-005: Atomic write sequence is NOT transactional — interrupted refresh leaves cache in mixed-version state

- **Location:** `RulesEngineCoordinator.swift:394-412` (Step 8)
- **Dimension:** security / logic / atomicity
- **Description:** The "atomic write" comment (lines 395-398) acknowledges the gap: "Order: srs payloads first (each + its sig), THEN manifest + sig last." Each `cache.write` is individually atomic at the POSIX-rename level, but the **set of 8 writes is not.** Failure modes:
  - **Crash between write #3 (bbtb-block.srs) and write #4 (bbtb-block.srs.sig):** new SRS but stale signature on disk. Extension's libbox watches mtime — on the next route reload it reads the new SRS with the old sig (mismatch); behavior depends on libbox tolerance.
  - **Crash between SRS writes and manifest update:** manifest still points to OLD hashes (matches what `entry.sha256` would say if A5-003 were implemented), but the actual SRS files on disk have NEW content. The next coordinator launch reads the manifest, thinks cache is at version N, but the SRS bytes are version N+1.
  - **The trust-path comment relies on libbox-side mismatch detection** ("libbox-side mismatch defense"), but I cannot find any such cross-check in libbox configuration — sing-box loads SRS files via path, it does not re-verify signatures.
- **Why it matters:** Defence-in-depth holes during BG-refresh interrupted by OS task suspension are inevitable on iOS. Without a transactional commit (write-then-rename of a directory pointer, or staging dir → swap), poisoned partial states survive across launches.
- **Suggested fix:** Use a staging directory pattern:
  1. Write all 8 files into `rules-staging-<uuid>/` (atomic per file)
  2. After all 8 writes succeed, do **one** `FileManager.replaceItemAt(rulesDirURL, withItemAt: stagingURL)` — POSIX rename of the directory inode, single atomic step on APFS.
  3. On launch, sweep `rules-staging-*` leftovers (interrupted refreshes).
  Alternatively, write a "commit marker" file (`bbtb-manifest-committed-v<N>.flag`) as the final atomic step, and on read prefer files matching the marker version.

---

### [HIGH] A5-006: SSRF blocklist runs on URL.host string — DNS rebinding bypasses it

- **Location:**
  - `RulesFetcher.swift:101-114` (host check on `url.host` string)
  - `ConfigParser/SubscriptionURLFetcher.swift:253-255` (accepted-risk comment: "DNS-rebinding attack ... NOT closed in Phase 3 — will require custom URLSession resolver. Carry-forward → Phase 7")
- **Dimension:** security
- **Description:** `isBlockedHost("rules.bbtb.example")` returns false because the string check looks at the hostname, not the resolved IP. An attacker controlling DNS for `rules.bbtb.example` (or running a captive portal that hijacks DNS) can resolve it to `127.0.0.1` or `169.254.169.254` (AWS metadata) or an internal IP that the device can reach over the carrier's intranet (corporate Wi-Fi). Since the rules URL is over HTTPS and the legitimate cert covers `rules.bbtb.example`, the attacker can only do this if they have a valid TLS cert for the rogue endpoint, which limits scope — but cert pinning is NOT applied here (no `URLSessionDelegate` evaluating server trust against pinned SPKIs).
- **Why it matters:** On user's home Wi-Fi an evil router can MITM `rules.bbtb.example` by DNS hijack + a self-signed cert if the user has ever accepted such a cert system-wide. On corporate networks with MDM-installed root CAs, DNS rebinding fully bypasses the SSRF guard and lets the attacker serve a signed manifest **iff** they have the private key — which combines with A5-001 to make this very attack viable in TestFlight if the placeholder key is ever leaked.
- **Suggested fix:** Either (a) accept the documented risk and clarify in `wiki/security-gaps.md` that DNS-rebinding remains carry-forward, (b) implement cert pinning for `rules.bbtb.example` (mirror the v1.1+ subscription pinning design that was downgraded), or (c) explicitly resolve via `getaddrinfo`, run `isBlockedHost` on the IP, and use the IP in the URL request (with Host header preserved) — heaviest but cleanest. For TestFlight the right call is probably (a) + ensure A5-001 is fixed so signature verify alone is the trust gate.

---

### [MEDIUM] A5-007: `forceUpdate` cooldown uses `clock.now()` and `Date` arithmetic — wallclock manipulation bypasses 60s rate limit

- **Location:** `RulesEngineCoordinator.swift:436-450`
- **Dimension:** security / logic
- **Description:** Cooldown gate compares `clock.now().timeIntervalSince(last)`. `Date` reflects wallclock. User toggling device time backwards before tapping force-update produces a negative `elapsed`, which is `< cooldownDuration`, so the cooldown stays "active" — that's the safe failure mode. But toggling time **forwards** by 60s skips cooldown. On iOS a user can manipulate device time freely. Combined with mass refresh, this lets a hostile (or curious) user DoS the rules VPS by setting time +1h, tapping force-update, repeating.
- **Why it matters:** Server-side rate limiting on the VPS is the real defense, but the doc comment claims client-side enforcement ("Не позволяет admin DoS-ить VPS repeated taps"). The claim is false against time-aware adversaries. For TestFlight (small internal user base) the impact is negligible, but ship a note.
- **Suggested fix:** Use `ContinuousClock.now` (monotonic across reboots-not but across suspend-yes on iOS) or `mach_absolute_time` for monotonic. The `Clock.swift` abstraction can return a monotonic Date alternative. Alternatively, rely on server-side rate limiting and remove the client-side cooldown claim from comments.

---

### [MEDIUM] A5-008: `Bundle.module.url` lookup fails silently on macOS Catalyst / future SwiftPM regressions → bootstrap-failed-silently swallows the error

- **Location:** `RulesEngineCoordinator.swift:244-250` ("Fail-soft" handler)
- **Dimension:** logic / bugs
- **Description:** If `BaselineRulesLoader.loadManifest` throws (missing resource — likely a build bug), `bootstrap()` only logs `.error` and returns. `cachedManifest` stays nil, `currentSnapshot()` returns nil, and the UI shows "rules not loaded" — but no telemetry, no fatal, no signal to the user. In TestFlight this could silently degrade all routing to "no rules" without anyone noticing for weeks.
- **Why it matters:** Phase 8 W4 BG-task and Phase 13 split-tunneling rely on baseline being present. A bundling regression on day-1 TestFlight build would result in no-routing-rules-applied silently. The Phase 1 device-debug methodology lessons (memory note `project_phase1_debugging_lessons`) suggest this is a recurring failure mode.
- **Suggested fix:** On `LoadError.resourceMissing` in `bootstrap()`, post a distinct notification (e.g., `.bbtbRulesEngineBaselineMissing`) so the UI or telemetry layer can react. Or surface the failure in `currentSnapshot()` return type — e.g., make it `Result<RulesSnapshot, BootstrapError>?`. At minimum, log to a counter that's visible in app diagnostics (the future RULES-09 viewer should show "baseline missing — contact support").

---

### [MEDIUM] A5-009: Reentrancy gap in actor — `isInFlight` guard is necessary because actor reentrancy at `await` points allows interleaving

- **Location:** `RulesEngineCoordinator.swift:267-275`, `436-452`
- **Dimension:** thread-safety
- **Description:** `performBackgroundRefresh` is `async` on an `actor`. Between any `await` (e.g., `fetcher.fetchWithFailover`, `cache.write`), other actor-isolated methods can interleave on the same actor (Swift's actor reentrancy semantics). The `isInFlight` flag handles concurrent `performBackgroundRefresh` calls correctly. **However:** `forceUpdate()` records `lastForceUpdateAt = clock.now()` BEFORE calling `await performBackgroundRefresh()` (line 450), then awaits. A concurrent caller can read `lastForceUpdateAt` and immediately hit cooldown — that's the intended behavior. But `cachedManifest` is read in `forceUpdate` line 455 / 461 AFTER an await; between the await and the read, a `bootstrap()` call could have mutated `cachedManifest`. The result is `.success(version: ...)` reporting a version from bootstrap rather than the just-completed refresh. Edge case but possible at app launch when both bootstrap and force-update are queued.
- **Why it matters:** UI toast reports wrong version. Low impact but indicates the broader actor-reentrancy mental model isn't being applied consistently. The `isInFlight` guard happens to be the right primitive but doesn't cover all races.
- **Suggested fix:** Capture the return value from `performBackgroundRefresh` and return the version from the manifest snapshot taken at that moment, not from `self.cachedManifest` post-await. Or use a snapshot pattern: `let outcome = await refreshAndSnapshot()` returning `(Bool, Int?)`.

---

### [MEDIUM] A5-010: Notification posts on MainActor without `nonisolated` — adds an unnecessary detached Task on every successful refresh

- **Location:** `RulesEngineCoordinator.swift:421-428`
- **Dimension:** thread-safety / minor perf
- **Description:** `Task { @MainActor in NotificationCenter.default.post(...) }` creates an unstructured task. Two issues: (1) the snapshot capture is fine (Sendable struct), (2) but `NotificationCenter.default.post` is itself nonisolated and synchronous-OK from any thread for `Notification.Name`. The MainActor hop is needed only if observers explicitly subscribed with `queue: .main`. Per memory note `feedback_nevpn_observer_queue_main` the pattern is to use `queue: nil + Task { @MainActor }` hop **inside the observer**, not at post time. Doing the hop at post time forces every observer (even nonisolated ones) to wait for MainActor.
- **Why it matters:** Minor: under MainActor pressure (cold start), the notification can lag arbitrarily. The doc comment at lines 12-15 acknowledges convenience but inverts the recommended pattern.
- **Suggested fix:** Post from current actor: `NotificationCenter.default.post(name: .bbtbRulesEngineDidUpdate, object: snapshot)` directly. Observers in MainActor classes use `queue: nil` + internal `Task { @MainActor }` hop.

---

### [MEDIUM] A5-011: `cache.write(manifestData, filename: "baseline-rules-manifest.json")` reuses the BASELINE filename for server-fetched manifest — semantic confusion + bootstrap idempotency hole

- **Location:**
  - `RulesEngineCoordinator.swift:404` (server manifest written as `baseline-rules-manifest.json`)
  - `RulesEngineCoordinator.swift:201-218` (bootstrap idempotency check on same filename)
- **Dimension:** logic
- **Description:** `bootstrap()` checks if `baseline-rules-manifest.json` exists — if so, treats as "already bootstrapped." After a successful server refresh, that file contains the **server** manifest, not the baseline. If on next cold-start the user uninstalls the app while preserving App Group state (rare on iOS but possible via Settings → General → Storage), or if the App Group survives a misbehaving reinstall, `bootstrap()` will decode the server manifest as if it were baseline, and skip the embedded baseline hydration entirely. This is mostly benign because the server manifest is strictly newer, but: if the server manifest's signature was verified by an OLD public key (key rotated since), the bytes are still treated as trusted. And the file naming creates a confusing trail in logs.
- **Why it matters:** Refactoring landmine. Also creates a corner case where stuck-on-old-key state cannot be self-healed by uninstall (only by uninstall + DeviceCleanAll).
- **Suggested fix:** Either (a) write the server manifest to a distinct filename like `server-rules-manifest.json` and have `currentSnapshot()` prefer it over baseline, or (b) on `bootstrap()` check both existence AND that the on-disk version is the embedded baseline version (compare to `Bundle.module` baseline version), and overwrite if mismatched.

---

### [LOW] A5-012: `cache.write` throws are swallowed at outer scope but file partial state left on disk

- **Location:** `RulesEngineCoordinator.swift:399-411`
- **Dimension:** logic / atomicity
- **Description:** The `do/catch` wraps all 8 `cache.write` calls. If write #4 fails (disk full), writes #1-3 stay on disk. `lastFailureReason = .fileError`, return false. The next refresh attempt re-fetches the manifest, sees `version > cachedVersion` (cachedManifest in-memory not updated), tries again — could partially succeed. But if the device is permanently low on storage, repeated partial writes accumulate cruft.
- **Why it matters:** Minor — no security impact, but eventually fills storage with partial SRS files. iOS will reap caches on memory pressure, so self-healing.
- **Suggested fix:** Subsumed by A5-005's staging-directory fix (one rename = all-or-nothing).

---

### [LOW] A5-013: `fetchWithFailover` non-FetchError mapping loses information

- **Location:** `RulesFetcher.swift:202-209`
- **Dimension:** bugs
- **Description:** Non-`FetchError` exceptions in `fetchWithFailover` are mapped to `.httpStatusError(0)` — comment acknowledges this is wrap-as-opaque. But this loses URLError codes that would help debug (e.g., `.dnsLookupFailed`, `.notConnectedToInternet`). Coordinator only sees "all mirrors failed [.httpStatusError(0), .httpStatusError(0), .httpStatusError(0)]" with no signal of root cause.
- **Why it matters:** Debug-only. TestFlight users reporting "rules not updating" → developer reads logs → sees opaque `httpStatusError(0)` for three mirrors → has to guess.
- **Suggested fix:** Add a `FetchError.networkError(URLError.Code)` case or carry `String(describing: error)` along.

---

### [LOW] A5-014: Mirror URL list hardcodes `rules.bbtb.example` / `rules2.bbtb.example` / `rules3.bbtb.example` placeholders

- **Location:** `RulesEngineCoordinator.swift:116-120`
- **Dimension:** bugs / configuration
- **Description:** Doc says "заменяются на real VPS URLs в W7" — same status as A5-001 placeholder public key. If W7 was not done before TestFlight, every refresh attempt hits `.example` TLD (RFC-2606 reserved), DNS fails immediately, `lastFailureReason = .network`, no rules ever update — combined with A5-008 silent baseline failure path, a TestFlight install with no W7 closure would have **no working rules pipeline at all** but show no surfaced error.
- **Why it matters:** Same TestFlight blocker class as A5-001.
- **Suggested fix:** Verify W7 completed before TestFlight. If shipping with placeholders intentionally (no server yet), document in release notes and surface a UI banner ("Rules updates not yet available in this build").

---

## Notes

- **Tests are out of scope** but the test injection pattern (`SignatureVerifierProtocol`, `RulesFetcherProtocol`, `ClockProtocol`) is well-designed and clean.
- **Logger redaction:** All log calls use `privacy: .public` correctly — host/version/byte-count are not user secrets. The `errorDescription` mapping in `FetchError` does include URL fragments, which are logged at `.error` level; in production builds these will appear in Console.app. Acceptable since URL = public mirror endpoint, but if multi-tenant URLs ever appear, revisit.
- **R8 guard validate-r1-r6.sh extension** referenced at PublicKey.swift:22 — confirm presence/absence in `scripts/validate-r1-r6.sh` separately (out of A5 scope but cross-cutting).
- **The combined TestFlight gating dependency** between A5-001 (placeholder key) and A5-014 (placeholder URLs) suggests W7 (08-08-PLAN.md) was a known gap when Phase 8 was paused; verify W7 status in `.planning/phases/08-rules-engine-split-tunneling/`.
- **D-14 toggle interaction (Phase 13):** out of A5 scope but worth flagging — if `routingRulesEnabled = false` in App Group suite, the entire signed pipeline still runs (no early exit on toggle). On disabled state, refresh still costs network. Consider gating `performBackgroundRefresh` on toggle to save battery.

