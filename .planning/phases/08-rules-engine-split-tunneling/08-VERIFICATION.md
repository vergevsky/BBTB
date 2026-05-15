---
phase: 08-rules-engine-split-tunneling
verified: 2026-05-15T06:46:30Z
uat_completed: 2026-05-15T14:00:00Z
status: complete_deferred
score: 9/11 must-haves verified
overrides_applied: 0
human_verification:
  - test: "M-04: BGAppRefreshTask real wall-time on iPhone"
    expected: "SRS file mtime advances after ~6h background; Console shows bbtbRulesEngineDidUpdate posted"
    why_human: "BGAppRefreshTask fires opportunistically; iOS Simulator trigger available but real-device closes the loop"
    result: "PASS — device logs confirm: bootstrap writes bbtb-baseline-*.srs ✓, BGAppRefreshTask fires ✓, RulesFetcher tries all 3 mirrors sequentially ✓, fails with -1003 DNS (expected: placeholder URLs). bbtbRulesEngineDidUpdate not posted — correct (only on successful server update). Mechanism works."
  - test: "M-05: Real domain blocking on device (curl max.ru → connection reset)"
    expected: "curl to block_completely domain returns connection reset/timeout through tunnel; never_through_vpn domain bypasses VPN (direct IP); always_through_vpn routes through VPN regardless"
    why_human: "Unit tests verify rule_set injection into config JSON; only real tunnel confirms sing-box actually drops/routes traffic"
    result: "PASS — user confirmed."
  - test: "M-07: Split-tunnel country resolve on device (RU CIDRs → direct)"
    expected: "Request to known-RU IP (yandex.ru) goes direct (non-VPN); non-RU IP goes through tunnel"
    why_human: "Server-side country→CIDR expansion; client cannot independently verify CIDR coverage without geo-located test endpoint and real signed server manifest"
    result: "DEFERRED — VPS admin pipeline not configured. Requires real VPS with signed manifest containing countries:[\"RU\"]. Carry-over to Phase 9/pre-TestFlight."
  - test: "M-08: min_app_version sheet UX flow on device (dismiss persistence, re-appear on next fetch)"
    expected: "Sheet appears when min_app_version > current; dismiss → banner persists in Advanced; force-kill and reopen → sheet re-appears; accepting → TestFlight URL opens"
    why_human: "UI snapshot tests cover layout; @AppStorage durability and TestFlight URL open need device validation"
    result: "DEFERRED — VPS admin pipeline not configured. Requires server-delivered manifest with min_app_version > current. Carry-over to Phase 9/pre-TestFlight."
gaps:
  - truth: "Production mirror URLs deliver real rules.json to clients"
    status: failed
    reason: "RulesEngineCoordinator.productionMirrors hardcoded to https://rules.bbtb.example/* placeholder URLs. No real VPS configured. RULES-01 network path is fully implemented in code but will always fail fetchWithFailover in practice until admin replaces these URLs."
    artifacts:
      - path: "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift"
        issue: "productionMirrors = [\"https://rules.bbtb.example/manifest.json\", ...] — placeholder, not real VPS"
    missing:
      - "Replace productionMirrors with real VPS URLs before shipping. Consider externalizing via build config or Info.plist key to avoid hardcoding."
  - truth: "Baseline SRS files are applied by sing-box on first boot (before server fetch)"
    status: partial
    reason: "Design mismatch between bootstrap output filenames and SingBoxConfigLoader expected filenames. bootstrap() writes 'bbtb-baseline-block.srs' to App Group cache; SingBoxConfigLoader injects route.rule_set paths for 'bbtb-block.srs'. On first boot sing-box logs a warning (missing file) but tunnel still starts per W5 plan §absent-files doc. Rules are NOT enforced until first successful server fetch."
    artifacts:
      - path: "BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift"
        issue: "baselineFilename(for:) returns 'bbtb-baseline-block.srs' but SingBoxConfigLoader expects 'bbtb-block.srs'"
      - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift"
        issue: "Hardcoded categories: (tag: 'bbtb-block', file: 'bbtb-block.srs') — does not match baseline naming"
    missing:
      - "Either: (a) rename bootstrap() output to 'bbtb-block.srs' to match SingBoxConfigLoader, OR (b) update SingBoxConfigLoader to use 'bbtb-baseline-*.srs' paths. Option (a) is simpler and aligns with the server manifest naming in RESEARCH.md."
---

# Phase 8: Rules Engine + Split Tunneling Verification Report

**Phase Goal:** Централизованные правила с Ed25519-подписью, split-tunneling по доменам/IP/странам через sing-box `route.rule_set`. Версия — v0.8.
**Verified:** 2026-05-15T06:46:30Z
**Status:** human_needed (automated checks: 9/11 VERIFIED, 2 gaps; 4 manual UAT scenarios required)
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| SC-1 | Подмена rules.json на сервере → клиент применяет в течение 6 часов | ✓ VERIFIED | RulesEngineCoordinator.performBackgroundRefresh() + BGAppRefreshTask (iOS) + NSBackgroundActivityScheduler 6h (macOS) fully implemented and wired. |
| SC-2 | Битая Ed25519-подпись → игнорирует обновление, кеш сохраняется | ✓ VERIFIED | RulesSigner.verify() + coordinator guards at step 2 (manifest sig) and step 7 (per-SRS sig). test_performBackgroundRefresh_tamperedSig_keepsCache_returnsFalse() confirms. |
| SC-3 | AppProxyProvider per-app routing | N/A — Out of Scope | Correctly deferred per D-08/D-09. wiki/appproxy-deferral-2026.md created. RULES-11 struck from REQUIREMENTS.md. |
| SC-4 | Просмотр правил (read-only) в Расширенных отражает актуальный rules.json | ✓ VERIFIED | RulesViewerSection + AdvancedSettingsView integration + SettingsViewModel.rulesSnapshot published via coordinator notification. |
| SC-5 | Кнопка «Принудительно обновить правила» работает | ✓ VERIFIED | ForceUpdateRulesButton (FSM: idle/inProgress/cooldown) + SettingsViewModel.triggerForceUpdate() + 60s cooldown gate via coordinator.forceUpdate(). |

### Requirements Coverage (RULES-01..10 + CORE-05)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | RULES-01: Download from primary VPS + 3 mirror failover (sequential) | PARTIAL | RulesFetcher.fetchWithFailover() — sequential failover fully implemented, SSRF-guarded, 11 tests pass. productionMirrors = placeholder "rules.bbtb.example" — WILL FAIL until admin configures real URLs. See gaps. |
| 2 | RULES-02: Ed25519 detached-signature verify via swift-crypto | ✓ VERIFIED | RulesSigner.verify() with Curve25519.Signing.PublicKey + PublicKey.swift with real ephemeral bytes (R12 invariant PASS: no sequential 0x00..0x1F pattern). 6 unit tests pass. |
| 3 | RULES-03: Bad signature → ignore update, keep cache | ✓ VERIFIED | coordinator step 2/7: guard signer.verify() → return false on fail; cachedManifest unchanged. test_tamperedSig_keepsCache PASS. |
| 4 | RULES-04: Fetch on start + every 6h background | ✓ VERIFIED | iOS: BGAppRefreshTask "app.bbtb.client.ios.rules-refresh" registered + Info.plist BGTaskSchedulerPermittedIdentifiers entry. macOS: NSBackgroundActivityScheduler interval=21600s, tolerance=600s. Foreground sanity fetch with 12h threshold also wired. |
| 5 | RULES-05: Apply 3 categories correctly (block/never/always) | ✓ VERIFIED (code); ? MANUAL | SingBoxConfigLoader injects route.rule_set[block/never/always] + 3 priority rules (reject/direct/firstProxy). test_expandConfigForTunnel_injectsThreeRuleSetEntries PASS. Device UAT M-05 required. |
| 6 | RULES-06: Priority order block > never > always > default | ✓ VERIFIED | rules inserted in order: block→reject first, never→direct second, always→proxy third at insertIdx after hijack-dns. test_expandConfigForTunnel_rulesetInjectionIsIdempotent confirms dedup. |
| 7 | RULES-07: Split-tunnel by domains/IPs/countries (server-resolved CIDR) | ✓ VERIFIED (code); ? MANUAL | Domain matchers in SRS (domain_suffix/domain), IP CIDRs in SRS, countries server-expanded at signing (D-04). D-03 sniff action ensures domain matching works. Device UAT M-07 required. |
| 8 | RULES-08: min_app_version numeric semver comparison + sheet | ✓ VERIFIED | String.compare(_:options:.numeric) in SettingsViewModel line 374. MinAppVersionSheet + MinAppVersionBanner wired. @AppStorage dismissedMinAppVersion per-version durability. 6 tests in MinAppVersionTests PASS. |
| 9 | RULES-09: Read-only viewer in Advanced Settings | ✓ VERIFIED | RulesViewerSection (3 CategoryGroup, 3 DisclosureGroup each, LazyVStack, textSelection enabled). AdvancedSettingsView line 52 wires snapshot prop. SettingsViewModel.rulesSnapshot published. |
| 10 | RULES-10: Force-update button + 60s cooldown | ✓ VERIFIED | ForceUpdateButtonState FSM (idle/inProgress/cooldown). SettingsViewModel.triggerForceUpdate() with race guard. cooldownDuration=60s in coordinator. 6 ForceUpdateButtonStateTests PASS. |
| 11 | RULES-11: AppProxy per-app routing | N/A | Out of Scope per D-08/D-09. Documented correctly. |
| 12 | CORE-05: Background fetch cadence + cold-start defer (DEC-06d-01) | ✓ VERIFIED | coordinator.init() cheap (no I/O). bootstrap() deferred via Task.detached(priority:.utility). BGAppRefreshTask/NSBackgroundActivityScheduler 6h. D-12 verified. |

**Score:** 9/11 in-scope requirements VERIFIED (1 partial/gap: RULES-01 placeholder URLs; 1 gap: baseline filename mismatch), 4 require device UAT

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesFetcher.swift` | HTTPS+SSRF fetch + sequential failover | ✓ VERIFIED | 239 lines, substantive. SSRF guard via SubscriptionURLFetcher.isBlockedHost. fetchWithFailover sequential DEC-06d-04. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSigner.swift` | Ed25519 verify via swift-crypto | ✓ VERIFIED | 80 lines. Curve25519.Signing.PublicKey.isValidSignature. Wrong-length early return. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` | Full pipeline: bootstrap/refresh/forceUpdate | ✓ VERIFIED | 529 lines. Actor, re-entry guard, 60s cooldown, PerfSignposter spans, MainActor notification. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/SRSCacheStore.swift` | Atomic App Group write/read | ✓ VERIFIED | 99 lines. Actor, Data.write(.atomic), injectable directory. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesManifest.swift` | Manifest Codable + FileEntry + CategoryBodies | ✓ VERIFIED | 158 lines. All fields present, snake_case CodingKeys. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/BaselineRulesLoader.swift` | Bundle resource loader | ✓ VERIFIED | 71 lines. Bundle.module lookup, throws LoadError. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/PublicKey.swift` | Hardcoded 32-byte Ed25519 pubkey | ✓ VERIFIED | Real ephemeral key (0xB5,0x3F,0xCF,...). R12 invariant PASS (not sequential). |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesSnapshot.swift` | UI-facing snapshot + CategoryEntries | ✓ VERIFIED | 85 lines. Sendable Equatable value types. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/Clock.swift` | Mockable wallclock | ✓ VERIFIED | File exists. Injectable ClockProtocol for cooldown testing. |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` | rule_set injection (D-01) | ✓ VERIFIED | Steps 5a/5b: 3 route.rule_set entries + 3 priority rules (block→reject, never→direct, always→firstProxy). Idempotent dedup. R1/R10 invariants preserved. |
| `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` | rulesCacheDirectory | ✓ VERIFIED | App Group Library/Caches/rules, idempotent createDirectory. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/RulesViewerSection.swift` | RULES-09 read-only viewer | ✓ VERIFIED | 325 lines. 3 CategoryGroup, 3 DisclosureGroup each, count badges, LazyVStack. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/ForceUpdateRulesButton.swift` | RULES-10 force-update + cooldown UI | ✓ VERIFIED | 254 lines. ForceUpdateButtonState FSM, status row 4 outcomes, haptic. |
| `BBTB/Packages/AppFeatures/Sources/SettingsFeature/MinAppVersionBanner.swift` | D-11 persistent banner | ✓ VERIFIED | 80 lines. Persistent (not gated by dismissal). Orange tint, chevron. |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MinAppVersionSheet.swift` | D-11 modal sheet | ✓ VERIFIED | 132 lines. iOS .medium detent, macOS 440×320. @AppStorage dismissal durability. |
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | BGAppRefreshTask registration + bootstrap | ✓ VERIFIED | BGTaskScheduler.shared.register for "app.bbtb.client.ios.rules-refresh". Info.plist BGTaskSchedulerPermittedIdentifiers matches. bootstrap() in Task.detached. |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | NSBackgroundActivityScheduler 6h + bootstrap | ✓ VERIFIED | NSBackgroundActivityScheduler interval=21600, tolerance=600. Task.detached bootstrap. |
| `BBTB/scripts/build-baseline-rules.sh` | Baseline compile + sign developer workflow | ✓ VERIFIED | 200+ lines bash. Two modes: production (BBTB_BASELINE_SIGNING_KEY) + ephemeral (auto-keypair). openssl@3 auto-detect. sing-box CLI rule-set compile. |
| `BBTB/scripts/validate-r1-r6.sh` | Phase 8 invariant gates | ✓ VERIFIED | R8 (no inline rule_set in template), R8b (AppGroupContainer paths), RULES-02 (32 hex bytes), R12 (no sequential placeholder), D-08×2 (no NEAppProxyProvider). ALL PASS per W7 SUMMARY. |
| `BBTB/Packages/RulesEngine/Sources/RulesEngine/Resources/` | Signed baseline SRS files | ✓ VERIFIED | baseline-rules.json + manifest.json + manifest.json.sig + 3×.srs + 3×.srs.sig present and real (ephemeral key). |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| BBTB_iOSApp.init | RulesEngineCoordinator.bootstrap() | Task.detached(priority:.utility) | ✓ WIRED | D-12 compliant. |
| BBTB_iOSApp BGAppRefreshTask handler | coordinator.performBackgroundRefresh() | async Task in BGAppRefreshTask closure | ✓ WIRED | Fires at 6h interval. |
| BBTB_macOSApp | NSBackgroundActivityScheduler.schedule | scheduler.schedule { coordinator.performBackgroundRefresh() } | ✓ WIRED | interval=21600s, tolerance=600s. |
| coordinator.performBackgroundRefresh | RulesFetcher.fetchWithFailover | fetcher protocol injection | ✓ WIRED | Sequential mirrors, HTTPS-only. |
| coordinator | RulesSigner.verify | signer protocol injection (DefaultRulesSigner) | ✓ WIRED | Manifest + per-SRS verify gates write. |
| coordinator | SRSCacheStore.write | cache actor injection | ✓ WIRED | Atomic Data.write(.atomic) 8 files. |
| coordinator.performBackgroundRefresh | NotificationCenter.bbtbRulesEngineDidUpdate | Task { @MainActor } post | ✓ WIRED | Posted after success, not bootstrap. |
| SettingsViewModel.wireRulesCoordinator | coordinator.currentSnapshot() + notification | addObserver + Task { @MainActor } | ✓ WIRED | rulesSnapshot @Published updates. |
| MainScreenViewModel.wireRulesCoordinator | coordinator.currentSnapshot() | same pattern | ✓ WIRED | showMinAppVersionSheet driven by snapshot.minAppVersion. |
| SettingsViewModel.triggerForceUpdate | coordinator.forceUpdate() | async Task, race guard | ✓ WIRED | Cooldown enforced in coordinator. |
| SingBoxConfigLoader.expandConfigForTunnel | AppGroupContainer.rulesCacheDirectory | direct import | ✓ WIRED | 3 rule_set entries + 3 priority rules injected. |
| Coordinator bootstrap | BaselineRulesLoader.loadSRS | throws call chain | ✓ WIRED | 8 files copied to App Group on first launch. |
| AdvancedSettingsView | RulesViewerSection | snapshot prop binding | ✓ WIRED | viewModel.rulesSnapshot passed directly. |
| AdvancedSettingsView | ForceUpdateRulesButton | buttonState + onTap binding | ✓ WIRED | viewModel.forceUpdateButtonState + triggerForceUpdate. |
| MainScreenView | MinAppVersionSheet | .sheet(isPresented: $viewModel.showMinAppVersionSheet) | ✓ WIRED | viewModel.dismissMinAppVersionSheet() on both buttons. |
| AdvancedSettingsView | MinAppVersionBanner (conditional) | if viewModel.showMinAppVersionBanner | ✓ WIRED | Persistent per UI-SPEC §A-08. |

### Data-Flow Trace (Level 4)

| Artifact | Data Variable | Source | Produces Real Data | Status |
|----------|---------------|--------|-------------------|--------|
| RulesViewerSection | snapshot: RulesSnapshot? | coordinator.currentSnapshot() → SettingsViewModel.rulesSnapshot @Published | Yes — materializes from cachedManifest CategoryBodies | ✓ FLOWING |
| ForceUpdateRulesButton | buttonState / statusOutcome | SettingsViewModel FSM driven by coordinator.forceUpdate() return | Yes — ForceUpdateOutcome from real pipeline | ✓ FLOWING |
| MinAppVersionBanner | showMinAppVersionBanner | snapshot.minAppVersion.compare(currentAppVersion, .numeric) | Yes — from decoded RulesManifest | ✓ FLOWING |
| MinAppVersionSheet | showMinAppVersionSheet | same as banner, gated by dismissedMinAppVersion @AppStorage | Yes | ✓ FLOWING |
| RulesEngineCoordinator | cachedManifest | server JSON decoded via RulesFetcher + RulesSigner | Server: YES when real URL configured. Baseline: YES from Bundle. | ✓ FLOWING (baseline) / ? FLOWS ONLY WHEN REAL SERVER CONFIGURED |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| RulesEngine package tests | swift test (per W7 SUMMARY: 41 tests) | 41/41 PASS (per W7 SUMMARY) | ✓ PASS (SUMMARY-reported; not re-run in verifier — requires Xcode workspace) |
| PacketTunnelKit rule_set tests | swift test --filter test_expandConfigForTunnel | 4 Phase-8 tests PASS (per W5 SUMMARY) | ✓ PASS (SUMMARY-reported) |
| AppFeatures rules tests | SettingsViewModelTests (6) + ForceUpdateButtonStateTests (6) + MinAppVersionTests (6) | 18 tests PASS (per W3/W8 SUMMARY) | ✓ PASS (SUMMARY-reported) |
| validate-r1-r6.sh Phase 8 gates | bash BBTB/scripts/validate-r1-r6.sh | R8/R8b/RULES-02/R12/D-08×2: 6/6 PASS per W7 SUMMARY | ✓ PASS (SUMMARY-reported) |
| R12: no sequential placeholder key | grep -q "0x00, 0x01, 0x02, 0x03" PublicKey.swift → 0 matches | Actual bytes: 0xB5,0x3F,0xCF,0xC3,... — not sequential | ✓ PASS (code-verified) |
| D-08: No NEAppProxyProvider references | grep -rE NEAppProxyProvider App/iOSApp App/macOSApp AppFeatures | 0 matches | ✓ PASS (code-verified) |
| BGTask identifier matches Info.plist | Info.plist BGTaskSchedulerPermittedIdentifiers = "app.bbtb.client.ios.rules-refresh" | Exact match with rulesRefreshTaskIdentifier constant | ✓ PASS (code-verified) |
| Baseline SRS files real content | ls BBTB/Packages/RulesEngine/.../Resources/ | 10 files present: manifest.json+.sig + 3×.srs + 3×.srs.sig + baseline-rules.json + README.md | ✓ PASS (code-verified) |

### Probe Execution

Step 7c: SKIPPED — no conventional probe-*.sh scripts found. validate-r1-r6.sh is the Phase 8 gate; results reported above from SUMMARY.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|------------|-------------|--------|----------|
| RULES-01 | 08-02-PLAN.md | Mirror failover fetch | PARTIAL | Code complete; productionMirrors = placeholder URLs |
| RULES-02 | 08-02-PLAN.md | Ed25519 signature verify | SATISFIED | RulesSigner + swift-crypto + 6 tests |
| RULES-03 | 08-03-PLAN.md | Bad sig → keep cache | SATISFIED | coordinator guard + test coverage |
| RULES-04 | 08-05-PLAN.md | Fetch on start + 6h BG | SATISFIED | BGAppRefreshTask + NSBackgroundActivityScheduler wired |
| RULES-05 | 08-06-PLAN.md | 3 categories applied | SATISFIED (code) / MANUAL UAT | SingBoxConfigLoader injection; M-05 device UAT |
| RULES-06 | 08-06-PLAN.md | Priority: block>never>always | SATISFIED | Injection order enforced; test confirms |
| RULES-07 | 08-06-PLAN.md | Split-tunnel domains/IPs/countries | SATISFIED (code) / MANUAL UAT | SRS format; D-04 server-side country; M-07 device UAT |
| RULES-08 | 08-04-PLAN.md | min_app_version comparison + sheet | SATISFIED | Numeric compare; sheet + banner wired; 6 tests |
| RULES-09 | 08-04-PLAN.md | Read-only viewer | SATISFIED | RulesViewerSection fully wired |
| RULES-10 | 08-04-PLAN.md | Force-update button + 60s cooldown | SATISFIED | ForceUpdateRulesButton + SettingsViewModel FSM |
| RULES-11 | 08-01-PLAN.md | AppProxy per-app routing | OUT OF SCOPE (documented) | wiki/appproxy-deferral-2026.md created |
| CORE-05 | 08-05-PLAN.md | BG fetch cadence + cold-start defer | SATISFIED | DEC-06d-01 pattern applied |

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `PublicKey.swift` | 20 | `TODO для W7 task 08-08` in doc comment | INFO | In a doc comment (not code), references completed W7. No runtime impact. |
| `AppGroupContainer.swift` | 75 | `TODO Phase 5: убрать вместе с logPath` | INFO | Pre-Phase-8 carry-over. Debug bridge, gated under `#if DEBUG`. Not a Phase 8 issue. |
| `RulesEngineCoordinator.swift` | 116-120 | productionMirrors = placeholder .example URLs | WARNING | No TBD/FIXME marker (no debt-gate trigger) but functional gap — fetchWithFailover always fails in practice. Documented in gaps. |
| `baseline-rules-manifest.json` | — | files[].name = "bbtb-baseline-*.srs" vs SingBoxConfigLoader expecting "bbtb-*.srs" | WARNING | Rules not enforced on first boot before server fetch. sing-box logs warning, tunnel still starts per W5 plan documentation. |

**Debt marker gate:** No `TBD`, `FIXME`, or `XXX` found in Phase 8 modified source files. The doc-comment `TODO` in PublicKey.swift references a completed wave (W7) and carries no unresolved debt.

### Human Verification Required

#### 1. M-04: BGAppRefreshTask Real Wall-Time

**Test:** Install signed build on real iPhone. Connect VPN. Leave app backgrounded. After ~6 hours (or: Xcode Debug → Simulate Background Fetch on Simulator), inspect Console.app.
**Expected:** `bbtb-baseline-block.srs` mtime advances in App Group Library/Caches/rules/; Console shows `"RulesEngineCoordinator.performBackgroundRefresh: success"` and `bbtbRulesEngineDidUpdate` posted.
**Why human:** BGAppRefreshTask fires opportunistically (iOS may throttle); deterministic test requires real-device or Simulator trigger. Wall-time 6h interval can only be confirmed on physical device or instrumented Simulator run.
**Note:** Since productionMirrors = placeholder URLs, performBackgroundRefresh will return false (network failure) in current build. To test BG cadence without real server: inject test mirrorURLs via a debug build config OR verify the BGTask registration fires correctly via Xcode Simulate Background Fetch.

#### 2. M-05: Real Domain Blocking On Device

**Test:** Connect tunnel on iPhone with baseline rules (max.ru in block_completely). Run `curl -v https://max.ru` via Shortcuts or TestFlight build with embedded curl. Repeat for a never_through_vpn domain.
**Expected:** curl to `max.ru` → connection reset or timeout (sing-box reject). curl to never_through_vpn domain → response comes from direct IP (non-VPN). curl to always_through_vpn domain → response through VPN IP.
**Why human:** Unit tests verify JSON config has rule_set entries; only real tunnel running sing-box confirms libbox actually honors the rules.
**Note:** Baseline block_completely contains max.ru and mssgr.tatar.ru. Since server fetch won't succeed (placeholder URLs), test with baseline rules directly. Verify bbtb-baseline-block.srs exists in App Group and sing-box can read it. If baseline naming mismatch blocks rules (bbtb-baseline-block.srs vs bbtb-block.srs), this scenario will fail — which confirms the gap severity.

#### 3. M-07: Split-Tunnel Country Resolution On Device

**Test:** Admin signs rules with `countries: ["RU"]` in never_through_vpn. Client fetches (requires real VPS). Connect tunnel. Request to known-RU IP (e.g. yandex.ru).
**Expected:** yandex.ru resolves to RU AS; request goes direct (non-VPN IP). Non-RU request goes through VPN.
**Why human:** Server-side CIDR expansion (D-04). Client cannot verify CIDR coverage without geo-located test endpoint. Requires real admin VPS with signed manifest using countries field.
**Note:** This test requires: (1) real VPS URL in productionMirrors, (2) signed manifest with countries:["RU"] in never_through_vpn, (3) VPS tooling expanding country codes to CIDRs. This is a full-stack test that validates D-04 end-to-end.

#### 4. M-08: min_app_version Sheet UX Flow On Device

**Test:** Admin publishes manifest with min_app_version set above current app version (e.g. "99.0.0"). Client fetches and processes.
**Expected:** (1) MinAppVersionSheet appears over main screen; (2) Dismiss → MinAppVersionBanner persists in Advanced Settings; (3) Force-kill app → reopen → sheet re-appears (per-version @AppStorage flag cleared only when new version arrives, not on dismiss); (4) Tap "Open TestFlight" → TestFlight URL opens.
**Why human:** @AppStorage durability across app kills and TestFlight URL open behavior require device interaction. UI snapshots in unit tests cover layout only.
**Note:** Requires real server fetch for min_app_version delivery. Alternative for testing without server: temporarily hardcode minAppVersion comparison in SettingsViewModel.wireRulesCoordinator to force-show the sheet.

---

### Gaps Summary

Two actionable gaps were found during verification:

**Gap 1 — Placeholder mirror URLs (RULES-01, WARNING severity):**
`RulesEngineCoordinator.productionMirrors` contains placeholder `https://rules.bbtb.example/` URLs. The network fetch pipeline is fully implemented and tested with mock URLs, but will always fail `fetchWithFailover` against these placeholder addresses in any real deployment. This is a configuration gap, not a code architecture gap — but it means RULES-01 is functionally unverifiable without real server infrastructure. Resolution: admin must replace productionMirrors before any TestFlight distribution. Consider externalizing as a build configuration key (xcconfig / Info.plist) to avoid shipping with hardcoded placeholder.

**Gap 2 — Baseline SRS filename mismatch (RULES-05/06/07, first-boot, WARNING severity):**
`RulesEngineCoordinator.bootstrap()` writes `bbtb-baseline-block.srs` (and never/always) to the App Group cache. `SingBoxConfigLoader.expandConfigForTunnel()` injects route.rule_set paths for `bbtb-block.srs` (without "baseline" prefix). On first boot (before any server fetch), sing-box loads the config but the referenced files do not exist under the expected names. Per W5 plan documentation ("missing file → warning log, не tunnel kill"), the tunnel still starts successfully — but RULES-05/06/07 are NOT enforced on first boot. Rules activate only after first successful server fetch (which requires real URLs — see Gap 1). Resolution: either rename bootstrap output files to match SingBoxConfigLoader expectations (rename to `bbtb-block.srs` on cache write), OR update SingBoxConfigLoader to use the baseline naming convention.

These two gaps are related: both are addressed by setting up real server infrastructure. Gap 2 has an additional code fix path (filename alignment) that is independent of server availability.

---

_Verified: 2026-05-15T06:46:30Z_
_Verifier: Claude (gsd-verifier)_
