# Phase 6e: Performance Audit Round 2 + macOS UAT replay — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14
**Phase:** 6e — Performance Audit Round 2 + macOS UAT replay
**Areas discussed:** Findings scope, Numerical Instruments baseline, macOS UAT replay, Closure rigor

---

## Findings scope

| Option | Description | Selected |
|--------|-------------|----------|
| MEDIUM + trivial imports (~9) | Закрываем 6 MEDIUM + 3 trivial imports. ~3-4 дня. 20 LOW остаются в backlog forever либо opportunistic cleanup в Phase 7+. (Recommended by Claude) | |
| Всё подряд — все 26 findings | Максимально чистая база перед Phase 7. ~1-2 недели. Риск что LOW — chore work с unclear impact. | ✓ |
| Только trivial imports (~3) | Bare minimum cleanup, ~30 минут. | |
| HIGH-leverage subset (8-10 cherry-picked) | Claude выбирает best impact/effort из 26. Остальные carved forever. ~2-3 дня. | |

**User's choice:** Всё подряд — все 26 findings
**Notes:** User приоритизирует maximally clean baseline перед Phase 7 (Anti-DPI + WireGuard — большой объём нового кода). Phase 6e должна быть «нулевая точка отсчёта» для performance regressions в Phase 7+.

---

## Numerical Instruments baseline

| Option | Description | Selected |
|--------|-------------|----------|
| Снять полный — все 4 dimensions | Time Profiler + ConnectTap + Energy Log + Allocations. ~30-45 мин. Baseline для Phase 7+ regression alerts. (Recommended by Claude) | |
| Снять минимум — только Time Profiler key spans | ColdLaunch + ConnectTap spans. ~15 мин. | |
| Skip — defer к Phase 11/12 pre-TestFlight | Не снимаем сейчас. Phase 11/12 обязательно покрывает. | ✓ |

**User's choice:** Skip — defer к Phase 11/12 pre-TestFlight
**Notes:** Velocity priority — Phase 6e не должна быть отвлечением на verification activities когда есть конкретные carved findings к закрытию. PerfSignposter инструментация (DEC-06d-06) уже сохранена в production code — pre-TestFlight snap (Phase 11/12) даст полноценный baseline для production release.

---

## macOS UAT replay

| Option | Description | Selected |
|--------|-------------|----------|
| Сейчас — partial (F-reverse + Settings-disable) | 2 macOS-specific risk scenarios. ~15-20 мин. NSWorkspace observer + Settings UI могут расходиться с iOS. (Recommended by Claude) | |
| Сейчас — full replay (5 hard-blocker scenarios) | A + F-direct + F-reverse + Settings-disable + G на MacBook. ~45-60 мин. | |
| Skip — defer к Phase 11/12 | macOS path = same source code как iOS; risk низкий. Phase 11/12 обязательно покрывает. | ✓ |

**User's choice:** Skip — defer к Phase 11/12
**Notes:** Same source code на iOS и macOS снижает risk. Phase 11/12 (pre-TestFlight polish) обязательно делает отдельную macOS UAT-сессию. Phase 6e фокусируется на cleanup, не verification.

---

## Closure rigor

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid — full rigor для MEDIUM, light для LOW bundle | Каждый MEDIUM atomic + gate. LOW bundle commits + single gate. (Recommended by Claude) | ✓ |
| Same as Phase 6d — full per-commit rigor | Каждый fix atomic + gate. Полный closure SUMMARY + wiki sync + STATE/ROADMAP/REQUIREMENTS. Max safety, max overhead. | |
| Lighter — bundle commits, single gate at end | Findings группируются (1-3 commits). Single gate в конце. Минимум docs. Быстрее, но risk что регрессия проскочит. | |

**User's choice:** Hybrid — full rigor для MEDIUM, light для LOW bundle
**Notes:** Balances safety (MEDIUM individually verified) с pragmatism (LOW bundle не требует 20 gate passes). Phase 6e closure SUMMARY будет compact (не full Phase 6d-style 200-line record, а tight 1-2 line per finding).

---

## Claude's Discretion

- **Wave structure** — planner выбирает 2-3 waves (MEDIUM individually + LOW bundle + closure). Pragmatic clustering.
- **LOW bundle theming** — planner organizes 20 LOW findings по smart themes (naming, dead-code, unused imports, comments). Not blocking optimal grouping.
- **Researcher scope** — `gsd-phase-researcher` reads 06D-FINDINGS.md + cross-references post-6d code state. Output: RESEARCH.md с per-finding current-state assessment (still applicable / partially-addressed-already / invalidated by post-6d commits).
- **Multi-AI delegation** — НЕ re-spawn 3-AI peer review. Architect mode (Codex via mcp__codex__codex) допустим как fallback if 2+ failures на same finding (per Delegator rule).
- **Slug awkwardness** — directory name `06e-performance-audit-round-2-macos-uat-replay` отражает первоначальный ROADMAP scope; macOS UAT было deferred в discuss. Slug оставлен as-is для git history consistency. Closure SUMMARY noted divergence.

## Deferred Ideas

- **Numerical Instruments baseline** → Phase 11/12 (pre-TestFlight obligatory).
- **macOS UAT replay (5 scenarios)** → Phase 11/12.
- **3-AI re-audit для post-Phase-6e** → если в Phase 7-10 будет замечена performance regression, рассмотреть на отдельной Phase 6f «Performance Audit Round 3». НЕ блокировать Phase 7.
- **NET-12 (active liveness probe)** → Phase 7-8 (Phase 6c carve-out, выходит за scope 6e).
