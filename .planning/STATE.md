---
gsd_state_version: 1.0
milestone: v0.12
milestone_name: + v1.0)
status: completed
stopped_at: context exhaustion at 76% (2026-05-12)
last_updated: "2026-05-12T07:41:42.673Z"
progress:
  total_phases: 12
  completed_phases: 0
  total_plans: 8
  completed_plans: 1
  percent: 0
---

# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-11 after Phase 1)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 2 — Trojan + Import flow (v0.2)

## Active Phase

- **Phase:** 2
- **Name:** Trojan + Import flow
- **Status:** Device UAT в процессе — T0-T4 PASS, T5 retry pending после fix `39356a4`. См. `.planning/phases/02-trojan-import-flow/02-UAT-PROGRESS.md`.
- **Goal:** Implementation complete in code; 2 регрессии найдены и пофикшены через UAT (см. 02-UAT-PROGRESS.md). Полный device UAT в процессе.
- **Version:** v0.2
- **Resume file:** `.planning/phases/02-trojan-import-flow/02-UAT-PROGRESS.md` — содержит next steps, root cause T5, UX findings.
- **Requirements (code-implemented):** PROTO-02, PROTO-10, IMP-02, KILL-03, IMP-04 foundation, IMP-05 foundation, TRANSP-03 (Trojan-WS), SRV-* (storage foundation). Все ждут финального device-теста.
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

**Возобновить UAT с T5 retry.** Полный план в `.planning/phases/02-trojan-import-flow/02-UAT-PROGRESS.md`.

Короткая версия:

1. В уже открытом Xcode → **Stop** (⌘.) → **Run** (⌘R). Пересоберёт с фиксом `39356a4` и переустановит на iPhone.
2. На iPhone — pool остался в SwiftData после T4. Tap **power-кнопку** (без re-import).
3. Ожидается state `.connected`, Safari → `api.ipify.org` показывает `185.237.218.81`.
4. Если PASS — продолжить с T6 (broken URI failover), T7-T9 (kill switch).
5. Если FAIL — собрать новые OSLog через Console.app (filter `bbtb`, 30s после tap).

## UAT findings (накапливаются)

**Fixed во время UAT:**
- `6d0f798` — TrojanURIParser default fingerprint при пустом `fp=` (был `""`, стал `"chrome"`).
- `39356a4` — ConfigImporter `serverAddress` ставился literal `"BBTB"`, что отвергалось iOS как невалидный `tunnelRemoteAddress`. Восстановлено Phase 1 поведение (host первого outbound).

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

## Session Continuity

Last session: 2026-05-12T07:41:42.667Z
Stopped at: context exhaustion at 76% (2026-05-12)
Resume file: `.planning/phases/02-trojan-import-flow/02-UAT.md`

---
*Last updated: 2026-05-12 после автономного прогона Phase 2. Phase 2 commits: `ceefc73` (CONTEXT) → `89ef6d7` (ROADMAP/REQ) → `b59bcac` (intel) → `7f063ff` (PLAN) → W0-W6 18 atomic commits → `2c52e27` (security fixes) → `7b39384` (verify). Всего 22 phase-2 commits на main.*
