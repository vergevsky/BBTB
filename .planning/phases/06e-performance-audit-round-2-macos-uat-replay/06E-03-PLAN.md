---
phase: 06e
slug: performance-audit-round-2-macos-uat-replay
plan: 03
type: execute
wave: 3
mode: mvp
depends_on: [01, 02]
autonomous: true
requirements: [QUAL-04, QUAL-05]
findings_addressed: [closure]
tags: [closure, summary, wiki-sync, state-sync, requirements-sync, d09-final-audit]
files_modified:
  - .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md
  - wiki/performance-baseline.md
  - wiki/log.md
  - .planning/STATE.md
  - .planning/ROADMAP.md
  - .planning/REQUIREMENTS.md

must_haves:
  truths:
    - "06E-Final-SUMMARY.md создан — closure record содержащий: 4 atomic MEDIUM commits (Wave 1) + 4-5 bundle commits (Wave 2) + L16 status (committed OR deferred) + 5 bookkeeping rows (M6, M15, L6, L17, L19 subsumed-by-6d) + final regression gate evidence + D-09 8-check grep audit results + DEC-06d-01..06 preservation confirmation."
    - "26 original 6d finding IDs полностью accounted (по 06D-FINDINGS.md catalog). Math по сценариям: SCENARIO A (L16 landed): 21 code-fixed IDs (Wave 1: M7+M10+M8+M11+L12 = 5; Wave 2: L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L16, L18, L20 = 16) + 5 bookkeeping IDs (M6, M15, L6, L17, L19 subsumed-by-6d) = 26 ✓; QUAL-04 = Validated unconditionally. SCENARIO B (L16 deferred): 20 code-fixed IDs + 5 bookkeeping + 1 deferred (L16) = 26 ✓; QUAL-04 = Validated с явным exception note 'L16 deferred к Phase 6f либо integrated в Phase 7+ refactor'. Trivial imports (3) считаются ОТДЕЛЬНО — они не L# finding IDs, а Periphery-derived additions из 06D-PERIPHERY-POST-FIX.md, attributed к QUAL-05 (Periphery actionable = 0)."
    - "wiki/performance-baseline.md § Open follow-ups updated по выбранному scenario: SCENARIO A → '26 carved finding IDs → all 26 closed in Phase 6e' + empty § Open follow-ups (post-6e); SCENARIO B → '26 carved finding IDs → 25 closed + 1 deferred (L16)' + § Open follow-ups (post-6e) contains L16 placeholder + 'reason: Codex code reviewer no-go'."
    - "wiki/log.md append-only entry для closure: date + source phase 6e + bullet summary."
    - ".planning/STATE.md: Phase 6e row → ✅ Closed; Active Phase block → Phase 7 (Anti-DPI suite + WireGuard family, v0.7); progress table updated."
    - ".planning/ROADMAP.md: Phase 6e Success Criteria checkboxes → marked checked; Phase 7 → Active."
    - ".planning/REQUIREMENTS.md: QUAL-04 + QUAL-05 added как Validated (если planner accepted proposal); либо justification если not added."
    - "Single final regression gate full suite (≥ baseline на каждом package) + iOS + macOS xcodebuild SUCCEEDED — verified ПЕРЕД closure commit per D-05a."
    - "Closure commit сообщение содержит ВСЕ closure deliverables и phase-final SHA references."
  artifacts:
    - path: ".planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md"
      provides: "Phase 6e closure record"
      contains: "Phase 6e"
    - path: "wiki/performance-baseline.md"
      provides: "long-term memory: § Open follow-ups updated to post-6e state"
      contains: "Phase 6e"
    - path: "wiki/log.md"
      provides: "append-only changelog entry for Phase 6e closure"
      contains: "Phase 6e"
    - path: ".planning/STATE.md"
      provides: "Active phase → 7; Phase 6e ✓ Closed"
    - path: ".planning/ROADMAP.md"
      provides: "Phase 6e Success Criteria checked; Phase 7 Active"
    - path: ".planning/REQUIREMENTS.md"
      provides: "QUAL-04, QUAL-05 Validated (если added)"
  key_links:
    - from: ".planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md"
      to: "wiki/performance-baseline.md § Open follow-ups (post-6e)"
      via: "cross-reference markdown link"
      pattern: "performance-baseline"
    - from: "wiki/log.md"
      to: ".planning/phases/06e-performance-audit-round-2-macos-uat-replay/"
      via: "closure entry references phase directory + key commit SHAs"
      pattern: "Phase 6e closure"
---

<objective>
Phase 6e — Wave 3: closure phase. Документирует выполненное в Wave 1 + Wave 2, обновляет long-term wiki memory + project state files. Никакого нового code change; чисто documentation + state sync.

**Purpose:** официально закрыть Phase 6e (v0.6.3 patch), подтвердить готовность к Phase 7, обновить wiki как long-term memory согласно проектному правилу «каждое архитектурное решение фиксируется в wiki» (см. `CLAUDE.md` § GSD Workflow).

**Output:**
- `06E-Final-SUMMARY.md` — closure record analog `06D-Final-SUMMARY.md` (но compact per D-05)
- `wiki/performance-baseline.md` § Open follow-ups updated (SCENARIO A: 26 carved IDs → all 26 closed in Phase 6e; SCENARIO B if L16 deferred: 26 IDs → 25 closed + 1 deferred L16). Trivial imports (3) — attributed к QUAL-05, отдельно от 26 L#/M# IDs.
- `wiki/log.md` append closure entry
- `.planning/STATE.md`, `ROADMAP.md`, `REQUIREMENTS.md` synced (Phase 6e ✓ Closed; Phase 7 Active; QUAL-04/05 Validated if added)
- 1 closure commit с references на all phase 6e SHAs
- Final regression gate pass (D-05a per CONTEXT.md)

**Scope NOT in this plan:** any code change (это documentation phase).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/REQUIREMENTS.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-VALIDATION.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-01-PLAN.md
@.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-02-PLAN.md
@.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@wiki/performance-baseline.md
@wiki/log.md
@wiki/index.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Final pre-closure regression gate (D-05a + D-09 8-check grep audit)</name>

  <files>
    (no source files — verification step before SUMMARY)
  </files>

  <read_first>
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-VALIDATION.md` § "D-09 Final Grep Audit" (full 8-check script)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-RESEARCH.md` Section 4 (architectural invariant map)
    - `.planning/phases/06d-performance-audit/06D-INVARIANT-AUDIT.md` (audit baseline patterns)
  </read_first>

  <action>
    Final regression gate ПЕРЕД написанием SUMMARY. Это D-05a requirement.

    1. **Full swift test:**
       - `swift test --package-path BBTB/Packages/AppFeatures` — expected ≥ 143/143 (Wave 1: 133 + 10 new = 143; Wave 2 L16 add +2 = 145 если landed)
       - `swift test --package-path BBTB/Packages/PacketTunnelKit` — expected ≥ 65/65 (61 + 4 от Wave 1 M8)
       - `swift test --package-path BBTB/Packages/VPNCore` — baseline 57/57
       - `swift test --package-path BBTB/Packages/ConfigParser` — baseline 210/210
       - `swift test --package-path BBTB/Packages/Localization` — baseline 3/3
       - `swift test --package-path BBTB/Packages/TransportRegistry` — baseline 42/42
       - Protocols packages — baseline counts
       Each MUST be green.

    2. **iOS + macOS xcodebuild:**
       - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` → BUILD SUCCEEDED
       - `xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` → BUILD SUCCEEDED

    3. **D-09 final 8-check grep audit per VALIDATION.md:**
       ```
       # 1. Forbidden symbols ≤ 7
       grep -rIn --include='*.swift' 'ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay' BBTB/Packages BBTB/App | grep -v '/Tests/' | wc -l   # ≤ 7 (baseline 4)

       # 2. NEVPN observer queue=.main = 0
       grep -rIn --include='*.swift' 'NEVPNStatusDidChange' BBTB/ | grep -E 'queue:\s*\.main' | wc -l   # 0

       # 3. #Predicate UUID? ≤ 1 (comment-only OK)
       grep -rIn --include='*.swift' -E '#Predicate.*UUID\?' BBTB/ | wc -l   # ≤ 1

       # 4. applyVPNStatus single authority
       grep -rIn --include='*.swift' 'func applyVPNStatus' BBTB/ | wc -l   # 1

       # 5. ExternalVPNStopMarker peek-only (.consume( callers = 0)
       grep -rIn --include='*.swift' 'ExternalVPNStopMarker' BBTB/ | grep '.consume(' | wc -l   # 0

       # 6. R18 sliding window = 2 hits (comment + code)
       grep -n 'toggle && intent' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift | wc -l   # 2

       # 7. PerfSignposter spans ≥ Phase 6d baseline (≥ 25)
       grep -rn 'PerfSignposter' BBTB --include="*.swift" | grep -v Tests | wc -l   # ≥ 25

       # 8. R10 defense-in-depth (BaseSingBoxTunnel SingBoxConfigLoader.validate ≥ 2)
       grep -c 'SingBoxConfigLoader.validate' BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/BaseSingBoxTunnel.swift   # ≥ 2
       ```
       Record actual numbers per check для Task 2 SUMMARY.

    4. **Periphery scan delta:**
       ```
       cd BBTB && periphery scan --workspace BBTB.xcworkspace --schemes BBTB BBTB-macOS --retain-public --report json
       ```
       Expected actionable count = 0 (34 false-positive remaining). Record actual count.

    5. Если ANY check FAIL — STOP, investigate root cause, revert offending commit per D-08; не proceed к SUMMARY до полного зелёного гейта.
  </action>

  <verify>
    <automated>swift test --package-path BBTB/Packages/AppFeatures &amp;&amp; swift test --package-path BBTB/Packages/PacketTunnelKit</automated>
    Executor дополнительно (после automated):
    - Запускает xcodebuild iOS + macOS commands
    - Запускает 8 D-09 grep audit команд + records results
    - Запускает periphery scan + records actionable count
    - Если ALL green → proceed Task 2
    - Если ANY fail → STOP + escalate per D-08
  </verify>

  <done>
    - All swift test packages green (baseline+)
    - iOS + macOS xcodebuild BUILD SUCCEEDED
    - D-09 8-check grep audit: results recorded (≤7/0/≤1/1/0/2/≥25/≥2)
    - Periphery actionable = 0 recorded
    - Working notes ready для Task 2 SUMMARY (test counts, audit numbers)
  </done>
</task>

<task type="auto">
  <name>Task 2: Write 06E-Final-SUMMARY.md (analog 06D-Final-SUMMARY.md, compact per D-05)</name>

  <files>
    .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md
  </files>

  <read_first>
    - `.planning/phases/06d-performance-audit/06D-Final-SUMMARY.md` (analog — frontmatter + sections structure)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-PATTERNS.md` Section "Wave 3 — Closure Artifacts Pattern" (06E-Final-SUMMARY.md required frontmatter + sections)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-CONTEXT.md` D-05 (closure SUMMARY spec — compact, не full 6d-style)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-01-PLAN.md` must_haves + Task 1-4 outcomes (commit SHAs из Wave 1)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-02-PLAN.md` must_haves + Task 1-7 outcomes (commit SHAs из Wave 2, L16 status)
    - Working notes из Task 1 (Wave 3 Task 1) — final regression gate results + D-09 8-check audit numbers + Periphery delta
    - Git log: `git log --oneline --since="2026-05-14" -- BBTB/Packages BBTB/App` (для actual commit SHAs)
  </read_first>

  <action>
    Создать `06E-Final-SUMMARY.md` в директории phase. Compact narrative per D-05 (не full Phase 6d-style; 26 findings × один-два line each).

    **Front-matter:**
    ```yaml
    ---
    phase: 06e-performance-audit-round-2
    plan: Final
    type: summary
    status: closed
    date: 2026-05-14
    findings_total: 26
    findings_closed_in_6e: <21 OR 22 — actual count depending L16 status>
    findings_subsumed_by_6d: <5 OR 4 — actual count>
    commits_total: <9 OR 10 — 4 Wave 1 atomic + 4-5 Wave 2 bundle + 1 closure>
    regression_gate_passes: <count Wave 1 4 + Wave 2 1 + Wave 3 1 = 6>
    hard_blockers_passed: "9/9 (D-07 PASS criteria fulfilled)"
    ---
    ```

    **Sections (compact per D-05):**

    1. **Status** — `Phase 6e ✅ Closed YYYY-MM-DD` (use today's date `2026-05-14`).

    2. **What Phase 6e delivered** — brief summary:
       - 4 atomic MEDIUM commits (Wave 1): M7, M10, M8+L12, M11.
       - 4-5 bundle commits (Wave 2): Theme A perf / Theme B correctness / Theme C-1 maintainability / Theme C-2 L16 (если landed) / Theme D trivial imports.
       - 5 bookkeeping rows (M6, M15, L6, L17, L19 subsumed-by-6d).
       - 4 new test files Wave 1 + 1 new test file Wave 2 (если L16 landed) = 4-5 new files.

    3. **Closed findings table — 26 rows** (action + commit SHA OR "subsumed by 6d <SHA>"):

       | ID | Severity | Action | Commit SHA |
       |---|---|---|---|
       | M7 | MEDIUM | fix(06e-M7) | `<actual SHA Wave 1 Task 1>` |
       | M10 | MEDIUM | fix(06e-M10) | `<actual SHA Wave 1 Task 2>` |
       | M8 | MEDIUM | fix(06e-M8 + L12) | `<actual SHA Wave 1 Task 3>` |
       | L12 | LOW (bundled with M8) | (same as M8) | (same as M8) |
       | M11 | MEDIUM | fix(06e-M11) | `<actual SHA Wave 1 Task 4>` |
       | M6 | MEDIUM | subsumed-by-6d | `1467328` + `9b38796` |
       | M15 | MEDIUM | subsumed-by-6d | `55bde6c` |
       | L1, L9, L10, L20 | LOW (Theme B) | chore(06e) correctness-cleanup | `<actual SHA Wave 2 Task 2>` |
       | L2, L5, L14, L15 | LOW (Theme C-1) | chore(06e) maintainability-cleanup | `<actual SHA Wave 2 Task 3>` |
       | L3, L4, L7, L8, L11, L13, L18 | LOW (Theme A) | chore(06e) perf-cleanup | `<actual SHA Wave 2 Task 1>` |
       | L16 | LOW (Theme C-2) | refactor(06e-L16) OR deferred к Phase 6f | `<SHA Wave 2 Task 5>` OR "deferred — Codex code reviewer no-go" |
       | L6, L17, L19 | LOW | subsumed-by-6d | `5ef3888` (L6), `bc7bc26` + `1467328` (L17), `b8d9294` (L19) |
       | Trivial-1, Trivial-2, Trivial-3 | trivial | chore(06e) remove unused imports | `<SHA Wave 2 Task 6>` |

    4. **Regression gate evidence** — per-wave + final:
       - Wave 1 (4× per-commit gate): AppFeatures test count progression + PacketTunnelKit + iOS + macOS xcodebuild.
       - Wave 2 (1× final gate): AppFeatures ≥ 143/143 (или 145 если L16 landed); PacketTunnelKit ≥ 65/65; other packages baseline; xcodebuild SUCCEEDED.
       - Wave 3 (1× pre-closure D-05a gate): same recap.

    5. **D-09 invariants final 8-check grep audit** — actual numbers from Task 1 working notes:
       | # | Check | Expected | Actual |
       |---|-------|----------|--------|
       | 1 | Forbidden symbols ≤ 7 | ≤ 7 | `<actual>` |
       | 2 | NEVPN observer queue=.main = 0 | 0 | `<actual>` |
       | 3 | #Predicate UUID? ≤ 1 | ≤ 1 | `<actual>` |
       | 4 | applyVPNStatus single authority | 1 | `<actual>` |
       | 5 | ExternalVPNStopMarker .consume(callers) = 0 | 0 | `<actual>` |
       | 6 | R18 sliding window `toggle && intent` = 2 | 2 | `<actual>` |
       | 7 | PerfSignposter spans ≥ 25 | ≥ 25 | `<actual>` |
       | 8 | R10 defense-in-depth ≥ 2 | ≥ 2 | `<actual>` |

    6. **DEC-06d-01..06 preservation confirmation** — bullet checklist:
       - [x] DEC-06d-01 cold-start init defer — Task.detached внутри handleForegroundReentry preserved
       - [x] DEC-06d-02 XPC consolidation ≤ 2 trips — M7 / M10 / M11 не добавляют XPC; L11 reduces N→1
       - [x] DEC-06d-03 event-driven status polling — L9 TTL = one-shot Task.sleep, не poll-loop
       - [x] DEC-06d-04 bounded probe concurrency — untouched
       - [x] DEC-06d-05 Apple-canonical options + ExternalVPNStopMarker — peek-only API preserved
       - [x] DEC-06d-06 PerfSignposter spans — preserved (≥ 25 grep audit)

    7. **R10 defense-in-depth preservation (M8 critical)** — post-expand `SingBoxConfigLoader.validate(json: expandedJSON)` остаётся unconditional в BaseSingBoxTunnel.swift; pre-expand validate теперь skipped когда `configJSONValidatedAt < 24h`. R10 invariant из `wiki/security-gaps.md` preserved.

    8. **Periphery scan result** — actionable count: `<actual>` (target 0; baseline 3 → after Theme D = 0). Это closes QUAL-05.

    9. **Deferred items** (per CONTEXT.md `<deferred>`):
       - Numerical Instruments baseline — Phase 11/12 (PerfSignposter готов).
       - macOS UAT replay (A/F-direct/F-reverse/Settings-disable/G) — Phase 11/12.
       - NET-12 (active liveness probe) — Phase 7-8.
       - L16 (если deferred) — Phase 6f либо integrated в Phase 7+ refactor scope.

    10. **Next phase signal** — `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).

    Use Write tool. НЕ heredoc.
  </action>

  <verify>
    <automated>test -f .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md</automated>
    Дополнительно:
    - `grep -c "^## Status" .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` ≥ 1
    - `grep -c "Phase 6e ✅ Closed" .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` ≥ 1
    - `grep -c "subsumed-by-6d\|subsumed by Phase 6d" .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` ≥ 5 (5 bookkeeping rows minimum)
    - `grep -c "DEC-06d" .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` ≥ 6 (preservation checklist 6 items)
    - `wc -l .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` reports ≥ 80 lines (full document body)
  </verify>

  <done>
    - 06E-Final-SUMMARY.md created
    - Frontmatter: phase + plan + status: closed + counts
    - 10 sections written per spec
    - All 26 findings accounted в table
    - Actual commit SHAs filled
    - D-09 grep audit numbers filled
    - DEC preservation checklist 6/6 checked
  </done>
</task>

<task type="auto">
  <name>Task 3: Update wiki/performance-baseline.md § Open follow-ups + wiki/log.md append</name>

  <files>
    wiki/performance-baseline.md
    wiki/log.md
  </files>

  <read_first>
    - `wiki/performance-baseline.md` (full — особенно existing § Open follow-ups section, которая listed 26 carved findings после Phase 6d closure)
    - `wiki/log.md` (full — last entry pattern = Phase 6d closure)
    - `wiki/index.md` (check если нужен ли additional entry — likely нет; performance-baseline.md уже indexed)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` (только что создан в Task 2)
  </read_first>

  <action>
    Wiki sync per CLAUDE.md project rule "каждое архитектурное решение или технологический выбор, принятый в ходе GSD-работы, обязательно фиксируется в wiki".

    **1. `wiki/performance-baseline.md` § Open follow-ups UPDATE:**

    Найти существующую section "§ Open follow-ups" (либо "Open follow-ups", либо "Carved findings backlog"). Заменить content:

    - **BEFORE (post-Phase-6d):** список 26 carved findings с file:line.
    - **AFTER (post-Phase-6e):**
      ```
      ## Open follow-ups (post-6e)

      **Status:** ✅ Все 26 carved findings из Phase 6d закрыты в Phase 6e (closure 2026-05-14, v0.6.3).

      Распределение закрытий (см. `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` для commit SHAs):
      - **4 MEDIUM atomic fixes (Wave 1):** M7 (scenePhase coalesce), M8 + L12 (validatedAt cache + R10 preserved), M10 (loadFromStore idempotency), M11 (applyVPNStatus explicit guard).
      - **16 LOW в 4 bundle commits (Wave 2):** Theme A perf (L3/L4/L7/L8/L11/L13/L18) / Theme B correctness (L1/L9/L10/L20) / Theme C-1 maintainability (L2/L5/L14/L15) / Theme C-2 L16 [см. status в 06E-Final-SUMMARY].
      - **3 trivial unused imports (Wave 2 Theme D):** ConfigParser × 2 + DesignSystem × 1.
      - **5 bookkeeping subsumed-by-6d:** M6 (`1467328` + `9b38796`), M15 (`55bde6c`), L6 (`5ef3888`), L17 (`bc7bc26` + `1467328`), L19 (`b8d9294`).

      **Carry-forward backlog (post-6e):**
      - **NET-12** — active liveness probe (Phase 6c R18 carve-out) → Phase 7-8.
      - **Numerical Instruments baseline** — defer к Phase 11/12 (pre-TestFlight obligatory; PerfSignposter spans готов).
      - **macOS UAT replay (5 scenarios A/F-direct/F-reverse/Settings-disable/G)** — defer к Phase 11/12.
      - **L16 (если deferred)** — applyVPNStatus extraction reviewer no-go → Phase 6f либо integrated в Phase 7+ refactor.
      ```

    Использовать Edit tool с exact-string match на existing "Open follow-ups" section. Если nuance в naming — read full wiki/performance-baseline.md ПЕРЕД Edit для точной строки match.

    **2. `wiki/log.md` APPEND:**

    Найти tail файла. APPEND новую entry:
    ```
    ## 2026-05-14 — Phase 6e closure (Performance Audit Round 2)

    - **Source:** `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/` (06E-CONTEXT, 06E-RESEARCH, 06E-PATTERNS, 06E-VALIDATION, 06E-01..03-PLAN, 06E-Final-SUMMARY)
    - **Changes:**
      - `wiki/performance-baseline.md` — § Open follow-ups переход '26 carved' → '26 closed in Phase 6e'.
      - Phase 6e commits landed: 4 MEDIUM atomic (M7/M10/M8+L12/M11) + 4-5 LOW bundles (perf/correctness/maintainability/[L16]/trivial-imports) + 1 closure commit.
      - 5 bookkeeping rows: M6, M15, L6, L17, L19 subsumed-by-6d.
      - Periphery actionable count: 3 → 0 (QUAL-05 closure proof).
    - **Preservation:** DEC-06d-01..06 + D-09 invariants + R10 defense-in-depth + R18 sliding window — все verified через final grep audit (8 checks).
    - **Version:** v0.6.3 (patch).
    - **Next:** `/gsd-discuss-phase 7` (Anti-DPI suite + WireGuard family, v0.7).
    ```

    Use Edit tool with append (insert before EOF) или Write tool reading current content + appending.

    **3. Check `wiki/index.md`:** если performance-baseline.md уже indexed — skip; если нет — add link. Likely already indexed после Phase 6d.

    НЕ нарушить project rule: page format header (Summary / Sources / Last updated) preservation в wiki/performance-baseline.md — обновить `**Last updated**` date.
  </action>

  <verify>
    <automated>grep -c "Phase 6e" wiki/performance-baseline.md &amp;&amp; grep -c "Phase 6e closure" wiki/log.md</automated>
    Дополнительно:
    - `grep -c "Open follow-ups (post-6e)" wiki/performance-baseline.md` ≥ 1
    - `grep -c "2026-05-14 — Phase 6e closure" wiki/log.md` ≥ 1
    - `grep -c "26 closed in Phase 6e\|all 26 carved findings\|Все 26 carved findings" wiki/performance-baseline.md` ≥ 1
    - `grep -c "NET-12" wiki/performance-baseline.md` ≥ 1 (carry-forward backlog preserved)
    - Last updated date в wiki/performance-baseline.md обновлён к 2026-05-14
  </verify>

  <done>
    - wiki/performance-baseline.md § Open follow-ups updated к post-6e state
    - wiki/log.md APPEND closure entry (2026-05-14 — Phase 6e closure)
    - wiki/index.md verified (no changes если уже indexed)
    - Last updated dates synced
  </done>
</task>

<task type="auto">
  <name>Task 4: Sync .planning/STATE.md + ROADMAP.md + REQUIREMENTS.md (Phase 6e ✅ Closed; Phase 7 Active; QUAL-04/05 Validated)</name>

  <files>
    .planning/STATE.md
    .planning/ROADMAP.md
    .planning/REQUIREMENTS.md
  </files>

  <read_first>
    - `.planning/STATE.md` (full — особенно "Active Phase" block + "Progress" table)
    - `.planning/ROADMAP.md` (full Phase 6e entry + Phase 7 entry)
    - `.planning/REQUIREMENTS.md` (PERF/QUAL section, last updated)
    - `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md` (только что создан в Task 2 — для actual commit SHAs + counts)
  </read_first>

  <action>
    Sync 3 project-level files per Phase 6e closure.

    **1. `.planning/STATE.md`:**

    - **Frontmatter:**
      - `milestone:` stays `v0.12` (final v0.12 + v1.0).
      - `status:` change → `"Phase 6e ✅ Closed 2026-05-14 — 26 carved findings cleanup (4 MEDIUM atomic + 4-5 LOW bundles + 5 subsumed). Next: /gsd-discuss-phase 7 (Anti-DPI suite + WireGuard family, v0.7)."`
      - `last_updated:` → `"2026-05-14T<HH:MM:SS>.000Z"` (current time).
      - `completed_phases:` increment by 1 (was 8, now 9 — 1/2/3/4/5/6 impl/6c/6d/6e).
      - `completed_plans:` increment by 3 (06E-01 + 06E-02 + 06E-03; new total +3).
      - `percent:` recompute (9/14 = 64%) либо derive из completed_plans/total_plans.

    - **Active Phase block:** REPLACE Phase 6e block с **Active Phase = Phase 7** stub:
      - **Phase:** 7
      - **Name:** Anti-DPI suite + WireGuard family
      - **Status:** Not started. Next step: `/gsd-discuss-phase 7` to gather context.
      - **Goal:** (carry from ROADMAP.md Phase 7 entry — Anti-DPI techniques + remaining 4 protocols WireGuard/AmneziaWG/TUIC v5/OpenVPN-TLS)
      - **Version:** v0.7
      - **Requirements:** PROTO-06..09 + DPI-01..05 + DPI-07 (carry from ROADMAP.md)

    - **Previous phase block (former "Active"):** MOVE existing Phase 6e content to "Previous phase" section, mark:
      - **Status:** ✅ Closed 2026-05-14
      - **Version:** v0.6.3 (patch)
      - **Outcome:** brief — SCENARIO A (L16 landed) 21 active fixes + 5 subsumed-by-6d OR SCENARIO B (L16 deferred) 20 active + 5 bookkeeping + 1 deferred; 4 MEDIUM atomic + 4-5 LOW bundles + 1 closure; Periphery actionable 3 → 0; DEC-06d-01..06 preserved; D-09 + R10 + R18 invariants preserved.
      - **Final commits:** reference 06E-Final-SUMMARY.md.
      - **Closure SUMMARY:** `.planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md`.

    - **Progress table:** update Phase 6e row from "**Active**" → "✅ Closed 2026-05-14 — 26 carved closed; QUAL-04 + QUAL-05 Validated"; add Phase 7 row marked "Active — next: `/gsd-discuss-phase 7`".

    - **Backlog section:** update entry "26 carved-out findings" → "✅ Closed in Phase 6e (2026-05-14)". Other items (NET-12 → Phase 7-8; macOS UAT → Phase 11/12; Numerical Instruments → Phase 11/12) — preserve as-is.

    - **Footer:** update "Last updated" line.

    **2. `.planning/ROADMAP.md`:**

    - **Phase 6e section (around line 233):**
      - Header `### Phase 6e:` → `### Phase 6e: Performance Audit Round 2 + macOS UAT replay ✅ Closed 2026-05-14`
      - **Success Criteria** checkboxes — mark all `- [ ]` → `- [x]` где applicable (1-7 per criteria text).
      - Add closure note по выбранному scenario: `**Outcome:** SCENARIO A (L16 landed) → 21 active fixes (4 MEDIUM atomic + 4-5 LOW bundle commits) + 5 subsumed-by-6d OR SCENARIO B (L16 deferred) → 20 active fixes + 5 bookkeeping + 1 deferred (L16 → Phase 6f либо integrated в Phase 7+ refactor). Periphery actionable: 3 → 0. PERF-01..05 + QUAL-01..03 preserved Validated; QUAL-04 + QUAL-05 added Validated (SCENARIO B: QUAL-04 с явным exception note по L16). Closure SUMMARY: .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md.`
      - **Plans list:**
        ```
        Plans:
        - [x] 06E-01-PLAN.md — Wave 1: 4 atomic MEDIUM fixes (M7/M10/M8+L12/M11) ✓
        - [x] 06E-02-PLAN.md — Wave 2: 4-5 LOW bundle commits (Themes A/B/C-1/C-2/D) ✓
        - [x] 06E-03-PLAN.md — Wave 3: closure (SUMMARY + wiki sync + state/roadmap/requirements sync) ✓
        ```

    - **Phase 7 section (around line 263 if exists):** unchanged (gets activated через `/gsd-discuss-phase 7`).

    **3. `.planning/REQUIREMENTS.md`:**

    - **PERF/QUAL section** add NEW Validated entries (decision per RESEARCH.md Q5 — добавляем оба QUAL-04 + QUAL-05; researcher не настаивает, но logical для closure tracking):
      ```
      - [x] **QUAL-04**: Carved-out backlog Phase 6d (26 finding IDs) полностью accounted; baseline maximally clean перед Phase 7. *(Phase 6e ✓ Closed 2026-05-14 — SCENARIO-specific: A = 21 active fixes + 5 subsumed-by-6d; B = 20 active + 5 bookkeeping + 1 deferred L16 [reason filled из Codex reviewer no-go]. Closure SUMMARY: 06E-Final-SUMMARY.md)*
      - [x] **QUAL-05**: Periphery dead-code scan на post-Phase-6e baseline: actionable count = 0 (down from 3 в Phase 6d closure). *(Phase 6e ✓ Closed 2026-05-14 — 3 trivial unused imports removed Theme D; Periphery delta 37 → 34 false-positive only)*
      ```

    - **Last updated footer:** update date к 2026-05-14 (либо append если already 2026-05-14 от Phase 6d).

    Use Edit tool с exact-string matches; либо Write tool (после Read) для STATE.md / ROADMAP.md если scope changes велик.

    НЕ нарушить:
    - Frontmatter YAML syntax preserved.
    - Existing requirements (PERF-01..05 + QUAL-01..03) untouched — only ADD QUAL-04/05.
    - Phase 7 entry в ROADMAP.md untouched (только Phase 6e entry modified).
  </action>

  <verify>
    <automated>grep -c "Phase 6e ✅ Closed" .planning/STATE.md &amp;&amp; grep -c "Phase 6e: Performance Audit Round 2 + macOS UAT replay ✅ Closed" .planning/ROADMAP.md</automated>
    Дополнительно:
    - `grep -c "QUAL-04" .planning/REQUIREMENTS.md` ≥ 1
    - `grep -c "QUAL-05" .planning/REQUIREMENTS.md` ≥ 1
    - `grep -c "\\[x\\] \\*\\*QUAL-04\\*\\*" .planning/REQUIREMENTS.md` ≥ 1 (Validated check applied)
    - `grep -c "completed_phases: 9" .planning/STATE.md` = 1 (was 8 → now 9)
    - `grep -c "Active.*Phase 7\\|Anti-DPI suite + WireGuard family" .planning/STATE.md` ≥ 1 (Phase 7 made active)
    - `grep -c "\\[x\\] 06E-01-PLAN" .planning/ROADMAP.md` ≥ 1 (plans marked done)
  </verify>

  <done>
    - STATE.md frontmatter updated (status, last_updated, completed_phases, completed_plans, percent)
    - STATE.md Active Phase → Phase 7
    - STATE.md Progress table — Phase 6e marked Closed, Phase 7 marked Active
    - ROADMAP.md Phase 6e Success Criteria checked, Plans list checked, Outcome note added
    - REQUIREMENTS.md QUAL-04 + QUAL-05 added Validated
    - All "Last updated" footers synced to 2026-05-14
  </done>
</task>

<task type="auto">
  <name>Task 5: Closure commit + final verification</name>

  <files>
    .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md
    wiki/performance-baseline.md
    wiki/log.md
    .planning/STATE.md
    .planning/ROADMAP.md
    .planning/REQUIREMENTS.md
  </files>

  <read_first>
    - `git status` (verify only закрепляемые closure docs modified; никаких stray source code changes)
    - `git diff --stat` (review files touched)
  </read_first>

  <action>
    Final closure commit с references на all phase 6e SHAs.

    1. Stage только closure files (NO source code changes в этом коммите):
       ```
       git status
       # Verify: ONLY .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md,
       # wiki/performance-baseline.md, wiki/log.md, .planning/STATE.md, .planning/ROADMAP.md, .planning/REQUIREMENTS.md
       # Если есть stray source changes — STOP, investigate.
       ```

    2. Construct commit message (HEREDOC):
       ```
       gsd-sdk query commit "$(cat <<'EOF'
       docs(06e): Phase 6e closure — 26 carved findings cleanup ✅

       Phase 6e «Performance Audit Round 2» закрыта 2026-05-14 (v0.6.3 patch).

       Outcome:
       - 4 atomic MEDIUM commits (Wave 1): M7 / M10 / M8+L12 / M11
       - 4-5 LOW bundle commits (Wave 2): perf-cleanup / correctness-cleanup /
         maintainability-cleanup / [L16 extraction conditional] / trivial-imports
       - 5 bookkeeping rows: M6 / M15 / L6 / L17 / L19 subsumed-by-Phase-6d

       Invariants preserved (final grep audit 8 checks PASS):
       - DEC-06d-01..06 architectural patterns
       - D-09 forbidden symbols / observer queue / #Predicate UUID? / applyVPNStatus single authority
       - R10 defense-in-depth (post-expand validate unconditional)
       - R18 sliding window (toggle && intent = 2)
       - ExternalVPNStopMarker peek-only API

       Periphery actionable count: 3 → 0 (QUAL-05 closure proof).
       Test counts final: AppFeatures ≥ 143/143, PacketTunnelKit ≥ 65/65, baselines on others.

       Next: /gsd-discuss-phase 7 (Anti-DPI suite + WireGuard family, v0.7).
       EOF
       )" --files .planning/phases/06e-performance-audit-round-2-macos-uat-replay/06E-Final-SUMMARY.md wiki/performance-baseline.md wiki/log.md .planning/STATE.md .planning/ROADMAP.md .planning/REQUIREMENTS.md
       ```

       Использовать `gsd-sdk query commit` для explicit file staging (no `git add .`) per Phase 6d practice.

    3. Verify commit landed: `git log --oneline -1` should show `docs(06e): Phase 6e closure ...`.

    4. **Final regression gate replay (D-05a — final pre-merge):**
       - `swift test --package-path BBTB/Packages/AppFeatures` → ≥ 143/143
       - `swift test --package-path BBTB/Packages/PacketTunnelKit` → ≥ 65/65
       - `xcodebuild ... BBTB iOS Simulator build` → BUILD SUCCEEDED
       - `xcodebuild ... BBTB-macOS build` → BUILD SUCCEEDED
       (Это второй раз для Wave 3; первый был Task 1 pre-SUMMARY. Defensive check на случай ничто не сломалось во время docs writes.)

    5. Если final gate green → Phase 6e officially closed. Print summary to user:
       ```
       ## ✅ Phase 6e ✅ Closed 2026-05-14 — v0.6.3

       26 carved findings closure:
       - 21 active fixes (4 MEDIUM atomic + 4-5 LOW bundles)
       - 5 subsumed-by-6d bookkeeping
       - Periphery actionable: 3 → 0
       - All DEC-06d-01..06 + D-09 + R10 + R18 invariants preserved

       Next: /gsd-discuss-phase 7 (Anti-DPI suite + WireGuard family, v0.7)
       ```

    6. Если final gate fails — investigate root cause (likely unrelated drift), per D-08; не proceed к celebration.
  </action>

  <verify>
    <automated>git log --oneline -1 | grep -c "docs(06e): Phase 6e closure"</automated>
    Дополнительно:
    - `swift test --package-path BBTB/Packages/AppFeatures` ≥ 143/143
    - `swift test --package-path BBTB/Packages/PacketTunnelKit` ≥ 65/65
    - `xcodebuild ... BBTB iOS Simulator build` → BUILD SUCCEEDED
    - `xcodebuild ... BBTB-macOS build` → BUILD SUCCEEDED
    - `git status` clean (no uncommitted changes after closure commit)
  </verify>

  <done>
    - Closure commit landed: `docs(06e): Phase 6e closure — 26 carved findings cleanup ✅`
    - Final regression gate green (replay)
    - User summary printed: Phase 6e ✅ Closed; next /gsd-discuss-phase 7
    - git status clean
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Documentation ↔ project state | Closure documentation source-of-truth для phase 6e outcomes — must accurately reflect actual SHAs + test results + grep audit numbers |
| wiki ↔ planning | wiki/performance-baseline.md = long-term memory; .planning/ = oprerational state — synced as cross-references |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-6e-09 | Repudiation / Integrity | 06E-Final-SUMMARY.md commit SHA documentation | **mitigate** | Task 2 use `git log --oneline --since="..."` для actual SHAs; не invented placeholders. Task 5 closure commit includes all SHA references. |
| T-6e-10 | Information Disclosure | wiki/log.md append entry | **accept** | Append-only changelog; no secrets exposed; references public commit SHAs. LOW severity. |
| T-6e-11 | Integrity | .planning/STATE.md frontmatter update | **mitigate** | YAML syntax preserved through Edit tool (not heredoc); progress counters derived from actual completed_plans. Verify через grep после Task 4. |
</threat_model>

<verification>
**Final regression gate в Task 1 (D-05a per CONTEXT.md):**
1. swift test all packages ≥ baseline+
2. iOS + macOS xcodebuild SUCCEEDED
3. D-09 8-check grep audit numbers recorded
4. Periphery actionable = 0

**Final regression gate REPLAY в Task 5 (D-05a defensive second pass):**
Same checks; ensures no drift from docs writes.

**D-08 FAIL recovery:** если final gate FAIL — STOP, investigate root cause; не proceed к closure commit. Possible roots: unrelated test flake (re-run); accidental source change в docs file (revert); upstream library drift (escalate к user).

**Verification of completeness (Task 2 SUMMARY):**
- 26 carved finding IDs accounted по выбранному сценарию (sum invariant):
  - SCENARIO A (L16 landed): 21 code-fixed IDs (Wave 1: M7+M10+M8+L12+M11 = 5; Wave 2: L1, L2, L3, L4, L5, L7, L8, L9, L10, L11, L13, L14, L15, L16, L18, L20 = 16) + 5 bookkeeping subsumed-by-6d (M6, M15, L6, L17, L19) = **26 ✓**.
  - SCENARIO B (L16 deferred): 20 code-fixed IDs (Wave 1: 5; Wave 2: 15 without L16) + 5 bookkeeping + 1 deferred (L16) = **26 ✓**.
- Trivial imports (3) — attributed к QUAL-05, считаются ОТДЕЛЬНО от 26 L#/M# IDs (Periphery-derived из 06D-PERIPHERY-POST-FIX.md, не из 06D-FINDINGS.md catalog).
- All Wave 1 + Wave 2 commit SHAs filled
- DEC-06d-01..06 preservation checklist 6/6 checked
- D-09 grep audit 8/8 actual numbers filled

**Verification of project state (Task 4 sync):**
- STATE.md progress: completed_phases 8 → 9; completed_plans +3
- ROADMAP.md Phase 6e Success Criteria all checked
- REQUIREMENTS.md QUAL-04 + QUAL-05 Validated added (или не added if planner discretion — document either way)

**Verification of closure commit (Task 5):**
- git log shows `docs(06e): Phase 6e closure ...` as HEAD
- git status clean
- Files staged: ONLY 6 closure files (no source code changes)
</verification>

<success_criteria>
- `06E-Final-SUMMARY.md` created с frontmatter (phase, status: closed, 2026-05-14) + 10 sections per spec (Status / What delivered / Closed findings table / Regression gate / D-09 audit / DEC preservation / R10 preservation / Periphery / Deferred / Next phase)
- All 26 carved finding IDs explicitly accounted по выбранному scenario (SCENARIO A: 21 active fixes + 5 bookkeeping; SCENARIO B: 20 active + 5 bookkeeping + 1 deferred L16). Commit SHAs filled для всех code-fixed IDs; subsumed-by-6d SHAs filled для bookkeeping (M6, M15, L6, L17, L19). Trivial imports (3) — отдельная строка, attributed к QUAL-05.
- `wiki/performance-baseline.md` § Open follow-ups updated: SCENARIO A → 'all 26 carved IDs closed in Phase 6e'; SCENARIO B → '25 closed + 1 deferred (L16)' с reason note. Carry-forward backlog (NET-12, Numerical Instruments, macOS UAT, L16 if SCENARIO B) preserved.
- `wiki/log.md` APPEND closure entry (date + source + bullet summary)
- `.planning/STATE.md` updated: status (closed Phase 6e), Active Phase → 7, Progress table, Backlog, frontmatter (completed_phases 9, completed_plans +3)
- `.planning/ROADMAP.md` Phase 6e Success Criteria checkboxes marked; Plans list checked; Outcome note added
- `.planning/REQUIREMENTS.md` QUAL-04 + QUAL-05 added Validated (либо documented decision не добавлять)
- Closure commit landed: `docs(06e): Phase 6e closure — 26 carved findings cleanup ✅`
- Final regression gate (replayed in Task 5) green
- User-facing summary printed
- D-09 8-check grep audit final verification: all expected values matched
</success_criteria>

<output>
After Task 5 completion, Phase 6e is officially closed. No additional artifact creation required beyond `06E-Final-SUMMARY.md` (created in Task 2).

User signal:
```
## ✅ Phase 6e ✅ Closed 2026-05-14 — v0.6.3

26 carved finding IDs closure (по выбранному scenario):
- SCENARIO A (L16 landed): 21 active fixes (4 MEDIUM atomic + 16 LOW + L12 bundled with M8) + 5 subsumed-by-6d bookkeeping (M6, M15, L6, L17, L19) = 26 ✓
- SCENARIO B (L16 deferred): 20 active fixes + 5 bookkeeping + 1 deferred (L16) = 26 ✓
- Trivial imports (3) — отдельно от 26 L#/M# IDs, attributed к QUAL-05
- Periphery actionable: 3 → 0 (QUAL-05 proof)
- All DEC-06d-01..06 + D-09 + R10 + R18 invariants preserved

Next: /gsd-discuss-phase 7 (Anti-DPI suite + WireGuard family, v0.7)
```
</output>
