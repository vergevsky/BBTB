---
phase: 06d-performance-audit
plan: 02c
slice: c
type: execute
wave: 2.3
mode: mvp
depends_on: [02b]
files_modified:
  - .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/screenshots/
  - .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
  - wiki/performance-baseline.md
  - wiki/index.md
  - wiki/log.md
  - .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md
  - .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
autonomous: false
requirements: [PERF-01, PERF-02, PERF-03, PERF-04]
tags: [pre-fix-baseline, instruments, periphery, wiki, checkpoint, budget-options]

must_haves:
  truths:
    - "Pre-fix Instruments traces сняты на iPhone iOS 26.5 (4 dimensions: Time Profiler cold + connect, Energy Log, Allocations host + extension) + MacBook secondary."
    - "6 baseline files наполнены реальными numerical data (не плейсхолдеры) — median values по ≥3-10 samples в зависимости от scenario."
    - "Periphery production scan output сохранён в periphery-scan-pre-fix.txt."
    - "wiki/performance-baseline.md initial pre-fix draft создан per CLAUDE.md Page Format."
    - "wiki/index.md содержит link на performance-baseline; wiki/log.md содержит pre-fix capture entry."
    - "06D-FINDINGS-SUMMARY.md содержит severity histogram + per-dimension breakdown + top-5 critical + clustered themes + 3 budget options (A/B/C/custom) для CHECKPOINT 1."
    - "Ни одного `.trace` бинарника в git (D-07c)."
    - "CHECKPOINT 1 signal received (option-a/b/c/custom) или явно ожидает user input."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md"
      provides: "Pre-fix Time Profiler cold-launch numerical export (median по 5 samples)"
    - path: ".planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md"
      provides: "Pre-fix Time Profiler connect-tap numerical export (median по ≥10 samples)"
    - path: ".planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md"
      provides: "Pre-fix Energy Log (idle 60s / connect window / active 5min) numerical export"
    - path: ".planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md"
      provides: "Pre-fix Allocations host-process numerical export"
    - path: ".planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md"
      provides: "Pre-fix Allocations Packet Tunnel extension-process numerical export"
    - path: "wiki/performance-baseline.md"
      provides: "Long-term wiki page для pre/post comparison + decisions (initial pre-fix state)"
      contains: "Performance baseline"
    - path: ".planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md"
      provides: "Budget decision input — severity histogram + top-5 critical + 3 budget options"
      contains: "Recommended budget options"
  key_links:
    - from: "baselines/*.md (pre-fix)"
      to: "wiki/performance-baseline.md table"
      via: "pre-fix data populated from numerical exports"
      pattern: "Pre-fix baseline"
    - from: "06D-FINDINGS-SUMMARY.md"
      to: "CHECKPOINT 1 user decision"
      via: "Three budget options presented inline"
      pattern: "Recommended budget options"
---

# Phase 6d Wave 02c — Pre-fix Instruments baseline + CHECKPOINT 1 prep

## Цель волны (по-русски)

Wave 06D-02c — последняя sub-wave перед CHECKPOINT 1. Делает три вещи:

1. **Pre-fix Instruments baseline** (Task 1) — снимаем 4 dimensions (Time Profiler cold + connect, Energy Log, Allocations host + extension) на iPhone iOS 26.5 + MacBook secondary. Эти данные — **источник правды** для post-fix comparison в Wave 06D-Final-a.
2. **wiki/performance-baseline.md initial draft + index + log** (Task 2) — long-term память. Post-fix добавится в Wave 06D-Final-b.
3. **06D-FINDINGS-SUMMARY.md** + CHECKPOINT 1 (Task 3 + Task 4) — severity histogram, top-5 critical, clustered themes, 3 budget options. Затем 🛑 CHECKPOINT 1 ждёт user budget decision.

После CHECKPOINT 1 signal → Wave 06D-03 (fix-cycle template) материализуется orchestrator-ом.

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
@.planning/phases/06d-performance-audit/06D-02b-SUMMARY.md
@.planning/phases/06d-performance-audit/06D-FINDINGS.md
@.planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md
@BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift
@wiki/auto-reconnect.md
@wiki/index.md
@wiki/log.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1 — Pre-fix Instruments baseline (iPhone iOS 26.5 + MacBook) + Periphery scan</name>
  <files>
    .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/screenshots/
    .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секция «Instruments Workflow» строки 639-872 — A/B/C/D подсекции; «Code-Simplicity / Dead-Code Detection» — Periphery invocation)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role K — baseline markdown shape)
    - .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md (A8 result — runtime search paths для extension attach)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift (созданный в Wave 06D-02a Commit 2)
  </read_first>
  <action>
    Снять Instruments traces на pre-fix codebase (current main commit, после Wave 06D-02a 3 atomic commits — sign post инъекции уже на месте). Записать numerical экспорты в 6 baseline-файлов созданных в Wave 06D-02a Commit 3.

    **Шаги:**

    1. **Time Profiler — Cold Launch iPhone iOS 26.5** (RESEARCH § A):
       - Подключить iPhone к Mac через кабель. Trust device.
       - Xcode → Product → Profile → выбрать template «App Launch» (Apple-blessed, автоматизирует pre-main + main-to-first-frame phases).
       - Target Device: iPhone iOS 26.5. Target Process: BBTB.
       - **True cold launches × 5**: force-quit BBTB (swipe up + swipe away) + wait ≥10s перед каждым sample. Inside-Xcode build-and-run **не** cold.
       - Запись stops автоматически после first interactive frame.
       - Export: copy-paste numerical data из Summary lanes + screenshot timeline → `baselines/cold-launch-iphone-pre-fix.md` (заполнить template). Median по 5 samples. Header: pre-fix commit SHA + date + device + iOS version.
       - `.trace` бинарник — **не в git** (D-07c). Сохранить локально, например `~/Documents/BBTB-traces/cold-launch-iphone-2026-05-NN.trace`.

    2. **Time Profiler — Cold Launch MacBook** (secondary, RESEARCH § E):
       - Scheme: BBTB-macOS. Target: My Mac.
       - 5 cold launches (close app + wait 10s между).
       - Export → `baselines/cold-launch-macbook-pre-fix.md`. Median.

    3. **Time Profiler — Connect Tap iPhone** (RESEARCH § B):
       - Template: Time Profiler (не App Launch — это in-app interaction).
       - Запись start ДО тапа Connect; stop после первого timer tick.
       - **≥10 connect-taps** от cold app state (force-quit между) + **≥10** от warm state (без force-quit). Median.
       - На timeline должны появиться **named spans** благодаря Wave 06D-02a Commit 2 signpost инъекциям: `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`. Если spans **не** появились — diagnostics step: re-verify Wave 06D-02a inject sites через grep, rebuild.
       - Export → `baselines/connect-tap-iphone-pre-fix.md`. Table со span timings (ConnectTap total / PreConnectProbe / ProvisionProfile separate columns). Plus xcrun instruments timeline screenshot.

    4. **Energy Log — iPhone** (RESEARCH § C, untethered measurement):
       - iPhone Settings → Privacy & Security → Developer Mode ON (если ещё нет).
       - Settings → Developer → Logging → Energy ON.
       - Reboot iPhone для clean baseline.
       - **Pre-scenario discipline** (Pitfall 7): close all other apps, Wi-Fi only mode, no other VPN active.
       - Disconnect iPhone от Mac (untethered = реалистично).
       - Three scenarios:
         a. Idle 60s — open BBTB, не нажимать ничего.
         b. Connect tap window — tap Connect, wait .connected, ещё 60s.
         c. Active session 5min — connection up, Safari 5-10 pages (Google, Wikipedia, etc.).
       - Reconnect iPhone. Settings → Developer → Logging → Energy → download log file.
       - Import в Instruments или открыть в Console.app для analyze.
       - **≥3 samples per scenario**, median.
       - Export → `baselines/energy-iphone-pre-fix.md`. Table per scenario: Energy Impact / CPU% avg / Network KB/s / Background CPU%.

    5. **Allocations — iPhone host process** (RESEARCH § D.1):
       - Xcode → Product → Profile → Allocations template. Target: BBTB (Running Applications list).
       - Scenarios sequential (mark Generations between):
         a. Cold launch → MainScreen idle 30s.
         b. Import URI через clipboard.
         c. Connect → .connected.
         d. Idle 60s в connected state.
       - Stop. Sort by Persistent Bytes desc. Top 20 classes — write down.
       - Export → `baselines/allocations-iphone-host-pre-fix.md`.

    6. **Allocations — iPhone Packet Tunnel extension process** (RESEARCH § D.2, **CRITICAL nontrivial**):
       - Запустить BBTB + Connect — убедиться VPN up + extension has PID.
       - В iPhone Settings → перейти на любой screen (например VPN settings) — гарантирует extension не suspend-нется на attach window.
       - Xcode → Product → Profile → Allocations template.
       - **Target list dropdown:** выбрать «Running Applications» (НЕ App Extensions list — Apple bug per Matt Eaton) → найти extension по имени `PacketTunnelExtension-iOS`. PID **must be present** — без PID extension suspended.
       - Если ошибка `"This copy of libswiftCore.dylib requires an OS version prior to 12.2.0"` — verify `/usr/lib/swift` в Runtime Search Paths для tunnel target (A8 verification из Wave 06D-02a). Если ASSUMED был wrong и path не set — fix в Tuist `Project.swift`, regenerate, повторить.
       - Scenarios:
         a. Idle 30s connected.
         b. Toggle airplane mode briefly (on-demand reconnect).
         c. Idle 30s post-reconnect.
       - Export → `baselines/allocations-iphone-extension-pre-fix.md`. Особое внимание libbox-related allocations (Go runtime objects).

    7. **Periphery scan pre-fix** (RESEARCH § «Code-Simplicity / Primary tool»):
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
         > ../.planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
       ```
       Сохранить full output. Count warnings + top 20 by file → краткое summary в `06D-02c-SUMMARY.md` (Task 4).

    8. **D-07c reinforcement:** ни одного `.trace` бинарника в git. Verify:
       ```bash
       git status --porcelain | grep -iE "\.trace$" && echo "ERROR: trace binary staged" && exit 1 || true
       ```

    9. **Atomic commit:** `docs(06d-02c): pre-fix Instruments baseline + Periphery scan`.

    **Time budget:** Instruments steps 1-6 — суммарно 2-4 часа физического времени на user-driven измерения. Это manual work на real device. Plan **не** автоматизирует это.

    **Regression gate after this task:** опционально (никаких code changes); но для consistency прогнать `swift test --package-path BBTB/Packages/AppFeatures`.
  </action>
  <verify>
    <automated>
      test $(wc -l < .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md) -gt 20 \
        && test $(wc -l < .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md) -gt 20 \
        && test -f .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt \
        && test $(wc -c < .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt) -gt 200 \
        && git status --porcelain | grep -v '^#' | grep -ciE "\.trace$" | awk '$1 == 0 { exit 0 } { exit 1 }'
    </automated>
  </verify>
  <done>
    6 baseline-файлов имеют наполнение (numerical tables, median values); periphery-scan-pre-fix.txt существует с реальным output (>200 байт); 0 `.trace` бинарников в git.
  </done>
</task>

<task type="auto">
  <name>Task 2 — wiki/performance-baseline.md initial draft + wiki/index.md + wiki/log.md sync</name>
  <files>
    wiki/performance-baseline.md
    wiki/index.md
    wiki/log.md
  </files>
  <read_first>
    - wiki/auto-reconnect.md (shape reference для wiki page — Header / Summary / Sources / Last updated / sections / Related pages)
    - wiki/index.md (current state — где впишется новая link)
    - wiki/log.md (append-only — Task добавит entry)
    - .planning/phases/06d-performance-audit/baselines/*.md (наполнены в Task 1 — данные для wiki table)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role F — wiki page format; Shared 2 — wiki sync cadence)
    - CLAUDE.md (Page format + C-06 wiki long-term memory rule)
  </read_first>
  <action>
    Создать wiki/performance-baseline.md initial draft + sync wiki/index.md + wiki/log.md.

    **Шаги:**

    1. **Create `wiki/performance-baseline.md` initial draft** — pre-fix только; post-fix добавится в Wave 06D-Final-b. Shape per CLAUDE.md Page Format + Role F в PATTERNS:
       ```markdown
       ---
       name: Performance baseline (Phase 6d)
       description: Pre- и post-fix measurements cold start, connect tap, energy, allocations на iPhone iOS 26.5 и MacBook. Артефакты Phase 6d (2026-05).
       type: measurement
       ---

       # Performance baseline (Phase 6d)

       **Summary**: Pre-fix Instruments measurements зафиксированы 2026-05-NN на iPhone iOS 26.5 и MacBook macOS X.Y. Post-fix added в Wave 06D-Final-b после CHECKPOINT 1 + fix-cycle. Все .trace бинарники локальные (не в git); markdown summaries в .planning/phases/06d-performance-audit/baselines/.

       **Sources**:
       - .planning/phases/06d-performance-audit/baselines/*.md (numerical экспорты)
       - .planning/phases/06d-performance-audit/06D-RESEARCH.md (методология)
       - .planning/phases/06d-performance-audit/06D-FINDINGS.md (consolidated findings → fixes)

       **Last updated**: 2026-05-NN (Wave 06D-02c pre-fix capture).

       ---

       ## Зачем эта страница

       (Объяснение non-programmer audience: Phase 5 пользователь сообщил «приложение тяжело грузится». Phase 6d — measurement + targeted fixes. Эта страница — long-term память что измерили, какие findings, какие фиксы помогли, какие нет. Будущие phases (7-12) opt-in к проверке здесь, не reinvent.)

       ## Методология

       (короткое описание Instruments templates + sample counts + true-cold discipline; details — в baselines/*.md.)

       ## Pre-fix baseline (Wave 06D-02c)

       | Dimension | Metric | iPhone iOS 26.5 | MacBook macOS X.Y |
       |---|---|---|---|
       | Cold launch | Total (median ms) | NN | NN |
       | Cold launch | App.init body (median ms) | NN | NN |
       | Connect tap | Total ConnectTap span (median ms) | NN | n/a |
       | Connect tap | PreConnectProbe (median ms) | NN | n/a |
       | Connect tap | ProvisionProfile (median ms) | NN | n/a |
       | Energy | Idle 60s | XX impact | n/a (separate macOS template) |
       | Energy | Active 5min | XX impact | n/a |
       | Allocations (host) | Persistent bytes after baseline | NN MB | n/a |
       | Allocations (extension) | Persistent bytes after baseline | NN MB | n/a |

       ## Post-fix comparison (Wave 06D-Final-b)

       _Будет заполнено в Wave 06D-Final-b post-fix Instruments traces._

       ## Decisions / open follow-ups

       _Заполнится по итогам fix-cycle._

       ## Related pages

       - [[auto-reconnect]] — Phase 6c long-term memory (architectural baseline для invariants)
       - [[architecture]] — SwiftPM-структура и tier map
       - [[tech-stack]] — Swift 6 + sing-box + libbox + SwiftData
       ```

    2. **Update `wiki/index.md`** — добавить link на новую страницу в секцию `## Безопасность` или новую `## Производительность` (после auto-reconnect). One-line description:
       `- [[performance-baseline]] — Pre/post-fix Instruments measurements (Phase 6d, 2026-05).`

    3. **Append `wiki/log.md`** — entry:
       ```
       ## 2026-05-NN — Phase 6d Wave 06D-02c pre-fix baseline captured

       Сняты Instruments traces на iPhone iOS 26.5 + MacBook: cold launch (App Launch template), connect tap (Time Profiler + OSSignposter spans из Wave 06D-02a), Energy Log (Idle/Connect/Active 5min), Allocations (host + Packet Tunnel extension). Periphery 3.7.4 production scan output saved. Создана wiki/performance-baseline.md (initial pre-fix draft); post-fix добавится в Wave 06D-Final-b.

       OSSignposter инъекции (PerfSignposter.swift) уже на месте с Wave 06D-02a — cold-start hot path (BBTB_iOSApp.init + BBTB_macOSApp.init), connect-tap (TunnelController.performToggleImpl), Libbox launch (PacketTunnelProvider iOS+macOS).
       ```

    **Atomic commit:** `docs(06d-02c): wiki performance-baseline initial draft + index + log sync`.
  </action>
  <verify>
    <automated>
      test -f wiki/performance-baseline.md \
        && grep -q "Performance baseline" wiki/performance-baseline.md \
        && grep -q "Pre-fix baseline" wiki/performance-baseline.md \
        && grep -q "performance-baseline" wiki/index.md \
        && grep -qE "Wave 06D-02c pre-fix baseline|pre-fix baseline captured" wiki/log.md
    </automated>
  </verify>
  <done>
    wiki/performance-baseline.md initial draft создан per CLAUDE.md Page Format; wiki/index.md содержит link; wiki/log.md обновлён.
  </done>
</task>

<task type="auto">
  <name>Task 3 — 06D-FINDINGS-SUMMARY.md + 06D-02c-SUMMARY.md (input для CHECKPOINT 1)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md
    .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (заполнен в Wave 06D-02b)
    - .planning/phases/06d-performance-audit/baselines/*.md (заполнены в Task 1)
    - .planning/phases/06d-performance-audit/periphery-scan-pre-fix.txt
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секция «Common Pitfalls / Pitfall 4 — User checkpoint fatigue», рекомендация о cluster-by-theme)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role M — closure summary shape)
    - .planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md (shape reference)
  </read_first>
  <action>
    Создать два user-facing документа: `06D-FINDINGS-SUMMARY.md` (для CHECKPOINT 1 decision) и `06D-02c-SUMMARY.md` (closure record).

    **1. `06D-FINDINGS-SUMMARY.md` структура** (по-русски, simple language per C-04):

    ```markdown
    # Phase 6d Findings — сводка для CHECKPOINT 1

    **Дата**: 2026-05-NN
    **Source**: `06D-FINDINGS.md` (consolidated synthesis после 3 AI passes + invariant filter)
    **Aim**: дать пользователю достаточно информации для решения «какой бюджет фиксов» **БЕЗ** необходимости читать 100+ строк FINDINGS.

    ## Краткое резюме (3-5 предложений non-programmer)

    [Что обнаружили в общих чертах. Например: «Codebase в целом здоровый — фокус Phase 6c (TunnelController slim, on-demand migration) дал заметную чистоту. Но cold start страдает от X задач параллельно в App.init; connect tap имеет N MS overhead от Y. Dead code обнаружен в Z крупных файлах (ConfigImporter.swift, MainScreenViewModel.swift).»]

    ## Severity histogram

    | Severity | Count | Comment |
    |---|---|---|
    | HIGH | NN | measurable user pain (>200ms, security, active bug) |
    | MEDIUM | NN | 50-200ms / maintenance debt / energy regression |
    | LOW | NN | cosmetic / <50ms / future-friction |
    | **Total** | NN | (после dedup + invariant filter) |

    ## Per-dimension breakdown

    | Dimension | HIGH | MEDIUM | LOW | Sum |
    |---|---|---|---|---|
    | Performance | … | … | … | … |
    | Energy | … | … | … | … |
    | Simplicity / Dead-code | … | … | … | … |
    | Memory | … | … | … | … |
    | Launch time | … | … | … | … |

    ## Top-5 critical findings (deep dive)

    | # | Title | Severity | File:Line | Why this matters (по-русски) | Recommended fix (short) |
    |---|---|---|---|---|---|
    | 1 | … | HIGH | … | … | … |
    | 2 | … | HIGH | … | … | … |
    | 3 | … | HIGH | … | … | … |
    | 4 | … | HIGH/MEDIUM | … | … | … |
    | 5 | … | HIGH/MEDIUM | … | … | … |

    (Если HIGH findings меньше 5 — заполнить MEDIUM-ами по убывающей impact.)

    ## Clustered themes (cluster-by-theme per Pitfall 4)

    Чтобы не утопить пользователя в 100+ строках LOW findings — сгруппированы по теме:

    | Theme | Findings count | Affected files | Severity mix |
    |---|---|---|---|
    | Cold-start hot path (App.init Task storm) | NN | BBTB_iOSApp.swift, BBTB_macOSApp.swift | H×N, M×N, L×N |
    | Connect-tap optimization | NN | TunnelController.swift, ConfigImporter.swift | … |
    | Dead code in ConfigImporter | NN | ConfigImporter.swift | … |
    | Dead code in MainScreenViewModel | NN | MainScreenViewModel.swift | … |
    | @Published thrash | NN | MainScreenViewModel.swift | … |
    | Periphery findings (dead-code scan) | NN | various | almost all LOW |
    | … | … | … | … |

    ## Рекомендуемые budget options для CHECKPOINT 1

    Три варианта; пользователь выбирает один (или комбинирует):

    ### Option A: Minimal — только HIGH

    - **Что**: закрыть все NN HIGH findings; MEDIUM + LOW carved out.
    - **Ожидаемые волны**: ~1-2 fix-waves (06D-03, optional 06D-04).
    - **Контекст-цена**: ~30-50% (per-wave 2-3 tasks × ~25% context).
    - **Кому подходит**: «времени мало, нужны только реальные user-impact исправления». Phase 7 starts sooner.
    - **Что осталось not-fixed**: MEDIUM + LOW carved out → задокументированы в `06D-FINDINGS.md` со статусом «Deferred to Phase 7+».

    ### Option B: Balanced — HIGH + MEDIUM

    - **Что**: закрыть NN HIGH + NN MEDIUM; LOW carved.
    - **Ожидаемые волны**: ~2-4 fix-waves.
    - **Контекст-цена**: ~50-80%.
    - **Кому подходит**: «нужны исправления, видимые в Instruments post-fix; нет цели вычистить каждый dead-code».
    - **Что осталось not-fixed**: LOW carved.

    ### Option C: Thorough — HIGH + MEDIUM + selected LOW themes

    - **Что**: HIGH + MEDIUM + LOW кластеры с большим cumulative impact (например, «Dead code in ConfigImporter — 12 items» — bundled commit). LOW themes без cumulative impact carved.
    - **Ожидаемые волны**: ~3-6 fix-waves.
    - **Контекст-цена**: ~80-100% (близко к budget limit; пользователь должен явно принять risk).
    - **Кому подходит**: «Phase 7 не торопит; хочется чистый baseline перед большим объёмом нового кода».
    - **Что осталось not-fixed**: ничего, кроме LOW тем явно carved.

    ## Decision request (для пользователя)

    Пожалуйста ответьте одной из:
    - `Option A` (HIGH only)
    - `Option B` (HIGH + MEDIUM)
    - `Option C` (HIGH + MEDIUM + selected LOW themes)
    - **OR** custom budget — указать findings по номерам / темам которые хочется закрыть, остальное carve.

    После решения orchestrator материализует `06D-03-PLAN.md` (template волны 3) конкретными task-ами под выбранный бюджет.
    ```

    Заполнить **актуальными числами** из `06D-FINDINGS.md`. Top-5 — реальные findings. Themes — кластеризованы из actual data.

    **2. `06D-02c-SUMMARY.md` структура** (Role M shape):

    ```markdown
    ---
    phase: 06d-performance-audit
    plan: 02c
    type: summary
    status: complete-awaiting-checkpoint
    date: 2026-05-NN
    commits:
      - "<sha1> — docs(06d-02c): pre-fix Instruments baseline + Periphery scan"
      - "<sha2> — docs(06d-02c): wiki performance-baseline initial draft + index + log sync"
      - "<sha3> — docs(06d-02c): findings summary + budget options for CHECKPOINT 1"
    ---

    # Plan 06D-02c — Wave 2.3 SUMMARY

    ## Status
    Wave 06D-02c complete; awaiting CHECKPOINT 1 (пользовательский выбор бюджета).

    ## What changed

    ### Files modified
    [таблица с file path + Δ + notes — как в 06C-04-SUMMARY]

    ### Files created
    - 6 baseline markdown templates наполнены реальными данными
    - periphery-scan-pre-fix.txt
    - wiki/performance-baseline.md (initial)
    - 06D-FINDINGS-SUMMARY.md
    - 06D-02c-SUMMARY.md (this file)

    ## Instruments baseline metrics (краткая сводка)
    [короткая таблица median timings из baselines/*.md]

    ## Periphery scan baseline
    Warnings count: NN; top-5 files by warning count: …

    ## Verification metrics

    | Check | Required | Actual | Status |
    |---|---|---|---|
    | 6 baseline files filled with real data | yes | yes | ✅ |
    | periphery-scan-pre-fix.txt > 200B | yes | … | ✅ |
    | wiki/performance-baseline.md initial draft | exists with Pre-fix table | yes | ✅ |
    | wiki/index.md updated | link добавлен | yes | ✅ |
    | wiki/log.md updated | entry добавлен | yes | ✅ |
    | .trace в git | 0 | 0 | ✅ |
    | 06D-FINDINGS-SUMMARY.md has 3 budget options | yes | yes | ✅ |

    ## Next

    🛑 **CHECKPOINT 1** (Task 4) — пользователь выбирает budget option (A / B / C / custom). См. `06D-FINDINGS-SUMMARY.md`.

    После решения — orchestrator материализует `06D-03-PLAN.md` (text template сейчас) под выбранный бюджет → Wave 06D-03 (fix-cycle) start.
    ```

    **Atomic commit** для этой task: один `docs(06d-02c): findings summary + budget options for CHECKPOINT 1`.
  </action>
  <verify>
    <automated>
      test -f .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -q "Severity histogram" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -q "Top-5 critical" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -q "Recommended budget options\|budget options" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -qE "Option A.*HIGH only|Option A.*Minimal" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -qE "Option B.*Balanced|Option B.*HIGH . MEDIUM" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && grep -qE "Option C.*Thorough|Option C.*selected LOW" .planning/phases/06d-performance-audit/06D-FINDINGS-SUMMARY.md \
        && test -f .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md \
        && grep -q "Plan 06D-02c" .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md \
        && grep -q "CHECKPOINT 1" .planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
    </automated>
  </verify>
  <done>
    06D-FINDINGS-SUMMARY.md содержит severity histogram + per-dimension breakdown + top-5 critical (актуальные данные) + 3 explicit budget options A/B/C + clustered themes. 06D-02c-SUMMARY.md имеет actual commits + verification metrics + указание на CHECKPOINT 1 как next.
  </done>
</task>

<task type="checkpoint:decision" gate="blocking">
  <name>🛑 CHECKPOINT 1 — User budget decision</name>
  <decision>Какой объём findings закрываем в Wave 06D-03+?</decision>
  <context>
    Wave 06D-02c завершён: 3 AI passes synthesizirovany (Wave 06D-02b), invariant violations отфильтрованы, pre-fix Instruments baseline снят. `06D-FINDINGS-SUMMARY.md` показывает actual counts: NN HIGH / NN MEDIUM / NN LOW findings (после dedup + filter).

    Пользователь должен решить, какой объём закрываем сейчас (в рамках Phase 6d, до Phase 7 — Anti-DPI + WireGuard). От этого зависит:
    - Количество fix-waves (06D-03, опционально 06D-04, …).
    - Точная композиция task-ов в `06D-03-PLAN.md` (сейчас template).
    - Когда стартует Phase 7.

    Phase 6d НЕ требует закрытия всех findings. Carved-out findings документируются в `06D-FINDINGS.md` со статусом «Deferred to Phase X» и могут быть подобраны позже.
  </context>
  <options>
    <option id="option-a">
      <name>Option A — Minimal (HIGH only)</name>
      <pros>
        - Быстро: 1-2 fix-waves.
        - Низкий context budget (~30-50%).
        - Phase 7 starts sooner.
        - Только real user-impact исправления.
      </pros>
      <cons>
        - MEDIUM + LOW carved → могут накапливаться в Phase 7-12.
        - Maintenance debt остаётся.
      </cons>
    </option>
    <option id="option-b">
      <name>Option B — Balanced (HIGH + MEDIUM)</name>
      <pros>
        - Видимые improvements в Instruments post-fix.
        - Snizit maintenance debt значимо.
        - Sweet spot для quality > speed (C-03).
      </pros>
      <cons>
        - 2-4 fix-waves.
        - Context budget ~50-80%.
        - Phase 7 starts позже.
      </cons>
    </option>
    <option id="option-c">
      <name>Option C — Thorough (HIGH + MEDIUM + selected LOW themes)</name>
      <pros>
        - Чистейший baseline перед Phase 7-12.
        - Dead-code clustering закроет large LOW counts одним commit-ом per theme (Pitfall 6 grouping).
        - Maximal scalable future (C-05).
      </pros>
      <cons>
        - 3-6 fix-waves.
        - Context budget ~80-100% — близко к limit.
        - Phase 7 заметно отодвигается.
      </cons>
    </option>
    <option id="option-custom">
      <name>Custom — пользователь указывает finding IDs / themes явно</name>
      <pros>
        - Maximum flexibility.
        - Можно taргетировать конкретные pain points из user experience.
      </pros>
      <cons>
        - Требует от пользователя прочитать `06D-FINDINGS.md` (не только SUMMARY).
        - Сложнее планировать waves.
      </cons>
    </option>
  </options>
  <resume-signal>
    Ответьте одним из:
    - `option-a` (Minimal — HIGH only)
    - `option-b` (Balanced — HIGH + MEDIUM)
    - `option-c` (Thorough — HIGH + MEDIUM + selected LOW themes)
    - `option-custom: <finding IDs или themes список>` — например `option-custom: F-001, F-003, F-007, theme:"Dead code in ConfigImporter"`

    После signal orchestrator материализует `06D-03-PLAN.md` (template сейчас) конкретными task-ами и запускает Wave 06D-03.
  </resume-signal>
</task>

</tasks>

<verification>

**Wave-level acceptance (после всех 3 tasks + CHECKPOINT 1 signal):**

1. **Pre-fix baseline complete:**
   - 6 baseline files наполнены (numerical data, не плейсхолдеры).
   - `wiki/performance-baseline.md` initial draft создан per CLAUDE.md Page Format.
   - `wiki/index.md` + `wiki/log.md` обновлены.
   - 0 `.trace` файлов в git.
2. **CHECKPOINT 1 prep:**
   - `06D-FINDINGS-SUMMARY.md` имеет 3 budget options + top-5 critical + clustered themes.
   - `06D-02c-SUMMARY.md` имеет actual metrics + verification table.
3. **CHECKPOINT 1 signal** — user выбрал option-a/b/c/custom.

</verification>

<success_criteria>

- [ ] Pre-fix Instruments baseline complete (6 baseline files наполнены реальными данными).
- [ ] wiki/performance-baseline.md initial draft + wiki/index.md update + wiki/log.md append.
- [ ] 06D-FINDINGS-SUMMARY.md содержит 3 budget options готовые для user choice.
- [ ] CHECKPOINT 1 signal received from user (option-a / option-b / option-c / option-custom).
- [ ] 0 `.trace` бинарников в git.

</success_criteria>

<output>
После завершения создан `06D-02c-SUMMARY.md`. Final state of wave: awaiting CHECKPOINT 1 signal. После signal orchestrator материализует Wave 06D-03.
</output>
</content>
</invoke>