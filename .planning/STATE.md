# Project State

## Project Reference

See: `.planning/PROJECT.md` (updated 2026-05-11 after Phase 1)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 2 — Trojan + Import flow (v0.2)

## Active Phase

- **Phase:** 2
- **Name:** Trojan + Import flow
- **Status:** Context gathered, ready for research/planning
- **Goal:** Расширить v0.1 до universal-парсера всех трёх форматов раздачи ссылок (subscription URL / multi-line URI / JSON endpoint), второго протокола (Trojan-TCP/TLS + Trojan-WS/TLS), auto-fallback через sing-box `urltest` outbound, toggle отключения kill switch.
- **Version:** v0.2
- **Resume file:** `.planning/phases/02-trojan-import-flow/02-CONTEXT.md`
- **Requirements (original):** PROTO-02, PROTO-10, IMP-02, IMP-03, KILL-03
- **Requirements (scope расширен в discuss-phase):** IMP-04 partial (universal parser foundation), IMP-05 partial, TRANSP-03 partial (WebSocket для Trojan), SRV-* foundation (SwiftData массив + isSupported). IMP-03 (file picker) **переехал в Phase 11** (UX-01 onboarding).

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

`/gsd-plan-phase 2` (с research) или `/gsd-ui-phase 2` (UI design contract — UI в этой фазе значительный) → `/gsd-execute-phase 2`.

**Перед planner'ом рекомендуется обновить:**
- `.planning/ROADMAP.md` — Phase 2 goal расширен (universal parser, 3 формата импорта, foundation для IMP-04/05, TRANSP-03 partial, SRV-* storage). IMP-03 переехал в Phase 11.
- `.planning/REQUIREMENTS.md` — пометить IMP-03 как «moved → Phase 11»; IMP-04/IMP-05/TRANSP-03/SRV-* отметить «partial — Phase 2 foundation, Phase 3/4 finish».

**Phase 2 scope (после discuss-phase) — см. `.planning/phases/02-trojan-import-flow/02-CONTEXT.md`:**
- PROTO-02 — Trojan handler (TCP+TLS и WS+TLS) в ProtocolRegistry
- PROTO-10 — auto-fallback через sing-box `urltest` outbound
- IMP-02 — QR-код импорт (CameraImporter, iOS + macOS permissions, NSCameraUsageDescription)
- IMP-04 partial — universal parser: subscription URL fetch + multi-line text + JSON endpoint
- IMP-05 partial — Outline/Clash YAML формально не делаем, но универсальный URI парсер видит все схемы
- TRANSP-03 partial — WebSocket transport для Trojan
- SRV-* foundation — SwiftData массив `ServerConfig` с isSupported / subscriptionURL полями
- KILL-03 — toggle в новой Settings page → «Безопасность», применяется при следующем connect
- **UI переработка**: TopBar (≡ слева + plus справа), новый layout idle (timer→pill→power→server-line), empty-state карточка, новый AppFeatures/SettingsFeature package
- **Тестовые кейсы**: 3 реальных формата ссылок пользователя на `vpn.vergevsky.ru` инфре (см. CONTEXT.md `<specifics>`)

## Session Continuity

Last session: 2026-05-11
Stopped at: Phase 2 context gathered (4 grey areas обсуждены, 15 decisions captured). Phase 2 scope расширен относительно оригинального ROADMAP.
Resume file: `.planning/phases/02-trojan-import-flow/02-CONTEXT.md`

---
*Last updated: 2026-05-11 после `/gsd-discuss-phase 2`. Phase 1 transition commits: `9aa3e93` → `0eceed1` → `5b897a5` → `913e0c6`. Phase 2 discuss artefacts — текущий commit.*
