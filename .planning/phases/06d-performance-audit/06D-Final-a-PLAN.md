---
phase: 06d-performance-audit
plan: Final-a
slice: a
type: execute
wave: Final.1
mode: mvp
depends_on: [03]
files_modified:
  - .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-post-fix.md
  - .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-post-fix.md
  - .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-post-fix.md
  - .planning/phases/06d-performance-audit/baselines/energy-iphone-post-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-post-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-post-fix.md
  - .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt
  - .planning/phases/06d-performance-audit/06D-COMPARISON.md
  - .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md
autonomous: true
requirements: [PERF-01, PERF-02, PERF-03, PERF-04]
tags: [post-fix-instruments, periphery-re-scan, comparison, pre-vs-post-deltas]

must_haves:
  truths:
    - "Post-fix Instruments traces сняты на iPhone iOS 26.5 (4 dimensions) + MacBook secondary; numerical data сохранены в baselines/*-post-fix.md."
    - "Periphery post-fix scan показывает изменение dead-code count (либо явная decision why некоторые items остались)."
    - "06D-COMPARISON.md содержит pre-vs-post таблицу для каждого dimension с дельтой и % изменения, плюс per-span breakdown."
    - "Pre-fix файлы не изменены после Wave 06D-02c (D-07c — apples-to-apples)."
    - "PerfSignposter.swift и span инъекции сохранены (verify grep)."
    - "Ни одного `.trace` бинарника в git."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/baselines/cold-launch-iphone-post-fix.md"
      provides: "Post-fix Time Profiler cold-launch numerical export"
    - path: ".planning/phases/06d-performance-audit/baselines/connect-tap-iphone-post-fix.md"
      provides: "Post-fix connect-tap span timings"
    - path: ".planning/phases/06d-performance-audit/baselines/energy-iphone-post-fix.md"
      provides: "Post-fix Energy Log"
    - path: ".planning/phases/06d-performance-audit/baselines/allocations-iphone-host-post-fix.md"
      provides: "Post-fix Allocations host-process"
    - path: ".planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-post-fix.md"
      provides: "Post-fix Allocations Packet Tunnel extension-process"
    - path: ".planning/phases/06d-performance-audit/06D-COMPARISON.md"
      provides: "Pre-vs-post side-by-side table + per-span breakdown + decisions narrative"
      contains: "Pre-fix.*Post-fix.*Delta"
  key_links:
    - from: "baselines/*-pre-fix.md (Wave 06D-02c)"
      to: "baselines/*-post-fix.md (this wave)"
      via: "06D-COMPARISON.md side-by-side delta tables"
      pattern: "Delta|change"
    - from: "06D-FINDINGS.md (closed findings)"
      to: "06D-COMPARISON.md decision narrative"
      via: "Section 6 (Closed findings) listing F-XX + commit SHA + visible improvement"
      pattern: "closes F-[0-9]+"
---

# Phase 6d Wave Final-a — Post-fix Instruments + Periphery re-scan + Comparison

## Цель волны (по-русски)

Wave Final-a — **измерительная** sub-wave. Снимаем post-fix Instruments traces (mirror 6 captures из Wave 06D-02c) и создаём `06D-COMPARISON.md` — pre-vs-post delta tables с numerical headlines.

После Wave Final-a → Wave Final-b (UAT smoke + wiki final + STATE/ROADMAP sync + closure).

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
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@.planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-01-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-03-PLAN.md
@.planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
@.planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
@.planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
@.planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
@.planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
@.planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
@.planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1 — Post-fix Instruments traces (iPhone iOS 26.5 + MacBook) + Periphery re-scan</name>
  <files>
    .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-post-fix.md
    .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-post-fix.md
    .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-post-fix.md
    .planning/phases/06d-performance-audit/baselines/energy-iphone-post-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-post-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-post-fix.md
    .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секция «Instruments Workflow» строки 639-872 — A/B/C/D подсекции; «Pitfall 3 — Pre-fix measurement becomes post-fix baseline»)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role K — baseline markdown shape)
    - .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md (pre-fix shape — копируем + актуализируем post-fix)
    - .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md (то же)
    - .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
    - .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
    - .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md (A8 + extension type info — нужно для allocations attach)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift (verify не удалён — критично для comparison)
  </read_first>
  <action>
    Снять Instruments traces post-fix — **те же 4 dimensions** что в Wave 06D-02c. Цель: numerical data для comparison. Использовать ту же методологию (samples count, force-quit discipline, untethered Energy Log, etc.) для apples-to-apples сравнения.

    **Шаги:**

    1. **Verify environment unchanged** (Pitfall 3 — accidental contamination):
       - `git log --oneline -1` — записать current commit SHA в `post-fix.md` header.
       - **Pre-fix файлы не должны быть изменены** после Wave 06D-02c (D-07c). Verify:
         ```bash
         git log --oneline -- .planning/phases/06d-performance-audit/baselines/*-pre-fix.md
         # Все commits должны быть из Wave 06D-02a/02c, никаких post-CHECKPOINT touches.
         ```
       - Verify PerfSignposter.swift не удалён:
         ```bash
         test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift && \
           grep -q "OSSignposter(subsystem" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift
         ```

    2. **Time Profiler — Cold Launch iPhone iOS 26.5** (RESEARCH § A, identical к Wave 06D-02c Task 1):
       - App Launch template.
       - **5 true cold launches** (force-quit + wait ≥10s между).
       - Median по 5 samples.
       - Export → `baselines/cold-launch-iphone-post-fix.md` (структура идентична pre-fix; добавить header `**Post-fix commit SHA**: <current main SHA>`).
       - `.trace` бинарник — локально.

    3. **Time Profiler — Cold Launch MacBook** (secondary):
       - Scheme BBTB-macOS, target My Mac.
       - 5 cold launches.
       - Export → `baselines/cold-launch-macbook-post-fix.md`.

    4. **Time Profiler — Connect Tap iPhone** (RESEARCH § B):
       - Time Profiler template (не App Launch).
       - **≥10 cold connect-taps** + **≥10 warm connect-taps**. Median по каждому набору.
       - На timeline должны быть видны те же named spans (ConnectTap / PreConnectProbe / ProvisionProfile / LibboxStart).
       - Export → `baselines/connect-tap-iphone-post-fix.md`.

    5. **Energy Log — iPhone** (RESEARCH § C, untethered):
       - Те же 3 scenarios (Idle 60s / Connect tap window / Active 5min) — **identical conditions** (close other apps, Wi-Fi only, etc. per Pitfall 7).
       - **≥3 samples per scenario**.
       - Export → `baselines/energy-iphone-post-fix.md`.

    6. **Allocations — iPhone host process** (RESEARCH § D.1):
       - Те же scenarios (cold launch → import → connect → idle 60s connected).
       - Sort by Persistent Bytes desc; top 20 classes.
       - Export → `baselines/allocations-iphone-host-post-fix.md`.

    7. **Allocations — iPhone Packet Tunnel extension process** (RESEARCH § D.2, **критический шаг**):
       - Same protocol как pre-fix (BBTB Connect → Settings screen → Profile → Allocations → Running Applications list → find extension by PID).
       - Те же scenarios (idle 30s → airplane toggle → idle 30s post-reconnect).
       - Export → `baselines/allocations-iphone-extension-post-fix.md`.

    8. **Periphery post-fix scan** (RESEARCH § Code-Simplicity):
       ```bash
       cd BBTB && tuist generate
       periphery scan \
         --workspace BBTB.xcworkspace \
         --schemes BBTB BBTB-macOS \
         --targets BBTB BBTB-macOS PacketTunnelExtension-iOS PacketTunnelExtension-macOS \
         --retain-public \
         --retain-objc-accessible \
         --report-exclude '**/Tests/*.swift' '**/Generated/*.swift' '**/.build/**' \
         --format xcode \
         > ../.planning/phases/06d-performance-audit/periphery-scan-post-fix.txt
       ```
       Сравнить counts с `periphery-scan-pre-fix.txt`:
       ```bash
       echo "Pre-fix warnings:  $(wc -l < .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt)"
       echo "Post-fix warnings: $(wc -l < .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt)"
       ```
       Если post-fix > pre-fix — investigate (новый dead code? false positive из refactor?). Документировать в Task 2 (06D-COMPARISON.md).

    9. **Storage** (D-07c): `.trace` бинарники — **локально, не в git**. Verify:
       ```bash
       git status --porcelain | grep -iE "\.trace$" && echo "ERROR: trace binary staged" && exit 1 || true
       ```

    10. **Atomic commit**: `docs(06d-final-a): post-fix Instruments traces + Periphery re-scan` после всех 6 baseline files + periphery output.

    **Time budget:** 2-4 часа user-driven manual work на real device (parallel к pre-fix Wave 06D-02c Task 1).
  </action>
  <verify>
    <automated>
      test $(wc -l < .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-post-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-post-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/energy-iphone-post-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-post-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-post-fix.md) -gt 20 \
        && test -f .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt \
        && test $(wc -c < .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt) -gt 200 \
        && test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift \
        && git status --porcelain | grep -v '^#' | grep -ciE "\.trace$" | awk '$1 == 0 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <done>
    6 post-fix baseline-файлов имеют наполнение (numerical tables, median values, current commit SHA в header); periphery-scan-post-fix.txt существует с реальным output; PerfSignposter.swift на месте; ни одного `.trace` в git.
  </done>
</task>

<task type="auto">
  <name>Task 2 — 06D-COMPARISON.md pre-vs-post analysis (per-span deltas)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-COMPARISON.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/baselines/*-pre-fix.md (все 6 файлов)
    - .planning/phases/06d-performance-audit/baselines/*-post-fix.md (все 6 файлов, готовы после Task 1)
    - .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
    - .planning/phases/06d-performance-audit/periphery-scan-post-fix.txt
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (для cross-reference finding ID → improvement)
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (severity rubric для interpreting delta)
  </read_first>
  <action>
    Создать `06D-COMPARISON.md` — headline-документ phase, который показывает что именно Phase 6d дала пользователю. Side-by-side таблицы pre vs post + narrative + per-span breakdown.

    **Структура** (полная — 9 секций):

    ```markdown
    # Phase 6d — Pre-vs-Post Comparison

    **Date**: 2026-05-NN
    **Pre-fix commit**: <SHA from baselines/*-pre-fix.md>
    **Post-fix commit**: <current main SHA>
    **Closed findings**: NN из 06D-FINDINGS.md (см. список ниже)

    ---

    ## TL;DR (для пользователя, non-programmer)

    [Короткое resume — 3-5 предложений. Например:
    «Cold start на iPhone iOS 26.5 сократился с XXXms до YYYms (-Z%, медиана по 5 samples). Connect tap (от тапа power-кнопки до .connected) — XXX → YYY ms (-Z%). Energy Impact на 5-минутной активной сессии остался Low; Allocations retained-size не вырос. Mертвого кода удалено N items (-X строк).»]

    ---

    ## 1. Cold launch comparison (Time Profiler / App Launch template)

    ### iPhone iOS 26.5

    | Phase | Pre-fix median ms | Post-fix median ms | Delta ms | Delta % |
    |---|---|---|---|---|
    | dyld + +load (purple) | … | … | … | …% |
    | Swift static init (purple) | … | … | … | …% |
    | App.init body (green) | … | … | … | …% |
    | First frame commit (green) | … | … | … | …% |
    | **Total cold launch** | … | … | … | …% |

    **OSSignposter spans** (если signposts появились на timeline в обоих traces):

    | Span | Pre-fix median ms | Post-fix median ms | Delta ms |
    |---|---|---|---|
    | ColdLaunch (App.init → first .onAppear) | … | … | … |

    ### MacBook (secondary)

    [Аналогичная таблица.]

    ---

    ## 2. Connect tap comparison (Time Profiler + signposts)

    ### iPhone iOS 26.5 — cold app state (≥10 samples each)

    | Span | Pre-fix median ms | Post-fix median ms | Delta ms | Delta % |
    |---|---|---|---|---|
    | ConnectTap (total: power tap → .connected) | … | … | … | …% |
    | PreConnectProbe | … | … | … | …% |
    | ProvisionProfile | … | … | … | …% |
    | LibboxStart (extension process) | … | … | … | …% |

    ### iPhone iOS 26.5 — warm app state (≥10 samples each)

    [Аналогичная таблица.]

    ---

    ## 3. Energy comparison (Energy Log untethered)

    ### iPhone iOS 26.5 (≥3 samples per scenario, median)

    | Scenario | Pre-fix Impact | Post-fix Impact | Pre CPU% avg | Post CPU% avg | Pre Net KB/s | Post Net KB/s | Verdict |
    |---|---|---|---|---|---|---|---|
    | Idle 60s | … | … | … | … | … | … | ✅ stable / ⚠ regressed / ✅ improved |
    | Connect tap window (60s) | … | … | … | … | … | … | … |
    | Active session 5min | … | … | … | … | … | … | … |

    ---

    ## 4. Allocations comparison

    ### iPhone iOS 26.5 host process

    | Scenario / Generation | Pre-fix Persistent MB | Post-fix Persistent MB | Delta |
    |---|---|---|---|
    | After cold launch + 30s idle | … | … | … |
    | After import URI | … | … | … |
    | After connect → .connected | … | … | … |
    | After 60s in connected | … | … | … |

    **Top retained classes delta:**

    | Class | Pre-fix Persistent | Post-fix Persistent | Delta |
    |---|---|---|---|
    | … | … | … | … |

    ### iPhone iOS 26.5 Packet Tunnel extension process

    [Аналогичная таблица. Особенно libbox-related allocations.]

    ---

    ## 5. Dead-code (Periphery) comparison

    | Metric | Pre-fix | Post-fix | Delta |
    |---|---|---|---|
    | Total warnings | … | … | …  (-X items) |
    | Unused public symbols | … | … | … |
    | Unused private symbols | … | … | … |
    | Top affected files (pre→post) | ConfigImporter.swift: N→M; MainScreenViewModel.swift: N→M; … | … | … |

    ---

    ## 6. Closed findings (cross-reference 06D-FINDINGS.md)

    | Finding ID | Title | Severity | Commit SHA | Visible in comparison |
    |---|---|---|---|---|
    | F-001 | … | HIGH | … | Cold launch -120ms section 1 |
    | F-002 | … | HIGH | … | ConnectTap -80ms section 2 |
    | … | … | … | … | … |

    Carved findings (по CHECKPOINT 1 budget):
    | Finding ID | Title | Severity | Deferred to | Rationale |
    |---|---|---|---|---|
    | F-NNN | … | MEDIUM | Phase 7 backlog | … |
    | F-NNN | … | LOW | Phase 11 polish | … |

    ---

    ## 7. Severity rubric verification (D-05a)

    Pre/post deltas vs RAIL + D-05a thresholds:

    | Span | Delta | Rubric tier | Comment |
    |---|---|---|---|
    | Cold launch total | -NNNms | HIGH improvement (>200ms) | Goal achieved |
    | ConnectTap total | -NNms | MEDIUM improvement (50-200ms) | Goal achieved |
    | Idle Energy | unchanged | — | OK |
    | Active Energy | unchanged | — | OK |

    ---

    ## 8. Decisions / open follow-ups

    [Если в ходе fix-cycle вылезли architectural decisions, которые валидны за пределами Phase 6d — здесь записаны кратко + ссылки на wiki page touch (это будет сделано в Wave 06D-Final-b). Например:
    - **DEC-06d-01**: «Cold start init pattern — все non-critical inits в Task { @MainActor } в onAppear, не в App.init body» → переедет в wiki/architecture.md в Wave Final-b.
    - **DEC-06d-02**: «Dead-code policy — Periphery scan run перед каждым release» → переедет в wiki/tech-stack.md.

    Open follow-ups:
    - <если есть findings с partial fix или needs further work>.]

    ---

    ## 9. Methodology integrity

    - Pre-fix capture date: 2026-05-NN (Wave 06D-02c Task 1).
    - Post-fix capture date: 2026-05-NN (this Task).
    - **Same device**: iPhone XX iOS 26.5 (same physical phone).
    - **Same scenarios**: copy-paste из pre-fix methodology (Pitfall 3 — no contamination).
    - **Same Instruments templates**: App Launch (cold), Time Profiler (connect), Energy Log, Allocations.
    - **Sample counts identical** к pre-fix (5 cold launches, ≥10 connect taps, ≥3 per energy scenario).
    - **OSSignposter инъекции** не изменялись между pre и post — comparison корректен.
    ```

    **Atomic commit:** `docs(06d-final-a): pre-vs-post comparison analysis`.

    **NB:** Если какой-то dimension показал **regression** (post-fix хуже pre-fix) — задокументировать честно в `## 7. Severity rubric verification` секции + investigate в TODO list (может быть, fix имел unintended side effect; либо measurement noise — повторить sample). Quality > speed (C-03): не прятать regression.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && test $(wc -c < .planning/phases/06d-performance-audit/06D-COMPARISON.md) -gt 3000 \
        && grep -q "Pre-vs-Post Comparison" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -qE "Cold launch comparison|Connect tap comparison" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -q "Energy comparison" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -q "Allocations comparison" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -q "Dead-code.*comparison" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -q "Closed findings" .planning/phases/06d-performance-audit/06D-COMPARISON.md \
        && grep -qE "Methodology integrity|Same Instruments" .planning/phases/06d-performance-audit/06D-COMPARISON.md
    </automated>
  </verify>
  <done>
    06D-COMPARISON.md содержит 9 секций (TL;DR + Cold + Connect + Energy + Allocations + Dead-code + Closed findings + Severity rubric + Decisions + Methodology). Все numerical таблицы заполнены реальными данными. Regression items (если есть) задокументированы честно. Decisions для wiki long-term — выделены и ссылаются на Wave 06D-Final-b wiki touch.
  </done>
</task>

<task type="auto">
  <name>Task 3 — 06D-Final-a-SUMMARY.md closure record</name>
  <files>
    .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/baselines/*-post-fix.md (Task 1)
    - .planning/phases/06d-performance-audit/06D-COMPARISON.md (Task 2)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role M)
  </read_first>
  <action>
    Создать `06D-Final-a-SUMMARY.md` — Role M shape — closure record для Wave Final-a.

    Структура:
    ```markdown
    ---
    phase: 06d-performance-audit
    plan: Final-a
    type: summary
    status: complete
    date: 2026-05-NN
    commits:
      - "<sha1> — docs(06d-final-a): post-fix Instruments traces + Periphery re-scan"
      - "<sha2> — docs(06d-final-a): pre-vs-post comparison analysis"
    ---

    # Plan 06D-Final-a — Wave Final.1 SUMMARY

    ## Status
    Post-fix measurements + comparison complete. Next: Wave 06D-Final-b (UAT + wiki + closure).

    ## Headline deltas

    | Dimension | Pre-fix | Post-fix | Delta |
    |---|---|---|---|
    | Cold launch iPhone (median ms) | … | … | -NNms (-XX%) |
    | Cold launch MacBook (median ms) | … | … | … |
    | ConnectTap total (median ms) | … | … | … |
    | Energy Impact Active 5min | … | … | stable / improved |
    | Allocations host (60s connected, MB) | … | … | … |
    | Allocations extension (60s, MB) | … | … | … |
    | Periphery warnings | … | … | -NN items |

    ## Verification metrics

    | Check | Required | Actual | Status |
    |---|---|---|---|
    | 6 post-fix baseline files filled | yes | yes | ✅ |
    | periphery-scan-post-fix.txt > 200B | yes | … | ✅ |
    | 06D-COMPARISON.md имеет 9 секций | yes | … | ✅ |
    | PerfSignposter.swift на месте | yes | yes | ✅ |
    | 0 `.trace` в git | yes | yes | ✅ |

    ## Next
    Wave 06D-Final-b — UAT regression smoke + wiki/performance-baseline.md final + STATE/ROADMAP/REQUIREMENTS sync + 06D-Final-SUMMARY.md + Phase 6d closure.
    ```

    **Atomic commit:** `docs(06d-final-a): wave final-a closure summary`.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md \
        && grep -q "Plan 06D-Final-a" .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md \
        && grep -qE "Headline deltas|Verification metrics" .planning/phases/06d-performance-audit/06D-Final-a-SUMMARY.md
    </automated>
  </verify>
  <done>
    06D-Final-a-SUMMARY.md имеет actual delta numbers + verification metrics + reference на Wave Final-b как next.
  </done>
</task>

</tasks>

<verification>

**Wave-level acceptance:**

1. **Post-fix Instruments traces** (Task 1):
   - 6 baseline `-post-fix.md` файлов созданы с реальными numerical data (current commit SHA в header).
   - Periphery post-fix scan output saved.
   - 0 `.trace` бинарников в git.
   - PerfSignposter.swift и span инъекции — preserved (не удалены).

2. **Comparison** (Task 2):
   - 06D-COMPARISON.md содержит 9 секций (TL;DR + Cold + Connect + Energy + Allocations + Dead-code + Closed findings + Severity rubric verification + Decisions + Methodology integrity).
   - Все таблицы заполнены реальными pre/post deltas.
   - Regression items (если есть) задокументированы честно.

3. **Closure** (Task 3):
   - 06D-Final-a-SUMMARY.md с headline deltas + verification metrics.

</verification>

<success_criteria>

- [ ] Post-fix Instruments baseline complete (6 files наполнены, periphery output saved).
- [ ] 06D-COMPARISON.md содержит pre/post deltas для каждого dimension.
- [ ] 06D-Final-a-SUMMARY.md имеет headline deltas + verification metrics.
- [ ] 0 `.trace` бинарников в git.
- [ ] PerfSignposter.swift и span инъекции preserved.

</success_criteria>

<output>
После завершения создан `06D-Final-a-SUMMARY.md`. Next: Wave 06D-Final-b.
</output>
</content>
</invoke>