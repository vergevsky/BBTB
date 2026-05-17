# A5 — RulesEngine package audit (Opus 4.7 reviewer #5, Audit-4)

**Baseline:** HEAD `ccbce8a` (Plan 07 closure index + AUDIT-3 verdict update; post-Plan-07 d802e72).
**Scope:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/` — 10 Swift files (~1290 LOC).
**Lens:** Security (Ed25519 signing trust chain, RulesFetcher SSRF, atomic cache writes, allowlist regex) + Thread safety (actor isolation, NotificationCenter, nonisolated cleanup race) + Logic (manifest validation, bootstrap idempotency, refresh recovery, partial-failure semantics).

**Prior-art treatment:** Plan 05 + Plan 07 closures are re-verified, not re-reported unless I find a hole in the patch. Plan 07 changes for RulesEngine are **docs-only** (T-C-D2 PublicKey doc-comment + T-C-C5H1 `commitTransaction` honesty note) — no code logic changed since AUDIT-3 A5 review.

---

## Verdict

🟢 **CLEAR APPROVE для TestFlight (Internal + External) from HEAD `ccbce8a`.**

The package's security primitives are sound: Ed25519 verify-first → SHA-256 binding → allowlist filename guard → atomic write order is consistently applied across `performBackgroundRefresh`. The Plan 07 doc honesty updates (PublicKey owner clarification + commitTransaction depth correction) accurately describe the actual implementation — no daylight between docs and code post-fix.

Re-audit findings: **0 CRITICAL, 0 HIGH, 4 MEDIUM (3 carry-over from Audit-3 confirmed-open, 1 newly-spotted), 5 LOW** — all defence-in-depth / docs / coverage / minor-correctness items. None block TestFlight (Internal or External). Three notable items:

1. **M-A5-4-01 (CARRY-OVER from M-A5-3-03)** — `bootstrap()` partial-write leaves stuck idempotency state. Plan 07 did not address. Realistic only on disk-pressure failure during first-launch; v1.0.1 candidate.
2. **M-A5-4-02 (NEW)** — `bootstrap()` recovery path decodes `baseline-rules-manifest.json` from App Group cache **without re-verifying signature**. After first successful refresh, this filename holds the SERVER manifest, not the embedded baseline. Recovery trust-model gap if App Group container is tampered (requires same trust boundary as main app — not an exploit, but defence-in-depth lapse).
3. **M-A5-4-03 (NEW)** — `RulesManifest.files: [FileEntry]` has no uniqueness invariant. Two entries with the same `name` cause the second's bytes to overwrite the first on disk (last-write-wins). Requires malicious VPS admin / key compromise to exploit. Add `Set<String>` check in `performBackgroundRefresh` step 6b.

The CV-H1 finding from Audit-3 (`route.rule_set[].path` allowlist gap in `SingBoxConfigLoader`) is **out-of-scope для this reviewer** (lives in PacketTunnelKit) but explicitly closed by Plan 07 T-C-H1' (commit 98f4800) — no regression risk for RulesEngine.

---

## Plan 07 RulesEngine changes verification

### T-C-D2 (commit `d802e72`) — `PublicKey.swift` doc-comment fix

**What changed:** Doc-comment was claiming placeholder bytes `0x00..0x1F` sequential but actual bytes are `0xB5 0x3F 0xCF 0xC3 …` (random-distribution). Updated text to honestly describe «non-trivial placeholder, NO matching private key exists, signed-rules pipeline currently dead-code in v1.0».

**Verification result: ✅ DOC-ACCURACY HOLDS with one caveat.**

- File `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift:22-31` now correctly notes the discrepancy and explicitly disclaims production keypair pairing.
- The `publicKeyBytes` array (lines 57-62) matches the actual on-disk bytes — confirmed via `git diff d802e72^ d802e72`.
- **⚠️ Minor doc imprecision (LOW-grade):** the new text calls these bytes «non-trivial random byte sequence» / «32 random-distribution bytes». Reading `BBTB/scripts/build-baseline-rules.sh:80-89, 211-217` shows these bytes are actually a **derived Ed25519 public key from an ephemeral keypair** (uniform-random because keygen is uniform random, but NOT arbitrary bytes — they are a valid point on Curve25519 and have a corresponding mathematically-derived private key, which was deleted on script exit via `trap`). The doc could be more precise: «these are an Ed25519 public key derived from an ephemeral private key that was generated and then deleted during baseline-build; no party currently holds the matching private key». **Not a security issue** — practically the trust property is the same (no exploitable signing oracle). Marking as L-A5-4-01.

**Q1 owner clarification (Plan 07):** the bytes ARE a real Curve25519 public key (passes `Curve25519.Signing.PublicKey(rawRepresentation:)` validation — verified by the fact that `try!` does not crash in production). They are NOT random arbitrary bytes. This nuance does not affect security — the matching private key was discarded post-keygen, so functional behavior matches «no private key exists».

### T-C-C5H1 (commit `047e60c`) — `SRSCacheStore.commitTransaction` doc honesty

**What changed:** Doc-comment was claiming «generation directory + atomic swap» (overstatement from Plan 05 T-B3' commit message). Now honestly describes:
- per-file rename loop with defence-in-depth via extension's libbox-side sha256 re-verify
- `defer cleanupStagingFiles()` orphan-purge discipline
- v1.1+ TODO for true versioned-generation atomic swap (referenced to `wiki/security-gaps.md` R25)

**Verification result: ✅ DOC NOW MATCHES CODE.**

- File `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift:74-91` honestly describes the implementation.
- The code (lines 92-133) is unchanged from Plan 05 T-B3' — still per-file `replaceItemAt`/`moveItem` loop. Codex was correct in C5'-3-001.
- Defence-in-depth claim is verifiable:
  - Each `.srs` file's SHA-256 is verified in `RulesEngineCoordinator.performBackgroundRefresh` step 7 (lines 421-427) BEFORE write to cache.
  - Extension reads `.srs` files independently via libbox `route.rule_set.path` per-entry (each rule_set load is independent).
  - Mid-loop Phase 3 failure → mixed-state on disk → next refresh re-verifies all files vs new manifest's sha256 → mismatch detected → fall back to baseline. ✅ Sound.

### Plan 05 closures (T-A1', T-B3', T-B4', T-B5'-extra, T-C11') — still hold

All Plan 05 closures verified intact in AUDIT-3 A5; no regression in Plan 07 changes (docs-only).

---

## Findings (re-audit)

### MEDIUM

#### M-A5-4-01 (CARRY-OVER M-A5-3-03 from Audit-3) — `bootstrap()` partial-write leaves stuck idempotency state

- **File:** `RulesEngineCoordinator.swift:200-252`
- **Severity:** MEDIUM (logic — first-launch reliability under disk pressure)
- **Description:**
  `bootstrap()` writes 8 files in sequence (manifest, manifest.sig, then 3 × (.srs, .srs.sig)):
  ```swift
  try await cache.write(manifestData, filename: "baseline-rules-manifest.json")          // step 1
  try await cache.write(manifestSig, filename: "baseline-rules-manifest.json.sig")      // step 2
  for category in [block, never, always] {
      try await cache.write(srsData, filename: basename)                                // step 3..5
      try await cache.write(sigData, filename: "\(basename).sig")                       // step 6..8
  }
  ```
  Idempotency gate at line 202 checks `cache.exists(filename: "baseline-rules-manifest.json")`.

  If step 1 succeeds but step 5 fails (disk pressure, sandbox jitter on first launch, OS-level write error), the on-disk state is:
  - `baseline-rules-manifest.json` ✅
  - `baseline-rules-manifest.json.sig` ✅
  - `bbtb-baseline-block.srs` ✅, `.sig` ✅
  - `bbtb-baseline-never.srs` ❌ MISSING
  - `bbtb-baseline-always.srs` ❌ MISSING

  On next app launch, `bootstrap()` sees the manifest file → idempotency returns no-op → never repairs the gap. Extension's libbox tries to load `bbtb-baseline-never.srs` → file missing → rule_set load fails → potentially extension crash or silent rule degradation depending on libbox config error handling.

- **Likelihood:** LOW (`Data.write(.atomic)` very rarely fails mid-sequence on iOS — sandbox container is single-volume). But TestFlight ad-hoc disk pressure on small devices (iPhone SE 1st gen 16GB) could trigger.
- **Impact when realized:** broken rules until first successful `performBackgroundRefresh` (6h+ after launch). User-perceptible if extension's libbox config explicitly references `bbtb-baseline-never.srs` and treats missing-rule_set as fatal.
- **Suggested fix (10-min, v1.0.1):**
  ```swift
  let allBaselineFilesPresent = await cache.exists(filename: "baseline-rules-manifest.json")
      && await cache.exists(filename: "bbtb-baseline-block.srs")
      && await cache.exists(filename: "bbtb-baseline-never.srs")
      && await cache.exists(filename: "bbtb-baseline-always.srs")
  if allBaselineFilesPresent {
      // existing recovery path — decode cached manifest
      return
  }
  // Otherwise re-run full hydration (idempotent — overwrites whatever exists).
  ```
- **Plan 07 disposition:** NOT addressed; documented in AUDIT-3 as M-A5-3-03; v1.0.1 carry-forward.

#### M-A5-4-02 (NEW) — `bootstrap()` recovery path decodes cached manifest WITHOUT signature re-verification

- **File:** `RulesEngineCoordinator.swift:210-218`
- **Severity:** MEDIUM (security / integrity — defence-in-depth gap)
- **Description:**
  `bootstrap()` recovery path (lines 210-218) decodes the on-disk `baseline-rules-manifest.json` to repopulate `cachedManifest`:
  ```swift
  if cachedManifest == nil, let data = await cache.read(filename: "baseline-rules-manifest.json") {
      do {
          cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: data)
      } catch { ... }
  }
  ```
  No signature verify is performed.

  **Why this matters:** the filename `baseline-rules-manifest.json` is **misleading** — after the first successful `performBackgroundRefresh` (lines 462-463), this file is OVERWRITTEN with the server-fetched manifest:
  ```swift
  batch.append((manifestData, "baseline-rules-manifest.json"))
  batch.append((manifestSig, "baseline-rules-manifest.json.sig"))
  ```

  So on every subsequent launch, `bootstrap()` recovery decodes whatever is in App Group cache **without verifying it against `baseline-rules-manifest.json.sig`**. The doc-comment line 197-199 says:
  > Trust path: baseline = embedded resources, integrity guaranteed by Apple code signing (T-08-W2-08 disposition `accept`). signature verify НЕ применяется к baseline — этот шаг pure delivery from Bundle.module → App Group.

  This trust justification only holds for first-launch hydration. After refresh, the file is no longer «from Bundle.module»; it's server-fetched data sitting in writable App Group container.

- **Threat scenario:**
  Attacker with App Group write access (requires same trust boundary as main app — e.g., malicious main-app bundle replacement, jailbreak-tier compromise) could overwrite cached manifest with adversarial content. Recovery accepts it blindly. Subsequent refresh's monotonic version check (line 342) would gate against tampered version BUT only after the recovered (potentially-malicious) `cachedManifest?.version` is used as the comparison baseline. Attacker could bump version to `Int.max` to lock out future refreshes.

  **However:** the on-disk `.srs` files would also be tampered, and extension's libbox doesn't sig-verify (only the main-app coordinator does). So the actual attack surface is:
  - Force coordinator to think it's at `version: Int.max` → all future server refreshes fail with `.alreadyLatest` → user stuck on tampered rules.
  - The tampered rule content is delivered to extension via App Group → extension routes traffic per tampered rules (e.g., split-tunnel exclude all enemy domains).

- **Mitigating factors:**
  1. iOS sandbox isolation: App Group container is only writable by main app + its declared extensions. No other process can write.
  2. Requires main-app binary replacement (Apple code-sign violation) to be exploitable.
  3. `currentSnapshot()` only displays rules in UI — does not directly control routing. Routing is gated by `routingRulesEnabled` toggle (Phase 13 D-04) which only injects EMBEDDED baseline rules via PacketTunnelKit, not the cached server manifest. So actual routing impact is minimal in v1.0 (server-fetched rules aren't wired into extension yet).
- **Severity rationale:** MEDIUM not HIGH because (a) requires Apple code-sign violation to be reachable, (b) server-fetched rules aren't wired to extension routing in v1.0 (Phase 13 only injects embedded baseline), (c) signature verify is performed on FUTURE refreshes — so tampered cache state is corrected on next successful network refresh. But it IS a defence-in-depth gap and the doc-comment's trust justification is incorrect.

- **Suggested fix (30-min, v1.0.1):**
  ```swift
  if cachedManifest == nil,
     let data = await cache.read(filename: "baseline-rules-manifest.json"),
     let sig = await cache.read(filename: "baseline-rules-manifest.json.sig") {
      // Verify signature on cached manifest before decoding.
      // Note: for first-launch baseline this succeeds because baseline.sig was
      // signed with the ephemeral keypair whose pubkey is in PublicKey.swift.
      // For post-refresh state, sig was server-signed — also verifies.
      // If tampered, signer.verify returns false → skip recovery, leave
      // cachedManifest = nil → caller treats as "no rules loaded" state.
      guard signer.verify(message: data, signature: sig) else {
          RulesEngineLogger.coordinator.error(
              "RulesEngineCoordinator.bootstrap recovery: cached manifest signature INVALID — refusing to decode tampered state"
          )
          return
      }
      do { cachedManifest = try JSONDecoder().decode(RulesManifest.self, from: data) }
      catch { ... }
  }
  ```

  **⚠️ Caveat:** because the current production `PublicKey` placeholder has no matching private key, the baseline `.sig` files were signed by the now-deleted ephemeral keypair (per `build-baseline-rules.sh:80-89` ephemeral mode). The pubkey in `PublicKey.swift` was updated to match the ephemeral pubkey by the script → so `signer.verify(baseline.sig, baselineBytes)` actually PASSES with the current placeholder. Recovery verify would succeed.

  After first refresh, the on-disk sig is server-signed — but no real production server exists (placeholder mirrors `rules.bbtb.example`). So in v1.0, recovery would only ever verify baseline-stamped sigs (because no real refresh ever completes). This fix is **net positive** for trust path consistency even though no exploit is reachable in v1.0.

- **Plan 07 disposition:** newly-spotted in Audit-4; not in AUDIT-3.

#### M-A5-4-03 (NEW) — `RulesManifest.files: [FileEntry]` lacks duplicate-name invariant

- **File:** `RulesEngineCoordinator.swift:366-374` (step 6b validation) + `RulesManifest.swift:47` (schema decl)
- **Severity:** MEDIUM (logic — defence-in-depth against compromised VPS admin)
- **Description:**
  `RulesManifest.files` is a plain array `[FileEntry]`. The decode in `performBackgroundRefresh` step 3 accepts any JSON array — duplicates allowed. Step 6b validates each entry's filename for path traversal but does not check uniqueness.

  Step 7 iterates each entry, fetches + verifies + accumulates into `verifiedSrsPayloads`. Step 8 (`commitTransaction`) writes all bytes batched — duplicates result in last-write-wins per filename via `replaceItemAt` (second write replaces first's inode).

  **Attack scenario:**
  Compromised VPS admin (or someone with control of the private signing key) crafts a manifest with two entries:
  ```json
  {
      "files": [
          { "name": "bbtb-block.srs", "category": "block_completely", "sha256": "...A...", "sig_path": "block-A.srs.sig" },
          { "name": "bbtb-block.srs", "category": "never_through_vpn", "sha256": "...B...", "sig_path": "block-B.srs.sig" }
      ]
  }
  ```
  Both entries pass:
  - Signature verify ✅ (manifest is signed by trusted key — defence relies on key not being compromised).
  - SHA-256 binding ✅ for each respective `.srs` body.
  - Filename allowlist ✅.

  But on disk, only ONE `bbtb-block.srs` file exists at the end (second entry's content). The «block_completely» rule_set's actual content depends on which entry was iterated last (order-dependent).

  More subtle: extension reads `bbtb-block.srs` via libbox. PacketTunnelKit's sing-box config almost certainly references `bbtb-block.srs` for the `block_completely` rule_set slot specifically. So the second-entry's content (labeled `never_through_vpn` in the manifest) ends up driving the `block_completely` routing decision.

  Net result: attacker swaps routing categories.

- **Likelihood:** requires private-key compromise OR malicious admin. Trust model assumes admin is trusted. But defence-in-depth principle: client should not blindly trust arbitrary admin actions when the schema can be tightened cheaply.
- **Severity rationale:** MEDIUM because (a) requires key compromise to be reachable, (b) the routing engine (PacketTunnelKit) uses the filenames not the manifest categories, so category labels in manifest are advisory, (c) easy fix.
- **Suggested fix (15-min):** Add uniqueness check in step 6b after path-traversal check:
  ```swift
  var seenNames = Set<String>()
  for entry in newManifest.files {
      if hasPathTraversalRisk(entry.name) || hasPathTraversalRisk(entry.sigPath) {
          lastFailureReason = .decode
          return false
      }
      guard seenNames.insert(entry.name).inserted else {
          lastFailureReason = .decode
          RulesEngineLogger.coordinator.error(
              "RulesEngineCoordinator.performBackgroundRefresh: duplicate filename in manifest: \(entry.name, privacy: .public)"
          )
          return false
      }
  }
  ```
  Also: enforce expected category set (`block`/`never`/`always` exactly once each) — manifest schema should be `[Category: FileEntry]` not `[FileEntry]`. Wider refactor; v1.0.1 candidate.

- **Plan 07 disposition:** newly-spotted in Audit-4; not in AUDIT-3.

#### M-A5-4-04 (CARRY-OVER M-A5-3-04 from Audit-3) — `RulesFetcher.fetch` buffers full response BEFORE size cap (vs `JSONEndpoint` streaming)

- **File:** `RulesFetcher.swift:147-176`
- **Severity:** MEDIUM (DoS / memory — parity gap)
- **Description:**
  Plan 05 T-B2' (commit `515f8dc`) updated `JSONEndpoint` in ConfigParser to use `URLSession.bytes(for:)` streaming — caps payload size during receive, not after. `RulesFetcher.fetch` still uses `data(for:)` which **buffers the entire response in memory before checking `data.count <= maxBytes`**.

  Lines 149-176:
  ```swift
  (data, response) = try await activeSession.data(for: request)  // buffers ALL bytes
  ...
  guard data.count <= maxBytes else { throw FetchError.payloadTooLarge(data.count) }
  ```

  Attacker serving a 5 GB response would force the iOS extension/main-app to allocate 5 GB before the cap fires. iOS jetsam will kill the process well before that, but the budget is consumed before the rejection.

- **Mitigating factor:** the URL must already pass HTTPS + SSRF + redirect checks. Only a compromised mirror VPS or DNS-spoof + acquired-trusted-cert attacker could deliver this. Combined with sig verify enforcement post-fetch, no integrity bypass — only resource exhaustion / DoS.
- **Severity rationale:** MEDIUM because (a) reaches into the BGAppRefreshTask path which has 30-sec OS budget — attacker forcing OOM here would prevent rules refresh from ever completing, (b) parity with Plan 05 T-B2' is straightforward.
- **Suggested fix (1h, post-TestFlight):** rewrite to use `URLSession.bytes(for:)` accumulator pattern (see `JSONEndpoint.swift` for pattern reference):
  ```swift
  let (asyncBytes, response) = try await activeSession.bytes(for: request)
  var buffer = Data()
  buffer.reserveCapacity(min(maxBytes, 64 * 1024))
  for try await byte in asyncBytes {
      buffer.append(byte)
      if buffer.count > maxBytes {
          throw FetchError.payloadTooLarge(buffer.count)
      }
  }
  ```
- **Plan 07 disposition:** NOT addressed; carry-forward to v1.0.1.

---

### LOW

#### L-A5-4-01 (REFINEMENT of L-A5-3-09 / C5'-3-005) — Plan 07 T-C-D2 doc-comment imprecision: «random byte sequence»

- **File:** `PublicKey.swift:22-31, 50-56`
- **Severity:** LOW (doc accuracy)
- **Description:**
  Plan 07 D-2 updated the doc-comment to call `publicKeyBytes` a «non-trivial random byte sequence». This understates the actual mechanism: per `BBTB/scripts/build-baseline-rules.sh:80-89, 211-217`, ephemeral mode generates a real Ed25519 keypair via `openssl genpkey -algorithm ed25519`, derives the DER-encoded public key, and rewrites `publicKeyBytes` with the matching 32-byte raw pubkey. The bytes are uniform-random in distribution **because Ed25519 keygen is uniform random**, but they are mathematically NOT arbitrary bytes — they are a valid Curve25519 point with a corresponding (now-deleted) private key.

  This precision matters for two reasons:
  1. The pubkey actually verifies the baseline `.sig` files (they were signed by the ephemeral private key in the same script run). Doc-comment line 30-31 says «NO corresponding private key exists; rule_set verify pipeline currently dead-code» — partially correct (no recoverable private key) but obscures that the baseline `.sig` files DO verify against this pubkey. If the recovery path were ever updated to verify (see M-A5-4-02), it would actually succeed.
  2. Future-developer confusion: someone reading "random bytes, no real key" might assume the bytes have no cryptographic significance and substitute arbitrary bytes — which would break baseline sig verification (and break a future M-A5-4-02 fix).

- **Suggested fix (5-min):** sharpen wording:
  > These bytes are a real Ed25519 public key derived from an **ephemeral keypair** generated by `build-baseline-rules.sh` (ephemeral mode). The matching private key was discarded on script exit (`trap` cleanup), so no party currently holds a signing oracle for this pubkey. The cached baseline `.sig` files were signed by the same ephemeral private key, so they DO verify against this pubkey — useful for first-launch trust-path consistency even though no production refresh ever validates against it.

- **Plan 07 disposition:** Plan 07 T-C-D2 doc update was net-positive (corrected the worse «0x00..0x1F sequential» falsehood) but introduced this softer imprecision. Refining is optional polish.

#### L-A5-4-02 (CARRY-OVER from Audit-3 M-A5-3-02) — `commitTransaction` does NOT fsync directory after rename

- **File:** `SRSCacheStore.swift:108-129`
- **Severity:** LOW (durability — non-iOS edge)
- **Description:** POSIX `rename(2)` is atomic but durability against power loss requires `fsync(dir_fd)` on the containing directory. On iOS, application sandbox-mediated file operations typically include implicit syncs at suspend/terminate, and the iOS storage stack's metadata journaling generally preserves rename atomicity across unclean shutdowns. So this is theoretical for iOS. macOS desktop deployment (Phase 12+ macOS build) is more exposed.
- **Plan 07 disposition:** not addressed; v1.0.1+ candidate.

#### L-A5-4-03 — `productionMirrors` is `https://rules.bbtb.example/...` placeholder; ships in v1.0 binary

- **File:** `RulesEngineCoordinator.swift:117-121`
- **Severity:** LOW (operational — confirmed as v1.1+ scope in `wiki/security-gaps.md` R25)
- **Description:** Both iOS (`BBTB_iOSApp.swift:176`) and macOS (`BBTB_macOSApp.swift:133`) instantiate `RulesEngineCoordinator()` with default mirrors. Background refresh runs every 6h. Each refresh attempt:
  1. Resolves `rules.bbtb.example` → NXDOMAIN (`.example` is RFC 2606 reserved TLD).
  2. URLSession throws `URLError.cannotFindHost`.
  3. `fetchWithFailover` catches as generic error → `httpStatusError(0)` → all 3 mirrors fail → `allMirrorsFailed([...])`.
  4. `performBackgroundRefresh` → `lastFailureReason = .network` → returns false.

  Net effect: BGAppRefreshTask wakes the app every 6h to perform a futile DNS lookup loop. Minor battery impact (~3 DNS attempts every 6h); no security exposure.

- **Mitigating factor:** even if attacker DNS-poisons `rules.bbtb.example` to a hostile server with valid TLS cert, signature verify on the manifest gates trust. Attacker cannot forge Ed25519 sig without the private key (and no party currently holds it for the placeholder pubkey). So MITM-via-DNS is mitigated by signature verify.

- **Suggested fix:** before v1.1+ public release, replace placeholder mirrors with real VPS URLs AND replace `PublicKey.publicKeyBytes` with the real production pubkey (matching real production private key). Both must change atomically (otherwise either the new pubkey rejects baseline sigs, or the new mirrors serve content not verifiable by old pubkey).
- **Plan 07 disposition:** carry-forward to v1.0.1+ deployment cycle (per Plan 04 / wiki R25).

#### L-A5-4-04 — Test coverage gap: no test for `commitTransaction` partial-failure paths

- **File:** `Tests/RulesEngineTests/SRSCacheStoreTests.swift` (only 6 tests, all `write/read/mtime/exists`)
- **Severity:** LOW (test coverage)
- **Description:**
  Plan 05 T-B3' added `commitTransaction` two-phase commit logic but no unit tests directly exercise it. The integration tests in `RulesEngineCoordinatorTests` cover the happy path via `performBackgroundRefresh`, but the following are uncovered:
  - Phase 2 staging write fails mid-loop (disk full simulation).
  - Phase 3 rename fails on 2nd of 8 files (file lock / permission denied).
  - `cleanupStagingFiles` removes orphan stagings from previous run on init.
  - `validateBareFilename` rejects Unicode fullwidth solidus / fraction slash / null bytes.
  - `validateBareFilename` rejects `..` substring.

- **Suggested fix:** add `SRSCacheStoreTests` covering each of the 5 cases above. ~1h work, valuable before v1.0.1 refactor to versioned-directory.
- **Plan 07 disposition:** not addressed; carry-forward.

#### L-A5-4-05 — `currentSnapshot()` materializes a new value-type on every call (allocation pressure if called from hot path)

- **File:** `RulesEngineCoordinator.swift:542-545, 550-559`
- **Severity:** LOW (perf — not in current hot path)
- **Description:**
  `currentSnapshot()` allocates a fresh `RulesSnapshot` struct + 3 `CategoryEntries` + array copies on every call. If a future contributor wires this into a `@Published var rulesSnapshot` that re-diffs every frame (SwiftUI body invocation), this could allocate per-frame.

  Current usage (per `MainScreenViewModel.swift` + `SettingsViewModel.swift`) is event-driven (post-`bbtbRulesEngineDidUpdate`), so not a hot path. But the actor-isolated method has no caching layer.

- **Suggested fix (v1.0.1):** memoize last-materialized snapshot keyed on `cachedManifest?.version` so repeated calls return the same value-type without re-allocation. Trivial — add `private var memoizedSnapshot: RulesSnapshot?` + invalidate in `bootstrap` / `performBackgroundRefresh`.

---

## Healthy patterns verified (Audit-4)

- **Actor isolation** — `SRSCacheStore` + `RulesEngineCoordinator` both `actor`s; all mutable state is actor-isolated; `directory: URL` correctly `nonisolated let` (immutable).
- **Trust chain order** — `RulesSigner.verify` (line 311) → JSON decode (line 322) → `srs_format_version` check (line 332) → monotonic version (line 342) → `total_size_bytes` cap (line 351) → path traversal allowlist (line 366) → per-file sig verify (line 395) → per-file sha256 binding (line 421) → atomic batch commit (line 464) → in-memory state mutation (line 474) → notification post (line 482). **Order is correct** — bytes are never trusted before signature verifies; in-memory state is mutated only after disk commit succeeds; notification fires last.
- **Allowlist filename validation** — `SRSCacheStore.validateBareFilename` correctly applies positive regex + `..` explicit reject + 256-char length cap; rejects Unicode (fullwidth solidus, fraction slash, NFKC/NFKD normalization holes).
- **`@Sendable` discipline** — all protocols (`SignatureVerifierProtocol`, `RulesFetcherProtocol`, `ClockProtocol`) are `Sendable`; no `@unchecked Sendable` in RulesEngine package (unlike PacketTunnelKit CV-H2 finding which Plan 07 fixed separately).
- **`@MainActor` hop for notification** — line 482 wraps `NotificationCenter.default.post` in `Task { @MainActor in ... }` per `feedback_nevpn_observer_queue_main.md` discipline.
- **Re-entry guard** (`isInFlight`) — protects against concurrent `performBackgroundRefresh` from BG task + foreground reentry + force-update racing.
- **Cooldown enforcement** (`forceUpdate`) — 60s gate per D-10; `lastForceUpdateAt` set BEFORE pipeline executes so even failed force-update counts toward cooldown (prevents repeated-failure DoS).
- **Defence-in-depth via SHA-256 + signature** — even if signature verify is fooled (e.g., quantum-future), per-file sha256 binding ensures hostile mirror cannot substitute alternate content under a stale-but-valid sig.
- **HTTPS-only + SSRF + redirect guard** — `RulesFetcher.fetch` builds ephemeral session with `HTTPSRedirectGuard` delegate when `URLSession.shared` is used (line 131-141). Reuse of `SubscriptionURLFetcher.isBlockedHost` ensures any future SSRF blocklist additions (e.g., Plan 07 T-C-H3' NAT64/6to4/IPv4-compat IPv6) propagate automatically to RulesEngine.

---

## Cross-validation notes with Audit-3

Comparing with my own AUDIT-3 review (`audit-3-reviewers/A5-rulesengine.md`):

| Finding | Audit-3 status | Audit-4 status | Notes |
|---|---|---|---|
| M-A5-3-01 — `commitTransaction` Phase 3 partial-failure docs | OPEN, downgraded by Plan 07 T-C-C5H1 doc honesty fix | ✅ **CLOSED** (docs now accurate) | Plan 07 047e60c |
| M-A5-3-02 — `commitTransaction` no fsync after rename | OPEN | OPEN, downgraded to LOW (L-A5-4-02) | iOS-specific mitigation noted |
| M-A5-3-03 — `bootstrap()` partial first-launch write | OPEN | OPEN → carried as M-A5-4-01 | Still unaddressed |
| M-A5-3-04 — `RulesFetcher` post-buffer maxBytes (parity gap) | OPEN | OPEN → carried as M-A5-4-04 | Still unaddressed |
| M-A5-3-05 — path-traversal failure misclassified as `.networkFailure` | OPEN | Re-checked — accurate (line 368 uses `.decode` which maps to `.networkFailure` per line 530); minor UI accuracy issue | Not re-listed |
| L-A5-3-09 / C5'-3-005 — PublicKey doc-comment mismatch | OPEN, addressed by Plan 07 T-C-D2 | ✅ **CLOSED** (with minor imprecision refinement L-A5-4-01) | Plan 07 d802e72 |
| **NEW** M-A5-4-02 | — | OPEN (newly spotted) | Recovery decode lacks sig verify |
| **NEW** M-A5-4-03 | — | OPEN (newly spotted) | Manifest files[] duplicates |

---

## Recommendation

🟢 **CLEAR APPROVE для Internal + External TestFlight from HEAD `ccbce8a`.**

No CRITICAL, no HIGH findings in RulesEngine scope. Plan 07 docs-honesty corrections (T-C-D2, T-C-C5H1) accurately reflect implementation reality — no daylight between docs and code.

**Tier B (v1.0.1 polish — ~3h total):**

| Finding | Effort | Priority |
|---|---|---|
| M-A5-4-01 — `bootstrap()` partial-write recovery (check all 8 files exist) | 10min | high (first-launch reliability) |
| M-A5-4-02 — `bootstrap()` recovery path sig-verify cached manifest | 30min | medium (defence-in-depth) |
| M-A5-4-03 — Add duplicate-name uniqueness check in manifest validation | 15min | medium (defence-in-depth) |
| M-A5-4-04 — `RulesFetcher` streaming `bytes(for:)` parity with `JSONEndpoint` | 1h | medium (DoS / OOM hardening) |
| L-A5-4-01 — Refine PublicKey doc-comment wording | 5min | low (docs polish) |
| L-A5-4-04 — Add `SRSCacheStoreTests` for `commitTransaction` failure paths | 1h | low (test coverage) |

**Tier C (v1.1+ deployment cycle):**

- L-A5-4-03 — replace placeholder mirrors + production pubkey atomically (already in wiki R25 backlog).
- L-A5-4-05 — memoize `currentSnapshot()` if it becomes hot path.
- L-A5-4-02 — `commitTransaction` directory fsync (only relevant for macOS desktop).

**Plan 07 disposition for RulesEngine:** Both Plan 07 RulesEngine tasks (T-C-D2 + T-C-C5H1) accurately closed the named Audit-3 findings (L-A5-3-09 / C5'-3-005 + C5'-3-001) via docs-honesty corrections. No code regressions. No security regressions. Trust chain remains intact.

---

## Files reviewed (10)

| File | LOC | Audit focus |
|---|---|---|
| `PublicKey.swift` | 73 | Plan 07 T-C-D2 doc update verification |
| `SRSCacheStore.swift` | 211 | Plan 07 T-C-C5H1 doc update + allowlist regex + actor isolation |
| `RulesSigner.swift` | 80 | Ed25519 verify primitive — non-throwing, length-gated |
| `RulesFetcher.swift` | 263 | SSRF + HTTPS + maxBytes + mirror failover + redirect guard |
| `RulesEngineCoordinator.swift` | 625 | Pipeline orchestration, trust chain order, idempotency |
| `RulesManifest.swift` | 159 | Schema decode invariants |
| `RulesSnapshot.swift` | 86 | UI-facing value-type |
| `BaselineRulesLoader.swift` | 71 | Bundle.module resource loading |
| `Clock.swift` | 17 | Test-injectable wallclock |
| `RulesEngineLogger.swift` | 18 | Subsystem-scoped Logger pattern |

Total reviewer content: ~1290 LOC across 10 files; ~635 lines of audit report produced.
