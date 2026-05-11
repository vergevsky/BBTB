# Project State

## Project Reference

See: `.planning/PROJECT.md` (initialized 2026-05-11)

**Project codename:** `BBTB` (display name «Верни жука» / «Bring Back the Bug»)
**Core value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.

**Current focus:** Phase 1 — Foundation (v0.1)

## Active Phase

- **Phase:** 1
- **Name:** Foundation
- **Status:** W0..W5 + W3.1 gap-closure complete; validate-r1-r6.sh green (11 invariants + 8 SPM test packages PASS); **only blocker is W5-T4 manual device DoD**
- **Goal:** Минимально жизнеспособная сборка с VLESS+Vision+Reality, kill switch и базовой архитектурой SwiftPM.
- **Context file:** `.planning/phases/01-foundation/01-CONTEXT.md`
- **Build system:** Tuist 4.x (`BBTB/Project.swift` + `BBTB/Workspace.swift`)
- **libbox.xcframework:** built from sing-box v1.13.11 via `make lib_apple`; postprocessed via `BBTB/scripts/fix-libbox-xcframework.sh`
- **Dev workflow:** `bash BBTB/scripts/dev-bootstrap.sh` resolves SPM, generates xcodeproj, builds both schemes

## W3.1 Gap-Closure (TUN inbound cleanup)

- **Status:** ✓ Complete 2026-05-11 — все 5 tasks + 2 побочных fix'а закоммичены атомарно.
- **Plan:** `.planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-PLAN.md`
- **Summary:** `.planning/phases/01-foundation/01-W3.1-tun-inbound-cleanup-SUMMARY.md`
- **What changed:** R1 валидатор ослаблен (forbidden = {socks, http, mixed, redirect, tproxy}); публичный `SingBoxConfigLoader.expandConfigForTunnel`; hack убран из `BaseSingBoxTunnel`; wiki R10 закрывает архитектурное решение.

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

W5-T4 manual device DoD (см. `.planning/phases/01-foundation/security-evidence/README.md`):
- DoD #1 api.ipify.org IP swap на iPhone + Mac
- DoD #2 kill switch blocks traffic on tunnel drop
- R1 SocksProbe screenshots (all ports closed)
- R6 POINTOPOINT: NO screenshots
- DIST-01/DIST-02 archive smoke

После — `/gsd-verify-work 1`.

---
*Last updated: 2026-05-11 after W3.1 gap-closure completion (TUN inbound runtime expansion moved from BaseSingBoxTunnel hack into SingBoxConfigLoader; wiki R10 closed; all 11 static invariants + 8 SPM test packages green).*
