# C5' — RulesEngine re-audit after Plan 03 T-A1/T-A3 (Codex 5.5)

**Scope:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/`
**Files audited:** 10 Swift files
**Baseline:** commit 55523dd
**Total findings:** 6 (CRITICAL: 1, HIGH: 1, MEDIUM: 3, LOW: 1)

## Findings

### [CRITICAL] C5'-001: Empty `sha256` silently disables manifest-to-SRS binding
- **Location:** `RulesEngineCoordinator.swift:404`
- **Description:** Step 7 only verifies SHA-256 when `entry.sha256` non-empty (`if !expectedHex.isEmpty { ... }`). Signed manifest с `sha256: ""` accepts любые validly signed SRS bytes для that file.
- **Why it matters:** Partially reopens C5-002. Detached SRS signature proves SRS signed sometime, но без mandatory manifest hash не bound to this manifest version/category. Stale mirror can replay older valid signed SRS when signed manifest accidentally или maliciously omits hash.
- **Suggested fix:** Reject missing, empty, non-64-length, или non-hex `sha256` BEFORE any SRS fetch/write. Treat as `.signature` или malformed-manifest failure.

### [HIGH] C5'-002: `commitTransaction` still permits mixed-version cache if rename phase fails mid-loop
- **Location:** `SRSCacheStore.swift:97`
- **Description:** Phase 1 writes all staging files, but Phase 2 replaces finals one-by-one. If `replaceItemAt` succeeds for files `0...N` then throws for `N+1`, already-replaced files stay committed while later files remain old/staged.
- **Why it matters:** Not group transaction. Extension reads fixed filenames, so can observe mixed old/new SRS or signatures after I/O error, app kill, storage issue.
- **Suggested fix:** Generation directory/current-pointer design, OR write versioned filenames + single committed generation marker the extension honors. Add rollback/recovery logic.

### [MEDIUM] C5'-003: `replaceItemAt` assumes every final file already exists
- **Location:** `SRSCacheStore.swift:99`
- **Description:** Commit path uses `FileManager.replaceItemAt(final, withItemAt: stagingURLs[i])` — replacement-oriented. If `final` doesn't exist (bootstrap не completed, cache reaped, server switches filenames), refresh fails during commit. Compounds C5'-002 partial state.
- **Suggested fix:** Enforce fixed filename allowlist matching bootstrap, OR make commit semantics explicitly create-or-replace.

### [MEDIUM] C5'-004: Fetched signature not cached under manifest `sigPath`
- **Location:** `RulesEngineCoordinator.swift:377`
- **Description:** Step 7 fetches `entry.sigPath`, но `verifiedSrsPayloads` stores только `basename`; Step 8 writes signature to `"\(payload.basename).sig"` instead of `entry.sigPath`. Manifest's `sig_path` validated и used for network fetch, не preserved on disk.
- **Suggested fix:** Store `sigPath` в `verifiedSrsPayloads` и write sig using that validated filename, OR reject manifests unless `sigPath == "\(name).sig"`.

### [MEDIUM] C5'-005: Bare-filename validation duplicated и inconsistent
- **Location:** `SRSCacheStore.swift:125`
- **Description:** Coordinator `hasPathTraversalRisk` rejects whitespace-only names after trimming; `SRSCacheStore.validateBareFilename` не. Both rely on substring checks instead of positive allowlist. Allows confusing filenames с newlines, bidi controls, zero-width characters.
- **Suggested fix:** Replace both helpers с one shared validator using positive regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`, reject leading `.`, reject `..`, reject Unicode control/format characters.

### [LOW] C5'-006: Redirect guard only applied for `URLSession.shared`
- **Location:** `RulesFetcher.swift:131`
- **Description:** T-A3 production default wraps `URLSession.shared` в ephemeral session с `HTTPSRedirectGuard`, но caller-provided session bypasses guard. Not production bypass (DefaultRulesFetcher protected), но tests/custom integrations could exercise unguarded redirect path.
- **Suggested fix:** Document injected-session contract clearly; add redirect tests; expose guarded-session factory.

## Verification Notes

Step 6b validates all manifest filenames before URL construction и aborts refresh before disk writes — old baseline/cache untouched. SHA comparison case-insensitive для non-empty hashes. Step 8 preserves broad order (SRS, SRS sig, manifest, manifest sig) с `sigPath` caveat. T-A3 redirect revalidation correct on default production path; residual DNS-rebinding risk remains accepted carry-forward.
