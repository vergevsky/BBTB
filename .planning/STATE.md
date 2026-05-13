---
gsd_state_version: 1.0
milestone: v0.12
milestone_name: + v1.0)
status: completed
last_updated: "2026-05-13T09:52:38.487Z"
progress:
  total_phases: 12
  completed_phases: 5
  total_plans: 26
  completed_plans: 28
  percent: 46
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-12 after Phase 3)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 06 — network resilience

## Active Phase

- **Phase:** 6c
- **Name:** On-demand reconnect migration
- **Status:** Plan 01 complete 2026-05-13 (Wave 0 — OnDemandRulesBuilder foundation, +11 tests). 4 plans remain.
- **Goal:** Заменить custom auto-reconnect machinery на iOS-нативный `isOnDemandEnabled` + `NEOnDemandRule*` (D-01..D-22, post-Round-1 triple-reviewer APPROVE)
- **Version:** v0.6.1 (patch)
- **Requirements:** NET-08..11 (re-validated via Apple-managed mechanism)
- **Wave progress:**
  - Wave 0 (06C-01) ✓ — OnDemandRulesBuilder foundation: 4 public methods + 11 tests; strictly additive; AppFeatures 138/138.
  - Wave 1 (06C-02) ✓ — ManagerSelector + ConfigImporter wiring + bbtbProvisionerDidSave: +7 tests (3 selector + 4 wiring); AppFeatures 145/145; parallel-run invariant preserved (TunnelController/RSM/NetworkReachability untouched).
  - Wave 2 (06C-03) ✓ — Settings toggle + ReconnectClock/TestClocks extract (B-01/B-02) + OnDemandMigrationTask (B-05 transient-failure guard) + TunnelWatchdog (W-05 .reasserting cancel): +18 tests (4 Settings + 5 Migration + 9 Watchdog); AppFeatures 163/163; TunnelController/NetworkReachability still untouched (wiring deferred to Wave 3).
  - Wave 3 (06C-04) — **IN PROGRESS, Task 3 scoped per Codex R5**:
    - Task 1 ✓ (commit d49e635) — additive wiring: cachedManager + bbtbProvisionerDidSave observer + setWatchdog + applyCurrentStateToCachedManager (Round 3 N-01 fallback + MINOR-01 graceful catch) + macOS wake 3 guards + .connecting banner case. AppFeatures 163/163 PASS, iOS+macOS xcodebuild SUCCEEDED.
    - Round 4 (commit 83260c1) — fight-back protection on `.disconnected`. Closed F-reverse (BBTB→Happ). To be reverted in Task 3a (becomes unnecessary after parallel-run cleanup).
    - Round 4 UI desync fix (commit 9206b8c) — state→.idle on external `.disconnected`. To be reverted in Task 3b (replaced by reactive UI driver).
    - Round 4.1 (commit 76ae2d6) — narrow fight-back guards. To be reverted in Task 3a.
    - Task 2 (UAT) — partial signal: A pass, F-direct pass, F-reverse pass after Round 4. Bug A (UI freeze on connect) + Bug B (Settings off → BBTB reactivates) discovered. **Architect review (06C-ARCHITECT-R5.md) diagnosed: both bugs are parallel-run hybrid (old ReconnectStateMachine firing in connect path + on external events). UAT cannot pass while hybrid exists. Pulling Task 3 cleanup forward, scope expanded per Codex R5 additions.**
    - Task 3a/3b/3c — **next** (Codex-driven scope):
      - 3a: delete OLD machinery (RSM + reachability + triggerRecoveryIfNeeded callsites) + revert Round 4/4.1 patches + add intent-closing on external `.disconnected`.
      - 3b: reactive UI — main `state` driven by NEVPNStatus events, not by `connect()` return. Banner enum trim. Add setFailoverObserver in TunnelWatchdog.
      - 3c: file deletes (5) + create TunnelControllerTests.swift + drop ReconnectStateObserverRelay from App entry points.
    - Re-UAT pair after cleanup: F-reverse (BBTB→Happ off-and-stay) + Settings off (toggle off in iOS Settings → BBTB stays off until explicit Connect). G (Mach port) runs passively in background.
  - Wave 4 (06C-05) — pending: regression + UAT documentation + wiki sync (UAT.md, REQUIREMENTS NET-12 liveness-probe stub for Phase 7-8)

### Previous phase (Phase 6 — Network Resilience)
- **Status:** ✓ Implementation complete 2026-05-13 — UAT отложен пользователем (Task 3 A-I deferred)
- **Goal:** DNS-стратегия (DoH + bootstrap, без хардкода Yandex), блокировка IPv6, авто-реконнект с retry, failover на следующий сервер
- **Version:** v0.6
- **Requirements:** NET-01..11
- **All 6 waves complete:**
  - Wave 1 (06-01) — DNSConfig + AdvancedSettingsStore
  - Wave 2 (06-02) — PoolBuilder DNS API + 6 sing-box template DNS swaps (Yandex→AdGuard)
  - Wave 3 (06-03) — Settings → Advanced DNS UI
  - Wave 4 (06-04) — NetworkReachability + ReconnectStateMachine actors
  - Wave 5 (06-05) — TunnelController actor + DNS wiring + wake + banner + notifications + Yandex eradication
  - Wave 6 (06-06) — SwiftDataFailoverProvider + manual-disconnect reset + 30s stable-session reset + single-server notification
- **Test totals (Phase 6):** AppFeatures 120/120, VPNCore 57/57, ConfigParser 210/210, PacketTunnelKit 61/61, Localization 3/3 + protocol packages — all green.
- **Pending:** Device UAT (Task 3 sub-tests A-I) — `/gsd-verify-work 6` once UAT signoff collected.
- **Previous phase (Phase 5) — Transports ✓ Complete 2026-05-13:**
  - 8 waves, ~376 tests PASS (VPNCore 45, TransportRegistry 42, ConfigParser 200, AppFeatures 54, Protocols 35+)
  - TransportConfig + Registry + per-protocol buildOutbound + ServerDetailView shipped
  - UAT отложен пользователем — 5 пунктов manual checks ждут (SwiftData migration, chevron nav, picker persistence, WS override connect, Trojan-WS regression)

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | ✓ Complete 2026-05-11 |
| 2 | Trojan + Import flow | v0.2 | ✓ Complete 2026-05-12 — UAT T0-T9 PASS |
| 3 | Server management | v0.3 | ✓ Complete 2026-05-12 — UAT T1-T8 PASS |
| 4 | Protocol expansion | v0.4 | ✓ Complete 2026-05-12 — UAT deferred (manual) |
| 5 | Transports | v0.5 | ✓ Complete 2026-05-13 — UAT deferred (manual, 5 checks) |
| 6 | Network resilience | v0.6 | ✓ Implementation complete 2026-05-13 — UAT deferred (Task 3 A-I manual) |
| 7 | Anti-DPI suite + WireGuard family | v0.7 | Not started |
| 8 | Rules Engine + Split tunneling | v0.8 | Not started |
| 9 | Deep links | v0.9 | Not started |
| 10 | Advanced settings + Security polish | v0.10 | Not started |
| 11 | Onboarding + UX polish | v0.11 | Not started |
| 12 | Pre-release + Public TestFlight | v0.12 + v1.0 | Not started |

## Accumulated Context

### Recent decisions (Phase 6)

- **D-01 bootstrap DNS strategy** (2026-05-13) — `buildDNSConfig` selects `tcp://<server-IP>` when first parsed config has IPv4 host; otherwise AdGuard `tcp://94.140.14.14` fallback. **Yandex `77.88.8.8` полностью искоренён из shipping code** (`grep -RIn "77.88.8.8" Packages/ | grep -v .build/ | grep -v Tests/` = 0).
- **D-02 tunnel DNS default** (2026-05-13) — Cloudflare DoH (`https://1.1.1.1/dns-query`) when no custom DNS + no AdBlock.
- **D-03 custom DNS priority** (2026-05-13) — non-empty validated `customDNS` overrides; AdBlock toggle ignored when custom set.
- **D-04 AdBlock toggle** (2026-05-13) — `customDNS` empty + `adBlockEnabled == true` → AdGuard DNS (`94.140.14.14` / `94.140.15.15`).
- **D-07 retry policy** (2026-05-13) — 3 attempts × 2/4/8 s exp backoff via `ReconnectStateMachine` actor; on exhaustion → `.allFailed` → `notifyReconnectFailed`.
- **D-08 failover** (2026-05-13) — `SwiftDataFailoverProvider` actor: round-robin cursor over `isSupported == true` servers sorted by `id.uuidString`; cursor seeded at currently-selected server; full circle → nil → `.allFailed`; single-server pool → `notifySingleServerUnavailable` + nil; reset triggers: manual disconnect OR 30s+ stable `.connected` (with `startedAt` race guard per Pitfall 4).
- **TunnelController promoted to actor** (2026-05-13) — was `final class @unchecked Sendable`; Phase 1-5 `connect()/disconnect()` bodies preserved verbatim; new state (`manualDisconnectInProgress`, `lastSuccessfulConnectAt`, `wakePending`, `failoverProvider`) actor-isolated. `setFailoverProvider(_:)` late-binds the real provider to break VM↔Controller init cycle (`[weak tunnel]` connect closure).
- **Pitfall 10 macOS wake** (2026-05-13) — `NSWorkspace.shared.notificationCenter.addObserver(forName: .NSWorkspaceDidWake)` (NOT `NotificationCenter.default` — wake events only fire on workspace center). `handleWake()` sets `wakePending` flag; next `NetworkReachability.satisfied` event consumes it and triggers recovery.
- **6 × sing-box templates** (2026-05-13, Wave 2) — JSON bootstrap DNS swapped Yandex → AdGuard (VLESS-Reality, VLESS-TLS, Trojan-TCP, Trojan-WS, Shadowsocks, Hysteria2). These are legacy single-protocol templates — production runtime uses PoolBuilder, which threads `DNSConfig` from `buildDNSConfig`.

### Recent decisions (Phase 4)

- **D-02 VLESS branching** (2026-05-12) — VLESSURIParser breaks on presence of `pbk`/`sid` params: with → `.vlessReality`; without → `.vlessTLS`. This is a breaking change to the parser return type (now returns `AnyParsedConfig` instead of `ParsedVLESS`).
- **D-08 R1 exception for Hysteria2** (2026-05-12) — Only Hysteria2 sets `allowInsecure` based on URI params. All other protocols hardcode `insecure: false`. Enforced at 3 layers: type system (no allowInsecure field on non-Hy2 structs), hardcoded literals in templates, invariant test `test_nonHy2_outbounds_neverHaveInsecureTrue`.
- **D-09 dual scheme** (2026-05-12) — Both `hy2://` and `hysteria2://` schemes supported; all three insecure synonyms (`insecure`, `allowInsecure`, `skip-cert-verify`) collapse to one Bool.
- **Yams 6.2.1 + octal quirk** (2026-05-12) — Added Jpsim/Yams for Clash YAML parsing. Values like `short-id: 01234567` parsed as octal integers by Yams — mitigated with `stringValue()` helper that calls `.description` on Int.
- **SIP002 dual-path for SS** (2026-05-12) — AEAD-2022 methods (`2022-blake3-*`) use percent-encoded userinfo; legacy methods use base64url. `URLComponents.password` splits on `:` — fixed with explicit userinfo reassembly before splitting.
- **runIsSupportedUpgrade throttle** (2026-05-12) — D-14 auto-upgrade: 5-min throttle via UserDefaults `bbtb.lastIsSupportedUpgrade`; fetch-all + Swift filter (not `#Predicate` on UUID — same bug as Phase 3); `rawURI = nil` on success (T-02-04 invariant).
- **Security Phase 4** (2026-05-12) — 7 threats T-04-06-01..T-04-06-07: all mitigated or accepted. R1 invariant preserved across all 5 protocols. No new carry-forwards beyond existing WR-* list.

### Recent decisions (Phase 3)

- **D-14: SNI исключён из identity key** (2026-05-12) — Subscription-серверы с Reality ротируют SNI (anti-fingerprint). identity = `host:port:protocolID`. SNI обновляется в UPDATE-ветке SubscriptionMergeService. Commits `2077fa7`, `84192a1`.
- **SwiftData #Predicate UUID?** (2026-05-12) — `#Predicate { $0.optionalUUID == uuid }` молча возвращает empty на реальных устройствах. Везде заменено на `context.fetch(all).filter { ... }`. Commit `84192a1`.
- **TunnelController disconnect race** (2026-05-12) — `stopVPNTunnel()` fire-and-forget; `connect()` видел `.disconnecting` и бросал ошибку. `disconnect()` теперь поллит до `.disconnected` (max 5s, 0.5s шаг). `connect()` трактует `.disconnecting` как transient. Commit `b5d3120`.
- **Security Phase 3** (2026-05-12) — T-03-01..T-03-09 (Plan 01-04) + T-03-23..T-03-27 (Plan 05): все mitigated или accepted. WR-01..WR-11 carry-forward: Phase 4 (WR-01/05/07) / Phase 7 (WR-02/11) / Phase 11 (WR-03/04/06/08/09/10). Подробности — `wiki/security-gaps.md` R15/R16.

### Recent decisions (Phase 2)

- **Trojan-WS ALPN** (2026-05-12) — ALPN `["h2", "http/1.1"]` нельзя использовать для Trojan-WS: при TLS handshake сервер выбирает h2, WebSocket upgrade (HTTP/1.1) отвергается. Фикс: `PoolBuilder` и шаблон `trojan-ws.json` используют `["http/1.1"]` для WS-транспорта. Commit `4255a77`.
- **NETunnelNetworkSettings.tunnelRemoteAddress** (2026-05-12) — `proto.serverAddress` должен быть валидным IP/hostname (iOS отвергает произвольные строки типа `"BBTB"`). Значение = `host` первого supported outbound из пула. Commit `39356a4`. См. memory `feedback_netunnelnetworksettings_tunnelRemoteAddress.md`.
- **Security audit Phase 2** (2026-05-12) — 13 threats: 11 COVERED, 1 PARTIAL (T-02-04 rawURI → зафикшен), 1 ACCEPT (T-02-03 audit log → Phase 12). 0 BLOCKER. Carry-forward: W-02-09 (fetcher body-size/redirect cap → Phase 7), W-02-10 (macOS `network.server` entitlement → Phase 10). Commit `2c52e27`.

### Recent decisions (Phase 1)

Полный лог решений — `wiki/security-gaps.md` (R1–R11) и `.planning/PROJECT.md` Key Decisions table. Кратко:

- **R10** (2026-05-11) — TUN inbound runtime expansion + sing-box 1.13 DNS-hijack migration. R1 = default-deny white-list `{tun, direct}`; `SingBoxConfigLoader.expandConfigForTunnel` публичный + idempotent; post-expand re-validation defense-in-depth.
- **R11** (2026-05-11) — Phase 1 security audit closed: 37/37 threats verified. См. `.planning/phases/01-foundation/01-SECURITY.md`.
- **${VLESS_FLOW} placeholder** (commit `9aa3e93`) — template support dual-config (Vision-enabled + non-Vision URIs); flow extracted из URI вместо hardcoded `xtls-rprx-vision`.

### Blockers / Concerns

- ⚠️ **[Phase 11 follow-up]** Empty-state UX issue: после удаления VPN profile из iOS Settings, MainScreen остаётся в `error` state без recovery action. Workaround: delete + reinstall. Fix план — auto-recreate manager при старте если активный ServerConfig есть, а manager отсутствует. Связано с REQ UX-02, CORE-07.
- ⚠️ **[Phase 11 follow-up]** SocksProbe UX — verdict UI должен различать «BBTB process» от «другие процессы на устройстве» через PID attribution. Сейчас port 1080 от AdGuard/iCloud Private Relay показывается как FAIL.
- ⚠️ **[Phase 12 prerequisite]** Apple Distribution credentials — перед TestFlight upload создать Apple Distribution cert + App Store profiles для `app.bbtb.client.ios` и `app.bbtb.client.ios.tunnel`. Phase 1 DIST-02 export на этом упал (UAT T7 partial); archive (DIST-01) сам собирается.
- ⚠️ **[Phase 11/12]** W2-05 iOS 16.1+ Apple-leak документация — promote из `.planning/phases/01-foundation/01-RESEARCH.md:277,982` в отдельную wiki-страницу либо в FAQ.

## Next Action

**Phase 6 implementation complete 2026-05-13 — UAT отложен пользователем.**

Когда пользователь будет готов к UAT — выполнить Plan 06-06 Task 3 sub-tests A-I на iPhone (iOS 18+) и MacBook (macOS 15+):

- **A.** DNS leak test (NET-01, NET-04) — `dnsleaktest.com`
- **B.** IPv6 leak test (NET-05, NET-06) — `ipv6-test.com`, `whoer.net`
- **C.** Settings → Advanced DNS UI persistence + validation
- **D.** Wi-Fi ↔ LTE handoff banner sequence (NET-08)
- **E.** Sleep wake recovery (NET-09)
- **F.** Failover after 3 failed attempts (NET-11)
- **G.** `.allFailed` local notification permission flow
- **H.** Manual disconnect — no spurious reconnect banner (Pitfall 3)
- **I.** R1 + R6 regression (SOCKS-port scanner + `ifconfig utun*` no POINTOPOINT v6)

После UAT signoff → `/gsd-verify-work 6` → переход к Phase 7 (Anti-DPI suite + WireGuard family).

## UAT findings (накапливаются)

**Fixed во время UAT Phase 2:**

- `6d0f798` — TrojanURIParser default fingerprint при пустом `fp=` (был `""`, стал `"chrome"`).
- `39356a4` — ConfigImporter `serverAddress` ставился literal `"BBTB"`, что отвергалось iOS как невалидный `tunnelRemoteAddress`. Восстановлено Phase 1 поведение (host первого outbound).

**Fixed во время UAT Phase 3:**

- `84192a1` — SwiftData `#Predicate { $0.subscriptionID == UUID? }` тихо возвращал empty; заменён на fetch-all + Swift filter в SubscriptionMergeService и ServerListViewModel.
- `2077fa7` — Subscription-серверы ротируют SNI (Reality anti-fingerprint); SNI исключён из identity key `host:port:protocolID`; SNI обновляется в UPDATE-ветке merge.
- `b5d3120` — T6 reconnect: `disconnect()` не ждал реального закрытия туннеля; добавлен poll до `.disconnected` (max 5s); `connect()` теперь пропускает `.disconnecting` как transient.

**Phase 11 backlog (UX polish):**

- Tunnel error message не отображается в `.error` state (только pill, без подробного текста).
- Wrapped error text — alert показывает технические префиксы из enum-обёрток (`Parse: Fetch failed: ...`). Должна показываться только пользовательская строка.
- Empty-state layout уточнён через диалог (карточка с 2 кнопками, не только текст).

После полного UAT:

- `/gsd-discuss-phase 3` — Server management (server-list UI, pull-to-refresh, multi-subscription).

## Известные не-блокеры Phase 2

- **macOS Debug signing-cert**: Phase 1 DIST-02 carry-forward gap, не Phase 2 regression. Перед Phase 12 TestFlight нужно создать Distribution cert + App Store profiles для `app.bbtb.client.macos` и `.macos.tunnel`.
- **W-02-09**: Subscription/JSON fetcher не имеют body-size cap и redirect-chain cap. Defence-in-depth gap, deferred to Phase 7 (DPI-08 cert pinning).
- **W-02-10**: Orphan `com.apple.security.network.server` entitlement на macOS app. Deferred to Phase 10 (вместе с R5 enforceRoutes toggle).
- **T-02-03**: Repudiation — нет audit-логов импорта/connect. Deferred to Phase 12.

## Phase 2 Artefacts

`.planning/phases/02-trojan-import-flow/` содержит:

- `02-CONTEXT.md` (15 decisions, 4 areas)
- `02-DISCUSSION-LOG.md` (audit trail)
- `02-UI-SPEC.md` (757 lines, design contract)
- `02-RESEARCH.md` (2817 lines, sing-box + Apple APIs)
- `02-PATTERNS.md` (1554 lines, Phase 1 analog map)
- `02-PLAN.md` (3412 lines, 7 waves × 34 tasks)
- `02-PLAN-CHECK.md` (plan-check: APPROVED, 0 HIGH)
- `02-EXECUTION-LOG.md` (chronological deviation log)
- `02-SECURITY.md` (12/13 closed, 0 BLOCKER)
- `02-VERIFICATION.md` (8/8 SC PASS in code)
- `02-UAT.md` (9 device tests T1-T9)

---
*Last updated: 2026-05-12 после закрытия Phase 3 UAT. Phase 3 UAT-баги: `84192a1` SwiftData UUID? predicate, `2077fa7` SNI rotation в identity, `b5d3120` TunnelController disconnect race. Всего 3 фазы закрыты. Следующий шаг: `/gsd-discuss-phase 4`.*
