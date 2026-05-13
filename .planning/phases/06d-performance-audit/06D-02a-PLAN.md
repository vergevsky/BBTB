---
phase: 06d-performance-audit
plan: 02a
slice: a
type: execute
wave: 2.1
mode: mvp
depends_on: [01]
files_modified:
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift
  - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift
  - .gitignore
  - .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
  - .planning/phases/06d-performance-audit/baselines/screenshots/.gitkeep
  - .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md
  - .planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md
  - .planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
autonomous: true
requirements: [QUAL-01]
tags: [wave0-gaps, periphery, signposts, baseline-templates, atomic-commits, instrumentation-only]

must_haves:
  truths:
    - "Periphery 3.7.4+ установлен; первый verification scan (без output записи) выполнен; jq + ripgrep установлены."
    - "OSSignposter инъекции добавлены в cold-start (BBTB_iOSApp + BBTB_macOSApp) и connect-tap hot path (TunnelController.performToggleImpl) и LibboxStart (PacketTunnelProvider iOS+macOS)."
    - "PerfSignposter.swift создан как sibling к TunnelLogger.swift pattern."
    - "Все 5 ASSUMED-claims (A1/A2/A6/A7/A8 + Open Q #3 + sing-box template count) проверены против кода и зафиксированы в 06D-02a-PREFLIGHT.md."
    - "6 baseline file templates созданы (пустые header skeletons — наполняются в 06D-02c)."
    - ".gitignore содержит `*.trace` + `traces-local/`."
    - "AppFeatures swift test 133/133 + iOS + macOS xcodebuild green между каждым из 3 atomic commits."
    - "Никаких изменений в бизнес-логике — только инструментация."
    - "D-09 Phase 6c invariants preserved — forbidden symbol grep ≤ 7 carve-out, observer queue=.main = 0, #Predicate UUID? = 0."
  artifacts:
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift"
      provides: "Shared OSSignposter enum (siblings к TunnelLogger.swift pattern)"
      contains: "OSSignposter(subsystem"
    - path: ".planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md"
      provides: "ASSUMED claims verification log + Periphery/jq/ripgrep install verification"
      contains: "ASSUMED claims"
    - path: ".planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md"
      provides: "Atomic commit cadence verification — 3 commits с regression gate между каждым"
      contains: "Commit 1.*Commit 2.*Commit 3"
    - path: ".planning/phases/06d-performance-audit/06D-02a-SUMMARY.md"
      provides: "Wave 02a closure record"
  key_links:
    - from: "PerfSignposter.swift"
      to: "BBTB_iOSApp.init + MainScreenView.onAppear (ColdLaunch span)"
      via: "beginInterval / endInterval pair"
      pattern: "ColdLaunch"
    - from: "PerfSignposter.swift"
      to: "TunnelController.performToggleImpl (ConnectTap + nested PreConnectProbe + ProvisionProfile)"
      via: "beginInterval / endInterval / defer"
      pattern: "ConnectTap|PreConnectProbe|ProvisionProfile"
    - from: "PerfSignposter.swift"
      to: "PacketTunnelProvider iOS+macOS (LibboxStart span)"
      via: "beginInterval / endInterval"
      pattern: "LibboxStart"
---

# Phase 6d Wave 02a — Wave 0 gaps: Periphery + signposts + baseline templates (3 atomic commits)

## Цель волны (по-русски)

Wave 06D-02a закрывает **Wave 0 gaps** (то, что должно было быть готово ещё до Wave 06D-01, но описано в RESEARCH секции `## Validation Architecture / Wave 0 Gaps`). Это **infrastructure prep** для Wave 06D-02c (pre-fix Instruments baseline).

**Атомарность 3 commits** (per checker WARNING fix): Wave 0 gaps декомпозированы на ТРИ atomic commits с **полным regression gate D-08 после КАЖДОГО**:

- **Commit 1** — `chore(06d-02a): install Periphery 3.7.4 + jq + ripgrep verification` (tooling only, no source).
- **Commit 2** — `feat(06d-02a): add PerfSignposter + inject ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart spans` (instrumentation, no behavior).
- **Commit 3** — `docs(06d-02a): scaffold Instruments baseline templates + .gitignore *.trace + ASSUMED-claim verification log` (scaffolding only).

После Wave 06D-02a → Wave 06D-02b (synthesis) → Wave 06D-02c (pre-fix Instruments + CHECKPOINT 1 prep).

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
@BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift
@BBTB/App/iOSApp/BBTB_iOSApp.swift
@BBTB/App/macOSApp/BBTB_macOSApp.swift
@CLAUDE.md
@wiki/auto-reconnect.md
</context>

<interfaces>
<!-- TunnelLogger.swift pattern (existing) — образец для PerfSignposter.swift -->

From BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift:
```swift
public enum TunnelLogger {
    public static let general = Logger(subsystem: "app.bbtb.tunnel", category: "general")
    public static let lifecycle = Logger(subsystem: "app.bbtb.tunnel", category: "lifecycle")
    public static let libbox = Logger(subsystem: "app.bbtb.tunnel", category: "libbox")
    public static let security = Logger(subsystem: "app.bbtb.tunnel", category: "security")
}
```

Existing subsystem names (verified by grep in 06D-PATTERNS.md Role J):
- `app.bbtb.client.ios` — BBTB_iOSApp.swift:30 (diag)
- `app.bbtb.tunnel` — TunnelLogger.swift
- `app.bbtb.client` — TunnelController.swift:69
- `app.bbtb.server-list`, `app.bbtb.subscription-merge`, `app.bbtb.server-probe`, `app.bbtb.app`

→ PerfSignposter.swift добавит `category: "performance"` к этим subsystems как новый sibling.

Span naming convention (per RESEARCH line 469): `ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`. PascalCase.
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1 — Commit 1: Periphery 3.7.4 + jq + ripgrep tooling install + verification (no source changes)</name>
  <files>
    .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (секции «Standard Stack / Tool installation», «Assumptions Log» A6, «Open Questions» 1-5)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role J — OSSignposter injection)
    - .gitignore (текущее состояние — не трогать в этом commit)
  </read_first>
  <action>
    **Commit 1 — TOOLING ONLY.** Никаких изменений в source-коде. Только установка инструментов и запись результата в PREFLIGHT.md.

    **Шаги:**

    1. **Periphery install + verification (verifies A6):**
       ```bash
       which periphery 2>/dev/null && periphery version || brew install peripheryapp/periphery/periphery
       periphery version   # ожидаем 3.7.4+
       ```
       Если `brew` отсутствует или install fail — escalate user. Документировать version в `06D-02a-PREFLIGHT.md`.

    2. **`jq` + `ripgrep` install if missing** (A6 + Standard Stack):
       ```bash
       which jq || brew install jq
       which rg || brew install ripgrep
       ```

    3. **Periphery + Tuist compat verification** (A6 second half):
       ```bash
       cd BBTB && tuist generate
       # Mini dry-run — single target, минимальный output, просто чтобы убедиться что periphery умеет читать workspace.
       periphery scan --workspace BBTB.xcworkspace --targets BBTB --retain-public --report-exclude '**/Tests/*.swift' 2>&1 | head -5
       ```
       Результат — в PREFLIGHT.md (full output не сохраняем; первый production scan — в Wave 06D-02c).

    4. **Create `06D-02a-PREFLIGHT.md`** — записать:
       - Periphery version (actual).
       - jq + rg versions.
       - Mini-scan result (success / partial / fail с error message).
       - Date + commit SHA.

    5. **Regression gate** (per WARNING fix Commit 1 cadence — no source changes, но прогоняем для baseline):
       ```bash
       swift test --package-path BBTB/Packages/AppFeatures   # 133/133 PASS
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build   # BUILD SUCCEEDED
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build   # BUILD SUCCEEDED
       ```

    6. **Atomic Commit 1:**
       ```
       chore(06d-02a): install Periphery 3.7.4 + jq + ripgrep verification

       - Periphery <version> installed via brew.
       - jq + ripgrep installed if missing.
       - Tuist + Periphery compat verified (mini dry-run on BBTB target).
       - Results recorded in 06D-02a-PREFLIGHT.md.

       No source changes. Regression gate green: AppFeatures 133/133 + iOS + macOS BUILD SUCCEEDED.
       ```
  </action>
  <verify>
    <automated>
      periphery version 2>/dev/null | grep -E "^[0-9]+\.[0-9]+\.[0-9]+" \
        && which jq >/dev/null && which rg >/dev/null \
        && test -f .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md \
        && grep -qiE "periphery|version" .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md \
        && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "passed|0 failures"
    </automated>
  </verify>
  <done>
    Periphery 3.7.4+ + jq + ripgrep установлены и verified; 06D-02a-PREFLIGHT.md содержит install result; regression gate green; ни одного source файла не изменено в этом commit; atomic Commit 1 создан.
  </done>
</task>

<task type="auto">
  <name>Task 2 — Commit 2: PerfSignposter + 5 span injection sites (ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart) — instrumentation only</name>
  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift
    BBTB/App/iOSApp/BBTB_iOSApp.swift
    BBTB/App/macOSApp/BBTB_macOSApp.swift
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
    BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift
    BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (Pattern 1 OSSignposter; span naming convention)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role J — OSSignposter injection)
    - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelLogger.swift (analog для PerfSignposter)
    - BBTB/App/iOSApp/BBTB_iOSApp.swift (cold-start entry — full read, 156 LOC)
    - BBTB/App/macOSApp/BBTB_macOSApp.swift (macOS cold-start — full read, 149 LOC)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (performToggleImpl — span injection target)
    - BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift (LibboxStart span target)
    - BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift (LibboxStart span target)
  </read_first>
  <action>
    **Commit 2 — INSTRUMENTATION ONLY.** Никаких behavioral changes. Только OSSignposter инъекции в hot path для будущих pre-fix/post-fix measurements.

    **Шаги:**

    1. **Create `PerfSignposter.swift`** в `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift`. Структура — sibling к TunnelLogger.swift pattern:
       ```swift
       import os.signpost

       public enum PerfSignposter {
           public static let app = OSSignposter(
               subsystem: "app.bbtb.client.ios",
               category: "performance"
           )
           public static let appMac = OSSignposter(
               subsystem: "app.bbtb.client.macos",
               category: "performance"
           )
           public static let tunnel = OSSignposter(
               subsystem: "app.bbtb.tunnel",
               category: "performance"
           )
           public static let client = OSSignposter(
               subsystem: "app.bbtb.client",
               category: "performance"
           )
       }
       ```
       Файл — `public enum` (не `class`) для namespace-only. iOS 15+ OSSignposter API (per RESEARCH State of the Art table).

    2. **Inject ColdLaunch span в `BBTB_iOSApp.swift`:**
       - `import os.signpost` (добавить если ещё нет).
       - В struct property: `private let coldStartState: OSSignpostIntervalState`.
       - В `init()` первой строкой: `self.coldStartState = PerfSignposter.app.beginInterval("ColdLaunch", id: PerfSignposter.app.makeSignpostID())`. Остальной init body — без изменений.
       - В root view (`BBTBRootView` либо WindowGroup contents) — `.onAppear { PerfSignposter.app.endInterval("ColdLaunch", coldStartState) }`. Если onAppear уже занят — добавить вторую .onAppear modifier.
       - **Не менять никакой бизнес-логики** — только инструментация.

    3. **Inject ColdLaunch span в `BBTB_macOSApp.swift`** — symmetric, но subsystem `PerfSignposter.appMac` (см. PerfSignposter.swift выше).

    4. **Inject ConnectTap / PreConnectProbe / ProvisionProfile spans в `TunnelController.performToggleImpl`:**
       - `let connectState = PerfSignposter.client.beginInterval("ConnectTap")` в начале performToggleImpl body.
       - `defer { PerfSignposter.client.endInterval("ConnectTap", connectState) }` — pair the end.
       - Nested span `PreConnectProbe` оборачивает probe call.
       - Nested span `ProvisionProfile` оборачивает provisionTunnelProfile call.
       - **D-09 invariant pre-check** (sensitive file TunnelController.swift):
         - `handleStatusChange` НЕ изменяется (только performToggleImpl). Verify `git diff` до commit.
         - Никаких XPC calls в NEVPNStatusDidChange observer.
         - Никаких ReconnectStateMachine/NetworkReachability references.
         - applyVPNStatus authority intact.
         - Sliding window invariant intact.

    5. **Inject LibboxStart span в `PacketTunnelProvider.swift` (iOS + macOS):**
       - В `startTunnel(options:completionHandler:)` — `let libState = PerfSignposter.tunnel.beginInterval("LibboxStart")` после parse providerConfiguration, перед `libbox.Start()`.
       - `PerfSignposter.tunnel.endInterval("LibboxStart", libState)` после `setTunnelNetworkSettings` returned (когда туннель готов).
       - Это **отдельный процесс** — pattern идентичный, но subsystem `app.bbtb.tunnel`.
       - **D-09 invariant pre-check** (sensitive file PacketTunnelProvider — entry point): только signpost begin/end, никаких behavioral changes в flow.

    6. **D-09 forbidden symbol grep** (после всех injections):
       ```bash
       cd BBTB/Packages/AppFeatures/Sources
       grep -rn "ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay" . | awk '!/^[[:space:]]*\/\//' | wc -l
       # Должно быть ≤ 7 (carve-out)
       grep -rn "NEVPNStatusDidChange.*queue:.*\.main\)\|NEVPNStatusDidChange.*queue:.*OperationQueue.main" . | wc -l
       # Должно быть 0
       grep -rn "#Predicate.*UUID?" . | wc -l
       # Должно быть 0
       ```

    7. **Regression gate** (D-08 — обязательно после инструментации):
       ```bash
       swift test --package-path BBTB/Packages/AppFeatures   # 133/133 PASS
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build   # BUILD SUCCEEDED
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build   # BUILD SUCCEEDED
       ```
       Если какой-то check fail — STOP, откатить signpost injection до зелёного состояния.

    8. **Atomic Commit 2:**
       ```
       feat(06d-02a): add PerfSignposter + inject ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart spans

       - PerfSignposter.swift: sibling enum к TunnelLogger pattern (4 subsystems × performance category).
       - BBTB_iOSApp.swift + BBTB_macOSApp.swift: ColdLaunch span init → root view onAppear.
       - TunnelController.performToggleImpl: ConnectTap (outer) + PreConnectProbe + ProvisionProfile (nested) — NO changes to handleStatusChange (D-09 invariant preserved).
       - PacketTunnelProvider iOS+macOS: LibboxStart span around libbox.Start() → setTunnelNetworkSettings.

       Instrumentation only — no behavioral changes. D-09 forbidden grep ≤ 7 carve-out / 0 / 0. Regression gate green.
       ```
  </action>
  <verify>
    <automated>
      test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift \
        && grep -q "OSSignposter(subsystem" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/PerfSignposter.swift \
        && grep -q "ColdLaunch" BBTB/App/iOSApp/BBTB_iOSApp.swift \
        && grep -q "ColdLaunch" BBTB/App/macOSApp/BBTB_macOSApp.swift \
        && grep -qE "ConnectTap|PreConnectProbe|ProvisionProfile" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift \
        && grep -q "LibboxStart" BBTB/App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift \
        && grep -q "LibboxStart" BBTB/App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift \
        && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "passed|0 failures"
    </automated>
  </verify>
  <done>
    PerfSignposter.swift существует и компилируется; 5 span injection sites in place (Cold iOS + Cold macOS + ConnectTap + PreConnectProbe + ProvisionProfile + LibboxStart iOS + LibboxStart macOS — 7 точек итого); D-09 forbidden grep clean; regression gate green; atomic Commit 2 создан.
  </done>
</task>

<task type="auto">
  <name>Task 3 — Commit 3: baseline templates + .gitignore + ASSUMED-claim verification log</name>
  <files>
    .gitignore
    .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md
    .planning/phases/06d-performance-audit/baselines/screenshots/.gitkeep
    .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md
    .planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md
    .planning/phases/06d-performance-audit/06D-02a-SUMMARY.md
  </files>
  <read_first>
    - .planning/phases/06d-performance-audit/06D-RESEARCH.md (Role K — baseline markdown shape; Assumptions Log A1-A10; Open Questions 1-5)
    - .planning/phases/06d-performance-audit/06D-PATTERNS.md (Role K — baseline shape; Role M — summary shape)
    - .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md (созданный в Task 1 — будет extended ASSUMED claims)
    - BBTB/Packages/ProtocolRegistry/Sources/ (для A2 registry threading verification)
    - BBTB/Packages/TransportRegistry/Sources/ (для A2)
    - BBTB/App/PacketTunnelExtension-macOS/Info.plist (для Open Q #3 — macOS extension type)
    - BBTB/Project.swift (для A8 — /usr/lib/swift runtime search paths)
  </read_first>
  <action>
    **Commit 3 — SCAFFOLDING ONLY.** Документация + .gitignore. Никаких изменений в production source (PerfSignposter и span injections уже в Commit 2).

    **Шаги:**

    1. **`.gitignore` update:**
       - Добавить:
         ```
         # Phase 6d Instruments artifacts (binary, do not commit)
         .planning/phases/06d-performance-audit/traces-local/
         *.trace
         ```
       - Если уже есть — verify, не дублировать.

    2. **Create baseline file templates** — пустые markdown по shape RESEARCH Role K (PATTERNS строки 314-360):
       - `.planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md`
       - `.../baselines/cold-launch-macbook-pre-fix.md`
       - `.../baselines/connect-tap-iphone-pre-fix.md`
       - `.../baselines/energy-iphone-pre-fix.md`
       - `.../baselines/allocations-iphone-host-pre-fix.md`
       - `.../baselines/allocations-iphone-extension-pre-fix.md`
       - `.../baselines/screenshots/.gitkeep` (создать пустой файл — git tracks empty dir)

       Каждый template содержит header skeleton (Summary / Date / Device / iOS / App version / Samples / Methodology / Numerical summary table / Top heavy stack traces / OSSignposter spans). Numerical таблицы — пустые с column headers. Wave 06D-02c наполнит реальными данными.

    3. **Extend `06D-02a-PREFLIGHT.md` — ASSUMED claims verification** (A1-A10 из RESEARCH `## Assumptions Log` + Open Questions 1-5):
        - **A1** — SwiftDataContainer.makeShared() cost: read implementation, отметить нужно ли deferral (decision — после baseline в Wave 06D-02c).
        - **A2** — Registry register thread coordination: read `ProtocolRegistry.swift` + `TransportRegistry.swift` implementation, документировать (`@MainActor static`? actor? lock?).
        - **A6** — Periphery + Tuist compat: уже verified в Commit 1; повторить запись в PREFLIGHT.
        - **A7** — Existing signpost grep: повторить из 06D-01 Task 0 (`grep -rn "OSSignposter\|os_signpost" BBTB --include="*.swift"`). После injection в Commit 2 — count должен быть ≥3 (PerfSignposter + spans).
        - **A8** — `/usr/lib/swift` runtime search path для tunnel extension target в Tuist config: `grep -r "/usr/lib/swift" BBTB/Project.swift BBTB/Workspace.swift` или Project.swift Tuist DSL.
        - **Open Q #3** — macOS Packet Tunnel extension type (app extension vs system extension): прочитать `BBTB/App/PacketTunnelExtension-macOS/Info.plist` + entitlements; определить и зафиксировать.
        - **Sing-box JSON templates count** (Open Q implicit): `find BBTB/Packages/PacketTunnelKit -name "*.json" -type f | wc -l` — researcher указал 6 (RESEARCH); verify.

    4. **Create `06D-02a-WAVE0-VERIFY.md`** — записать atomic commit cadence (3 commits + regression gate между каждым):
       ```markdown
       # Wave 06D-02a — Wave 0 gaps atomic commit verification

       **Date**: 2026-05-NN

       ## Commit cadence (per checker WARNING fix — atomic 3-commit decomposition)

       | # | Commit message prefix | Files changed | Regression gate result | Status |
       |---|---|---|---|---|
       | 1 | `chore(06d-02a): install Periphery 3.7.4 + jq + ripgrep verification` | 06D-02a-PREFLIGHT.md only | AppFeatures 133/133, iOS+macOS BUILD SUCCEEDED | ✅ |
       | 2 | `feat(06d-02a): add PerfSignposter + inject ColdLaunch/ConnectTap/PreConnectProbe/ProvisionProfile/LibboxStart spans` | 6 source files (PerfSignposter + 2 App + TunnelController + 2 PacketTunnelProvider) | AppFeatures 133/133, iOS+macOS BUILD SUCCEEDED | ✅ |
       | 3 | `docs(06d-02a): scaffold Instruments baseline templates + .gitignore *.trace + ASSUMED-claim verification log` | 6 baseline templates + .gitignore + PREFLIGHT extended + WAVE0-VERIFY + SUMMARY | AppFeatures 133/133, iOS+macOS BUILD SUCCEEDED | ✅ |

       ## D-09 invariant grep audit (after Commit 2)

       | Check | Required | Actual | Status |
       |---|---|---|---|
       | Forbidden symbols (ReconnectStateMachine\|NetworkReachability\|ReconnectStateObserverRelay) | ≤ 7 (carve-out) | NN | ✅ |
       | NEVPN observer queue=.main | 0 | 0 | ✅ |
       | #Predicate UUID? | 0 | 0 | ✅ |
       | OSSignposter usages | ≥ 7 (post-injection) | NN | ✅ |
       ```

    5. **Create `06D-02a-SUMMARY.md`** (Role M shape) — short closure record для Wave 02a.

    6. **Regression gate** (Commit 3 final):
       ```bash
       swift test --package-path BBTB/Packages/AppFeatures   # 133/133 PASS
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB -destination 'generic/platform=iOS Simulator' build
       xcodebuild -project BBTB/BBTB.xcodeproj -scheme BBTB-macOS -destination 'platform=macOS' build
       ```

    7. **Atomic Commit 3:**
       ```
       docs(06d-02a): scaffold Instruments baseline templates + .gitignore *.trace + ASSUMED-claim verification log

       - 6 baseline markdown templates (cold iOS/macOS, connect iOS, energy iOS, allocations host+extension iOS) — empty skeleton, filled in 06D-02c.
       - .gitignore: *.trace + traces-local/ (D-07c — no binary traces in git).
       - 06D-02a-PREFLIGHT.md extended with A1/A2/A6/A7/A8 + Open Q #3 + template count verification.
       - 06D-02a-WAVE0-VERIFY.md: atomic 3-commit cadence record (per checker WARNING fix).
       - 06D-02a-SUMMARY.md: wave closure record.

       Scaffolding only — no production source changes. Regression gate green.
       ```
  </action>
  <verify>
    <automated>
      grep -qE "\.trace|traces-local" .gitignore \
        && test -f .planning/phases/06d-performance-audit/baselines/cold-launch-iphone-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/cold-launch-macbook-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/connect-tap-iphone-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/energy-iphone-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/allocations-iphone-host-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/allocations-iphone-extension-pre-fix.md \
        && test -f .planning/phases/06d-performance-audit/baselines/screenshots/.gitkeep \
        && test -f .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md \
        && grep -qiE "ASSUMED|A1|A6|A7" .planning/phases/06d-performance-audit/06D-02a-PREFLIGHT.md \
        && test -f .planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md \
        && grep -qE "Commit 1|Commit 2|Commit 3" .planning/phases/06d-performance-audit/06D-02a-WAVE0-VERIFY.md \
        && test -f .planning/phases/06d-performance-audit/06D-02a-SUMMARY.md \
        && swift test --package-path BBTB/Packages/AppFeatures 2>&1 | grep -qE "passed|0 failures"
    </automated>
  </verify>
  <done>
    .gitignore содержит *.trace; 6 baseline templates + .gitkeep созданы; 06D-02a-PREFLIGHT.md extended with full ASSUMED verification (A1/A2/A6/A7/A8 + Open Q #3 + template count); 06D-02a-WAVE0-VERIFY.md фиксирует 3-commit cadence + D-09 grep audit; 06D-02a-SUMMARY.md closure record; regression gate green; atomic Commit 3 создан.
  </done>
</task>

</tasks>

<verification>

**Wave-level acceptance (после всех 3 atomic commits):**

1. **Commit 1 (tooling)** прошёл с green regression gate. PREFLIGHT.md содержит Periphery/jq/rg versions.
2. **Commit 2 (instrumentation)** прошёл с green regression gate. 5 span injection sites in place; D-09 forbidden grep clean.
3. **Commit 3 (scaffolding)** прошёл с green regression gate. 6 baseline templates + .gitignore + extended PREFLIGHT + WAVE0-VERIFY + SUMMARY созданы.
4. **WAVE0-VERIFY.md** документирует все 3 commits + per-commit regression result + D-09 grep audit.
5. Никакой бизнес-логики не изменено — только инструментация.
6. **D-09 invariants preserved:**
   - Никаких изменений в `TunnelController.handleStatusChange` (только performToggleImpl instrumentation).
   - Никаких изменений в NEVPNStatusDidChange observer.
   - Никаких новых XPC trips в hot path.
   - Никаких #Predicate UUID? введений.
   - Никаких revival ReconnectStateMachine / NetworkReachability.

</verification>

<success_criteria>

- [ ] 3 atomic commits созданы в порядке: tooling → instrumentation → scaffolding.
- [ ] Regression gate green после **каждого** из 3 commits (не только в конце wave).
- [ ] PerfSignposter.swift + 5+ span injection sites in place.
- [ ] Periphery 3.7.4+ + jq + rg установлены.
- [ ] 6 baseline templates + .gitkeep + .gitignore + PREFLIGHT + WAVE0-VERIFY + SUMMARY созданы.
- [ ] ASSUMED claims (A1/A2/A6/A7/A8 + Open Q #3 + template count) verified.
- [ ] D-09 invariants preserved (forbidden grep ≤ 7; observer queue=.main = 0; #Predicate UUID? = 0).
- [ ] AppFeatures 133/133 + iOS xcodebuild + macOS xcodebuild — все green после каждого commit.

</success_criteria>

<output>
После завершения создан `06D-02a-SUMMARY.md`. 3 atomic commits в git history. Next: Wave 06D-02b (synthesis).
</output>
</content>
</invoke>