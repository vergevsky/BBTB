# C5 — RulesEngine (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 5 (0/1/3/1)

## Critical
No critical findings found in this RulesEngine pass.

## High
### C5'-3-001: `commitTransaction` is still a per-file rename loop, not a generation-directory atomic swap
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift:61`
- **Dimension:** Logic / atomic cache write correctness
- **Description:** Plan 05 says T-B3' closed the mixed-version cache issue with a generation directory + atomic swap, but the checked-in implementation still writes `<filename>.bbtb-staging` files and then renames each final one-by-one (`SRSCacheStore.swift:87`, `SRSCacheStore.swift:94`). The doc-comment explicitly says true group atomicity is deferred (`SRSCacheStore.swift:74`). If Phase 3 succeeds for the first N files and then throws, those N finals remain new while the rest remain old; the function rethrows and only removes remaining staging files (`SRSCacheStore.swift:107`). `RulesEngineCoordinator` then returns failure without updating `cachedManifest` (`RulesEngineCoordinator.swift:464`), but the extension reads fixed SRS paths directly from the App Group cache and does not re-check the signed manifest or SHA-256 before injecting rule sets (`SingBoxConfigLoader.swift:371`).
- **Why HIGH:** A storage error, process kill, or filesystem race during the rename loop can leave `bbtb-baseline-block.srs`, `bbtb-baseline-never.srs`, and `bbtb-baseline-always.srs` at different signed versions. Because PacketTunnelKit points sing-box at those fixed files directly, the tunnel can consume mixed rule policy until the next successful refresh. This is the same failure class T-B3' was supposed to eliminate, but the current code only improves staging cleanup.
- **Suggested fix:** Implement the closure as documented: write a complete generation directory, verify all expected files are present, then atomically swap a single `current` pointer/directory name that the extension resolves. Alternatively, keep fixed filenames but add a manifest generation marker that the extension honors and refuses to reload while a commit is incomplete. Add a fault-injection unit test that forces Phase 3 failure after the first rename and asserts readers cannot observe mixed policy.

## Medium
### C5'-3-002: Manifest file list is not constrained to the three fixed extension filenames/categories
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:366`
- **Dimension:** Logic / manifest validation
- **Description:** Step 6b validates every `entry.name` and `entry.sigPath` as safe bare filenames, but it does not require exactly one entry for each category or require the filenames that PacketTunnelKit actually injects (`bbtb-baseline-block.srs`, `bbtb-baseline-never.srs`, `bbtb-baseline-always.srs`). A signed manifest with a missing category, duplicate category, or alternate safe filename can pass signature/hash checks and be committed successfully, while the extension continues reading the old fixed filenames from `SingBoxConfigLoader.swift:371`.
- **Why MEDIUM:** This is an operational integrity gap rather than an attacker bypass: a malformed signed manifest can report a successful rules update while the tunnel still uses stale rules for one or more categories. For block rules, stale policy is security-relevant.
- **Suggested fix:** Before fetching SRS payloads, validate `files` as a set: exactly three entries, categories `{block, never, always}`, and expected `(category, name, sigPath)` pairs. If future server-side filenames are needed, move filename resolution into a signed generation manifest consumed by both RulesEngine and PacketTunnelKit.

### C5'-3-003: `bootstrap()` can permanently skip recovery after a partial first-launch write
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:202`
- **Dimension:** Logic / first-launch cache recovery
- **Description:** `bootstrap()` treats `baseline-rules-manifest.json` existence as the only "already bootstrapped" signal. The initial hydration writes manifest first, then manifest sig, then each SRS and sig sequentially (`RulesEngineCoordinator.swift:226`). If the app runs out of space or is killed after the manifest write but before all SRS files land, the next launch sees the manifest and skips bootstrap, leaving missing or stale rule-set files indefinitely.
- **Why MEDIUM:** This can strand a fresh install in a "manifest exists, rule files missing" state. It is not a signature bypass, but it can disable or partially disable routing rules until reinstall or a later successful server refresh.
- **Suggested fix:** Bootstrap through `commitTransaction` using the same batch order as refresh, or use a separate `.bootstrap-complete` sentinel written last. On startup, if the sentinel is absent or any expected baseline file is missing, remove the partial cache and retry bootstrap.

### C5'-3-004: `RulesFetcher` enforces `maxBytes` only after buffering the full response
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift:146`
- **Dimension:** Security / resource exhaustion hardening
- **Description:** `RulesFetcher.fetch` calls `URLSession.data(for:)`, then checks `data.count <= maxBytes` after the entire body is already in memory (`RulesFetcher.swift:150`, `RulesFetcher.swift:171`). A compromised mirror or server-side mistake can send a large chunked response and force the app to allocate it before `.payloadTooLarge` is raised.
- **Why MEDIUM:** Rules URLs are fixed HTTPS production mirrors and signatures still gate trust, so this is not a content integrity bypass. It is still a pre-TestFlight hardening gap in a network-facing updater that already has a 5 MB cap by design.
- **Suggested fix:** Mirror the streaming pattern used by the patched subscription/json fetchers: reject excessive `Content-Length` up front, read with `bytes(for:)`, accumulate until `maxBytes + 1`, then cancel and throw `.payloadTooLarge`.

## Low
### C5'-3-005: Production public key comments still describe a placeholder key that is no longer in the file
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift:22`
- **Dimension:** Security / operational clarity
- **Description:** The comments say `publicKeyBytes` is the placeholder sequence `0x00..0x1F` and not for production, but the actual bytes start `0xB5, 0x3F, 0xCF, 0xC3...` (`PublicKey.swift:44`). `RulesSigner.swift` also still says tests are decoupled from the production placeholder key (`RulesSigner.swift:10`).
- **Why LOW:** This does not weaken Ed25519 verification by itself. It does create an operational ambiguity: reviewers cannot tell whether a real production key was installed and the docs are stale, or whether this is still a non-production placeholder.
- **Suggested fix:** Update the comments to identify the key state accurately and add a small test or validation script assertion that the compiled public key is 32 bytes and matches the approved deployment key fingerprint.

## Notes
- I read `AUDIT-2.md` first and did not re-report the closed T-A1' empty/malformed SHA-256 bypass, T-B4' Unicode/path-traversal allowlist, T-B5'-extra staging cleanup, or T-C11' manifest `sigPath` preservation as standalone findings.
- Signature verification order is sound: manifest signature gates decode, SRS signatures gate payloads, and `sha256` is mandatory/exactly 64 hex chars before disk writes.
- The filename allowlist is ASCII-only and rejects Unicode slash variants by construction.
- Actor isolation is clean for `RulesEngineCoordinator` and `SRSCacheStore`; the notification pattern posts via `Task { @MainActor }` and consumers use `queue: nil` plus a MainActor hop.
- I did not find a direct PII leak in RulesEngine logs. Logged mirror URLs are public production endpoints; filenames are manifest-signed operational data.
