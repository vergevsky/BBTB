# C5 — RulesEngine audit (Codex 5.5)

**Scope:** BBTB/Packages/RulesEngine/Sources/
**Files audited:** 21 (10 Swift + 11 resources)
**Total findings:** 8 (CRITICAL: 4, HIGH: 2, MEDIUM: 2, LOW: 0)

## Findings

### [CRITICAL] C5-001: SSRF guard is pre-DNS only and can be bypassed by DNS/redirects
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift:108`
- **Dimension:** security
- **Description:** `RulesFetcher` checks only `url.host` before `URLSession.data(for:)`. It does not validate resolved IPs, does not re-check redirected URLs, and the reused blocklist misses required `.local` and `100.64.0.0/10` shared-address space.
- **Why it matters:** A public hostname can resolve to `127.0.0.1`, RFC1918, ULA, link-local, or metadata IPs after passing the string check. A public mirror can also redirect to an internal host or non-HTTPS URL without this code reapplying the guard.
- **Suggested fix:** Use a `URLSessionTaskDelegate` to deny redirects unless the target is HTTPS and passes the same guard. Add post-DNS IP validation for all resolved addresses before fetch, and explicitly block `.local`, `100.64.0.0/10`, RFC1918, loopback, link-local, ULA, multicast/reserved IPv4, and IPv6 loopback/link-local.

### [CRITICAL] C5-002: Manifest `sha256` is ignored, allowing signed SRS replay/mix-and-match
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:374`
- **Dimension:** security
- **Description:** The coordinator verifies the detached `.srs.sig`, but never compares `SHA256(srsRes.body)` to `entry.sha256`.
- **Why it matters:** The signature only proves "this SRS was signed sometime." It does not bind the SRS bytes to this manifest version, category, or filename. A malicious/stale mirror can serve an older valid signed SRS plus matching old sig for a new signed manifest, and the client will accept it.
- **Suggested fix:** After fetch and before append/write, compute SHA-256 of each SRS and require exact match with the signed manifest's `files[].sha256`. Reject malformed/non-64-hex hashes.

### [CRITICAL] C5-003: Manifest replay protection is incomplete; no `updated_at` or freshness window
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:341`
- **Dimension:** security
- **Description:** Replay protection is only `newManifest.version > cachedVersion`. `RulesManifest` has no `updated_at` field, and the coordinator has no max-age/freshness check.
- **Why it matters:** A fresh install or reset cache starts from baseline version `0`, so any old signed manifest with version `> 0` can be replayed indefinitely. This accepts stale signed rules even if the server has revoked or replaced them.
- **Suggested fix:** Add signed `updated_at` / `expires_at` to `RulesManifest`, parse with `ISO8601DateFormatter`, reject manifests older than the policy window, reject timestamps too far in the future, and keep the monotonic version check.

### [CRITICAL] C5-004: Manifest-controlled filenames are written without path traversal validation
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:381`
- **Dimension:** security
- **Description:** `entry.name` and `entry.sigPath` come from the signed manifest and are later passed to `SRSCacheStore.write`, which uses `directory.appendingPathComponent(filename)` with no "bare filename" enforcement.
- **Why it matters:** A signed bad manifest, server-side generation bug, or compromised signing pipeline can write outside `Library/Caches/rules` using `../` or absolute/path-like names, poisoning other App Group cache files.
- **Suggested fix:** Validate `name` and `sigPath` immediately after manifest decode: reject absolute paths, empty names, `/`, `\`, `..`, percent-encoded traversal, and unexpected extensions. Prefer mapping categories to fixed local filenames instead of trusting remote filenames for disk writes.

### [HIGH] C5-005: Refresh writes are not transactionally atomic across all rule files
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:400`
- **Dimension:** security
- **Description:** Each SRS and sig is atomically written individually, but the group of files is not committed atomically. The extension reads fixed SRS paths directly, not the manifest, so the comment about "old manifest references old hashes" does not protect the runtime reader.
- **Why it matters:** If the app is killed or I/O fails mid-sequence, the App Group cache can persist a mixed old/new ruleset. The extension can auto-reload between file writes and run with only part of the intended signed rules update.
- **Suggested fix:** Stage a complete verified set in a versioned directory, fsync, then atomically switch a single `current` pointer/manifest or generate extension config paths from the committed version. If fixed filenames must remain, write inactive filenames first and perform a coordinated swap with a single generation marker the extension honors.

### [HIGH] C5-006: Embedded baseline signatures are copied but never verified
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:227`
- **Dimension:** security
- **Description:** `bootstrap()` loads `baseline-rules-manifest.json`, `.sig`, and SRS `.sig` files, then writes them to App Group cache without Ed25519 verification.
- **Why it matters:** The architecture says baseline uses the same signed trust path. As written, a mismatched/corrupt committed baseline artifact can ship and be applied on first run without the RulesEngine detecting it.
- **Suggested fix:** In `bootstrap()`, verify baseline manifest signature before decode/write, then verify each baseline SRS signature and SHA-256 before writing. Treat failure as a hard bootstrap error.

### [MEDIUM] C5-007: Per-file `size_bytes` is not modeled or enforced
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift:102`
- **Dimension:** performance
- **Description:** The bundled manifest includes `size_bytes`, but `RulesManifest.FileEntry` does not decode it. Coordinator only checks signed `total_size_bytes <= 5MB` and fetches each file with a 5MB cap.
- **Why it matters:** A manifest can declare a small total but cause multiple near-5MB SRS downloads. That weakens the DoS guard and makes manifest metadata less authoritative.
- **Suggested fix:** Add `sizeBytes` to `FileEntry`, reject negative/zero/unreasonable values, require each fetched SRS `count == sizeBytes`, and require sum of file sizes equals `total_size_bytes`.

### [MEDIUM] C5-008: Bootstrap idempotency checks only manifest existence, not complete valid cache
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:201`
- **Dimension:** logic
- **Description:** If `baseline-rules-manifest.json` exists, bootstrap skips hydration even if SRS files or signatures are missing/corrupt. Recovery decode also does not verify the cached manifest signature.
- **Why it matters:** A partial previous write or cache corruption can permanently suppress baseline repair, leaving the extension with missing or stale rule files until a successful network refresh.
- **Suggested fix:** On bootstrap, validate the full cache set: manifest + sig, all expected SRS + sig files, signatures, hashes, and categories. If validation fails, rehydrate from verified bundle baseline.

## Notes

Server refresh has the right high-level order for manifest signature verification before manifest decode, and SRS signatures are verified before cache writes. `SRSCacheStore` actor serialization is sound for main-app writer concurrency, but it does not make the multi-file update atomic for the extension process.

I did not modify code and did not run build/tests, per your constraints.

**Verdict:** not TestFlight-ready for the signed rules pipeline until C5-001 through C5-006 are fixed.
