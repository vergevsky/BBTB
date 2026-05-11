---
phase: 01-foundation
audit_date: 2026-05-11
auditor: gsd-security-auditor
asvs_level: 1
register_source: PLAN.md threat models W0..W5 (37 threats)
status: verified
threats_total: 37
threats_closed: 37
threats_open: 0
threats_accepted: 9
remediation_commits: []
---

# Phase 1 — Security Audit Report

## Scope

Verify each declared threat mitigation in `.planning/phases/01-foundation/01-W{0..5}-*-PLAN.md` `<threat_model>` blocks (37 threats total). Verification is by grep + UAT cross-evidence; implementation files are read-only.

## Outcome

**All 37 threats closed.** 27 mitigations verified in implementation; 9 accepted risks documented with rationale; T-01-W5-02 remediated in this audit cycle (`.gitignore` updated to cover repo-root build artifacts).

R1/R6/KILL invariants all have observable evidence: white-list config validation, single-point R6-safe settings builder, single-point KillSwitch wiring, plus static + runtime guards and production UAT confirmation.

---

## Closed Threats (36)

### Wave 0 — Bootstrap (5/5)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W0-01 | Tampering — xcconfig DEVELOPMENT_TEAM | mitigate | `BBTB/Config/Common.xcconfig:2` — `DEVELOPMENT_TEAM = UAN8W9Q82U` static; in git history |
| T-01-W0-02 | Information Disclosure — test-config.vless.local.txt in git | mitigate | `BBTB/.gitignore:26-28` — `Tests/Fixtures/*.local.txt` excluded; only `.template` allowed; `git ls-files` shows no `.local.txt` |
| T-01-W0-03 | Tampering — Bundle ID mismatch | accept | PLAN.md row 1368 (W0-T1 checkpoint + W0-T5 build failure); accept documented |
| T-01-W0-04 | Information Disclosure — entitlements over-scope | mitigate | Each `*.entitlements` reviewed: `BBTB/App/iOSApp/BBTB-iOS.entitlements` only `packet-tunnel-provider` + `allow-vpn` + group + keychain; `BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift:7-9` returns `code:-1` (reserved, not active) |
| T-01-W0-05 | DoS — dependency cycle | mitigate | `BBTB/Packages/VPNCore/Package.swift` — no `dependencies`; `BBTB/Packages/ProtocolEngine/Package.swift` — only Libbox; `BBTB/Packages/PacketTunnelKit/Package.swift:8-11` — depends on VPNCore + ProtocolEngine (downward only); `validate-r1-r6.sh` builds all 8 packages PASS |

### Wave 1 — Security Config (6/6)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W1-01 | Information Disclosure — sing-box SOCKS5 open on 127.0.0.1 | mitigate | Template `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/SingBoxConfigTemplate.vless-reality.json` — no `inbounds` key (UAT T1 PASS); `SingBoxConfigLoader.swift:53-72` — `allowedInboundTypes = {tun, direct}` white-list, throws `.forbiddenInboundType` for any other type |
| T-01-W1-02 | Information Disclosure — experimental gRPC outbounds | mitigate | Template has `"experimental": {}` (line 76); `SingBoxConfigLoader.swift:74-86` rejects non-empty `clash_api` / `v2ray_api` / `cache_file.enabled=true` |
| T-01-W1-03 | Tampering — malformed sing-box JSON → libbox panic | mitigate | `BaseSingBoxTunnel.swift:94-100` — `try SingBoxConfigLoader.validate(json:)` runs BEFORE `LibboxBootstrap.setup` and `LibboxNewCommandServer`; `SingBoxConfigError.malformedJSON` thrown on invalid JSON |
| T-01-W1-04 | Spoofing — VLESS URI with substituted outbound type | mitigate | `SingBoxConfigLoader.swift:92-94` — `outbounds.contains { type == "vless" }` required, throws `.noVLESSOutbound` otherwise |
| T-01-W1-05 | Information Disclosure — SocksProbe in App Group / Keychain | mitigate | `BBTB/Tools/SocksProbe/SocksProbe-iOS/SocksProbe-iOS.entitlements` — empty dict; `SocksProbe-macOS.entitlements` — only `app-sandbox` + `network.client`, no app-group / keychain; bundle ID `app.bbtb.tools.socksprobe.{ios,macos}` separate namespace (`BBTB/Tools/SocksProbe/Project.swift:37,56`); `validate-r1-r6.sh` SEC-03 PASS |
| T-01-W1-06 | Information Disclosure — SocksProbe macOS missing network.client | mitigate | `SocksProbe-macOS.entitlements:7-8` — `network.client = true`; no `network.server` |

### Wave 2 — KillSwitch + R6 (5/5)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W2-01 | Information Disclosure — utun IFF_POINTOPOINT | mitigate (partial — Apple platform limit) | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift:42-61` — `makeR6Safe()` is the only `NEPacketTunnelNetworkSettings` builder; never assigns `destinationAddresses` (confirmed via `grep -rE "destinationAddresses\\s*=" Sources/` returns 0 matches in `validate-r1-r6.sh` R6 check PASS); UAT T5 reports iOS 26 unconditionally sets IFF_POINTOPOINT regardless — assertion downgraded to warning in commit 74605f8 — **Apple platform limitation, code-side mitigation present** |
| T-01-W2-02 | Tampering — regression adds destinationAddresses via PR | mitigate | `validate-r1-r6.sh:36-38` — grep guard; runs in every `/gsd-verify-work` and CI; `TunnelSettingsTests.swift:12` references the rule |
| T-01-W2-03 | DoS — traffic leak on tunnel drop | mitigate | `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:19` — `proto.includeAllNetworks = true`; tests `KillSwitchTests.swift:10,38` assert; `validate-r1-r6.sh` KILL-01 PASS; UAT T3 PASS |
| T-01-W2-04 | Information Disclosure — DNS leak | mitigate | `TunnelSettings.swift:56` — `dns.matchDomains = [""]`; `KillSwitch.swift:24` — `proto.enforceRoutes = !platformShouldDisableEnforceRoutes()` (= true in Phase 1); test `TunnelSettingsTests.swift:40` asserts matchDomains |
| T-01-W2-05 | Information Disclosure — iOS 16.1+ Apple traffic leak via includeAllNetworks | accept | PLAN.md row 633: "Системное ограничение Apple; задокументировано". Documented in `.planning/phases/01-foundation/01-RESEARCH.md:277,982`. **Minor gap**: PLAN.md cited `wiki/security-gaps.md` but the leak text is in `01-RESEARCH.md`, not yet promoted to wiki. Not a blocker — accept stands |

### Wave 3 — Base Tunnel (7/7)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W3-01 | Tampering — malicious sing-box config via providerConfiguration | mitigate | `BaseSingBoxTunnel.swift:94-100` validates BEFORE `LibboxBootstrap.setup` (line 104) and `LibboxNewCommandServer` (line 124); plus post-expand re-validation lines 170-176 |
| T-01-W3-02 | Information Disclosure — regression adds inbounds to template | mitigate | `validate-r1-r6.sh:30-31` grep template guard; UAT T1 PASS; `SingBoxConfigLoaderTests.swift` includes `test_templateLoadsAndValidates` |
| T-01-W3-03 | Information Disclosure — libbox sets destinationAddresses bypassing TunnelSettings | mitigate | `ExtensionPlatformInterface.swift:93-125` builds settings via `TunnelSettings.makeR6Safe` and invokes `InterfaceFlagsInspector.assertNoPointToPointOnUtun()` post-set; libbox never has direct access to settings object |
| T-01-W3-04 | Spoofing — App Group container compromise | accept | PLAN.md row 1095: iOS sandbox protects between bundles; in-team access only |
| T-01-W3-05 | Tampering — libbox.xcframework supply chain | accept (Phase 1) | `BBTB/Vendored/README.md:7` — pinned `v1.13.11`; `BBTB/.gitignore:23` excludes `Vendored/libbox.xcframework/` (binary not in git); Phase 12 will add codesign verification |
| T-01-W3-06 | DoS — extension crash from libbox panic / Go runtime | mitigate | `BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:15` — `MXMetricManagerSubscriber`; install called in `BBTB/App/iOSApp/BBTB_iOSApp.swift:18` and `BBTB_macOSApp.swift:18`; `didReceive(MXDiagnosticPayload)` writes JSON to App Group |
| T-01-W3-07 | Information Disclosure — OSLog secrets in Console.app | mitigate | `TunnelLogger.swift:7-12` — `Logger(subsystem: "app.bbtb.tunnel", ...)`; secret paths use `privacy: .public` only for non-secret data (basePath, libbox-emitted messages — see `ExtensionPlatformInterface.swift:391,428` + `BaseSingBoxTunnel.swift:110,160`); secret fields (UUID, publicKey) NEVER passed to logger; UAT T6 PASS (Release mode shows no debug entries) |

### Wave 4 — UI Import (8/8)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W4-01 | Tampering — substituted vless:// in pasteboard | mitigate | UI requires explicit tap (`ImportFromClipboardButton`); `VLESSURIParser.swift:62-64` refuses if `security != "reality"`, throws `.notRealityProtocol` |
| T-01-W4-02 | Information Disclosure — secrets in OSLog | mitigate | `ConfigImporter.swift:88-104` — payload Keychain-saved; never logged; `KeychainStore.swift:11-17` errors carry only OSStatus, no data; `TunnelLogger` privacy audit (W3-07) covers extension side |
| T-01-W4-03 | Information Disclosure — SwiftData ServerConfig host+name | mitigate | `ServerConfig` (in VPNCore) holds host + name + keychainTag only; secrets via `KeychainStore.swift` (SEC-05: `kSecAttrAccessibleWhenUnlocked`); `validate-r1-r6.sh` SEC-05 PASS |
| T-01-W4-04 | Spoofing — remarks=«Госуслуги» social engineering | accept | PLAN.md row 1801: UX decision Phase 1, user copied URI themselves |
| T-01-W4-05 | Tampering — missing KillSwitch.apply wiring | mitigate | `ConfigImporter.swift:165` — `KillSwitch.apply(to: proto)`; `validate-r1-r6.sh:52-53` KILL-01 grep PASS |
| T-01-W4-06 | DoS — saveToPreferences hangs UI in .connecting | mitigate | `TunnelController.swift:25-37` — 30s polling loop with terminal `throw NSError(code: -3, "Connection timed out after 30s")` |
| T-01-W4-07 | Information Disclosure — iOS pasteboard banner UX noise | accept | PLAN.md row 1804: Apple-OS notification, Phase 11 will switch to UIPasteControl |
| T-01-W4-08 | Tampering — ConfigBuilder regression returns JSON with inbounds | mitigate | `BBTB/Packages/Protocols/VLESSReality/Tests/VLESSRealityTests/ConfigBuilderTests.swift:7-34` — `test_buildSingBoxJSON_filled_passesValidate` asserts `SingBoxConfigLoader.validate(json:)` succeeds; runs in `validate-r1-r6.sh` VLESSReality package PASS |

### Wave 5 — Crash Reporter + Distribution (6/6)

| Threat ID | Category | Disposition | Evidence |
|-----------|----------|-------------|----------|
| T-01-W5-01 | Information Disclosure — crash payload exposes secret-handling code | accept | PLAN.md row 939: Apple processes crash payloads in Phase 1; UI send deferred to Phase 12 (TELEM-03/04) |
| T-01-W5-02 | Information Disclosure — TestFlight archive committed via `git add .` | mitigate | Remediated 2026-05-11 (audit cycle): root `/.gitignore:7-10` adds `build/`, `*.xcarchive`, `*.dSYM`, `*.ipa`; `git check-ignore -v build/BBTB-iOS.xcarchive` → matches `.gitignore:7:build/`; existing `BBTB/.gitignore:6` still covers `BBTB/build/` for the alt-path scenario |
| T-01-W5-03 | Tampering — validate-r1-r6.sh regression | mitigate | Script verified executable and exit-0; output ends with "✓ ALL STATIC INVARIANTS + UNIT TESTS PASS"; manual policy runs before each `/gsd-verify-work`; UAT T1 PASS |
| T-01-W5-04 | Information Disclosure — test-config.vless.local.txt in git | mitigate | `BBTB/.gitignore:26-28` — `Tests/Fixtures/*.local.txt` excluded; only `.template` allowed |
| T-01-W5-05 | Spoofing — developer fakes manual smoke screenshot | accept | PLAN.md row 943: solo developer workflow; no 3rd-party review |
| T-01-W5-06 | Information Disclosure — api.ipify.org screenshots show server IP | accept | PLAN.md row 944: server IP is public information (any `curl` sees it); no UUID/keys in screenshot |

---

## Open Threats (0)

None.

### Remediation history (this audit)

| Date | Threat | Action | Verification |
|------|--------|--------|--------------|
| 2026-05-11 | T-01-W5-02 | Added `build/`, `*.xcarchive`, `*.dSYM`, `*.ipa` to repo-root `/.gitignore:7-10` | `git check-ignore -v build/BBTB-iOS.xcarchive` → `.gitignore:7:build/`; `git status` no longer lists `build/` as untracked |

---

## Accepted Risks Log (9)

| Threat ID | Disposition | Rationale | Cited in PLAN.md |
|-----------|-------------|-----------|------------------|
| T-01-W0-03 | accept | Bundle ID mismatch caught by W0-T1 + W0-T5 build failure | W0 row 1368 |
| T-01-W2-05 | accept | iOS 16.1+ Apple traffic leak via includeAllNetworks — Apple platform limitation | W2 row 633 (additional doc in `01-RESEARCH.md:277,982`) |
| T-01-W3-04 | accept | App Group container compromise — iOS sandbox between-bundle protection | W3 row 1095 |
| T-01-W3-05 | accept | libbox.xcframework supply chain — pinned v1.13.11; Phase 12 adds codesign | W3 row 1096 |
| T-01-W4-04 | accept | remarks social engineering — UX decision (user copied URI) | W4 row 1801 |
| T-01-W4-07 | accept | iOS pasteboard banner — Apple-OS notification, Phase 11 UIPasteControl | W4 row 1804 |
| T-01-W5-01 | accept | Crash payload stack-trace exposure — Phase 1 only writes to App Group | W5 row 939 |
| T-01-W5-05 | accept | Manual smoke screenshot spoofing — solo developer trust model | W5 row 943 |
| T-01-W5-06 | accept | api.ipify.org screenshots show server IP — server IP is public | W5 row 944 |

---

## UAT Cross-Evidence

| UAT Test | Threats Covered | Result |
|----------|-----------------|--------|
| T1 — `validate-r1-r6.sh` exit 0 | T-01-W5-03; static covers W1-01..06, W2-01..04, W4-05, W5-04 | PASS |
| T2 — VLESS+Reality import + connect + IP swap iPhone | W3-01, W4-01, W4-08, W4-05 (end-to-end correctness) | PASS |
| T3 — Kill switch blocks on tunnel drop | T-01-W2-03 (KILL-02) | PASS |
| T4 — SocksProbe R1 (BBTB extension opens 0 ports) | T-01-W1-01 (production check) | PASS — port 1080 belonged to unrelated process |
| T5 — R6 IFF_POINTOPOINT | T-01-W2-01 production check | SKIPPED (N/A on iOS 26 — Apple unconditionally sets flag; assertion downgraded in commit 74605f8) — code-side mitigation present |
| T6 — Release-mode console no debug | T-01-W3-07 | PASS |
| T7 — DIST-01 archive / DIST-02 export | (no direct threat — Phase 12 prerequisite) | PARTIAL (archive ✓, export blocked-by-credentials) |

---

## Unregistered Flags

No `## Threat Flags` section found in any wave SUMMARY.md (W3.1 cleanup SUMMARY does not declare new attack surface; it removed code rather than adding it). No unregistered surface detected.

---

## Audit Summary

| Metric | Count |
|--------|-------|
| Total threats | 37 |
| Closed (mitigate verified + accept documented) | 37 |
| Open | 0 |
| Accepted (sub-bucket of Closed) | 9 |
| Mitigations remediated in this cycle | 1 (T-01-W5-02 — `.gitignore`) |

### Mitigation pattern strength

- R1 (no listen-on-localhost): **strong** — white-list `{tun, direct}` (default-deny), template-side + runtime validate + post-expand re-validate, plus production SocksProbe spot-check.
- R6 (no IFF_POINTOPOINT): **strong on code side, partial on OS side** — code never sets `destinationAddresses`; iOS 26 unconditionally sets the flag (Apple-platform limit, accepted per commit 74605f8 + UAT T5).
- KILL-01/02: **strong** — single point in `KillSwitch.apply`, called once in `ConfigImporter`, asserted by tests + UAT T3.
- SEC-03 (SocksProbe isolation): **strong** — entitlements verified absent, bundle namespace separate.
- SEC-05 (Keychain): **strong** — `kSecAttrAccessibleWhenUnlocked` + access-group computed from team prefix.

### Notes / escalations

1. **RESOLVED** — `build/` at repo root added to `/.gitignore` in this audit cycle. Verified with `git check-ignore`. No outstanding blocker.
2. **MINOR (follow-up)** — W2-05 accept disposition cites `wiki/security-gaps.md` but the iOS 16.1+ Apple-leak text actually lives in `.planning/phases/01-foundation/01-RESEARCH.md:277,982`. Promote to `wiki/security-gaps.md` during Phase 11 FAQ work. Not blocking phase advancement.
3. **OBSERVATION** — UAT T7 DIST-02 export blocked-by-credentials is **not** a Phase 1 security gap — it is a Phase 12 prerequisite (Apple Distribution cert + App Store profile creation). Tracked separately in `memory/project_phase12_distribution_creds_prerequisite.md`.
