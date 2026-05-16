# Pre-TestFlight Comprehensive Audit — Phase 13 Plan 02

**Date:** 2026-05-16 (evening)
**Reviewers:** 7 Opus 4.7 subagents + 9 Codex 5.5 threads = 16 parallel reviewers
**Scope:** 15 packages / ~23k LOC shipping code, 183 swift files
**Baseline:** main @ commit `663f266` (Phase 13 Plan 01 closed)

---

## Verdict

**🛑 BLOCK TestFlight Internal Distribution upload до closure CRITICAL findings.**

**Rationale:** Найдено 18 CRITICAL findings, из которых:
- 6 — **JSON injection через raw string template substitution** во ВСЕХ 6 протоколах (`buildSingBoxJSON` paths) — cross-cutting security defect, не «один баг где-то».
- 4 — **Signed rules pipeline gaps** (placeholder pubkey, path traversal через server-controlled filenames, missing sha256 verification, replay protection через wallclock).
- 3 — **SSRF guards bypassable** (SubscriptionURLFetcher, JSONEndpointFetcher, RulesFetcher) — string-prefix matching без post-DNS validation.
- 1 — **MainScreenViewModel observer leak без deinit** — Phase 6c NEVPN storm class regression.
- 1 — **IPv6 leakage в diagnostics export** — privacy contract violation.
- 3 — **Cache poisoning через body-size DoS / no-input-limits на parsing boundary**.

Несколько находок ниже CRITICAL (HIGH) тоже de-facto blocking: **Keychain delete с add-payload** (C2-001), **disconnect() can stop wrong VPN manager** (C3-002), **TUIC imports succeed но cannot connect** (C3-003).

---

## Summary

| Severity | Total | Cross-validated (Opus+Codex agree) | Single-source (require verification) |
|----------|-------|-----------------------------------|-------------------------------------|
| **CRITICAL** | **18** | 6 (RulesEngine pipeline) | 12 |
| **HIGH** | **44** | 11 | 33 |
| **MEDIUM** | **56** | ~5 | ~51 |
| **LOW** | **42** | ~3 | ~39 |
| **TOTAL** | **160** | | |

**Distribution per reviewer:**

| Reviewer | Scope | C/H/M/L counts |
|----------|-------|----------------|
| A1 Opus | PacketTunnelKit | 0 / 3 / 6 / 5 |
| A2 Opus | VPNCore | 0 / 3 / 5 / 3 |
| A3 Opus | MainScreenFeature | 1 / 4 / 6 / 3 |
| A4 Opus | ConfigParser | 1 / 6 / 8 / 4 |
| A5 Opus | RulesEngine | 2 / 4 / 5 / 3 |
| A6 Opus | MEDIUM tier (12 pkgs) | 0 / 3 / 8 / 6 |
| A7 Opus | LOW tier (5 pkgs) | 0 / 0 / 1 / 8 |
| C1 Codex | PacketTunnelKit | 0 / 3 / 3 / 0 |
| C2 Codex | VPNCore | 0 / 1 / 1 / 1 |
| C3 Codex | MainScreenFeature | 0 / 3 / 1 / 1 |
| C4 Codex | ConfigParser | 3 / 3 / 2 / 0 |
| C5 Codex | RulesEngine | 4 / 2 / 2 / 0 |
| C6 Codex | Settings+ServerList | 1 / 0 / 3 / 1 |
| C7 Codex | Fronting+DeepLinks+KS+Transport | 0 / 3 / 4 / 1 |
| C8 Codex | Protocols/* (6 protocols) | 6 / 6 / 0 / 0 |
| C9 Codex | LOW tier | 0 / 0 / 1 / 6 |

---

## Cross-Validation Notes

**Где Opus и Codex согласны (high confidence CRITICAL):**

- **RulesEngine signature pipeline:** A5-001 (placeholder pubkey) + C5-001 (pre-DNS SSRF); A5-002 (path traversal) + C5-004 (path traversal); A5-003 (sha256 not verified) + C5-002 (sha256 ignored); A5-004 (minAppVersion not enforced) + C5-003 (replay protection incomplete). **4 cross-validated CRITICAL.**
- **SubscriptionURLFetcher SSRF:** A4-001 (string-prefix bypassable) + C4-001 (incomplete redirect/DNS guard). **1 cross-validated CRITICAL.**
- **MainScreenViewModel observer deinit:** A3-001 + C3-005 (both at line 110). **1 cross-validated CRITICAL→HIGH** (A3 marked CRITICAL, C3 marked LOW — disagreement on severity, lean CRITICAL given Phase 6c regression class).

**Где только Codex увидел (single-source но high confidence — pattern consistent):**

- **C8-001 to C8-011 — Raw JSON template substitution в 6 protocols** (Phase-level pattern). Opus A6 не обнаружил т.к. focus был shallow MEDIUM-tier. **Recommendation: verify через manual code-read одного из 6 protocols (e.g. Trojan ConfigBuilder.swift:63) перед closure.**
- **C4-002 — JSONEndpointFetcher missing SSRF guard** (Opus A4 пропустил).
- **C4-003 — No input/body size limits at public boundary** (Opus A4 покрыл частично через A4-002/A4-004/A4-005 — cross-validated через 3 separate Opus findings).
- **C6-001 — IPv6 leakage в DiagnosticsExporter** (Opus A6-004 mentioned but classified MEDIUM, Codex C6 elevated к CRITICAL — privacy contract violation).
- **C5-005/006 — Atomic write race + baseline never verified** (RulesEngine, Opus A5 mentioned related issues).

**Где только Opus увидел:**

- **A3-001 — `MainScreenViewModel` no `deinit`** (Codex C3-005 confirmed but rated LOW; Opus rated CRITICAL given Phase 6c NEVPN storm class). **Verify on real device pre-merge.**
- **A4-007 — Placeholder Ed25519 в SubscriptionPinManager** (separate from A5-001 / C5-001 RulesEngine placeholder).
- **A4-003 — JSON injection через `tag` field reaches sing-box config** (Opus saw additional injection point Codex C8 didn't cover).
- **A1-002 — UserDefaults toggle staleness в hot path** (Codex C1 didn't flag).
- **A6-001 — `killSwitchEnabled` default mismatch between SettingsViewModel and ConfigImporter** (Opus systemic finding, no Codex parallel).

---

## CRITICAL Findings (must fix before TestFlight)

### Cluster 1: Protocols/* Raw JSON Template Substitution (6 findings, all from C8)

**Pattern (cross-protocol):** Each protocol's `ConfigBuilder.buildSingBoxJSON(...)` uses raw string substitution to insert user-controlled values (password, host, SNI, fingerprint, UUID, WS path) into a pre-quoted JSON template. No JSON escaping → quote/control-char injection → malformed JSON or sibling-field injection before validation.

- **C8-001 VLESSReality:** `ConfigBuilder.swift:58` — host/uuid/flow/sni/fingerprint/publicKey/shortId raw-substituted.
- **C8-003 VLESSTLS:** `ConfigBuilder.swift:58` — host/SNI/fingerprint/flow raw replacement.
- **C8-005 Trojan:** `ConfigBuilder.swift:63` — password/host/SNI/fingerprint/WS path/WS host raw-substituted. **Trojan password = user-controlled, arbitrary characters expected.**
- **C8-007 Shadowsocks:** `ConfigBuilder.swift:52` — host/method/password raw-substituted.
- **C8-009 Hysteria2:** `ConfigBuilder.swift:92` — host/auth password/SNI raw-inserted.
- **C8-011 TUIC:** `ConfigBuilder.swift:95` — host/UUID/password/CC/UDP mode/SNI/fingerprint raw-inserted.

**Why CRITICAL:** Each is user-controlled input flowing into JSON template без escape — attacker control of password / SNI / fingerprint can produce malformed sing-box JSON or inject `"flow": "vision", "tls": {"insecure": true, "allow_insecure": true}` etc. Attack surface = ANY URI import (subscription, paste, QR).

**Verification needed:** ConfigImporter использует `PoolBuilder.buildSingleOutboundJSON` (через `buildOutbound` path, который возвращает dict — safe). Но template paths `buildSingBoxJSON` остаются public API, возможно тестами/legacy callers используются. Cross-validate если live path только dict-based — может downgrade severity к HIGH.

**Suggested fix:** Удалить template path целиком (если dead) ИЛИ заменить raw substitution на dict-based `buildOutbound` → `JSONSerialization.data`. Не оставлять public template APIs.

### Cluster 2: RulesEngine Signed Pipeline Gaps (6 cross-validated findings)

- **A5-001 / (Phase 8 incomplete):** `PublicKey.swift` всё ещё содержит placeholder Ed25519 pubkey — manifest signature verification либо fails always (rules never load) либо trivially forgeable если placeholder private key утечёт. **Phase 8 W7 closure не подтверждён.**
- **A5-002 / C5-004:** `entry.name` / `entry.sigPath` из server-controlled manifest пишутся в файловую систему через `appendingPathComponent` БЕЗ path-traversal validation. Compromised signing key → write outside `Library/Caches/rules` (`../../`, abs paths).
- **A5-003 / C5-002:** `entry.sha256` decoded но NEVER verified против actual SRS bytes. Attacker может substitute valid signed SRS из старой манифест-версии (replay/mix-and-match).
- **A5-004 / C5-003:** `manifest.version > cachedVersion` единственная replay protection; нет `updated_at` freshness window. Fresh install (cachedVersion=0) accepts ANY signed manifest indefinitely. **C5-003: add signed `updated_at` + max-age policy.**
- **A5-005 / C5-005:** Atomic write — каждый SRS+sig individually atomic, но group of 8 files (manifest+sig + 3 SRS + 3 SRS-sig) НЕ atomic transactional. App kill mid-sequence → mixed old/new ruleset; extension auto-reload между writes runs с partial signed rules.
- **A5-006 / C5-006:** `bootstrap()` загружает embedded baseline + sigs БЕЗ Ed25519 verification — committed baseline artifact corruption silently applied on first run.

**Why CRITICAL:** Любая из 6 — single-step compromise rules pipeline trust model. Cross-validated между Opus и Codex с high confidence.

**Suggested fix:** Block TestFlight on Phase 8 W7 actual closure. Audit needed in order:
1. Replace placeholder pubkey c real Ed25519 published key (Phase 8 incomplete prerequisite).
2. Add `entry.name`/`sigPath` validation (reject `/`, `\`, `..`, percent-encoded). Prefer fixed local filenames mapped from categories.
3. Verify SHA-256 of each fetched SRS against `entry.sha256` before write.
4. Add `updated_at` field + freshness window enforcement.
5. Versioned cache dir + atomic swap (single generation marker extension reads).
6. Verify baseline signatures in `bootstrap()`.

### Cluster 3: SSRF Guards Incomplete (3 CRITICAL, multi-package)

- **A4-001 / C4-001 — SubscriptionURLFetcher:** `isBlockedHost(rawHost)` checked ONCE before fetch, string-prefix only. Missing: `.local`/mDNS, IPv4-mapped IPv6 (`::ffff:10.0.0.1`), DNS rebinding, redirect re-check, `100.64/10` CGNAT space, non-canonical IP forms (octal `0177.0.0.1`).
- **C4-002 — JSONEndpointFetcher:** HTTPS-only enforced, NO SSRF host blocklist at all. Any caller с user-provided JSON endpoint URL может reach loopback/RFC1918.
- **C5-001 — RulesFetcher:** pre-DNS string check only, no redirect re-validation, blocklist misses `.local` and `100.64/10`.

**Why CRITICAL:** All three fetchers receive user-supplied URLs (subscription, mirror, endpoint). Bypass enables reach к internal services (router admin pages, instance metadata `169.254.169.254` if iOS proxies через corporate WiFi, mDNS discovery).

**Suggested fix:** Centralize в `ValidatedHTTPSFetcher` actor с:
- IP-parser based blocklist (NOT string-prefix).
- Disable redirects (или re-validate в `willPerformHTTPRedirection` delegate).
- Cover: RFC1918, loopback, link-local (169.254/16, fe80::/10), ULA (fc00::/7), CGNAT (100.64/10), multicast/reserved IPv4, `.local`, IPv4-mapped IPv6, IPv6 loopback `::1`, IPv6 link-local.

### Cluster 4: Single-source CRITICAL

- **A3-001 / C3-005:** ✅ CLOSED 2026-05-16 commit (T-A4) — `MainScreenViewModel` теперь has `deinit` removing 3 observer tokens; observer props marked `nonisolated(unsafe)` для Swift 6 strict concurrency compliance.
- **C6-001 — DiagnosticsExporter IPv6 leaks:** `prepareLog()` masks ТОЛЬКО IPv4 через `maskIPv4`; IPv6 explicitly oставлен unchanged. Header export говорит «IP addresses masked» — privacy contract violation.
- **A4-002 / A4-004 / A4-005 / C4-003 — Body-size DoS (multi-source HIGH→CRITICAL given combined exploit chain):** `URLSession.data(for:)` unbounded body, `JSONSerialization`/`Yams.load` unbounded, base64 decode unbounded. Subscription endpoint serving 1GB JSON → OOM crash на каждый refresh.
- **A4-003 — JSON injection через `tag` field:** Opus single-source. Sing-box config tag field accepts user input from subscription extraction (DNS extraction loop), может break `urltest.outbounds` resolution. Need verification.
- **A4-007 — Placeholder Ed25519 в SubscriptionPinManager** (separate от RulesEngine placeholder).

---

## HIGH Findings (should fix before TestFlight; multi-source когда указано)

### PacketTunnelKit
- **A1-001:** STUN-block rule injection lacks `tag` key — sing-box schema reject OR rule never matches (WebRTC IP leak).
- **A1-002:** `UserDefaults(suiteName:)` reads inside hot path `expandConfigForTunnel` без caching, cross-process eventual consistency → toggle staleness.
- **A1-003:** "idempotent" contract violated — STUN/priority-rule insertion falls back на `rules.count` when `hijack-dns` absent.
- **C1-001:** `commandServer.start()` precedes expand/validate; failure path не closing → libbox resources leak.
- **C1-002:** `ExtensionPlatformInterface` `@unchecked Sendable` без synchronization — libbox Go-runtime threads + NWPathMonitor races.
- **C1-003:** `validate` accepts non-dialable group-only proxy configs (urltest/selector без resolved children).

### VPNCore
- **A2-001 / C2-001 partial:** KeychainStore silently falls back к private access group when `AppIdentifierPrefix` missing; **C2-001 separately:** `SecItemDelete` uses add payload не lookup query → duplicate-item on key rotation.
- **A2-002 / C2-002:** Keychain queries не pin `kSecAttrSynchronizable=false` — VPN credentials могли бы sync через iCloud Keychain.
- **A2-003:** SwiftData `#Predicate` on optional `String` in migration — UUID? anti-pattern parallel (silent empty result).

### MainScreenFeature
- **A3-002:** `applyVPNStatus` dedupe key drops `.connected→.connected (different connectedDate)` updates → timer authority sticks to stale start.
- **A3-003:** `init` seed Task races с `bootstrap` cancellation → initial NEVPN status lost.
- **A3-004:** ✅ CLOSED 2026-05-16 commit (T-B4) — `killSwitchObserver` queue switched to `nil` matching `nevpnStatusObserver` pattern.
- **A3-005:** `ConfigImporter` `@unchecked Sendable` с non-Sendable `modelContainer` → concurrent SwiftData fetches across `provisionTunnelProfile` calls могут crash.
- **C3-001:** `handleForegroundReentry()` calls `tunnel.handleForeground()` (no-op) НЕ VM `handleForeground()` (real) — Phase 6c defense-in-depth regression.
- **C3-002:** ✅ CLOSED 2026-05-16 (T-B2) — `disconnect()` теперь filters через `ManagerSelector.ourManagers(...)` matching `connect()` (:617) и bootstrap (:286).
- **C3-003:** TUIC imports succeed but `reparseFromKeychainScalar`/`reparseFromKeychain` omit `"tuic"` case → connection fails. **TUIC-only user видит "no supported servers".**

### ConfigParser
- **A4-002 / A4-004 / A4-005:** Body size unbounded + JSON depth unbounded + base64 unbounded → triple DoS surface (each enough alone).
- **A4-003:** JSON injection через `tag` field reaches sing-box config.
- **A4-006:** PoolBuilder cross-process UserDefaults read без thread-safety annotation.
- **A4-007:** Ed25519 placeholder в SubscriptionPinManager.

### RulesEngine
- **A5-005 / C5-005:** Non-transactional multi-file refresh write.
- **A5-006 / C5-001:** SSRF pre-DNS only (counted в CRITICAL Cluster 3, also HIGH multi-validation).
- **C5-005 / C5-006 separately:** Atomic + baseline-verify (counted в CRITICAL Cluster 2).

### MEDIUM-tier packages (HIGH severity carve-outs)
- **A6-001 / A6-002 — killSwitchEnabled default mismatch:** SettingsViewModel + enforceRoutes treat absence as `false`; ConfigImporter + MainScreenViewModel treat absence as `true`. First-install macOS enforceRoutes toggle silently down-toggles kill switch.
- **A6-003 — ImportHandler `/import` over-broad prefix:** matches `/important`, `/importer`.
- **C7-001 — CDN adapters blacklist not allowlist:** mutate every outbound except small blacklist → `direct`/`urltest` outbounds corrupted with proxy fields.
- **C7-002 — FrontingConfigApplier single-outbound bypass:** `validateProfile` only on batch path, not on inline `apply(outbound:profile:adapter:)`.
- **C7-004 — Deep-link URLs logged as `.public`:** subscription tokens leak via Console/sysdiagnose.

### Protocols/* (HIGH from C8 — buildOutbound validation gaps, 6 findings)
- **C8-002 VLESSReality:** silently omits `tls.reality` when publicKey empty.
- **C8-004 VLESSTLS:** `buildOutbound` skips validations present in `buildSingBoxJSON`.
- **C8-006 Trojan:** `buildOutbound` skips port/password/SNI validations.
- **C8-008 Shadowsocks:** `buildOutbound` skips method whitelist + non-empty password.
- **C8-010 Hysteria2:** `buildOutbound` skips port/auth/SNI validation.
- **C8-012 TUIC:** `buildOutbound` skips congestion-control + UDP-relay-mode whitelist (sharpest cross-protocol consistency gap).

---

## MEDIUM Findings (fix in next iteration after CRITICAL/HIGH closed)

См. individual per-reviewer findings files в `audit-findings/`. Concentrated themes:

- DiagnosticsExporter (IPv4 mask only, byte-vs-char counting, log file growth)
- Force-update cooldown bypass via app restart (C6-003)
- SwiftData @Query / fetch debounce edge cases (C6-005, A6-008, A6-009)
- KeychainStore correctness (C2-001 incorrect SecItemDelete usage)
- Transport handler input validation (C7-007 path/host без validation)
- macOS-only enforceRoutes (A2-009 KeychainStore.delete с nil access group)
- @MainActor mismatches (A3-008 OnDemandRulesBuilder)

**Total 56 MEDIUM findings.** Будут tracking'аться отдельным backlog'ом после Phase 13 closure.

---

## LOW Findings (track for cleanup, не blocking)

**Total 42 LOW findings.** Themes:

- Dead code (XrayFallback placeholder, registeredIdentifiers, 34 unused L10n accessors)
- Stale TODO comments / version strings (VPNCore.version = "0.1.0" stale)
- Code smells (force-casts, fatalError in entitlement path, hidden coupling)
- Privacy levels в os_log (.public когда могло быть .private)
- Cooldown timer lifecycle (теоретический leak в test scenarios)

---

## Systemic Patterns Observed

1. **Validation duplicated в `buildSingBoxJSON` template path и `buildOutbound` dict path, но inconsistently** (C8 cross-protocol pattern). Template paths валидируют port/required-fields; dict paths trust public parsed structs. Если template paths dead → удалить. Если live → centralize validation в shared helper.

2. **SSRF guard pattern скопирован 3+ раза с variations** (`SubscriptionURLFetcher.isBlockedHost`, `RulesFetcher` reuses, `FrontingConfigApplier.isPrivateOrLoopback`, `JSONEndpointFetcher` missing). String-prefix approach фундаментально insufficient. Should be: **one shared `ValidatedHTTPSFetcher` actor** with IP-parser-based blocklist + redirect re-validation.

3. **`@unchecked Sendable` без synchronization** в 3 packages (A1-004 BaseSingBoxTunnel, A3-005 ConfigImporter, A6-016 KillSwitch suiteName, C1-002 ExtensionPlatformInterface) — Swift 6 compile-time check bypassed без runtime contract. Audit `@unchecked Sendable` usages systemically.

4. **`UserDefaults(suiteName:)` hot-path reads** в multiple packages without caching (A1-002, A1-014, A3-008, A6-016) — cross-process eventual consistency может cause toggle staleness. Consider: cache snapshot at tunnel start; explicit refresh trigger on settings change.

5. **`fatalError` в production paths** где throw был бы appropriate (A1-011 AppGroupContainer, C1-006 same). Especially в extension which has limited diagnosability — should map к throwing error.

6. **Replay protection через monotonic version + wallclock manipulation susceptibility** в RulesEngine (A5-007, C5-003). Fresh install resets version → any signed manifest accepted. Need signed `updated_at` field + freshness window.

7. **Phase 8 W7 not actually closed** despite ROADMAP showing Phase 8 ✅: placeholder Ed25519 pubkey (A5-001, A4-007 separate site), `rules.bbtb.example` mirror URLs (A5-014), real cert/signing key never published. **Status mismatch между ROADMAP и codebase — verify Phase 8 closure assumptions before Phase 13 TestFlight.**

---

## Recommended Fix Order (User to Prioritize)

### Tier A — Block TestFlight Upload (must close)

1. **RulesEngine placeholder pubkey + Phase 8 W7 closure** (A5-001). Either real key published OR disable RulesEngine fetch для v1.0 (баselin-only). 1-2 hours.
2. **RulesEngine path traversal validation** (A5-002 / C5-004). Validate `entry.name` / `entry.sigPath` reject `/`, `\`, `..`, percent-encoded, abs paths. 1 hour.
3. **RulesEngine sha256 verification** (A5-003 / C5-002). Compute SHA-256 of each SRS, compare с manifest `entry.sha256`. 1 hour.
4. **Protocols/* JSON injection** (C8-001..C8-011) — verify if `buildSingBoxJSON` template paths dead. Если dead → delete (4 hours including tests). Если live → migrate to dict-based serialization (8-16 hours).
5. **SubscriptionURLFetcher/JSONEndpointFetcher/RulesFetcher SSRF unification** (A4-001 + C4-001 + C4-002 + C5-001). Create `ValidatedHTTPSFetcher` с IP-parser blocklist + redirect re-validation. 4-6 hours.
6. **MainScreenViewModel deinit** (A3-001) — add `deinit` removing 3 observers. 30 min.
7. **DiagnosticsExporter IPv6 masking** (C6-001) — extend regex для IPv6. 1 hour.

### Tier B — Should fix before TestFlight (highly recommended)

8. **TUIC reparse missing** (C3-003) — add `"tuic"` case in reparseFromKeychain*. 30 min.
9. **disconnect() ManagerSelector** (C3-002) — use ourManagers filter. 15 min.
10. **Keychain SecItemDelete query fix** (C2-001) — split base/add query. 30 min.
11. **`killSwitchObserver queue: .main → nil`** (A3-004) — direct fix per memory pattern. 5 min.
12. **Body size limits на boundary** (A4-002/004/005, C4-003) — add max-size guards on subscription fetch + JSON parse + base64 decode. 2 hours.
13. **RulesEngine atomic multi-file write** (A5-005 / C5-005) — versioned cache dir + atomic swap. 4-6 hours.
14. **killSwitchEnabled default consistency** (A6-001 / A6-002) — pin default `true` everywhere. 30 min.
15. **MainScreenViewModel state machine fixes** (A3-002, A3-003, A3-005 ConfigImporter modelContainer isolation). 3-4 hours.

### Tier C — Next iteration backlog (post-TestFlight)

All MEDIUM findings + remaining HIGH (RulesEngine baseline verify, FrontingEngine validation paths, deep-link logging redaction).

### Tier D — Cleanup (LOW)

XrayFallback dead module, unused L10n accessors, stale TODOs, force-cast cleanup.

---

## Estimated Fix Effort

- **Tier A (CRITICAL):** 12-30 hours (зависит от protocol template path live/dead status)
- **Tier B (HIGH selected):** 12-15 hours
- **Tier C (MEDIUM):** 30-50 hours
- **Tier D (LOW):** 8-15 hours

**Recommended pre-TestFlight scope:** Tier A + Tier B = 24-45 hours. Fits в 2-4 dedicated work days.

---

## Per-Reviewer Findings Files

Полный detail каждого finding с file:line + description + why-it-matters + suggested-fix:

- `audit-findings/A1-PacketTunnelKit-opus.md`
- `audit-findings/A2-VPNCore-opus.md`
- `audit-findings/A3-MainScreenFeature-opus.md`
- `audit-findings/A4-ConfigParser-opus.md`
- `audit-findings/A5-RulesEngine-opus.md`
- `audit-findings/A6-MEDIUM-tier-opus.md`
- `audit-findings/A7-LOW-tier-opus.md`
- `audit-findings/C1-PacketTunnelKit-codex.md`
- `audit-findings/C2-VPNCore-codex.md`
- `audit-findings/C3-MainScreenFeature-codex.md`
- `audit-findings/C4-ConfigParser-codex.md`
- `audit-findings/C5-RulesEngine-codex.md`
- `audit-findings/C6-Settings-ServerList-codex.md`
- `audit-findings/C7-Fronting-DeepLinks-KillSwitch-TransportRegistry-codex.md`
- `audit-findings/C8-Protocols-codex.md`
- `audit-findings/C9-LOW-tier-codex.md`

---

## Next Step

User приоритизирует Tier A+B closure → отдельный fix-up cycle с per-fix атомарными commits. После closure: re-baseline build + tests → mark Phase 13 Plan 02 ✅ DONE → proceed к Apple Developer Portal NE capability + App Store Connect record creation.

**Verification rerun після fixes:** re-dispatch CRITICAL-only reviewer set (A4 + A5 + C4 + C5 + C8) verify все Tier A closed.
