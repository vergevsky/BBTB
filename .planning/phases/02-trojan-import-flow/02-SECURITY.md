---
phase: 02-trojan-import-flow
audit_date: 2026-05-12
auditor: gsd-security-auditor (Opus 4.7 1M)
asvs_level: 1
register_source: 02-PLAN.md "Threat Model (Phase 2 STRIDE)" — 13 threats T-02-01..T-02-13
phase1_carry_forward: 01-SECURITY.md — 37 closed threats, R1/R6/R10/R11/KILL invariants
status: verified-with-findings
threats_total: 13
threats_covered: 11
threats_partial: 1
threats_missing: 0
threats_accepted: 1
phase1_invariants_regressions: 0
new_findings: 4
remediation_commits: []
---

# Phase 2 — Security Audit Report

## Executive Summary

- **Phase 2 threat register (T-02-01..T-02-13):** 13 declared. **11 COVERED**, **1 PARTIAL** (T-02-04 — Trojan password also persisted in plaintext via `rawURI` field, not only Keychain), **1 ACCEPT** (T-02-03 repudiation — no audit log, deferred to Phase 12).
- **Phase 1 carry-forward invariants (R1, R6, R10, R11, KILL-01/02, SEC-03, SEC-05):** **0 regressions**. R1 inbound whitelist `{tun, direct}` intact; R6 `destinationAddresses` never assigned; KillSwitch single-mutator preserved; experimental APIs still rejected; templates have no `inbounds` and `experimental: {}` empty.
- **New attack surface flagged (4 issues, none blocking):** subscription URL fetch has no body-size limit / no redirect cap / no User-Agent normalization variance from device; `validate-r1-r6.sh` static check is silently broken for `KillSwitch.apply` due to signature change (T-02-08 mitigation works in code but the regression-guard is now blind); macOS main app retains `com.apple.security.network.server = true` from Phase 1 (not new, but worth re-evaluating now that R1 outbound surface expanded).
- **Mitigations cross-referenced to source:** every COVERED row cites file:line evidence; PARTIAL row explains residual gap; carry-forward grid shows the live invariant.

**Phase 2 may ship.** No BLOCKER findings; recommendations below are WARNINGS to address in Phase 3/Phase 7 as the surface grows.

---

## Phase 2 Threat Register — Verification Matrix

| Threat | Category | Disposition | Verdict | Evidence (file:line) |
|--------|----------|-------------|---------|----------------------|
| T-02-01 | Spoofing — malicious subscription/JSON operator | mitigate | **COVERED** | R1 chain enforced: `UniversalImportParser.parseSingBoxJSON` (`UniversalImportParser.swift:259-306`) **only** extracts entries from `outbounds[]` array (never copies `inbounds` / `experimental` / `dns` from operator JSON); the final config is **re-built** by `PoolBuilder.buildSingBoxJSON` (`PoolBuilder.swift:33-98`) with empty `experimental: {}` (line 85) and no `inbounds` key, then `ConfigImporter.importFromRawInput` step 6 calls `SingBoxConfigLoader.validate(json: poolJSON)` (`ConfigImporter.swift:175-179`). End-to-end test `test_variant3_invalidJSON_R1Rejection` (`IntegrationTests.swift:110-136`) confirms malicious `inbounds:[{type:socks}]` is rejected with `.forbiddenInboundType("socks")`. |
| T-02-02 | Tampering — subscription URL response in-flight | mitigate | **COVERED** | HTTPS-only enforced before fetch: `SubscriptionURLFetcher.fetch` rejects `http://` with `FetchError.nonHTTPS` (`SubscriptionURLFetcher.swift:60-62`); `JSONEndpointFetcher.fetch` does the same (`JSONEndpointFetcher.swift:28-30`); `UniversalImportParser.classify` only routes `https://` prefix to subscription fetcher (`UniversalImportParser.swift:87-91`). `URLSession.shared` uses system cert store and ATS defaults. Cert pinning deferred to DPI-08 / Phase 7 per plan. |
| T-02-03 | Repudiation — operator not attestable | **accept** | **ACCEPT** | Phase 2 has no audit log. Documented in plan row T-02-03; deferred to Phase 12 TELEM-04. No code expected — accepted risk. |
| T-02-04 | Information Disclosure — Trojan password / VLESS uuid in Keychain | mitigate | **PARTIAL** — see Finding F-02-04 below | KEYCHAIN path verified: `ConfigImporter.persistSupported` builds `payload` dict including Trojan `password` (line 235) and serialises it via `KeychainStore.save(secret: payloadData, tag: keychainTag)` (line 252); `KeychainStore.save` uses `kSecAttrAccessibleWhenUnlocked` (`KeychainStore.swift:42`). **HOWEVER**: the same `persistSupported` ALSO writes `rawURI: rawURI` (line 271) into the SwiftData `ServerConfig.rawURI` field for supported Trojan configs — and the Trojan URI userinfo contains the cleartext password (`TrojanURIParser.swift:63`). Therefore the password is duplicated in two stores: Keychain (correct) **and** plaintext SwiftData rawURI (gap). Plan T-02-04 row only acknowledges this for `unsupported` rows. |
| T-02-05 | Information Disclosure — Camera permission scope | mitigate | **COVERED** | `NSCameraUsageDescription` explicit Russian text "BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов" in `App/iOSApp/Info.plist` and `App/macOSApp/Info.plist`; macOS entitlement `com.apple.security.device.camera` only on main app (`App/macOSApp/BBTB-macOS.entitlements:24`), NOT on PacketTunnelExtension entitlements (verified absent in `PacketTunnelExtension-iOS.entitlements` and `PacketTunnelExtension-macOS.entitlements`). `AVCaptureMetadataOutput` accepts ONLY `[.qr]` types (`QRScannerViewController.swift:31, 108`); no frame storage / recording API used. |
| T-02-06 | DoS — Subscription URL fetch timeout | mitigate | **COVERED** | `URLRequest.timeoutInterval = 30` in both fetchers: `SubscriptionURLFetcher.swift:64` and `JSONEndpointFetcher.swift:32`. Progress overlay UI flagged via `MainScreenViewModel.importInProgress` (`MainScreenViewModel.swift:14, 94-95`). |
| T-02-07 | DoS — Pool > 50 servers (256 KB iOS limit) | mitigate | **COVERED** | `PoolBuilder.buildSingBoxJSON` truncates input via `Array(supportedConfigs.prefix(50))` (`PoolBuilder.swift:34`); guarded by `PoolError.noSupportedServers` if empty. |
| T-02-08 | EoP — Kill Switch toggle bypass | mitigate | **COVERED** (with W-02-08 warning below) | `KillSwitch.apply(to:enabled:)` is the only mutator of `includeAllNetworks` / `enforceRoutes` (`KillSwitch.swift:26-44`). `ConfigImporter.provisionTunnelProfile` (`ConfigImporter.swift:322-343`) is the single call site, reading the flag with safe default `?? true` (line 334). `SettingsViewModel` uses `@AppStorage("app.bbtb.killSwitchEnabled")` default `true` (`SettingsViewModel.swift:7`). D-14 banner state in `MainScreenViewModel.handleUserDefaultsChange` (`MainScreenViewModel.swift:146-154`). Tests: `KillSwitchTests.swift` covers both `enabled: true` and `enabled: false` paths (8 assertions). **Warning**: `scripts/validate-r1-r6.sh` static check `grep -q "KillSwitch.apply(to: proto)"` no longer matches the new parameterized call signature — see W-02-08. |
| T-02-09 | Spoofing — QR-code containing malicious URL | mitigate | **COVERED** | `UniversalImportParser.classify` (`UniversalImportParser.swift:85-139`) gates on `StubParsers.knownSchemes` (`StubParsers.swift:16`) — unknown schemes returned as `.unknown(snippet)` and throw `UniversalImportError.unknownInputFormat`. QR scanner pipes via `MainScreenView.fullScreenCover → viewModel.importFromQRString` (`MainScreenView.swift:63-71`) → `importer.importFromQRCode → UniversalImportParser.import` (`ConfigImporter.swift:107-109`). No shell / command interpolation present. |
| T-02-10 | Tampering — multi-protocol pool config injection | mitigate | **COVERED** | `SingBoxConfigLoader.validate` extended to verify urltest/selector `outbounds[].outbounds[]` references resolve to existing tags (`SingBoxConfigLoader.swift:119-130`); throws `.unresolvedOutboundRef(ref, in)`. Unit tests `SingBoxConfigLoaderTests.swift:158-170` exercise this. Operator-injected typo (e.g., `urltest.outbounds = ["evil-direct"]` with no such tag) → rejected before being applied. |
| T-02-11 | Information Disclosure — `allowInsecure=1` URI param bypass | mitigate | **COVERED** | `TrojanURIParser.parse` reads then discards `allowInsecure` (`TrojanURIParser.swift:77-79` — comment "parsed but explicitly ignored"); `security` is forced to `"tls"` constant in output (`TrojanURIParser.swift:115`); both templates have `"insecure": false` hardcoded (`SingBoxConfigTemplate.trojan-tcp.json:51`, `SingBoxConfigTemplate.trojan-ws.json:51`); `PoolBuilder.buildTrojanOutbound` writes `"insecure": false` hardcoded (`PoolBuilder.swift:138`). No code path can emit `insecure: true`. Test `test_allowInsecure_isIgnored` (`TrojanURIParserTests.swift:103-110`) asserts parser ignores the param. |
| T-02-12 | DoS — DNS through dead outbound | mitigate | **COVERED** | `PoolBuilder.dnsBlock(detour: finalTag)` parameterises DNS detour to `urltest-out` (≥2 servers case) or to the single-outbound tag (`PoolBuilder.swift:75, 156-191`). Phase 1 vless-reality template now uses `${DNS_DETOUR}` placeholder (`SingBoxConfigTemplate.vless-reality.json:13`), substituted by `VLESSReality/ConfigBuilder` to `vless-out` for single-server case. Same for Trojan templates (`SingBoxConfigTemplate.trojan-{tcp,ws}.json:13`). DoH `https://cloudflare-dns.com/dns-query` routed through whichever outbound is alive. |
| T-02-13 | Spoofing — V2Ray-style JSON confused with sing-box | mitigate | **COVERED** | `SubscriptionURLFetcher.detectFormat` distinguishes v2ray JSON by detecting `outbounds[].protocol` key absent `type` key (`SubscriptionURLFetcher.swift:92-96`), returns `.v2rayJSON(reason)`. `UniversalImportParser.classify` mirrors this check (`UniversalImportParser.swift:97-101`) and `import(...)` throws `UniversalImportError.v2rayJSONUnsupported` (line 61). Localized error key registered (W4.T2 per execution log). |

**Total per disposition:** 11 COVERED · 1 PARTIAL (T-02-04) · 1 ACCEPT (T-02-03) · 0 MISSING.

---

## Phase 1 Carry-Forward Invariants — Re-Verification

| Invariant | Phase 1 Source | Phase 2 Check | Status |
|-----------|----------------|---------------|--------|
| **R1 (SEC-01)** Inbound whitelist `{tun, direct}` | `SingBoxConfigLoader.swift:58-60` | Whitelist UNCHANGED in Phase 2 file at lines 58-60. `proxyOutboundTypes` set (lines 69-73) is **outbound** classification only — does NOT relax inbound whitelist. Trojan added as **outbound**, not inbound. | **NO REGRESSION** |
| **R1 (SEC-02)** No experimental APIs | `SingBoxConfigLoader.swift:93-104` | UNCHANGED — still throws on `clash_api`, `v2ray_api`, `cache_file.enabled=true`. All new templates have `"experimental": {}` empty (`SingBoxConfigTemplate.trojan-tcp.json:72`, `trojan-ws.json:79`, `vless-reality.json:76`). `PoolBuilder` emits `"experimental": [:]` (`PoolBuilder.swift:85`). Tests cover all 3 experimental keys (`SingBoxConfigLoaderTests.swift:109-123`). | **NO REGRESSION** |
| **R6** No `destinationAddresses` (P2P=false) | `TunnelSettings.swift:42-61` | UNCHANGED — single builder `makeR6Safe` still never assigns `destinationAddresses`; `validate-r1-r6.sh` static grep R6 check PASS. | **NO REGRESSION** |
| **R10** TUN inbound runtime expansion + DNS-hijack 1.13 | `SingBoxConfigLoader.expandConfigForTunnel` | UNCHANGED (`SingBoxConfigLoader.swift:136-231`); still injects `{type: tun, tag: tun-in, mtu, stack: gvisor}`, removes legacy `{type: dns}` outbound, rewrites `dns-out` outbound refs → `action: hijack-dns`, inserts `sniff` rule first. Idempotent. | **NO REGRESSION** |
| **R11** Phase 1 audit 37/37 closed | `01-SECURITY.md` | Phase 2 does not modify any of the 37 mitigations. Spot-checked: KeychainStore (`KeychainStore.swift:42`) still uses `kSecAttrAccessibleWhenUnlocked` (SEC-05); SocksProbe entitlements unchanged. | **NO REGRESSION** |
| **KILL-01** `includeAllNetworks=true` by default | `KillSwitch.swift:29` | When `enabled=true` (default), still `true`. When user toggles off, `false`. Default-true fail-safe preserved in 3 places: `SettingsViewModel.killSwitchEnabled = true` (`SettingsViewModel.swift:7`), `ConfigImporter` `?? true` (`ConfigImporter.swift:334`), `MainScreenViewModel.lastKillSwitchValue` initialiser `?? true` (`MainScreenViewModel.swift:26`). | **NO REGRESSION** |
| **KILL-02** Single mutator point | `KillSwitch.swift:26-44` | UNCHANGED — `KillSwitch.apply(to:enabled:)` is the only function setting `includeAllNetworks` / `enforceRoutes`; `ConfigImporter.provisionTunnelProfile` is the only call site. `grep -rn "includeAllNetworks" Packages/` returns ONLY `KillSwitch.swift:29, 35` and test files. | **NO REGRESSION** |
| **SEC-03** SocksProbe isolation | `Tools/SocksProbe/*.entitlements` | UNCHANGED. validate-r1-r6.sh SEC-03 grep PASS (verified in this audit). | **NO REGRESSION** |
| **SEC-05** Keychain `kSecAttrAccessibleWhenUnlocked` | `KeychainStore.swift:42` | UNCHANGED. validate-r1-r6.sh SEC-05 grep PASS. | **NO REGRESSION** |
| **W5-02** `.gitignore` covers build artifacts at repo root | `/.gitignore:7-10` | Spot-verified: `/.gitignore` still contains `build/`, `*.xcarchive`, `*.dSYM`, `*.ipa` — Phase 1 remediation intact. | **NO REGRESSION** |
| **No `print(` / `os_log(.debug` in production sources** | Phase 1 SEC | `grep -rn "print("` and `grep -rn "Logger\|os_log"` over all new Phase 2 sources (ConfigParser, Trojan, AppFeatures Settings/MainScreen) returns ZERO matches. New code does not log secrets — passwords, UUIDs, public keys never reach OSLog. | **NO REGRESSION** |

---

## New Phase 2 Findings

### F-02-04 — Trojan password persisted in plaintext SwiftData `rawURI` (PARTIAL)

**Category:** Information Disclosure (extension of T-02-04).

**Observation.** `ConfigImporter.persistSupported` (`ConfigImporter.swift:201-275`) saves the Trojan password into Keychain at line 252 (correct) but ALSO writes the original `rawURI` (which embeds the password in `trojan://<password>@host:...` userinfo per `TrojanURIParser.swift:62-64`) into `ServerConfig.rawURI: String?` at line 271. SwiftData persists to the App Group container at-rest, which on iOS is covered by Data Protection class `NSFileProtectionCompleteUntilFirstUserAuthentication` by default — strictly weaker than the Keychain entry's `kSecAttrAccessibleWhenUnlocked`.

The plan's T-02-04 row only acknowledges this for *unsupported* protocols (ss://, vmess://, …), arguing that user pasted them in plaintext anyway. The same reasoning applies in principle to Trojan, BUT:
1. There is no documented need for `rawURI` on **supported** rows (re-parse on handler upgrade is the use case for unsupported only — once the protocol is supported the Keychain payload is the canonical source).
2. Two copies of the password (Keychain + SwiftData) increase exposure if the SwiftData store leaks (e.g., backup exfiltration before first-unlock).

**Severity:** WARNING (not BLOCKER). Phase 2 still ships passwords in Keychain as the canonical store; the duplicate is an additional risk, not a regression vs Phase 1 (Phase 1 had no rawURI field at all).

**Recommendation for Phase 3.**
- Option A: For `isSupported = true` rows, persist `rawURI` with the userinfo password REDACTED (e.g., `trojan://<REDACTED>@host:port?...`). The pasteboard origin is preserved for diagnostics without the secret.
- Option B: For supported rows, leave `rawURI = nil`; populate only for unsupported rows. The re-parse-on-handler-upgrade flow (D-04) explicitly applies only to unsupported entries.
- Either way, add a unit test asserting that `ServerConfig.rawURI` for a Trojan row does not contain the cleartext password.

### W-02-08 — `validate-r1-r6.sh` KILL-01 grep silently broken

**Category:** Tooling / regression-guard failure (not application code).

**Observation.** `scripts/validate-r1-r6.sh` static check `grep -q KillSwitch.apply(to: proto) BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` returns FAIL because Phase 2 W0.T2 changed the call signature to `KillSwitch.apply(to: proto, enabled: killSwitchEnabled)` (`ConfigImporter.swift:335`). The mitigation is intact in code — this is a tooling defect: the static-check pattern needs updating.

**Severity:** WARNING. The runtime mitigation is verified by unit tests (`KillSwitchTests.swift`) and by reading the source directly in this audit. But the regression-detection script now passes "0 invariants failed (KILL-01 ConfigImporter grep)" only because the grep is being interpreted as a hard FAIL — and that FAIL is now hiding any future actual regression in the same area because the script exits early.

**Recommendation.** Update the grep to `grep -qE "KillSwitch\\.apply\\(to: proto"` (anchor only on the prefix, allow any trailing args). Or replace with a stricter call-site count: exactly one occurrence of `KillSwitch.apply(to:` across `Packages/AppFeatures/Sources/MainScreenFeature/`. Do this in Phase 3 W0.

### W-02-09 — Subscription/JSON fetchers have no body-size limit and no redirect cap

**Category:** Denial of Service / Information Disclosure (defence-in-depth gap).

**Observation.** `SubscriptionURLFetcher.fetch` and `JSONEndpointFetcher.fetch` (`SubscriptionURLFetcher.swift:59-76`, `JSONEndpointFetcher.swift:27-59`) call `URLSession.shared.data(for:)`. There is no `URLSessionTaskDelegate.urlSession(_:dataTask:didReceive:completionHandler:)` size cutoff and no `urlSession(_:task:willPerformHTTPRedirection:newRequest:completionHandler:)` cap. A malicious or compromised subscription endpoint can:
1. Stream gigabytes of response body, exhausting iOS memory pressure (force-kill the app — partial DoS).
2. Redirect indefinitely through attacker-controlled intermediaries (URLSession's default redirect cap is high but finite; still allows leaking the `BBTB/0.2` User-Agent + future-bearer-tokens to N hops).
3. Redirect to a non-HTTPS final URL — `SubscriptionURLFetcher` re-checks the scheme only on the initial URL, not on the redirected URL. `URLSession` default *will* upgrade by default but does not forbid redirect to http:// in all OS versions.

**Severity:** WARNING. T-02-02 declared mitigation is "HTTPS-only enforcement before fetch", which is true for the *initial* request; the residual gap is the post-redirect path. The 30 s `timeoutInterval` partially mitigates the body-stream DoS but doesn't bound total bytes.

**Recommendation for Phase 3 (defensive hardening before Phase 7 cert pinning):**
- Set `URLSessionConfiguration.timeoutIntervalForRequest = 30` and `timeoutIntervalForResource = 60`.
- Implement a `URLSessionDataDelegate` that aborts when received body exceeds e.g. 2 MB (subscription responses are normally < 64 KB).
- Implement a `willPerformHTTPRedirection` delegate that limits to N=5 redirects and rejects any non-HTTPS final URL.
- Cover with a unit test that simulates a redirect to `http://attacker/`.

### W-02-10 — macOS main app retains `com.apple.security.network.server = true`

**Category:** Information Disclosure (over-scoped entitlement carried from Phase 1).

**Observation.** `App/macOSApp/BBTB-macOS.entitlements:14` contains:
```xml
<key>com.apple.security.network.server</key>
<true/>
```
The main app does not bind any listening socket (R1-spirit — only the TUN inbound on the extension side is allowed). This entitlement is a Phase 1 carry-forward, not introduced in Phase 2, but it interacts with the new Phase 2 surface in that:
- The main app now imports `ConfigParser` (subscription fetcher, JSON endpoint fetcher) which only makes outbound HTTPS calls — these need `network.client` (granted), NOT `network.server`.
- The QR scanner uses `AVCaptureSession` — no networking entitlement needed.

**Severity:** WARNING. Not a Phase 2 regression. But Phase 2 expanded the main app's network surface (subscription fetch) without removing the orphan `network.server` entitlement, which would be the right time to do so.

**Recommendation for Phase 3 or Phase 10.** Remove `com.apple.security.network.server` from `App/macOSApp/BBTB-macOS.entitlements`. Confirm via build + smoke test that nothing in the main app actually listens on a socket. Phase 1 audit row T-01-W0-04 already validated extension entitlements; this is the macOS-main-app counterpart that was missed.

---

## Cross-Cutting Observations

### Pasteboard read is user-initiated (no auto-detect)
`ConfigImporter.importFromPasteboard` (`ConfigImporter.swift:100-105`) reads `UIPasteboard.general.string` / `NSPasteboard.general.string(forType:)` ONLY when called from the import button action (`MainScreenView.swift:106-108` and `EmptyStateCard` callback at `:122`). No automatic clipboard scan on app foregrounding. iOS pasteboard banner appears only on tap — consistent with Phase 1 W4-07 accepted disposition.

### QR-payload not used for command/shell interpolation
The scanned string flows: `QRScannerViewController.metadataOutput → onScan → MainScreenView.fullScreenCover → viewModel.importFromQRString → importer.importFromQRCode → UniversalImportParser.import`. At every hop the string is passed as a Swift `String` to a parser — never to a shell, never to `NSExpression`, never used in `WebView.evaluateJavaScript`, never used to construct a file path. The classification gate (`UniversalImportParser.classify`) rejects unknown schemes with `.unknownInputFormat` before any side-effect.

### V2Ray JSON rejection is enforced at both fetcher and parser
`SubscriptionURLFetcher.detectFormat` and `UniversalImportParser.classify` both detect the `outbounds[].protocol` (v2ray) vs `outbounds[].type` (sing-box) distinction. Defence-in-depth: even if a future call site bypassed the fetcher and pasted a v2ray JSON directly, the parser layer still rejects it.

### Trojan handler honours TLS strictness
- `TrojanURIParser` rejects `security != "tls"` with `notTLSSecurity` (file:line `TrojanURIParser.swift:71-75`) — no clear-text Trojan possible.
- `allowInsecure=1` is consumed and discarded (line 79); the final `ParsedTrojan.security` is hardcoded `"tls"` (line 115).
- Templates and `PoolBuilder` write `insecure: false` literally — no substitution path could produce `true`.

### KILL-03 toggle has correct fail-safe semantics
Reading `UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true` returns `true` when the key is missing, when it cannot be cast (corruption), and on first run. The toggle defaults to `true` in `@AppStorage` initialisation. There is no code path where `killSwitchEnabled` resolves to `false` due to a read failure.

---

## Unregistered Threat Flags

No `## Threat Flags` section is present in the Phase 2 execution log (`02-EXECUTION-LOG.md`) or in the wave SUMMARY files. The execution log mentions 5 minor deviations (W1.T3 test relaxation, W3.T1+T2 deferred unit tests, W3.T2 deinit removal, W4.T7 `@preconcurrency` annotation, W5.T1 fixture re-gen) — none of these introduce new attack surface. They are all internal refactoring or test infrastructure.

The 4 findings above (F-02-04, W-02-08, W-02-09, W-02-10) are raised by this audit independently — they were not flagged during execution.

---

## Audit Summary

| Metric | Count |
|--------|-------|
| Phase 2 threats declared | 13 |
| COVERED (mitigation verified in code) | 11 |
| PARTIAL (mitigation present but incomplete) | 1 (T-02-04) |
| ACCEPT (no mitigation expected, documented) | 1 (T-02-03) |
| MISSING (declared but absent) | 0 |
| Phase 1 invariants checked | 11 |
| Phase 1 invariants regressed | 0 |
| New findings raised by this audit | 4 (F-02-04, W-02-08, W-02-09, W-02-10) |
| BLOCKER findings | 0 |

### Recommended remediation timeline

| Finding | Severity | Target |
|---------|----------|--------|
| F-02-04 (Trojan password in rawURI) | WARNING | Phase 3 W0 — quick fix (1-3 LoC). |
| W-02-08 (validate-r1-r6.sh grep) | WARNING | Phase 3 W0 — tooling-only, 1-LoC regex update. |
| W-02-09 (fetcher body-size / redirect cap) | WARNING | Phase 3 W2 (subscription refresh) or Phase 7 (anti-DPI hardening). Whichever lands first. |
| W-02-10 (macOS network.server entitlement) | WARNING | Phase 10 — bundle with macOS-specific hardening pass (R5 enforceRoutes toggle is also Phase 10). |

### Mitigation pattern strength (Phase 2)

- **HTTPS-only enforcement (T-02-02):** strong on initial URL, partial on redirect chain (see W-02-09).
- **R1 outbound-only flow (T-02-01, T-02-10):** strong — parser strips operator JSON down to outbound entries, PoolBuilder rebuilds with empty experimental, validate runs at extension boundary. Integration test covers a real attacker scenario.
- **`allowInsecure` ignored (T-02-11):** strong — parser-side discard + template-side hardcode + builder-side hardcode = three independent layers all producing `insecure: false`.
- **Kill switch parameterisation (T-02-08):** strong on code side; tooling regression-guard is silently broken (W-02-08).
- **Camera scope (T-02-05):** strong — main-app-only entitlement, QR-only metadata type, no frame storage.
- **DoS protections (T-02-06, T-02-07):** moderate — 30 s timeout, 50-server cap, but no body-size cap (W-02-09).

---

## Notes / Escalations

1. **Phase 3 W0 should ship F-02-04 + W-02-08 fixes** as part of Wave 0 foundation hardening — both are tiny (< 10 LoC each) and remove a residual data-leak surface (F-02-04) + restore the regression-detection script (W-02-08).
2. **W-02-09 should be addressed jointly with DPI-08 cert pinning in Phase 7.** The fetcher-hardening (body-size, redirect cap, redirect-https check) is a natural prerequisite for cert pinning anyway.
3. **W-02-10 entitlement cleanup** is a Phase 10 / Phase 11 candidate — best done together with macOS R5 toggle and final dist-cert setup so the build is re-signed only once.
4. **No BLOCKER findings.** Phase 2 may transition to UAT and verify-work without further security work.

---

*Audit run: 2026-05-12 by gsd-security-auditor (Opus 4.7, 1M context).*
*Verification method: PLAN.md threat register grep + cross-reference against implementation source; Phase 1 invariants re-checked via direct read of `SingBoxConfigLoader.swift`, `TunnelSettings.swift`, `KillSwitch.swift`, `KeychainStore.swift`, entitlements files.*
*Implementation files NOT modified — audit is read-only per `<role>`.*
