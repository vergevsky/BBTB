---
phase: 06d-performance-audit
plan: 03
type: execute
wave: 3
mode: mvp
depends_on: [02c]
files_modified: []  # TBD после CHECKPOINT 1 — материализуется по выбранному бюджету
autonomous: false
requirements: [QUAL-01, QUAL-02]
tags: [fix-cycle, template, awaiting-checkpoint, atomic-commits, regression-gate, invariant-guard]

checkpoint_dependency:
  blocked_by: "CHECKPOINT 1 (in 06D-02c-PLAN.md Task 4)"
  needs_signal:
    - "option-a (HIGH only)"
    - "option-b (HIGH + MEDIUM)"
    - "option-c (HIGH + MEDIUM + selected LOW themes)"
    - "option-custom: <finding IDs / themes>"
  materialization_action: |
    После signal orchestrator (gsd-planner в режиме gap-closure либо revision) overwrites
    тело этого плана конкретными task-ами под выбранный budget. Альтернативно — orchestrator
    создаёт sub-plans 06D-03a-PLAN.md, 06D-03b-PLAN.md, … по одной wave fix-cycle на sub-plan,
    с этим файлом превращённым в umbrella index. Структура верifaqиваемых invariants
    (regression cadence + atomic commit policy + D-09 guard + grep audit + per-finding
    acceptance_criteria + sensitive-files D-09 pre-check) остаётся **verbatim** в каждом
    materialized sub-plan / overwritten body.

must_haves:
  # Эти must-haves применяются к КАЖДОЙ материализованной fix-task независимо от темы.
  truths:
    - "AppFeatures swift test 133/133 + iOS Simulator xcodebuild + BBTB-macOS xcodebuild — green между КАЖДОЙ atomic commit."
    - "D-09 Phase 6c invariants preserved: intent-closing path, no XPC observer, no RSM/NetReach revival, single-authority applyVPNStatus, sliding session window — все intact."
    - "Каждая fix-task — atomic commit с reference на finding ID из 06D-FINDINGS.md (`fix(06d-NN): <one-line> closes F-XX`)."
    - "Bundled commits для same-file same-theme LOW fixes (Pitfall 6 / RESEARCH Pitfall 5 grouping)."
    - "Forbidden-symbol grep (Phase 6c B-08 pattern) — count не растёт по ходу wave."
    - "Никаких новых dependencies (D-02a) без explicit user-impact justification + CHECKPOINT escalation."
    - "Никаких изменений в OSSignposter инъекциях из Wave 06D-02a Commit 2 (они нужны для post-fix Wave 06D-Final-a comparison)."
    - "Каждая materialized task имеет per-finding <acceptance_criteria> с объективно-проверяемыми критериями (grep matches, Instruments thresholds, test exit codes, build assertions)."
    - "Если materialized task касается SENSITIVE FILES (TunnelController.swift, MainScreenViewModel.swift, BBTB_iOSApp.swift, BBTB_macOSApp.swift, PacketTunnelProvider*.swift) — task имеет inline 'D-09 invariant pre-check' step."
  artifacts:
    - path: ".planning/phases/06d-performance-audit/06D-03-SUMMARY.md (или 06D-03a/03b/… если split)"
      provides: "Per-wave closure record с commit SHA list, finding IDs closed, verification metrics, invariant-guard grep result"
  key_links:
    - from: "06D-FINDINGS.md HIGH/MEDIUM/LOW finding row"
      to: "fix commit SHA (one per atomic commit per finding или per bundled theme)"
      via: "commit message reference `closes F-NN`"
      pattern: "closes F-[0-9]+"
    - from: "Each fix commit"
      to: "Regression gate D-08 (swift test + xcodebuild × 2)"
      via: "post-commit verification"
      pattern: "133/133.*PASS|BUILD SUCCEEDED"
---

# Phase 6d Wave 3 — Fix cycle (TEMPLATE — awaiting CHECKPOINT 1)

## ⚠ Статус плана

**Этот файл — TEMPLATE.** Конкретные fix-task-и появятся **после** того, как пользователь даст signal в CHECKPOINT 1 (см. `06D-02c-PLAN.md` Task 4). Сейчас в этом плане:

- ✅ Verbatim секции, которые применяются к ЛЮБОМУ materialized fix-cycle (regression gate cadence, atomic commit policy, D-09 invariant guard, grep audit checklist, materialization protocol с per-finding acceptance_criteria + sensitive-files D-09 pre-check).
- ✅ Placeholder task slots (`<placeholder>` type) — orchestrator overwrites после signal.
- ✅ `autonomous: false` + `<checkpoint_dependency>` блок в frontmatter — execute-phase знает, что блок ждёт user signal.

После signal orchestrator может:
1. **Overwrite этот body** конкретными task-ами под выбранный бюджет, ИЛИ
2. **Создать sub-plans** `06D-03a-PLAN.md` / `06D-03b-PLAN.md` / … (по одной fix-wave на sub-plan) с этим файлом как umbrella index. Решает orchestrator по объёму findings.

В обоих сценариях **verbatim секции ниже копируются в materialized plans без изменений** — это инварианты выполнения fix-cycle.

---

## Цель волны (по-русски)

Wave 06D-03 — это **fix-cycle** для исправления findings, выбранных пользователем в CHECKPOINT 1. По принципу **«качество > скорость»** (C-03):
- Каждый fix — atomic commit с reference на finding ID.
- Между КАЖДЫМ commit-ом — **полный regression gate** (swift test + iOS xcodebuild + macOS xcodebuild).
- Любая попытка изменения Phase 6c invariant (D-09) **STOP-сценарий** с escalation user.
- Bundle same-file same-theme LOW commits (Pitfall 6 от RESEARCH) — `chore(06d-NN): cleanup dead code in <file> (M items)` вместо 12 separate commits.
- Каждая materialized task имеет per-finding `<acceptance_criteria>` + (если сенситивная) D-09 invariant pre-check.

После Wave 06D-03 (или 03a/03b/…) — Wave 06D-Final-a (post-fix Instruments + comparison), затем Wave 06D-Final-b (UAT + wiki + closure).

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
@.planning/phases/06d-performance-audit/06D-02c-SUMMARY.md
@.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md
@CLAUDE.md
</context>

---

## Verbatim section 1 — Regression gate cadence (D-08)

> Эти команды и пороги применяются между КАЖДЫМ atomic commit fix-cycle. Никаких сокращений вроде «прогоним gate в конце wave» — это нарушает Pitfall 6 (test regression detected after wave but root cause is earlier wave).

**Команды gate (per Role G в PATTERNS.md, copied from 06C-04-SUMMARY.md):**

```bash
# 1) AppFeatures test suite — must be 133/133 PASS (или actual N/N где N стабилен)
swift test --package-path BBTB/Packages/AppFeatures

# 2) iOS Simulator build — must BUILD SUCCEEDED
xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB \
  -destination 'generic/platform=iOS Simulator' build

# 3) macOS build — must BUILD SUCCEEDED
xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS \
  -destination 'platform=macOS' build
```

**Verification table** — копируется в materialized SUMMARY для каждой fix-task:

| Check | Required | Actual | Status |
|---|---|---|---|
| `swift test --package-path BBTB/Packages/AppFeatures` | 133/133 PASS (post-6c baseline) | … | ✅ / ❌ |
| `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build` | BUILD SUCCEEDED | … | ✅ |
| `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` | BUILD SUCCEEDED | … | ✅ |

**Failure handling:**
- Любой ❌ → **revert последний commit** (`git reset --hard HEAD~1` если изменения только в нём; иначе `git revert <SHA>` с follow-up fix-commit-ом).
- Если revert не возвращает green → `git bisect` между last known green commit и current HEAD (Pitfall 6 mitigation).
- После fix-on-top — повторить full gate. **Никаких amend** на existing commit (Phase 6c lesson, delegator.md git safety).

**Pre-wave checkpoint:** перед стартом любой fix-task `swift test` MUST be 133/133. Если current main 132/133 — STOP, fix existing failures **перед** добавлением new.

---

## Verbatim section 2 — Atomic commit policy (Role I в PATTERNS + RESEARCH Pitfall 5)

> Phase 6c использовала pattern «one logical fix = one commit». Phase 6d **наследует** этот pattern для HIGH severity, но **расширяет** правилом cluster-bundling для cosmetic / LOW.

### Правило 1 — HIGH severity

**One finding = one commit.** Commit message:

```
<type>(06d-<wave>): <one-line goal>

- <bullet 1: что изменилось>
- <bullet 2: почему>
- ...

closes F-XX
ref: 06D-FINDINGS.md F-XX
```

Где `<type>` — `fix` (correctness bug), `perf` (perceptible perf improvement), `refactor` (structural без поведения), `chore` (dead code / cleanup).

Пример:
```
perf(06d-03): defer SwiftDataContainer.makeShared() to background Task in onAppear

- Move makeShared() out of BBTB_iOSApp.init() into Task { @MainActor } in onAppear.
- ConfigImporter init теперь awaits container availability instead of synchronous.
- Reduces App.init body time by ~120ms (Instruments median).

closes F-001
ref: 06D-FINDINGS.md F-001
```

### Правило 2 — MEDIUM / LOW bundle by same-file same-theme

**Multiple findings in same file/theme = ONE commit** (Pitfall 5 в RESEARCH).

Пример:
```
chore(06d-03): cleanup dead code in ConfigImporter.swift (12 items)

Удалены:
- `parseLegacyVMess` (lines 234-267, not referenced since Phase 4 D-08 cutover)
- `legacyTLSDefaults` (lines 312-325, replaced by VPNCore.TLSDefaults)
- ... (10 more items)

Total lines removed: -187.

closes F-012, F-013, F-014, F-015, F-016, F-017, F-018, F-019, F-020, F-021, F-022, F-023
ref: 06D-FINDINGS.md theme "Dead code in ConfigImporter"
```

### Правило 3 — никогда `--no-verify`, никогда `--amend` (delegator.md git safety)

- Все pre-commit hooks выполняются (если они есть).
- При regression на commit — fix-on-top **новым** commit (хоть с одной строкой), никогда amend.

### Правило 4 — никаких массовых рефакторов в одном commit

Если single «logical fix» затрагивает >5 файлов — это сигнал, что fix должен быть **split** на несколько commits по подсистемам. См. CLAUDE.md C-05 (scalable solutions).

---

## Verbatim section 3 — D-09 Phase 6c invariant guard (Shared 3 в PATTERNS)

> **Это критическая секция.** Любая fix-task, которая ломает D-09 invariant — **STOP**, escalate to user. Не «попробовать обойти», не «частично»; полный STOP.

### Защищаемые инварианты (verbatim из CONTEXT.md D-09)

1. **`TunnelController.handleStatusChange` intent-closing path UNCHANGED.**
   Проверка: `git diff <commit> -- BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` — ни одной diff-строки в функции `handleStatusChange`, либо изменение явно согласовано с user в CHECKPOINT.

2. **No XPC в NEVPNStatusDidChange observer hot path.**
   Проверка: `grep -rn "loadAllFromPreferences\|loadFromPreferences" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` — count не должен расти; если new occurrence, ground в NOT-observer path (handleForeground OK, observer body — STOP).

3. **No reintroduction `ReconnectStateMachine` / `NetworkReachability` / custom retry loops.**
   Forbidden symbols grep:
   ```bash
   cd BBTB/Packages/AppFeatures/Sources
   grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay\|triggerRecoveryIfNeeded\|lastKnownStatus" . | awk '!/^[[:space:]]*\/\//' | wc -l
   ```
   Pre-wave baseline: 7 (Phase 6c carve-out — `connectInProgress` / `manualDisconnectInProgress` matches). Post-fix: 7 или меньше; **никогда больше**.

4. **`applyVPNStatus(_:connectedDate:)` остаётся SINGLE authority для `state` + `reconnectBannerState`.**
   Проверка: `grep -n "self.state = " BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — count assignments to `self.state` извне `applyVPNStatus` функции должен оставаться baseline (только init + applyVPNStatus body).

5. **Sliding session window invariant: `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.**
   Проверка: `grep -n "isOnDemandEnabled = " BBTB/Packages/AppFeatures/Sources/MainScreenFeature/*.swift` — все assignments должны conform этому pattern.

### Дополнительные memory-derived invariants (PATTERNS Shared 3)

6. **Observer queue `nil` (НЕ `.main`).**
   Проверка: `grep -rn "NEVPNStatusDidChange.*queue:.*\.main\)\|NEVPNStatusDidChange.*queue:.*OperationQueue.main" BBTB/Packages/AppFeatures/Sources/` — должно быть 0.

7. **Никаких `#Predicate` с optional UUID.**
   Проверка: `grep -rn "#Predicate.*UUID?" BBTB/Packages/` — должно быть 0.

### STOP-сценарий

Если **любая** fix-task triggered violation:
1. **STOP** — не коммитить.
2. **Revert** изменения если уже staged (`git checkout -- <file>`).
3. **Document** в `06D-INCIDENT-LOG.md` (создать если не существует): дата, finding ID, какой invariant, какие изменения были предложены.
4. **Escalate user**: показать violation + предложить варианты:
   - Drop finding (mark in 06D-FINDINGS.md «Dropped post-CHECKPOINT — invariant violation»).
   - Modify fix approach так, чтобы invariant не ломался (запросить новый brainstorm).
   - User explicit override (редко; требует обоснования и записи в decision log).

---

## Verbatim section 4 — Grep-audit checklist (Role H в PATTERNS)

> Запускается **до** и **после** каждой fix-task. Phase 6c B-08 inheritance.

```bash
# 1. Forbidden symbols (Phase 6c invariant)
cd BBTB/Packages/AppFeatures/Sources
FORBIDDEN_COUNT=$(grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay\|triggerRecoveryIfNeeded\|lastKnownStatus" . | awk '!/^[[:space:]]*\/\//' | wc -l | tr -d ' ')
echo "Forbidden symbol matches: $FORBIDDEN_COUNT (baseline 7 — carve-out only)"
# Должно быть ≤ 7

# 2. NEVPN observer queue (memory feedback_nevpn_observer_queue_main.md)
QUEUE_MAIN_COUNT=$(grep -rn "NEVPNStatusDidChange.*queue:.*\.main\)\|NEVPNStatusDidChange.*queue:.*OperationQueue.main" . | wc -l | tr -d ' ')
echo "NEVPN observer queue=.main matches: $QUEUE_MAIN_COUNT"
# Должно быть 0

# 3. XPC в hot path (Phase 6c invariant)
cd BBTB
XPC_HOTPATH_COUNT=$(grep -rn "loadAllFromPreferences\|loadFromPreferences" Packages/AppFeatures/Sources/MainScreenFeature/ | wc -l | tr -d ' ')
echo "loadAll/From-Preferences hot-path matches: $XPC_HOTPATH_COUNT (baseline TBD — capture в Wave 06D-02a PREFLIGHT)"
# Должно быть ≤ baseline

# 4. SwiftData #Predicate UUID? (memory feedback_swiftdata_uuid_predicate.md)
cd /Users/vergevsky/ClaudeProjects/VPN
PREDICATE_UUID_COUNT=$(grep -rn "#Predicate.*UUID?\|Predicate.*: UUID?" BBTB/Packages/ | wc -l | tr -d ' ')
echo "#Predicate UUID? matches: $PREDICATE_UUID_COUNT"
# Должно быть 0

# 5. OSSignposter инъекции (preserved from Wave 06D-02a Commit 2)
SIGNPOST_COUNT=$(grep -rn "OSSignposter\|signpostID\|beginInterval\|endInterval" BBTB --include="*.swift" | wc -l | tr -d ' ')
echo "OSSignposter usages: $SIGNPOST_COUNT (baseline установлен в Wave 06D-02a — capture в PREFLIGHT)"
# Должно быть ≥ baseline (никаких удалений инъекций без user signal в CHECKPOINT)
```

Записать в `06D-NN-SUMMARY.md` per task:

| Grep | Pre-fix count | Post-fix count | Status |
|---|---|---|---|
| Forbidden symbols (carve-out=7) | … | … | ✅ ≤ 7 |
| Observer queue=.main | 0 | 0 | ✅ |
| XPC in hot path | … | ≤ pre | ✅ |
| #Predicate UUID? | 0 | 0 | ✅ |
| OSSignposter usages | … | ≥ pre | ✅ |

---

## Verbatim section 5 — Materialization protocol (для orchestrator)

> Эта секция — instructions для orchestrator при materialization template-плана после CHECKPOINT 1 signal.

**Если signal = `option-a` (HIGH only):**
- Создать tasks per HIGH finding (1 task per finding, или bundle если same-file).
- Maximum 2-3 tasks per materialized plan (per-plan context budget per planner rules).
- Если HIGH findings > 3 → split на `06D-03a-PLAN.md`, `06D-03b-PLAN.md`, … (одна wave на sub-plan).
- Verbatim sections 1-4 копируются в каждый sub-plan body.

**Если signal = `option-b` (HIGH + MEDIUM):**
- HIGH tasks как Option A.
- MEDIUM tasks — bundle same-theme в один task (Pitfall 5 grouping); per-theme 1 task.
- Likely 2-4 fix-waves total (06D-03a, 06D-03b, ...).

**Если signal = `option-c` (HIGH + MEDIUM + selected LOW themes):**
- HIGH + MEDIUM как Option B.
- Selected LOW themes — bundled per theme, 1 commit per theme (`chore(06d-NN): cleanup <theme> (N items)`).
- Likely 3-6 fix-waves total.

**Если signal = `option-custom: <list>`:**
- Map specified finding IDs → tasks per finding (или bundled per theme).
- Если custom mix предлагает >6 fix-waves — escalate user (warning: больше budget чем Option C).

**Common к всем options (MANDATORY clauses per checker BLOCKER #3):**

- Каждый materialized task имеет `<read_first>` (минимум: target file + 06D-FINDINGS.md + 06D-CONTEXT.md + 06D-RESEARCH.md).
- Каждый имеет `<action>` с concrete file paths + function names + line ranges + recommended fix verbatim из FINDINGS.
- `<verify>` блок включает full regression gate из Verbatim section 1.
- `<done>` ссылается на closing finding IDs.

- **`<acceptance_criteria>` clause (BLOCKER #3 fix):** Каждый materialized task **MUST** include `<acceptance_criteria>` block с **per-finding** success criteria, **в дополнение** к generic regression gate verify block. Criteria должны быть объективно-проверяемыми:
  - file:line grep matches (presence or absence) — например `grep -q "Task { @MainActor }" BBTB/App/iOSApp/BBTB_iOSApp.swift`.
  - Instruments span timing thresholds — например `ColdLaunch span post-fix median < 80% pre-fix median` (cross-ref в post-fix Wave 06D-Final-a).
  - Test command exit codes — например `swift test --filter ConfigImporterTests.testParseLegacyURIRemoved 2>&1 | grep -q "0 failures"`.
  - Build-output assertions — например `xcodebuild ... 2>&1 | grep -q "BUILD SUCCEEDED"`.

- **`D-09 invariant pre-check` clause (BLOCKER #3 fix — sensitive files):** Если materialized task касается **любого** из SENSITIVE FILES ниже, task body **MUST** include inline 'D-09 invariant pre-check' step, который grep-verifies 5 invariants ДО внесения изменений:

  **SENSITIVE FILES list:**
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`
  - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`
  - `BBTB/App/iOSApp/BBTB_iOSApp.swift`
  - `BBTB/App/macOSApp/BBTB_macOSApp.swift`
  - `BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`
  - `BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`

  **5 invariants verified (D-09):**
  1. `handleStatusChange` path UNCHANGED (verify by `git diff` показывает 0 строк в этой функции).
  2. No XPC в `NEVPNStatusDidChange` observer (verify by `grep -rn "loadAllFromPreferences\|loadFromPreferences"` в observer scope = 0 новых).
  3. No `ReconnectStateMachine` / `NetworkReachability` / `ReconnectStateObserverRelay` references (verify forbidden grep ≤ 7 carve-out).
  4. `applyVPNStatus` single authority preserved (verify `self.state = ` extramural counts стабилен).
  5. Sliding session window invariant preserved (verify `isOnDemandEnabled = autoReconnectToggle && userIntendedConnected` pattern).

  Эти проверки запускаются **в task body перед** внесением changes; если хоть одна не PASS — STOP (per Verbatim section 3 STOP-сценарий).

**Pre-flight перед стартом Wave 06D-03 (или 03a):**
- `swift test --package-path BBTB/Packages/AppFeatures` должен быть 133/133 PASS на текущем main.
- `06D-FINDINGS.md` — exists, заполнен, имеет finding IDs.
- `06D-FINDINGS-SUMMARY.md` — exists, contains budget options.
- User signal — recorded в `06D-03-CHECKPOINT-DECISION.md` (orchestrator создаёт после signal).

---

<tasks>

<task type="placeholder">
  <name>Task 1 — TBD post-CHECKPOINT 1</name>
  <files>TBD после CHECKPOINT 1 signal — конкретные пути materialized из выбранных finding IDs.</files>
  <read_first>
    Базовый набор для каждой materialized task (orchestrator добавит file-specific):
    - .planning/phases/06d-performance-audit/06D-FINDINGS.md (текущая finding row для этой task)
    - .planning/phases/06d-performance-audit/06D-CONTEXT.md (D-09 invariants reminder)
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (relevant Pattern / Pitfall секции)
    - Target source file(s) per finding location.
  </read_first>
  <action>
    Placeholder — orchestrator материализует concrete action после CHECKPOINT 1 signal. Action будет содержать:
    - Concrete file paths + function names + line ranges.
    - Recommended fix verbatim из `06D-FINDINGS.md` finding row.
    - D-09 invariant check (если затрагивает потенциально protected area — explicit verification что не нарушает).
    - Atomic commit message template (one finding = one commit, либо bundled per theme).

    ## Materialization invariants

    Orchestrator при materialization этой task MUST добавить:

    1. **Per-finding `<acceptance_criteria>` block** с объективно-проверяемыми критериями:
       - grep matches (presence/absence) на конкретные file:line patterns.
       - Instruments span timing thresholds (если применимо).
       - test command exit codes.
       - build-output assertions.
       (См. Verbatim section 5 «Common к всем options» — clause `<acceptance_criteria>` clause).

    2. **D-09 invariant pre-check step** (inline в `<action>` body) — если materialized task касается любого SENSITIVE FILE:
       - TunnelController.swift, MainScreenViewModel.swift, BBTB_iOSApp.swift, BBTB_macOSApp.swift, PacketTunnelProvider*.swift.
       - 5 invariants verified BEFORE making changes (handleStatusChange unchanged / no XPC observer / no RSM/NetReach / applyVPNStatus authority / sliding window).
       (См. Verbatim section 5 «D-09 invariant pre-check» clause + Verbatim section 3 STOP-сценарий).

    3. Generic regression gate (`<verify>` block) — из Verbatim section 1.
  </action>
  <verify>
    <automated>
      # Placeholder verify — materialization добавит finding-specific check + regression gate.
      # Базовая часть (всегда применяется):
      swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "133/133|all tests passed|0 failures" \
        && xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build 2>&1 | grep -q "BUILD SUCCEEDED" \
        && xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build 2>&1 | grep -q "BUILD SUCCEEDED"
    </automated>
  </verify>
  <done>
    Placeholder — orchestrator overwrites после CHECKPOINT 1 signal. Materialized done будет: «F-XX closed (commit SHA), regression gate green, grep audit row added to summary, acceptance_criteria PASS, D-09 pre-check PASS (если сенситивный файл)».
  </done>
</task>

<task type="placeholder">
  <name>Task 2 — TBD post-CHECKPOINT 1</name>
  <files>TBD</files>
  <read_first>Базовый набор (см. Task 1).</read_first>
  <action>
    Placeholder — materialized после CHECKPOINT 1.

    ## Materialization invariants

    Orchestrator при materialization этой task MUST добавить:
    1. Per-finding `<acceptance_criteria>` block (BLOCKER #3 — Verbatim section 5).
    2. D-09 invariant pre-check step inline в `<action>` если касается SENSITIVE FILE (BLOCKER #3 — Verbatim section 5).
    3. Generic regression gate (`<verify>` — Verbatim section 1).
  </action>
  <verify>
    <automated>
      swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "133/133|all tests passed|0 failures"
    </automated>
  </verify>
  <done>Placeholder.</done>
</task>

<task type="placeholder">
  <name>Task 3 — TBD post-CHECKPOINT 1 (если применимо к budget)</name>
  <files>TBD</files>
  <read_first>Базовый набор (см. Task 1).</read_first>
  <action>
    Placeholder. NB: per planner rules — max 2-3 tasks per plan. Если >3 tasks required по выбранному бюджету, orchestrator должен создать sub-plans 06D-03a / 06D-03b / … вместо overwriting текущего файла.

    ## Materialization invariants

    Orchestrator при materialization этой task MUST добавить:
    1. Per-finding `<acceptance_criteria>` block (BLOCKER #3 — Verbatim section 5).
    2. D-09 invariant pre-check step inline в `<action>` если касается SENSITIVE FILE (BLOCKER #3 — Verbatim section 5).
    3. Generic regression gate (`<verify>` — Verbatim section 1).
  </action>
  <verify>
    <automated>
      swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "133/133|all tests passed|0 failures"
    </automated>
  </verify>
  <done>Placeholder.</done>
</task>

</tasks>

<verification>

**Template-level acceptance:**

1. Этот файл — TEMPLATE; materialized concrete plan(s) либо overwriting либо как sub-plans 06D-03a/03b/….
2. После materialization каждая concrete fix-task проходит:
   - Regression gate D-08 (Verbatim section 1).
   - Atomic commit policy (Verbatim section 2).
   - D-09 invariant guard (Verbatim section 3) — без violations.
   - Grep audit (Verbatim section 4) — counts within baseline.
   - Per-finding `<acceptance_criteria>` PASS (Verbatim section 5 «Common к всем options»).
   - D-09 invariant pre-check (Verbatim section 5 «sensitive files» clause) если касается SENSITIVE FILE.
3. Поверка по итогам всей Wave 06D-03 (или серии 03a/03b/…):
   - Все selected findings (per CHECKPOINT 1 signal) — `[Closed]` в 06D-FINDINGS.md со ссылкой на commit SHA.
   - Carved findings — `[Deferred to Phase X]` явно записаны.
   - `06D-NN-SUMMARY.md` per wave с commit list + verification metrics + grep audit table + acceptance_criteria PASS table.

</verification>

<success_criteria>

- [ ] Этот template остаётся `autonomous: false` до прихода CHECKPOINT 1 signal.
- [ ] После signal materialized в concrete tasks (либо overwriting body, либо sub-plans 06D-03a/03b/…).
- [ ] Verbatim sections 1-5 копируются в КАЖДУЮ materialized fix-plan body без изменений.
- [ ] Каждая materialized task имеет полный `<read_first>` / `<action>` / `<verify>` / `<acceptance_criteria>` / `<done>`.
- [ ] Sensitive-file tasks имеют inline D-09 invariant pre-check step.
- [ ] AppFeatures 133/133 + iOS + macOS xcodebuild — green между КАЖДЫМ atomic commit.
- [ ] D-09 invariants preserved (forbidden symbol grep ≤ 7; observer queue=.main = 0; #Predicate UUID? = 0).
- [ ] Все closed findings отражены в 06D-FINDINGS.md со ссылками на commit SHA.

</success_criteria>

<output>
Materialization — orchestrator responsibility. После CHECKPOINT 1 signal:
1. Orchestrator overwrites этот body конкретными task-ами (или создаёт sub-plans 06D-03a/03b/…).
2. Каждая materialized plan создаёт свой `06D-NN-SUMMARY.md` с commit SHA list + regression gate result + grep audit table + per-finding acceptance_criteria PASS table.
3. После закрытия всех selected findings — `gsd-plan-phase` либо orchestrator переходит к Wave 06D-Final-a (post-fix Instruments + comparison) → Wave 06D-Final-b (UAT + wiki + closure).
</output>
</content>
</invoke>