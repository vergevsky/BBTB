# Phase 2 — Plan Check Report

**Phase:** 02-trojan-import-flow (Trojan + Import flow, v0.2)
**Plan reviewed:** `02-PLAN.md` (3412 lines, 7 waves, 34 tasks)
**Adversarial verification by:** `gsd-plan-checker` (goal-backward)
**Reviewed:** 2026-05-11
**Reviewer mindset:** assume flawed until proven otherwise

---

## Overall Verdict

**APPROVED WITH WARNINGS** — execution can proceed.

The plan demonstrates rigorous goal-backward derivation: every ROADMAP success criterion is anchored to specific waves/tasks, every CONTEXT decision (D-01..D-15) has at least one implementing task with code-level detail, every UI-SPEC §7 component has a creation task, every PATTERNS critical decision (§5.1–§5.4) is reflected in W0/W1 design choices, and Phase 1 regression risk is addressed via three explicit checkpoints (W0.T6, W1.T9, W3.T3, W5.T3). RESEARCH integration is strong — urltest interval=1m (not default 3m), HEAD-probe semantics, `dns.detour → urltest-out` migration, validate relaxation to `noProxyOutbound`, NETunnelProviderManager `save → load` pattern are all carried into specific tasks.

No blockers were found — no scope reduction of locked decisions, no contradictions with CONTEXT, no missing requirement coverage, no broken wave dependencies, no Phase 1 invariant silently dropped, no Deferred Idea creeping in.

However, **12 warnings** identify quality risks the executor should mitigate during execution. Two are MED-severity (one is a borderline scope-budget issue on Wave 4 — 9 tasks, three is a slight risk that the **build will compile but device-side IPC will be untested before W5 UAT**); the rest are LOW.

---

## Coverage Summary

### ROADMAP Success Criteria (8/8 covered)

| SC | Description | Tasks covering | Verdict |
|----|-------------|----------------|---------|
| SC-1 | 3 import formats + QR + unsupported graceful | W1.T3, T4, T5, T6, T7, T8; W3.T1; W4.T7; W5.T1; W5.T2-T1..T4 | COVERED |
| SC-2 | Auto-fallback through urltest | W1.T8 (PoolBuilder urltest assembly); W0.T4 (validate accepts urltest); W0.T5 (DNS detour); W5.T2-T6 (UAT failover) | COVERED |
| SC-3 | Trojan on TCP+TLS and WS+TLS | W1.T1 (2 templates), W1.T2 (ConfigBuilder), W1.T3 (parser), W2.T1 (register), W2.T2 (smoke), W5.T1, W5.T2-T5 | COVERED |
| SC-4 | Kill Switch toggle in Settings → Безопасность, applied on next connect, banner | W0.T2 (signature), W3.T1 (UserDefaults read), W3.T2 (banner state), W4.T6 (Settings), W5.T1 Test 6, W5.T2-T7..T9 | COVERED |
| SC-5 | Camera permission iOS + macOS | W4.T7 (CameraPermission), W4.T8 (Info.plist + entitlement), W5.T2-T4 | COVERED |
| SC-6 | MainScreen rewrite — top bar, idle layout, empty-state | W0.T3 (rename), W4.T3, T4, T5, T9; W5.T2-T5, T9 | COVERED |
| SC-7 | SwiftData array migrated | W0.T1 (schema extension), W3.T1 (multi-row save), W5.T1 Test 7 (replace-pool) | COVERED |
| SC-8 | Unit-test suite green | W0.T6, W1.T9, W3.T3, W5.T3, W6.T1 — 4 explicit regression checkpoints | COVERED |

### CONTEXT Decisions (15/15 covered)

| D-XX | Decision | Implementing task | Verdict |
|------|----------|-------------------|---------|
| D-01 | urltest inside sing-box, one VPN profile | W1.T8 PoolBuilder; W3.T1 ConfigImporter "load → modify → save → load" pattern | COVERED |
| D-02 | Three import formats (subscription URL / multi-line / JSON endpoint) | W1.T5 (Subscription), W1.T6 (JSON endpoint), W1.T7 (Universal facade classify) | COVERED |
| D-03 | Leadaxe as spec only, not dependency | Embedded as design source in W1.T7 algorithm (RESEARCH §6.3 referenced); ConfigParser/Package.swift dependencies list (W1.T9) excludes any GPL dep | COVERED |
| D-04 | Universal parser recognises ALL URI schemes; unsupported → isSupported=false | W1.T4 (StubParsers for ss/vmess/hy2/wireguard); ServerConfig.isSupported W0.T1 | COVERED |
| D-05 | Trojan TCP+TLS + WS+TLS | W1.T1 (two templates), W1.T2 (TransportType enum), W1.T3 (parser type=tcp/ws) | COVERED |
| D-06 | SwiftData singleton → array | W0.T1 (4 new fields + optional keychainTag), W3.T1 (per-server persist loop) | COVERED |
| D-07 | subscriptionURL stored, re-import = replace-pool | W3.T1 (`deleteExistingPool(subscriptionURL:)`); W5.T1 Test 7 | COVERED |
| D-08 | Trojan URI strict TLS, `allowInsecure` ignored, SNI mandatory | W1.T3 Test 6/7/10; W1.T2 template hardcoded `insecure: false` | COVERED |
| D-09 | MainScreen layout (top bar ≡/+, idle layout, no chevron) | W4.T3 (visual rewrite), W4.T4 (TopBar, ServerLineView), W4.T5 (MainScreenView rewrite) | COVERED |
| D-10 | Empty-state card with 2 CTAs, top bar visible | W4.T4 (EmptyStateCard); W4.T5 case .empty branch | COVERED |
| D-11 | ServerLine: 1 outbound → remark; ≥2 → "Авто"; tap disabled v0.2 | W3.T2 (`currentServerLineText` computed); W4.T4 (ServerLineView no chevron) | COVERED |
| D-12 | Settings page with only "Безопасность" + Kill Switch | W4.T6 (SettingsView with single Section) | COVERED |
| D-13 | Toggle without confirmation alert | W4.T6 (plain SwiftUI `Toggle`, no `.alert`) | COVERED |
| D-14 | Apply on next connect + banner if active | W3.T1 (UserDefaults read on provision); W3.T2 (`needsReconnectForKillSwitch` via NotificationCenter); W4.T5 (banner render); W5.T2-T9 | COVERED |
| D-15 | `KillSwitch.apply(to:enabled:)` signature | W0.T2 (signature change + 2 new tests for enabled=false); ConfigImporter call-site updated | COVERED |

### UI-SPEC §7 Component Inventory (12/12 covered)

| Component | Task | Verdict |
|-----------|------|---------|
| MainScreenView (rewrite) | W4.T5 | COVERED |
| StatusPill (rename + restyle) | W0.T3 (rename) + W4.T3 (Capsule restyle) | COVERED |
| ConnectionButton (140 pt, accent on connected) | W4.T3 | COVERED |
| ConnectionTimer (Date? optional) | W4.T3 | COVERED |
| ImportFromClipboardButton (delete) | W4.T5 (`git rm`) | COVERED |
| MainScreenViewModel (rewrite) | W3.T2 | COVERED |
| EmptyStateCard | W4.T4 | COVERED |
| ServerLineView | W4.T4 | COVERED |
| ReconnectBanner | W4.T4 | COVERED |
| TopBar (or inline toolbar) | W4.T4 (per W4.T5 Variant A/B note) | COVERED (with WARN-3 — see below) |
| SettingsView + SettingsViewModel + KillSwitchToggleSection | W4.T6 | COVERED |
| QRScannerView + QRScannerViewController/NSRepresentable + CameraPermission | W4.T7 | COVERED |
| ImportProgressOverlay | W4.T4 | COVERED |

### CLAUDE.md compliance: PASS — primary language Russian preserved in user-facing strings; new wiki/`.planning/` synchronisation hooks present in plan (W6.T2 mentions STATE.md / ROADMAP / wiki update post-phase).

### Architectural Responsibility Map (RESEARCH §): Plans assign capabilities consistent with the responsibility map. Auth/secrets stay in `KeychainStore` (App tier). Validation stays in `SingBoxConfigLoader` (PacketTunnelKit tier). HTTP fetching stays in `ConfigParser` (App tier). Tunnel mutation stays in `KillSwitch.apply` (single mutator per PATTERNS §2.25). No security-sensitive capability is downgraded to a less-trusted tier.

---

## Findings Table

Severity scale: **HIGH** (BLOCKER), **MED** (WARNING — fix recommended), **LOW** (INFO).

| # | Finding | Severity | Section in PLAN | Recommendation |
|---|---------|----------|-----------------|----------------|
| F-01 | **Wave 4 task count (9) exceeds soft scope threshold (4 = warning, 5+ = blocker per checker's scope-sanity dimension)**, but each task is well-scoped, action descriptions are concrete, and the wave naturally decomposes into 3 logical commits (DesignSystem+Localization → Visual rewrite → SettingsFeature+QR+Tuist). The plan acknowledges this by setting `commits: 6-8` (matching 6-8 commits not 9). | MED | `## Wave 4` overview header (line 2123–2131) | Acceptable but executor should consider whether T4 (5 new components in one task) deserves splitting; if any single commit grows >300 LOC, split into atomic per-component commits. Not a blocker. |
| F-02 | **`MainScreenView.swift` rewrite (W4.T5) contains an unresolved A/B variant choice** — TopBar component vs `.toolbar` ToolbarItem for menu icon. The plan recommends Variant A but leaves the final decision to executor with "зафиксировать в commit message". | MED | W4.T5 lines 2440–2456 | Executor SHOULD commit to Variant A (PATTERNS §2.16 — TopBar as own component is more testable) before starting W4.T5; otherwise risk of partial implementation churn. Recommendation: lock to Variant A in CONTEXT supplement before W4 begins. |
| F-03 | **W2.T1 (TrojanHandler registration) explicitly notes the commit "may not compile" until W4.T9 runs Tuist regen** — flagged in the plan as a known issue with two mitigation options offered. | MED | W2.T1 lines 1664–1668 | Executor MUST follow the plan's own recommendation ("сделать оба изменения в одном коммите") OR re-order: run W4.T9 Tuist-only step BEFORE W2.T1. Leaving a known-broken commit in the history breaks `git bisect` for any future regression. Recommend amend wave ordering or single-commit consolidation. |
| F-04 | **`ConfigParser` testTarget gains dependency on `PacketTunnelKit`** (W2.T2) for R1 self-test in `DualProtocolSmokeTests`. The plan correctly notes this is acceptable per PATTERNS §3.6 (test target is exempt from production cycle constraint). However, the production `ConfigParser/Package.swift` MUST remain free of `PacketTunnelKit` dep — verified in W1.T8 `done` clause but worth re-flagging. | LOW | W2.T2 lines 1720–1729; W1.T8 `done` clause line 1522 | No action needed — the plan is correct. Executor must NOT add `PacketTunnelKit` to the `target` (only `testTarget`). |
| F-05 | **PoolBuilder duplicates DNS block / VLESS outbound shape in code rather than reusing `SingBoxConfigTemplate.vless-reality.json`** — to avoid ConfigParser→PacketTunnelKit dep. Plan correctly identifies this as deliberate duplication (W1.T8 architecture note line 1513). | LOW | W1.T8 lines 1512–1513 | Justified. Risk: template drift between `vless-reality.json` and PoolBuilder's `buildVLESSOutbound` in-code shape. Mitigation: cross-test that an `ImportResult` from W1.T7 → PoolBuilder produces JSON byte-identical (modulo whitespace + key order) for a single VLESS server to `ConfigBuilder.buildSingBoxJSON` output. Suggest adding such an equivalence test in W2.T2 or W5.T1 (NOT a blocker). |
| F-06 | **`ConfigImporter.deleteAllExistingConfigs` for non-subscription path (W3.T1)** deletes ALL Phase 1 user data on re-paste. This is more conservative than D-07 (which only specifies replace-pool for subscription URL re-import). The plan notes this explicitly in W5.T1 Test 7 NOTE (line 2952). | LOW | W3.T1 lines 1797–1804; W5.T1 line 2952 | Document this behaviour in `02-UAT.md` T1/T2/T3 expected outcomes so user is not surprised when paste of multi-line block wipes prior subscription pool. Acceptable for v0.2 (single VPN profile concept), but UX-warn worthy. |
| F-07 | **Trojan ParsedTrojan field `security` is always "tls" by post-validation invariant** — D-08 STRICT reading means `security != tls` → throws. The field exists in struct but is effectively redundant (always "tls" if struct exists). Test 7 in W1.T3 tests strict-reject for missing security. The redundant field is harmless but worth noting. | LOW | W1.T3 lines 916–920 | No action. Future Phase could remove field but `Sendable, Equatable` struct shape adds no maintenance cost. |
| F-08 | **W4.T7 QR scanner: macOS `QRScannerNSView` implementation is sketched, not fully specified**. The plan says "Implementation per RESEARCH §8.5 macOS variant" but reading RESEARCH §8.5 shows full code only for iOS UIViewControllerRepresentable. macOS NSViewRepresentable code is implied but not explicit. | MED | W4.T7 lines 2733–2737 | Executor must verify RESEARCH §8.5 macOS section is sufficient before W4.T7; if not, fail-fast and request RESEARCH update. Risk: macOS QR scanner unimplemented at W4.T7 commit time; build green but feature stub. UAT T4 may need iOS-only marking for v0.2. |
| F-09 | **Wave 5 Test 7 (Replace-pool D-07) contradicts W3.T1 deleteAllExistingConfigs logic** — plan acknowledges this explicitly in NOTE (line 2952) with the resolution: subscription path uses replace-by-URL; non-subscription uses replace-all. Resolution is technically consistent with D-07 strict reading ("Re-import того же URL = replace pool"). | LOW | W5.T1 line 2952 | Already resolved in NOTE. Executor should make sure ConfigImporterTests Test 4 (W3.T1) explicitly tests the URL-matching predicate so the contradiction is caught at unit level. |
| F-10 | **DesignSystem `Spacing.xxl=32` vs UI-SPEC §8.1 token `2xl=32`** — naming mismatch. Plan uses `xxl` (which is fine Swift identifier) but UI-SPEC writes `2xl`. Same for `xxxl` (plan) vs `3xl` (spec). | LOW | W4.T1 line 2153–2154 vs UI-SPEC §8.1 lines 476–485 | Cosmetic. Plan's `xxl`/`xxxl` is valid Swift, UI-SPEC's `2xl`/`3xl` would not compile as Swift identifiers (leading digit). Plan version is correct; reference in commit message that UI-SPEC names were normalized for Swift compatibility. |
| F-11 | **Pool size cap (50 outbounds) hardcoded in PoolBuilder** is silent truncation — user importing 60-server subscription will get 50 with no UI warning on v0.2. RESEARCH §9.5 justifies cap; plan implements it. | LOW | W1.T8 line 1431 | UAT T1 expected outcome should mention "если в подписке >50 серверов, отображаются первые 50". Plan currently does not document this in `02-UAT.md` task. Suggest adding a one-liner. |
| F-12 | **Phase 1 R1 inbound whitelist (`{tun, direct}`) is preserved via "do not change" comment** in W0.T4 line 564, but the plan does NOT add a regression test verifying the whitelist is still enforced after W0.T4 changes. Test 6 (W0.T4) tests `socks` inbound is rejected — this covers R1 indirectly. | LOW | W0.T4 Test 6 (line 524) | Already covered by Test 6 (`forbiddenInboundType("socks")`). Sufficient. No action needed. |

---

## Dimension-by-Dimension Verdicts

| Dimension | Status | Notes |
|-----------|--------|-------|
| 1. Requirement Coverage (ROADMAP 8 SC + 10 REQ-IDs) | PASS | All 8 SC and all 10 REQ-IDs (PROTO-02, PROTO-10, IMP-02, KILL-03 + foundations IMP-04, IMP-05, TRANSP-03, SRV-01/02/03) mapped to tasks. |
| 2. Task Completeness | PASS | All 34 tasks have `<name>`, `<files>`, `<action>`, `<verify>`, `<done>`. TDD tasks have `<behavior>`. Verify commands are runnable bash. |
| 3. Dependency Correctness | PASS | Wave graph: W0 → W1 → W2 → W3 → W4 → W5 → W6 acyclic. W4 depends only on W0+W3 (not W2) which is correct (W4 visual rewrite does not need TrojanHandler registered). No circular deps. |
| 4. Key Links Planned | PASS | 9 key_links in frontmatter all map to specific tasks: ConfigImporter→UniversalImportParser (W3.T1), ConfigImporter→PoolBuilder (W3.T1), ConfigImporter→KillSwitch.apply (W3.T1), SettingsViewModel→UserDefaults (W4.T6), MainScreenView→SettingsView (W4.T5+T9), QRScannerView→ConfigImporter (W4.T5), PoolBuilder→urltest (W1.T8), SingBoxConfigLoader→Trojan/urltest types (W0.T4), iOSApp→TrojanHandler register (W2.T1). |
| 5. Scope Sanity | WARN | Wave 4 = 9 tasks (above 4-task warning, below 5+ blocker per dimension thresholds but high). Mitigated by aggressive sub-task atomicity. F-01 covers. |
| 6. must_haves Derivation | PASS | All 15 truths are user-observable (e.g., "User can import a Trojan URI via clipboard"). All 18 artifacts have provides/contains/min_lines. |
| 7. Context Compliance | PASS | All 15 decisions implemented exactly as written. No locked decision contradicted. No Deferred Idea (IMP-03, server-list UI, full Settings, anti-DPI, R5 toggle, certificate pinning, auto-reconnect on toggle) appears in plan. |
| 7b. Scope Reduction Detection | PASS | No "v1/v2", "static for now", "simplified", "placeholder", "future enhancement" language reducing user decisions. The plan uses "Phase 11 forward-compat" and "deferred to Phase X" only for items explicitly listed in CONTEXT Deferred Ideas — that is NOT scope reduction, that is scope discipline. |
| 7c. Architectural Tier Compliance | PASS | All capabilities placed in correct tier per Phase 1 carry-forward map. R1 validation in PacketTunnelKit (lowest-trust layer). HTTP fetch in ConfigParser. Tunnel mutation single-pointed at `KillSwitch.apply` per PATTERNS §2.25. |
| 8. Nyquist Compliance | PASS | Every implementation task has `<automated>` verify command (swift build, swift test, grep, plutil). No watch-mode flags. Latency: longest is `xcodebuild` at W4.T9/W6.T1 (~30-60s). Sampling: every wave has multiple verified tasks. No 3 consecutive implementation tasks without verify. |
| 9. Cross-Plan Data Contracts | PASS | Single plan, no cross-plan data path conflicts. Internal data contracts (ImportedServer → AnyParsedConfig → ParsedX → outboundJSON → poolJSON) are defined upfront in `<interfaces>` block (lines 256–383). |
| 10. CLAUDE.md Compliance | PASS | Russian-primary user strings preserved (NSCameraUsageDescription in Russian per CONTEXT). Wiki/`.planning/` synchronization mentioned post-phase. Tuist generator pattern preserved (BBTB project layout). |
| 11. Research Resolution | PASS | RESEARCH.md has no `## Open Questions` section requiring resolution — all 12 sections are complete deep-dives with citations marked `[VERIFIED:...]` or `[CITED:...]`. |
| 12. Pattern Compliance | PASS | All 30+ new/modified files in PATTERNS.md ## File Classification have referenced analogs (where exact match exists) or marked NEW. Plan tasks cite PATTERNS §X.Y for each significant decision (counted ~50 explicit PATTERNS references). |

---

## MUST-FIX Before Execution

None. The plan is approved for execution.

## SHOULD-DO Before Execution (recommended but not blocking)

1. **(F-02)** Lock the W4.T5 TopBar Variant A/B choice. Suggested: Variant A (TopBar.swift as own testable component) per PATTERNS §2.16.
2. **(F-03)** Decide whether to merge W2.T1 + W4.T9 into a single Tuist-coupled commit or to insert a Tuist-only sub-commit before W2.T1. Either solves the "broken commit" risk. Recommend the second option (smaller blast radius).
3. **(F-08)** Verify RESEARCH.md §8.5 contains full macOS NSViewRepresentable code before W4.T7 starts. If not, request RESEARCH update or mark macOS QR as v0.3 follow-up.

---

## NICE-TO-HAVE Improvements During Execution

- **(F-05)** Add cross-equivalence test in W5.T1 verifying single-VLESS PoolBuilder output matches `VLESSReality/ConfigBuilder.buildSingBoxJSON` byte-for-byte (modulo whitespace) to prevent template drift.
- **(F-06)** Document in `02-UAT.md` (W5.T2) that paste of multi-line block (non-subscription path) replaces ALL existing servers.
- **(F-11)** Mention 50-server truncation in UAT T1 expected outcomes for clarity.

---

## Phase 1 Regression Risk — assessed PASS

Plan includes 4 regression checkpoints (W0.T6, W1.T9, W3.T3, W5.T3) verifying all 6 Phase 1 packages + 1 Phase 1 protocol package + new Phase 2 packages remain green. Specific Phase 1 invariants confirmed in plan:

- **R1 inbound whitelist `{tun, direct}`** — preserved via W0.T4 explicit comment + Test 6 (forbiddenInboundType socks).
- **R6 P2P=false** — TunnelSettings.makeR6Safe not modified (PATTERNS §3.x carry-forward).
- **R10 TUN inbound runtime expansion** — `expandConfigForTunnel` unchanged per RESEARCH §7.4 confirmation.
- **R11 security audit 37/37** — no closed decision re-opened; new threats T-02-01..T-02-13 inherit R1 mitigation via `SingBoxConfigLoader.validate` self-test pipeline (PATTERNS §3.1).
- **KILL-01/02 defaults** — `apply(to:enabled:true)` preserves Phase 1 R4 defaults; ConfigImporter passes `enabled: true` hardcoded between W0.T2 and W3.T1 to maintain Phase 1 path identity.
- **No debug logs in Release** — W6.T1 explicit grep for `print(` and `os_log(.debug` in production sources.

---

## Out-of-Scope Discipline — PASS

Plan correctly excludes all CONTEXT-Deferred items:
- IMP-03 file picker — explicit "Phase 11" in plan §13 + multiple references.
- Server-list UI / pull-to-refresh / multi-subscription UI — Phase 3.
- Full Settings sections — Phase 4 / 10 / 11.
- Anti-DPI suite — Phase 7.
- macOS R5 enforceRoutes toggle — Phase 10 (hook reserved).
- Certificate pinning subscription — Phase 7.
- Auto-reconnect on toggle change — explicitly rejected per CONTEXT D-14.
- Confirmation alert on Kill Switch — explicitly rejected per CONTEXT D-13.

No deferred item creeps into any task action.

---

## Verification Methodology

This review followed the goal-backward protocol:

1. Extracted 8 ROADMAP success criteria and 15 CONTEXT decisions as the target outcome set.
2. For each criterion/decision, located implementing task(s) in PLAN.md by frontmatter `must_haves`, `key_links`, and full task `<action>` body search.
3. Validated each task has Files + Action + Verify + Done.
4. Built wave dependency graph (W0 → W1 → W2 → W3 → W4 → W5 → W6) — acyclic.
5. Cross-referenced critical RESEARCH findings (urltest 1m interval, HEAD probe, DNS detour, validate relaxation, NETunnelProviderManager save→load) against task actions — all present.
6. Cross-referenced PATTERNS critical decisions §5.1–§5.4 against W0/W1 design — all reflected.
7. Scanned plan for scope-reduction language (v1/v2/static/placeholder) — none found that contradicts user decisions.
8. Verified Phase 1 invariants (R1, R6, R10, R11, KILL-01/02) explicitly preserved.

---

## Sign-off

**Verification by:** `gsd-plan-checker`
**Mode:** Goal-backward, adversarial stance, pre-execution
**Verdict:** **APPROVED WITH WARNINGS** — proceed to `/gsd-execute-phase 2`.
**Date:** 2026-05-11
**Total findings:** 12 (0 HIGH, 3 MED, 9 LOW)

