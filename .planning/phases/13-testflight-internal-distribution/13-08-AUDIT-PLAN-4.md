# Phase 13 / Plan 08 — Fourth Pre-TestFlight Audit Cycle

**Type:** Read-only quality gate (fourth pass)
**Status:** ⚪ EXECUTING
**Created:** 2026-05-17
**Baseline:** HEAD `ccbce8a` (post-Plan-07 — 17 atomic fix commits)

---

## Context

Audit-history к настоящему моменту:
- **Plan 02 (AUDIT.md)** — initial 16-reviewer sweep, 160 findings.
- **Plan 04 (AUDIT-2.md)** — re-audit Plan 03 closures, ~95 new findings.
- **Plan 05** — autonomous fix-up, 25 findings closed.
- **Plan 06 (AUDIT-3.md)** — re-audit Plan 05 closures, ~135 new findings (0 CRITICAL, ~14 HIGH).
- **Plan 07** — autonomous fix-up, 23 highest-impact findings closed (4 CV-HIGH + 2 regressions + 8 single-source HIGH + 5 MEDIUM + 4 LOW).

**Plan 08 audit** проверяет:
1. **No regressions** введённых Plan 07 fixes — это самый important checkpoint. Plan 07 трогал hot paths (BaseSingBoxTunnel, ExtensionPlatformInterface, TunnelController single-flight, ProvisionSerializer split).
2. **No new vulnerabilities** созданных рефакторами.
3. **Carry-forward acceptance** — действительно ли deferred items (~30 MEDIUM + ~40 LOW от Plan 06) безопасны для ship.
4. **Cross-cutting concerns** — Swift 6 strict concurrency после concurrency-heavy refactors.

---

## Methodology — identical to Plan 02/04/06

### Wave 1 — HIGH-risk (5 Opus + 5 Codex parallel)

| Reviewer | Package | Output file |
|---|---|---|
| A1 (Opus) | PacketTunnelKit | `audit-4-reviewers/A1-pkt.md` |
| A2 (Opus) | VPNCore | `audit-4-reviewers/A2-vpncore.md` |
| A3 (Opus) | MainScreenFeature | `audit-4-reviewers/A3-mainscreen.md` |
| A4 (Opus) | ConfigParser | `audit-4-reviewers/A4-configparser.md` |
| A5 (Opus) | RulesEngine | `audit-4-reviewers/A5-rulesengine.md` |
| C1 (Codex) | PacketTunnelKit | `audit-4-reviewers/C1-pkt.md` |
| C2 (Codex) | VPNCore | `audit-4-reviewers/C2-vpncore.md` |
| C3 (Codex) | MainScreenFeature | `audit-4-reviewers/C3-mainscreen.md` |
| C4 (Codex) | ConfigParser | `audit-4-reviewers/C4-configparser.md` |
| C5 (Codex) | RulesEngine | `audit-4-reviewers/C5-rulesengine.md` |

### Wave 2 — MEDIUM (1 Opus + 3 Codex parallel)

| Reviewer | Packages | Output file |
|---|---|---|
| A6 (Opus) | SettingsFeature + ServerListFeature + FrontingEngine + DeepLinks + KillSwitch + TransportRegistry + Protocols/* | `audit-4-reviewers/A6-medium.md` |
| C6 (Codex) | SettingsFeature + ServerListFeature | `audit-4-reviewers/C6-ui.md` |
| C7 (Codex) | FrontingEngine + DeepLinks + KillSwitch + TransportRegistry | `audit-4-reviewers/C7-infra.md` |
| C8 (Codex) | Protocols/* (6 protocols) | `audit-4-reviewers/C8-protocols.md` |

### Wave 3 — LOW (1 Opus + 1 Codex parallel)

| Reviewer | Packages | Output file |
|---|---|---|
| A7 (Opus) | DesignSystem + ProtocolEngine + ProtocolRegistry + Localization + CrashReporter | `audit-4-reviewers/A7-low.md` |
| C9 (Codex) | (same) | `audit-4-reviewers/C9-low.md` |

### Wave 4 — Aggregation → `AUDIT-4.md`

---

## Constraints на reviewers

- **READ-ONLY** sandbox (no edits)
- **Compare against Plan 06 / AUDIT-3.md** — не повторять Plan 06 findings уже закрытые в Plan 07 (commits `9da8c96 → ccbce8a`)
- **File:line citations mandatory** — no vague "somewhere in package"
- **Severity calibration:** same as prior plans (CRITICAL=exploitable/leak; HIGH=hot-path bug; MEDIUM=edge case; LOW=smell)
- **Особое внимание Plan 07-touched files:** BaseSingBoxTunnel (lifecycle queue), ExtensionPlatformInterface (state queue), TunnelController (single-flight), ConfigImporter (split mutex), MainScreenViewModel (.disconnected gate + observer coalescing), SubscriptionURLFetcher (NAT64), UniversalImportParser (VLESS+TLS dispatch), SingBoxConfigLoader (rule_set allowlist).

---

## Estimated wall time + cost

Same as prior audits (~35-45 min, ~800k-1.05M tokens).
