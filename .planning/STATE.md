# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-11 after Phase 1)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 2 — Trojan + Import flow (v0.2)

## Active Phase

- **Phase:** 2
- **Name:** Trojan + Import flow
- **Status:** Implementation complete, ready for device UAT (T1-T9 in `02-UAT.md`)
- **Goal:** ✅ ACHIEVED in code (8/8 SC PASS, 13/13 CONTEXT decisions honored, 0 Phase 1 regressions).
- **Version:** v0.2
- **Resume file:** `.planning/phases/02-trojan-import-flow/02-UAT.md` (next step: user runs T1-T9 on real iPhone)
- **Requirements closed (code-verified):** PROTO-02 ✓, PROTO-10 ✓, IMP-02 ✓, KILL-03 ✓, IMP-04 (foundation) ✓, IMP-05 (foundation) ✓, TRANSP-03 (Trojan-WS) ✓, SRV-* (storage foundation) ✓.
- **Requirements moved out:** IMP-03 (file picker) → Phase 11.

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | ✓ Complete 2026-05-11 |
| 2 | Trojan + Import flow | v0.2 | Implementation complete, ready for device UAT (2026-05-12) |
| 3 | Server management | v0.3 | Not started |
| 4 | Protocol expansion | v0.4 | Not started |
| 5 | Transports | v0.5 | Not started |
| 6 | Network resilience | v0.6 | Not started |
| 7 | Anti-DPI suite + WireGuard family | v0.7 | Not started |
| 8 | Rules Engine + Split tunneling | v0.8 | Not started |
| 9 | Deep links | v0.9 | Not started |
| 10 | Advanced settings + Security polish | v0.10 | Not started |
| 11 | Onboarding + UX polish | v0.11 | Not started |
| 12 | Pre-release + Public TestFlight | v0.12 + v1.0 | Not started |

## Accumulated Context

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

**Device UAT на реальном iPhone** — см. `.planning/phases/02-trojan-import-flow/02-UAT.md` для 9 тестов T1-T9.

Краткий чек-лист:
1. Открыть проект в Xcode (`open BBTB/BBTB.xcworkspace`), запустить на iPhone.
2. **T1**: Импорт subscription URL `https://vpn.vergevsky.ru/sub/VGV...` — пул должен содержать 6+ серверов.
3. **T2**: Импорт multi-line блока 6 URI через буфер обмена — те же 6.
4. **T3**: Импорт JSON endpoint — конфиг загружен.
5. **T4**: Сканирование QR с одним URI — импортирован.
6. **T5**: Connect → проверка через `https://api.ipify.org` (IP изменился).
7. **T6**: Force-block VLESS exit (отключить VLESS Reality порт на сервере либо изменить публичный ключ) → urltest должен переключиться на Trojan-WS. **Самый рискованный тест** — libbox 1.13.11 может выдать сюрпризы.
8. **T7**: Toggle Kill Switch off в Settings → reconnect → проверить что `includeAllNetworks=false`.
9. **T8**: Toggle Kill Switch on → reconnect → восстановить default behavior.
10. **T9**: Wi-Fi ↔ LTE — auto-reconnect.

При device-bug'ах — вернуться к итерации (новая фаза или patch в Phase 2).

После успешного UAT:
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

## Session Continuity

Last session: 2026-05-12
Stopped at: Phase 2 implementation complete via autonomous chain (discuss → ROADMAP/REQ sync → UI-SPEC → RESEARCH → PATTERNS → PLAN → plan-check → execute → security → verify). 8/8 success criteria PASS in code, 147+ unit tests green, 0 Phase 1 regressions. Awaiting device UAT.
Resume file: `.planning/phases/02-trojan-import-flow/02-UAT.md`

---
*Last updated: 2026-05-12 после автономного прогона Phase 2. Phase 2 commits: `ceefc73` (CONTEXT) → `89ef6d7` (ROADMAP/REQ) → `b59bcac` (intel) → `7f063ff` (PLAN) → W0-W6 18 atomic commits → `2c52e27` (security fixes) → `7b39384` (verify). Всего 22 phase-2 commits на main.*
