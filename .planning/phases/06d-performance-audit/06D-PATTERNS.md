# Phase 6d: Performance & Code Quality Audit — Pattern Map

**Mapped:** 2026-05-14
**Files analyzed:** 0 new feature-code files / ~5 candidate signpost-injection sites / 8 markdown artifact roles / 1 wiki page / 1 wave-plan series / N fix-cycle commits (decomposition TBD post-checkpoint)
**Analogs found:** all roles have concrete in-tree analogs (Phase 6c-derived) — no "no-analog" rows

> Phase 6d **не** создаёт новых feature-файлов. Это process-heavy фаза, где «file:role:analog» матрица не помогает напрямую. Вместо неё ниже — карта **ролей** (markdown-артефакт, signpost-инъекция, wave-план, atomic-commit) с конкретными excerpts из существующих Phase 6c артефактов, которые надо копировать verbatim.
>
> Источник правды по содержимому: `06D-CONTEXT.md` (D-01..D-11b) + `06D-RESEARCH.md` (Wave 0 prescriptive guidance). Этот файл — *только* про то, **какие существующие куски кода и markdown надо взять за образец**.

---

## Role Classification (Phase 6d артефакты и инъекции)

| Артефакт / Injection | Роль | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `06D-01-PLAN.md` (audit briefing + 3 parallel passes) | wave-plan markdown | document → 3 audit AI passes → markdown findings | `.planning/phases/06c-on-demand-migration/06C-01-PLAN.md` | exact (wave-plan) |
| `06D-02-PLAN.md` (synthesis + Instruments baseline) | wave-plan markdown | research output → synthesis + measurement | `.planning/phases/06c-on-demand-migration/06C-02-PLAN.md` | exact (wave-plan) |
| `06D-03..N-PLAN.md` (fix-cycle waves) | wave-plan markdown | findings → atomic commits + regression gate | `.planning/phases/06c-on-demand-migration/06C-04-PLAN.md` | exact (fix-cycle wave) |
| `06D-Final-PLAN.md` (post-fix Instruments + closure) | wave-plan markdown | post-fix measure → comparison → wiki sync | `.planning/phases/06c-on-demand-migration/06C-05-PLAN.md` | exact (closure wave) |
| `06D-FINDINGS-OPUS.md` | AI-pass output markdown | Opus internal context → markdown table | `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R2-INTERNAL.md` | role-match (single-AI review output) |
| `06D-FINDINGS-CODEX.md` | AI-pass output markdown | `mcp__codex__codex` (read-only) → markdown table | `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R2-CODEX.md` + `06C-REVIEWS-R3-CODEX.md` + `06C-ARCHITECT-R5.md` | exact (Codex peer review) |
| `06D-FINDINGS-GEMINI.md` | AI-pass output markdown | `mcp__gemini__gemini` (read-only) → markdown table | `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R3-GEMINI.md` | exact (Gemini peer review) |
| `06D-FINDINGS.md` (synthesis) | aggregated findings markdown | 3 AI outputs → dedup + severity + consensus columns | `.planning/phases/06c-on-demand-migration/06C-REVIEWS.md` (Round 2 reviewer roll-up) | role-match (multi-source synthesis) |
| `06D-REVISION-LOG.md` (если будут pivots) | append-only revision log | rounds of architecture change → chronological log | `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` (Rounds 1..6) | exact (revision log) |
| `06D-UAT.md` (regression smoke) | UAT result markdown | manual checks → pass/fail table | `.planning/phases/06c-on-demand-migration/06C-UAT.md` | exact (UAT result table) |
| `06D-SUMMARY.md` (closure record) | wave/phase closure markdown | all waves → consolidated record + verification metrics | `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md` (+ `06C-05-SUMMARY.md`) | exact (closure summary) |
| `baselines/cold-launch-iphone.md`, `connect-tap-iphone.md`, `energy-log.md`, `allocations.md` | Instruments trace summary markdown | `.trace` бинарник + Instruments numerical export → markdown table со span timings | **NEW pattern — no in-tree analog**. Closest neighbour: `wiki/auto-reconnect.md` (long-form measurement/decision log layout). | new-but-shaped-by-CLAUDE.md «Page format» |
| `wiki/performance-baseline.md` | wiki page (long-term memory) | pre-fix + post-fix measurements + decisions | `wiki/auto-reconnect.md` (long-form Phase 6c memory) | exact (wiki page format) |
| `OSSignposter`-инъекции в `BBTB_iOSApp.swift`, `BBTB_macOSApp.swift`, `TunnelController.swift`, `MainScreenViewModel.swift`, `ConfigImporter.swift` | signpost injection в hot path | code-level instrumentation, нет runtime semantics change | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift` (subsystem-scoped `Logger` enum) — pattern для shared `OSSignposter` namespace; ~15 существующих `Logger(subsystem: …, category: …)` deklarations (см. ниже) — pattern для subsystem naming. | role-match (existing OSLog usage → новый OSSignposter sibling) |
| Fix-cycle commits (06D-03..N) | atomic commit | one logical fix → one commit → regression gate | Phase 6c commits `19f3fe7` / `5b0e28c` / `69b8ae8` / `44a5630` (см. `06C-04-SUMMARY.md` header) | exact (atomic-commit-per-fix) |
| Regression gate (test + xcodebuild) между waves | verification step (CI-equivalent) | post-commit verification | `06C-04-SUMMARY.md` § "Verification metrics" — `swift test 133/133` + iOS Simulator xcodebuild + BBTB-macOS xcodebuild | exact (3-pronged green gate) |
| Grep-audit (forbidden symbols после Phase 6c) | verification step (file-level audit) | shell grep + awk-strip comments → count | `06C-04-SUMMARY.md` § "Verification metrics" row "Awk-stripped grep B-08" | exact (Phase 6c B-08 inheritance) |

**Conventions enforced (CLAUDE.md + delegator.md):**
- User-facing markdown (CONTEXT, PLAN, FINDINGS narrative секции, SUMMARY) — **на русском** (D-11).
- AI delegation prompts (Codex/Gemini briefs) — **на английском** (D-11a).
- Технические термины (`NEVPNStatusDidChange`, `TunnelController`, `applyVPNStatus`, `OSSignposter`) — **без перевода**, grep-able anchors (D-11b).
- Wiki page format — strict (header / Summary / Sources / Last updated / sections / Related pages) — см. CLAUDE.md «Page format».
- Atomic commits с reference на plan task — см. `06C-04-SUMMARY.md` commits column.

---

## Pattern Assignments (по ролям)

### Role A: Wave-plan markdown (`06D-01-PLAN.md` .. `06D-Final-PLAN.md`)

**Analog:** `.planning/phases/06c-on-demand-migration/06C-01-PLAN.md` (briefing wave, 32k) + `06C-04-PLAN.md` (fix-cycle wave, 86k) + `06C-05-PLAN.md` (closure wave, 26k).

**Что копировать:**
- Header (frontmatter с `phase / plan / type / status / date`) — pattern из `06C-04-SUMMARY.md` lines 1-19 (но `type: plan`, `status: in-progress` для plans).
- Структура: `## Goal` → `## Tasks` (нумерованные с file paths) → `## Verification` (acceptance gates) → `## Out of scope` → `## Open questions / Pending decisions`.
- Acceptance gate секция — verbatim формат из `06C-04-SUMMARY.md` § "Verification metrics" (см. ниже Role G).

**Concrete excerpt** — frontmatter pattern для нового plan:
```yaml
---
phase: 06d-performance-audit
plan: 01
type: plan
status: ready
date: 2026-05-14
---
```
(Source: `06C-04-SUMMARY.md` lines 1-19 — same layout, status field варьируется: `ready` → `in-progress` → `complete-pending-uat` → `closed`.)

**Plan task format** (excerpt, переносится 1:1):
- Каждая task имеет: номер, title, list of files-to-touch (absolute paths), acceptance criterion (boolean), test/verification command.
- Out-of-scope раздел в конце plan — копирует style `06C-CONTEXT.md` § "Deferred Ideas".

---

### Role B: Multi-AI delegation brief invocation (Wave 06D-01 fanout)

**Analog (primary):** `~/.claude/rules/delegator.md` (7-section format, mandatory) — already loaded in working memory; см. `06D-RESEARCH.md` lines 528-623 для готового skeleton.

**Analog (concrete Codex invocation):** `06C-REVIEWS-R2-CODEX.md`, `06C-REVIEWS-R3-CODEX.md`, `06C-ARCHITECT-R5.md` — три Codex pass'а Phase 6c, все через `mcp__codex__codex` в `sandbox: read-only`, single-shot. Synthesis в `06C-REVIEWS.md`.

**Analog (concrete Gemini invocation):** `06C-REVIEWS-R3-GEMINI.md` — Gemini Round 3 review, `sandbox: read-only`, single-shot. **NEW для Phase 6d:** fallback chain `gemini-3.1-pro-preview → deep-research-preview-04-2026 → gemini-3-pro-preview → gemini-3-flash-preview → gemini-2.5-pro` (D-03 + memory `feedback_gemini_fallback_chain.md`). Phase 6c Gemini pass *не* использовал fallback — Phase 6d **впервые** кодифицирует chain в plan.

**Что копировать verbatim:**
- 7-section structure (TASK / EXPECTED OUTCOME / CONTEXT / CONSTRAINTS / MUST DO / MUST NOT DO / OUTPUT FORMAT) — из `~/.claude/rules/delegator.md`.
- `sandbox: "read-only"` для все 3 audit passes (advisory mode — никаких изменений source).
- Notify-user line `Delegating to {Expert}: {one-line task}` перед каждой делегацией — из `delegator.md` step 4.

**Что меняется относительно Phase 6c:**
- Phase 6c делал Codex/Gemini как *single review* of конкретного plan / decision. Phase 6d делает **3 параллельных peer-reviews** одной кодовой базы с **identical brief** (D-03). Это новый pattern.
- Severity rubric (HIGH/MEDIUM/LOW + measurable thresholds — `>200ms` / `50-200ms` / `<50ms`) — кодифицируется впервые в Phase 6d (D-05a, `06D-RESEARCH.md` lines 539-545).
- 40-findings-per-pass cap (`06D-RESEARCH.md` line 545) — новый guardrail; Phase 6c не имел quota.

**Concrete brief skeleton:** см. `06D-RESEARCH.md` lines 528-623 (готовый текст, planner копирует в `06D-01-PLAN.md` task body).

---

### Role C: AI-pass output markdown (`06D-FINDINGS-{OPUS|CODEX|GEMINI}.md`)

**Analog (Codex output):** `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R2-CODEX.md` (5860 bytes) — пример output Codex-pass: исполнительное summary + список findings с severity и concrete file:line + recommended fix.

**Analog (Gemini output):** `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R3-GEMINI.md` (6774 bytes) — пример Gemini output, чуть более narrative-heavy чем Codex; структурно совместим.

**Analog (Opus output, через internal context):** `.planning/phases/06c-on-demand-migration/06C-REVIEWS-R2-INTERNAL.md` (15387 bytes) — наш собственный Round 2 internal review, demonstrates Opus output shape.

**Required structure (per `06D-RESEARCH.md` lines 616-622):**
```markdown
# Phase 6d Audit — {OPUS|CODEX|GEMINI} Pass

## 1. Executive summary
- bullet 1 (top pattern observed)
- ...
- (3–5 bullets total)

## 2. Findings table
| # | Title | Dimension | Severity | File:Line | Description | Recommended fix |
|---|---|---|---|---|---|---|
| 1 | … | Performance | HIGH | BBTB/App/iOSApp/BBTB_iOSApp.swift:38-50 | … | … |
| … |

## 3. Methodology
- What I read (paths)
- What I skipped, why
- Tools used

## Confidence per dimension
- Performance: HIGH/MEDIUM/LOW
- Energy: …
- Simplicity: …
- Memory: …
- Launch: …
Estimated pass duration: NN min.
```

**Output language note (D-11):** findings table column `Description` и `Recommended fix` могут быть на английском (AI outputs более точны на английском), но **synthesis** (`06D-FINDINGS.md`) — на русском с английскими code anchors.

---

### Role D: Synthesis markdown (`06D-FINDINGS.md`)

**Analog:** `.planning/phases/06c-on-demand-migration/06C-REVIEWS.md` (9124 bytes) — Phase 6c Round 2 reviewer roll-up: consolidated table из internal+Codex+(потом)Gemini, с дедупликацией и приоритезацией.

**Что копировать:**
- Table layout с колонками `# | Title | Dimension | Severity | File:Line | Description | Opus | Codex | Gemini | Consensus | Recommended fix` (D-04 explicit).
- Колонки Opus/Codex/Gemini — `[FOUND]` / `[NOT FOUND]`.
- Consensus column — `3/3 strong` / `2/3 moderate` / `1/3 unique-but-valuable` (D-04).
- Отдельная секция в конце `## Filtered findings` — что отвергнуто, why. Pattern из `06C-REVIEWS.md` (там были «Round 2 W-X warnings» + «closed items» секции — те же mechanics).
- Дедупликация rule из `06D-RESEARCH.md` lines 625-636 — «false uniqueness» (одинаковые finding'и с разными file:line — merge в один) + «invariant violation» (D-09 — drop, не downgrade).

**Concrete example finding row** (synthesis формат):
```markdown
| 3 | XPC в App.init blocks main thread | Performance | HIGH | BBTB/App/iOSApp/BBTB_iOSApp.swift:80-95 | NEVPNManager.loadAllFromPreferences sync trip в startReachability… | [FOUND] | [FOUND] | [NOT FOUND] | 2/3 moderate | Defer load to Task in onAppear, await before first connect tap |
```

---

### Role E: Revision-log markdown (`06D-REVISION-LOG.md` — optional, если будут architecture pivots)

**Analog:** `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` (49795 bytes, 6 rounds documented chronologically).

**Когда использовать:** только если в Phase 6d возникнет architecture pivot после findings (например, если 3 AI разойдутся в фундаментальной recommendation и потребуется architect-style escalation, как Phase 6c Round 5). При линейном проходе по checklist'у — не нужен.

**Что копировать:**
- Заголовок `## Round N — {Date} — {one-line title}`.
- Структура каждого round'а: «Trigger / Diagnosis / Decision / Impact on plan».
- Append-only — никогда не редактируем prior rounds.

---

### Role F: Wiki page `wiki/performance-baseline.md`

**Analog:** `wiki/auto-reconnect.md` (21464 bytes, Phase 6c long-term memory) — same shape: «Page format» из CLAUDE.md, Last updated, секции с конкретными решениями + measurements.

**Что копировать verbatim:**
- Header формат (lines 1-10 в `auto-reconnect.md` — заголовок, **Summary**, **Sources**, **Last updated**, `---` separator).
- Wiki-link стиль — `[[page-name]]` для cross-refs (CLAUDE.md правило).
- Sections по темам: «Cold start baseline (pre-fix)», «Cold start (post-fix)», «Connect tap baseline», «Energy», «Allocations», «Methodology», «Open follow-ups».
- В конце — `## Related pages` со списком связанных страниц (`[[auto-reconnect]]`, `[[architecture]]`, `[[tech-stack]]`, потенциально новые).

**Concrete excerpt** (header skeleton — копируется в новую страницу):
```markdown
# Performance baseline (Phase 6d)

**Summary**: Pre- и post-fix измерения cold start, connect tap, energy, allocations на iPhone iOS 26.5 и MacBook macOS Sequoia/Tahoe. Артефакты Phase 6d (2026-05).

**Sources**: `.planning/phases/06d-performance-audit/baselines/*.md`, Instruments .trace files (локально, не в git).

**Last updated**: 2026-05-NN.

---

…
```

---

### Role G: Regression gate (verification cells)

**Analog:** `06C-04-SUMMARY.md` § "Verification metrics" (lines 70-83) — таблица с тремя обязательными checks.

**Что копировать verbatim** (3-pronged green gate, executed после каждой fix-wave):

```bash
# 1) AppFeatures test suite — must be 133/133 PASS
swift test --package-path BBTB/Packages/AppFeatures

# 2) iOS Simulator build — must BUILD SUCCEEDED
xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB \
  -destination 'generic/platform=iOS Simulator' build

# 3) macOS build — must BUILD SUCCEEDED
xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS \
  -destination 'platform=macOS' build
```

**Verification row pattern** (copied 1:1 в каждый `06D-NN-SUMMARY.md`):
```markdown
| Check | Required | Actual | Status |
|---|---|---|---|
| `swift test --package-path BBTB/Packages/AppFeatures` | 133/133 PASS | … | ✅ / ❌ |
| `xcodebuild -scheme BBTB -destination 'generic/platform=iOS Simulator' build` | BUILD SUCCEEDED | … | ✅ |
| `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` | BUILD SUCCEEDED | … | ✅ |
```

---

### Role H: Grep-audit (forbidden-symbol verification)

**Analog:** `06C-04-SUMMARY.md` row "Awk-stripped grep B-08 (forbidden symbols)" — Phase 6c использовала awk-stripped grep чтобы выбросить single-line comments и проверить, что forbidden symbols (`ReconnectStateMachine`, `NetworkReachability`, `ReconnectStateObserverRelay`, `lastKnownStatus`, `wakePending`, `triggerRecoveryIfNeeded`) удалены.

**Concrete excerpt** (Phase 6c command, naturalised к Phase 6d):

```bash
# Phase 6c invariants — должно остаться зелёным:
cd BBTB/Packages/AppFeatures/Sources
grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay\|triggerRecoveryIfNeeded\|lastKnownStatus" . \
  | awk '!/^[[:space:]]*\/\//'
# Phase 6c established: 7 matches (Round 5 carve-out — connectInProgress, manualDisconnectInProgress).
# Phase 6d must NOT raise this count.
```

**Phase 6d-specific extensions** (новые forbidden patterns — добавляются в plan'ах):
- `\.main\)` в `NEVPNStatusDidChange` observer setup (queue: .main banned per memory `feedback_nevpn_observer_queue_main.md`).
- `loadAllFromPreferences` count в hot paths (Phase 6c reduced to минимум; каждое новое добавление — suspect).
- `#Predicate.*UUID` (banned per memory `feedback_swiftdata_uuid_predicate.md`).

---

### Role I: Atomic-commit pattern (fix-cycle waves 06D-03..N)

**Analog:** Phase 6c commits в `06C-04-SUMMARY.md` frontmatter (lines 7-17):
- `19f3fe7 — Task 3a slim + intent-closing`
- `5b0e28c — Task 3b reactive UI driver + banner trim + watchdog observer`
- `69b8ae8 — Task 3c delete 5 files + new TunnelControllerTests`
- `44a5630 — Round 6 re-UAT follow-up (VM foreground resync + connectedDate authority)`

**Pattern** (verbatim из Phase 6c):
1. Один logically-coherent fix = один commit.
2. Commit message формат: `{type}({plan-ref}): {one-line goal}` — например `perf(06D-03): defer SwiftData container init to onAppear`.
3. Commit body — bullet-list изменений + reference на finding ID из `06D-FINDINGS.md`.
4. После commit — запустить regression gate (Role G). Если падает — fix-on-top **в новом commit** (не amend). Это правило из delegator.md и CLAUDE.md «git safety protocol».

**Что меняется относительно Phase 6c:**
- Phase 6c имела ~24-30 commits в 4 waves. Phase 6d может иметь больше (зависит от findings volume и budget decision после CHECKPOINT). `06D-RESEARCH.md` § "Pitfall 5: Atomic-commit churn" предупреждает про risk и предлагает grouping (one wave = logically related group, не one finding = one commit).

---

### Role J: OSSignposter injection (Wave 0 gap — `06D-RESEARCH.md` § 1369-1397)

**Analog:** существующий subsystem-scoped Logger enum в `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift` (12 lines) — pattern для shared namespace.

**Concrete excerpt** (TunnelLogger.swift, lines 7-12, copied verbatim для shape):
```swift
public enum TunnelLogger {
    public static let general = Logger(subsystem: "app.bbtb.tunnel", category: "general")
    public static let lifecycle = Logger(subsystem: "app.bbtb.tunnel", category: "lifecycle")
    public static let libbox = Logger(subsystem: "app.bbtb.tunnel", category: "libbox")
    public static let security = Logger(subsystem: "app.bbtb.tunnel", category: "security")
}
```

**New for Phase 6d** — sibling enum, тот же shape, но `OSSignposter`:
```swift
// Source pattern: TunnelLogger above + 06D-RESEARCH.md Example 1 (lines 1124-1160)
import os.signpost

public enum PerfSignposter {
    public static let app = OSSignposter(subsystem: "app.bbtb.client.ios", category: "performance")
    public static let tunnel = OSSignposter(subsystem: "app.bbtb.tunnel", category: "performance")
}
```

**Subsystem naming convention** — копирует существующий codebase (verified through grep):
- `app.bbtb.client.ios` (host app, diag) — used in `BBTB_iOSApp.swift:30`.
- `app.bbtb.tunnel` (extension) — used in `TunnelLogger.swift`.
- `app.bbtb.client` (shared client logic) — used in `TunnelController.swift:69`, `TunnelWatchdog.swift:57`, `FailoverProvider.swift:71`.
- `app.bbtb.server-list` — `ServerListViewModel.swift:47`, `ServerDetailViewModel.swift:35`.
- `app.bbtb.subscription-merge` — `SubscriptionMergeService.swift:25`.
- `app.bbtb.server-probe` — `ServerProbeService.swift:31`.
- `app.bbtb.app` — `CrashReporter.swift:18`.

→ Для Phase 6d **performance** category добавляется как новый sibling к `general/lifecycle/libbox/security`. Subsystem остаётся прежним, чтобы Instruments фильтрация работала consistent.

**Injection sites (per `06D-RESEARCH.md` Wave 0 prescription):**
- `BBTB/App/iOSApp/BBTB_iOSApp.swift:22` (init begin) → `MainScreenView.onAppear` (first frame end) — span `ColdLaunch`. Existing imports уже включают `OSLog` (line 15); добавить `import os.signpost`.
- `BBTB/App/macOSApp/BBTB_macOSApp.swift` — symmetric.
- `TunnelController.swift` `performToggleImpl` — span `ConnectTap` + nested `PreConnectProbe` + `ProvisionProfile`.
- `MainScreenViewModel.swift` — потенциально `applyVPNStatus` (если synthesis findings локализуют там lag).
- `ConfigImporter.swift` — потенциально `ImportFlow` span (если cold-start чек покажет, что ConfigImporter.init дорогой).

**Concrete code example** для injection: `06D-RESEARCH.md` lines 1124-1190 (Examples 1 + 2 — modern OSSignposter API, iOS 15+). Planner копирует verbatim.

**Naming convention для spans** (per `06D-RESEARCH.md` line 469): `ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`. PascalCase, no spaces — чтобы в Instruments timeline появлялись как human-readable lanes.

---

### Role K: Instruments trace summary markdown (`baselines/*.md`)

**Analog:** **NEW pattern — no in-tree analog**. Phase 1-6c не сохраняли Instruments measurements в markdown form.

**Closest neighbour:** layout страницы `wiki/auto-reconnect.md` — long-form measurement/decision log с numerical tables + reasoning. Copies из там:
- Header формат (CLAUDE.md «Page format»).
- Numerical tables («Pre-fix» vs «Post-fix» columns).
- Прямые цитаты из Instruments numerical export (Time Profiler "Heaviest stack trace" lanes, Energy Log Wh totals, Allocations retained-size).

**Mandated structure** (per `06D-CONTEXT.md` D-07c — текстовые summary + screenshots, без `.trace` бинарников):
```markdown
# Cold launch — iPhone iOS 26.5 (baseline)

**Summary**: Cold-launch Time Profiler trace, 5 samples, median selected.
**Date**: 2026-05-NN
**Device**: iPhone XX, iOS 26.5
**App version**: 0.6.2 (commit {SHA})

## Methodology
1. Force-quit BBTB, wait ≥10s.
2. Instruments → App Launch template → record.
3. Repeat × 5; sort by total span time; take median sample.

## Numerical summary
| Phase | Duration (median ms) | Notes |
|---|---|---|
| System interface init (purple) | … | dyld + Swift runtime |
| Static runtime init (purple) | … | framework init |
| App init (green) | … | BBTB_iOSApp.init body |
| Initial frame render (green) | … | SwiftUI first commit |
| **Total cold launch** | … | spawn → first interactive frame |

## Top heavy stack traces
1. {function} — {ms}, {context}
2. …

## OSSignposter spans (если уже добавлены)
| Span | Median ms |
|---|---|
| ColdLaunch | … |
```

**Что в комплект:**
- `cold-launch-iphone.md`
- `connect-tap-iphone.md`
- `energy-log-iphone.md`
- `allocations-iphone.md`
- (macOS counterparts, как secondary, тот же shape).

**Storage rule (D-07c):** `.trace` бинарники — НЕ в git (большие). Markdown summaries + screenshots ключевых spans → `.planning/phases/06d-performance-audit/baselines/`. Конечный «headline» переезжает в `wiki/performance-baseline.md`.

---

### Role L: UAT smoke markdown (`06D-UAT.md`)

**Analog:** `.planning/phases/06c-on-demand-migration/06C-UAT.md` (18369 bytes, 9 scenarios + result rows + critical/non-blocking annotation).

**Что копировать:**
- Table layout — `# | Scenario | Plat | Severity | First pass | Follow-up fix | Final`.
- Severity column values — `HARD BLOCKER` / `HARD BLOCKER (CRITICAL)` / `Non-blocking` (per `06C-UAT.md` + Round 2 B-10 hard-blocker set).
- Final-pass rows фиксируют commit SHA fix'а.

**Phase 6d UAT scope (per D-08, more limited чем 6c):**
- Regression smoke на всех 9 Phase 6c scenarios (A, B, C, D, E, F-direct, F-reverse, G, H, I + Settings-disable) — **один прогон** на iPhone iOS 26.5 после Wave Final.
- Не requires re-UAT на каждой fix-wave (между waves — только regression gate из Role G).
- Pitfall 5 (server-side kill) — может finally быть протестирован (отложен из Phase 6c) если фикс пайплайна позволит.

**Concrete excerpt** (header формат — из `06C-UAT.md` тёж):
```markdown
# Phase 6d UAT — Regression smoke

**Date**: 2026-05-NN
**Device**: iPhone XX iOS 26.5 + MacBook macOS X.Y
**App version**: 0.6.2 (commit {final SHA})

## Result table
| # | Scenario | Plat | Severity | Result | Notes |
|---|---|---|---|---|---|
| A | Wi-Fi ↔ LTE reconnect | iOS | HARD BLOCKER | ✅ | … |
…
```

---

### Role M: Phase closure summary (`06D-SUMMARY.md`)

**Analog:** `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md` (21717 bytes) + `06C-05-SUMMARY.md` (6532 bytes).

**Что копировать verbatim:**
- Frontmatter (lines 1-18) с `phase / plan / type / status / date / commits` list.
- Структура: `## Status` → `## What changed` (file change table) → `## Verification metrics` → `## Architecture confirmations` → `## Reference index` → `## Status` (final).
- Reference index секция (lines 161-167) — каждое решение D-NN / B-NN / W-NN получает one-line trace. Phase 6d наследует, но имена будут F-NN (findings), C-NN (commits), W-NN (waves).

---

## Shared Patterns (cross-cutting)

### Shared 1: User-facing language (CLAUDE.md + D-11)
**Source:** `CLAUDE.md` § Rules + `06D-CONTEXT.md` D-11/D-11a/D-11b.
**Apply to:** All markdown roles A, D, F, K, L, M.
**Rule:**
- Narrative / explanations / decisions — **на русском**.
- AI delegation prompts (Role B) — **на английском**.
- Code anchors (file paths, function names, type names, Instruments span names) — **без перевода**, grep-able.
- Простые объяснения для non-programmer audience (явное правило CLAUDE.md + user preference).

### Shared 2: Wiki sync cadence
**Source:** `CLAUDE.md` § Ingest workflow + § GSD Workflow «Синхронизация».
**Apply to:** Wave Final (всегда), Wave 06D-02 (initial baseline draft), любая фаза-wave которая принимает architectural решение.
**Rule:**
1. Создать/обновить `wiki/performance-baseline.md`.
2. Update `wiki/index.md` с link на новую страницу + one-line description.
3. Append entry в `wiki/log.md` с датой и summary.
4. Любое решение, валидное за пределами Phase 6d, переезжает в wiki — не остаётся только в `.planning/` (правило CLAUDE.md «Wiki — long-term memory»).

### Shared 3: Memory anti-pattern guard (D-09 invariants)
**Source:** `06D-CONTEXT.md` D-09 + memory files `feedback_nevpn_observer_queue_main.md` / `feedback_connectedDate_authority_for_since.md` / `feedback_nevpn_xpc_mach_port.md` / `feedback_swiftdata_uuid_predicate.md` / `feedback_failover_two_phase_init.md`.
**Apply to:** Role D (synthesis filter — Forbidden-finding categories из `06D-RESEARCH.md` lines 625-636).
**Rule:** Любое finding, предлагающее rollback Phase 6c invariant, **DROP** (не downgrade) + записать в секцию «Filtered — violates Phase 6c invariant» с обоснованием. Concrete invariants:
- `TunnelController.handleStatusChange` intent-closing UNCHANGED.
- No XPC в `NEVPNStatusDidChange` observer hot path.
- No reintroduction `ReconnectStateMachine` / `NetworkReachability` / custom retry loops.
- `applyVPNStatus(_:connectedDate:)` SINGLE authority for `state` + `reconnectBannerState`.
- Sliding session window invariant `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.
- Observer queue `nil` (НЕ `.main`).
- Никаких `#Predicate` с optional UUID.

### Shared 4: Delegator 7-section brief
**Source:** `~/.claude/rules/delegator.md` — mandatory format для любой делегации.
**Apply to:** Role B (Wave 06D-01 3 параллельных passes), любая sub-task делегация в fix-cycle waves (если будет).
**Rule:** TASK / EXPECTED OUTCOME / CONTEXT (3 fields) / CONSTRAINTS (3 fields) / MUST DO / MUST NOT DO / OUTPUT FORMAT — verbatim 7 секций. Single-shot stateless = full context каждый раз; multi-turn = `*-reply` с тем же `threadId` + accumulated error history.

### Shared 5: Gemini fallback chain (D-03 + memory)
**Source:** `06D-CONTEXT.md` D-03 + memory `feedback_gemini_fallback_chain.md` (recent, 2026-05-13).
**Apply to:** Role B Gemini invocation; любая Gemini делегация в Phase 6d.
**Rule:** `gemini-3.1-pro-preview` → `deep-research-preview-04-2026` → `gemini-3-pro-preview` → `gemini-3-flash-preview` → `gemini-2.5-pro`. Если все 5 → pause 5-10 мин → repeat. Если опять все 5 → задокументировать в `06D-FINDINGS.md` § «Gemini skipped — API unavailable» + продолжить с 2-pass synthesis (Opus + Codex). **NEW для Phase 6d** — Phase 6c не имела этого pattern.

### Shared 6: Atomic-commit + immediate regression gate
**Source:** Phase 6c commits + `delegator.md` git safety protocol + CLAUDE.md § GSD «качество > скорость».
**Apply to:** Role I (fix-cycle commits), Role G (regression gate).
**Rule:**
1. One logical fix = one commit.
2. Run regression gate (Role G) immediately после каждого commit.
3. Если fail — fix-on-top **в новом commit** (никаких amend).
4. Co-Authored-By trailer per CLAUDE.md / delegator pattern.

---

## NEW Patterns (introduced by Phase 6d — нет analog в codebase)

| Pattern | First introduced | Description |
|---|---|---|
| **Multi-AI peer-review with identical brief** | Phase 6d Wave 01 | 3 independent passes (Opus / Codex / Gemini) с identical 7-section brief; synthesis в один файл с per-AI `[FOUND]` колонками. Phase 6c делегировала single-purpose (review of конкретного plan), не parallel peer-review. |
| **40-findings-per-pass cap** | Phase 6d D-05a / brief | Quality-over-quantity quota; Phase 6c не имела. |
| **Severity rubric с numeric thresholds** | Phase 6d D-05a | `>200ms` / `50-200ms` / `<50ms` — кодифицировано впервые. Phase 6c severity была ad-hoc per architect review. |
| **Instruments trace summary в markdown** | Phase 6d Role K | Phase 1-6 не сохраняли measurements в structured markdown. baselines/*.md — новый артефакт class. |
| **`wiki/performance-baseline.md`** | Phase 6d Role F | Новая wiki page; copy shape из `wiki/auto-reconnect.md`. |
| **`OSSignposter`-based instrumentation** | Phase 6d Role J | Codebase уже имеет `Logger` (15+ usages) но **никакого** `OSSignposter` (grep returned empty). Phase 6d вводит pattern впервые. |
| **Synthesis-filter rule «Filtered — violates Phase 6c invariant»** | Phase 6d Role D | Codified guardrail против AI proposals откатить Phase 6c. |
| **Gemini fallback chain в plan** | Phase 6d Shared 5 | Memory feedback свежий (2026-05-13); Phase 6d кодифицирует в plan впервые. |
| **CHECKPOINT 1 (user budget decision после Wave 02)** | Phase 6d D-06 | User-gated decision на основе actual findings volume. Phase 6c не имела explicit checkpoint pattern (хотя de facto Round 5 architect decision сыграл аналогичную роль). |

---

## Anti-Patterns to Avoid (per `06D-CONTEXT.md` D-09 + `06D-RESEARCH.md` § Pitfalls)

| Anti-pattern | Why bad | Source |
|---|---|---|
| Reintroduce `ReconnectStateMachine` / `NetworkReachability` / `ReconnectStateObserverRelay` | Phase 6c invariant D-09; bug class 4 (Mach-port exhaustion) returns | `06D-CONTEXT.md` D-09; memory `feedback_nevpn_xpc_mach_port.md` |
| XPC (`loadAllFromPreferences`) внутри `NEVPNStatusDidChange` observer hot path | iOS 26 `EXC_RESOURCE` / `PORT_SPACE` crash; Phase 6c specifically fixed | D-09; memory `feedback_nevpn_xpc_mach_port.md` |
| Observer queue `.main` (vs `nil`) | Dropped notifications когда app suspended (Settings round-trip); Phase 6c Round 6 fixed | D-09; memory `feedback_nevpn_observer_queue_main.md` |
| `#Predicate { $0.optionalUUID == X }` | Тихо возвращает empty в SwiftData; реальный bug на device, незаметен в тестах | memory `feedback_swiftdata_uuid_predicate.md` |
| Synthesize finding `Date()` instead of `connection.connectedDate` для `since` | Timer обнуляется при foreground re-entry; Phase 6c bonus fix | memory `feedback_connectedDate_authority_for_since.md` |
| AI proposal: rewrite libbox / sing-box / gomobile binding | Out of scope D-02a; huge phase в своём праве | `06D-CONTEXT.md` D-02a |
| AI proposal: add new dependency как general refactor | D-02a; только с explicit user-impact justification | `06D-CONTEXT.md` D-02a |
| Atomic-commit churn (30+ commits для одной phase) | Pitfall 5 в `06D-RESEARCH.md` lines 1061-1073 — group findings в logical waves | `06D-RESEARCH.md` § Pitfalls |
| Pre-fix measurement становится post-fix baseline | Pitfall 3 — Instruments кеширует state; force-quit + ≥10s wait между samples mandatory | `06D-RESEARCH.md` § Pitfalls |
| Single-shot Codex/Gemini без full context | Stateless; каждый retry должен включать full error history + accumulated context per delegator.md | `~/.claude/rules/delegator.md` Retry section |
| Эмодзи в Codex / Gemini briefs или wiki | User preference + CLAUDE.md (emojis avoided unless requested) | Working memory + this prompt's role section |

---

## Metadata

**Analog search scope:**
- `.planning/phases/06c-on-demand-migration/*.md` (24 файла, всё Phase 6c artifacts)
- `wiki/*.md` (37 файлов; primary refs: `auto-reconnect.md`, `architecture.md`, `index.md`, `log.md`)
- `BBTB/Packages/**/*.swift` (grep для `Logger(` / `os_signpost` / `OSSignposter` — 16 `Logger` matches, 0 `OSSignposter` matches; Phase 6d **впервые** вводит сигнпостер)
- `~/.claude/rules/delegator.md` (7-section format + retry pattern)
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/*.md` (5 memory files cited в D-09 invariant list)
- `06D-CONTEXT.md`, `06D-RESEARCH.md` — Phase 6d upstream

**Files scanned:**
- Read in full: `06D-CONTEXT.md`, `06C-04-SUMMARY.md`, `BBTB/Packages/PacketTunnelKit/.../TunnelLogger.swift`, `BBTB/App/iOSApp/BBTB_iOSApp.swift` (header only).
- Read targeted ranges: `06D-RESEARCH.md` (lines 410-509, 520-637, 875-984, 1122-1260 — patterns + brief skeleton + Instruments + examples + state-of-art).
- Grep'd: `os_signpost / OSSignposter / Logger(` in `BBTB/**/*.swift`.
- Listed: `.planning/phases/06c-on-demand-migration/`, `wiki/`, `.planning/phases/`, `.planning/phases/06d-performance-audit/`.
- ROADMAP.md Phase 6d section (line 187-205) — confirmed.

**Pattern extraction date:** 2026-05-14.
