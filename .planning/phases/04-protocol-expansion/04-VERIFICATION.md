---
phase: 04-protocol-expansion
verified: 2026-05-12T21:00:00Z
status: passed
score: 10/10 must-haves verified
overrides_applied: 0
re_verification: false
gaps: []
human_verification: []
---

# Phase 4: Protocol Expansion Verification Report

**Phase Goal:** Add VLESS+TLS, Shadowsocks-2022, Hysteria2 protocols and Clash YAML/Outline subscription format. Users can import vless+tls / ss / hy2 URIs, Outline access keys, and Clash YAML. Previously-imported unsupported servers auto-upgrade on next foreground.
**Verified:** 2026-05-12T21:00:00Z
**Status:** PASSED
**Re-verification:** No — initial verification

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `AnyParsedConfig` has 5 cases including .vlessTLS, .shadowsocks, .hysteria2 | VERIFIED | `ImportedServer.swift` lines 14–20: enum has exactly 5 cases |
| 2 | VLESS URI parser branches to .vlessTLS on security=tls (without pbk) | VERIFIED | `VLESSURIParser.swift` lines 108–141: TLS branch returns `.vlessTLS` |
| 3 | Shadowsocks parser handles SIP002 (base64) and SIP022 (percent-encoded) dual-path | VERIFIED | `ShadowsocksURIParser.swift` lines 112–138: two-path `decodeUserinfo` with method whitelist |
| 4 | Hysteria2 parser handles hy2:// and hysteria2:// schemes, allowInsecure from 3 synonyms | VERIFIED | `Hysteria2URIParser.swift` lines 62–64 (dual scheme), lines 83–85 (3-synonym allowInsecure) |
| 5 | ClashYAML parser extracts proxies section, maps ss/trojan/vless/hysteria2/vmess | VERIFIED | `ClashYAMLParser.swift` lines 38–89: full switch on type, Yams.load, per-proxy error isolation |
| 6 | UniversalImportParser routes ss://, hy2://, hysteria2://, and Clash YAML content | VERIFIED | `UniversalImportParser.swift` lines 211–286 (ss, hy2/hysteria2 cases), lines 313–338 (ClashYAML) |
| 7 | `runIsSupportedUpgrade()` throttled to 5-min via UserDefaults, clears rawURI on success | VERIFIED | `ConfigImporter.swift` lines 757–798: `bbtb.lastIsSupportedUpgrade` key, 300s guard, `live.rawURI = nil` line 791 |
| 8 | R1 invariant: only Hysteria2 sets tls.insecure=true; VLESSTLS and SS templates have no insecure=true | VERIFIED | `SingBoxConfigTemplate.vless-tls.json` line 52: `"insecure": false` hardcoded; `SingBoxConfigTemplate.shadowsocks.json`: no TLS block at all; `SingBoxConfigTemplate.hysteria2.json` line 50: `${ALLOW_INSECURE}` placeholder only here |
| 9 | ProtocolRegistry registers 3 new handlers in both iOS and macOS app entry points | VERIFIED | `BBTB_iOSApp.swift` lines 39–41, `BBTB_macOSApp.swift` lines 27–29: VLESSTLSHandler, ShadowsocksHandler, Hysteria2Handler all registered |
| 10 | VLESSTLS/Shadowsocks/Hysteria2 packages declared in Project.swift localPackages and target deps | VERIFIED | `Project.swift` lines 41–43 (localPackages), lines 88–90 (target deps) |

**Score:** 10/10 truths verified

---

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `ConfigParser/Sources/ConfigParser/ImportedServer.swift` | AnyParsedConfig 5 cases | VERIFIED | Lines 14–20: vlessReality, vlessTLS, trojan, shadowsocks, hysteria2 |
| `ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` | Reality/TLS branch, returns AnyParsedConfig | VERIFIED | Dual branch; TLS branch fully implemented |
| `ConfigParser/Sources/ConfigParser/ShadowsocksURIParser.swift` | SIP002 + SIP022 dual-path | VERIFIED | Whitelist of 8 methods, 2-path decodeUserinfo |
| `ConfigParser/Sources/ConfigParser/Hysteria2URIParser.swift` | hy2:// + hysteria2://, allowInsecure, multi-port reject | VERIFIED | All three D-08 synonyms, pre-scan multi-port reject |
| `ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift` | Yams.load, proxies section | VERIFIED | Full per-type mapping, per-proxy error isolation |
| `ConfigParser/Sources/ConfigParser/UniversalImportParser.swift` | Routes all 5 URI schemes + Clash YAML | VERIFIED | ss, hy2, hysteria2 cases + clashYAML classification |
| `Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift` | R1: insecure=false hardcoded | VERIFIED | No allowInsecure field in VLESSTLSInputs by design |
| `Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json` | insecure: false | VERIFIED | Line 52 hardcoded false |
| `Protocols/Shadowsocks/Sources/Shadowsocks/ConfigBuilder.swift` | No TLS block | VERIFIED | Template has no TLS field |
| `Protocols/Shadowsocks/Sources/Shadowsocks/Resources/SingBoxConfigTemplate.shadowsocks.json` | No TLS block | VERIFIED | Outbound has method/password/network only |
| `Protocols/Hysteria2/Sources/Hysteria2/ConfigBuilder.swift` | ${ALLOW_INSECURE} placeholder, D-08 EXCEPTION only | VERIFIED | Lines 91–95: only Hysteria2 builder touches insecure |
| `Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json` | insecure: ${ALLOW_INSECURE} | VERIFIED | Line 50: parameterized placeholder |
| `AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` | 5-case exhaustive switches + runIsSupportedUpgrade() | VERIFIED | Exhaustive switches in buildServerConfig/reparseFromKeychain/protocolIDString; runIsSupportedUpgrade at lines 757–798 |
| `App/iOSApp/BBTB_iOSApp.swift` | Register 3 new handlers + scenePhase hook | VERIFIED | Lines 39–41 (handlers), lines 82–86 (scenePhase .active triggers upgrade) |
| `App/macOSApp/BBTB_macOSApp.swift` | Register 3 new handlers + scenePhase hook | VERIFIED | Lines 27–29 (handlers), lines 84–88 (scenePhase hook) |
| `BBTB/Project.swift` | VLESSTLS/Shadowsocks/Hysteria2 in localPackages + target deps | VERIFIED | Lines 41–43 and 88–90 |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `UniversalImportParser` | `ShadowsocksURIParser` | `parseSingleURI` case "ss" | WIRED | Line 215: `ShadowsocksURIParser.parse(trimmed)` |
| `UniversalImportParser` | `Hysteria2URIParser` | `parseSingleURI` case "hy2","hysteria2" | WIRED | Line 251: `Hysteria2URIParser.parse(trimmed)` |
| `UniversalImportParser` | `ClashYAMLParser` | `parseClashYAML` | WIRED | Line 316: `ClashYAMLParser.parse(body)` |
| `ConfigImporter` | `PoolBuilder.buildSingBoxJSON` | `importFromRawInput` | WIRED | Line 243: `PoolBuilder.buildSingBoxJSON(from: supportedParsed)` — includes new 3 protocols via exhaustive switch |
| `ConfigImporter` | `runIsSupportedUpgrade` | `scenePhase == .active` in App | WIRED | iOS line 84: `Task { await viewModel.importer.runIsSupportedUpgrade() }` |
| `PoolBuilder` | `buildHysteria2Outbound` | `buildSingBoxJSON` switch `.hysteria2` | WIRED | Lines 57–60: `buildHysteria2Outbound(parsed: h, tag: tag)` |
| `PoolBuilder` | `buildShadowsocksOutbound` | `buildSingBoxJSON` switch `.shadowsocks` | WIRED | Lines 53–56: `buildShadowsocksOutbound(parsed: s, tag: tag)` |
| `PoolBuilder` | `buildVLESSTLSOutbound` | `buildSingBoxJSON` switch `.vlessTLS` | WIRED | Lines 49–52: `buildVLESSTLSOutbound(parsed: v, tag: tag)` |
| `runIsSupportedUpgrade` | `live.rawURI = nil` | after successful upgrade | WIRED | Line 791: `live.rawURI = nil  // T-02-04 invariant` |
| `runIsSupportedUpgrade` | `UserDefaults` throttle key | `bbtb.lastIsSupportedUpgrade` | WIRED | Lines 759–761: 300s guard; line 796: `UserDefaults.standard.set(now, forKey: throttleKey)` |

### Security Invariants

| Invariant | Status | Evidence |
|-----------|--------|----------|
| **R1**: tls.insecure=false hardcoded for VLESS+TLS | VERIFIED | Template line 52: `"insecure": false`; PoolBuilder line 149: `"insecure": false` comment "R1 invariant" |
| **R1**: Shadowsocks has no TLS block | VERIFIED | Template has no TLS key; `buildShadowsocksOutbound` returns method/password/network only |
| **D-08**: Only Hysteria2 sets allowInsecure=true | VERIFIED | `ParsedShadowsocks`, `ParsedVLESSTLS`, `ParsedTrojan` have no `allowInsecure` field by design (type-level enforcement); only `ParsedHysteria2` has it; PoolBuilder comment block + `test_nonHy2_outbounds_neverHaveInsecureTrue` test |
| **T-02-04**: rawURI=nil after successful auto-upgrade | VERIFIED | `ConfigImporter.swift` line 791: `live.rawURI = nil`; `IsSupportedUpgradeTests` line 80: `XCTAssertNil(cfg.rawURI, "rawURI must be cleared after upgrade (T-02-04 invariant)")` |
| **D-14**: 5-min throttle via UserDefaults | VERIFIED | `ConfigImporter.swift` lines 759–761: `guard now - last >= 300 else { return }`; `test_throttlingPreventsSecondRun` PASS |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| ConfigParser 151 tests pass, 0 failures | `swift test` in ConfigParser | 151 tests, 0 failures | PASS |
| ClashYAMLParser tests (5) pass | suite ClashYAMLParserTests | 5/5 pass | PASS |
| Hysteria2URIParserTests (12) pass | suite Hysteria2URIParserTests | 12/12 pass | PASS |
| ShadowsocksURIParserTests (7) pass | suite ShadowsocksURIParserTests | 7/7 pass | PASS |
| PoolBuilderTests (29) including test_nonHy2_outbounds_neverHaveInsecureTrue | suite PoolBuilderTests | 29/29 pass | PASS |
| AppFeatures 49 tests pass, 0 failures | `swift test` in AppFeatures | 49 tests, 0 failures | PASS |
| IsSupportedUpgradeTests (5) pass | suite IsSupportedUpgradeTests | 5/5 pass (throttle, rawURI=nil, SS upgrade, Hy2 upgrade, skip without rawURI) | PASS |
| ConfigImporterAnyParsedConfigTests (7) pass | suite ConfigImporterAnyParsedConfigTests | 7/7 pass (shadowsocks roundtrip, vlessTLS roundtrip, hysteria2 buildServerConfig) | PASS |

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| PROTO-03 | VLESS+TLS without Reality — parsed, persisted, sing-box outbound built | SATISFIED | VLESSURIParser TLS branch; PoolBuilder.buildVLESSTLSOutbound; template with insecure:false; Keychain roundtrip test passes |
| PROTO-04 | Shadowsocks-2022 + legacy SIP002 — dual-path parser, correct outbound (no TLS block) | SATISFIED | ShadowsocksURIParser dual-path; no TLS block in template or PoolBuilder outbound |
| PROTO-05 | Hysteria2 — hy2:// + hysteria2:// schemes, allowInsecure R1 exception (D-08) | SATISFIED | Hysteria2URIParser dual scheme; 3-synonym allowInsecure; D-08 exception type-enforced |
| IMP-04 | isSupported auto-upgrade — runIsSupportedUpgrade() with 5-min throttle + rawURI cleared | SATISFIED | ConfigImporter.runIsSupportedUpgrade lines 757–798; T-02-04 enforced; scenePhase hook wired |
| IMP-05 | Clash YAML subscription — ClashYAMLParser extracts proxies array, UniversalImportParser routes | SATISFIED | ClashYAMLParser.parse + UniversalImportParser.parseClashYAML; classification detects 6 Clash YAML markers |

### Anti-Patterns Found

No blockers or warnings found. Reviewed all Phase 4 files. Notable code quality observations:

- `TODO Phase 5` comment in `BBTB_iOSApp.swift` line 28 for sing-box log export cleanup — references Phase 5 explicitly, not a Phase 4 issue
- No TBD/FIXME/XXX markers in any Phase 4 files

### Human Verification Required

None — all must-haves are programmatically verifiable and tests pass.

---

## Gaps Summary

No gaps. All 10 observable truths are VERIFIED by direct code inspection and passing test suites.

---

_Verified: 2026-05-12T21:00:00Z_
_Verifier: Claude (gsd-verifier)_
