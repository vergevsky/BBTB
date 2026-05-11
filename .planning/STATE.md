# Project State

## Project Reference

See: `.planning/PROJECT.md` (initialized 2026-05-11)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 1 — Foundation (v0.1)

## Active Phase

- **Phase:** 1
- **Name:** Foundation
- **Status:** Build green (iOS Simulator + macOS BUILD SUCCEEDED); blocking on W5-T4 device DoD
- **Goal:** Минимально жизнеспособная сборка с VLESS+Vision+Reality, kill switch и базовой архитектурой SwiftPM.
- **Context file:** `.planning/phases/01-foundation/01-CONTEXT.md`
- **Build system:** Tuist 4.x (`BBTB/Project.swift` + `BBTB/Workspace.swift`)
- **libbox.xcframework:** built from sing-box v1.13.11 via `make lib_apple`; postprocessed via `BBTB/scripts/fix-libbox-xcframework.sh`
- **Dev workflow:** `bash BBTB/scripts/dev-bootstrap.sh` resolves SPM, generates xcodeproj, builds both schemes

## Progress

| Phase | Name | Version | Status |
|-------|------|---------|--------|
| 1 | Foundation | v0.1 | Not started |
| 2 | Trojan + Import flow | v0.2 | Not started |
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

## Next Action

`/gsd-plan-phase 1` — создать PLAN.md фазы 1 на основе зафиксированного контекста.

---
*Last updated: 2026-05-11 after `/gsd-discuss-phase 1` — rebrand YourVPN → BBTB + 4 implementation decisions captured.*
