---
phase: 06d-performance-audit
plan: 02b
slice: b
type: execute
wave: 2.2
mode: mvp
depends_on: [02a]
files_modified:
  - .planning/phases/06d-performance-audit/06D-FINDINGS.md
  - .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
autonomous: true
requirements: [QUAL-02, QUAL-03]
tags: [synthesis, multi-ai, dedup, consensus, invariant-filter, opus-synthesizer]

must_haves:
  truths:
    - "06D-FINDINGS.md полностью заполнен (consolidated table, rejected/filtered секции, coverage matrix)."
    - "Synthesis выполнен Opus 4.7 (D-04 explicit); НЕ делегирован к Codex/Gemini."
    - "Invariant-violation findings отфильтрованы в отдельную секцию '## 3. Rejected findings' с rationale + reference на конкретный D-09 invariant."
    - "Out-of-scope findings (D-02a: libbox rewrite / SwiftPM migration / new deps без justification) в '## 4. Filtered findings'."
    - "Consensus markers (3/3 strong / 2/3 moderate / 1/3 unique-but-valuable) применены к каждому row."
    - "Coverage matrix (AI × dimension) заполнена реальными counts."
    - "Dedup pass устранил false-uniqueness (Pitfall 1) — semantic duplicates merged."
    - "Anti-bias rule (RESEARCH Open Question #5) применён — Opus's own findings в конфликте с Codex/Gemini документированы как 'rejected my own'."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS.md"
      provides: "Consolidated multi-AI synthesis с consensus markers + invariant filter + coverage matrix"
      contains: "Consensus"
    - path: ".planning/phases/06d-performance-audit/06D-02b-SUMMARY.md"
      provides: "Wave 02b closure record — synthesis metrics + counts по AI/dimension/severity"
  key_links:
    - from: "06D-FINDINGS-{OPUS,CODEX,GEMINI}.md"
      to: "06D-FINDINGS.md"
      via: "Synthesis: dedup + consensus + invariant filter"
      pattern: "Consolidated findings"
    - from: "Each finding row"
      to: "Consensus marker (3/3 / 2/3 / 1/3)"
      via: "AI presence columns"
      pattern: "3/3 strong|2/3 moderate|1/3 unique"
---

# Phase 6d Wave 02b — Synthesis: consolidated FINDINGS + invariant filter + coverage matrix

## Цель волны (по-русски)

Wave 06D-02b — **аналитическая синтезирующая** волна. Opus 4.7 читает все три AI-pass файла из Wave 06D-01 (`06D-FINDINGS-OPUS.md`, `06D-FINDINGS-CODEX.md`, `06D-FINDINGS-GEMINI.md`) и складывает в один consolidated `06D-FINDINGS.md` с:

- **Consensus markers** (3/3 / 2/3 / 1/3) для каждого finding.
- **Dedup pass** — устранение false-uniqueness (Pitfall 1).
- **Invariant filter** — finding-и, нарушающие D-09 Phase 6c invariants → в Rejected section.
- **Out-of-scope filter** (D-02a) — libbox rewrite / SwiftPM migration / unjustified deps → в Filtered section.
- **Coverage matrix** — AI × dimension counts.

**Anti-bias rule** (RESEARCH Open Question #5): при конфликте Opus's finding vs Codex/Gemini, **другая AI wins по default**; документировать каждый «rejected my own finding because…» entry.

После Wave 06D-02b → Wave 06D-02c (pre-fix Instruments baseline + CHECKPOINT 1 prep).

---

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/06d-performance-audit/06D-CONTEXT.md
@.planning/phases/06d-performance-audit/06D-RESEARCH.md
@.planning/phases/06d-performance-audit/06D-PATTERNS.md
@.planning/phases/06d-performance-audit/06D-01-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md
@.planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
@.planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1 — Synthesis: consolidated 06D-FINDINGS.md + invariant filter + coverage matrix</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md
    - .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
    - .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md
    - .planning/phases/06d-performance-audit/06D-CONTEXT.md (D-04 synthesis format, D-09 invariants)
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секция «Common Pitfalls / Pitfall 1 — False uniqueness», «Pitfall 2 — Invariant rollback»; секция «Recommended forbidden-finding categories (synthesis filter)»)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role D — synthesis format, Shared 3 — memory anti-pattern guard)
    - 5 memory files в D-09 list (re-read для свежей памяти invariant rationale):
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_observer_queue_main.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_connectedDate_authority_for_since.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_xpc_mach_port.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_swiftdata_uuid_predicate.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_failover_two_phase_init.md
  </read_first>
  <action>
    Произвести **synthesis** трёх AI-pass файлов в один consolidated `06D-FINDINGS.md`. Opus 4.7 — synthesizer (D-04). Anti-bias rule per RESEARCH Open Question #5: при конфликте Opus's finding vs Codex/Gemini, **другая AI wins по default**; задокументировать каждый «rejected my own finding because…» entry.

    **Шаги:**

    1. **Read all three AI pass files в полном объёме**. Не пропускать ни одной findings table row.

    2. **Dedup pass** (Pitfall 1):
       - Для каждой строки в OPUS: проверить, есть ли семантически эквивалентная в CODEX или GEMINI (даже если File:Line другой).
       - "Семантически эквивалентная" — same root cause + same dimension + same severity tier. Title может различаться.
       - Merge identical findings в один row; колонки Opus/Codex/Gemini = `[FOUND]` / `[NOT FOUND]` соответственно.
       - File:Line — выбрать наиболее точный из трёх; альтернативные локации — в `Description` как "также упомянуто в…".

    3. **Consensus markers** (D-04):
       - `3/3 strong` — все три AI нашли.
       - `2/3 moderate` — две AI.
       - `1/3 unique-but-valuable` — одна AI, но finding имеет concrete value (не drop в Filtered).

    4. **Invariant filter** (Pitfall 2 + Shared 3 в PATTERNS):
       - Для каждой строки проверить: предлагает ли она rollback одного из 5 Phase 6c invariants (D-09)?
         - `TunnelController.handleStatusChange` intent-closing rollback?
         - Reintroduce XPC в NEVPNStatusDidChange observer?
         - Reintroduce ReconnectStateMachine / NetworkReachability / custom retry?
         - Break single-authority applyVPNStatus?
         - Break sliding session window?
         - Observer queue `.main` (memory feedback_nevpn_observer_queue_main.md)?
         - `#Predicate` с optional UUID (memory feedback_swiftdata_uuid_predicate.md)?
       - Если **yes** — DROP, переместить в `## 3. Rejected findings (Phase 6c invariant violations — D-09)` table с rationale + reference на конкретный invariant.

    5. **Out-of-scope filter** (D-02a):
       - libbox / sing-box / gomobile rewrite proposals → DROP, в `## 4. Filtered findings` table.
       - SwiftPM → Bazel migration → DROP.
       - New dependency без user-impact justification (≥ HIGH/MEDIUM threshold) → DROP.

    6. **Abstract-beauty filter**:
       - "Could be more functional" / "consider Combine instead of @Published" без measurable user impact → DROP, в `## 4. Filtered findings`.

    7. **False-uniqueness check** (Pitfall 1):
       - Если 5+ строк имеют identical "Description" но разные "File:Line" — это **один real finding**, merge.

    8. **Coverage matrix** (Section 5):
       - Для каждой AI × dimension cell: count найденных findings. Например:
         ```
         | AI | Performance | Energy | Simplicity | Memory | Launch |
         | Opus | 8 | 2 | 12 | 3 | 5 |
         | Codex | 6 | 1 | 9 | 2 | 4 |
         | Gemini | 5 | 3 | 7 | 4 | 3 |  (или N/A если skipped)
         ```
       - Это даёт user интуицию о per-AI bias.

    9. **Language convention** (D-11):
       - Section headers и colonki — на русском.
       - Title и Description колонки — допустимы на английском (точнее терминология).
       - Code anchors (File:Line, function names) — verbatim, без перевода.

    10. **Заполнить 06D-FINDINGS.md** по skeleton из 06D-01 Task 4. Section 6 (Notes for CHECKPOINT 1) — оставить «TBD Wave 06D-02c Task 3» — следующая sub-wave закроет.

    **Atomic commit:** один commit `docs(06d-02b): synthesis of 3 AI passes — consolidated FINDINGS with consensus markers + invariant filter`.

    **NB:** Synthesis — это аналитическая работа Opus. **Не делегировать к Codex/Gemini** (D-04 explicit: Opus synthesizes). Antibias rule в коммите body.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && test $(wc -c < .planning/phases/06d-performance-audit/06D-FINDINGS.md) -gt 4000 \
        && grep -q "Consolidated findings" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Rejected findings.*invariant" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Filtered findings" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Coverage matrix" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -qE "3/3 strong|2/3 moderate|1/3 unique" .planning/phases/06d-performance-audit/06D-FINDINGS.md
    </automated>
  </verify>
  <done>
    06D-FINDINGS.md полностью заполнен: consolidated findings table с consensus markers, отдельные секции rejected-by-invariant + filtered-out-of-scope, coverage matrix по AI×dimension. Dedup проведён (false-uniqueness устранён). D-09 invariants защищены — нарушения в rejected table.
  </done>
</task>

<task type="auto">
  <name>Task 2 — 06D-02b-SUMMARY.md closure record</name>
  <files>
    .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (заполнен в Task 1)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role M — summary shape)
    - .planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md (shape reference)
  </read_first>
  <action>
    Создать `06D-02b-SUMMARY.md` (Role M shape) — closure record для synthesis wave.

    Структура:
    ```markdown
    ---
    phase: 06d-performance-audit
    plan: 02b
    type: summary
    status: complete
    date: 2026-05-NN
    commits:
      - "<sha> — docs(06d-02b): synthesis of 3 AI passes — consolidated FINDINGS"
    ---

    # Plan 06D-02b — Wave 2.2 SUMMARY

    ## Status
    Synthesis complete. 06D-FINDINGS.md filled. Next: Wave 06D-02c (pre-fix Instruments baseline + CHECKPOINT 1 prep).

    ## Findings totals (post-filter)

    | Severity | Count |
    |---|---|
    | HIGH | NN |
    | MEDIUM | NN |
    | LOW | NN |
    | **Total** | NN |

    ## Filter breakdown

    | Filter | Count moved out |
    |---|---|
    | Rejected by D-09 (invariant violations) | NN |
    | Filtered as out-of-scope (D-02a) | NN |
    | Filtered as abstract-beauty | NN |
    | Merged as false-uniqueness | NN |

    ## Coverage matrix

    | AI | Performance | Energy | Simplicity | Memory | Launch | Total |
    |---|---|---|---|---|---|---|
    | Opus | … | … | … | … | … | NN |
    | Codex | … | … | … | … | … | NN |
    | Gemini | … | … | … | … | … | NN / N/A |

    ## Consensus distribution

    | Marker | Count |
    |---|---|
    | 3/3 strong | NN |
    | 2/3 moderate | NN |
    | 1/3 unique-but-valuable | NN |

    ## Anti-bias check (RESEARCH Open Q #5)

    [Список Opus's own findings, rejected in favor of Codex/Gemini consensus. Каждая запись — finding ID + rationale.]

    ## Next
    Wave 06D-02c — pre-fix Instruments baseline + 06D-FINDINGS-SUMMARY.md + CHECKPOINT 1 prep.
    ```

    **Atomic commit:** `docs(06d-02b): wave 02b closure summary`.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md \
        && grep -q "Plan 06D-02b" .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md \
        && grep -qE "Findings totals|Filter breakdown" .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md \
        && grep -q "Coverage matrix" .planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
    </automated>
  </verify>
  <done>
    06D-02b-SUMMARY.md содержит actual numbers (counts, distribution, anti-bias check), готов как input для Wave 06D-02c.
  </done>
</task>

</tasks>

<verification>

**Wave-level acceptance:**

1. **Synthesis complete:**
   - `06D-FINDINGS.md` имеет consolidated table с consensus markers (3/3 / 2/3 / 1/3).
   - Rejected-by-invariant section не пуста (если были violations) либо явный «0 violations detected».
   - Filtered-out-of-scope section не пуста (если были) либо явный «0 filtered».
   - Coverage matrix заполнена реальными counts.
2. **D-09 защищён:** все findings, нарушающие invariants — в Rejected section с rationale.
3. **Anti-bias rule applied:** документировано в SUMMARY (Opus's own findings vs others).
4. **Regression gate** (D-08) — этот wave НЕ изменяет production code, regression gate необязателен; но допустим smoke test чтобы убедиться что main всё ещё green.

</verification>

<success_criteria>

- [ ] 06D-FINDINGS.md содержит 6 секций (executive, consolidated, rejected, filtered, coverage matrix, notes-for-checkpoint).
- [ ] Consensus markers (3/3 / 2/3 / 1/3) применены к каждому row.
- [ ] Dedup pass устранил false-uniqueness.
- [ ] D-09 invariant violations — в Rejected section.
- [ ] 06D-02b-SUMMARY.md имеет actual counts + anti-bias check + reference на Wave 06D-02c.

</success_criteria>

<output>
После завершения создан `06D-02b-SUMMARY.md`. Next: Wave 06D-02c.
</output>
</content>
</invoke>