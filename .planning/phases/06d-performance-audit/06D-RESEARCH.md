# Phase 6d: Performance & Code Quality Audit — Research

**Researched:** 2026-05-14
**Domain:** Cross-cutting multi-AI peer-review audit (perf / energy / simplicity / memory / launch) + Instruments verification cycle на iOS+macOS Swift/SwiftUI/NetworkExtension stack.
**Confidence:** HIGH (большая часть базы — verified citations Apple/RAIL/Periphery; ASSUMED-маркеры явно перечислены в Assumptions Log)
**Researcher:** Claude Opus 4.7 (1M context)

---

## Summary

Phase 6d — это **operational research-and-fix phase**, не feature-добавка. Архитектура почти полностью зафиксирована в `06D-CONTEXT.md` (D-01..D-11b). Задача исследования — собрать **prescriptive playbook** для исполнителя планирования: точный шаблон делегационного брифа для трёх AI-pass-аутитов (Opus / Codex / Gemini), пошаговый рецепт Instruments-измерений на iPhone iOS 26.5 + MacBook macOS Sequoia/Tahoe (включая нетривиальный кейс attach Instruments к Packet Tunnel extension process), выбор инструментов для dead-code и cold-start анатомии SwiftUI+SwiftData+NetworkExtension стека.

**Главный риск фазы** (специфический для multi-AI peer review) — три AI-аутитора могут найти **одно и то же** под разными `file:line` и создать иллюзию уникальности; synthesis должен агрессивно дедупить, а также фильтровать findings, которые противоречат Phase 6c инвариантам D-09 (любой откат back к ReconnectStateMachine / XPC в hot path / single-authority breakdown).

**Главный архитектурный нюанс измерений** — Packet Tunnel extension это **отдельный процесс**, не часть host app; Instruments к нему attach'ится не через App Extensions list, а через **Running Applications list** [VERIFIED: Apple DTS Engineer Matt Eaton via developer.apple.com/forums/thread/654914]. Без этого нюанса измерение libbox startup внутри extension невозможно — researcher этот шаг прописывает в Wave 06D-02 явно.

**Primary recommendation:** План должен идти строго waves 06D-01 (audit brief + 3 parallel passes) → 06D-02 (synthesis + Instruments pre-fix baseline) → **CHECKPOINT** (user budget decision) → 06D-03..N (fix-cycle, одна wave = один theme, не один файл) → 06D-Final (Instruments post-fix comparison + UAT smoke + closure). Между каждой fix-wave — regression gate (D-08: AppFeatures 133/133 + iOS+macOS xcodebuild).

---

<user_constraints>
## User Constraints (from CONTEXT.md)

> Эта секция — **верхатим** copy из `06D-CONTEXT.md`. Планировщик и executor'ы должны лочить эти решения и НЕ исследовать альтернативы.

### Locked Decisions

#### Focus / Symptoms (user pain points, 2026-05-13)

- **D-01: Primary audit targets — cold start + connect tap.** Пользователь сообщил, что приложение «тяжело грузится» начиная с Phase 5. Из 4 предложенных вариантов user выбрал именно эти два:
  - **Cold start path:** от тапа по иконке до появления рабочего MainScreen с пропрорисованными кнопками. Включает: AppDelegate/SceneDelegate init → ProtocolRegistry + TransportRegistry registration (5 + 5 handlers) → SwiftData container init (любые migrations при первом запуске) → ConfigImporter init → TunnelController init + `startReachability` (с initial `loadAllFromPreferences` XPC seed) → MainScreenViewModel init (с initial NEVPN seed XPC) → MainScreenView rendering.
  - **Connect tap path:** от тапа power-кнопки до финального статуса «Подключено» + тикающий таймер. Включает: `performToggleImpl` → pre-connect probe (параллельный TCP ко всем supported) → `provisionTunnelProfile` (SwiftData fetch + sing-box config build via PoolBuilder + saveToPreferences → XPC) → `tunnel.connect()` → `startVPNTunnel` → libbox launch внутри Packet Tunnel extension → 30-секундный polling loop до `.connected`.
- **D-01a:** Все findings и fixes должны trace'иться к одному из двух targets (или к косвенному улучшению — dead-code/simplicity, которое в свою очередь упрощает hot path или snizает binary size).

#### Audit scope (code boundary)

- **D-02: Full scope.** Аудит покрывает: все Swift packages (AppFeatures, VPNCore, ProtocolRegistry, TransportRegistry, ConfigParser, KillSwitch, PacketTunnelKit, 5 протокольных packages, 5 транспортных handler'ов, Localization, CrashReporter, DesignSystem, ServerListFeature, SettingsFeature); App entry points (`BBTB/App/iOSApp/BBTB_iOSApp.swift`, `BBTB/App/macOSApp/BBTB_macOSApp.swift`, оба Packet Tunnel extensions, AppProxyProvider macOS); sing-box JSON templates; Instruments profiling `libbox.xcframework` startup в Packet Tunnel extension process (НЕ переписываем gomobile binding, но profiling — да).
- **D-02a: НЕ в scope:** перeписывание sing-box / libbox internals; замена backend (Rust sing-box, etc.); миграция с SwiftPM на другую build system; добавление новых dependencies (кроме случаев когда replacement существующего даёт обоснованный win).

#### AI participants & pass design

- **D-03: Три независимых peer-review passes с одинаковым брифом.**
  - **Opus 4.7** — этот thread (через Read / Bash / Agent с `subagent_type=Explore` для широких searches).
  - **Codex GPT-5.2** — через `mcp__codex__codex` в `sandbox: read-only`.
  - **Gemini 3.1 Pro** — через `mcp__gemini__gemini` в `sandbox: read-only`. **Primary model:** `gemini-3.1-pro-preview`. **Fallback chain на 503/error:** `gemini-3.1-pro-preview` → `deep-research-preview-04-2026` → `gemini-3-pro-preview` → `gemini-3-flash-preview` → `gemini-2.5-pro`. Если все 5 fallback'ов упали — пауза 5-10 мин + повтор; если снова всё — задокументировать и продолжить с 2 passes (Opus + Codex), пометив Gemini как "skipped — API unavailable".
- **D-04: Findings synthesis.** Единый `06D-FINDINGS.md`. Каждое finding — строка с колонками: `# | Title | Dimension | Severity | File:Line | Description | Opus | Codex | Gemini | Consensus | Recommended fix`. Колонки Opus/Codex/Gemini = `[FOUND]` / `[NOT FOUND]`. Consensus = `3/3 strong` / `2/3 moderate` / `1/3 unique-but-valuable`. Synthesis делает Opus после завершения всех трёх pass'ов.

#### Audit dimensions

- **D-05: Все 5 dimensions равновесомые a priori.** Severity учитывает actual user impact, не a priori weight.
  - Performance / responsiveness (особенно cold start + connect tap).
  - Energy consumption (Energy Log в Instruments).
  - Code simplicity / deduplication / dead code.
  - Memory footprint (Allocations + retained-size).
  - Launch time (overlaps с cold start, focus на Process spawn → first frame).
- **D-05a:** Severity rubric (precise thresholds — финализируется в PLAN):
  - **HIGH** — measurable user pain (`>200ms` perceived lag на cold start или connect tap), security/correctness concern, или active bug.
  - **MEDIUM** — measurable но sub-perception impact (`50-200ms`), maintenance debt с concrete cost, energy regression на typical session.
  - **LOW** — cosmetic / future-friction (`<50ms`), simplification без measurable user impact.

#### Severity & end-condition

- **D-06: End-condition определяется после findings checkpoint.**
  - **Wave 1** — 3 parallel AI audit passes; outputs хранятся как `06D-FINDINGS-OPUS.md` + `06D-FINDINGS-CODEX.md` + `06D-FINDINGS-GEMINI.md`.
  - **Wave 2** — synthesis в `06D-FINDINGS.md` + Instruments baseline (`wiki/performance-baseline.md` initial draft с pre-fix traces).
  - **🛑 CHECKPOINT 1** — user reviews scale + decides budget.
  - **Wave 3..N** — fix-cycle waves (одна wave = логически связанная группа фиксов), атомарные commit'ы.
  - **Wave Final** — Instruments post-fix traces + comparison + `wiki/performance-baseline.md` final + `06D-UAT.md` + closure.

#### Instruments measurement

- **D-07: Real device — iPhone iOS 26.5.** Не Simulator. MacBook — secondary, traces на macOS Sequoia/Tahoe.
- **D-07a: Traces:** Time Profiler (cold launch — iPhone+MacBook); Time Profiler (connect tap — iPhone); Energy Log (idle 60s + connect window + 5min active — iPhone); Allocations (cold launch + import + connect — iPhone).
- **D-07b: Baseline:** pre-fix snapshot на main (`c51b2ce` или successor). Сравнение pre-fix vs post-fix внутри Phase 6d. Phase 1 baseline недоступен.
- **D-07c: Сохранение traces:** `.trace` файлы — большие бинарники, **НЕ в git**. Скриншоты ключевых spans + текстовые exports → `wiki/performance-baseline.md` + `.planning/phases/06d-performance-audit/baselines/` (markdown summaries).

#### Regression gate (architectural invariants)

- **D-08:** AppFeatures swift test **133/133** + iOS Simulator xcodebuild + BBTB-macOS xcodebuild — все три green ТHROUGHOUT fix-cycle. Между каждой fix-wave запускаются все три. Любая регрессия → revert / fix-on-top перед следующей wave.
- **D-09: Phase 6c invariants preserved:**
  - `TunnelController.handleStatusChange` intent-closing path UNCHANGED.
  - No XPC в `NEVPNStatusDidChange` observer hot path.
  - No reintroduction `ReconnectStateMachine` / `NetworkReachability` / custom retry loops.
  - `applyVPNStatus(_:connectedDate:)` остаётся SINGLE authority для `state` + `reconnectBannerState`.
  - Sliding session window invariant: `manager.isOnDemandEnabled = autoReconnectToggle && userIntendedConnected`.
- **D-09a:** Любая fix-wave, которая ломает D-09 invariant — STOP, escalate to user.

#### Wave structure (preliminary)

- **D-10:** Минимум 4-5 waves: 06D-01 audit briefing + 3 parallel passes → 06D-02 synthesis + baseline → 🛑 CHECKPOINT → 06D-03..N fix-cycle → 06D-Final Instruments post-fix + UAT smoke + closure.

#### Communication

- **D-11: Все user-facing документы на русском** (CONTEXT, PLAN, FINDINGS narrative, SUMMARY).
- **D-11a: AI delegation prompts на английском** (стандарт для MCP servers).
- **D-11b: Технические термины** (XPC, NEVPN*, SwiftData, Instruments span names, function names) — на английском без translation (grep-anchors).

### Claude's Discretion

- Точный текст 7-section delegation brief для трёх audit passes — пишется в `06D-01-PLAN.md`.
- Конкретные measurable thresholds для HIGH/MEDIUM/LOW severity (D-05a стартовые, финализируются в plan с учётом Instruments baseline).
- Wave 06D-03..N decomposition — зависит от actual findings (не известна сейчас; решаем после checkpoint).
- Instruments trace export format — текстовые summary в markdown с key span timings (не binary `.trace`).
- Когда и как делегировать конкретный fix к Codex / Gemini (если sub-task требует second opinion) — по правилам `~/.claude/rules/delegator.md`.

### Deferred Ideas (OUT OF SCOPE)

#### Carry-over из STATE.md / Phase 6c backlog

- **Phase 11 follow-up** — empty-state UX issue после удаления VPN profile из iOS Settings; auto-recreate manager workaround. Не Phase 6d.
- **Phase 11 follow-up** — SocksProbe PID attribution UI. Не Phase 6d.
- **Phase 12 prerequisite** — Apple Distribution credentials. Не Phase 6d.
- **W2-05 iOS 16.1+ Apple-leak документация** — promote из 01-RESEARCH.md в FAQ. Не Phase 6d.

#### Phase 7-8 backlog (отдельные phases)

- **NET-12: active liveness probe** (sing-box `Cmd_LogClient` polling или app-side HTTP ping). Phase 7-8.
- **macOS-specific UAT replay** Phase 6c scenarios A/F-reverse/Settings-disable/G на macOS отдельно.

#### Out of scope для Phase 6d (могут стать своими phases в будущем)

- **Замена `libbox.xcframework` на Rust sing-box или другой backend** — большой scope, отдельная phase.
- **Миграция с SwiftPM на другую build system (Bazel, etc.)** — большой scope.
- **Adding new dependencies для perf wins** — допустимо только как часть конкретного fix'а с clear user-impact justification.
- **UI redesign** — Phase 11 territory.

</user_constraints>

---

## Project Constraints (from CLAUDE.md)

> Эти directives — non-negotiable, заданы проектным CLAUDE.md + user instructions. Planner и executors обязаны соблюдать.

| # | Directive | Impact на Phase 6d |
|---|-----------|---------------------|
| C-01 | Все ответы / user-facing docs — на **русском языке** | CONTEXT, PLAN, FINDINGS narrative, SUMMARY — Russian. AI delegation prompts — English (D-11a). Технические анкоры — English (D-11b). |
| C-02 | **Аббревиатуры с русским переводом в скобках** при первом упоминании | Например: «XPC (межпроцессное взаимодействие — Mach IPC через NSXPCConnection)», «VPN (виртуальная частная сеть)», «DPI (Deep Packet Inspection — глубокий анализ пакетов)». |
| C-03 | **Quality > speed** — между быстрым patch и архитектурно правильным fix — выбираем второе | При planning fix-cycle: если finding допускает quick patch vs proper refactor, выбираем refactor даже если он медленнее реализуется. |
| C-04 | **Non-programmer audience** — explanations простые, без CS jargon | В user-facing секциях (FINDINGS Summary, SUMMARY closure): простой язык, метафоры. Technical body — нормальный технический язык. |
| C-05 | **Scalable solutions prioritized** | Findings, которые улучшают только текущий момент vs findings, которые упрощают будущие phases (Phase 7-12) — приоритет последним. |
| C-06 | **Wiki = long-term decision log** | Любое архитектурное решение Phase 6d (например, «cold-start init pattern — lazy via `@MainActor static let`») переезжает в `wiki/` соответствующей страницей. Не оставлять только в `.planning/`. |
| C-07 | Никогда не модифицировать `raw/` | Phase 6d вообще не трогает `raw/` — это для wiki sources. Здесь упомянуто только для полноты. |
| C-08 | `wiki/index.md` + `wiki/log.md` обновляются после каждого изменения wiki | Новая страница `wiki/performance-baseline.md` → entry в `index.md` + `log.md` append. |
| C-09 | Имена wiki страниц — lowercase с дефисами | `wiki/performance-baseline.md`, не `Performance-Baseline.md`. |

---

## Phase Requirements

> Phase 6d на момент discuss-phase **не имел** заведённых REQ-IDs. Новые QUAL-* / PERF-* будут зарегистрированы в `06D-01-PLAN.md` (Wave 1 первое действие). Researcher здесь даёт каркас.

| ID (proposed) | Description | Research Support |
|---|---|---|
| PERF-01 | Cold start path: process launch → MainScreen interactive — measurable Time Profiler trace pre-fix vs post-fix; target ≤ Phase 1 baseline или ≤ user perception threshold | См. секцию **Cold-start anatomy** + **Instruments workflow / Time Profiler cold launch** |
| PERF-02 | Connect tap path: power-button tap → `.connected` + timer tick — Time Profiler + os_signpost markers | См. секцию **Connect-tap anatomy** + **Instruments workflow / Connect tap** |
| PERF-03 | Energy regression budget на typical session (5min active VPN) — Energy Log baseline | См. секцию **Instruments workflow / Energy Log** |
| PERF-04 | Memory regression budget — Allocations retained-size delta | См. секцию **Instruments workflow / Allocations** |
| QUAL-01 | Dead code identification и removal — Periphery scan + grep-audit | См. секцию **Code-simplicity / dead-code detection** |
| QUAL-02 | Architectural invariants preserved — D-09 Phase 6c invariants intact post-fix | См. секцию **Common Pitfalls / Invariant violation** |
| QUAL-03 | Multi-AI findings synthesis — 3 independent passes deduplicated в unified file | См. секцию **Multi-AI audit brief template** |

---

## Architectural Responsibility Map

Phase 6d затрагивает **несколько тиров одновременно** — cold-start path спускается от Process spawn до SwiftUI rendering, connect-tap path пересекает host app ↔ Packet Tunnel extension boundary. Карта помогает планировщику не путать тиры при назначении fix-задач.

| Capability | Primary Tier | Secondary Tier | Rationale |
|---|---|---|---|
| Process spawn → dyld → +load → SwiftUI App.init | **iOS Runtime** (Darwin) | — | Apple-managed, мы влияем косвенно через binary size (Periphery) и static initializers |
| SwiftUI App.init (registry registration, SwiftData container) | **Host App** | — | `BBTB_iOSApp.init()` (`/BBTB/App/iOSApp/BBTB_iOSApp.swift`) — наш код, hot path для cold start |
| ConfigImporter / MainScreenViewModel construction | **Host App / AppFeatures** | — | `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` |
| Pre-connect TCP probe | **Host App** | — | В `TunnelController.performToggleImpl` (host process), параллельный к supported outbounds |
| `NETunnelProviderManager` save/load (XPC) | **Host App ↔ iOS NE daemon** | — | XPC boundary; expensive (Mach IPC); кешируется в `cachedManager` (Phase 6c) |
| `manager.connection.startVPNTunnel(...)` | **Host App → Packet Tunnel Extension** (process boundary) | — | iOS spawns extension process; host app только initiator |
| sing-box config JSON build (PoolBuilder) | **Host App** | — | `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/` — runs в host, передаётся в extension через `protocolConfiguration.providerConfiguration` |
| libbox launch (sing-box engine) | **Packet Tunnel Extension** (separate process) | — | Внутри `PacketTunnelExtension-iOS/PacketTunnelProvider.swift`; profiling требует attach Instruments к extension process |
| TUN inbound + DNS hijack + outbound dialing | **Packet Tunnel Extension** | — | Apple framework provides TUN fd; sing-box owns packet processing |
| SwiftData CRUD (servers, subscriptions, settings) | **Host App** | — | `BBTB/Packages/AppFeatures/Sources/.../*ViewModel.swift` + `SwiftDataContainer.makeShared()` |
| UI rendering (SwiftUI views) | **Host App** | — | `MainScreenView` / `ServerListSheet` / `SettingsView` — SwiftUI on main thread |

**Tier ownership trap to flag in synthesis:** AI-аудитор может предложить «перенести pre-connect probe в extension». Это **нарушение тиров** — extension process не должен делать TCP probes к серверам до того как туннель установлен (нет route, нет DNS), это работа host app. Synthesis отвергает такое предложение.

---

## Standard Stack

> Phase 6d не вводит новых runtime dependencies (D-02a). Standard Stack здесь — **tooling stack** для аудита и измерения.

### Core (verification & measurement)

| Tool | Version | Purpose | Why Standard |
|---|---|---|---|
| **Xcode Instruments** | 16.x (iOS 26 SDK) | Time Profiler, Energy Log, Allocations, App Launch template | [VERIFIED: developer.apple.com/xcode] Apple-managed, единственный device-attached профайлер на iOS. Real device required для Energy Log. |
| **`OSSignposter` (Swift)** | iOS 15+ API | Mark custom intervals для Instruments timeline | [CITED: developer.apple.com/documentation/os/ossignposter] Modern API заменяет deprecated `os_signpost` C-style. |
| **`os.log` Logger** | iOS 14+ | Subsystem-categorized logging для production diagnostics | Уже используется (`BBTB_iOSApp.swift` line 30: `Logger(subsystem: "app.bbtb.client.ios", category: "diag")`) |
| **`swift test`** | Swift 6 / Xcode 16 | Regression gate AppFeatures 133/133 | Уже используется (Phase 1-6c) |
| **`xcodebuild`** | Xcode 16+ | iOS Simulator + BBTB-macOS build gate | Уже используется (Phase 1-6c) |

### Supporting (code analysis)

| Tool | Version | Purpose | When to Use |
|---|---|---|---|
| **Periphery** | 3.7.4 (released 2026-04-26) | Dead-code detection в Swift packages + xcworkspace | [VERIFIED: github.com/peripheryapp/periphery] Primary dead-code tool. Поддерживает SPM + Xcode workspace. |
| **SwiftLint `analyze` mode** | latest | Backup для unused_declaration rule | [CITED: realm.github.io/SwiftLint/unused_declaration.html] Дополняет Periphery; ловит другие классы style/lint issues. Не primary. |
| **`grep` / `rg` (ripgrep)** | system | Forbidden-symbol audit (как Phase 6c B-08) | Pattern Phase 6c: `grep "ReconnectStateMachine\|NetworkReachability"` → должен возвращать 0 |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|---|---|---|
| Periphery | SwiftLint `unused_declaration` only | SwiftLint работает на per-file scope, не cross-file references → высокий false-negative rate. Periphery строит граф через SourceKit → точнее. [CITED: medium комбинация SwiftLint + Periphery is "complementary"] |
| Instruments | XCTest performance tests (`measure { }` blocks) | XCTest даёт numeric data без UI; хорош для CI regression detection, но **не даёт timeline view** (где время реально идёт). Phase 6d требует именно anatomy → Instruments primary. XCTest — opt-in для closure-time CI guard. |
| os.signpost (Swift API) | Manual `Date()` printing в OSLog | Apple-blessed integration с Instruments UI; signposts появляются как spans на timeline автоматически. Manual `Date()` приходится мэппить рукой. |
| Manual screen-by-screen profiling | App Launch template (specific Instruments template) | App Launch template **автоматически** запускает app + measures launch phases (purple = pre-main, green = main-to-first-frame) [VERIFIED: WWDC19 #423]. Сильно быстрее чем ручной Time Profiler setup. **Use both:** App Launch для quick triage, Time Profiler для detail. |

### Tool installation / verification

```bash
# Verify Xcode + Instruments
xcodebuild -version  # expect Xcode 16.x
xcrun instruments -h | head -5  # list templates available

# Install Periphery 3.7.4 (Homebrew — most common path)
brew install peripheryapp/periphery/periphery
periphery version  # expect 3.7.4 or newer

# Verify SwiftLint installed (already in repo if Tuist setup uses it)
which swiftlint && swiftlint version
```

**Verification вылог в `06D-RESEARCH-VERIFICATION.md` или в notes Wave 06D-01 Task 0.**

### Version verification — researcher note

- **Periphery 3.7.4** — released 2026-04-26 [VERIFIED: WebFetch github.com/peripheryapp/periphery via Read tool]. Если к моменту планирования вышла более новая — использовать latest stable. CHANGELOG проверять перед install.
- **Xcode** — на момент 2026-05 latest stable — Xcode 16.x; на компьютере пользователя проверить через `xcodebuild -version` перед Instruments-сессией [ASSUMED — verify in Wave 06D-02].

---

## Architecture Patterns

### System Diagram — Cold Start Path (D-01)

```
[iPhone Home Screen]
        │
        │ tap icon
        ▼
┌─────────────────────────────────────────────────┐
│ iOS Runtime (Darwin)                            │
│  • Process spawn (fork+exec)                    │
│  • dyld: load shared libraries (App + ext deps) │
│  • +load Objective-C class init                 │
│  • main()                                        │
└─────────────────────────────────────────────────┘
        │
        │ swift @main expansion
        ▼
┌─────────────────────────────────────────────────┐
│ BBTB_iOSApp.init()                              │
│  1. CrashReporter.shared.install()              │
│  2. AppGroupContainer.exportSingBoxLogToDocs()  │
│  3. ProtocolRegistry register × 5               │
│  4. TransportRegistry register × 5              │
│  5. SwiftDataContainer.makeShared()  [disk I/O] │
│  6. ConfigImporter(modelContainer:...)          │
│  7. Task { OnDemandMigrationTask.runIfNeeded } [XPC] │
│  8. TunnelController()                          │
│  9. MainScreenViewModel(importer, tunnel, ...)  │
│ 10. SwiftDataFailoverProvider + setFailoverProvider │
│ 11. Task { TunnelWatchdog setup + setWatchdog } │
│ 12. Task { tunnel.startReachability() } [seed XPC] │
└─────────────────────────────────────────────────┘
        │
        │ App.body evaluated
        ▼
┌─────────────────────────────────────────────────┐
│ SwiftUI WindowGroup → BBTBRootView              │
│  • NavigationStack                              │
│  • MainScreenView(viewModel:)                   │
│  • .modelContainer(modelContainer)              │
└─────────────────────────────────────────────────┘
        │
        │ First render commit
        ▼
[MainScreen visible — interactive]
```

**Hot-path components for cold start (potential findings targets):**
- (5) `SwiftDataContainer.makeShared()` — synchronous disk I/O on init; first launch может включать migrations
- (7), (10), (11), (12) — четыре отдельных `Task { }` post-init; каждая делает XPC к NE daemon (`loadAllFromPreferences` или эквивалент)
- (3), (4) — 10 dictionary `register` calls; должны быть O(1) но проверить нет ли там Sendable / actor coordination
- (6), (9) — VM construction; могут содержать `@Published` initializers с side effects

### System Diagram — Connect Tap Path (D-01)

```
[MainScreen: power button visible, idle]
        │
        │ user taps power
        ▼
ConnectionButton.action ──► performToggleImpl (TunnelController actor)
        │
        │ user intent ON
        ▼
┌─────────────────────────────────────────────────┐
│ Pre-connect probe (parallel TCP)                │
│  For each ServerConfig where isSupported:       │
│    • Connect TCP to host:port (race timeout)    │
│    • Record latency / failure                   │
│  Pick winner (lowest latency)                   │
└─────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────┐
│ provisionTunnelProfile (ConfigImporter)         │
│  • SwiftData fetch all ServerConfig             │
│  • Build sing-box config JSON via PoolBuilder   │
│  • Set NETunnelProviderProtocol.protocol-config │
│  • manager.isOnDemandEnabled = (toggle && true) │
│  • manager.saveToPreferences() [XPC]            │
│  • Post .bbtbProvisionerDidSave notification    │
└─────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────┐
│ tunnel.connect()                                │
│  • manager.connection.startVPNTunnel(options:)  │
│  • Poll status until .connected (max 30s)       │
└─────────────────────────────────────────────────┘
        │
        │ iOS spawns Packet Tunnel extension process
        ▼
┌─────────────────────────────────────────────────┐
│ [SEPARATE PROCESS] PacketTunnelProvider         │
│  • startTunnel(options:completionHandler:)      │
│  • Parse providerConfiguration                  │
│  • Open libbox.LibboxNewService(config: ...)    │
│  • libbox.Start()  [sing-box launch]            │
│  • Build NEPacketTunnelNetworkSettings          │
│  • setTunnelNetworkSettings(_:) [XPC back]      │
└─────────────────────────────────────────────────┘
        │
        ▼
NEVPNStatus → .connecting → .connected
        │
        │ NEVPNStatusDidChange notification fires
        ▼
TunnelController.handleStatusChange + MainScreenViewModel.applyVPNStatus
        │
        ▼
state = .connected(since: connectedDate) + timer ticks
```

**Hot-path components for connect tap (potential findings targets):**
- **Pre-connect probe** — already parallel, but timeouts/retry policy могут быть suboptimal
- **PoolBuilder JSON build** — потенциально expensive (template parse + interpolation × N servers); может быть кешируемо если конфиг не менялся
- **`saveToPreferences()` XPC** — ~10-100ms typical; нельзя избежать (Apple-managed)
- **libbox.Start() в extension** — Go runtime init + sing-box config parse + outbound setup; main cold-path inside extension
- **30s polling loop** — `sleep 0.5s` × до 60 итераций; должен exit early на `.connected`

### Recommended File Layout (existing, для reference)

```
BBTB/
├── App/                                         # Entry points
│   ├── iOSApp/BBTB_iOSApp.swift                 # @main iOS, 156 строк
│   ├── macOSApp/BBTB_macOSApp.swift             # @main macOS, 149 строк
│   ├── PacketTunnelExtension-iOS/
│   │   └── PacketTunnelProvider.swift           # iOS tunnel process entry
│   ├── PacketTunnelExtension-macOS/             # macOS tunnel process entry
│   └── AppProxyExtension-macOS/
│       └── AppProxyProvider.swift               # macOS per-app proxy (Phase 8)
├── Packages/                                     # SPM packages
│   ├── AppFeatures/                              # UI / ViewModels / Controllers
│   │   └── Sources/
│   │       ├── MainScreenFeature/                # Hot path for both targets
│   │       │   ├── BBTB_iOSApp.swift (delegated)
│   │       │   ├── TunnelController.swift        # 316 строк (post Phase 6c)
│   │       │   ├── MainScreenViewModel.swift     # 593 строк ⚠️ largest VM
│   │       │   ├── ConfigImporter.swift          # 1071 строк ⚠️ largest non-test file
│   │       │   ├── TunnelWatchdog.swift          # 267 строк
│   │       │   ├── OnDemandRulesBuilder.swift    # 180 строк
│   │       │   ├── OnDemandMigrationTask.swift   # 117 строк
│   │       │   └── ...                            # plus 12 smaller files
│   │       ├── ServerListFeature/                 # ServerList + Detail
│   │       ├── SettingsFeature/                   # Settings + Advanced
│   │       └── MenuBarFeature/                    # macOS menu bar
│   ├── PacketTunnelKit/                          # PoolBuilder + sing-box config
│   ├── VPNCore/                                   # Protocol types, TransportConfig
│   ├── ConfigParser/                              # URI / YAML parsers
│   ├── ProtocolRegistry/                          # 5 protocol handlers
│   ├── TransportRegistry/                         # 5 transport handlers
│   ├── Protocols/{VLESSReality,VLESSTLS,...}     # Per-protocol packages
│   └── ...                                        # Localization, CrashReporter, etc.
└── Vendored/libbox.xcframework                    # sing-box gomobile binding
```

**Findings hotspots по line count** (raw output `wc -l` Sources/*):
1. `ConfigImporter.swift` — **1071 lines** — крупнейший файл. Highly likely target для simplicity/dead-code findings.
2. `MainScreenViewModel.swift` — **593 lines** — два месяца Phase 6 + 6c эволюции; вероятны merged-then-unused helpers.
3. `ServerListViewModel.swift` — **394 lines** — Phase 3 + 5.
4. `TunnelController.swift` — **316 lines** — post Phase 6c trim (был 909). Маленький bonus delta вряд ли.
5. `TunnelWatchdog.swift` — **267 lines** — Phase 6c new. Check for over-engineering.
6. `ServerListSheet.swift` — **235 lines** — Static height constants для presentationDetents — известная Phase 11 follow-up.

### Pattern 1: OSSignposter для cold-start markers

**What:** Использовать `OSSignposter` (iOS 15+ Swift API) для маркировки начала и конца cold-start span'а; Instruments на timeline покажет это автоматически.

**When to use:** Wave 06D-02 Task: добавить signpost'ы в `BBTB_iOSApp.init()` (start) и в `MainScreenView.onAppear` (end) — это даёт чёткий span "Cold launch" в Time Profiler trace.

**Example** (modern iOS 15+ API):

```swift
// Source: developer.apple.com/documentation/os/ossignposter
//         + swiftbysundell.com/wwdc2018/getting-started-with-signposts/
import os.signpost

// В подходящем shared месте (например, BBTB_iOSApp.swift outside struct):
private let perfSignposter = OSSignposter(
    subsystem: "app.bbtb.client.ios",
    category: "performance"
)

// Modern OSSignposter API (iOS 15+, preferred):
struct BBTB_iOSApp: App {
    private let coldStartSignpostState: OSSignpostIntervalState

    init() {
        // Mark start of cold-start span
        self.coldStartSignpostState = perfSignposter.beginInterval("ColdLaunch")
        // ... existing init code ...
    }
    // ...
}

// In root view:
struct BBTBRootView: View {
    var body: some View {
        NavigationStack {
            MainScreenView(viewModel: viewModel, onOpenSettings: { ... })
                .onAppear {
                    // Mark end of cold-start span (first interactive frame)
                    perfSignposter.endInterval("ColdLaunch", coldStartSignpostState)
                }
        }
    }
}
```

**Legacy fallback API** (если по какой-то причине нужно использовать `os_signpost` Cтиль):

```swift
// Source: developer.apple.com/documentation/os/os_signpost
//         + swiftbysundell.com/wwdc2018/getting-started-with-signposts/
import os.signpost

let log = OSLog(subsystem: "app.bbtb.client.ios", category: "performance")
let id = OSSignpostID(log: log)
os_signpost(.begin, log: log, name: "ColdLaunch", signpostID: id)
// ... work ...
os_signpost(.end, log: log, name: "ColdLaunch", signpostID: id)
```

**Recommended naming convention:** `ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`. Эти имена появятся в Instruments timeline как human-readable spans.

### Pattern 2: SwiftData ModelContainer — defer where possible

**What:** SwiftData `ModelContainer` создаётся синхронно через `try SwiftDataContainer.makeShared()` в `BBTB_iOSApp.init()` (line 53-57). Это **блокирует main thread** до завершения; при первом запуске включает migrations.

**When to use this pattern:** Если Time Profiler покажет, что `makeShared` занимает >100ms, рассмотреть:
- (a) Lazy loading через `@MainActor private static let` (создаётся при первом обращении, не при app launch)
- (b) `Task.detached { try SwiftDataContainer.makeShared() }` с awaiting в `.task { }` modifier на root view

[ASSUMED] — actual cost зависит от количества данных в SwiftData store. Decision гейтит Instruments baseline (Wave 06D-02).

**Tradeoff:** Lazy container усложняет downstream code (`ConfigImporter` ожидает container в `init`). Refactor — Medium effort.

### Pattern 3: Registry init via `@MainActor static let`

**What:** `ProtocolRegistry.shared.register(...)` × 5 и `TransportRegistry.shared.register(...)` × 5 — 10 dictionary inserts в `App.init()` (lines 38-50 в `BBTB_iOSApp.swift`).

**When to use:** Если Time Profiler покажет, что register calls suffer из-за thread-coordination (registries — Swift actor? singleton с lock? — нужно проверить implementation). Альтернатива:

```swift
// Source: training data — Swift static init pattern
// Перед изменением: VERIFY actual implementation of ProtocolRegistry / TransportRegistry
//                   через Read tool. Если уже @MainActor singleton — no-op.
enum AppRegistries {
    @MainActor static let protocols: Void = {
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)
        ProtocolRegistry.shared.register(TrojanHandler.self)
        // ...
    }()

    @MainActor static let transports: Void = {
        TransportRegistry.shared.register(TCPTransportHandler.self)
        // ...
    }()
}

// In App.init: _ = AppRegistries.protocols; _ = AppRegistries.transports
```

[ASSUMED] — выигрыш зависит от реальной реализации registry classes. Mark for verify in Wave 06D-02.

### Anti-Patterns to Avoid

- **`Task { }` storm в `App.init()`:** В `BBTB_iOSApp.swift` lines 68, 92, 101, 111 есть **4 отдельных `Task { }`** (migration, failover provider swap, watchdog setup, reachability start). Каждый создаёт structured concurrency overhead. Если они **independent** — OK, но если они логически last-one-wins — лучше серилизовать или объединить. Findings target.
- **Synchronous XPC в cold path:** Уже устранено в Phase 6c. AI-аудитор может **предложить вернуть** sync `loadAllFromPreferences()` в `App.init()` для cache priming — это **violates D-09 invariant**. Synthesis отвергает.
- **`@StateObject` re-init на NavigationStack push:** `BBTBRootView` line 126: `@StateObject private var settingsVM = SettingsViewModel()` — нормально (lifetime связан с BBTBRootView). НО если бы был внутри `body` или внутри ViewBuilder closure — был бы re-init на каждый push. Flag-worthy в audit pass.
- **`@Published` thrash:** `MainScreenViewModel` имеет `state: AppState` + `reconnectBannerState` — оба `@Published`. Если код в connect/disconnect path делает несколько последовательных мутаций — каждая триггерит view rebuild. Findings target: batch mutations via `withAnimation { }` или local var → single assignment.

---

## Multi-AI Audit Brief Template (Wave 06D-01)

> Этот шаблон — **единственный источник правды** для 3 параллельных audit pass'ов. **Identical brief** для Opus / Codex / Gemini (D-03). Разница только в способе delivery: Opus получает в текущем context, Codex через `mcp__codex__codex` с `sandbox: read-only`, Gemini через `mcp__gemini__gemini` с `sandbox: read-only` (+ fallback chain D-03).

### Format conformance

Брифа структура — **7 секций** по `~/.claude/rules/delegator.md` [VERIFIED: cat ~/.claude/rules/delegator.md]. Уже в Wave 06D-01 planner будет лочить exact text; researcher даёт каркас.

### Recommended brief skeleton (English, per D-11a)

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
     MEDIUM = measurable sub-perception impact (50–200ms), maintenance debt with concrete
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
     is not acceptable — say "extract method Y from file Z lines A–B into helper W".

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
   Section 1: Executive summary (3–5 bullets — top patterns observed).
   Section 2: Findings table (column set above).
   Section 3: Methodology — what you read, what you skipped, why.
   Closing: estimated pass duration + your confidence level (HIGH/MEDIUM/LOW)
   per dimension.
```

### Recommended forbidden-finding categories (synthesis filter)

При synthesis (Wave 06D-02) дедупление и фильтрация:

| Category | Rule | Action |
|---|---|---|
| **Invariant violation (D-09)** | Finding предлагает откатить Phase 6c (вернуть RSM, NetworkReachability, XPC в observer, dual-authority for state) | **DROP — мотивированно записать в `06D-FINDINGS.md` секцию «Filtered — violates Phase 6c invariant»** |
| **Out-of-scope (D-02a)** | Finding предлагает заменить libbox / sing-box / SwiftPM | **DROP — записать в `06D-FILTERED.md` или в FINDINGS секцию «Filtered — out of scope»** |
| **Abstract beauty без impact** | Finding о style/idiom без measurable user impact или maintenance cost | **DROP, не downgrade в LOW** |
| **False uniqueness** | 2-3 AI указали на похожее, но разные `file:line` — это **один finding, не три** | **Merge: один row, всё трое в `Found by:`** |
| **Conflict between AIs** | AI A говорит "extract X to helper", AI B говорит "inline X" | **Synthesis decides on architectural grounds (which serves Phase 7 better) — D-05a + C-05** |

---

## Instruments Workflow (iOS 26.5 + macOS Sequoia/Tahoe, 2026)

> Все шаги для iPhone iOS 26.5. macOS counterpart примечания в подсекции macOS specifics. Researcher делает максимально prescriptive — planner копирует в `06D-02-PLAN.md`.

### A. Time Profiler — Cold Launch (iPhone)

**Preferred approach: App Launch template** (Apple-blessed, автоматизирует setup) [VERIFIED: WWDC19 #423; WebSearch confirmed].

```text
1. Подключить iPhone iOS 26.5 к Mac через USB-C / Lightning. Trust device.
2. В Xcode: Product → Profile (⌘I). Build + spawn Instruments.
3. Instruments template chooser → "App Launch" → Choose.
   - НЕ "Time Profiler" сразу — App Launch template ВКЛЮЧАЕТ Time Profiler
     плюс specialized launch-phase lanes (purple = pre-main / dyld;
     green = main-to-first-frame).
4. В Instruments: select Target Device (iPhone), Target Process (BBTB).
5. Запустить запись (red ●). Instruments автоматически:
   a. Завершит уже запущенный BBTB (если активен)
   b. Spawn'нет BBTB cold
   c. Запишет launch phases от process spawn до first frame
   d. Остановит запись после first interactive frame
6. По завершении: Instruments покажет timeline с:
   - "System interface init" (purple) — dyld + +load + main()
   - "Static runtime init" (purple) — Swift runtime + framework init
   - "App init" (green) — наш BBTB_iOSApp.init() body
   - "Initial frame render" (green) — SwiftUI first commit
7. КЛЮЧЕВОЕ: если signposts добавлены (Pattern 1 выше), они появятся
   как именованные spans поверх обычных lanes.
```

**Cold launch требует "true cold":** перед каждым sample — force-quit BBTB (swipe up + swipe app away) **И** wait ≥10 seconds (или reboot iPhone для самой холодной). Inside-Xcode build-and-run **НЕ** cold — Xcode держит app warm.

**Sample count:** минимум **5 cold launches**, median по timing. iPhone iOS 26.5 имеет thermal throttling — несколько consecutive samples могут показать degradation.

**Text export для wiki / baselines:**

```text
1. В Instruments после записи: Window → Show Detail View
2. Select лучший / худший / медианный sample
3. File → Save As → выбрать `.trace` (для local archive — НЕ в git per D-07c)
4. ДЛЯ ТЕКСТА: copy-paste numerical data из Summary lanes
   ИЛИ screenshot timeline area для inclusion в markdown
5. Save into: `.planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md`
   format:
     # Cold launch — iPhone iOS 26.5 — pre-fix baseline
     Date: 2026-MM-DD
     Device: iPhone 15 Pro (or whatever)
     iOS: 26.5
     Build: BBTB v0.6.1 commit <sha>
     Samples: 5 (cold)
     | Phase | Median ms | Min ms | Max ms |
     | --- | --- | --- | --- |
     | dyld + +load | XX | YY | ZZ |
     | Swift static init | XX | YY | ZZ |
     | App.init body | XX | YY | ZZ |
     | First frame commit | XX | YY | ZZ |
     | Total cold launch | XX | YY | ZZ |
```

### B. Time Profiler — Connect Tap (iPhone)

```text
1. Профиль BBTB через Time Profiler template (не App Launch — мы профилируем
   in-app interaction, не launch).
2. Product → Profile → Instruments → Time Profiler template.
3. Запустить запись (red ●) ПЕРЕД тапом по power button.
4. В app: tap power button. Wait для .connected + timer tick.
5. Остановить запись (red ■) сразу после первого timer tick.
6. На timeline должны быть видны named spans (если сигнпосты добавлены):
   - "ConnectTap" (begin: tap detected, end: .connected fired)
   - "PreConnectProbe" (begin: probe launched, end: probe winner selected)
   - "ProvisionProfile" (begin: PoolBuilder start, end: saveToPreferences returned)
   - "LibboxStart" (если signpost внутри Packet Tunnel extension — см. секция D ниже)
```

**Recommended signposts to add для Wave 06D-02:**

| Signpost name | Begin location | End location |
|---|---|---|
| `ConnectTap` | `TunnelController.performToggleImpl` enter | `MainScreenViewModel.applyVPNStatus(.connected, ...)` |
| `PreConnectProbe` | probe launch (inside performToggleImpl) | probe winner picked |
| `ProvisionProfile` | `provisionTunnelProfile` enter | `saveToPreferences` returned |
| `LibboxStart` | `PacketTunnelProvider.startTunnel` enter (extension) | sing-box reports ready (extension) |
| `XPCSaveToPrefs` | `manager.saveToPreferences()` await start | await complete |

[ASSUMED] — exact API call points; planner verifies в Wave 06D-02 Task 0.

**Sample count:** ≥10 connect-taps от cold app state, ≥10 от warm app state. Median.

### C. Energy Log (iPhone)

[VERIFIED: developer.apple.com/library/archive — Energy Efficiency Guide]

Energy Log captures: CPU activity, network activity, GPU usage, screen brightness, location, background work. Требует **real device** — недоступен на Simulator.

```text
1. iPhone Settings → Privacy & Security → Developer Mode → ON
   (если уже не enabled).
2. iPhone Settings → Developer → Logging → "Energy" → ON.
3. Reboot iPhone (рекомендуется для clean baseline).
4. Disconnect iPhone от Mac (untethered measurement — более реалистичен).
5. Run scenarios:
   a. Idle 60s — open BBTB но не нажимай ничего (просто экран открыт).
   b. Connect tap — открой BBTB, тапни Connect, дождись .connected,
      жди 60s в connected state.
   c. Active session 5min — установить connection, открыть browser (Safari),
      загрузить 5-10 страниц (любых — Google, Wikipedia, etc.) через VPN.
6. Reconnect iPhone к Mac.
7. Xcode → Window → Devices and Simulators → Open Console.
   Альтернатива: Instruments → File → Import → выбрать energy log file
   из iPhone (Settings → Developer → Logging → Energy → download).
8. Анализ:
   - "Energy Impact" (overall score — low/medium/high)
   - "CPU" lane (cycles per second)
   - "Network" lane (bytes/sec sent+received)
   - "Display" lane (brightness time)
   - "Background activity" (CPU consumed when app не на screen)
```

**Recommended metrics для baseline (markdown export):**

```markdown
# Energy Log — iPhone iOS 26.5 — pre-fix baseline
Date: 2026-MM-DD
Scenarios: idle 60s | connect tap | active 5min

| Scenario | Energy Impact | CPU% avg | Network KB/s avg | Background CPU% |
|---|---|---|---|---|
| Idle 60s | Low? | XX | 0 | <Y |
| Connect tap window (30s) | Med? | XX | varies | <Y |
| Active 5min | Med? | XX | depends | <Y |
```

**Energy regression threshold (recommended для D-05a refinement):**
- **HIGH energy regression:** Active 5min Energy Impact "High" где было "Low/Medium" OR CPU% avg ≥2× baseline
- **MEDIUM:** Energy Impact one tier up (Low→Medium) OR CPU% +25-100%
- **LOW:** CPU% +<25% OR minor lane delta

[ASSUMED — thresholds — refined after baseline collection in Wave 06D-02].

### D. Allocations (iPhone) — Host App + Packet Tunnel Extension

**Allocations template** — measures retained-size growth + leak candidates. Apple-blessed approach для memory regression detection.

#### D.1 Host app process

```text
1. Xcode → Product → Profile → Allocations template.
2. Target: iPhone + BBTB (Running Applications list).
3. Record. Scenarios:
   a. Cold launch → MainScreen idle 30s (baseline)
   b. Import URI (через clipboard или QR) (test import allocations)
   c. Tap Connect → wait .connected (test connect allocations)
   d. Idle 60s in connected state (test steady-state growth)
4. Stop recording.
5. Анализ:
   - "Allocations Summary" → "Persistent Bytes" column (retained)
   - Sort by Persistent Bytes desc; top 20 classes — candidate findings
   - "Generations" — mark snapshot at end of (a), (b), (c), (d);
     compare deltas
```

#### D.2 Packet Tunnel extension process (CRITICAL nontrivial step)

> [VERIFIED: developer.apple.com/forums/thread/654914 — Apple DTS Engineer Matt Eaton]
> Stage trap: extension process attach **НЕ через App Extensions list** —
> через **Running Applications list** с visible PID.

```text
1. Запустить BBTB на iPhone, сделать connect — убедиться VPN успешно
   поднят (внешний IP changed). Это критично — extension должен быть
   запущен и иметь PID.
2. ⚠️ В iPhone Settings: перейти на любой экран (например, Settings → VPN).
   Это гарантирует, что extension продолжит работать когда мы будем
   делать attach (если оставить только BBTB в foreground, system может
   suspend'нуть всё).
3. Xcode → Product → Profile (это spawn'нет Instruments + start BBTB
   profiling — но нам нужна не BBTB, а её extension).
4. В Instruments выбрать template → Allocations.
5. ⚠️ ВАЖНО: target list dropdown:
   - НЕ "App Extensions" submenu — там extension показан но attach
     не работает (confirmed Apple bug/limitation per Matt Eaton).
   - ВЫБРАТЬ "Running Applications" → найти extension по имени
     (например, "PacketTunnelExtension-iOS"). У него должен быть
     PID — обязательное условие. Без PID — extension suspended,
     attach не сработает.
6. Start recording.
7. Scenarios:
   a. Idle 30s connected (steady-state)
   b. Trigger network change (toggle airplane mode briefly) (on-demand
      reconnect event)
   c. Idle 30s post-reconnect
8. Stop recording.
9. Анализ: smae как D.1 но для PacketTunnelProvider process.
   Особый интерес: libbox-related allocations (Go runtime objects
   из gomobile binding).
```

**Known issue (Matt Eaton):** Error `"This copy of libswiftCore.dylib requires an OS version prior to 12.2.0"` при attach к extension. **Solution:** Add `/usr/lib/swift` как first item в Runtime Search Paths (Build Settings) для tunnel provider target. Это уже сделано в Phase 1 — verify в Wave 06D-02 Task 0 [ASSUMED — flag for verify].

**Memory regression threshold:**
- **HIGH:** retained-size growth >10MB unaccounted-for after baseline scenarios completion
- **MEDIUM:** >2MB but <10MB
- **LOW:** <2MB drift considered noise [ASSUMED — refined after baseline].

[ASSUMED — exact iPhone class for thresholds — iPhone 13 vs iPhone 15 Pro имеют разный baseline memory headroom. Treat thresholds as relative to baseline + delta, не absolute.]

### E. macOS counterparts

```text
- App Launch / Time Profiler / Allocations templates все работают на macOS
  через target = "My Mac" в Instruments.
- Energy Log: на macOS используется альтернативный template "Energy Log
  (macOS)" с CPU/wake/disk lanes. Не путать с iPhone Energy Log.
- Packet Tunnel extension: macOS Packet Tunnel extension runs тоже как
  separate process; attach pattern идентичен (Running Applications list).
  Если у пользователя установлена system extension (vs app extension),
  процесс называется иначе — но всё равно через Running Applications.
- Cold launch path для macOS:
  scheme = BBTB-macOS (НЕ BBTB-iOS); entry point = BBTB_macOSApp.swift
  (149 LOC). Сравнить cold launch iPhone vs MacBook поможет понять,
  где зашиты iOS-specific bottlenecks (NEVPN XPC) vs cross-platform
  (SwiftData, registries).
```

### F. Trace storage rules (D-07c — re-emphasized)

| File type | Action |
|---|---|
| `.trace` (Instruments binary) | **NEVER commit to git**. Store locally в `~/Documents/BBTB-traces/` или временно в `.planning/phases/06d-performance-audit/traces-local/` (must be in `.gitignore`). |
| Markdown summary | **Commit**. `.planning/phases/06d-performance-audit/baselines/{scenario}-{platform}-{prefix}.md` |
| Screenshot of timeline | **Commit as PNG** в `.planning/phases/06d-performance-audit/baselines/screenshots/`. Size <1MB per file. Naming: `cold-launch-iphone-pre-fix.png` etc. |
| `wiki/performance-baseline.md` | **Commit**. Cross-link to per-scenario markdown files. Phase 6d Final wave updates с post-fix numbers. |

---

## Code-Simplicity / Dead-Code Detection

### Primary tool: Periphery 3.7.4

[VERIFIED: github.com/peripheryapp/periphery — released 2026-04-26]

**Installation:**
```bash
brew install peripheryapp/periphery/periphery
periphery version  # expect 3.7.4 or newer
```

**Tuist compatibility:** [VERIFIED via WebFetch — поддержки явной "Tuist" нет в docs, но Periphery работает с любым **xcworkspace** + **schemes**, что Tuist именно генерирует.] Tuist project уже создаёт `BBTB.xcworkspace` + schemes (BBTB, BBTB-macOS); Periphery подключается стандартным flow.

**Canonical invocation для BBTB:**

```bash
# В корне проекта (где BBTB/Workspace.swift):
cd BBTB
tuist generate  # ensure xcworkspace is up-to-date

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

**Why each flag:**
- `--workspace BBTB.xcworkspace + --schemes`: standard для multi-target workspace.
- `--targets`: списком явно перечисляем оба host app + оба extension targets — Periphery должна build их и анализировать перекрёстные references.
- `--retain-public`: SPM packages exporting public API — мы можем не использовать public symbol внутри **этого** workspace, но external consumer (Phase 7 будет использовать) может. False-positive trap.
- `--retain-objc-accessible`: `@objc` annotated symbols accessible через Obj-C runtime, Periphery их не видит как referenced.
- `--report-exclude`: skip test files и .build artifacts.

**False positives — known classes для BBTB:**

| Class | Mitigation |
|---|---|
| `@main struct BBTB_iOSApp: App` | Entry point — Periphery видит как unreferenced без `--retain-objc-accessible`. |
| SPM package public types использованные только в tests | `--retain-public` митигирует. |
| Conformance to protocols (e.g., Decodable types использованные через Codable runtime) | `--retain-codable-properties` flag (Periphery 3.5+). |
| sing-box config JSON template structs (parsed через Codable) | Same as above. |
| `@MainActor static let` lazy init helpers | Static side-effect-only init может выглядеть unused. Manual review required. |

### Backup tool: SwiftLint analyze mode

[CITED: realm.github.io/SwiftLint/unused_declaration.html]

SwiftLint `unused_declaration` rule в `analyze` mode дополняет Periphery — реже даёт false positives на specific patterns (но и реже находит cross-file dead code). **Use as second-pass** после Periphery, на специфических hotspots (`ConfigImporter.swift`, `MainScreenViewModel.swift`).

```bash
# В корне проекта:
xcodebuild -workspace BBTB/BBTB.xcworkspace -scheme BBTB \
           -destination 'generic/platform=iOS Simulator' \
           build > xcodebuild-output.log
swiftlint analyze \
  --compiler-log-path xcodebuild-output.log \
  --reporter emoji \
  > ../.planning/phases/06d-performance-audit/swiftlint-analyze.txt
```

**Note:** SwiftLint analyze require'ует свежий xcodebuild log; rebuild на каждый run.

### Grep-audit pattern (Phase 6c B-08 inheritance)

> [VERIFIED: 06C-04-SUMMARY.md] Phase 6c использовала awk-stripped grep для verification что forbidden symbols удалены. Phase 6d наследует pattern.

```bash
# Phase 6c invariant check — должно вернуть 0:
cd BBTB/Packages/AppFeatures/Sources
grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay\|triggerRecoveryIfNeeded\|lastKnownStatus" . \
  | awk '!/^[[:space:]]*\/\//'  # strip single-line comments
# Phase 6c: expected 7 (Round 5 carve-out — connectInProgress, manualDisconnectInProgress).
# Phase 6d: should remain 7 or fewer.
```

Phase 6d может добавить новые forbidden patterns на основе finding categories:
- `"\.main\)"` в NEVPNStatusDidChange observer setup (queue: .main banned per memory `feedback_nevpn_observer_queue_main.md`)
- `"loadAllFromPreferences"` count в hot paths (each addition is suspect — Phase 6c reduced это к минимуму)
- `"#Predicate.*UUID"` (banned per memory `feedback_swiftdata_uuid_predicate.md`)

### Anti-patterns specific to BBTB stack

[ASSUMED — these are pattern-recognition hypotheses; AI passes will confirm or refute с file:line evidence]

| Anti-pattern | Likely location | How to detect |
|---|---|---|
| `@Published` thrash — multiple sequential mutations | `MainScreenViewModel`, `ServerListViewModel` | grep `@Published` count + manual review of mutation sequences |
| Accidentally-retained Combine subscriptions | Anywhere using `.sink { }` без `.store(in:)` | grep `\.sink\b` + manual review for capture lists |
| `Task { }` inside view body re-init | SwiftUI views | grep `\.task\s*{` vs `Task\s*{` inside `body` |
| ViewModel re-init on NavigationStack push | `BBTBRootView`, etc. | grep `@StateObject` inside ViewBuilder closures |
| SwiftData `#Predicate` with optional UUID | Anywhere | grep `#Predicate.*UUID?` |
| XPC inside hot paths | NEVPNStatusDidChange observer | Phase 6c invariant — grep `loadAllFromPreferences` near `NEVPNStatusDidChange` |
| Singleton init на app launch вместо lazy | `*.shared\.register` | check `App.init` body для register calls |

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---|---|---|---|
| Custom interval timing | `Date()` differences printed in OSLog | `OSSignposter` + Instruments | OSSignposter integrates automatically with Instruments timeline; no manual mapping; iOS 15+ Swift API. [CITED: developer.apple.com/documentation/os/ossignposter] |
| Custom cold-launch measurement | `CFAbsoluteTimeGetCurrent()` differences | Xcode Instruments **App Launch template** | App Launch template separates pre-main (dyld) от main-to-first-frame automatically; manual approach mixes both. [VERIFIED: WWDC19 #423 + WebSearch] |
| Custom dead-code detection | Manual `grep -L "func X"` across project | **Periphery 3.7.4** | Periphery builds cross-file reference graph via SourceKit. Manual grep misses transitive references, protocol conformances, generic usage. [VERIFIED: github.com/peripheryapp/periphery] |
| Custom Energy attribution | `MetricKit` polling | Instruments **Energy Log** (iPhone Settings → Developer → Logging) | Apple-managed per-subsystem attribution (CPU, network, location, display). Real device required. MetricKit hourly summaries не дают spike resolution. [CITED: developer.apple.com/library/archive — Energy Efficiency Guide for iOS Apps] |
| Custom memory leak detection | Manual `class A { deinit { print } }` instrumentation | Instruments **Allocations** template + generations/snapshots | Allocations builds full retained-size accounting; finds reference cycles automatically. Manual approach misses ARC cycle detection. |
| Custom multi-AI consensus voting | Hand-rolled merge of 3 findings outputs | **Identical 7-section delegation brief** (per `~/.claude/rules/delegator.md`) + manual synthesis with deterministic rules (D-04 consensus markers) | Identical inputs to 3 AIs minimize bias; deterministic synthesis rules avoid favoritism. [VERIFIED: ~/.claude/rules/delegator.md] |

**Key insight:** Phase 6d не вводит нового runtime кода — это **measurement + analysis** phase. Custom tooling здесь == reinventing wheel. Apple-blessed paths (Instruments, OSSignposter, MetricKit) и community-standard paths (Periphery) — обязательны.

---

## Runtime State Inventory

> Not applicable in classical sense — Phase 6d не выполняет rename/refactor с string replacement. **Однако** есть тонкость: некоторые findings могут затронуть state, и planner должен это учитывать.

| Category | Items Found | Action Required |
|---|---|---|
| Stored data | **None** — verified by reading 06C-04-SUMMARY (Phase 6c data layer untouched; SwiftData store schema unchanged) | No data migration |
| Live service config | **Potential:** if findings touch `manager.protocolConfiguration.providerConfiguration` (sing-box JSON shipped в extension), users may need to disconnect+reconnect для apply. | Document в Wave 06D-Final SUMMARY: "если пользователь активный — рекомендуется reconnect для применения" |
| OS-registered state | **None** — Phase 6c уже мигрировала `isOnDemandEnabled`; new install path unchanged. | No re-registration |
| Secrets / env vars | **None** — Phase 6d не трогает Keychain, SOPS, или environment | None |
| Build artifacts | **Potential:** SwiftPM `.build/` directories — если Periphery scan делается на dirty `.build`, false negatives. Wave 06D-02 Task 0 включает `swift package clean` перед scan. | Clean before Periphery / SwiftLint analyze |

---

## Common Pitfalls

### Pitfall 1: False uniqueness в multi-AI findings (synthesis trap)

**What goes wrong:** Три AI находят одну и ту же реальную проблему, но описывают её разными `file:line`. Opus указывает на `ConfigImporter.swift:450`, Codex на `ConfigImporter.swift:447`, Gemini вообще говорит "в области парсинга URI". При синтезе появляется три отдельных entries вместо одного.

**Why it happens:** AI пасс читает код в разное время, может цитировать строку рядом с реальной проблемой, либо описывать общую проблему без точной локализации.

**How to avoid:**
- В audit brief MUST DO: "cite exact File:Line" (это уже включено выше).
- При синтезе: для каждого finding смотреть, **что описано**, не **где** — если описание семантически идентично, это один finding с `Found by: Opus + Codex + Gemini`.
- Создать explicit dedup pass в Wave 06D-02 Task 2 (после 3 file merge, before consensus markers).

**Warning signs:** более 5 findings с identical "Description" но разными "File:Line" — почти наверняка одна реальная проблема, splintered across passes.

### Pitfall 2: AI recommends rollback of Phase 6c invariant (D-09 violation)

**What goes wrong:** Свежий AI-аудитор без context Phase 6c history может увидеть `applyVPNStatus(_:connectedDate:)` как single authority и заметить "это monolithic — split на 2 method". Любое такое предложение — D-09 violation.

**Why it happens:** Phase 6c context огромен (5 waves, 6 rounds, multi-AI architect reviews) — даже identical 7-section brief не даст full understanding. AI делает "по best practice" reasoning без awareness что это уже было rejected по reason.

**How to avoid:**
- В audit brief CONSTRAINTS секция — verbatim перечислить 5 Phase 6c invariants (уже включено).
- В synthesis: фильтр "Filtered — violates Phase 6c invariant" — отдельная секция в `06D-FINDINGS.md`, не drop, не downgrade. Это создаёт audit trail и помогает counter-argue если user попросит revisit.
- Cross-reference с `wiki/auto-reconnect.md` "Lessons learned" в synthesis review.

**Warning signs:** finding mentions `ReconnectStateMachine`, `NetworkReachability`, "split single-authority", "move XPC to observer", "remove sliding window".

### Pitfall 3: Pre-fix measurement становится post-fix baseline (accidental contamination)

**What goes wrong:** Wave 06D-02 captures Instruments traces. Wave 06D-03 starts fixes. Если по ошибке `wiki/performance-baseline.md` записывается с **mixed** numbers — pre-fix from Tuesday, post-fix from Wednesday, no clear delineation — comparison невозможна.

**Why it happens:** Без explicit file-naming discipline, "baseline" mutates over phase.

**How to avoid:**
- **Strict file naming:** `cold-launch-iphone-pre-fix.md`, `cold-launch-iphone-post-fix-wave-N.md`. Никаких generic "current.md".
- **Pre-fix файлы — frozen** после Wave 06D-02 sign-off. Любое изменение — отдельный suffix `-rerun.md`.
- **`wiki/performance-baseline.md` table:** explicit columns `pre-fix` and `post-fix`, не "current".
- **Git lock:** после Wave 06D-02 commit, `pre-fix` files не должны изменяться. Any change = explicit revision commit с reason.

**Warning signs:** baseline file modified after CHECKPOINT 1 without `-revised` suffix; numbers в wiki без clear "pre" / "post" annotation.

### Pitfall 4: User checkpoint fatigue от 70+ LOW findings

**What goes wrong:** Если три AI passes найдут 100+ findings, и user стоит перед списком — фокус на HIGH/MEDIUM не работает, потому что LOW findings создают шум.

**Why it happens:** AI passes конфигурированы найти всё (D-05 — все 5 dimensions equally weighted). LOW threshold (<50ms) низок — там много кандидатов.

**How to avoid:**
- В synthesis (Wave 06D-02): **cluster LOW findings по theme** (e.g., "Dead code in ConfigImporter — 12 items", "Test coverage gaps — 8 items", "Style inconsistencies — 15 items") — один row в high-level summary, expand-to-detail для каждого cluster.
- В CHECKPOINT 1 presentation user: показать count by severity + by dimension; **не показывать full list** на одной странице. Drill-down по запросу.
- В CONTEXT.md уже отражено: D-06 "Определим после findings" — explicit checkpoint design.

**Warning signs:** `06D-FINDINGS.md` >100 rows без clustering; user reaction "слишком много, не разобраться".

### Pitfall 5: Atomic-commit churn (30+ commits для one phase)

**What goes wrong:** "Atomic commit per fix" pattern (Phase 6c heritage) может стать pathological при 50 LOW findings — 50 separate commits для cosmetic refactors. Git log unreadable, code review невозможен.

**Why it happens:** Pattern был designed для Phase 6c где fixes имели architectural significance. Cosmetic fixes — другая категория.

**How to avoid:**
- **Bundle same-file / same-theme fixes в один commit.** Пример: 12 dead-code items в `ConfigImporter.swift` — **one commit** "chore(06d): cleanup dead code in ConfigImporter (12 items per FINDINGS)" + body — bullet list of removed items + line counts.
- **Atomic per-theme, не per-finding** для cosmetic / LOW severity. HIGH severity — все ещё per-finding (architectural significance).
- **Plan recommends commit cadence:** в Wave 06D-03..N plan structure, list "Expected commits: ~N" — guide для executor.

**Warning signs:** git log за Phase 6d показывает >30 commits без architectural narrative.

### Pitfall 6: Test regression detected after wave but root cause is earlier wave

**What goes wrong:** Wave 06D-04 ставит fix; AppFeatures 133/133 → 130/133. Root cause может быть в Wave 06D-04 OR в bug introduced в Wave 06D-03 что прошёл tests but failed integration.

**Why it happens:** Tests test functional behavior; performance refactor может изменить timing characteristics that break flaky tests или expose hidden bugs.

**How to avoid:**
- **`git bisect` cadence checkpoint** в plan: после wave с unexpected test failure — first action `git bisect` между last green commit и current HEAD.
- **Pre-wave checkpoint:** перед start каждой fix-wave, run **full** regression suite (D-08) — must be 133/133. Если current main не 133/133, **STOP** — fix existing before adding new.
- **Bisect-friendly commits:** atomic per-fix (HIGH) / per-theme (LOW) makes bisect возможным. Один mega-commit per wave — bisect bisects ничего.

**Warning signs:** AppFeatures tests fail with message обращённым к unrelated test method; reverting last commit не fixes — bisect needed.

### Pitfall 7: Energy Log untethered measurement contamination

**What goes wrong:** Energy Log scenarios записаны на iPhone untethered (per recommendation). Если в этот же window:
- iPhone делает iCloud sync
- Background app refresh для других apps
- Push notification arrives
- Wi-Fi/LTE handoff

Numbers для BBTB зашумлены — Energy Log attributes CPU/network to **all** processes, не только BBTB.

**Why it happens:** Real-device measurement realistic but untethered = uncontrolled.

**How to avoid:**
- **Pre-scenario discipline:** Airplane mode → Wi-Fi only → close all other apps (multitask swipe) → Settings → Battery → "Last 24 hours" cleared.
- **Multiple samples** (≥3) per scenario; median, не mean.
- **Document conditions** в baseline.md: "iPhone background apps closed, Wi-Fi only, airplane mode off, no other VPN active".
- **Counter-check via tethered Time Profiler** — если CPU% in Energy Log не matches CPU% trace, есть contamination.

**Warning signs:** Energy Log shows huge "Other" lane (non-BBTB activity); CPU% varies >50% between samples.

### Pitfall 8: AI proposes adding new dependency (D-02a violation)

**What goes wrong:** Codex/Gemini могут увидеть problem, для которого existing dependencies не оптимальны, и предложить добавить новую (e.g., "use ComposableArchitecture instead of @Published" или "add Logging library для structured logs").

**Why it happens:** AI "best practice" reasoning. Без explicit constraint, default — propose best tool for job.

**How to avoid:**
- Brief CONSTRAINTS уже включает "no new dependencies unless explicit user-impact justification" — но AI может попытаться justify.
- В synthesis: для finding предлагающего dependency, **must include**: (a) measurable user-impact (>200ms saved? >5MB binary saved?), (b) alternative without dep (downgrade в LOW если без dep не impactful).
- Default action: **DROP** unless user-impact justification meets HIGH/MEDIUM threshold.

**Warning signs:** finding mentions specific 3rd-party package name; "use library X for this" without metrics.

---

## Code Examples

### Example 1: OSSignposter modern API (iOS 15+) для cold-start marker

```swift
// Source: developer.apple.com/documentation/os/ossignposter
//         + swiftwithmajid.com/2022/05/04/measuring-app-performance-in-swift/
import os.signpost

// Global signposter (subsystem matches existing OSLog категорию в codebase)
private let perfSignposter = OSSignposter(
    subsystem: "app.bbtb.client.ios",
    category: "performance"
)

@main
struct BBTB_iOSApp: App {
    private let coldStartState: OSSignpostIntervalState

    init() {
        // BEGIN interval: cold-start span starts at App.init entry
        self.coldStartState = perfSignposter.beginInterval(
            "ColdLaunch",
            id: perfSignposter.makeSignpostID()
        )

        // ... все existing init code (CrashReporter, registries, SwiftData, etc.)
    }

    var body: some Scene {
        WindowGroup {
            BBTBRootView(viewModel: viewModel)
                .onAppear {
                    // END interval: first interactive frame
                    perfSignposter.endInterval("ColdLaunch", coldStartState)
                }
        }
    }
}
```

**В Instruments:** select target = BBTB, template = "Blank" → add Instrument "os_signpost" → on timeline появится "ColdLaunch" lane с begin/end markers.

### Example 2: Connect-tap span с nested probe + provision

```swift
// Source: training knowledge + Apple docs pattern
extension TunnelController {
    func performToggleImpl() async throws -> Bool {
        // Begin overall ConnectTap span
        let connectState = perfSignposter.beginInterval("ConnectTap")
        defer { perfSignposter.endInterval("ConnectTap", connectState) }

        // Nested span: probe
        let probeState = perfSignposter.beginInterval("PreConnectProbe")
        let winner = try await preConnectProbe()
        perfSignposter.endInterval("PreConnectProbe", probeState)

        // Nested span: provision
        let provState = perfSignposter.beginInterval("ProvisionProfile")
        try await provisionTunnelProfile(winner)
        perfSignposter.endInterval("ProvisionProfile", provState)

        // tunnel.connect() — extension boundary, separate signposts там
        try await connectAndAwait()

        return true
    }
}
```

### Example 3: Periphery scan output processing

```bash
# Source: github.com/peripheryapp/periphery CLI help
# Generate Periphery scan report:
periphery scan \
  --workspace BBTB/BBTB.xcworkspace \
  --schemes BBTB BBTB-macOS \
  --retain-public \
  --retain-objc-accessible \
  --format json \
  > periphery-output.json

# Pretty-print findings count by file:
jq -r '.[] | "\(.location.file):\(.location.line) \(.kind) \(.name)"' \
   periphery-output.json | \
   sort | uniq -c | sort -rn | head -20
```

### Example 4: 7-section delegation brief invocation (Codex)

```javascript
// Source: ~/.claude/rules/delegator.md 7-section format
// Researcher pseudo-code — planner finalizes в Wave 06D-01.
await mcp__codex__codex({
    developer-instructions: read("~/.claude/plugins/cache/.../prompts/code-reviewer.md"),
    sandbox: "read-only",
    cwd: "/Users/vergevsky/ClaudeProjects/VPN",
    prompt: `
1. TASK: Independent peer-review audit of BBTB iOS+macOS codebase...
2. EXPECTED OUTCOME: 06D-FINDINGS-CODEX.md with table format...
3. CONTEXT:
   - Current state: ...
   - Relevant code: ...
   - Background: ...
4. CONSTRAINTS:
   - Technical: ...
   - Patterns: ...
   - Limitations (Phase 6c invariants — verbatim):
     * TunnelController.handleStatusChange intent-closing UNCHANGED
     * No XPC in NEVPNStatusDidChange observer
     * ...
5. MUST DO: ...
6. MUST NOT DO: ...
7. OUTPUT FORMAT: Markdown at .planning/phases/06d-performance-audit/06D-FINDINGS-CODEX.md
    `.trim()
});
```

---

## State of the Art (2026 update)

| Old Approach | Current Approach | When Changed | Impact |
|---|---|---|---|
| `os_signpost(_:dso:log:name:signpostID:)` C-style API | `OSSignposter` Swift API (iOS 15+) | iOS 15 (2021) | Type-safe, Swift-native, IDE-friendly. Use modern API for new code. [VERIFIED: WebSearch confirmed multiple sources noting "older os_signpost API is now deprecated, new methods introduced since iOS 15"] |
| Manual `Time Profiler` template + manual setup | `App Launch` template (Apple-blessed automated launch profiling) | Xcode 11 / iOS 13 (2019) | App Launch automatically captures pre-main + main-to-first-frame phases; reduces setup time from minutes to seconds. [VERIFIED: WWDC19 #423] |
| `SwiftLint unused_declaration` only | **Periphery** (specialized, SourceKit-based) | Periphery widespread adoption ~2020+ | Periphery builds full graph; SwiftLint stays for style. Use both, Periphery primary. [VERIFIED: github.com/peripheryapp/periphery + community articles] |
| Custom `ReconnectStateMachine` (Phase 6) | `NEOnDemandRule` + sliding session window (Phase 6c) | BBTB Phase 6c (2026-05-13) | Eliminates 4 bug classes (phantom reconnect, XPC storm, fight-back, port exhaustion). [VERIFIED: 06C-04-SUMMARY.md, wiki/auto-reconnect.md] |
| `os.log` `Logger` for performance | Continue using `Logger` for diagnostics + `OSSignposter` for timing | iOS 15 (2021) | Different tools for different jobs: Logger = text log; OSSignposter = Instruments timeline spans. |
| `MetricKit` для on-device perf | Continue (Phase 12 territory) | iOS 13 (2019) | MetricKit = aggregate metrics hourly; supplements Instruments measurements; **не** заменяет device profiling. [ASSUMED — not in Phase 6d scope, but worth flagging для Phase 12] |

**Deprecated / outdated approaches to AVOID:**

- **Plain `print(Date().timeIntervalSince(start))` для timing.** Не integrates с Instruments; не sub-millisecond accurate; manual mapping painful.
- **Simulator для Energy Log.** Не работает [VERIFIED: Apple docs — Energy Log requires real device].
- **App Extensions list для Instruments attach.** Не работает per Apple DTS engineer; use Running Applications list instead [VERIFIED: developer.apple.com/forums/thread/654914].
- **Symbol-by-symbol Combine subscription leak detection.** Use Instruments Allocations + Leaks; manual approach unreliable.

---

## Assumptions Log

> Claims tagged `[ASSUMED]` в этом research require user confirmation в discuss-phase / planner gate. Planner и executor должны verify эти assumptions в Wave 06D-02 Task 0 (Instruments baseline preparation) или earlier.

| # | Claim | Section | Risk if Wrong |
|---|---|---|---|
| A1 | `SwiftDataContainer.makeShared()` может быть >100ms hot path | Architecture Patterns / Pattern 2 | Если на самом деле <50ms, refactor усложнения не стоит. Verify by Instruments в Wave 06D-02. |
| A2 | Registry register calls (`ProtocolRegistry.shared.register`) могут страдать от thread coordination | Architecture Patterns / Pattern 3 | Если registries уже @MainActor static, рекомендация — no-op. Verify by reading registry implementation в Wave 06D-02 Task 0. |
| A3 | Memory regression thresholds (10MB HIGH / 2MB MEDIUM) — точные числа | Instruments Workflow / D | Зависят от iPhone model. Refined after baseline collection. |
| A4 | Energy regression thresholds (Impact tier shift / CPU% 25%-100%) | Instruments Workflow / C | Refined after baseline. |
| A5 | "true cold launch" achievable через force-quit + 10s wait | Instruments Workflow / A | iOS warm-cache lifetime может быть >10s. If results sus, reboot device для truly cold. |
| A6 | Periphery 3.7.4 fully supports Tuist-generated xcworkspace | Code-Simplicity / Primary tool | Periphery docs не упоминают Tuist explicitly, но Tuist выводит standard xcworkspace + schemes — Periphery работает с теми. Verify в Wave 06D-02 Task 0 via dry-run. |
| A7 | Signposts уже не добавлены в codebase (нужно добавлять в Wave 06D-02) | Multiple sections | Grep `OSSignposter\|os_signpost` в Wave 06D-02 Task 0 для verify. Если уже есть — reuse. |
| A8 | `/usr/lib/swift` runtime search path для Tunnel extension target — set | Instruments Workflow / D.2 | Phase 1 R8 mentions это для libbox compatibility; assumed still set. Verify by reading `Project.swift` Tuist config в Wave 06D-02. |
| A9 | macOS Energy Log имеет separate template name ("Energy Log (macOS)") | Instruments Workflow / E | Mac Instruments может объединить templates. Verify в Wave 06D-02. |
| A10 | `BBTB_macOSApp.swift` имеет parallel structure с iOS app (149 vs 156 LOC similar) | Code Examples / Anti-patterns | Both files должны получать одинаковые signpost-style additions; verify divergence в audit pass. |

---

## Open Questions

1. **Какие именно signposts уже existed в codebase (если есть)?**
   - What we know: A7 lists `OSSignposter`/`os_signpost` grep как TODO для Wave 06D-02 Task 0.
   - What's unclear: текущий counts.
   - Recommendation: Wave 06D-02 Task 0 starts с grep; если nonzero, document existing pattern.

2. **Реальный cost Phase 1 baseline missing.**
   - What we know: D-07b confirms "Phase 1 baseline недоступен".
   - What's unclear: какой threshold для success criteria "cold-start time ≤ Phase 1 baseline" (Roadmap line 199).
   - Recommendation: либо replace SC #5 в Roadmap на "≤ user perception threshold (RAIL 100ms response, 1s perceptual)", либо capture pre-fix как proxy baseline + SC = "≤ pre-fix" — degenerate то же что post-fix ≤ pre-fix. Discuss with user в Wave 06D-Final closure.

3. **macOS Packet Tunnel extension architecture: app extension vs system extension?**
   - What we know: iOS = app extension (`PacketTunnelExtension-iOS/PacketTunnelProvider.swift`).
   - What's unclear: macOS — может быть SystemExtension (Apple recommend в macOS 11+). Влияет на Instruments attach pattern.
   - Recommendation: Wave 06D-02 Task 0 reads `BBTB/App/PacketTunnelExtension-macOS/` Info.plist + entitlements для определения; planner затем подбирает attach instruction.

4. **Three-AI parallel vs serial — actual wall-clock budget?**
   - What we know: Opus runs внутри текущего thread; Codex single-shot через MCP; Gemini single-shot через MCP с fallback chain.
   - What's unclear: realistic time-to-completion для каждой pass — Opus может быть minutes (current context), Codex/Gemini — каждый ~30-60s but Gemini fallback может занять до 10 мин на retries.
   - Recommendation: Wave 06D-01 plan envelopes "expected pass duration: Opus 5-15min, Codex 1-5min, Gemini 1-15min (with fallback)". Track actual в `06D-01-SUMMARY.md`.

5. **Synthesis bias: Opus делает synthesis из 3 passes, включая own pass.**
   - What we know: D-04 specifies Opus synthesizes.
   - What's unclear: bias toward own findings.
   - Recommendation: explicit synthesis rules в `06D-01-PLAN.md`:
     - Когда Opus's и Codex/Gemini's финдинги конфликтуют, default — **другой AI's wins** (anti-bias rule).
     - Synthesis must include explicit "rejected my own finding because..." entries when Opus's finding не survives consensus.

---

## Environment Availability

> Phase 6d требует tooling доступности; researcher проверяет typical setup. Planner enforces в Wave 06D-02 Task 0.

| Dependency | Required By | Available | Version | Fallback |
|---|---|---|---|---|
| Xcode 16+ | Instruments + xcodebuild | [ASSUMED ✓] | check via `xcodebuild -version` | Required — no fallback |
| iPhone iOS 26.5 (real device) | Time Profiler / Energy Log / Allocations on device | [ASSUMED ✓] (Phase 6c re-UAT used this same device) | iOS 26.5 | Required — Energy Log impossible on Simulator |
| MacBook Apple Silicon | BBTB-macOS xcodebuild + Instruments macOS profiling | [ASSUMED ✓] (project constraint) | macOS Sequoia / Tahoe | Required для D-02 scope |
| `mcp__codex__codex` MCP server | Codex GPT-5.2 pass | [VERIFIED ✓ — Phase 6c used same] | latest | If unavailable: skip Codex pass, document |
| `mcp__gemini__gemini` MCP server | Gemini 3.1 Pro pass | [VERIFIED ✓ — Phase 6c used same; auth confirmed 2026-05-13] | latest | Fallback chain D-03; if все 5 — skip Gemini, document |
| **Periphery 3.7.4** | Dead-code detection | [ASSUMED ✗] (not in current dev env per check needed) | 3.7.4 | `brew install peripheryapp/periphery/periphery` — Wave 06D-02 Task 0 includes install |
| SwiftLint | Backup dead-code + style | [ASSUMED ✓] (typical Swift project) | latest | `brew install swiftlint` if missing |
| `git bisect` | Pitfall 6 mitigation | [VERIFIED ✓] (git installed) | system | None needed |
| `jq` | Periphery JSON output processing | [ASSUMED ✗] (typical dev tool but check) | latest | `brew install jq` if missing |
| `ripgrep` (`rg`) | Forbidden-symbol audits (Phase 6c B-08 pattern) | [ASSUMED ✓] (typical dev tool) | latest | `brew install ripgrep` if missing |

**Missing dependencies with no fallback:** Periphery (most likely missing на dev machine), но `brew install` тривиально — Wave 06D-02 Task 0 covers это.

**Missing dependencies with fallback:** Если Gemini API completely down (>1 hour outage), Phase 6d продолжает с 2 passes per D-03; final FINDINGS marks Gemini как "skipped".

---

## Validation Architecture

> `workflow.nyquist_validation: true` в `.planning/config.json` — секция включена.

### Test Framework

| Property | Value |
|---|---|
| Framework | Swift Testing / XCTest (mixed; AppFeatures uses XCTest per `swift test` invocation) |
| Config file | `BBTB/Packages/AppFeatures/Package.swift` (test target declared); no separate config |
| Quick run command | `swift test --package-path BBTB/Packages/AppFeatures` (≤30s — Phase 6c last ran 7.55s for 133/133) |
| Full suite command | `swift test --package-path BBTB/Packages/AppFeatures` + adjacent packages (`swift test --package-path BBTB/Packages/VPNCore` etc.) + `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'generic/platform=iOS Simulator' build` + `xcodebuild ... -scheme BBTB-macOS -destination 'platform=macOS' build` |
| Phase gate | All three (test + iOS build + macOS build) green BEFORE start of next fix-wave |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|---|---|---|---|---|
| PERF-01 | Cold start path measurable + improvable | manual (Instruments) | Instruments App Launch template → save markdown export | ❌ Wave 0 — `wiki/performance-baseline.md` + `baselines/cold-launch-iphone-pre-fix.md` |
| PERF-02 | Connect tap path measurable | manual (Instruments) | Instruments Time Profiler + signpost markers | ❌ Wave 0 — signposts addition + baseline file |
| PERF-03 | Energy regression budget honored | manual (Energy Log) | iPhone Settings → Developer → Logging → Energy → import via Console.app | ❌ Wave 0 — baseline file |
| PERF-04 | Memory regression budget honored | manual (Allocations) | Instruments Allocations template, host + extension processes | ❌ Wave 0 — baseline file |
| QUAL-01 | Dead code identified + removed | automated | `periphery scan ...` (Wave 06D-02 + post-fix re-scan) | ❌ Wave 0 — Periphery install + initial scan output file |
| QUAL-02 | Phase 6c invariants preserved | automated | grep audit + `swift test --package-path BBTB/Packages/AppFeatures` (must remain 133/133) | ✅ existing (TunnelControllerTests, 7 tests) |
| QUAL-03 | Multi-AI synthesis consensus markers | manual | review `06D-FINDINGS.md` for `Consensus` column completeness | ❌ Wave 06D-02 produces file |

### Sampling Rate

- **Per task commit (fix-wave atomic):** `swift test --package-path BBTB/Packages/AppFeatures` (~8s) + grep B-08-style forbidden-symbol audit
- **Per wave merge (between fix-waves):** Full suite — AppFeatures tests + adjacent packages (VPNCore, ConfigParser, etc., per Phase 6c precedent) + iOS Simulator xcodebuild + BBTB-macOS xcodebuild
- **Phase gate (06D-Final):** Full suite green + post-fix Instruments traces captured + comparison delta documented в `wiki/performance-baseline.md`

### Wave 0 Gaps (Wave 06D-02 task list)

- [ ] **Signposts addition** — add `OSSignposter` `beginInterval`/`endInterval` pairs to:
  - `BBTB_iOSApp.swift` + `BBTB_macOSApp.swift` (ColdLaunch span)
  - `TunnelController.performToggleImpl` (ConnectTap span + nested PreConnectProbe / ProvisionProfile)
  - `PacketTunnelProvider.swift` iOS+macOS (LibboxStart span inside extension)

- [ ] **Periphery install + initial scan** — `brew install peripheryapp/periphery/periphery` + first scan to `periphery-scan-pre-fix.txt`

- [ ] **Baseline file scaffolding** — create empty templates:
  - `.planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md`
  - `.../baselines/cold-launch-macbook-pre-fix.md`
  - `.../baselines/connect-tap-iphone-pre-fix.md`
  - `.../baselines/energy-iphone-pre-fix.md`
  - `.../baselines/allocations-iphone-host-pre-fix.md`
  - `.../baselines/allocations-iphone-extension-pre-fix.md`
  - `.../baselines/screenshots/` (directory)

- [ ] **`wiki/performance-baseline.md` initial draft** — page format per CLAUDE.md template (Summary, Sources, Last updated header) + table skeleton with `pre-fix` / `post-fix` columns

- [ ] **`.gitignore` update** — ensure `.planning/phases/06d-performance-audit/traces-local/**` ignored (binary `.trace` files)

- [ ] **Verify A2 / A6 / A7 / A8** assumptions through code reads (registry implementations, Tuist config, existing signpost grep, runtime search paths)

- [ ] **MCP availability check** — confirm `mcp__codex__codex` + `mcp__gemini__gemini` responsive before Wave 06D-01 dispatch

---

## Sources

### Primary (HIGH confidence)

- `~/.claude/rules/delegator.md` — 7-section delegation brief format (VERIFIED via Read)
- `06D-CONTEXT.md` — D-01..D-11b locked decisions (VERIFIED via Read)
- `06C-04-SUMMARY.md` — Phase 6c invariants D-09 source (VERIFIED via Read)
- `wiki/auto-reconnect.md` — Phase 6c long-term reasoning (VERIFIED via Read)
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` — actual cold-start path code (VERIFIED via Read)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` — line counts confirmed (VERIFIED via `wc -l`)
- `.planning/config.json` — `nyquist_validation: true` confirmed (VERIFIED via Read)
- developer.apple.com/forums/thread/654914 — Apple DTS Engineer Matt Eaton on Instruments attach for Packet Tunnel extension (VERIFIED via WebFetch)

### Secondary (MEDIUM-HIGH confidence)

- developer.apple.com/documentation/os/ossignposter — OSSignposter modern API (CITED, page title only via WebFetch; content cross-referenced via Swift by Sundell article)
- web.dev/articles/rail — RAIL thresholds (100ms response, 1s load, 50ms input handling) (VERIFIED via WebFetch — direct quotes)
- github.com/peripheryapp/periphery — Periphery 3.7.4 release date 2026-04-26 + features (VERIFIED via WebFetch)
- developer.apple.com/videos/play/wwdc2019/423/ — Optimizing App Launch (referenced via WebSearch — App Launch template overview)
- swiftbysundell.com/wwdc2018/getting-started-with-signposts/ — `os_signpost` legacy API example code (VERIFIED via WebFetch)
- realm.github.io/SwiftLint/unused_declaration.html — SwiftLint analyze mode (CITED via WebSearch)
- developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time — Apple launch-time docs (CITED via WebSearch)
- developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/ — Energy Efficiency Guide (CITED via WebSearch)

### Tertiary (LOWER confidence — мнения / community)

- medium.com / hackingwithswift.com / swiftwithmajid.com и подобные — community articles referenced для cross-verification of API patterns; не sole source of truth for any prescription.
- Donny Wals article — legacy `os_signpost` example (VERIFIED via WebFetch); modern OSSignposter API only briefly hinted at, cross-referenced.

---

## Metadata

**Confidence breakdown:**

- **Standard Stack:** HIGH — Periphery 3.7.4 version verified; Xcode 16/Instruments verified via Apple docs; OSSignposter via Swift by Sundell + Apple docs page title; SwiftLint analyze mode via official docs.
- **Architecture Patterns / Cold-start anatomy:** HIGH for code path (read actual `BBTB_iOSApp.swift`); MEDIUM for optimization recommendations (А1-A3 ASSUMED — depend on actual Instruments measurements).
- **Architecture Patterns / Connect-tap anatomy:** HIGH for high-level steps; MEDIUM for exact span boundaries (signposts not yet inserted — A7).
- **Multi-AI brief template:** HIGH — 7-section structure from delegator.md verified; consensus rules from D-04 verbatim.
- **Instruments workflow:** HIGH for procedure (Apple DTS verified для Packet Tunnel attach; App Launch template via WWDC); MEDIUM for thresholds (A3, A4 ASSUMED).
- **Dead-code detection:** HIGH (Periphery primary, SwiftLint backup — both confirmed via official docs).
- **Common pitfalls:** HIGH for synthesis pitfalls (general patterns); MEDIUM for BBTB-specific patterns (A1-A10 ASSUMED).
- **Severity rubric / RAIL alignment:** HIGH — RAIL thresholds verified from web.dev verbatim; CONTEXT.md D-05a rubric checks out against RAIL.

**Research date:** 2026-05-14
**Valid until:** 2026-05-28 (14 days — short window because:
  - Instruments tooling stable, но iOS / Xcode point releases могут invalidate specific attach details
  - Periphery active development — version bump может invalidate specific flag recommendations
  - AI delegation paths (Codex / Gemini fallback chain) — sufficient for current session, re-verify if delay >7d).

---

*Research для Phase 6d Performance & Code Quality Audit. Consumed by `gsd-planner` для производства `06D-01-PLAN.md` ... `06D-Final-PLAN.md`. Updates на этот файл — только в случае substantive correction (typo OK без revision; addition of clarifying examples OK; structural change requires `-revised` suffix + commit entry).*
