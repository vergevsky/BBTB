# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-11 after Phase 1)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 2 — Trojan + Import flow (v0.2)

## Active Phase

- **Phase:** 2
- **Name:** Trojan + Import flow
- **Status:** Ready to plan
- **Goal:** Расширить импорт до QR-кода и файла, добавить второй протокол (Trojan), включить auto-fallback.
- **Version:** v0.2
- **Requirements:** PROTO-02, PROTO-10, IMP-02, IMP-03, KILL-03 (см. `.planning/REQUIREMENTS.md`)

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | ✓ Complete 2026-05-11 |
| 2 | Trojan + Import flow | v0.2 | Ready to plan |
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

Plan Phase 2 — `/gsd-discuss-phase 2` (контекст) → `/gsd-plan-phase 2` (PLAN.md) → `/gsd-execute-phase 2`.

Phase 2 scope (из ROADMAP.md):
- IMP-02 — QR-код импорт (CameraImporter, iOS + macOS permissions)
- IMP-03 — file-picker импорт (.vless / .json)
- PROTO-02 — Trojan handler в ProtocolRegistry
- PROTO-10 — auto-fallback: при блокировке VLESS+Reality автоматически пробуется Trojan
- KILL-03 — тоггл «Отключить kill switch» в Расширенных (с предупреждением)

## Session Continuity

Last session: 2026-05-11
Stopped at: Phase 1 complete (UAT 5p+1partial+1NA, security 37/37 closed), ready to plan Phase 2
Resume file: None

---
*Last updated: 2026-05-11 после Phase 1 transition. Commits: `9aa3e93` (W5 dual-config) → `0eceed1` (UAT close) → `5b897a5` (security audit) → `913e0c6` (wiki R11).*
