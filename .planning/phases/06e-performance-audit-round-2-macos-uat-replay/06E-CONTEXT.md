# Phase 6e: Performance Audit Round 2 + macOS UAT replay — Context

**Gathered:** 2026-05-14
**Status:** Ready for planning

<domain>
## Phase Boundary

**Что Phase 6e делает:** tactical cleanup-фаза после Phase 6d. Закрывает оставшиеся **26 carved-out findings** из Phase 6d (6 MEDIUM + 20 LOW + 3 trivial unused imports). Цель — maximally clean baseline перед Phase 7 (Anti-DPI + WireGuard family — большой объём нового кода, проще ревью когда predecessor чистый).

**Что Phase 6e НЕ делает (per discuss-phase decisions):**
- **НЕ снимает numerical Instruments baseline.** User выбрал defer к Phase 11/12 (pre-TestFlight obligatory snap). Phase 6e работает на existing descriptive analysis из Phase 6d; PerfSignposter инструментация уже готова (DEC-06d-06) для будущего capture.
- **НЕ делает macOS UAT replay.** User выбрал defer к Phase 11/12. Phase 6c/6d Phase 6c/6d scenarios A/F-direct/F-reverse/Settings-disable/G на macOS — pre-TestFlight checklist.
- **НЕ закрывает NET-12** (active liveness probe — explicit Phase 7-8 carve-out из Phase 6c).
- **НЕ добавляет новых фич.** Только cleanup / refactor / dead-code removal / unused imports.
- **НЕ ломает 6 architectural patterns DEC-06d-01..06** (cold-start init defer, XPC consolidation, event-driven status polling, bounded probe concurrency, Apple-canonical options discriminator + sticky marker, PerfSignposter spans).
- **НЕ ломает D-09 invariants Phase 6c** (forbidden symbols grep ≤ 7, observer queue=nil, `#Predicate` UUID? = 0, applyVPNStatus single authority, sliding window).

**Версия:** v0.6.3 (patch). Phase 7 стартует только после Phase 6e closure.

**Note по slug:** directory name `06e-performance-audit-round-2-macos-uat-replay` отражает первоначальный (max-scope) ROADMAP entry. После discuss-phase macOS UAT было deferred. Slug оставлен as-is для git history consistency.

</domain>

<decisions>
## Implementation Decisions

### Scope budget (D-01..D-04)

- **D-01: Findings scope — ALL 26 carved findings.** User выбрал максимальную очистку. Включает:
  - **6 MEDIUM (carved Phase 6d):** M6, M7, M8, M10, M11, M15 — см. `.planning/phases/06d-performance-audit/06D-FINDINGS.md` (полное описание + file:line + recommended fix per finding).
  - **20 LOW:** L1-L20 — см. `06D-FINDINGS.md` (code quality / minor cleanup).
  - **3 trivial unused imports:** см. `.planning/phases/06d-performance-audit/06D-PERIPHERY-POST-FIX.md`.
- **D-01a:** Researcher (gsd-phase-researcher) MUST cross-check каждое carved finding против post-Phase-6d code state — некоторые могут быть incidentally addressed одним из 7 post-fix commits (cold-start UI freeze block + Settings-disable saga). Если finding уже invalid (fix landed) — promoted к "closed in 6d post-fix" с reference SHA, не re-fixed.
- **D-01b:** Planner может re-organize sub-themes если useful (e.g., bundle related LOW findings together) — но individual MEDIUM сохраняются как separate atomic units.

### Optional verification activities (D-02..D-03)

- **D-02: Numerical Instruments baseline — SKIPPED, deferred к Phase 11/12.** Не снимаем в Phase 6e. Rationale: user приоритизирует velocity для cleanup; PerfSignposter spans уже сохранены в production code (DEC-06d-06), значит pre-TestFlight snap (Phase 11/12) даст полноценный baseline для production release. Если в Phase 7-10 будет замечена performance regression — отдельный ad-hoc snap может быть сделан тогда (это не блокирует Phase 6e closure).
- **D-03: macOS UAT replay — SKIPPED, deferred к Phase 11/12.** Не выполняем в Phase 6e. Rationale: macOS path использует тот же source code что iOS; risk низкий. Phase 11/12 (pre-TestFlight polish) обязательно покрывает macOS UAT отдельной сессией. **Не должно блокировать Phase 6e closure.**

### Closure rigor (D-04..D-05)

- **D-04: Hybrid closure standard.** MEDIUM findings и LOW bundle получают РАЗНЫЕ режимы:
  - **Каждый MEDIUM fix → atomic commit + per-commit regression gate** (как Phase 6d sub-plans 03a-h). `swift test --package-path BBTB/Packages/AppFeatures` + iOS xcodebuild + macOS xcodebuild green на каждом MEDIUM commit. 6 MEDIUM = 6 atomic commits + 6 gate passes.
  - **20 LOW findings → bundle commits по theme** (e.g., naming consistency, dead-code removal, unused imports, comment cleanup). 1-3 bundle commits всего. **Single regression gate в конце LOW bundle** (не per-commit).
  - **3 trivial unused imports → один single commit** с regression gate (тривиально).
- **D-04a:** Между MEDIUM commits и LOW bundle — НЕ полагаемся на cumulative gate. Каждый MEDIUM gate'ится отдельно (поломка ловится точечно). LOW bundle gate'ится в конце (поломка ловится как chunk, но trade-off приемлем для cleanup-tier).
- **D-05: Closure SUMMARY + wiki sync — compact (не full Phase 6d-style).** Включает:
  - `06E-Final-SUMMARY.md` — closure record (commits list, what closed, what deferred, regression gate evidence). Структура аналогична `06D-Final-SUMMARY.md` но shorter (не 19 findings × full detail, а 26 findings × один-два line each).
  - `wiki/performance-baseline.md` update — § Open follow-ups переходит из "26 carved" → "26 closed in Phase 6e" + new "Open follow-ups (post-6e)" если что-то осталось.
  - `STATE.md` + `ROADMAP.md` + `REQUIREMENTS.md` sync — Phase 6e ✅ Closed; new QUAL-04..XX Validated (если added).
  - `wiki/log.md` — closure entry.
  - **НЕ требуется:** отдельный 06E-COMPARISON.md (нет numerical pre/post — было решено в D-02). Заменяется compact narrative в SUMMARY.
- **D-05a: D-09 invariants — final grep audit** перед closure commit (как Phase 6d). Если grep показывает regression — STOP, fix, retry.

### Multi-AI participation (D-06)

- **D-06: NO 3-AI peer review re-spawn для Phase 6e.** Findings уже triaged в Phase 6d через Opus + Codex + Gemini (см. 06D-FINDINGS.md). Phase 6e — execution-фаза, не audit. Multi-AI delegation допустим только для:
  - **Architect mode** (`mcp__codex__codex`, `sandbox: read-only`) — если researcher или executor встречает ambiguity в одном из 6 MEDIUM finding fixes (impact uncertain, fix-strategy не очевиден). 2+ failed attempts на same issue → escalate к architect.
  - **Code reviewer mode** (`mcp__codex__codex`, `sandbox: read-only`) — финальный sanity-check перед closure commit, если cleanup сложный. Optional.

### Phase 6e success contract (D-07..D-08)

- **D-07: PASS criteria для closure:**
  1. Все 26 carved findings либо closed (commit SHA), либо explicitly downgraded к "permanently accepted" (with rationale в SUMMARY).
  2. Каждый MEDIUM individually verified через regression gate.
  3. LOW bundle final regression gate green.
  4. AppFeatures swift test 133/133 (либо ≥ 133 если новые tests added).
  5. iOS + macOS xcodebuild SUCCEEDED.
  6. D-09 invariants final grep clean.
  7. Phase 6d DEC-06d-01..06 patterns preserved.
  8. `wiki/performance-baseline.md` § Open follow-ups updated.
  9. Closure SUMMARY + STATE/ROADMAP/REQUIREMENTS sync.
- **D-08: FAIL recovery:** если MEDIUM regression gate FAIL → revert + investigate root cause. Если patterns invariant violation detected → revert immediately, не try to "fix forward" (Phase 6c R18 lesson). Если 2+ failures на same MEDIUM finding → escalate к Architect через mcp__codex__codex (Delegator rule).

### Claude's Discretion

- **Wave structure** — planner может выбрать 2-3 waves:
  - **Wave 1**: MEDIUM findings (6 atomic commits per finding) — последовательно с regression gate между.
  - **Wave 2**: LOW bundle commits (1-3 commits по themes) + trivial imports (1 commit) + final regression gate.
  - **Wave 3 (closure)**: SUMMARY + STATE/ROADMAP/REQUIREMENTS sync + wiki update + final regression gate.
  Альтернативно: всё в 2 plan'ах (MEDIUM + LOW combined; closure).
- **LOW bundle theming** — planner organizes LOW по smart themes (naming, dead-code, unused-imports, comment-cleanup, etc.). Не блокировать на оптимальной группировке — pragmatic clustering ок.
- **Researcher scope** — `gsd-phase-researcher` reads `06D-FINDINGS.md` + cross-references post-6d code state. Не нужно re-run 3-AI audit. Output: RESEARCH.md с per-finding current-state assessment (still applicable / partially-addressed-already / invalidated).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 6d artifacts (входной scope для 6e)

- `.planning/phases/06d-performance-audit/06D-FINDINGS.md` — полный список из 45 findings с severity classification, file:line, recommended fix. **ЭТО первичный input для Phase 6e research.** 26 findings со status "carved" — это scope.
- `.planning/phases/06d-performance-audit/06D-COMPARISON.md` — каталог 19 closed findings (НЕ scope для 6e — для cross-reference только).
- `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md` — Phase 6d closure record + 6 architectural decisions DEC-06d-01..06 + carved findings backlog summary. **Pattern reference для 6e closure.**
- `.planning/phases/06d-performance-audit/06D-PERIPHERY-POST-FIX.md` — 3 trivial unused imports + dead-code scan output.
- `.planning/phases/06d-performance-audit/06D-CONTEXT.md` — Phase 6d discuss-phase decisions (D-01..D-22). Pattern reference для discuss-phase structure.

### Phase 6c invariants (must-preserve)

- `.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md` — D-09 invariants list + grep audit pattern (forbidden symbols ≤ 7, observer queue=.main = 0, #Predicate UUID? = 0, etc.). **Final grep audit перед Phase 6e closure обязателен.**
- `wiki/auto-reconnect.md` — Phase 6c R18 sliding-window invariant + `applyVPNStatus` single authority + reactive UI driver.
- `wiki/security-gaps.md` — R18 (Phase 6c) + R19 (Phase 6d) + ExternalVPNStopMarker semantics. **Must preserve `ExternalVPNStopMarker.isPending` peek-only semantics — НЕ возвращать к `consume()`.**

### Long-term wiki

- `wiki/performance-baseline.md` — long-term memory с 6 architectural decisions DEC-06d-01..06 + Open follow-ups section (the 26 carved findings list — Phase 6e closure обновляет эту section).
- `wiki/index.md` — wiki index (add 6e link если new wiki page создаётся).
- `wiki/log.md` — append-only changelog (closure entry для 6e).

### Project-level

- `.planning/PROJECT.md` — R19 Key Decisions row (Phase 6d) — DEC-06d-01..06 reference.
- `.planning/REQUIREMENTS.md` — PERF-01..05 + QUAL-01..03 (Phase 6d Validated). Phase 6e добавляет QUAL-04..XX (TBD в planning) либо ни одного нового req (если 6e — pure cleanup без new commitments).
- `.planning/STATE.md` — Phase 6e Active block + Progress table.
- `.planning/ROADMAP.md` — Phase 6e entry (Goal + Success Criteria + Plans list TBD).

### Auto-memory (current-session relevance)

- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_phase6d_architectural_patterns.md` — DEC-06d-01..06 bundle с "How to apply" guidance. Researcher + planner должны учитывать.
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/project_phase6d_complete.md` — Phase 6d closure summary.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **PerfSignposter spans** (`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift`) — DEC-06d-06 standard tooling. **Не удалять**. Может пригодиться researcher'у если MEDIUM finding касается hot path.
- **ExternalVPNStopMarker** (`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExternalVPNStopMarker.swift`) — DEC-06d-05 sticky marker pattern. **Не модифицировать без понимания race semantics.**
- **TestClocks + ReconnectClock** (preserved extracts из Phase 6c) — useful для тестов если новые tests добавляются для MEDIUM fixes.
- **Phase 6d FINDINGS structure** — researcher может использовать тот же synthesis format в RESEARCH.md.

### Established Patterns (must follow)

- **Atomic commit + regression gate** (Phase 6d sub-plans 03a-h pattern) — для каждого MEDIUM.
- **Bundle commit + single gate** (новый pattern для 6e LOW) — pragmatic для cleanup-tier.
- **`gsd-sdk query commit ... --files ...`** — explicit file staging, не `git add .` (per Phase 6d practice).
- **Awk-stripped grep audit** для invariants (Phase 6c B-08 pattern, used in Phase 6d INVARIANT-AUDIT).

### Integration Points

- **Findings researcher reads:** `06D-FINDINGS.md` lines 26-50 (carved section, marked with `[carved-out]` flag или similar — researcher проверит actual structure).
- **Closure SUMMARY writes to:** новая `06E-Final-SUMMARY.md` + updates существующих `wiki/performance-baseline.md` § Open follow-ups + `wiki/log.md` append.
- **STATE.md sync:** Phase 6e row → ✅ Closed; Phase 7 → Active.

</code_context>

<specifics>
## Specific Ideas

User explicit decisions:
- **«Всё подряд — все 26 findings»** — максимальная очистка baseline'а перед Phase 7. Не cherry-pick.
- **Skip Instruments baseline сейчас** — defer к Phase 11/12. Velocity priority.
- **Skip macOS UAT replay сейчас** — defer к Phase 11/12. Same source code как iOS, risk low.
- **Hybrid closure rigor** — full per-commit gate для MEDIUM (6×), single bundle gate для LOW (1×), trivial imports один commit.

Pattern preservation references (user emphasized в Phase 6d):
- DEC-06d-05 ExternalVPNStopMarker — НЕ переписывать без понимания race.
- R18 sliding window invariant — preserve.
- D-09 invariants — preserve через final grep audit.

</specifics>

<deferred>
## Deferred Ideas

- **Numerical Instruments baseline** — defer к Phase 11/12 (pre-TestFlight obligatory).
- **macOS UAT replay (5 scenarios A/F-direct/F-reverse/Settings-disable/G)** — defer к Phase 11/12.
- **3-AI re-audit для post-Phase-6e** — если в Phase 7-10 будет замечена performance regression, рассмотреть на отдельной Phase 6f «Performance Audit Round 3». Не block Phase 7.
- **NET-12 (active liveness probe)** — Phase 7-8 carve-out (Phase 6c R18). НЕ в scope 6e.
- **Phase 7 ready signal** — после 6e closure → `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).

</deferred>

---

*Phase: 6e — Performance Audit Round 2 + macOS UAT replay (slug ROADMAP-derived; macOS UAT actually deferred per D-03)*
*Context gathered: 2026-05-14*
