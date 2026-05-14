# Phase 7a — Pre-UAT Summary (v0.7.1)

**Status:** Code-complete, awaiting iPhone UAT smoke
**Date:** 2026-05-14
**Version:** v0.7.1 (Phase 7a — TUIC v5 + anti-DPI smart defaults)
**Scope:** PROTO-08 (TUIC v5), DPI-01 (uTLS random), DPI-02 (TLS ClientHello fragmentation), DPI-07 (port diversity — already worked)

---

## Что сделано (commits)

| Wave | Commit | Scope |
|---|---|---|
| **0** discuss-phase | `9130e3c` + `444a09e` + `bb63101` + `92b051d` | CONTEXT.md + DISCUSSION-LOG.md + ROADMAP/REQUIREMENTS/PROJECT sync + wiki decision logs (openvpn-deferral, wireguard-deferral) |
| **1** TUIC v5 package | `8ca1014` | New SwiftPM package `Protocols/TUIC` (Handler + ConfigBuilder + Resources/SingBoxConfigTemplate.tuic.json + 26 tests). New `TUICURIParser` (18 tests). `ParsedTUIC` struct + `case tuic` in AnyParsedConfig. Integration in UniversalImportParser, PoolBuilder, ClashYAMLParser, StubParsers, SubscriptionMergeService, TransportOverride, ServerDetailViewModel, ConfigImporter (3 switches). +1418 lines, 21 files. |
| **2** Anti-DPI smart defaults | `1d98abc` | `uTLS=random` default for all TLS protocols (VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, TUIC v5, Hy2 nil-fallback). `tls.record_fragment: true` default for VLESS+TLS / Trojan (NOT for Reality/Vision — XTLS; NOT for TUIC — QUIC «only ECH»). URI override always honoured. 4 parser files + 3 ConfigBuilder files + 2 test updates. +45/-18 lines. |
| **3** Mux infrastructure | _intentionally deferred_ | Per-server URI/Clash opt-in for smux/yamux/h2mux мерge'ится с Phase 10 (DPI-09 UI toggle) — единый PR без half-baked интерфейса. Rationale в commit `cb6140b` note + 07-CONTEXT.md D-05. |
| **4** App registration + Tuist + xcodebuild | `cb6140b` | `import TUIC` + `ProtocolRegistry.shared.register(TUICHandler.self)` в `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift`. `BBTB/Project.swift` Tuist получил TUIC localPackage + product dep в iOS и macOS app targets. **`tuist generate` ✓**, **iOS xcodebuild ✓**, **macOS xcodebuild (с ad-hoc signing) ✓**. |
| **5** Wiki + closure | _this commit_ | wiki/anti-dpi-techniques.md (реальное состояние sing-box 1.13.x с матрицей техник). wiki/protocols-overview.md (8 in-scope, TUIC v5 + AmneziaWG 2.0 в Phase 7b, WG plain + OpenVPN — Out of Scope). 07a-PRE-UAT-SUMMARY.md (this file). STATE.md update. |

---

## Test coverage

| Package | Tests | Status |
|---|---|---|
| `VPNCore` | existing | ✓ (ParsedTUIC pattern-matched correctly through AnyParsedConfig switch) |
| `Protocols/TUIC` | 26 (16 ConfigBuilder + 10 BuildOutbound) | ✓ green |
| `Protocols/VLESSReality` | 8 existing | ✓ green |
| `Protocols/VLESSTLS` | 20 existing | ✓ green (включая обновлённый buildOutbound с record_fragment) |
| `Protocols/Trojan` | 16 existing | ✓ green |
| `Protocols/Shadowsocks` | existing | ✓ green |
| `Protocols/Hysteria2` | 14 existing | ✓ green (nil-fingerprint fallback "chrome" → "random") |
| `ConfigParser` | 228 (was 227 + 1 override-preserved test) | ✓ green (18 TUIC parser tests included) |
| `AppFeatures` (MainScreenFeature) | 143 | ✓ green |

**Total: ~470+ tests green, no regressions.**

---

## Build verification

- `swift build` for AppFeatures, ConfigParser, всех Protocols — clean.
- `tuist generate` — clean.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination generic/iOS -configuration Debug build` — **SUCCEEDED**.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination generic/macOS -configuration Debug build` (с `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` ad-hoc signing) — **SUCCEEDED**.

---

## Архитектурные decisions (D-XX)

D-01..D-05 — fixed in `07-CONTEXT.md` (см. discuss-phase). Wave-level decisions:
- **W4 ad-hoc rationale (mux defer):** Per-server URI/Clash opt-in mux без UI toggle = half-baked для пользователя. Phase 10 даст DPI-09 picker → объединить — единственно правильный путь по «quality > speed».
- **W2 fragment scope correction (Codex follow-up):** sing-box docs «Only ECH is supported in QUIC» — TUIC v5 НЕ получает `tls.record_fragment` default. CONTEXT.md matrix исправлена; верифицировано в Trojan/VLESSTLS ConfigBuilder.swift comments.

---

## Что осталось до закрытия Phase 7a

### Pre-UAT (этот PRE-UAT-SUMMARY)
- ✅ Code-complete
- ✅ All package tests green
- ✅ iOS + macOS xcodebuild SUCCEEDED
- ✅ Wiki long-term memory updated
- ✅ Decision logs committed

### UAT (Phase 7a Wave-Final, awaiting user action)
1. **TestFlight upload** — User builds v0.7.1 (увеличить version + build), uploads to App Store Connect, distributes via External Testing invite link.
2. **iPhone UAT smoke** (по образцу Phase 6e UAT):
   - Импорт TUIC v5 URI (например `tuic://uuid:password@host:port?congestion_control=bbr&udp_relay_mode=native&sni=...`) — Server появляется в списке как «TUIC v5» с правильным флагом страны.
   - Connect к TUIC серверу — трафик ходит, IP swap наблюдается, latency приемлемая.
   - Auto-fallback с VLESS+Reality + TUIC в одном пуле (urltest) — sing-box выбирает рабочий outbound, fail один — переключается.
   - Существующие 5 протоколов (regression smoke): VLESS+Reality (Phase 1), Trojan (Phase 2), Shadowsocks-2022 (Phase 4), Hysteria2 (Phase 4), VLESS+Vision/TLS (Phase 4) — продолжают работать с обновлённым `tls.record_fragment` и uTLS=random.
   - Settings → kill switch / on-demand auto-reconnect — без regression (R18 invariant сохранён).

### Phase 7a Closure
После UAT PASS:
- `STATE.md` Active Phase: 7 → 7a closed → 7b active.
- `ROADMAP.md` Phase 7a success criteria checkboxes mark ✓.
- `REQUIREMENTS.md` PROTO-08, DPI-01, DPI-02, DPI-07 → Validated.
- `wiki/log.md` Phase 7a closure entry.
- Версия app — `v0.7.1`.

---

## Carry-forward для Phase 7b

- **Engine abstraction layer** — first multi-engine integration. Design в одном PacketTunnelProvider extension с runtime engine selection (SingBoxEngine vs AmneziaWG2Engine).
- **AmneziaWG 2.0 через `amneziawg-apple`** SwiftPM library (MIT, fork wireguard-apple).
- **AmneziaWG `.conf` parser** для UniversalImportParser.
- **DPI-04** (random TCP/UDP delay) — приходит «бесплатно» как Jc/Jmin/Jmax junk packets в AWG handler.
- **Mux infrastructure** (был Wave 3) — потенциально переносится в Phase 10 DPI-09 unified PR с UI toggles.

---

## Wave / commit hash table (для git navigation)

```
9130e3c — docs(phase-07): capture phase context via discuss-phase
444a09e — docs(phase-07): sync ROADMAP / REQUIREMENTS / PROJECT to Phase 7 decisions
bb63101 — docs(wiki): add Phase 7 deferral decision logs
92b051d — docs(wiki): register Phase 7 deferral pages in index + log
8ca1014 — feat(07a-w1): TUIC v5 protocol package (PROTO-08)
1d98abc — feat(07a-w2): anti-DPI smart defaults — uTLS=random + tls.record_fragment
cb6140b — feat(07a-w4): register TUICHandler in apps + Tuist project
[this commit] — docs(07a-w5): pre-UAT wiki sync + closure summary
```

---

*Phase 7a implementation autonomous run completed 2026-05-14. Next: iPhone UAT (manual user action) → after PASS → start Phase 7b planning.*
