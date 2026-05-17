# Phase 13 / Plan 06 — Third Pre-TestFlight Audit Cycle

**Type:** Read-only quality gate (third pass)
**Status:** ⚪ EXECUTING
**Created:** 2026-05-17
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Baseline:** HEAD `fb2ff54` (post-Plan-05 Tier-A++/B/C + Tier-D LOW closure)

---

## Context

После двух предыдущих audit циклов:

- **Plan 02 (AUDIT.md)** — initial 16-reviewer sweep, 160 findings.
- **Plan 04 (AUDIT-2.md)** — re-audit Plan 03 closures, ~95 new findings (4 partial + 2 NEW CRITICAL + 11 HIGH + ~30 MEDIUM + ~50 LOW).
- **Plan 05** — autonomous fix-up cycle, 25 findings closed across 16 atomic commits (3 CRITICAL + 8 HIGH + 9 MEDIUM + 4 LOW + 1 wiki doc).

Этот **Plan 06 audit** проверяет:
1. **No regressions** введённых Plan 05 fixes.
2. **No new vulnerabilities** созданных рефакторами (особенно T-A3' numeric IP parser, T-B5' real mutex, T-B3' generation atomic swap, T-B4' allowlist regex).
3. **Carry-forward acceptance** — действительно ли deferred items (LOW polish, A6'-006 placeholder URL, v1.1+ TODOs) безопасны для ship.
4. **Cross-cutting concerns** invisible per-package — systemic patterns в reactive paths, Swift 6 strict concurrency, energy.

---

## Goal

Catch критические bugs / security / concurrency / energy / logic issues which would embarrass on real-device user — на baseline `fb2ff54`.

**Out of scope** (same as Plan 02):
- Code fixes (отдельный Plan 07 fix-up если будут blocking findings)
- UI snapshot diffing
- Tests directories
- Fuzz / property-based testing

---

## Success Criteria

- ✅ AUDIT-3.md создан с structure mirror Plan 02 (`13-02-AUDIT-PLAN.md` output section)
- ✅ Все 15 packages покрыты HIGH×2/MEDIUM×1/LOW×1 reviewer
- ✅ Findings classified по severity
- ✅ Каждый finding — location (path:line) + description + why-it-matters + suggested-fix
- ✅ CRITICAL findings cross-validated Opus + Codex
- ✅ Verdict: 🟢 APPROVE / 🟡 CONDITIONAL APPROVE / 🛑 BLOCK

---

## Methodology — identical to Plan 02

### Wave 1 — HIGH-risk (5 Opus + 5 Codex parallel)

| Reviewer | Package | Output file |
|---|---|---|
| A1 (Opus) | PacketTunnelKit | `audit-3-reviewers/A1-pkt.md` |
| A2 (Opus) | VPNCore | `audit-3-reviewers/A2-vpncore.md` |
| A3 (Opus) | MainScreenFeature | `audit-3-reviewers/A3-mainscreen.md` |
| A4 (Opus) | ConfigParser | `audit-3-reviewers/A4-configparser.md` |
| A5 (Opus) | RulesEngine | `audit-3-reviewers/A5-rulesengine.md` |
| C1 (Codex) | PacketTunnelKit | `audit-3-reviewers/C1-pkt.md` |
| C2 (Codex) | VPNCore | `audit-3-reviewers/C2-vpncore.md` |
| C3 (Codex) | MainScreenFeature | `audit-3-reviewers/C3-mainscreen.md` |
| C4 (Codex) | ConfigParser | `audit-3-reviewers/C4-configparser.md` |
| C5 (Codex) | RulesEngine | `audit-3-reviewers/C5-rulesengine.md` |

### Wave 2 — MEDIUM (1 Opus + 3 Codex parallel)

| Reviewer | Packages | Output file |
|---|---|---|
| A6 (Opus) | SettingsFeature + ServerListFeature + FrontingEngine + DeepLinks + KillSwitch + TransportRegistry + Protocols/* | `audit-3-reviewers/A6-medium.md` |
| C6 (Codex) | SettingsFeature + ServerListFeature | `audit-3-reviewers/C6-ui.md` |
| C7 (Codex) | FrontingEngine + DeepLinks + KillSwitch + TransportRegistry | `audit-3-reviewers/C7-infra.md` |
| C8 (Codex) | Protocols/* (6 protocols) | `audit-3-reviewers/C8-protocols.md` |

### Wave 3 — LOW (1 Opus + 1 Codex parallel)

| Reviewer | Packages | Output file |
|---|---|---|
| A7 (Opus) | DesignSystem + ProtocolEngine + ProtocolRegistry + Localization + CrashReporter | `audit-3-reviewers/A7-low.md` |
| C9 (Codex) | (same) | `audit-3-reviewers/C9-low.md` |

### Wave 4 — Aggregation (main thread)

1. Read all 16 reviewer output files
2. Dedupe overlapping findings
3. Mark cross-validated (Opus + Codex agree) vs single-source (verify needed)
4. Detect cross-package systemic patterns
5. Write `AUDIT-3.md` mirror Plan 02 format
6. Present verdict + recommendation

---

## Constraints на reviewers

- **READ-ONLY** sandbox (no edits)
- **Compare against Plan 04 / AUDIT-2.md** — не повторяй закрытые findings (Plan 05 commits 986c2af, 1883035, 86dd31e, 2952871, 515f8dc, 74dd020, c1ee6b4, 4f916d7, 6244b8b, f909b5b, 81d7ea6, ce130bf, 81d0418, 2b49a23, fb2ff54)
- **File:line citations mandatory** — no vague "somewhere in package"
- **Severity calibration:**
  - CRITICAL = exploitable / data leak / data loss / connection broken
  - HIGH = bug в hot path / correctness gap / race
  - MEDIUM = edge case / performance / DX
  - LOW = code smell / docs / cleanup
- **Output format** — markdown с per-finding template (path:line + severity + dimension + description + why + fix)
- **Размер**: ≤2000 lines per reviewer file (compressed structured findings)

---

## Estimated wall time + cost

Same as Plan 02 (~35-45 min, ~800k-1.05M tokens). Justified: third audit gate, last check before TestFlight upload.

---

## Risks + Mitigation

| Risk | Mitigation |
|---|---|
| Reviewers повторяют Plan 02/04 findings, не учитывая Plan 05 closures | Caveat в prompt'е: «assume Plan 05 closures landed at commit X-Y; verify open issues only» + path к AUDIT-2.md |
| Context overflow на main thread aggregation | Каждый reviewer пишет в файл; main thread читает 16 файлов sequentially, не batch'ит raw output'ы в context |
| False-positive flood (особенно security от Codex) | Same severity calibration prompt как Plan 02 |
| Codex SSE timeout | Per-package thread (Wave 1 HIGH), per-group Codex split (Wave 2 MEDIUM 3-way split) |
| Cross-cutting issues пропущены | Wave 4 main-thread pattern detection после reading all 16 files |
