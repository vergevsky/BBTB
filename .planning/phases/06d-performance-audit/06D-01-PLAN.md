---
phase: 06d-performance-audit
plan: 01
type: execute
wave: 1
mode: mvp
depends_on: []
files_modified:
  - .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md
  - .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
  - .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md
  - .planning/phases/06d-performance-audit/06D-FINDINGS.md
  - .planning/phases/06d-performance-audit/06D-01-SUMMARY.md
autonomous: true
requirements: [QUAL-03]
tags: [audit, multi-ai-review, performance, energy, simplicity, memory, launch-time]

must_haves:
  truths:
    - "Три независимых audit-pass-а Opus / Codex / Gemini завершены и сохранены каждый в отдельном файле."
    - "Identical 7-section English brief доставлен во все три pass-а."
    - "Gemini fallback chain отработала (или зафиксирован «skipped — API unavailable»)."
    - "06D-FINDINGS.md skeleton создан с полной таблицей колонок (Opus/Codex/Gemini/Consensus) — наполнение происходит в Wave 06D-02."
    - "Ни один pass не предложил откатить инвариант D-09 (intent-closing / no-XPC observer / no-RSM / single-authority applyVPNStatus / sliding window)."
    - "Каждый из 3 audit-pass-ов покрыл все 5 dimensions per coverage matrix (perf/responsiveness + energy + simplicity/dead-code + memory + launch)."
    - "Cold-start path и connect-tap path (D-01 primary targets) адресованы как минимум одним HIGH или MEDIUM finding в каждом из 3 audit-pass-ов (если pass-ы не находят ни одного finding для D-01 target — это означает либо что код чистый по этому target-у, либо что brief не дотащил target до AI; orchestrator должен явно пометить такой исход в синтезе)."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md"
      provides: "Opus 4.7 audit pass output — executive summary + findings table + methodology"
      contains: "# Phase 6d Audit — OPUS Pass"
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md"
      provides: "Codex GPT-5.2 audit pass output — executive summary + findings table + methodology"
      contains: "# Phase 6d Audit — CODEX Pass"
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md"
      provides: "Gemini 3.1 Pro audit pass output — executive summary + findings table + methodology"
      contains: "# Phase 6d Audit — GEMINI Pass"
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS.md"
      provides: "Synthesis skeleton — пустая table с финальными колонками, заполняется в 06D-02"
      contains: "Opus | Codex | Gemini | Consensus"
    - path: ".planning/phases/06d-performance-audit/06D-01-SUMMARY.md"
      provides: "Wave 06D-01 closure record — actual durations, fallback events, finding counts per pass"
  key_links:
    - from: "06D-01 Task 1 (Opus pass)"
      to: "06D-FINDINGS-OPUS.md"
      via: "Internal context read + markdown write"
      pattern: "OPUS Pass.*Executive summary"
    - from: "06D-01 Task 2 (Codex pass)"
      to: "06D-FINDINGS-CODEX.md"
      via: "mcp__codex__codex sandbox=read-only"
      pattern: "CODEX Pass.*Findings table"
    - from: "06D-01 Task 3 (Gemini pass)"
      to: "06D-FINDINGS-GEMINI.md"
      via: "mcp__gemini__gemini sandbox=read-only + fallback chain"
      pattern: "GEMINI Pass.*Findings table"
---

# Phase 6d Wave 1 — Audit briefing + 3 параллельных AI passes

## Цель волны (по-русски)

Phase 6d — это **multi-AI peer review** (взаимное ревью несколькими ИИ) кодовой базы BBTB по пяти измерениям (производительность, энергопотребление, простота / удаление dead code, память, время холодного старта). Wave 06D-01 запускает **три независимых параллельных аудита** с **identical** (идентичным) 7-section English брифом:

- **Opus 4.7** — внутри текущего треда (через Read / Bash / Grep).
- **Codex GPT-5.2** — через MCP-сервер `mcp__codex__codex` в режиме `sandbox: read-only`.
- **Gemini 3.1 Pro** — через MCP-сервер `mcp__gemini__gemini` в режиме `sandbox: read-only`, с **fallback chain** (D-03 + memory `feedback_gemini_fallback_chain.md`): `gemini-3.1-pro-preview` → `deep-research-preview-04-2026` → `gemini-3-pro-preview` → `gemini-3-flash-preview` → `gemini-2.5-pro`.

Все три pass-а пишут результаты в отдельные файлы. Synthesis (объединение) и фильтрация — следующая волна (06D-02).

**Источник правды по содержанию брифа:** `06D-RESEARCH.md` секция `## Multi-AI Audit Brief Template (Wave 06D-01)` строки 520-623 — *планировщик копирует skeleton verbatim в Task 1/2/3 ниже*.

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
@.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md
@.planning/phases/06c-on-demand-migration/06C-UAT.md
@CLAUDE.md
@~/.claude/rules/delegator.md
@wiki/auto-reconnect.md
</context>

<brief_skeleton>
## Verbatim 7-section English brief skeleton (D-03 identical для всех 3 passes)

> Task 0 копирует этот блок в `06D-01-PREFLIGHT.md` секцию `## Frozen brief skeleton`. Task 1 / 2 / 3 цитируют этот же текст как `prompt` для своего pass-а (с одной substitution в EXPECTED OUTCOME filename + OUTPUT header). Никаких per-AI вариаций (D-03).

```text
1. TASK: Independent multi-AI peer-review audit of the BBTB iOS+macOS Swift codebase
   on five dimensions (performance, energy, simplicity, memory, launch) with a primary
   focus on two user-reported pain paths: cold start (icon tap → interactive MainScreen)
   and connect tap (power-button tap → .connected + ticking timer).

2. EXPECTED OUTCOME: A markdown table of findings using the exact column set:
   `# | Title | Dimension | Severity | File:Line | Description | Recommended fix`
   Saved to: `.planning/phases/06d-performance-audit/06D-FINDINGS-{OPUS|CODEX|GEMINI}.md`.
   Severity rubric (D-05a):
     HIGH = measurable user pain (>200ms perceived lag on cold start or connect tap),
            security/correctness concern, or active bug;
     MEDIUM = measurable sub-perception impact (50-200ms), maintenance debt with concrete
              cost, or energy regression on typical session;
     LOW = cosmetic / future-friction (<50ms), simplification without measurable impact.
   Maximum 40 findings per pass; quality over quantity.

3. CONTEXT:
   - Current state: BBTB is a VPN client targeting iOS 18+ and macOS 15+. Tech stack:
     SwiftUI + Swift Concurrency + SwiftData + NetworkExtension + sing-box via
     libbox.xcframework + Tuist-managed Xcode project.
   - Relevant code paths (read these in full before producing findings):
     * App entry: `BBTB/App/iOSApp/BBTB_iOSApp.swift` (156 LOC)
     * App entry: `BBTB/App/macOSApp/BBTB_macOSApp.swift` (149 LOC)
     * Hot-path package: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/`
       (TunnelController.swift 316 LOC, MainScreenViewModel.swift 593 LOC,
        ConfigImporter.swift 1071 LOC, TunnelWatchdog.swift 267 LOC,
        OnDemandRulesBuilder.swift 180 LOC, plus ~12 smaller files)
     * Tunnel: `BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
     * sing-box build: `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/`
     * Parsers: `BBTB/Packages/ConfigParser/Sources/`
     * Protocol registry: `BBTB/Packages/ProtocolRegistry/Sources/`
     * Transport registry: `BBTB/Packages/TransportRegistry/Sources/`
     * Protocol packages: `BBTB/Packages/Protocols/{VLESSReality,VLESSTLS,
       Shadowsocks,Hysteria2,Trojan}/Sources/`
     * VPNCore types: `BBTB/Packages/VPNCore/Sources/`
   - Background: Phase 6c just landed a major refactor that took TunnelController
     from 909 → 316 LOC and deleted 5 files (ReconnectStateMachine, NetworkReachability,
     and their tests). Phase 6c invariants MUST be preserved (see CONSTRAINTS).
     The user reports the app "feels heavy" since Phase 5. Audit must localize the
     cause through specific findings.

4. CONSTRAINTS:
   - Technical: Swift 6 mode, Xcode 16+, iOS 18+, macOS 15+, no new third-party
     dependencies unless a finding has explicit user-impact justification.
   - Patterns: Apple-blessed concurrency (actors, structured Task), SwiftUI native,
     SwiftData (no Core Data fallback), NEOnDemandRule for reconnect (no custom
     state machines).
   - Limitations (Phase 6c invariants — NEVER recommend rolling back):
     * `TunnelController.handleStatusChange` intent-closing path UNCHANGED.
     * No XPC inside `NEVPNStatusDidChange` observer hot path.
     * No reintroduction of ReconnectStateMachine / NetworkReachability / custom
       retry loops.
     * `applyVPNStatus(_:connectedDate:)` remains SINGLE authority for
       MainScreenViewModel.state + reconnectBannerState.
     * Sliding session window invariant:
       `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.
     * Observer registration on `queue: nil` (NEVER `.main` — Phase 6c Round 6).
     * Никаких `#Predicate` с optional UUID (memory feedback).
   - Out of scope (do NOT propose):
     * Rewriting libbox.xcframework or sing-box internals.
     * Replacing the backend (Rust sing-box, alternative engines).
     * Migrating off SwiftPM (Bazel, etc.).
     * UI redesigns (Phase 11 territory).
     * Adding new dependencies as a general refactor — only with explicit
       user-impact justification.

5. MUST DO:
   - Read every file under the paths listed in CONTEXT before emitting findings.
   - Trace every finding to one of: cold start path, connect tap path, or indirect
     improvement that helps one of those (binary size reduction, hot-path complexity
     reduction, etc.).
   - For each finding, cite exact File:Line in the codebase. "Unknown" or "various"
     is not acceptable.
   - Mark severity per the D-05a rubric and justify it briefly.
   - For each finding, propose a concrete fix with files to change. "Refactor X"
     is not acceptable — say "extract method Y from file Z lines A-B into helper W".

6. MUST NOT DO:
   - Do not propose any change that violates a Phase 6c invariant (CONSTRAINTS).
   - Do not propose adding new dependencies unless explicit user-impact justification
     is given.
   - Do not propose UI redesigns or new features.
   - Do not emit abstract-beauty findings ("this could be more functional") without
     measurable user impact or maintenance cost reduction.
   - Do not propose libbox / sing-box / gomobile-binding rewrites.
   - Do not exceed 40 findings per pass — quality over quantity.

7. OUTPUT FORMAT: Markdown file at the path specified in EXPECTED OUTCOME.
   First line of body: `# Phase 6d Audit — {OPUS|CODEX|GEMINI} Pass`.
   Section 1: Executive summary (3-5 bullets — top patterns observed).
   Section 2: Findings table (column set above).
   Section 3: Methodology — what you read, what you skipped, why.
   Closing: estimated pass duration + your confidence level (HIGH/MEDIUM/LOW)
   per dimension.
```

---
</brief_skeleton>


<tasks>

<task type="auto">
  <name>Task 0 — Pre-flight check: MCP availability, codebase grep, brief skeleton frozen</name>
  <files>
    .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-CONTEXT.md (D-03 fallback chain, D-09 invariants)
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секция «Environment Availability» строки ~1316-1335; секция «Multi-AI Audit Brief Template» строки ~520-623)
    - ~/.claude/rules/delegator.md (7-section format + sandbox semantics)
    - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_gemini_fallback_chain.md
  </read_first>
  <action>
    Выполнить три проверки и зафиксировать результаты в `06D-01-PREFLIGHT.md`:

    1. **MCP availability:** убедиться что инструменты `mcp__codex__codex` и `mcp__gemini__gemini` доступны в текущей сессии. Если оба недоступны — STOP, escalate user (Phase 6d требует все три pass-а; работа с двумя возможна только если Gemini fallback chain полностью упадёт по D-03 — это разрешено только в Task 3, не на pre-flight).

    2. **Codebase signpost grep** (verifies ASSUMED A7 из RESEARCH):
       `grep -rn "OSSignposter\|os_signpost\|signposter" BBTB --include="*.swift"` — записать сколько matches и где. Researcher предположил, что matches = 0; Task 0 верифицирует. Результат влияет на Wave 06D-02 Task 0 (signpost injection).

    3. **Brief skeleton freeze:** скопировать verbatim 7-section brief из `06D-RESEARCH.md` строки ~528-623 в файл `06D-01-PREFLIGHT.md` секцию `## Frozen brief skeleton`. Этот текст — **источник правды** для Task 1/2/3. Никаких per-AI вариаций (D-03: identical brief).

    Замечание: pre-flight НЕ требует никаких изменений в production-коде. Файлы создаются только в `.planning/phases/06d-performance-audit/`.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md \
        && grep -c "TASK: Independent multi-AI peer-review" .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md \
        | awk '$1 >= 1 { exit 0 } { exit 1 }' \
        && grep -c "OPUS\|CODEX\|GEMINI" .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md \
        | awk '$1 >= 3 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <done>
    06D-01-PREFLIGHT.md существует, содержит копию 7-section brief skeleton verbatim из RESEARCH, фиксирует MCP availability + signpost grep count.
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 1 — Opus 4.7 audit pass (internal context)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md (frozen brief skeleton)
    - .planning/phases/06d-performance-audit/06D-CONTEXT.md (D-01..D-11b)
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (Architectural Responsibility Map; Standard Stack; Common Pitfalls 1-8)
    - BBTB/App/iOSApp/BBTB_iOSApp.swift (156 LOC — cold-start entry)
    - BBTB/App/macOSApp/BBTB_macOSApp.swift (149 LOC — macOS cold-start)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (316 LOC — post-6c slim)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift (593 LOC)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift (1071 LOC — крупнейший файл)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift (267 LOC)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift (180 LOC)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift (117 LOC)
    - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ (PoolBuilder + templates)
    - BBTB/Packages/ConfigParser/Sources/ (URI / YAML parsers)
    - BBTB/Packages/ProtocolRegistry/Sources/
    - BBTB/Packages/TransportRegistry/Sources/
    - BBTB/Packages/Protocols/{VLESSReality,VLESSTLS,Trojan,Shadowsocks,Hysteria2}/Sources/
    - BBTB/Packages/VPNCore/Sources/
    - 5 memory files в D-09 invariants list:
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_observer_queue_main.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_connectedDate_authority_for_since.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_xpc_mach_port.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_swiftdata_uuid_predicate.md
      - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_failover_two_phase_init.md
  </read_first>
  <action>
    Выполнить Opus pass — independent peer-review audit по 7-section брифу (frozen в Task 0). Этот pass идёт через текущий thread, без MCP-делегации.

    **Шаги:**

    1. Открыть `06D-01-PREFLIGHT.md` секцию `## Frozen brief skeleton` — это TASK / EXPECTED OUTCOME / CONTEXT / CONSTRAINTS / MUST DO / MUST NOT DO / OUTPUT FORMAT для текущего pass-а.

    2. Прочитать **в полном объёме** все файлы из `<read_first>` выше. Это hot-path codebase (cold-start path + connect-tap path per D-01) + supporting packages + Phase 6c invariant context.

    3. Для каждой потенциальной находки определить:
       - **Dimension** — Performance / Energy / Simplicity / Memory / Launch.
       - **Severity** по D-05a rubric (HIGH = >200ms perceived lag / security / bug; MEDIUM = 50-200ms / maintenance debt / energy regression; LOW = <50ms / cosmetic).
       - **Exact File:Line** — никаких «various» или «unknown».
       - **Concrete fix** — "extract method Y from file Z lines A-B into helper W", не "refactor X".

    4. Применить self-filter перед записью:
       - Drop любой finding, нарушающий D-09 (Phase 6c invariants — verbatim в Constraint секции брифа).
       - Drop out-of-scope D-02a (libbox/sing-box rewrite, SwiftPM migration, новые dependencies без user-impact justification).
       - Drop abstract beauty без measurable impact.

    5. Максимум **40 findings** (quality over quantity per RESEARCH severity rubric line 545).

    6. Записать output в `06D-FINDINGS-OPUS.md` строго по структуре OUTPUT FORMAT (Role C в PATTERNS.md):
       ```
       # Phase 6d Audit — OPUS Pass

       ## 1. Executive summary
       (3-5 bullets с top patterns)

       ## 2. Findings table
       | # | Title | Dimension | Severity | File:Line | Description | Recommended fix |

       ## 3. Methodology
       (What I read / What I skipped / Tools used)

       ## Confidence per dimension
       Performance / Energy / Simplicity / Memory / Launch — HIGH/MEDIUM/LOW.
       Estimated pass duration: NN min.
       ```

    7. **Anti-bias note** (per RESEARCH Open Question #5): помнить, что Opus делает synthesis в Wave 06D-02. Не «придерживать» findings, чтобы они потом «выиграли» consensus. Pass честный и максимально полный сейчас.

    Язык findings table: Description + Recommended fix допустимы на английском (точнее терминология для модели); narrative секции (Executive summary, Methodology) — допустимы на английском (внутренний AI-output артефакт). Синтез в 06D-02 переведёт key items на русский для user-facing FINDINGS.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md \
        && test $(wc -c < .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md) -gt 2000 \
        && grep -q "# Phase 6d Audit — OPUS Pass" .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md \
        && grep -q "Findings table" .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md \
        && grep -E "HIGH|MEDIUM|LOW" .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md | head -1 \
        && grep -v '^#' .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay" | awk '$1 == 0 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <done>
    06D-FINDINGS-OPUS.md существует, > 2KB, имеет заголовок «# Phase 6d Audit — OPUS Pass», содержит findings table с severity rating, **не содержит** упоминаний Phase 6c invariant rollback (forbidden symbols grep = 0 после awk-strip).
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2 — Codex GPT-5.2 audit pass (single-shot via MCP, sandbox=read-only)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md (frozen brief skeleton — `## Frozen brief skeleton` секция)
    - ~/.claude/rules/delegator.md (7-section format invocation pattern, sandbox semantics, notify-user step 4)
    - .planning/phases/06c-on-demand-migration/06C-REVIEWS-R2-CODEX.md (пример предыдущего Codex audit output — shape reference)
    - .planning/phases/06c-on-demand-migration/06C-ARCHITECT-R5.md (пример Codex architect output — shape reference)
  </read_first>
  <action>
    Делегировать audit pass к Codex GPT-5.2 через MCP `mcp__codex__codex`. **Identical brief** с Task 1 (D-03).

    **Шаги:**

    1. **Notify user** перед вызовом (delegator.md step 4):
       `Delegating to Code Reviewer (Codex GPT-5.2): Phase 6d multi-AI audit — independent peer review pass over BBTB codebase.`

    2. **Read expert prompt — 4-level fallback discovery** (per checker WARNING fix, delegator.md spec):
       Discovery order (используйте первый найденный):
       1. `${CLAUDE_PLUGIN_ROOT}/prompts/code-reviewer.md` — current delegator standard (primary).
       2. `~/.claude/plugins/cache/*/prompts/code-reviewer.md` — legacy cache path (glob match, expanded by shell).
       3. `~/.claude/get-shit-done/references/code-reviewer*.md` — project-skill location.
       4. Если **ALL absent** → PREFLIGHT (`06D-01-PREFLIGHT.md`) records 'code-reviewer prompt missing' и **ESCALATE to user** (block, do **NOT** proceed with weak one-liner). One-liner fallback **удалён** — Phase 6d требует proper expert prompt для honest peer-review.

       Discovery commands (для записи в PREFLIGHT):
       ```bash
       # Level 1 (primary)
       test -n "$CLAUDE_PLUGIN_ROOT" && test -f "$CLAUDE_PLUGIN_ROOT/prompts/code-reviewer.md" \
         && echo "Found at level 1: $CLAUDE_PLUGIN_ROOT/prompts/code-reviewer.md"

       # Level 2 (legacy cache)
       ls ~/.claude/plugins/cache/*/prompts/code-reviewer.md 2>/dev/null \
         | head -1 | xargs -I{} echo "Found at level 2: {}"

       # Level 3 (project-skill)
       ls ~/.claude/get-shit-done/references/code-reviewer*.md 2>/dev/null \
         | head -1 | xargs -I{} echo "Found at level 3: {}"
       ```

       Если ни один level не дал hit → STOP, document в PREFLIGHT, ESCALATE user.

    3. **Invoke** `mcp__codex__codex` с параметрами:
       - `developer-instructions`: contents of code-reviewer.md из found path (Level 1-3). Если **не найдено ни на одном уровне** — DO NOT invoke; instead STOP + escalate (см. step 2 fallback Level 4).
       - `sandbox`: `"read-only"` (advisory mode, никаких изменений source).
       - `cwd`: `/Users/vergevsky/ClaudeProjects/VPN`.
       - `prompt`: copy verbatim секция `## Frozen brief skeleton` из `06D-01-PREFLIGHT.md`. Один substitution: в строке `Saved to: .planning/phases/06d-performance-audit/06D-FINDINGS-{OPUS|CODEX|GEMINI}.md` заменить плейсхолдер на `06D-FINDINGS-CODEX.md`. В первой строке OUTPUT — `# Phase 6d Audit — CODEX Pass`. Никаких других модификаций брифа.

    4. **Retry policy** (delegator.md):
       - Если call возвращает error → retry через `mcp__codex__codex-reply` с тем же `threadId` + добавить error history.
       - Max 3 attempts. После 3 — escalate user.

    5. **Output capture:** Codex MCP вернёт `{ threadId, content }`. Sandbox=read-only означает Codex **не** может писать файлы сам — синтаксически сохранить `content` в `06D-FINDINGS-CODEX.md` через Write tool после получения response. Header первой строкой: `# Phase 6d Audit — CODEX Pass`. Если Codex вернул output БЕЗ заголовка — добавить его и весь content ниже.

    6. **Validation после write:**
       - `wc -c 06D-FINDINGS-CODEX.md` > 2000 байт.
       - `grep -q "CODEX Pass" 06D-FINDINGS-CODEX.md`.
       - `grep -q "Findings table\|Title.*Dimension.*Severity"` (хотя бы один из двух markers — table exists).
       - **D-09 invariant filter:** `grep -v '^#' 06D-FINDINGS-CODEX.md | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay"` должен быть **0**. Если ненулевой — Codex предложил rollback Phase 6c → задокументировать в `06D-FINDINGS-CODEX.md` секцию `## INVARIANT VIOLATIONS DETECTED (will be filtered in Wave 02)` + продолжить. **Не блокирует Wave 01** — synthesis отфильтрует.

    7. Не «фиксить» Codex output: если pass нашёл мало findings или не такие, как ожидалось — записать as-is. Это independent pass; bias от Opus pass-а исключён (Codex не видит Opus output).

    **NB:** Если `mcp__codex__codex` недоступен → escalate user (нельзя продолжать Wave 06D-01 без Codex pass). Это не Gemini-style fallback — Codex не имеет MCP-альтернатив.

    **Тайминг (per RESEARCH Open Question #4):** ожидать 1-5 мин на single-shot pass.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md \
        && test $(wc -c < .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md) -gt 2000 \
        && grep -q "CODEX Pass" .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md \
        && grep -qE "Findings table|Severity" .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
    </automated>
  </verify>
  <done>
    06D-FINDINGS-CODEX.md существует, > 2KB, имеет заголовок «CODEX Pass», содержит findings table со severity, D-09 violations (если найдены) задокументированы в отдельной секции для отфильтровывания в Wave 02. Threat actor для invariant violations — synthesis (не текущая task).
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3 — Gemini 3.1 Pro audit pass (single-shot via MCP + fallback chain)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-01-PREFLIGHT.md (frozen brief skeleton)
    - ~/.claude/rules/delegator.md
    - ~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_gemini_fallback_chain.md (D-03 chain: gemini-3.1-pro-preview → deep-research-preview-04-2026 → gemini-3-pro-preview → gemini-3-flash-preview → gemini-2.5-pro)
    - .planning/phases/06c-on-demand-migration/06C-REVIEWS-R3-GEMINI.md (пример предыдущего Gemini audit output — shape reference)
  </read_first>
  <action>
    Делегировать audit pass к Gemini 3.1 Pro через MCP `mcp__gemini__gemini`. **Identical brief** с Task 1 / Task 2.

    **Шаги:**

    1. **Notify user:** `Delegating to Code Reviewer (Gemini 3.1 Pro): Phase 6d multi-AI audit — independent peer review pass over BBTB codebase.`

    2. **Read expert prompt** (same path as Task 2 — Code Reviewer prompt).

    3. **Invoke** `mcp__gemini__gemini` с параметрами:
       - `developer-instructions`: same as Task 2.
       - `sandbox`: `"read-only"`.
       - `cwd`: `/Users/vergevsky/ClaudeProjects/VPN`.
       - `model`: **primary** `gemini-3.1-pro-preview`. **Fallback chain** (D-03 + memory):
         1. `gemini-3.1-pro-preview` (primary)
         2. `deep-research-preview-04-2026`
         3. `gemini-3-pro-preview`
         4. `gemini-3-flash-preview`
         5. `gemini-2.5-pro`
       - `prompt`: copy verbatim `## Frozen brief skeleton` из PREFLIGHT с substitution: filename → `06D-FINDINGS-GEMINI.md`, OUTPUT header → `# Phase 6d Audit — GEMINI Pass`.

    4. **Fallback logic:**
       - Если call возвращает 503 / API error на **любом** model — switch на следующий в chain, retry с тем же prompt.
       - Если все 5 fallback моделей упали → **пауза 5-10 мин** (физический wait, не loop) → повторить с primary.
       - Если снова все 5 упали → задокументировать failure в `06D-FINDINGS-GEMINI.md` content:
         ```
         # Phase 6d Audit — GEMINI Pass

         ## Status: SKIPPED — Gemini API unavailable

         **Date**: 2026-05-NN
         **Attempted models**: <list>
         **Last error**: <verbatim>
         **Decision**: Continuing Phase 6d с 2-pass synthesis (Opus + Codex) per D-03.
         ```
       - **Не блокировать Wave 01** на Gemini outage — phase продолжается с двумя passes; synthesis в 06D-02 учитывает.

    5. **Output capture:** same как Task 2 — `content` → Write tool → `06D-FINDINGS-GEMINI.md`. Header `# Phase 6d Audit — GEMINI Pass` первой строкой.

    6. **Validation после write** (если pass успешен, не skipped):
       - File > 2KB.
       - `grep -q "GEMINI Pass"`.
       - `grep -qE "Findings table|Severity"`.
       - D-09 invariant grep (same как Task 2).

    7. **Validation если skipped:**
       - File содержит "SKIPPED" в Status секции.
       - `wc -c` > 200 (минимальная skip-record).

    **Тайминг:** primary attempt 1-2 мин; полный fallback chain до 10 мин; full skip path (после паузы) до 25 мин. Pre-allocate budget.

    **Записать в `06D-01-SUMMARY.md` (Task 4)** реальную fallback-историю: какие модели пробовали, какие упали, какая в итоге сработала или skip.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md \
        && ( ( test $(wc -c < .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md) -gt 2000 \
                && grep -q "GEMINI Pass" .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md ) \
              || grep -q "SKIPPED" .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md )
    </automated>
  </verify>
  <done>
    06D-FINDINGS-GEMINI.md существует. Либо (a) > 2KB с заголовком «GEMINI Pass» и findings table, либо (b) skip-record с причиной (все 5 fallback моделей упали + пауза + повтор). В обоих случаях Wave 02 synthesis может proceed.
  </done>
</task>

<task type="auto">
  <name>Task 4 — 06D-FINDINGS.md skeleton + 06D-01-SUMMARY.md closure</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS.md
    .planning/phases/06d-performance-audit/06D-01-SUMMARY.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-FINDINGS-OPUS.md (готов после Task 1)
    - .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md (готов после Task 2)
    - .planning/phases/06d-performance-audit/06D-FINDINGS-GEMINI.md (готов после Task 3, либо skip-record)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role D — synthesis format, Shared 5 — fallback record)
    - .planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md (shape reference — Role M)
  </read_first>
  <action>
    Создать два файла:

    **1. `06D-FINDINGS.md` skeleton** — пустая структура для наполнения в Wave 06D-02. Содержит:

    ```markdown
    # Phase 6d — Multi-AI Audit Findings (synthesis)

    **Status**: SKELETON — заполняется в Wave 06D-02 Task 1 (synthesis).
    **Date**: 2026-05-NN (Wave 06D-01 closure)
    **Sources**: 06D-FINDINGS-OPUS.md + 06D-FINDINGS-CODEX.md + 06D-FINDINGS-GEMINI.md
    **Synthesizer**: Opus 4.7 (anti-bias rule: when own finding conflicts with another AI, other wins by default per RESEARCH Open Question #5)

    ## 1. Executive synthesis
    [TBD Wave 02 Task 1]

    ## 2. Consolidated findings
    | # | Title | Dimension | Severity | File:Line | Description | Opus | Codex | Gemini | Consensus | Recommended fix |
    |---|---|---|---|---|---|---|---|---|---|---|

    ## 3. Rejected findings (Phase 6c invariant violations — D-09)
    | # | Finding | Source AI | Invariant violated | Why dropped |
    |---|---|---|---|---|

    ## 4. Filtered findings (out-of-scope D-02a, abstract beauty, false uniqueness)
    | # | Finding | Source AI | Reason |
    |---|---|---|---|

    ## 5. Coverage matrix (per-AI per-dimension)
    | AI | Performance | Energy | Simplicity | Memory | Launch |
    |---|---|---|---|---|---|
    | Opus | TBD | TBD | TBD | TBD | TBD |
    | Codex | TBD | TBD | TBD | TBD | TBD |
    | Gemini | TBD | TBD | TBD | TBD | TBD |

    ## 6. Notes for CHECKPOINT 1
    [TBD Wave 02 Task 3 — counts by severity, top-5 critical, recommended budget options.]
    ```

    **2. `06D-01-SUMMARY.md` closure record** — actual durations, MCP behavior, finding counts:

    Структура (per Role M shape из PATTERNS):
    ```markdown
    ---
    phase: 06d-performance-audit
    plan: 01
    type: summary
    status: complete
    date: 2026-05-NN
    ---

    # Plan 06D-01 — Wave 1 SUMMARY

    ## Status
    Three independent audit passes (Opus, Codex, Gemini) completed. Synthesis в 06D-02.

    ## Pass results
    | Pass | Source | Duration | Findings count | Severity breakdown | Status |
    |---|---|---|---|---|---|
    | Opus 4.7 | internal thread | NN min | NN total | H/M/L = X/Y/Z | ✅ Complete |
    | Codex GPT-5.2 | mcp__codex__codex | NN min | NN total | H/M/L = X/Y/Z | ✅ Complete |
    | Gemini 3.1 Pro | mcp__gemini__gemini | NN min | NN total | H/M/L = X/Y/Z | ✅ Complete / ⚠ Skipped |

    ## Gemini fallback history
    [Какие модели пробовали, какие упали, какая в итоге сработала. Если skipped — вся последовательность retries + пауза.]

    ## Invariant violations detected (preview for Wave 02 filter)
    [Counts per pass для finding-ов, нарушающих D-09. Точная фильтрация в Wave 02.]

    ## Verification metrics
    | Check | Required | Actual | Status |
    |---|---|---|---|
    | 06D-FINDINGS-OPUS.md exists + > 2KB + has table | yes | ... | ✅ |
    | 06D-FINDINGS-CODEX.md exists + > 2KB + has table | yes | ... | ✅ |
    | 06D-FINDINGS-GEMINI.md exists (>2KB OR skipped) | yes | ... | ✅ |
    | 06D-FINDINGS.md skeleton exists | yes | ... | ✅ |

    ## Decisions
    - Если Gemini skipped: documented + Wave 02 synthesis уведомлена.
    - Если invariant violations detected in any pass: документ только; filtering — Wave 02 Task 1.

    ## Next
    Wave 06D-02 — synthesis + Instruments pre-fix baseline.
    ```

    Зафиксировать **actual numbers**, не плейсхолдеры — Wave 06D-01 финализирован только когда summary написан с реальными данными.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Consolidated findings" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Opus | Codex | Gemini | Consensus" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && grep -q "Rejected findings.*invariant" .planning/phases/06d-performance-audit/06D-FINDINGS.md \
        && test -f .planning/phases/06d-performance-audit/06D-01-SUMMARY.md \
        && grep -q "Plan 06D-01 — Wave 1 SUMMARY" .planning/phases/06d-performance-audit/06D-01-SUMMARY.md \
        && grep -q "Pass results" .planning/phases/06d-performance-audit/06D-01-SUMMARY.md
    </automated>
  </verify>
  <done>
    06D-FINDINGS.md skeleton содержит все 6 секций с правильными table headers (включая Opus/Codex/Gemini/Consensus колонки), готов к наполнению в Wave 02. 06D-01-SUMMARY.md имеет реальные данные по трём pass-ам (counts, durations, fallback history, invariant violation preview).
  </done>
</task>

</tasks>

<verification>

**Wave-level acceptance (после всех 4 tasks):**

1. `ls -la .planning/phases/06d-performance-audit/06D-FINDINGS-*.md` показывает **три** AI-pass файла + один synthesis skeleton (4 файла итого, NOT counting PREFLIGHT/SUMMARY).
2. Каждый AI-pass файл (или skip-record) валиден per Task 1/2/3 acceptance.
3. **Forbidden symbol audit** на всех трёх AI outputs (Phase 6c invariant guard):
   ```bash
   for f in .planning/phases/06d-performance-audit/06D-FINDINGS-{OPUS,CODEX,GEMINI}.md; do
     test -f "$f" || continue
     grep -v '^#' "$f" | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay" \
       | awk -v f="$f" '$1 > 0 { print "WARN: invariant violation candidate in " f ": " $1 }'
   done
   ```
   Нулевое количество предпочтительно; ненулевое — задокументировано в файле для filter в Wave 02 (НЕ блокирует Wave 01).
4. `06D-01-SUMMARY.md` зафиксировал actual pass durations + fallback history (если был).
5. Regression gate (D-08) **не запускается** в Wave 06D-01 — это audit-only wave, никаких изменений production-кода. swift test + xcodebuild — отложены до первой fix-wave (06D-03+).

</verification>

<success_criteria>

- [ ] 06D-01-PREFLIGHT.md содержит frozen brief skeleton (verbatim из RESEARCH).
- [ ] 06D-FINDINGS-OPUS.md > 2KB, header «OPUS Pass», findings table, 0 forbidden symbols (or documented).
- [ ] 06D-FINDINGS-CODEX.md > 2KB, header «CODEX Pass», findings table, 0 forbidden symbols (or documented).
- [ ] 06D-FINDINGS-GEMINI.md либо > 2KB + header «GEMINI Pass» + table, либо skip-record с reason.
- [ ] 06D-FINDINGS.md skeleton с 6 секциями (включая Opus/Codex/Gemini/Consensus columns).
- [ ] 06D-01-SUMMARY.md фиксирует actual data (durations, counts, fallback history).
- [ ] Никаких изменений в production-коде BBTB (audit-only wave).

</success_criteria>

<output>
После завершения создать `.planning/phases/06d-performance-audit/06D-01-SUMMARY.md` (это уже сделано в Task 4). Зафиксировать `git add` + `git commit` с сообщением:
```
docs(06d-01): three AI audit passes (Opus + Codex + Gemini) + synthesis skeleton

- 06D-FINDINGS-OPUS.md (internal pass, NN findings)
- 06D-FINDINGS-CODEX.md (mcp__codex__codex, NN findings)
- 06D-FINDINGS-GEMINI.md (mcp__gemini__gemini + fallback, NN findings / skipped)
- 06D-FINDINGS.md (synthesis skeleton — populated in Wave 02)
- 06D-01-PREFLIGHT.md + 06D-01-SUMMARY.md
```
</output>
</content>
</invoke>