---
phase: 4
slug: protocol-expansion
status: complete
nyquist_compliant: true
wave_0_complete: true
created: 2026-05-12
signed_off: 2026-05-12
---

# Phase 4 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | XCTest (Swift Package Manager) |
| **Config file** | BBTB/Packages/AppFeatures/Package.swift |
| **Quick run command** | `swift test --filter ConfigParserTests` |
| **Full suite command** | `swift test` |
| **Estimated runtime** | ~30 seconds |

---

## Sampling Rate

- **After every task commit:** Run `swift test --filter ConfigParserTests`
- **After every plan wave:** Run `swift test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 0 | PROTO-03 | — | VLESSURIParser stub created | unit | `swift test --filter VLESSURIParserTests` | ✅ | ✅ green |
| 04-01-02 | 01 | 0 | PROTO-04 | — | ShadowsocksURIParser stub created | unit | `swift test --filter ShadowsocksURIParserTests` | ✅ | ✅ green |
| 04-01-03 | 01 | 0 | PROTO-05 | — | Hysteria2URIParser stub created | unit | `swift test --filter Hysteria2URIParserTests` | ✅ | ✅ green |
| 04-02-01 | 02 | 1 | PROTO-03 | — | VLESSURIParser parses vless:// with security=tls | unit | `swift test --filter VLESSURIParserTests` | ✅ | ✅ green |
| 04-02-02 | 02 | 1 | PROTO-04 | — | SS dual-path decode: 2022-blake3 direct + legacy base64 | unit | `swift test --filter ShadowsocksURIParserTests` | ✅ | ✅ green |
| 04-02-03 | 02 | 1 | PROTO-05 | D-08 | Hysteria2 insecure=1 maps to tls.insecure:true only for hy2:// | unit | `swift test --filter Hysteria2URIParserTests` | ✅ | ✅ green |
| 04-03-01 | 03 | 2 | PROTO-03 | — | VLESSWithoutRealityProtocol builds valid sing-box config | unit | `swift test --filter VLESSWithoutRealityTests` | ✅ | ✅ green |
| 04-03-02 | 03 | 2 | PROTO-04 | — | ShadowsocksProtocol builds valid ss outbound for all SS methods | unit | `swift test --filter ShadowsocksProtocolTests` | ✅ | ✅ green |
| 04-03-03 | 03 | 2 | PROTO-05 | D-08 | Hysteria2Protocol: only hy2:// sets tls.insecure=true | unit | `swift test --filter Hysteria2ProtocolTests` | ✅ | ✅ green |
| 04-04-01 | 04 | 3 | IMP-05 | — | ClashYAMLParser extracts proxies array, maps to AnyParsedConfig | unit | `swift test --filter ClashYAMLParserTests` | ✅ | ✅ green |
| 04-04-02 | 04 | 3 | IMP-05 | — | Outline access keys (SIP002 ss://) parsed correctly | unit | `swift test --filter ShadowsocksURIParserTests` | ✅ | ✅ green |
| 04-04-03 | 04 | 3 | IMP-04 | — | UniversalImportParser routes all 5 URI schemes | unit | `swift test --filter UniversalImportParserTests` | ✅ | ✅ green |
| 04-05-01 | 05 | 4 | IMP-04 | D-14 | isSupported auto-upgrade triggers on app launch | integration | `swift test --filter IsSupportedUpgradeTests` | ✅ | ✅ green |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `VLESSURIParserTests.swift` — stubs for PROTO-03 (VLESS+TLS without Reality)
- [x] `ShadowsocksURIParserTests.swift` — stubs for PROTO-04 (SS-2022 + legacy)
- [x] `Hysteria2URIParserTests.swift` — stubs for PROTO-05 (Hysteria2 URI)
- [x] `ClashYAMLParserTests.swift` — stubs for IMP-05 (Clash YAML)
- [x] Add `Yams 6.2.1` to Package.swift dependencies

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| VLESS+TLS connects on real server | PROTO-03 | Requires live server | Import vless:// URI with security=tls, connect, verify IP changes |
| SS-2022 connects (aes-128-gcm) | PROTO-04 | Requires Outline server | Import Outline access key, connect, verify IP |
| Hysteria2 connects | PROTO-05 | Requires hy2 server + UDP QUIC | Import hy2:// URI, connect on iPhone, verify IP changes |
| isSupported auto-upgrade | IMP-04 | Requires pre-existing isSupported=false rows | Import Hy2 config, delete app, reinstall, verify auto-upgrade runs |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 30s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** ✅ 2026-05-12 — 151/151 ConfigParser + 49/49 AppFeatures PASS
