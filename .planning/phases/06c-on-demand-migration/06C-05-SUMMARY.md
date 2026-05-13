---
phase: 06c-on-demand-migration
plan: 05
type: summary
status: complete
date: 2026-05-13
commits:
  - "44a5630 — Round 6 re-UAT follow-up (VM foreground resync + connectedDate authority)"
  - "efd52fb — Round 6 docs sync (STATE/ROADMAP/REQUIREMENTS/SUMMARY/REVISION-LOG/wiki)"
  - "<pending> — Plan 05 closure docs (06C-UAT.md + STATE/PROJECT touchups + this SUMMARY)"
---

# Plan 06C-05 — Final closure SUMMARY

## Status

**Phase 6c officially closed 2026-05-13.** All 4 Plan 05 tasks resolved (3 done within Round 6 cycle, Task 1 done in this closure step). Hard-blocker UAT set PASS (6/7, E carved out to NET-12).

## How Plan 05 scope landed

Plan 05 was a **document-and-close wave** by design — no code changes. Most of its scope ended up landing in **Round 6 cycle** (commits `44a5630` + `efd52fb`) because the re-UAT discovered the last UI desync and demanded a code fix; the doc sync naturally followed in the same cycle. This closure step finishes the residual artifacts.

| Plan 05 task | Landed where |
|---|---|
| **Task 1 — Create `06C-UAT.md`** | ✅ This closure step (file created with 9 Phase 6c scenarios + Settings-disable + Phase 1-6 regression smoke + decisions + metrics + closure checklist). |
| **Task 2 — Update STATE/PROJECT/REQUIREMENTS/ROADMAP** | ⅔ in commit `efd52fb`: REQUIREMENTS NET-08..11 promoted `[ ] → [x]`; ROADMAP Phase 6c Wave 4 marked Complete; STATE.md Wave 3 status updated. ⅓ in this closure step: STATE.md `Current focus` line + PROJECT.md R18 status wording «awaiting re-UAT» → «✅ Closed» + Last updated bumped. |
| **Task 3 — Wiki sync** | ✅ Done in commit `efd52fb`: `wiki/auto-reconnect.md` Last updated + two new subsections («VM foreground resync» + «connectedDate authority»); `wiki/index.md` already had the link from prior check-up commit `abcd53a`; `wiki/log.md` Round 6 entry appended. |
| **Task 4 — Final review checkpoint** | ⏳ This closure step → checkpoint completes upon human PASS signoff (user already signed off the three Round 6 re-UAT scenarios verbally before this commit). |

## Files modified in this closure step

**Created:**
- `.planning/phases/06c-on-demand-migration/06C-UAT.md` — formal UAT report (~230 lines, all sections per Plan 05 Task 1 spec + Round 6 extension).
- `.planning/phases/06c-on-demand-migration/06C-05-SUMMARY.md` (this file).

**Modified:**
- `.planning/STATE.md` — `Current focus` line updated from «Phase 06 — network resilience» to «Phase 6c ✓ Complete 2026-05-13 — next: proposed Phase 6d».
- `.planning/PROJECT.md` — R18 row Status column: «✓ Закрыто на main, awaiting re-UAT» → «✅ Closed 2026-05-13 — re-UAT PASS». Last-updated footer bumped.

## File counts

| Category | Count |
|----------|-------|
| New planning artifacts | 2 (06C-UAT.md + 06C-05-SUMMARY.md) |
| New wiki pages | 0 (auto-reconnect.md was created Round 5; updated this cycle) |
| Modified planning artifacts | 6 (STATE, PROJECT, REQUIREMENTS, ROADMAP, 06C-04-SUMMARY, 06C-REVISION-LOG) — across full Round 6 cycle |
| Modified wiki files | 2 (auto-reconnect.md, log.md) |

## Phase 6c — final metrics (rolled up)

### Code net delta

| Direction | Lines | Notes |
|-----------|-------|-------|
| Removed (5 files deleted Task 3c) | ~1401 | RSM + NetReach + 3 test files |
| Removed (TunnelController slim) | -593 | 909 → 316 |
| Added (7 new files + supporting) | ~700 | OnDemandRulesBuilder + Migration + Watchdog + ManagerSelector + Round 6 `handleForeground()` + tests |
| **Net delta** | **≈ −1300 lines** | Целевая code reduction достигнута и превзойдена |

### Test counts (AppFeatures)

- Wave 0: 138/138
- Wave 1: 145/145
- Wave 2: 163/163
- Wave 3 (after Task 3c deletes): **133/133**
- Round 6 follow-up: **133/133** (no regressions)

### UAT outcome

- Hard-blocker set per Round 2 B-10: **6/7 PASS** (A, C, F-reverse, G, I, Settings-disable). 1 deferred (E → NET-12 backlog).
- Phase 1-6 regression smoke: **0 регрессий** обнаружено.

### Build verification (final)

- `swift test --package-path BBTB/Packages/AppFeatures` → **133/133 PASS** in 7.4s.
- `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build` → **BUILD SUCCEEDED**.
- `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` → **BUILD SUCCEEDED**.

## Decision/Spec references

- **D-18..D-22** — confirmed (see `06C-UAT.md` Section 3).
- **Round 5 architect additions** — intent-closing on external disconnect + reactive UI driver — confirmed via F-reverse + Settings-disable PASS.
- **Round 6 follow-up fix** — observer queue `.main → nil` + `handleForeground()` resync + `connectedDate` authority — confirmed via Settings-disable re-test PASS.

## Memory updates (already landed in Round 6 cycle)

- `project_phase6c_resume_checkpoint.md` REMOVED.
- `project_phase6c_complete.md` CREATED.
- `feedback_nevpn_observer_queue_main.md` CREATED.
- `feedback_connectedDate_authority_for_since.md` CREATED.
- `MEMORY.md` index updated.

## Open carve-outs (deferred to future phases)

- **`NET-12: active liveness probe`** (Phase 7-8) — sing-box `Cmd_LogClient` polling или app-side HTTP ping для detection «tunnel formally `.connected` но не передаёт трафик» (Pitfall 5 / scenario E).
- **macOS-specific UAT replay** — Phase 6c сценарии A/F-reverse/Settings-disable/G выполнялись только на iOS; macOS pathway architecturally идентичен (одни и те же VM + TunnelController source), но не отдельно UAT'ом подтверждался. Risk низкий, но future cycle стоит включить macOS-UAT.
- **Замечание 2 от пользователя** (производительность с Phase 5+) — выделено в **новую Phase 6d (Performance & Code Quality Audit, multi-AI peer review)** перед Phase 7.

## Next steps

1. Этот commit закрывает Phase 6c documentation.
2. Затем `/gsd-phase` — вставить новую **Phase 6d** в ROADMAP.md перед Phase 7.
3. Затем `/gsd-discuss-phase 6d` — собрать контекст для Performance Audit (что именно «тяжело грузится», какой scope, какие AIs приглашаем, как организуем findings).

**Phase 7 (Anti-DPI suite + WireGuard family)** остаётся следующим feature-релизом после Phase 6d.
