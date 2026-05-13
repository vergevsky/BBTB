---
phase: 06d-performance-audit
plan: Final-b
slice: b
type: execute
wave: Final.2
mode: mvp
depends_on: [Final-a]
files_modified:
  - .planning/phases/06d-performance-audit/06D-UAT.md
  - wiki/performance-baseline.md
  - wiki/index.md
  - wiki/log.md
  - wiki/architecture.md
  - wiki/tech-stack.md
  - .planning/STATE.md
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md
  - .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md
autonomous: true
requirements: [QUAL-01, QUAL-02, QUAL-03]
tags: [uat, wiki-long-term-memory, phase-close, regression-gate-final, state-roadmap-sync]

must_haves:
  truths:
    - "06D-UAT.md — regression smoke на iPhone iOS 26.5 проведён для всех 9 Phase 6c scenarios + Settings-disable (carry-over); все hard-blockers PASS."
    - "wiki/performance-baseline.md final: pre/post comparison + decisions + open follow-ups; wiki/index.md + wiki/log.md синхронизированы."
    - "Архитектурные решения, всплывшие в ходе аудита (если есть) — переехали в wiki соответствующие страницы (C-06: wiki long-term memory)."
    - "STATE.md + ROADMAP.md + REQUIREMENTS.md обновлены — Phase 6d ✅ Closed; новые PERF-* / QUAL-* requirements marked Validated."
    - "Full regression gate (D-08) green в финальной проверке: AppFeatures 133/133 + iOS xcodebuild + macOS xcodebuild."
    - "D-09 invariants preserved до конца phase (final grep audit clean)."
    - "06D-Final-SUMMARY.md имеет full commit history + verification metrics + decisions + reference index."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/06D-UAT.md"
      provides: "Regression smoke результаты — все 9 Phase 6c scenarios + Settings-disable на iPhone iOS 26.5"
      contains: "Phase 6d UAT"
    - path: "wiki/performance-baseline.md"
      provides: "Long-term wiki page (final state) — pre/post + decisions + Phase 7+ pointers"
      contains: "Post-fix comparison"
    - path: ".planning/phases/06d-performance-audit/06D-Final-SUMMARY.md"
      provides: "Phase 6d closure summary — full commit list + verification metrics + reference index"
      contains: "Phase 6d — Final SUMMARY"
  key_links:
    - from: "Phase 6c UAT scenarios (A..I + Settings-disable)"
      to: "06D-UAT.md regression smoke result"
      via: "1 smoke pass на iPhone iOS 26.5"
      pattern: "PASS|FAIL"
    - from: "06D-FINDINGS.md (closed findings)"
      to: "wiki/performance-baseline.md decision narrative"
      via: "Decisions section listing F-XX closures + commit SHA"
      pattern: "closes F-[0-9]+"
    - from: "Phase 6d Final-b"
      to: "Phase 7 ready signal"
      via: "STATE.md + ROADMAP.md Phase 6d → Closed"
      pattern: "Phase 6d.*Closed"
---

# Phase 6d Wave Final-b — UAT smoke + wiki long-term memory + Phase closure

## Цель волны (по-русски)

Wave Final-b — закрывающая sub-wave Phase 6d. Три направления:

1. **UAT regression smoke** (Task 1) — все 9 Phase 6c scenarios (A..I) + Settings-disable на iPhone iOS 26.5. Один прогон. Покрывает D-09 invariant verification + Phase 6d-specific checks (signposts intact + comparison delta visible).
2. **wiki long-term memory** (Task 2) — `wiki/performance-baseline.md` final state (pre/post + decisions + Phase 7+ pointers), wiki/index.md + log.md sync. Любое архитектурное решение, всплывшее в аудите — переезжает в соответствующую wiki page (C-06).
3. **Phase closure** (Task 3) — `06D-Final-SUMMARY.md` + STATE.md + ROADMAP.md + REQUIREMENTS.md обновлены; Phase 6d ✅ Closed; PERF-* / QUAL-* requirements Validated; user может запускать `/gsd-discuss-phase 7`. Final regression gate.

---

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06d-performance-audit/06D-CONTEXT.md
@.planning/phases/06d-performance-audit/06D-RESEARCH.md
@.planning/phases/06d-performance-audit/06D-PATTERNS.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@.planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-COMPARISON.md
@.planning/phases/06d-performance-audit/06D-01-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-03-PLAN.md
@.planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md
@.planning/phases/06c-on-demand-migration/06C-UAT.md
@.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md
@.planning/phases/06c-on-demand-migration/06C-05-SUMMARY.md
@wiki/performance-baseline.md
@wiki/auto-reconnect.md
@wiki/index.md
@wiki/log.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1 — 06D-UAT.md regression smoke (9 Phase 6c scenarios + Settings-disable) на iPhone iOS 26.5</name>
  <files>
    .planning/phases/06d-performance-audit/06D-UAT.md
  </files>
  <read_first>
    - .planning/phases/06c-on-demand-migration/06C-UAT.md (template + 9 scenarios + Settings-disable; shape reference)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role L — UAT smoke shape)
    - .planning/phases/06d-performance-audit/06D-CONTEXT.md (D-09 invariants — UAT validates что они сохранились)
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (closed findings — какие могли затронуть UAT-relevant code paths)
    - .planning/phases/06d-performance-audit/06D-COMPARISON.md (numerical baseline для cross-reference в notes column)
  </read_first>
  <action>
    Provide regression smoke UAT — все 9 Phase 6c scenarios + Settings-disable carry-over. **Один прогон** на iPhone iOS 26.5; per-fix-wave UAT не требуется (это сделано regression gate между waves в Wave 06D-03).

    **Структура `06D-UAT.md`** (по Role L pattern из PATTERNS, copy from 06C-UAT.md shape):

    ```markdown
    # Phase 6d UAT — Regression smoke

    **Date**: 2026-05-NN
    **Device**: iPhone XX iOS 26.5 + MacBook macOS X.Y
    **App version**: 0.6.2 (commit <final SHA>)
    **UAT scope** (D-08 from CONTEXT.md): regression smoke — все 9 Phase 6c scenarios (A..I) + Settings-disable. Один прогон. Не re-UAT per fix-wave (regression gate между waves в Wave 06D-03 покрывает unit + build levels).

    ## Result table

    | # | Scenario | Plat | Severity | Result | Notes |
    |---|---|---|---|---|---|
    | A | Wi-Fi ↔ LTE reconnect | iOS | HARD BLOCKER | ✅ / ❌ | Ожидалось PASS (Phase 6c carry-over; D-09 invariant preserved). Cross-ref: cold-launch и connect-tap время см. 06D-COMPARISON section 1 + 2. |
    | B | iPhone overnight (8h+) | iOS | Non-blocking | ✅ / ⏭️ | Может skip если budget tight; PASS если выполнено. |
    | C | macOS sleep 10min → wake | macOS | HARD BLOCKER | ✅ / ❌ | Phase 6c carry-over. Включает D-11/12/13 macOS NSWorkspace.didWakeNotification. |
    | D | Smena Wi-Fi network (SSID change) | iOS | Non-blocking | ✅ / ⏭️ | … |
    | E | Pitfall 5: stable session 1min, server-side sing-box kill | iOS | HARD BLOCKER (CRITICAL) | ✅ / ❌ / ⏭️ Deferred | Если test infrastructure готов (см. Phase 6c carry-over). Иначе deferred к Phase 7-8 (NET-12 liveness probe). |
    | F-direct | BBTB → ProtonVPN takeover → return → 1-tap Connect | iOS | HARD BLOCKER | ✅ / ❌ | Phase 6c PASS; D-09 invariant intent-closing path UNCHANGED — должно остаться PASS. |
    | F-reverse | BBTB active → Happ activation → BBTB stays off | iOS | HARD BLOCKER (CRITICAL) | ✅ / ❌ | Phase 6c PASS; D-09 critical preserved. |
    | G | App in background 30+ min, EXC_RESOURCE / PORT_SPACE check via Console.app | iOS 26.5 | HARD BLOCKER (CRITICAL — bug class 4) | ✅ / ❌ | Passive during F scenarios. Zero crashes expected. |
    | H | Toggle «Авто-переподключение» OFF while connected | iOS | Non-blocking | ✅ / ⏭️ | … |
    | I | Migration smoke — Phase 6 → 6d upgrade install | iOS | HARD BLOCKER | ✅ / ❌ | manager.isOnDemandEnabled = true confirmed in Settings → VPN. |
    | Settings-disable | BBTB active → iOS Settings → VPN → BBTB toggle off → BBTB stays off until explicit Connect | iOS | HARD BLOCKER | ✅ / ❌ | Phase 6c Round 6 fix `44a5630` — должно остаться PASS. |

    **Hard-blocker set (per 06C Round 2 B-10)**: A, C, E, F-reverse, F-direct, G, I, Settings-disable.

    ## Phase 6c invariant verification (D-09)

    Manual checks помимо UAT scenarios:

    | Invariant | Verification | Result |
    |---|---|---|
    | TunnelController.handleStatusChange UNCHANGED | `git log -- BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` since 6c close — diff в handleStatusChange? | … |
    | No XPC в NEVPNStatusDidChange observer | F-reverse + Settings-disable + G all PASS | … |
    | No reintroduction RSM / NetworkReachability | `grep -rn "ReconnectStateMachine\|NetworkReachability\|...\" Sources/ \| awk '!/^[[:space:]]*\\/\\//' \| wc -l` ≤ 7 | … |
    | applyVPNStatus single authority | grep `self.state = ` в MainScreenViewModel — только в applyVPNStatus + init | … |
    | Sliding window invariant | F-reverse + Settings-disable PASS | … |
    | Observer queue = nil (memory) | `grep -rn "NEVPNStatusDidChange.*queue:.*\\.main\\)"` = 0 | … |
    | No #Predicate UUID? | `grep -rn "#Predicate.*UUID?"` = 0 | … |

    ## Phase 6d-specific checks (post-fix architectural)

    | Check | Verification | Result |
    |---|---|---|
    | OSSignposter spans intact | `grep -rn "OSSignposter\|beginInterval\|endInterval" BBTB --include="*.swift" \| wc -l` ≥ Wave 06D-02a baseline | … |
    | PerfSignposter.swift present | `test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift` | … |
    | Cold launch improvement visible | Section 1 в 06D-COMPARISON.md показывает delta | … |
    | Connect tap improvement visible | Section 2 в 06D-COMPARISON.md показывает delta | … |
    | Energy stable / improved | Section 3 в 06D-COMPARISON.md — никаких HIGH regression (tier shift up или CPU% +>25%) | … |
    | Allocations stable / improved | Section 4 в 06D-COMPARISON.md — никаких HIGH regression (>10MB drift) | … |
    | Dead-code decreased | periphery-scan-post-fix.txt warnings < pre-fix | … |

    ## Final regression gate (D-08)

    | Check | Required | Actual | Status |
    |---|---|---|---|
    | swift test --package-path BBTB/Packages/AppFeatures | 133/133 PASS | … | ✅ |
    | xcodebuild iOS Simulator | BUILD SUCCEEDED | … | ✅ |
    | xcodebuild BBTB-macOS | BUILD SUCCEEDED | … | ✅ |

    ## Decisions / closure criteria

    UAT passes when:
    - **All hard-blocker scenarios PASS** (A, C, F-direct, F-reverse, G, I, Settings-disable; E deferred OK если NET-12 не готов).
    - **D-09 invariant verification — all check rows PASS**.
    - **Phase 6d-specific checks — all PASS**.
    - **Final regression gate green**.

    If ANY hard FAIL → STOP, document в `06D-UAT.md`, escalate user (fix-on-top или revert before close).
    ```

    Прогнать manually на iPhone (user или developer driving the test). Заполнить Result column реальными observed outcomes. Если какой-то scenario FAIL — задокументировать notes + escalate user перед continuing Task 2-3.

    **Atomic commit:** `docs(06d-final-b): UAT regression smoke + invariant verification on iPhone iOS 26.5`.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -q "Phase 6d UAT" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -q "Result table" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -qE "F-reverse|Settings-disable" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -q "Phase 6c invariant verification" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -q "Phase 6d-specific checks" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -q "Final regression gate" .planning/phases/06d-performance-audit/06D-UAT.md \
        && grep -cE "✅|❌|⏭️|PASS|FAIL" .planning/phases/06d-performance-audit/06D-UAT.md | awk '$1 >= 8 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <done>
    06D-UAT.md содержит result table со всеми 11 scenarios (9 Phase 6c + E deferred row + Settings-disable), D-09 invariant verification таблицу, Phase 6d-specific checks (signposts intact + comparison delta visible), final regression gate. ≥8 PASS/FAIL/⏭ маркеров заполнены реальными outcomes. Если есть FAIL — задокументировано + escalated.
  </done>
</task>

<task type="auto">
  <name>Task 2 — Wiki long-term memory sync (wiki/performance-baseline.md final + wiki/index.md + wiki/log.md + architectural decisions touch)</name>
  <files>
    wiki/performance-baseline.md
    wiki/index.md
    wiki/log.md
    wiki/architecture.md
    wiki/tech-stack.md
  </files>
  <read_first>
    - wiki/performance-baseline.md (initial pre-fix draft из Wave 06D-02c Task 2)
    - wiki/index.md (current state)
    - wiki/log.md (последние entries)
    - wiki/auto-reconnect.md (Phase 6c long-term memory — pattern shape для Phase 6d entries)
    - wiki/architecture.md (если есть architectural decisions из 06D-COMPARISON секции 8)
    - wiki/tech-stack.md (если есть tooling decisions, например Periphery as standard tool)
    - .planning/phases/06d-performance-audit/06D-COMPARISON.md (Decisions / open follow-ups секция 8)
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (closed findings — для cross-ref в wiki narrative)
    - CLAUDE.md C-06 (wiki = long-term decision log)
  </read_first>
  <action>
    Sync wiki — long-term memory обновляется finally после Phase 6d closure.

    **Шаги:**

    1. **Update `wiki/performance-baseline.md` finalize** — Wave 06D-02c создал initial pre-fix draft; финализируем post-fix данными + decisions:

       Структура (final state):
       ```markdown
       ---
       name: Performance baseline (Phase 6d)
       description: ...
       type: measurement
       ---

       # Performance baseline (Phase 6d)

       **Summary**: Phase 6d (Performance & Code Quality Audit) closed 2026-05-NN. Triple-AI peer review (Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) + Instruments measurements + NN findings closed → измеримые improvements: cold launch -XXms, connect tap -YYms, NN dead-code items удалены.

       **Sources**:
       - .planning/phases/06d-performance-audit/06D-FINDINGS.md (full findings list)
       - .planning/phases/06d-performance-audit/06D-COMPARISON.md (pre-vs-post detail)
       - .planning/phases/06d-performance-audit/baselines/*.md (numerical экспорты)
       - .planning/phases/06d-performance-audit/periphery-scan-{pre,post}-fix.txt
       - .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md (closure record)

       **Last updated**: 2026-05-NN (Phase 6d closure).

       ---

       ## Зачем эта страница (long-term context)

       (Объяснение non-programmer audience: Phase 5 user reported «приложение тяжело грузится». Phase 6d закрыл это через measurement + targeted fixes. Эта страница — long-term память что было до, что стало после, какие architectural patterns установлены — чтобы будущие phases (7-12) использовали те же measurements + не повторяли исследование заново.)

       ## Pre-fix baseline (Wave 06D-02c)

       [Полная таблица из Wave 06D-02c — pre-fix данные.]

       ## Post-fix comparison (Wave 06D-Final-a)

       [Заполнено из 06D-COMPARISON.md секции 1-5 — pre vs post side-by-side для каждого dimension.]

       ## Architectural decisions established (Phase 6d-specific)

       [Из 06D-COMPARISON.md секции 8 — long-term valid decisions. Например:
       - **DEC-06d-01**: Cold-start non-critical inits → Task в onAppear, не App.init body.
         Rationale: SwiftDataContainer.makeShared() в init блокировал main thread на ~XXms.
         Reference: F-001 in 06D-FINDINGS.md; commit <SHA>.
         Future phases должны применять этот pattern для новых init-heavy operations.
       - **DEC-06d-02**: Periphery scan как стандартный pre-release gate.
         Установлен Periphery 3.7.4; CI/local scan для каждого release v0.6.2+.
       - ...]

       ## Open follow-ups (carved или discovered)

       [Из 06D-COMPARISON.md + 06D-FINDINGS.md — что carved + что обнаружено но не закрыто:
       - **F-NNN**: <title>, severity MEDIUM/LOW, deferred to Phase 7 backlog. Rationale: ...
       - **macOS-specific UAT replay** (отложено из Phase 6c) — теперь, когда Phase 6d closed, можно replay на MacBook отдельно. Phase 11/12 territory.
       - ...]

       ## Methodology (для будущих phase performance audits)

       Если в Phase 7-12 нужно будет повторить performance audit — следовать pattern Phase 6d:
       1. Multi-AI peer review (3 passes, identical 7-section brief, parallel).
       2. Instruments baseline (App Launch + Time Profiler + Energy Log + Allocations) на real device.
       3. CHECKPOINT для budget decision.
       4. Atomic-commit fix cycle с regression gate между.
       5. Post-fix re-measure + comparison + wiki update.

       Pattern документирован в `.planning/phases/06d-performance-audit/06D-RESEARCH.md` (полная research output, valid until 2026-05-28; revisit if reused later).

       ## Related pages

       - [[auto-reconnect]] — Phase 6c long-term memory (architectural baseline для invariants).
       - [[architecture]] — SwiftPM-структура (обновлена DEC-06d-01 если применимо).
       - [[tech-stack]] — Standard tooling (обновлён Periphery если DEC-06d-02 применимо).
       - [[dns-pipeline-decisions]] — Phase 6 baseline (DNS-strategy long-term).
       ```

    2. **Update `wiki/index.md`** — проверить что link на `[[performance-baseline]]` существует (создавался в Wave 06D-02c); обновить description если final state расширил scope:
       ```
       - [[performance-baseline]] — Pre/post-fix Instruments measurements + architectural decisions (Phase 6d, closed 2026-05).
       ```

    3. **Append `wiki/log.md`** — closure entry:
       ```
       ## 2026-05-NN — Phase 6d ✅ Closed (Performance & Code Quality Audit)

       Triple-AI peer review (Opus 4.7 + Codex GPT-5.2 + Gemini 3.1 Pro) → consolidated 06D-FINDINGS.md (NN findings, NN HIGH / NN MEDIUM / NN LOW post-filter). CHECKPOINT 1 → пользователь выбрал option-X. Wave 06D-03 (или 03a/03b/…) закрыл NN findings атомарными commits с regression gate между каждой fix-task. Wave 06D-Final-a снял post-fix Instruments traces, comparison показал cold launch -XXms / connect tap -YYms / Energy stable / Allocations stable / dead-code -NN items. UAT regression smoke на iPhone iOS 26.5 — все hard-blocker scenarios PASS (Phase 6c invariants preserved).

       **Architectural decisions переехавшие в wiki**:
       - [[performance-baseline]] new — full pre/post detail + decisions list.
       - [[architecture]] — DEC-06d-01 (cold-start init pattern) если применимо.
       - [[tech-stack]] — DEC-06d-02 (Periphery as standard) если применимо.

       **GSD updates**:
       - STATE.md Phase 6d → ✅ Closed.
       - ROADMAP.md Phase 6d → ✅ Complete; Phase 7 теперь next-active.
       - REQUIREMENTS.md новые PERF-* / QUAL-* → Validated.

       **Что дальше:** `/gsd-discuss-phase 7` — Anti-DPI suite + WireGuard family.
       ```

    4. **Touch `wiki/architecture.md`** (если есть architectural decision из COMPARISON section 8):
       - Добавить short entry в существующую секцию decisions, либо новую секцию `## Phase 6d additions (2026-05)` со ссылкой на `[[performance-baseline]]` для full detail.
       - **Не дублировать** содержимое — линковать.

    5. **Touch `wiki/tech-stack.md`** (если есть tooling decision):
       - Добавить Periphery 3.7.4 в standard tooling list если DEC-06d-02 применимо.
       - OSSignposter — упомянуть как standard performance instrumentation patten.

    **Не дублировать decisions content между wiki и .planning** (CLAUDE.md C-06 rule):
    - В `.planning/phases/06d-performance-audit/` — operational план фазы.
    - В `wiki/` — long-term decision log.
    - Связывать линками, не копировать.

    **Atomic commit:** `docs(06d-final-b): wiki long-term memory sync — performance-baseline final + architecture + tech-stack touch`.
  </action>
  <verify>
    <automated>
      grep -q "Post-fix comparison" wiki/performance-baseline.md \
        && grep -qE "Architectural decisions established|DEC-06d-01|DEC-06d-02" wiki/performance-baseline.md \
        && grep -q "Phase 6d.*Closed\|Phase 6d.*✅" wiki/log.md \
        && grep -q "performance-baseline" wiki/index.md
    </automated>
  </verify>
  <done>
    wiki/performance-baseline.md финализирован с pre/post comparison + architectural decisions + methodology секцией; wiki/index.md актуализирован; wiki/log.md содержит closure entry; wiki/architecture.md и/или wiki/tech-stack.md обновлены если есть applicable decisions (либо пустой commit с обоснованием "no wiki touch needed beyond performance-baseline" если decisions narrow scope).
  </done>
</task>

<task type="auto">
  <name>Task 3 — 06D-Final-SUMMARY.md + STATE.md / ROADMAP.md / REQUIREMENTS.md sync + final regression gate (Phase 6d closure)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md
    .planning/STATE.md
    .planning/ROADMAP.md
    .planning/REQUIREMENTS.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-01-SUMMARY.md
    - .planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
    - .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
    - .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
    - .planning/phases/06d-performance-audit/06D-03-PLAN.md (либо 06D-03*-SUMMARY.md materialized после CHECKPOINT 1)
    - .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md
    - .planning/phases/06d-performance-audit/06D-COMPARISON.md
    - .planning/phases/06d-performance-audit/06D-UAT.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
    - .planning/REQUIREMENTS.md
    - .planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md (Role M shape reference)
    - .planning/phases/06c-on-demand-migration/06C-05-SUMMARY.md (closure pattern reference)
  </read_first>
  <action>
    Финальная закрывающая task. Создаёт closure summary + обновляет project-level docs.

    **1. `06D-Final-SUMMARY.md` структура** (Role M shape, copy from 06C-04-SUMMARY.md):

    ```markdown
    ---
    phase: 06d-performance-audit
    plan: Final
    type: summary
    status: closed
    date: 2026-05-NN
    commits:
      - "<SHA> — chore(06d-02a): install Periphery 3.7.4 + jq + ripgrep verification"
      - "<SHA> — feat(06d-02a): add PerfSignposter + inject ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart spans"
      - "<SHA> — docs(06d-02a): scaffold Instruments baseline templates + .gitignore *.trace + ASSUMED-claim verification log"
      - "<SHA> — docs(06d-02b): synthesis of 3 AI passes — consolidated FINDINGS"
      - "<SHA> — docs(06d-02c): pre-fix Instruments baseline + Periphery scan"
      - "<SHA> — docs(06d-02c): wiki performance-baseline initial draft + index + log sync"
      - "<SHA> — docs(06d-02c): findings summary + budget options for CHECKPOINT 1"
      - <... Wave 06D-03 commits per finding ...>
      - "<SHA> — docs(06d-final-a): post-fix Instruments traces + Periphery re-scan"
      - "<SHA> — docs(06d-final-a): pre-vs-post comparison analysis"
      - "<SHA> — docs(06d-final-b): UAT regression smoke + invariant verification"
      - "<SHA> — docs(06d-final-b): wiki long-term memory sync"
      - "<SHA> — docs(06d-final-b): phase closure SUMMARY + STATE/ROADMAP/REQUIREMENTS sync"
    ---

    # Plan 06D-Final — Phase 6d Closure SUMMARY

    ## Status

    **Phase 6d ✅ Closed 2026-05-NN.** Performance & Code Quality Audit complete; v0.6.2 patch shipped.

    ## What Phase 6d delivered

    ### Triple-AI peer review
    - Opus 4.7 (internal thread, NN findings).
    - Codex GPT-5.2 (mcp__codex__codex sandbox=read-only, NN findings).
    - Gemini 3.1 Pro (mcp__gemini__gemini sandbox=read-only + fallback chain, NN findings / skipped).
    - Synthesis: 06D-FINDINGS.md (consolidated, NN total post-filter; NN rejected by D-09; NN filtered out-of-scope).

    ### CHECKPOINT 1 decision
    User selected: option-X (HIGH only / + MEDIUM / + LOW themes / custom).
    Budget materialized: NN findings closed; NN carved.

    ### Fix cycle (Wave 06D-03 + sub-plans if any)
    - NN atomic commits (HIGH × N + MEDIUM × N + LOW theme bundles × N).
    - Regression gate green между каждой commit (AppFeatures 133/133 + iOS xcodebuild + macOS xcodebuild × NN passes).
    - D-09 invariants preserved throughout (forbidden symbol grep stayed ≤ 7; observer queue=.main stayed 0; #Predicate UUID? stayed 0).

    ### Instruments measurements (pre vs post)
    | Span | Pre-fix median | Post-fix median | Delta |
    |---|---|---|---|
    | Cold launch (iPhone) | XXms | YYms | -ZZms (-WW%) |
    | Cold launch (MacBook) | XXms | YYms | -ZZms |
    | ConnectTap | XXms | YYms | -ZZms |
    | PreConnectProbe | XXms | YYms | -ZZms |
    | ProvisionProfile | XXms | YYms | -ZZms |
    | Energy Active 5min | Impact tier | Impact tier | stable / improved |
    | Allocations host (60s connected) | NN MB | NN MB | … |
    | Allocations extension | NN MB | NN MB | … |
    | Periphery warnings | NN | NN | -NN items |

    Full detail — `06D-COMPARISON.md`.

    ### Wiki long-term memory updates
    - `wiki/performance-baseline.md` — new page (pre + post + decisions + methodology + Phase 7+ pointers).
    - `wiki/index.md` — link added.
    - `wiki/log.md` — closure entry.
    - `wiki/architecture.md` — DEC-06d-01 added if applicable.
    - `wiki/tech-stack.md` — DEC-06d-02 added if applicable.

    ## Verification metrics (final)

    | Check | Required | Actual | Status |
    |---|---|---|---|
    | swift test --package-path BBTB/Packages/AppFeatures | 133/133 PASS | NN/NN PASS | ✅ |
    | xcodebuild -scheme BBTB iOS Simulator | BUILD SUCCEEDED | … | ✅ |
    | xcodebuild -scheme BBTB-macOS | BUILD SUCCEEDED | … | ✅ |
    | Forbidden symbols grep (≤ 7 carve-out) | ≤ 7 | NN | ✅ |
    | NEVPN observer queue=.main grep | 0 | 0 | ✅ |
    | XPC in observer hot path grep | ≤ baseline | … | ✅ |
    | #Predicate UUID? grep | 0 | 0 | ✅ |
    | OSSignposter usages | ≥ Wave 06D-02a baseline | NN | ✅ |
    | Phase 6c UAT scenarios A..I + Settings-disable | All hard-blockers PASS | … | ✅ |
    | .trace bin в git | 0 | 0 | ✅ |
    | wiki/performance-baseline.md final state | yes | yes | ✅ |

    ## Architecture confirmations

    - All 5 Phase 6c invariants (D-09) preserved after NN fix-commits.
    - OSSignposter инструментация (Wave 06D-02a Commit 2) сохранена в production code — будущие perf audits могут переиспользовать без re-injection.
    - Periphery 3.7.4 now standard tooling (DEC-06d-02 if shipped).

    ## Closed findings (full list)

    [Table: F-001..F-NNN с commit SHA, severity, dimension, before/after metric if applicable.]

    ## Carved findings (deferred)

    [Table: F-NNN deferred to Phase X, rationale.]

    ## Reference index

    - **CHECKPOINT 1 decision**: option-X, recorded in `06D-03-CHECKPOINT-DECISION.md`.
    - **Multi-AI brief skeleton**: `06D-01-PREFLIGHT.md` (frozen verbatim text), source `06D-RESEARCH.md` строки 528-623.
    - **Phase 6c invariants**: `06D-CONTEXT.md` D-09 + `wiki/auto-reconnect.md`.
    - **Architectural Responsibility Map**: `06D-RESEARCH.md` (planner используется для будущих phase 7+).

    ## Status

    **Phase 6d ✅ Closed 2026-05-NN.** Next: `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).
    ```

    **2. Update `.planning/STATE.md`:**
    - `current_focus`: → "Phase 6d ✅ Closed 2026-05-NN — next: Phase 7 (Anti-DPI suite + WireGuard family)".
    - `## Active Phase` block: phase=7, status="Not started", goal=ROADMAP.
    - `### Previous phase (Phase 6d — Performance & Code Quality Audit ✅ Closed 2026-05-NN)`: добавить block с краткой Pa-сводкой (cold launch -XXms, connect tap -YYms, NN findings closed, NN carved, wiki touch); сослаться на `06D-Final-SUMMARY.md`.
    - `## Progress` table: Phase 6d row → "✓ Closed 2026-05-NN".
    - `### Recent decisions (Phase 6d)`: new section с 2-3 ключевыми decisions (например, DEC-06d-01 cold-start init pattern, DEC-06d-02 Periphery as standard).
    - `## Next Action`: → `/gsd-discuss-phase 7`.

    **3. Update `.planning/ROADMAP.md`:**
    - Phase 6d entry → status `✓ Complete 2026-05-NN`.
    - В `Goal` дополнить кратким outcome (-XXms cold launch, -YYms connect tap).
    - В `Success Criteria` — отметить каждый SC как ✓ либо ✗ с reference (например, "1. ✓ — multi-AI audit complete (06D-FINDINGS.md, NN findings); 2. ✓ — severity classified в FINDINGS; ...").
    - `Plans` list — заполнить актуальными filenames (06D-01 / 06D-02a / 06D-02b / 06D-02c / 06D-03 [+ 03a/03b/… если materialized как sub-plans] / 06D-Final-a / 06D-Final-b) со статусом `[x]`.

    **4. Update `.planning/REQUIREMENTS.md`:**
    - Добавить PERF-01..PERF-04 + QUAL-01..QUAL-03 (если ещё не добавлены) → `[x] Validated` со ссылкой на 06D-Final-SUMMARY.md.
    - Если в FINDINGS были найдены regression hits в существующих requirements — отметить + ссылка.

    **5. Final regression gate** (D-08 — последний прогон перед closure commit):
    ```bash
    swift test --package-path BBTB/Packages/AppFeatures
    xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build
    xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build
    ```
    Все три должны быть green. Если нет — **STOP**, escalate user (Phase 6d не closing с broken main).

    **6. Atomic commit (один — phase closure):**
    `docs(06d-final-b): phase closure SUMMARY + STATE/ROADMAP/REQUIREMENTS sync — Phase 6d ✅ Closed`.

    После commit user может запускать `/gsd-discuss-phase 7`. Phase 6d официально закрыт.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md \
        && grep -q "Phase 6d — Closure SUMMARY\|Phase 6d Closure\|Phase 6d ✅ Closed" .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md \
        && grep -q "Triple-AI peer review\|CHECKPOINT 1\|Fix cycle" .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md \
        && grep -qE "Verification metrics|Final.*regression" .planning/phases/06d-performance-audit/06D-Final-SUMMARY.md \
        && grep -q "Phase 6d.*Closed\|Phase 6d.*✓ Complete" .planning/ROADMAP.md \
        && grep -qE "Phase 6d.*✅|Phase 6d ✅ Closed|Phase 6d.*Complete" .planning/STATE.md \
        && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "passed|0 failures" \
        && xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -q "BUILD SUCCEEDED" \
        && xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build 2>&1 | grep -q "BUILD SUCCEEDED"
    </automated>
  </verify>
  <done>
    06D-Final-SUMMARY.md содержит полную closure запись (commits list, what delivered, verification metrics, architecture confirmations, closed/carved findings, reference index). STATE.md, ROADMAP.md, REQUIREMENTS.md обновлены — Phase 6d ✅ Closed; PERF-* / QUAL-* requirements Validated; Phase 7 теперь next. Final regression gate green (3/3 checks). Phase 6d официально закрыт.
  </done>
</task>

</tasks>

<verification>

**Wave-level acceptance (после всех 3 tasks):**

1. **UAT smoke** (Task 1):
   - 06D-UAT.md содержит result table (11 scenarios), Phase 6c invariant verification table, Phase 6d-specific checks table, final regression gate row.
   - Все hard-blocker scenarios PASS.

2. **Wiki long-term memory** (Task 2):
   - wiki/performance-baseline.md final state (pre + post + decisions + methodology + related pages).
   - wiki/index.md содержит link.
   - wiki/log.md содержит closure entry.
   - wiki/architecture.md + wiki/tech-stack.md обновлены если applicable.

3. **Closure** (Task 3):
   - 06D-Final-SUMMARY.md полный.
   - STATE.md + ROADMAP.md + REQUIREMENTS.md sync (Phase 6d → Closed; new requirements → Validated).
   - Final regression gate green (AppFeatures 133/133 + iOS xcodebuild + macOS xcodebuild).

4. **D-09 invariants preserved до конца phase** (final grep audit clean):
   - Forbidden symbols ≤ 7 (Phase 6c carve-out).
   - Observer queue=.main = 0.
   - #Predicate UUID? = 0.
   - OSSignposter usages ≥ baseline.

</verification>

<success_criteria>

- [ ] Все 3 tasks Wave Final-b closed.
- [ ] 06D-UAT.md regression smoke — все hard-blocker scenarios PASS.
- [ ] wiki long-term memory sync (performance-baseline final + index + log + architecture/tech-stack touch).
- [ ] 06D-Final-SUMMARY.md содержит полную closure запись.
- [ ] STATE.md + ROADMAP.md + REQUIREMENTS.md — Phase 6d ✅ Closed.
- [ ] Final regression gate green (3/3).
- [ ] D-09 invariants preserved (grep audit clean).
- [ ] User может запускать `/gsd-discuss-phase 7`.

</success_criteria>

<output>
После всех 3 task: создан `06D-Final-SUMMARY.md`, project docs sync. Phase 6d официально закрыт. Next user action: `/gsd-discuss-phase 7` для Anti-DPI suite + WireGuard family (Phase 7, v0.7).
</output>
</content>
</invoke>