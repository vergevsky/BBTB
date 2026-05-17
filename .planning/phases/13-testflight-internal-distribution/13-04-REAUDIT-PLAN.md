# Phase 13 / Plan 04 — Re-Audit Post-Fix Verification

**Type:** Read-only quality gate (verification + regression scan)
**Status:** ⚪ EXECUTING (autonomous, no approval gate)
**Created:** 2026-05-17
**Phase:** 13 (TestFlight Internal Distribution v0.13)
**Preconditions:**
- Plan 02 (Pre-TestFlight audit) ✅ DONE — 160 findings в `AUDIT.md`
- Plan 03 (Audit fix-up cycle) ✅ DONE — 17 fix commits на main, all CRITICAL closed
- Baseline: HEAD `55523dd` (post-Plan-03 state)

---

## Goal

Verify quality of Plan 03 fix-up cycle через re-audit ВСЕГО shipping кода (не только изменённых файлов) с тем же 16-reviewer pattern:
1. **Confirm CRITICAL closures** — все 18 CRITICAL findings из Plan 02 actually закрыты в коде, не только marked ✅ в AUDIT.md.
2. **Catch regressions** — Plan 03 фиксы могли ввести новые bugs (refactoring side effects, например group-atomic transaction в RulesEngine, actor-обёртка в ConfigImporter, IPv6 mask regex в DiagnosticsExporter).
3. **Surface новые findings** — что reviewers первого раунда могли пропустить.

**Out of scope:**
- Code fixes (отдельным циклом если найдутся new CRITICAL).
- UI snapshot diffing.
- Device performance benchmarks.
- Test файлы (1936 файлов) — audit shipping кода.

---

## Success Criteria

- ✅ AUDIT-2.md создан с структурой similar к Plan 02 AUDIT.md
- ✅ Все 15 пакетов re-audited той же 16-reviewer allocation
- ✅ Каждый Plan 02 CRITICAL finding явно verified:
  - **Confirmed closed** (reviewer не флагает) OR
  - **Regression detected** (reviewer находит новый или похожий issue) OR
  - **Still open** (fix не полный)
- ✅ Новые findings classified по severity (CRITICAL / HIGH / MEDIUM / LOW)
- ✅ Cross-validation для CRITICAL findings (Opus + Codex agree)
- ✅ Verdict: 🟢 APPROVE / 🟡 CONDITIONAL / 🛑 BLOCK для TestFlight upload

---

## Scope & Allocation (mirror Plan 02)

### HIGH-risk packages — 10 reviewers (5 Opus + 5 Codex parallel)

| Reviewer | Package | Focus |
|---|---|---|
| A1' Opus | PacketTunnelKit | Thread-safety + Security + Energy (verify T-B9 STUN tag + commandServer cleanup; check new staging-file writes в SRSCacheStore) |
| A2' Opus | VPNCore | Thread-safety + Logic + Bugs (verify T-B3 KeychainStore refactor) |
| A3' Opus | MainScreenFeature | Thread-safety + Logic + Energy (verify T-A4 deinit, T-B4 queue, T-B8 timer min, T-B2 ManagerSelector, T-B6 killSwitch defaults) |
| A4' Opus | ConfigParser | Security + Bugs (verify T-A3 SSRF unification, T-A6 size caps, T-A7 sanitize + placeholder DEBUG, T-B5 serializer) |
| A5' Opus | RulesEngine | Security + Thread-safety + Logic (verify T-A1 path traversal + sha256 + group atomic; check Crypto import; SRSCacheStore changes) |
| C1' Codex | PacketTunnelKit | Second-opinion + new regressions |
| C2' Codex | VPNCore | Second-opinion + new regressions |
| C3' Codex | MainScreenFeature | Second-opinion + new regressions |
| C4' Codex | ConfigParser | Second-opinion + new regressions |
| C5' Codex | RulesEngine | Second-opinion + new regressions |

### MEDIUM-risk — 4 reviewers (1 Opus + 3 Codex)

| Reviewer | Packages | Focus |
|---|---|---|
| A6' Opus | All 12 MEDIUM packages | Verify T-B7 ImportHandler + T-B10 CDN allowlist; sweep остальных |
| C6' Codex | SettingsFeature + ServerListFeature | UI features verify |
| C7' Codex | Fronting + DeepLinks + KillSwitch + TransportRegistry | Network infra verify |
| C8' Codex | Protocols/* | **Verify T-A2 — unsafe template paths fully removed**, dict path remains safe |

### LOW-risk — 2 reviewers (1 Opus + 1 Codex)

| Reviewer | Packages | Focus |
|---|---|---|
| A7' Opus | DesignSystem + ProtocolEngine + ProtocolRegistry + Localization + CrashReporter | Quick sanity |
| C9' Codex | Same | Second-opinion |

---

## Output Format — AUDIT-2.md

```markdown
# Pre-TestFlight Re-Audit — Phase 13 Plan 04

**Date:** 2026-05-17
**Reviewers:** 16 (same allocation как Plan 02)
**Baseline:** commit 55523dd (post-Plan-03 fixes)
**Comparison:** Plan 02 `AUDIT.md` (160 findings, 18 CRITICAL)

## Verdict

🟢 APPROVE / 🟡 CONDITIONAL / 🛑 BLOCK

## CRITICAL Closure Verification

| Plan 02 ID | Status | Re-audit reviewer notes |
|---|---|---|
| A3-001 (deinit) | ✅ Confirmed closed | ... |
| C6-001 (IPv6 mask) | ✅ Confirmed closed | ... |
| A4-001 (SSRF) | ✅ Confirmed closed | ... |
| ... (18 rows) | | |

## New Findings (post-Plan-03)

(structured by severity, same format как Plan 02 AUDIT.md)

## Regressions Detected

(если Plan 03 fix ввёл новый issue — flagged here)

## Recommended Action
```

---

## Execution Plan

### Phase 1 — Baseline verification (10 min)
- Confirm xcodebuild green ✅ (done above)
- Confirm relevant tests green (RulesEngine 41/41, SingBoxConfigLoader 57/57, 67 protocol tests)

### Phase 2 — Wave 1 dispatch (~25 min wall time)
- 5 Opus subagents + 5 Codex threads на HIGH-risk packages
- Per-reviewer: write findings к `audit-findings-2/A{1..5}-pkg-opus.md` and `C{1..5}-pkg-codex.md`

### Phase 3 — Wave 2 dispatch (~15 min, parallel с Wave 1)
- 1 Opus + 3 Codex threads на MEDIUM

### Phase 4 — Wave 3 dispatch (~8 min, parallel с Wave 1/2)
- 1 Opus + 1 Codex thread на LOW

### Phase 5 — Aggregation (15 min)
- Read all 16 findings files
- Build AUDIT-2.md с verdict
- Compare против Plan 02 AUDIT.md CRITICAL closure status

---

## Estimated Cost

Same as Plan 02:
- Opus 7 subagents: ~500-800k tokens
- Codex 9 threads: ~350-450k tokens
- Main thread aggregation: ~50k tokens
- **Total:** ~900k-1.3M tokens

---

## Risk: Re-audit может surface new issues

Если CRITICAL найдутся → возможны 2 outcomes:
- **Regression от Plan 03** → fix immediately (Tier A++ task)
- **Missed by Plan 02 reviewers** → classify + decide closure scope

В обоих случаях этот документ обновляется в Phase 5 (Aggregation), новые fix-up tasks начинаются после approval.
