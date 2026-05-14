---
gsd_state_version: 1.0
milestone: v0.12
milestone_name: v0.12 + v1.0
status: "Phase 6e CONTEXT.md captured 2026-05-14 — scope decided (ALL 26 findings; baseline + macOS UAT deferred к 11/12; hybrid closure rigor). Next: `/gsd-plan-phase 6e`."
last_updated: "2026-05-14T13:30:00.000Z"
progress:
  total_phases: 14
  completed_phases: 8
  total_plans: 53
  completed_plans: 53
  percent: 57
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-12 after Phase 3)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 6e — discuss-phase complete 2026-05-14; CONTEXT.md captured (ALL 26 carved findings, hybrid closure rigor, Instruments + macOS UAT deferred к Phase 11/12). Next: `/gsd-plan-phase 6e`. Phase 7 (Anti-DPI suite + WireGuard family, v0.7) — после 6e closure.

## Active Phase

- **Phase:** 6e _(INSERTED 2026-05-14)_
- **Name:** Performance Audit Round 2 + macOS UAT replay _(slug captures original ROADMAP scope; macOS UAT deferred per discuss-phase D-03)_
- **Status:** CONTEXT.md captured 2026-05-14. Next: `/gsd-plan-phase 6e` to spawn researcher (cross-check 26 carved findings vs post-6d code state) + planner.
- **Goal:** Tactical cleanup-фаза после Phase 6d. Закрыть **все 26 carved-out findings** из Phase 6d (6 MEDIUM atomic + 20 LOW bundled + 3 trivial unused imports) с hybrid closure rigor. Не закрывает NET-12 (Phase 7-8 carve-out).
- **Version:** v0.6.3 (patch)
- **Requirements:** maintains PERF-01..05 + QUAL-01..03 (Phase 6d Validated); новые QUAL-04..XX могут быть added в planning (TBD). Ничего из существующего не invalidates.
- **Scope decisions (06E-CONTEXT.md):**
  - D-01 — ALL 26 findings (6 MED + 20 LOW + 3 trivial imports). Researcher cross-checks vs post-6d code state.
  - D-02 — Numerical Instruments baseline SKIPPED (defer к Phase 11/12).
  - D-03 — macOS UAT replay SKIPPED (defer к Phase 11/12).
  - D-04 — Hybrid closure rigor: MEDIUM atomic-commit-per-fix + per-commit regression gate; LOW bundle commits + single regression gate; trivial imports один commit.
  - D-06 — NO 3-AI re-audit (findings уже triaged в 6d).
- **Phase 6e artifacts:**
  - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md` ✓ (2026-05-14)
  - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-DISCUSSION-LOG.md` ✓ (2026-05-14)

### Previous phase (Phase 6d — Performance & Code Quality Audit ✅ Closed 2026-05-14)

- **Status:** ✅ Closed 2026-05-14 после UAT regression smoke PASS на iPhone iOS 26.5 (hard-blockers: A, F-direct, F-reverse, G, I, Settings-disable; E deferred → NET-12; C macOS skipped — carry-over).
- **Goal:** Multi-AI peer review (Claude Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) на cold-start / connect-tap / energy / memory / code quality. Findings classified by severity, fixed atomically.
- **Version:** v0.6.2 (patch)
- **Requirements:** PERF-01..05 + QUAL-01..03 ✅ Validated (new section в REQUIREMENTS.md).
- **Outcome:** 45 findings synthesized → 19 closed (cold-start ~−500…−1100 мс, connect-tap ~−1000…−3000 мс, disconnect −2.5 сек, energy + correctness wins) + 6 post-fix commits (cold-start UI freeze block + Settings-disable saga). 26 carved-out → backlog для Phase 6e.
- **Phase 6d-specific architectural decisions:** DEC-06d-01..06 (см. `wiki/performance-baseline.md`):
  - DEC-06d-01 — Cold-start init defer pattern.
  - DEC-06d-02 — XPC consolidation в TunnelController (≤ 2 trips).
  - DEC-06d-03 — Event-driven status polling (AsyncStream, не sleep-loops).
  - DEC-06d-04 — Bounded concurrency для probe-style operations.
  - DEC-06d-05 — Apple-canonical `options["manualStart"]` discriminator + sticky App Group marker для Settings-disable correctness (open-source-research-derived from WireGuard iOS).
  - DEC-06d-06 — PerfSignposter spans сохранены в production code как standard tooling.
- **Final commits:** Audit + Wave 02a + Synthesis (`e2c9ac6`, `7ffb398`, `64368c6`, `85b16cb`); Wave 03a-03h fix cycle (19 commits, see ROADMAP Phase 6d sub-plans); Wave Final-a (`c1fc126` + `8e6e660` + `6573af4` + `b4d869c`); Post-fix (4 cold-start commits + 3 Settings-disable saga, final `cff3f46`); Wave Final-b (`0a9d1af` UAT + `e2e72ab` wiki sync + closure commit).
- **UAT report:** `.planning/phases/06d-performance-audit/06D-UAT.md`.
- **Closure SUMMARY:** `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md`.
- **Wiki long-term memory:** `wiki/performance-baseline.md` (new, comprehensive).

### Backlog (carried out из Phase 6d Final-b)

- **26 carved-out findings** — Phase 6e «Performance Audit Round 2» или low-effort bundle Phase 6e:
  - 6 MEDIUM (carved): M6, M7, M8, M10, M11, M15
  - 20 LOW: L1-L20
  - 3 trivial unused imports (L-trivial-imports — 3-line cleanup)
- **NET-12** (Phase 6c carve-out, не закрыт в 6d) — active liveness probe для soft-kill server detection. Phase 7-8.
- **macOS-specific UAT replay** — Phase 6c/6d сценарии A/F/Settings-disable/G не выполнялись на macOS отдельно. Отдельная UAT-сессия перед Phase 11/12.
- **Numerical Instruments baseline** — опциональный post-Phase-6d single capture (PerfSignposter готов).

### Previous-previous phase (Phase 6c — On-demand reconnect migration ✅ Closed 2026-05-13)

- **Status:** ✅ Closed 2026-05-13 после re-UAT PASS pair (F-reverse + Settings-disable + G passive on iPhone iOS 26.5).
- **Goal:** Заменить custom auto-reconnect machinery на iOS-нативный `isOnDemandEnabled` + `NEOnDemandRule*` (D-01..D-22, post-Round-1 triple-reviewer APPROVE)
- **Version:** v0.6.1 (patch)
- **Requirements:** NET-08..11 ✅ Validated через Apple-managed mechanism + re-UAT.
- **Final commits:** `19f3fe7` + `5b0e28c` + `69b8ae8` (cutover) + `44a5630` (Round 6 follow-up VM resync + connectedDate authority) + `ce5913d` (Plan 05 closure — UAT.md + SUMMARY).
- **Wave progress:**
  - Wave 0 (06C-01) ✓ — OnDemandRulesBuilder foundation: 4 public methods + 11 tests; strictly additive; AppFeatures 138/138.
  - Wave 1 (06C-02) ✓ — ManagerSelector + ConfigImporter wiring + bbtbProvisionerDidSave: +7 tests (3 selector + 4 wiring); AppFeatures 145/145; parallel-run invariant preserved (TunnelController/RSM/NetworkReachability untouched).
  - Wave 2 (06C-03) ✓ — Settings toggle + ReconnectClock/TestClocks extract (B-01/B-02) + OnDemandMigrationTask (B-05 transient-failure guard) + TunnelWatchdog (W-05 .reasserting cancel): +18 tests (4 Settings + 5 Migration + 9 Watchdog); AppFeatures 163/163; TunnelController/NetworkReachability still untouched (wiring deferred to Wave 3).
  - Wave 3 (06C-04) — **✓ COMPLETE 2026-05-13 — re-UAT PASS + follow-up fix landed**:
    - Task 1 ✓ (commit d49e635) — additive wiring: cachedManager + bbtbProvisionerDidSave observer + setWatchdog + applyCurrentStateToCachedManager (Round 3 N-01 fallback + MINOR-01 graceful catch) + macOS wake 3 guards + .connecting banner case. AppFeatures 163/163 PASS.
    - Round 4 (commits 83260c1 + 9206b8c + 76ae2d6) — interim UAT hotfixes (fight-back + UI desync + narrow guards). All three superseded by Task 3a/3b rewrites.
    - Task 2 (UAT) — partial signal: A/C/F-direct/F-reverse (Round 4-fixed) PASS; Bug A (UI freeze on Connect) + Bug B (Settings off → auto-reactivate) discovered. **Codex GPT-5.2 architect review (`06C-ARCHITECT-R5.md`)** диагностировал оба бага как parallel-run hybrid → pull Task 3 cleanup forward, scope expanded.
    - Task 3a ✓ (commit `19f3fe7`) — TunnelController slim 909 → 316 строк; intent-closing on external `.disconnected` (Settings-disable + other-VPN takeover → close intent); `connectInProgress`/`manualDisconnectInProgress` PRESERVED (Round 5 carve-out); old machinery + ReconnectStateObserverRelay GONE.
    - Task 3b ✓ (commit `5b0e28c`) — `applyVPNStatus(_:)` reactive driver — NEVPNStatus authority for BOTH `state` AND `reconnectBannerState`; `.connecting` enum case added, `.retrying`/`.allFailed` dropped (W-02 audit cleared all consumer sites); `TunnelWatchdog.setFailoverObserver(_:)` setter + fire-site wired; App entry points cleaned of stale relay refs; seed initial state at VM init.
    - Task 3c ✓ (commit `69b8ae8`) — DELETED 5 files (RSM + tests + NetReach + tests + TCST); PRESERVED `ReconnectClock.swift` + `TestClocks.swift` (B-01/B-02); NEW `TunnelControllerTests.swift` (7 tests, D-24 cat 2); AppFeatures 133/133 PASS; awk-stripped grep returns 7 (only Round 5 carve-out flags, no forbidden symbols).
    - **Final build verification:** `swift build` + `swift test 133/133` + `xcodebuild BBTB iOS Simulator` + `xcodebuild BBTB-macOS` — все green на main.
    - **Re-UAT outcome (iPhone iOS 26.5, 2026-05-13):**
      - **F-reverse:** ✓ PASS — BBTB active → Happ takeover → BBTB stays off (intent-closing работает).
      - **Settings-disable Round 1:** ⚠️ PARTIAL FAIL — system VPN off, но UI stuck on `.connected` с тикающим таймером. Codex GPT-5.2 architect диагноз: VM `NEVPNStatusDidChange` observer на `queue: .main` теряет notification во время Settings round-trip (app suspended → main queue paused → notification dropped, не replays).
      - **G (passive):** ✓ PASS — zero EXC_RESOURCE / PORT_SPACE crashes.
    - **Follow-up fix landed (commit `44a5630`):** 3 surgical changes в `MainScreenViewModel.swift`:
      1. Observer queue `.main → nil` (match TunnelController; Task hop сохраняет main-actor мутации).
      2. New `MainScreenViewModel.handleForeground()` — one XPC trip на scene `.active`: `loadAllFromPreferences` + `ManagerSelector` filter + read `connection.status` + `connection.connectedDate` → feed `applyVPNStatus(_:connectedDate:)`.
      3. Wire `viewModel.handleForeground()` в `BBTB_iOSApp` + `BBTB_macOSApp` рядом с существующим `tc.handleForeground()`.
      Bonus (Замечание 1): `applyVPNStatus` теперь принимает `connectedDate: Date?` (default nil); `.connected` ветка использует `connectedDate ?? state.connectionStart ?? Date()`. Чинит сценарий «BBTB активирован через iOS Settings → таймер начинает с захода в app». Verification: 133/133 PASS + iOS+macOS xcodebuild SUCCEEDED. **Settings-disable re-tested PASS** (пользователь подтвердил).

  - Wave 4 (06C-05) — pending: regression + UAT.md документация + wiki sync + NET-12 (liveness probe) backlog для Phase 7-8.

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
| 6c | On-demand reconnect migration | v0.6.1 | ✅ Closed 2026-05-13 — re-UAT PASS pair; NET-08..11 Validated |
| 6d | Performance & Code Quality Audit _(INSERTED 2026-05-13)_ | v0.6.2 | ✅ Closed 2026-05-14 — 19 findings closed + 7 post-fix; UAT regression smoke PASS; PERF-01..05 + QUAL-01..03 Validated |
| **6e** | **Performance Audit Round 2 + macOS UAT replay** _(INSERTED 2026-05-14)_ | **v0.6.3** | **Active — next: `/gsd-discuss-phase 6e`** |
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

**Phase 6e INSERTED 2026-05-14 — Performance Audit Round 2 + macOS UAT replay.**

**Следующий шаг:** `/gsd-discuss-phase 6e` — определить scope: какие из 26 carved findings закрывать в 6e vs дальше defer, делать ли numerical Instruments baseline (single capture для regression detection), делать ли macOS UAT replay сейчас или отложить к Phase 11/12.

**Phase 6e scope (входной — из ROADMAP):**

- 6 MEDIUM carved-out findings: M6, M7, M8, M10, M11, M15
- 20 LOW findings: L1-L20
- 3 trivial unused imports
- Optional: numerical Instruments baseline (post-Phase-6d single capture)
- Optional: macOS UAT replay (A/F-direct/F-reverse/Settings-disable/G)

После Phase 6e closure → `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).

**Backlog (carry forward в Phase 7+):**

- **NET-12** (active liveness probe — Pitfall 5 soft-kill server detection) — Phase 7-8. **НЕ в scope 6e.**
- **Historical Phase 6 UAT (sub-tests A-I — DNS leak / IPv6 leak / single-server notification)** — субсумированы Phase 6c re-UAT + 6d regression smoke. Если потребуется отдельный DNS leak / IPv6 leak smoke — Phase 12 pre-TestFlight checklist.

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
*Last updated: 2026-05-14 после закрытия Phase 6d (Performance & Code Quality Audit). 19 findings closed + 7 post-fix correctness commits (cold-start UI freeze + Settings-disable saga). PERF-01..05 + QUAL-01..03 → Validated. 8 фаз closed: 1, 2, 3, 4, 5, 6 (impl), 6c, 6d. Следующий шаг: `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).*
