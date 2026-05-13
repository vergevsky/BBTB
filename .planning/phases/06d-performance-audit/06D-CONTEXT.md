# Phase 6d: Performance & Code Quality Audit — Context

**Gathered:** 2026-05-14 (discussion straddled midnight from 2026-05-13)
**Status:** Ready for planning

<domain>
## Phase Boundary

**Что Phase 6d делает:** cross-cutting multi-AI peer review нашей кодовой базы. Три независимых ревью-pass'а (Opus 4.7 / Codex GPT-5.2 / Gemini 3.1 Pro) с одинаковым брифом → синтез в одном файле findings → user checkpoint для бюджета фиксов → wave фиксов атомарными commit'ами → Instruments baseline + verification → closure.

**Что Phase 6d НЕ делает:**
- Никаких новых фич (никаких новых экранов, никаких новых API, никаких новых протоколов/транспортов).
- Не переписываем `libbox.xcframework` (gomobile binding — выходит за scope; profilling — да, переписывать — нет).
- Не делаем full re-UAT всего проекта (только regression smoke через swift test + iOS/macOS xcodebuild).
- Не закрываем NET-12 (active liveness probe — это отдельная backlog row для Phase 7-8, оставлено как есть).
- Не делаем UI redesign — только behavioral fixes (responsiveness / lag), если попадут в HIGH/MEDIUM findings.

**Версия:** v0.6.2 (patch). Phase 7 (Anti-DPI + WireGuard) стартует только после Phase 6d closure.

</domain>

<decisions>
## Implementation Decisions

### Focus / Symptoms (user pain points, 2026-05-13)

- **D-01: Primary audit targets — cold start + connect tap.** Пользователь сообщил, что приложение «тяжело грузится» начиная с Phase 5. Из 4 предложенных вариантов user выбрал именно эти два:
  - **Cold start path:** от тапа по иконке до появления рабочего MainScreen с пропрорисованными кнопками. Включает: AppDelegate/SceneDelegate init → ProtocolRegistry + TransportRegistry registration (5 + 5 handlers) → SwiftData container init (любые migrations при первом запуске) → ConfigImporter init → TunnelController init + `startReachability` (с initial `loadAllFromPreferences` XPC seed) → MainScreenViewModel init (с initial NEVPN seed XPC) → MainScreenView rendering.
  - **Connect tap path:** от тапа power-кнопки до финального статуса «Подключено» + тикающий таймер. Включает: `performToggleImpl` → pre-connect probe (параллельный TCP ко всем supported) → `provisionTunnelProfile` (SwiftData fetch + sing-box config build via PoolBuilder + saveToPreferences → XPC) → `tunnel.connect()` → `startVPNTunnel` → libbox launch внутри Packet Tunnel extension → 30-секундный polling loop до `.connected`.
- **D-01a:** Все findings и fixes должны trace'иться к одному из двух targets (или к косвенному улучшению — dead-code/simplicity, которое в свою очередь упрощает hot path или snizает binary size).

### Audit scope (code boundary)

- **D-02: Full scope.** Аудит покрывает:
  - **Все Swift packages:** AppFeatures (MainScreen + Settings + ServerList + ImportFlow + TunnelController + Watchdog + OnDemand machinery), VPNCore, ProtocolRegistry, TransportRegistry, ConfigParser, KillSwitch, PacketTunnelKit, 5 протокольных packages (VLESSReality, VLESSTLS, Trojan, Shadowsocks, Hysteria2), 5 транспортных handler'ов (TCP/WS/HTTP/HTTPUpgrade/gRPC), Localization, CrashReporter, DesignSystem, ServerListFeature, SettingsFeature.
  - **App entry points:** `BBTB/App/iOSApp/BBTB_iOSApp.swift`, `BBTB/App/macOSApp/BBTB_macOSApp.swift`, оба Packet Tunnel extensions, `BBTB/App/AppProxyExtension-macOS/AppProxyProvider.swift`.
  - **sing-box JSON templates:** 6 шаблонов в `BBTB/Packages/PacketTunnelKit/.../Templates/` (или wherever they live — researcher проверит). Влияют на libbox startup time, parse cost.
  - **Instruments profiling `libbox.xcframework` startup в Packet Tunnel extension process.** Мы НЕ переписываем gomobile binding, но Instruments traces (Time Profiler, Allocations) на PacketTunnelExtension process — да, чтобы знать где libbox жжёт время на старте.
- **D-02a: НЕ в scope:** перeписывание sing-box / libbox internals; замена backend (Rust sing-box, etc.); миграция с SwiftPM на другую build system; добавление новых dependencies (кроме случаев, когда replacement существующего даёт обоснованный win).

### AI participants & pass design

- **D-03: Три независимых peer-review passes с одинаковым брифом.**
  - **Opus 4.7** — этот thread (через Read / Bash / Agent с `subagent_type=Explore` для широких searches).
  - **Codex GPT-5.2** — через `mcp__codex__codex` в `sandbox: read-only`, single-shot или multi-turn если потребуется уточнение.
  - **Gemini 3.1 Pro** — через `mcp__gemini__gemini` в `sandbox: read-only`, single-shot.
  - Все трое получают **identical 7-section delegation brief** (по правилу `~/.claude/rules/delegator.md`) с включёнными: phase scope (D-01 / D-02), 5 audit dimensions (D-05), severity rubric (D-06 stub), findings output format, code locations to read.
- **D-04: Findings synthesis.** Single unified файл `06D-FINDINGS.md`. Каждое finding — строка с колонками: `# | Title | Dimension | Severity | File:Line | Description | Opus | Codex | Gemini | Consensus | Recommended fix`. Колонки Opus/Codex/Gemini = `[FOUND]` / `[NOT FOUND]`. Consensus = `3/3 strong` / `2/3 moderate` / `1/3 unique-but-valuable`. Я (Opus) делаю synthesis из 3 outputs после того, как все три pass'а завершились.

### Audit dimensions (Claude's discretion, with rationale)

- **D-05: Все 5 dimensions равновесомые a priori.** Severity (HIGH/MEDIUM/LOW) учитывает actual user impact, не a priori weight.
  - **Performance / responsiveness** — особенно cold start + connect tap (D-01).
  - **Energy consumption** — particularly на iPhone (Energy Log в Instruments).
  - **Code simplicity / deduplication / dead code** — снижает maintenance burden, often correlates с smaller binary.
  - **Memory footprint** — Allocations + retained-size, особенно если есть recurring leaks.
  - **Launch time** — overlaps с cold start, но focus на Process spawn → first frame.
- **D-05a:** Severity rubric (precise thresholds — будет уточнён в PLAN с конкретными числами):
  - **HIGH** — measurable user pain (`>200ms` perceived lag на cold start или connect tap), security/correctness concern, или active bug.
  - **MEDIUM** — measurable but sub-perception impact (`50-200ms`), maintenance debt с concrete cost, energy regression на typical session.
  - **LOW** — cosmetic / future-friction (`<50ms`), simplification без measurable user impact.

### Severity & end-condition

- **D-06: End-condition определяется после findings checkpoint.**
  - **Wave 1** — 3 parallel AI audit passes; outputs хранятся как `06D-FINDINGS-OPUS.md`, `06D-FINDINGS-CODEX.md`, `06D-FINDINGS-GEMINI.md`.
  - **Wave 2** — synthesis в `06D-FINDINGS.md` + Instruments baseline (`wiki/performance-baseline.md` initial draft с pre-fix traces). Подсчитываем сколько HIGH / MEDIUM / LOW.
  - **🛑 CHECKPOINT 1** — user reviews scale + decides budget: «закрыть все HIGH? + MEDIUM? + LOW?». На основе reality (5 HIGH + 20 MEDIUM + 50 LOW — другой бюджет, чем 1 HIGH + 3 MEDIUM + 8 LOW).
  - **Wave 3..N** — fix-cycle waves (одна wave = логически связанная группа фиксов или один большой фикс), атомарные commit'ы на каждый fix.
  - **Wave Final** — Instruments post-fix traces + comparison + `wiki/performance-baseline.md` final + `06D-UAT.md` + closure.

### Instruments measurement (Claude's discretion)

- **D-07: Real device — iPhone iOS 26.5.** Не Simulator (Energy Log требует real device). MacBook — secondary, traces на macOS Sequoia/Tahoe.
- **D-07a: Traces:**
  - **Time Profiler (cold launch):** process spawn → MainScreen interactive frame. На iPhone и MacBook отдельно.
  - **Time Profiler (connect tap):** power button tap → final status `.connected` + timer ticking. На iPhone.
  - **Energy Log:** idle 60s + connect tap window + 5min active session. На iPhone.
  - **Allocations (cold launch + import + connect):** retained-size growth across operations. На iPhone.
- **D-07b: Baseline:** pre-fix snapshot на текущем main (`c51b2ce` или successor). Сравнение pre-fix vs post-fix внутри Phase 6d. Phase 1 baseline недоступен (saved traces не существуют).
- **D-07c: Сохранение traces:** Instruments `.trace` файлы — большие бинарники, НЕ в git. Скриншоты ключевых spans + текстовые exports → `wiki/performance-baseline.md` + `.planning/phases/06d-performance-audit/baselines/` (markdown summaries, без `.trace`).

### Regression gate (architectural invariants)

- **D-08: AppFeatures swift test 133/133 + iOS Simulator xcodebuild + BBTB-macOS xcodebuild — все три green THROUGHOUT fix-cycle.** Между каждой fix-wave запускаем эти три. Любая регрессия → revert / fix-on-top перед следующей wave.
- **D-09: Phase 6c invariants preserved:**
  - `TunnelController.handleStatusChange` intent-closing path UNCHANGED.
  - No XPC в NEVPNStatusDidChange observer hot path.
  - No reintroduction `ReconnectStateMachine` / `NetworkReachability` / custom retry loops.
  - `applyVPNStatus(_:connectedDate:)` остаётся SINGLE authority для `state` + `reconnectBannerState`.
  - Sliding session window invariant `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.
- **D-09a:** Любая fix-wave, которая ломает D-09 invariant — STOP, escalate to user.

### Wave structure (preliminary)

- **D-10:** Phase 6d разбивается на минимум 4-5 waves:
  - **06D-01** — Audit briefing + 3 parallel passes. Output: `06D-FINDINGS-OPUS.md` + `06D-FINDINGS-CODEX.md` + `06D-FINDINGS-GEMINI.md` + initial `06D-FINDINGS.md` skeleton.
  - **06D-02** — Synthesis + Instruments baseline. Output: complete `06D-FINDINGS.md` + `wiki/performance-baseline.md` initial pre-fix draft.
  - **🛑 CHECKPOINT — user budget decision.**
  - **06D-03..N** — Fix-cycle waves. Каждая = логически связанная группа findings (например: «cold start XPC consolidation», «MainScreenViewModel init deduplication», «sing-box template inlining», «registry init lazy loading»).
  - **06D-Final** — Instruments post-fix + comparison + UAT smoke + closure docs.

### Communication

- **D-11: Все user-facing документы на русском** (по CLAUDE.md правилу + явный user preference). Findings descriptions, plan goals, summary explanations — на русском с простыми объяснениями (non-programmer audience).
- **D-11a: AI delegation prompts на английском** (стандарт для MCP servers, лучшее качество от моделей). Internal artifacts (FINDINGS, PLAN, SUMMARY) — на русском.
- **D-11b: Технические термины** (XPC, NEVPN*, SwiftData, Instruments span names, function names) — на английском без translation, потому что они grep'аются и matchаются к коду.

### Claude's Discretion

- Точный текст 7-section delegation brief для трёх audit passes — буду писать в `06D-01-PLAN.md`.
- Конкретные measurable thresholds для HIGH/MEDIUM/LOW severity (D-05a даёт стартовые значения, но финализируется в plan с учётом Instruments baseline).
- Wave 06D-03..N decomposition — зависит от actual findings (не известна сейчас; решаем после checkpoint).
- Instruments trace export format — текстовые summary в markdown с key span timings (не binary `.trace`).
- Когда и как делегировать конкретный fix к Codex / Gemini (если sub-task требует second opinion) — по правилам `~/.claude/rules/delegator.md`.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher / planner / executors / 3 audit AIs) MUST read these before planning / auditing / implementing.**

### Phase 6d source-of-truth

- `.planning/ROADMAP.md` §"Phase 6d (INSERTED 2026-05-13): Performance & Code Quality Audit" — phase goal + success criteria + version.
- `.planning/PROJECT.md` §"R18" — недавнее архитектурное решение Phase 6c (NEOnDemandRule + sliding session window + reactive UI). Аудит должен respect'ить эти инварианты.
- `.planning/STATE.md` — текущее состояние проекта (Phase 6c ✅ Closed, Phase 6d Active).

### Project-level reference

- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — source of truth для project goal, release roadmap, технологического стека. Аудит не нарушает этих ограничений.
- `CLAUDE.md` — project rules (русский язык, wiki как long-term memory, качество > скорость, simple explanations для non-programmer).
- `~/.claude/rules/delegator.md` — protocol для делегирования к Codex / Gemini через MCP (7-section brief, advisory vs implementation, retry policy).

### Recent architecture (Phase 6c baseline)

- `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md` — full record недавнего рефакторинга: TunnelController 909 → 316 строк, 5 файлов удалены, реактивный UI driver. Net code change −1300 строк в фазе 6c.
- `.planning/phases/06c-on-demand-migration/06C-UAT.md` — outcome Phase 6c (re-UAT PASS pair on iPhone iOS 26.5). Architectural invariants list (sliding window, no XPC in observer hot path).
- `wiki/auto-reconnect.md` — long-term запись Phase 6c решений (sliding window, reactive UI driver, VM foreground resync, connectedDate authority).
- `wiki/security-gaps.md` R18 — security-уровневое resoning Phase 6c.

### Memory (lessons that constrain Phase 6d behavior)

- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_observer_queue_main.md` — observer на NEVPNStatusDidChange должен быть `queue: nil`. Аудит должен не предлагать обратный rollback.
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_connectedDate_authority_for_since.md` — `state.connectionStart` authority order: NE-reported → sticky → `Date()`. Не trog'ать.
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_nevpn_xpc_mach_port.md` — никогда не делать XPC в NEVPNStatusDidChange observer hot path (iOS 26 EXC_RESOURCE/PORT_SPACE crash class).
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_swiftdata_uuid_predicate.md` — `#Predicate { $0.optionalUUID == X }` тихо возвращает empty; везде fetch-all + Swift filter. Audit может предложить вернуть `#Predicate` для perf — отвергаем.
- `~/.claude/projects/-Users-vergevsky-ClaudeProjects-VPN/memory/feedback_failover_two_phase_init.md` — actor-actor cycle late-binding pattern; не trog'ать без явного refactor рассуждения.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **Existing test suite:** AppFeatures 133/133 PASS, ~376 tests in adjacent packages (ConfigParser, TransportRegistry, VPNCore, etc.) — regression gate работает.
- **Build system:** Tuist-managed `Project.swift` + `Workspace.swift`; xcodebuild iOS Simulator + BBTB-macOS уже отлажены как quick verification.
- **MCP delegation infrastructure:** `mcp__codex__codex` + `mcp__gemini__gemini` готовы (Gemini auth = `gemini-api-key` confirmed 2026-05-13). 7-section brief шаблон в `~/.claude/rules/delegator.md`.
- **Wiki structure:** уже устоявшийся pattern (Page Format в CLAUDE.md). `wiki/performance-baseline.md` — новая страница, но pattern идентичен `wiki/auto-reconnect.md`.

### Established Patterns

- **Atomic commits per fix** — Phase 6c использовала этот pattern (Task 3a / 3b / 3c, Round 6 fix). Phase 6d наследует.
- **Multi-round revision log** (`06C-REVISION-LOG.md` Rounds 1-6) — Phase 6d может вести `06D-REVISION-LOG.md` если будут architecture pivots после findings.
- **Codex architect delegation** (`~/.claude/plugins/cache/jarrodwatts-claude-delegator/.../prompts/architect.md`) — pattern для делегации complex diagnoses. Phase 6d использует это **тройно** (Opus + Codex + Gemini независимо).
- **Round 2 B-08 awk-stripped grep audit** — Phase 6c использовала для verification отсутствия forbidden symbols. Phase 6d может ввести аналогичные grep audits для verification что dead code действительно удалён.

### Integration Points

- **Codebase locations affected by fixes:** `BBTB/App/iOSApp/BBTB_iOSApp.swift`, `BBTB/App/macOSApp/BBTB_macOSApp.swift`, любой файл в `BBTB/Packages/*/Sources/*` — потенциально. Каждый fix — атомарный commit с указанием Plan reference (06D-NN).
- **Test regression gate triggered:** после КАЖДОЙ fix-wave (между waves) — `swift test --package-path BBTB/Packages/AppFeatures` (must be 133/133) + `xcodebuild -project BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build` + `xcodebuild -project BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build`.
- **Wiki sync:** `wiki/performance-baseline.md` создаётся в 06D-02 (pre-fix traces) + обновляется в 06D-Final (post-fix comparison). `wiki/log.md` append-entry на каждом значимом milestone. `wiki/index.md` link на performance-baseline.

</code_context>

<specifics>
## Specific Ideas

- **«Качество > скорость»** (CLAUDE.md правило + явный user preference). При выборе между быстрым patch'ем и архитектурно правильным fix'ом — выбираем второе, даже если требует больше времени или multi-wave decomposition.
- **«Non-programmer audience»** — все user-facing документы (CONTEXT, PLAN, FINDINGS summary section, SUMMARY) должны быть understandable без CS background. Технические термины оставляем (XPC, NEVPN, etc. — это grep'абельные code anchors), но объяснения вокруг них — простые.
- **«Wiki — long-term memory»** (CLAUDE.md правило). Любое решение Phase 6d, которое валидно за пределами этой phase (например, «не делать XPC в Cold-start hot path», «sing-box template parse cost эстимировался X ms») — переезжает в wiki соответствующей страницей или дополняет существующую.
- **Round 2 B-10 hard-blocker pattern** — Phase 6d может ввести аналогичный contract: какие findings BLOCK closure (regression в Phase 6c invariants D-09 — всегда BLOCK), какие NON-BLOCKING (LOW severity без user impact).
- **Conservative bias:** аудит ищет actionable findings, не abstract beauty. «Этот код можно было бы написать в functional style» — NOT a finding если нет measurable user impact или maintenance cost reduction.

</specifics>

<deferred>
## Deferred Ideas

### Carry-over из STATE.md / Phase 6c backlog

- **Phase 11 follow-up** — empty-state UX issue после удаления VPN profile из iOS Settings; auto-recreate manager workaround. Не Phase 6d.
- **Phase 11 follow-up** — SocksProbe PID attribution UI. Не Phase 6d.
- **Phase 12 prerequisite** — Apple Distribution credentials. Не Phase 6d.
- **W2-05 iOS 16.1+ Apple-leak документация** — promote из 01-RESEARCH.md в FAQ. Не Phase 6d.

### Phase 7-8 backlog (отдельные phases)

- **NET-12: active liveness probe** (sing-box `Cmd_LogClient` polling или app-side HTTP ping). Phase 7-8.
- **macOS-specific UAT replay** Phase 6c scenarios A/F-reverse/Settings-disable/G на macOS отдельно. Если в Phase 6d аудит даст findings, влияющие на macOS pathway — fixes applies к обеим платформам, но отдельная macOS UAT — Phase 12 territory.

### Out of scope для Phase 6d (могут стать своими phases в будущем)

- **Замена `libbox.xcframework` на Rust sing-box или другой backend** — большой scope, нужна отдельная phase.
- **Миграция с SwiftPM на другую build system (Bazel, etc.)** — большой scope, не оправдан текущим pain.
- **Adding new dependencies для perf wins** (например, swap NSObjectProtocol notifications на Combine publishers) — допустимо только как часть конкретного fix'а с clear user-impact justification; не как general refactor.
- **UI redesign** — Phase 11 territory (Onboarding + UX polish).

### Reviewed but not folded

(Пока пусто — discussion stayed within scope thanks to scope_guardrail rules.)

</deferred>

---

*Phase: 06d-performance-audit*
*Context gathered: 2026-05-14 via discuss-phase default mode*
*Next: `/gsd-plan-phase 6d` to produce executable plans (likely 4-5 waves: 1 audit briefing + parallel passes, 2 synthesis + baseline, CHECKPOINT, 3..N fix-cycle, Final).*
