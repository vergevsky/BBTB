# C5 — RulesEngine (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 4 (0/0/3/1)

## Plan 07 closure verification
- T-C-D2 PublicKey doc-comment: PASS
- T-C-C5H1 SRSCacheStore doc honesty: PASS

## Critical
No critical findings in this RulesEngine pass.

## High
No high findings in this RulesEngine pass.

## Medium

### C5-4-001: `min_app_version` is not enforced before applying a signed manifest
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:331`
- **Dimension:** Logic / compatibility gate
- **Description:** `RulesManifest.minAppVersion` is documented as the minimum app version required to consume the manifest (`RulesManifest.swift:33-35`), but `performBackgroundRefresh()` only gates on `srsFormatVersion`, monotonic `version`, total size, and filename safety before fetching and committing all files (`RulesEngineCoordinator.swift:331-374`, `RulesEngineCoordinator.swift:452-475`). The field is then surfaced in the UI snapshot (`RulesEngineCoordinator.swift:550-557`) rather than used as an apply gate.
- **Why MEDIUM:** A signed server manifest intended for a newer client can still be written into the App Group cache and become the active rules cache for this build. The SRS format gate catches libbox binary-format incompatibility, but it does not cover future semantic changes in category meaning, filename conventions, or routing policy that `min_app_version` is supposed to fence.
- **Fix:** Inject the current app version into `RulesEngineCoordinator` or pass it into `performBackgroundRefresh()`, compare `newManifest.minAppVersion` with the current bundle version before Step 7, and reject unsupported manifests without committing files. Keep the UI prompt as a secondary user-facing signal.

### C5-4-002: Bootstrap recovery decodes the cached manifest without verifying its sidecar signature
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:210`
- **Dimension:** Security / cache integrity defense-in-depth
- **Description:** On cold start, `bootstrap()` treats `baseline-rules-manifest.json` as the idempotency marker and, if `cachedManifest` is nil, decodes that cached file directly (`RulesEngineCoordinator.swift:202-218`). After a successful refresh, the same filename is overwritten with the server-fetched manifest and its sidecar signature (`RulesEngineCoordinator.swift:462-463`), so the recovery path is no longer reading an immutable Bundle resource even though the surrounding trust-path comment only justifies skipping signature verification for Bundle.module delivery (`RulesEngineCoordinator.swift:197-199`).
- **Why MEDIUM:** This is not a remote signature bypass: normal refresh still verifies manifest and SRS signatures before writing. It is a local cache integrity gap. If the App Group cache is tampered, recovery can seed `cachedManifest` from unsigned JSON, including an artificially high version that suppresses future signed updates via the monotonic version check at `RulesEngineCoordinator.swift:341-348`.
- **Fix:** When recovering from disk, read `baseline-rules-manifest.json.sig` too and call `signer.verify(message:signature:)` before decoding. If verification fails, refuse recovery and either rehydrate baseline or leave `cachedManifest` nil.

### C5-4-003: Manifest file entries are not checked for duplicate output filenames
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:366`
- **Dimension:** Logic / manifest invariant
- **Description:** Step 6b validates each `files[]` entry's `name` and `sigPath` as safe bare filenames, but it does not require uniqueness (`RulesEngineCoordinator.swift:366-374`). Step 7 then fetches every entry into `verifiedSrsPayloads` (`RulesEngineCoordinator.swift:380-429`), and Step 8 appends them into a single commit batch (`RulesEngineCoordinator.swift:453-464`). If a signed manifest contains the same `name` twice with different categories or bytes, the later batch entry overwrites the earlier final file during `commitTransaction()` (`SRSCacheStore.swift:110-120`).
- **Why MEDIUM:** This requires a bad signed manifest or key/admin compromise, so it is not an attacker bypass under the normal trust model. It does make the client accept an ambiguous manifest where category intent and final on-disk content depend on array order, which is avoidable for a rules distribution trust boundary.
- **Fix:** Add `Set<String>` checks for `entry.name` and `entry.sigPath` in Step 6b. If v1.0 expects exactly the three baseline filenames, also validate the category-to-filename map there.

## Low

### C5-4-004: Runtime log still claims `commitTransaction` wrote files "group-atomically"
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift:130`
- **Dimension:** Operational clarity
- **Description:** Plan 07 corrected the `commitTransaction()` doc-comment to say the implementation is still a per-file rename loop and not a versioned generation-directory swap (`SRSCacheStore.swift:74-89`). The success log still says it wrote files "group-atomically" (`SRSCacheStore.swift:130-132`), which is the exact overstatement the doc fix was meant to remove.
- **Why LOW:** This does not change behavior or weaken signature/hash verification. It can mislead future incident triage or audit work when diagnosing a partial Phase 3 rename failure.
- **Fix:** Change the message to describe the actual contract, for example "committed staged files with per-file atomic renames".

## Notes
- I did not re-report the AUDIT-3 carryovers for true generation-directory atomicity, bootstrap partial first-launch writes, or `RulesFetcher.fetch` buffering before `maxBytes`; they remain visible in current code but are already tracked.
- T-C-D2 is materially closed in `PublicKey.swift`: the comment now matches the non-sequential placeholder bytes at `PublicKey.swift:22-31` and `PublicKey.swift:57-62`.
- T-C-C5H1 is materially closed in the doc-comment: `SRSCacheStore.swift:74-89` now states the per-file rename limitation and v1.1+ generation-directory TODO accurately.
- Trust-chain order in refresh is still sound: manifest signature verify precedes decode (`RulesEngineCoordinator.swift:310-323`), SRS signature and SHA-256 checks precede disk writes (`RulesEngineCoordinator.swift:392-429`), and in-memory state/notification update only after commit succeeds (`RulesEngineCoordinator.swift:452-487`).
