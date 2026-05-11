---
phase: 02-trojan-import-flow
verified: 2026-05-12T02:00:00Z
status: human_needed
verdict: ACHIEVED (pending device UAT)
score: 8/8 automated success criteria verified
phase1_invariants_regressions: 0
tests_run: 147+ across 7 packages
gaps: []
human_verification:
  - test: "T1 — Subscription URL import (Variant 1)"
    expected: "Pasted https://vpn.vergevsky.ru/sub/... → progress overlay → alert with imported count → idle layout"
    why_human: "Requires live subscription endpoint, real iPhone, real network — cannot run in unit test."
  - test: "T2 — Multi-line URI block import (Variant 2)"
    expected: "Pasted 6-line block (4 VLESS + 2 Trojan) → alert «Добавлено: 6.» → SwiftData has 6 rows"
    why_human: "Live UI flow, real pasteboard, SwiftData visual inspection."
  - test: "T3 — JSON endpoint import (Variant 3)"
    expected: "Pasted JSON endpoint URL → fetch → parse → import success"
    why_human: "Requires live JSON endpoint, real network."
  - test: "T4 — QR-code import + permission flow"
    expected: "qrencode-generated QR → camera prompt → scan → alert success. Permission denied subtest also runs."
    why_human: "Real camera, real iOS permission dialog, no simulator camera."
  - test: "T5 — Connect & IP change verification"
    expected: "Power button → .connected state → api.ipify.org returns server IP not home IP"
    why_human: "Real VPN tunnel, real device, real network."
  - test: "T6 — urltest failover (PROTO-10)"
    expected: "Stop sing-box on VLESS server → within 2 minutes Trojan outbound takes over → IP changes"
    why_human: "Most-critical real-device behavioral test. Requires live multi-server pool and ability to kill one server."
  - test: "T7/T8 — Kill Switch OFF/ON round-trip"
    expected: "Toggle in Settings → iOS Settings → VPN → BBTB → Include All Networks reflects state"
    why_human: "iOS Settings.app inspection (can't be programmatically asserted)."
  - test: "T9 — Toggle KillSwitch during active tunnel → banner"
    expected: "Connected → toggle KillSwitch → ReconnectBanner appears on top bar; dismiss → reconnect applies change"
    why_human: "UI rendering verification during live tunnel state."
known_caveats:
  - "macOS Debug build fails with signing cert error (Phase 1 DIST-02 known gap, unrelated to Phase 2)."
  - "Security audit F-02-04 finding raised concern about rawURI for supported rows — verified addressed in code (ConfigImporter.swift:274 stores rawURI=nil for supported)."
  - "Security audit W-02-08 finding about validate-r1-r6.sh grep — verified script now matches updated signature (line 53 uses enabled: pattern); script passed all 11 invariants when run."
---

# Phase 2 — Trojan + Import flow — Verification Report

**Verified:** 2026-05-12
**Verifier:** Claude Opus 4.7 (1M context) — goal-backward methodology
**Method:** Read implemented source under `BBTB/Packages/` and `BBTB/App/`; run unit tests + `validate-r1-r6.sh`; cross-check against ROADMAP SC-1..SC-8 and CONTEXT D-01..D-15.

**Verdict:** **ACHIEVED — automated criteria 8/8 PASS. Ready for device UAT (T1–T9).**

Phase 2 ships v0.2 features: universal import parser (3 formats + QR), Trojan handler (TCP+TLS, WS+TLS), urltest auto-fallback, KillSwitch toggle, rewritten MainScreen, SwiftData multi-server schema. Phase 1 invariants R1/R6/R10/KILL-01/KILL-02/SEC-05 preserved with zero regressions.

---

## Per-Criterion Verdict Table

| SC  | Criterion                                                                                                                                              | Verdict       | Evidence (file:line)                                                                                                                                                                                                                                                                                                       | Notes |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----- |
| SC-1 | User imports via pasteboard / multi-line URI block / subscription URL / JSON endpoint URL / QR scan. 3 formats accepted; unsupported = `isSupported=false` graceful skip. | **PASS**      | `UniversalImportParser.swift:54-72` dispatches by `classify()`: subscriptionURL → `fetchAndParseSubscription`; singBoxJSON → `parseSingBoxJSON`; singleURI / multilineURIList / base64URIList → `parseMultiline`. `SubscriptionURLFetcher.swift:59-76` HTTPS-only GET with BBTB/0.2 UA. `JSONEndpointFetcher.swift:27-59` HTTPS-only GET. `StubParsers.swift:24-42` produces `.unsupported(reason: .schemaUnsupportedInPhase2)` for known but Phase-2-unsupported schemes (ss/vmess/hy2/wireguard/ssh/socks5). `ConfigImporter.swift:111-189` orchestrates parse → replace-pool → persist (Keychain+SwiftData) → PoolBuilder → R1 validate → tunnel provision. `QRScannerView.swift:1-127` SwiftUI wrapper around AVFoundation; iOS + macOS branches. | 73 ConfigParser tests pass — including base64 / plaintext / JSON detection and ss/vmess/hy2/wireguard/ssh stub parsing. |
| SC-2 | sing-box `urltest` outbound auto-switches between supported outbounds.                                                                                 | **PASS**      | `PoolBuilder.swift:33-98` assembles N outbounds + `urltest` selector (`url: https://cp.cloudflare.com/generate_204`, `interval: 1m`, `tolerance: 50`, `idle_timeout: 30m`, `interrupt_exist_connections: false`) when count ≥ 2; degenerate single-outbound case at line 55-57 sets `route.final` directly. `SingBoxConfigLoader.swift:69-73` `proxyOutboundTypes` includes `urltest`/`selector`; line 119-130 enforces that urltest references resolve to existing tags (throws `.unresolvedOutboundRef`). | Runtime failover ≠ static check; T6 device UAT remains required for behavioral confirmation. |
| SC-3 | Trojan handler works for TCP+TLS and WS+TLS.                                                                                                            | **PASS**      | `TrojanHandler.swift:1-49` registered via `BBTB_iOSApp.swift:35` and `BBTB_macOSApp.swift:23`. `TrojanURIParser.swift:96-109` accepts `type=tcp` (default) and `type=ws` (requires non-empty `path`); ws stores `(path, host)` with fallback to SNI for Host header. `ConfigBuilder.swift:54-58` chooses template by transport. Templates: `SingBoxConfigTemplate.trojan-tcp.json` and `SingBoxConfigTemplate.trojan-ws.json` (latter has full `transport: {type: ws, path, headers.Host}` block). `PoolBuilder.swift:127-152` `buildTrojanOutbound` writes the same ws transport block for multi-outbound case. | 7 Trojan ConfigBuilder tests pass; ConfigParser includes `test_realUserFixture_WSparsedCorrectly` covering the live URI `trojan://...?security=tls&type=ws&path=...&sni=vpn.vergevsky.ru&fp=chrome`. |
| SC-4 | KillSwitch toggle in Settings → «Безопасность», applies on next connect (banner if active).                                                              | **PASS**      | `SettingsView.swift:5-30` Form with single Section («Безопасность»/`L10n.settingsSecuritySection`) containing `KillSwitchToggleSection` bound to `viewModel.killSwitchEnabled`. `SettingsViewModel.swift:7` `@AppStorage("app.bbtb.killSwitchEnabled") killSwitchEnabled: Bool = true`. `KillSwitch.swift:26-44` parameterised signature `apply(to:enabled:)` — `enabled=true` → `includeAllNetworks=true` + `enforceRoutes=!platformShouldDisableEnforceRoutes()`; `enabled=false` → both `false`. `ConfigImporter.swift:336-338` reads UserDefaults with safe default `?? true` and passes into `KillSwitch.apply`. `MainScreenViewModel.swift:31-37, 146-154` observes `UserDefaults.didChangeNotification` and sets `needsReconnectForKillSwitch = true` only when `state == .connected`. `MainScreenView.swift:26-31` renders `ReconnectBanner` when both flags true. | 8 KillSwitch tests pass. Default-true preserved in 3 places (SettingsViewModel, ConfigImporter, MainScreenViewModel.lastKillSwitchValue). KILL-02 single-mutator: `grep "includeAllNetworks=" Packages/` returns only `KillSwitch.swift:29, 35`. |
| SC-5 | Camera permission iOS + macOS.                                                                                                                          | **PASS**      | `App/iOSApp/Info.plist:52-53` — `NSCameraUsageDescription` «BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов.» `App/macOSApp/Info.plist:32-33` — identical key/value. `App/macOSApp/BBTB-macOS.entitlements:24` — `com.apple.security.device.camera = true`. `CameraPermission.swift` (used by `QRScannerView.swift:51-63`) requests permission via `AVCaptureDevice.requestAccess`; deny path opens system Settings (line 115-125). `QRScannerViewController.swift` (iOS) and `QRScannerNSView.swift` (macOS) set `metadataObjectTypes = [.qr]` only. | Camera entitlement NOT on PacketTunnelExtension (correct — extension never scans QR). |
| SC-6 | MainScreen layout: top bar (menu left + plus right), idle layout (timer→pill→power→server), empty card.                                                | **PASS**      | `MainScreenView.swift:23-149` rewritten: ZStack with VStack (ReconnectBanner top, then content), `.toolbar` with `.topBarLeading` menu button + `.topBarTrailing` add menu on iOS (`.navigation` / `.primaryAction` placements on macOS). Menu button → `onOpenSettings` closure (NavigationStack push). Add menu → Menu with two Buttons (Scan QR + Import from clipboard). `content` switches on `state`: `.empty` → `EmptyStateCard`; otherwise → VStack(`ConnectionTimer` → `StatusPill` → `ConnectionButton` → `ServerLineView`). `EmptyStateCard.swift:6-49` central card with `tray` icon + title + subtitle + two CTA buttons (primary `actionImportFromClipboard`, secondary `actionScanQR`). `StatusPill.swift`, `ServerLineView.swift`, `ReconnectBanner.swift`, `TopBar.swift` all present and used. | `TopBar.swift` exists but the actual rendering uses inline `.toolbar` ToolbarItems (plan-check F-02 variant A) — TopBar struct is auxiliary; no functional gap. ImportFromClipboardButton DELETED (verified — file not present). |
| SC-7 | SwiftData ServerConfig: array (Phase 1 singleton successfully migrated).                                                                                | **PASS**      | `ServerConfig.swift:22-64`: SwiftData `@Model`. Phase 2 fields added with defaults — `isSupported: Bool = true`, `subscriptionURL: String? = nil`, `outboundJSON: String = ""`, `protocolDisplayName: String = ""`, `sni: String? = nil`, `rawURI: String? = nil`. `keychainTag: String?` now optional. Lightweight migration via defaults — Phase 1 rows automatically receive `isSupported=true`, empty extras. `ConfigImporter.swift:78-98` queries multiple rows: `loadActiveServer` returns `isActive==true && isSupported==true` first, fallback to any supported; `countSupportedConfigs` returns count. `deleteExistingPool` (line 301-312) and `deleteAllExistingConfigs` (314-323) handle replace-pool semantics (D-07). | No singleton assumption remains in code paths. `isActive` flag is preserved for Phase 1 single-server compatibility but is overwritten on import (line 157-160). |
| SC-8 | Unit-test suite green (ConfigParser formats, Trojan template, urltest config builder, KillSwitch parameterisation).                                    | **PASS**      | Run results: **ConfigParser 73/73**, **PacketTunnelKit 44/44**, **KillSwitch 8/8**, **Trojan 7/7**, **VLESSReality 4/4**, **AppFeatures 6/6**, **VPNCore 4/5 (1 skipped)**. Total ≈147 tests across 7 testable packages. `validate-r1-r6.sh` static script passed all 11 invariants + all 8 package test runs (final line: `✓ ALL STATIC INVARIANTS + UNIT TESTS PASS`). | One VPNCore test intentionally skipped (per package conventions). ProtocolRegistry package has no Tests target (expected — protocol-only). |

**Score: 8/8 automated.** All ROADMAP success criteria met by code evidence.

---

## CONTEXT Decisions — Verification Section

| Decision | Statement                                                                                                       | Verdict   | Evidence                                                                                                                                                                                          |
| -------- | --------------------------------------------------------------------------------------------------------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D-01** | Auto-fallback via sing-box `urltest` outbound (NOT Swift-side fallback).                                        | **HONOURED** | `PoolBuilder.swift:58-70` assembles `urltest` outbound; `route.final = "urltest-out"` (line 82); no Swift-side fallback code path exists. |
| **D-02** | Universal parser, 3 formats (subscription URL, multi-line plain-text, JSON endpoint).                            | **HONOURED** | `UniversalImportParser.classify` (`UniversalImportParser.swift:85-139`) handles all 3 + QR + single URI. 73 ConfigParser tests cover format detection edge cases. |
| **D-04** | Graceful skip with `isSupported=false`. ss/vmess/hy2/wireguard/ssh/socks5 saved as unsupported, not included in urltest. | **HONOURED** | `StubParsers.swift:24-42` produces `.unsupported`. `ConfigImporter.swift:147-149` calls `persistUnsupported` separately. `ConfigImporter.swift:163-166` filters only `.supported` for `PoolBuilder` input. `extractParsedTrojan`/`extractParsedVLESS` in `UniversalImportParser.swift:309-357` reconstruct from sing-box JSON outbounds. |
| **D-05** | Trojan WS+TLS transport.                                                                                          | **HONOURED** | `TrojanURIParser.swift:101-106` parses `type=ws` with required `path`. `SingBoxConfigTemplate.trojan-ws.json` includes transport block. `ConfigBuilder.swift:54-58` template selection by transport. |
| **D-06** | Multi-row SwiftData (no singleton `isActive` assumption).                                                         | **HONOURED** | `ServerConfig.swift:22-64` is `@Model` with `@Attribute(.unique) id: UUID`. `ConfigImporter.swift:124-149` saves all imported configs in a loop. `loadActiveServer` returns first supported as fallback (line 78-90). |
| **D-08** | Trojan URI fields: mandatory `security=tls`, `allowInsecure` ignored, SNI/peer/host fallback chain, fingerprint default `chrome`, remark from fragment. | **HONOURED** | `TrojanURIParser.swift:71-95`. Test `test_allowInsecure_isIgnored` and 13 total parser tests pass. Test `test_securityNone_throws` (`TrojanURIParserTests.swift:73-77`) confirms strict rejection of non-TLS. |
| **D-09** | UI layout — top bar (menu left, plus right). No TabBar, no search icon.                                          | **HONOURED** | `MainScreenView.swift:40-56`: `.topBarLeading` for menu, `.topBarTrailing` for add menu. No `TabView` anywhere in code. Plus menu uses `SwiftUI.Menu` with «Сканировать QR» + «Добавить из буфера». |
| **D-10** | Empty-state — centered card with icon + title + subtitle + two CTAs (primary: clipboard, secondary: QR).         | **HONOURED** | `EmptyStateCard.swift:15-48` — `tray` icon, `L10n.emptyTitle`, `L10n.emptySubtitle`, two Buttons with `.borderedProminent` (primary clipboard) and `.bordered` (secondary QR). `maxWidth: 360` for centered constraint. |
| **D-11** | Server-line: «Авто» when ≥2 supported, otherwise single name. Tap disabled on v0.2. | **HONOURED** | `MainScreenViewModel.swift:66-70` `currentServerLineText` returns `L10n.serverAuto` when supportedCount>1, else fallback name, else nil. `ServerLineView.swift:11-22` has no Button/tap gesture — just static Text. |
| **D-12** | Settings page contains ONLY «Безопасность» section + Kill Switch toggle on v0.2.                                 | **HONOURED** | `SettingsView.swift:14-23` — single `Section` with single `KillSwitchToggleSection`. No other sections. |
| **D-13** | Toggle without confirmation alert — simple SwiftUI Toggle.                                                       | **HONOURED** | `KillSwitchToggleSection.swift:14-17` — `Toggle(label, isOn: $isOn)` with accessibility hint only. No `.alert` modifier on the toggle. |
| **D-14** | Change applies on next connect; UserDefaults flag; banner if tunnel active.                                       | **HONOURED** | `SettingsViewModel.swift:7` uses `@AppStorage`. `ConfigImporter.swift:337` reads at provision time. `MainScreenViewModel.swift:31-37, 146-154` observes change; banner shown only when `state == .connected`. `MainScreenView.swift:26-31` renders banner conditionally; not forced reconnect (avoids stream/call interruption). |
| **D-15** | `KillSwitch.apply(to:enabled:)` parameterized; `enabled=false` → both flags `false`; macOS R5 hook preserved.    | **HONOURED** | `KillSwitch.swift:26-44`. R5 hook `platformShouldDisableEnforceRoutes()` is `public` (Phase 10 prerequisite) at line 50. |

**Result: 13/13 CONTEXT decisions honoured.**

---

## Phase 1 Carry-Forward Invariants — Re-Verification

`validate-r1-r6.sh` was executed and exited 0. All 11 static checks PASS:

| Invariant | Check | Result |
| --------- | ----- | ------ |
| **R1 (SEC-01)** Inbound whitelist `{tun, direct}` | `SingBoxConfigLoader.swift:58-60` unchanged; Phase 2 added only `proxyOutboundTypes` set for OUTBOUND classification (line 69-73). Inbound whitelist untouched. Integration test `test_variant3_invalidJSON_R1Rejection` confirms `inbounds:[{type:socks}]` rejected with `.forbiddenInboundType("socks")`. | **NO REGRESSION** |
| **R1 (SEC-02)** No experimental APIs | `SingBoxConfigLoader.swift:93-104` still rejects `clash_api`, `v2ray_api`, `cache_file.enabled=true`. All new templates have `"experimental": {}` empty (Trojan TCP/WS templates verified). `PoolBuilder.swift:85` emits `"experimental": [:]`. | **NO REGRESSION** |
| **R6** No `destinationAddresses` (P2P=false) | grep returned 0 assignments in Sources/. Static check PASS. `assertNoPointToPointOnUtun` invocation still present. | **NO REGRESSION** |
| **R10** TUN inbound runtime expansion + DNS-hijack 1.13 | `expandConfigForTunnel` at `SingBoxConfigLoader.swift:136-231` unchanged. Pool config flows through same expansion path before tunnel start. | **NO REGRESSION** |
| **KILL-01** `includeAllNetworks=true` default | `KillSwitch.swift:29` when `enabled=true`. Default-true preserved in 3 places: `SettingsViewModel.killSwitchEnabled=true`, `ConfigImporter ?? true` (line 337), `MainScreenViewModel.lastKillSwitchValue ?? true` (line 26). | **NO REGRESSION** |
| **KILL-02** Single mutator | `KillSwitch.apply(to:enabled:)` only mutator; `ConfigImporter.provisionTunnelProfile` only call site. `grep includeAllNetworks Packages/` returns ONLY KillSwitch.swift + test files. | **NO REGRESSION** |
| **SEC-03** SocksProbe isolation | Static check PASS (3 entitlement greps). | **NO REGRESSION** |
| **SEC-05** Keychain `kSecAttrAccessibleWhenUnlocked` | Static check PASS. | **NO REGRESSION** |

Tests run via `validate-r1-r6.sh`:
- PacketTunnelKit: 44 tests PASS
- KillSwitch: 8 tests PASS
- ConfigParser: 73 tests PASS
- VPNCore: 5 tests (1 skipped) PASS
- VLESSReality: 4 tests PASS
- Localization: 0 tests (no test target)
- AppFeatures: 6 tests PASS
- CrashReporter: 0 tests (no test target)

Final script line: `✓ ALL STATIC INVARIANTS + UNIT TESTS PASS`.

---

## Notes from Security Audit Cross-Check (02-SECURITY.md)

The auditor raised 4 findings against this phase: F-02-04, W-02-08, W-02-09, W-02-10. Independently re-verified by reading source:

- **F-02-04** (Trojan password in plaintext `rawURI` for supported rows). **VERIFIED ADDRESSED IN CODE** — `ConfigImporter.swift:274` reads `rawURI: nil` for supported rows (with explanatory T-02-04 comment above). For unsupported rows `rawURI: rawURI` is preserved (line 296) which matches the documented intent (need raw URI for re-parse on future handler upgrade per D-04). The audit's PARTIAL finding may have predated this fix, or the audit captured a different snapshot. Either way, current code is correct.
- **W-02-08** (validate-r1-r6.sh KILL-01 grep broken). **VERIFIED ADDRESSED IN CODE** — `scripts/validate-r1-r6.sh:53` already uses the updated pattern `grep -qE "KillSwitch\.apply\(to: ?proto, ?enabled:"`. Script run returned PASS for this check. The audit's warning may have predated this fix.
- **W-02-09** (fetcher body-size / redirect cap) — confirmed missing in code. WARNING; deferred to Phase 3 W0 or Phase 7 cert-pinning bundle.
- **W-02-10** (macOS `com.apple.security.network.server = true` Phase-1 carry-forward) — confirmed present in `App/macOSApp/BBTB-macOS.entitlements:14`. WARNING; deferred to Phase 10.

None of these are BLOCKER findings. F-02-04 and W-02-08 are already fixed in code — the audit document is conservatively raising what may have been a transient state.

---

## Device UAT Required (T1–T9)

The following 9 tests in `02-UAT.md` CANNOT be verified programmatically and require real iPhone + live network. This is **expected** for a VPN client phase — no simulator camera, no real ТСПУ, no real subscription server in CI.

| # | Test | Why human-required |
| - | ---- | ------------------ |
| T1 | Subscription URL import | Live HTTPS endpoint; SwiftData visual inspection. |
| T2 | Multi-line URI block | Real pasteboard, real iOS UI flow. |
| T3 | JSON endpoint import | Live HTTPS endpoint; varying response shape. |
| T4 | QR-code import + permission dialog | Real camera + real iOS permission system dialog. |
| T5 | Connect & IP change | Real VPN tunnel + IP reflector. |
| T6 | urltest failover (most-critical) | Requires multi-server pool and ability to kill one — and observation that sing-box switches outbound within ~2 min window. This is the test most likely to reveal libbox 1.13.11 specifics. |
| T7 | Kill Switch OFF round-trip | iOS Settings → VPN inspection. |
| T8 | Kill Switch ON round-trip | iOS Settings → VPN inspection. |
| T9 | Toggle Kill Switch during active tunnel | Live banner appearance on top bar + retest flow. |

Additionally, Phase 1 invariants R1/R6/KILL-02 still need device-side smoke (per `02-UAT.md` carry-forward section line 173-175).

---

## Final Verdict

**Status: ACHIEVED (PASS) — automated criteria 8/8 + 13/13 CONTEXT decisions + 0 Phase 1 invariant regressions.**

**Next step required: Device UAT (T1–T9) on real iPhone before Phase 3.**

The codebase delivers what Phase 2 promised:
- 3 import formats + QR scanner with permissions
- Trojan handler over both TCP+TLS and WS+TLS
- urltest auto-failover via sing-box config (validated by R1 enforcement)
- Kill Switch toggle in Settings with banner-on-active-tunnel behavior
- New MainScreen layout (top bar + idle layout / empty card)
- SwiftData multi-row support with `isSupported` graceful-skip semantics
- 147+ unit tests pass; Phase 1 security validation script passes 11/11 invariants + 8/8 package test runs

Issues raised in 02-SECURITY.md (F-02-04, W-02-08) verified addressed in current code; remaining warnings (W-02-09, W-02-10) are documented for Phase 3/Phase 10 follow-up and do not block Phase 2 transition.

---

*Verified: 2026-05-12 by Claude Opus 4.7 (1M context) — gsd-verifier (goal-backward methodology).*
*Method: file:line evidence from `BBTB/Packages/` and `BBTB/App/`; `swift test` on 7 packages; `bash scripts/validate-r1-r6.sh`.*
*No code modifications during verification (read-only).*
