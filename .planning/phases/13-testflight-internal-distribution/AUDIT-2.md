# Pre-TestFlight Re-Audit — Phase 13 Plan 04

**Date:** 2026-05-17
**Reviewers:** 7 Opus 4.7 subagents + 9 Codex 5.5 threads = 16 parallel reviewers (mirror Plan 02)
**Baseline:** commit `55523dd` (post-Plan-03 fixes)
**Comparison:** Plan 02 `AUDIT.md` (160 findings, 18 CRITICAL marked closed)

---

## Verdict

**🟡 CONDITIONAL APPROVE — 3 партиальные closures + 1 new CRITICAL surface.**

Plan 03 fix-up cycle закрыл **большинство** Plan 02 CRITICAL/HIGH findings. Однако re-audit выявил:

- **4 partial closures** — fix landed но не полностью закрывает finding (T-A5 IPv6 mask, T-A3 IPv6-mapped SSRF, T-A1 sha256 empty bypass, T-B5 actor reentrancy).
- **1 new CRITICAL** — IPv4-mapped IPv6 SSRF bypass через non-canonical literal forms (Codex C4 single-source).
- **1 new regression** — Fronting batch applies single profile к ВСЕМ pool outbounds (was already present pre-Plan-03 но caller behavior changed in Plan 03 wiring).
- **~12 new HIGH findings** — большинство edge cases в refactored code paths (commitTransaction recovery, HTTPSRedirectGuard bypass на pinned path, etc.)

**Recommendation:** **Fix 4 partial-closures + new CRITICAL before TestFlight upload.** Estimated 4-6 hours.

---

## CRITICAL Closure Verification (Plan 02 → Plan 04 status)

| Plan 02 ID | Cluster | Plan 03 Commit | Re-audit Status |
|---|---|---|---|
| A3-001 / C3-005 | MainScreen observer leak | T-A4 c661634 | ✅ **Confirmed closed** (A3' + C3' both PASS) |
| A4-001 / C4-001 | SubscriptionURLFetcher SSRF | T-A3 0da0608 | ⚠️ **Partial** — string-prefix gaps (C4'-001 CRITICAL) |
| A4-002 / 004 / 005 / C4-003 | Body-size DoS | T-A6 753878e | ✅ **Confirmed closed** для subscription path; ⚠️ JSONEndpointFetcher still post-buffer (C4'-003 HIGH) |
| A4-003 | JSON injection via tag | T-A7 88d0f58 | ✅ **Confirmed closed** (NFC + BiDi strip) |
| A4-007 | Placeholder Ed25519 SubscriptionPinManager | T-A7 | ✅ **Confirmed closed** (#if DEBUG guard) |
| A5-001 | Placeholder Ed25519 RulesEngine | Kept (operational task) | ⏸️ Carry-forward (de-facto safe — server URLs тоже placeholders) |
| A5-002 / C5-004 | RulesEngine path traversal | T-A1 b50c2a6 | ⚠️ **Partial** — blocklist not allowlist; Unicode fullwidth solidus bypasses (A5'-001 HIGH) |
| A5-003 / C5-002 | RulesEngine sha256 not verified | T-A1 | ⚠️ **Partial** — empty sha256 silently skipped (C5'-001 CRITICAL) |
| A5-005 / C5-005 | RulesEngine non-atomic write | T-A1 | ⚠️ **Partial** — Phase 2 rename mid-loop failure still mixed-state (C5'-002 HIGH) |
| C5-001 | RulesFetcher SSRF | T-A3 | ✅ **Confirmed closed** для production path |
| C6-001 | IPv6 mask | T-A5 f1d0a15 | 🛑 **NOT FULLY CLOSED** — compressed IPv6 (`fe80::1`, `2001:db8::8a2e:7334`) NOT matched (C6'-001 HIGH); IPv4-mapped after IPv4 mask still partial |
| C8-001..C8-011 (6× CRITICAL) | Protocols JSON template raw substitution | T-A2 55523dd | ✅ **Confirmed closed** all 6 protocols (C8' PASS, only 1 LOW doc inconsistency) |
| A6-001 / A6-002 | killSwitchEnabled defaults | T-B6 bdba28d | ✅ **Confirmed closed** |
| A6-003 / C7-005 | ImportHandler path | T-B7 e2173d0 | ✅ **Confirmed closed** (с LOW caveat о `/import/<subpath>`) |
| C7-001 / C7-002 / C7-003 | CDN allowlist + isPrivateOrLoopback | T-B10 44be034 | ✅ **Confirmed closed** |
| C7-004 | DeepLink URL log | T-B7 | ✅ **Confirmed closed** |
| C8-002..C8-012 (6× HIGH) | Protocols buildOutbound validation parity | T-B11 8c8b952 | ✅ **Confirmed closed** через PoolBuilder.isValidPoolEntry |
| C3-002 | disconnect ManagerSelector | T-B2 7dc86b1 | ✅ **Confirmed closed** |
| C3-003 | TUIC reparse | T-B1 32c45d0 | ✅ **Confirmed closed** |
| A2-001 / A2-002 / C2-001 / C2-002 / C2-003 | KeychainStore | T-B3 7223253 | ✅ **Confirmed closed** (с MEDIUM C2'-001 locked-device accessibility) |
| A1-001 | STUN tag schema | T-B9 78e216f | ✅ **Confirmed closed** |
| C1-001 | commandServer leak | T-B9 | ✅ **Confirmed closed** |
| A3-002 | connectedDate dedupe | T-B8 41349c2 | ✅ **Confirmed closed** (с MEDIUM C3'-002 stale prev-session) |
| A3-004 | killSwitchObserver queue | T-B4 cc88712 | ✅ **Confirmed closed** |
| **A3-005** | **ConfigImporter modelContainer** | **T-B5 ce54f72** | ⚠️ **PARTIAL** — ProvisionSerializer reentrant after `await`; не full mutex (A3'-001 + C3'-001 HIGH) |
| C3-001 | handleForegroundReentry no-op | T-B8 | ✅ **Confirmed closed** |
| A4-006 | PoolBuilder UserDefaults read | (not directly addressed) | ⏸️ Still present, Tier C |

**Summary:** 18/18 CRITICAL findings из Plan 02 attempted, но 4 actually NOT FULLY CLOSED:
- **C5'-001 (NEW CRITICAL)** — empty sha256 в manifest silently disables binding
- **C4'-001 (NEW CRITICAL)** — non-canonical IPv4-mapped IPv6 SSRF bypass
- **C6-001 / T-A5 partial** — compressed IPv6 mask incomplete (HIGH privacy)
- **A3-005 / T-B5 partial** — actor reentrancy не full mutex (HIGH concurrency)

---

## New CRITICAL Findings (post-Plan-03)

### C5'-001: Empty `sha256` в манифесте silently disables manifest-to-SRS binding
- **Reviewer:** Codex C5'
- **Location:** `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:404`
- **Description:** Step 7 only verifies SHA-256 when `entry.sha256` non-empty (`if !expectedHex.isEmpty`). Подписанный manifest с `sha256: ""` accepts любые validly signed SRS bytes для that file. Partially reopens C5-002.
- **Why CRITICAL:** Detached SRS signature proves SRS signed sometime, но без mandatory manifest hash не bound к этой manifest version/category. Stale mirror can replay older valid signed SRS when signed manifest accidentally OR maliciously omits hash.
- **Suggested fix:** Reject missing, empty, non-64-length, или non-hex `sha256` BEFORE any SRS fetch/write. Treat as `.signature` or malformed-manifest failure.

### C4'-001: `isBlockedHost` still misses non-canonical IPv4-mapped IPv6 literals
- **Reviewer:** Codex C4' (single-source — verify before fix)
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:330`
- **Description:** T-A3 blocks только compressed dotted-quad form `::ffff:a.b.c.d`. Does not parse IP literals canonically. Equivalent blocked destinations can pass as IPv6 literals: expanded mapped forms `0:0:0:0:0:ffff:127.0.0.1` or hex mapped forms `::ffff:7f00:1`. Recursive check (lines 386-389) only works when suffix is dotted IPv4 string.
- **Why CRITICAL:** Direct SSRF bypass к loopback/private targets using IP literal (не DNS rebinding). Redirect guard reuses same predicate → inherits bypass.
- **Suggested fix:** Replace string-prefix IP detection с numeric parsing. Use `inet_pton`/`IPv6Address`-style parsing, normalize IPv4-mapped IPv6 к IPv4 bytes, check CIDR ranges numerically для both initial URL и redirect targets.

---

## New HIGH Findings (regressions + new)

### A3'-001 / C3'-001: ProvisionSerializer actor reentrant — не full async mutex
- **Location:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:67`
- **Description:** Swift actors release isolation at `await` suspension points. `_provisionTunnelProfileInternal` awaits inside TaskGroup (Keychain reads) и at `tunnelProvisioner.provisionTunnelProfile(...)`. Second `provisionTunnelProfile(for:)` can enter while first suspended → overlap on downstream NE provider config build/save/load. Original A3-005 race не fully mitigated.
- **Why HIGH:** T-B5 fix marked closure но does не provide claimed mutual exclusion.
- **Suggested fix:** Use real async mutex/task-chain pattern (e.g., `pending: [CheckedContinuation]` queue в actor), OR explicitly narrow serializer к pre-await SwiftData section + document downstream provisioning may overlap.

### A5'-001: Path traversal blocklist не allowlist — Unicode fullwidth solidus bypasses
- **Location:** `RulesEngineCoordinator.swift:570+ hasPathTraversalRisk`
- **Description:** Substring-blocklist approach misses Unicode fullwidth solidus `／` (U+FF0F), fraction slash `⁄` (U+2044), NFKC/NFKD normalization holes. Plan 02 suggested allowlist `^[A-Za-z0-9._-]+$` — implementation chose weaker blocklist.
- **Suggested fix:** Replace blocklist с positive regex `^[A-Za-z0-9][A-Za-z0-9._-]*$`. Reject leading `.`, `..`, Unicode control/format characters.

### A5'-002: `commitTransaction` does NOT cleanup `.bbtb-staging` files on failure
- **Location:** `SRSCacheStore.swift:97`
- **Description:** Phase 2 rename failure leaves orphan `.bbtb-staging` files. No init-time sweep. Disk leak + future confusion if filename set changes between batches.
- **Suggested fix:** Add cleanup loop в `commitTransaction` exception path + init-time sweep of `.bbtb-staging` files.

### C4'-002: PinnedSubscriptionURLFetcher path bypasses HTTPSRedirectGuard
- **Location:** `SubscriptionURLFetcher.swift:63`
- **Description:** `PinnedSubscriptionURLFetcher.fetch` creates custom session с `PinnedSessionDelegate`, calls `SubscriptionURLFetcher.fetch(url:session:)`. Because session не URLSession.shared, guarded-session branch skipped. Pinned fetches get initial isBlockedHost но не redirect revalidation.
- **Why HIGH:** When pinning wired later, user-controlled subscription URL can redirect к blocked host без guard.
- **Suggested fix:** Make `PinnedSessionDelegate` also implement `willPerformHTTPRedirection` using same guard.

### C4'-003: JSONEndpointFetcher cap post-buffer — still DoS-able
- **Location:** `JSONEndpointFetcher.swift:81`
- **Description:** Still uses `activeSession.data(for:)`, checks `data.count` AFTER full buffer. Hostile endpoint can OOM-kill via large chunked body before `.bodyTooLarge` evaluated.
- **Suggested fix:** Use same streaming helper as `SubscriptionURLFetcher.bytes(for:)` с Content-Length fast-path.

### C5'-002: commitTransaction Phase 2 mid-loop failure → mixed-version cache
- **Location:** `SRSCacheStore.swift:97`
- **Description:** Phase 2 replaces finals one-by-one. If `replaceItemAt` succeeds for files `0...N` and then throws for `N+1`, already-replaced files stay committed while later files remain old/staged.
- **Why HIGH:** Не group transaction. Extension reads fixed filenames → can observe mixed old/new SRS or signatures.
- **Suggested fix:** Generation directory + atomic swap of single `current` pointer, OR versioned filenames + single committed generation marker the extension honors.

### C6'-001 / Codex C6': IPv6 mask regex misses compressed forms
- **Location:** `DiagnosticsExporter.swift:148`
- **Description:** The prefix side of compressed regex `(?:[0-9a-fA-F]{1,4}:){0,7}::` consumes colon immediately before `::`. Addresses `fe80::1`, `2001:db8::8a2e:7334`, `::1` (works) не all matched. IPv4-mapped after `maskIPv4` partial leak `::ffff:192.0.2.xxx`.
- **Why HIGH (privacy):** Original T-A5 closure claim incomplete для dominant IPv6 notation. **T-A5 actually NOT FULLY CLOSED.**
- **Suggested fix:** Use numeric IP parsing/normalization (IPv6Address), OR replace P2 с tested compressed-IPv6 pattern that handles prefix groups, suffix groups, zone IDs, dotted-quad mapped.

### C7'-001: Fronting JSON batch apply rewrites ALL compatible outbounds с одним FrontingProfile
- **Location:** `FrontingConfigApplier.swift:47`
- **Description:** Live caller picks profile from selected server, applies к entire generated pool. Unrelated VLESS/Trojan servers в multi-outbound pool rewritten к selected server's CDN.
- **Why HIGH:** Routing semantics broken; traffic для other pool entries sent через wrong admin-controlled fronting.
- **Suggested fix:** Make fronting apply tag-scoped или selected-outbound-scoped.

### Plan 02 carry-forward A4'-001: DNS-rebinding still bypasses post-T-A3 SSRF
- **Location:** `SubscriptionURLFetcher.isBlockedHost` (string match only)
- **Description:** Comment acknowledges as residual risk, NOT documented в wiki/security-gaps.md.
- **Why HIGH (CLAUDE.md decision-log rule violation):** Should be wiki-documented.
- **Suggested fix:** Write wiki entry + optional URLSessionTaskMetrics.remoteAddress post-check.

---

## New MEDIUM Findings (selected highlights)

- **C2'-001** — VPN secrets use `kSecAttrAccessibleWhenUnlocked` instead of `AfterFirstUnlockThisDeviceOnly`. Locked-device tunnel restart can fail.
- **C2'-003** — false-pinned Keychain lookup doesn't match prior synchronizable items (cleanup gap).
- **C3'-002** — `min(connectedDate, state.connectionStart)` can reuse stale prev-session date.
- **A6'-001** — `T-A2` left dead `SingBoxConfigTemplate.*.json` resources в 5 of 6 protocols (`.process(...)` Package.swift declarations remain).
- **A6'-006** — `testFlightInviteURL = "PLACEHOLDER"` 404s если MinAppVersionBanner fires.
- **C4'-004** — `HTTPSRedirectGuard: NSObject, Sendable` Swift 6 strict concurrency risk (should be `@unchecked Sendable`).
- **C5'-003/004/005** — commitTransaction edge cases (replaceItemAt assumes final exists; sigPath not used; validation duplicated).
- **C6'-002** — ServerListViewModel 100ms debounce skips mandatory post-mutation reloads.
- **C1'-001** — PacketTunnelKit validate(json:) doesn't verify route.rules[].outbound references.

---

## New LOW Findings (selected)

- **A1'-006** — `validate` не enforces path-traversal на user-supplied `route.rule_set[].path`.
- **A3'-002** — `ProvisionSerializer.run` declared `rethrows` но closure is `throws` — `rethrows` is dead code.
- **C7'-002** — TransportRegistry supportedProtocols omits "tuic".
- **C7'-003** — FrontingEngine.isPrivateOrLoopback duplicates SubscriptionURLFetcher.isBlockedHost inline (drift risk).
- **C8'-001** — TUIC ConfigBuilder comment says "always false" but code never emits insecure.
- **C9'-001** — Duplicate `settings.security.section` key в Localizable.xcstrings.

---

## Distribution per Reviewer

| Reviewer | Scope | Closure Verdict | New C/H/M/L |
|---|---|---|---|
| A1' Opus | PacketTunnelKit | 2/2 PASS | 0/0/1/7 |
| C1' Codex | PacketTunnelKit | 2/2 PASS | 0/0/1/0 |
| A2' Opus | VPNCore | 5/5 PASS | 0/0/4/4 |
| C2' Codex | VPNCore | 5/5 PASS (с caveats) | 0/0/2/1 |
| A3' Opus | MainScreenFeature | 8/8 PASS structurally; A3-005 partial | 0/2/4/5 |
| C3' Codex | MainScreenFeature | 7/8 PASS + 1 PARTIAL (T-B5) | 0/1/1/1 |
| A4' Opus | ConfigParser | 5/5 PASS (с DNS-rebinding wiki gap) | 0/1/4/7 |
| C4' Codex | ConfigParser | 4/5 PASS + 1 PARTIAL (T-A3 IPv6) | **1**/2/1/0 |
| A5' Opus | RulesEngine | 4/4 PASS structurally; gaps | 0/2/5/4 |
| C5' Codex | RulesEngine | 3/4 PASS + 1 PARTIAL (T-A1 sha256) | **1**/1/3/1 |
| A6' Opus | MEDIUM tier | 5/5 PASS | 0/0/2/11 |
| C6' Codex | Settings+ServerList | 1/2 PASS + 1 FAIL (T-A5 IPv6) | 0/1/1/0 |
| C7' Codex | Fronting+DeepLinks+KS+Transport | 2/2 PASS | 0/1/0/3 |
| C8' Codex | Protocols | 6/6 PASS | 0/0/0/1 |
| A7' Opus | LOW tier | 1/1 PASS | 0/0/0/5 |
| C9' Codex | LOW tier | N/A (no Plan 03 changes) | 0/0/0/1 |
| **TOTAL** | **15 packages** | **44/50 PASS, 4 PARTIAL** | **2 CRITICAL, 11 HIGH, ~30 MEDIUM, ~50 LOW** |

---

## Recommended Action Before TestFlight Upload

### Tier A++ (block TestFlight — 4 issues, ~4-6h)

| Task | Closes | Effort |
|---|---|---|
| **T-A1' Fix sha256 empty bypass** | C5'-001 CRITICAL | 30min |
| **T-A3' Fix IPv6-mapped SSRF (numeric IP parser)** | C4'-001 CRITICAL | 2-3h |
| **T-A5' Fix IPv6 mask compressed forms** | C6'-001 HIGH (closes T-A5 properly) | 1-2h |
| **T-B5' Fix ProvisionSerializer reentrancy** | A3'-001 / C3'-001 HIGH (closes T-B5 properly) | 1-2h |

### Tier B+ (recommended pre-TestFlight)

- C4'-002 PinnedSubscriptionURLFetcher add redirect guard
- C4'-003 JSONEndpointFetcher streaming + cap
- C5'-002 commitTransaction generation directory atomic swap
- C7'-001 Fronting tag-scoped apply
- A5'-001 Path traversal allowlist (replace blocklist)
- A5'-002 commitTransaction staging cleanup

### Tier C/D backlog
~30 MEDIUM + ~50 LOW findings tracked for post-TestFlight iteration.

---

## Summary

Plan 03 fix-up cycle made **substantial** progress (38+ findings closed including 14/18 CRITICAL clusters fully addressed). Однако 4 partial closures + 1 new CRITICAL surface mean **not safe to ship as-is**. **~4-6 hours additional Tier A++ work** required before TestFlight upload.

After Tier A++ closure → re-audit gate (smaller CRITICAL-only subset, ~30 min) → if clean → ship.

**No regressions detected from Plan 03 refactoring** beyond known partial-closure gaps (positive — refactoring discipline held).
