---
phase: 06c-on-demand-migration
plan: 04
type: execute
wave: 4
depends_on: ["06c-on-demand-migration:03"]
files_modified:
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift
autonomous: false
requirements: [NET-08, NET-09, NET-10, NET-11]
must_haves:
  truths:
    - "OnDemandMigrationTask.runIfNeeded() invoked once per app launch from BBTB_iOSApp + BBTB_macOSApp init path (async Task), before TunnelController setup"
    - "TunnelController использует TunnelWatchdog для mid-session failover вместо ReconnectStateMachine — handleStatusChange(.disconnected) делегирует в watchdog"
    - "TunnelController имеет cachedManager: NETunnelProviderManager? property (Round 2 B-03) — populated в startReachability() + refreshed через NotificationCenter observer для .bbtbProvisionerDidSave. Используется как managerEnabled gate для watchdog handleStatusChange — вместо broken `lastKnownStatus != .invalid` proxy"
    - "TunnelController.connect() / disconnect() после setUserIntent дополнительно вызывают OnDemandRulesBuilder.applyCurrentState(to: cachedManager) + save + reload — гарантирует что toggle && intent gate flip приводит к immediate manager.isOnDemandEnabled update (Round 2 B-04 wiring complement)"
    - "macOS NSWorkspace.didWakeNotification observer сохранён (D-11/12/13) — startVPNTunnel() идемпотентный nudge с 3 guards (W-06): manager.isEnabled + manager.isOnDemandEnabled + loadAutoReconnectEnabled — БЕЗ XPC trips для status reading"
    - "ReconnectBanner state теперь derived из NEVPNStatus snapshots + TunnelWatchdog setFailoverObserver callback (а не ReconnectStateMachineState enum) — enum trimmed: .retrying + .allFailed removed, .connecting added"
    - "Files DELETED в Task 3c: ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift — НО `ReconnectClock.swift` (extracted в Plan 03 Task 2.5 per B-01) и `TestClocks.swift` (per B-02) ПРЕСЕРВЕРЫ"
    - "TunnelController.swift сократился (Task 3a): removed handleReachability, triggerRecoveryIfNeeded, scheduleFailoverResetAfterStableSession, manualDisconnectInProgress/connectInProgress/wakePending flags, ReconnectStateObserverRelay, lastKnownStatus cache, scheduleClearManualDisconnect"
    - "UserIntentStore и userIntendedConnected flag сохранены — watchdog читает их через TunnelController.setUserIntent передающий вниз; OnDemandMigrationTask и watchdog gate используют один источник истины"
    - "Connect()/disconnect() контракт сохранён verbatim: Phase 1-5 polling loops + timeouts identical (Round 2 wiring дополняет — НЕ заменяет — bodies)"
    - "Новый TunnelControllerTests.swift покрывает connect/disconnect contract (replaces deleted TunnelControllerStateTests); 6 tests minimum"
    - "Task 3 split into 3a/3b/3c per W-01 — context-budget safety"
    - "Task 3c acceptance grep использует awk comment-stripping pre-step (B-08) — doc-comments не дают false positives"
    - "Device UAT 9 сценариев — hard-blocker set {A, C, E, F, G, I} (Round 2 B-10) на iPhone iOS 26.5 + macOS перед merge cutover commit (checkpoint)"
  artifacts:
    - path: "BBTB/App/iOSApp/BBTB_iOSApp.swift"
      provides: "Wire OnDemandMigrationTask.runIfNeeded() in app init"
      contains: "OnDemandMigrationTask.runIfNeeded"
    - path: "BBTB/App/macOSApp/BBTB_macOSApp.swift"
      provides: "Wire OnDemandMigrationTask.runIfNeeded() in app init"
      contains: "OnDemandMigrationTask.runIfNeeded"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift"
      provides: "Slimmed actor — connect/disconnect + watchdog wiring + macOS wake + status observer for banner only"
      max_lines: 350
    - path: "BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift"
      provides: "Connect/disconnect contract preservation tests (D-24 category 2)"
      min_lines: 100
  key_links:
    - from: "BBTB_iOSApp.init (async Task)"
      to: "OnDemandMigrationTask.runIfNeeded"
      via: "Task { await OnDemandMigrationTask.runIfNeeded() } перед tunnel setup"
      pattern: "OnDemandMigrationTask\\.runIfNeeded"
    - from: "BBTB_macOSApp.init (async Task)"
      to: "OnDemandMigrationTask.runIfNeeded"
      via: "Task at startup"
      pattern: "OnDemandMigrationTask\\.runIfNeeded"
    - from: "TunnelController NEVPNStatusDidChange observer"
      to: "TunnelWatchdog.handleStatusChange"
      via: "await watchdog.handleStatusChange(status, managerEnabled: cachedManager?.isEnabled ?? false) — Round 2 B-03 fix"
      pattern: "watchdog\\.handleStatusChange"
    - from: "ConfigImporter / SettingsViewModel / OnDemandMigrationTask post"
      to: "TunnelController cachedManager refresh observer"
      via: "NotificationCenter .bbtbProvisionerDidSave observer (Round 2 B-03 cross-plan)"
      pattern: "bbtbProvisionerDidSave"
    - from: "TunnelController.connect / disconnect"
      to: "TunnelWatchdog.setUserIntent"
      via: "await watchdog.setUserIntent(true/false)"
      pattern: "watchdog\\.setUserIntent"
    - from: "MainScreenViewModel.reconnectBannerState"
      to: "NEVPNStatus + watchdog signals"
      via: "Replace ReconnectStateMachineState consumption"
      pattern: "reconnectBannerState"
---

## Phase Goal

**As a** user upgrading from Phase 6 to Phase 6c, **I want to** keep my VPN connection auto-recovering across network changes, sleep, and server failures with NONE of the previous Phase 6 UAT bug classes (phantom reconnect, XPC storm, fight-back with other VPN apps, EXC_RESOURCE), **so that** my one-tap VPN simply works through any mobility event without me having to think about it.

<objective>
Wave 3 / Cutover + Cleanup — **Wire new components into TunnelController + App entry points, run device UAT, ONLY THEN delete old components.** Это inflection-point wave: до этой wave старая custom-reconnect machinery всё ещё работала parallel-run. После этой wave она уходит навсегда.

Структура wave (Round 2 W-01 — Task 3 split into 3a/3b/3c):

1. **Task 1 — Wire** OnDemandMigrationTask в App init (iOS + macOS), wire TunnelWatchdog в TunnelController, **cachedManager B-03 fix** + bbtbProvisionerDidSave observer, **connect()/disconnect() applyCurrentState complement (Round 2 B-04 wiring)**, macOS wake observer с 3 guards (W-06). PRESERVE connect()/disconnect() bodies verbatim — only NEW lines added after setUserIntent.
2. **Task 2 — Device UAT** — checkpoint:human-verify. 9 сценариев на iPhone iOS 26.5 + macOS smoke. Hard-blocker set {A, C, E, F, G, I} per Round 2 B-10. Если ALL hard PASS → proceed. Если ANY hard FAIL → STOP, fix-forward.
3. **Task 3a — TunnelController slim-down** (Round 2 W-01 split): delete stored props/methods listed in original Step 2; update handleStatusChange to use `cachedManager?.isEnabled ?? false` (B-03); preserve startReachability, macOS wake observer, connect/disconnect bodies. Acceptance: TunnelController.swift ≤ 350 lines, builds green.
4. **Task 3b — Banner state rewire** (Round 2 W-01 split, includes W-02 audit): grep all `case .retrying` / `case .allFailed` consumer sites BEFORE mutating enum (W-02). Update MainScreenViewModel banner state mapping. Add `setFailoverObserver` к TunnelWatchdog (deferred from Plan 03 Task 3). ReconnectBanner enum: add `.connecting`, remove `.retrying` / `.allFailed`. Acceptance: builds green; no consumer site references removed cases.
5. **Task 3c — Cleanup + create TunnelControllerTests** (Round 2 W-01 split): DELETE 5 files (RSM + tests + NetReach + tests + TCST) — **PRESERVE ReconnectClock.swift (B-01) + TestClocks.swift (B-02)**. CREATE TunnelControllerTests.swift (6 tests). Update App entry points (drop ReconnectStateObserverRelay). Acceptance: full xcodebuild green; awk-stripped grep returns 0 for deleted symbol references (B-08).
6. **Final build + commit** — cutover commit.

Purpose:
- D-10/D-14/D-15 cleanup полностью выполнен — ~570 строк custom auto-reconnect logic удалено.
- D-16 preservation invariant: FailoverProvider.swift, SwiftDataFailoverProvider остаются unchanged.
- D-11/D-12/D-13: macOS wake observer specifically preserved (cheap idempotent nudge `startVPNTunnel()`, NO XPC).
- D-17 narrow: NEVPNStatusDidChange observer остаётся ТОЛЬКО для (a) banner UI feeding и (b) delegate в watchdog для mid-session failover. Никаких recovery branches.
- OQ-2 решение: `userIntendedConnected` (UserIntentStore) **сохраняем как локальный gate watchdog'а** — переименовать переменную нет necessity, semantics остаётся «user wants tunnel». connectInProgress/manualDisconnectInProgress flags **удалены** — они нужны были только для recovery path race protection, в новой архитектуре нет recovery path.
- OQ-3 решение: TunnelWatchdog как **отдельный actor file** (создан в Plan 06C-03), wired в TunnelController через late-binding setter (mirror того как failoverProvider wires).
- OQ-6 решение: FailoverProvider.connect closure НЕ изменяется. Apple's on-demand параллельно reconnect'ит — может попасть в «уже .connecting»; TunnelController.connect() polling loop уже трактует `.disconnecting` как transient (line 282 comment). Если Apple's запустил с старого config — наш swap saveToPreferences с новым config заставит OS перезагрузить config. UAT-Task E validate this.
- OQ-7 решение: Banner state map — `.connecting` → "Подключение"; `.reasserting` → "Переподключение"; watchdog `nextServerAttempt called` → "Переключение на другой сервер" (failover signal); никакого `allFailed` (Apple's on-demand крутится дольше — UX-неправильно говорить «всё failed», пока iOS retries). **Round 2 W-02**: enum mutation в Task 3b предваряется grep audit всех consumer sites.

Output (8 files changed + 2 new tests + 5 deleted files):
- App entry points (iOS + macOS): migration task wired.
- TunnelController: slimmed; uses TunnelWatchdog; macOS wake preserved.
- MainScreenViewModel: banner state mapping rewired.
- ReconnectBanner: text labels for new state mapping.
- DELETED: ReconnectStateMachine.swift + tests, NetworkReachability.swift + tests, TunnelControllerStateTests.swift.
- NEW: TunnelControllerTests.swift (D-24 category 2).

**Это пользователь-блокирующая wave**: между Task 2 и Task 3 — checkpoint device UAT. Если UAT fails, Task 3 cleanup НЕ выполняется. Roll-back путь: revert commit от Task 1+2; Wave 0-2 остаются valid (builder + parallel run).
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@.planning/phases/06c-on-demand-migration/06C-CONTEXT.md
@.planning/phases/06c-on-demand-migration/06C-RESEARCH.md
@.planning/phases/06c-on-demand-migration/06C-01-PLAN.md
@.planning/phases/06c-on-demand-migration/06C-02-PLAN.md
@.planning/phases/06c-on-demand-migration/06C-03-PLAN.md

<interfaces>
<!-- Existing TunnelController public API (preserved verbatim per D-15): -->
```swift
public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
    func startReachability() async   // RENAMED / RESHAPED in Wave 3 → setUp() or similar (planner choice)
    func stopReachability() async    // RENAMED / RESHAPED
    func handleForeground() async    // Может быть deleted (Pitfall 8: cheap no-op)
}
```

Wave 3 решение: оставить `startReachability()` / `stopReachability()` names для **backward compat** с existing App entry points (минимизация changes в BBTB_iOSApp / BBTB_macOSApp). Semantics shift: теперь они только устанавливают NEVPNStatusDidChange observer + macOS wake observer + initialize watchdog. NO NWPathMonitor, no ReconnectStateMachine.

<!-- TunnelWatchdog from Plan 06C-03: -->
```swift
public actor TunnelWatchdog {
    public init(failoverProvider: any FailoverProviding,
                stableSessionThreshold: TimeInterval = 30,
                disconnectDebounce: TimeInterval = 3,
                clock: ReconnectClock = SystemReconnectClock())
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async
    public func setUserIntent(_ intent: Bool) async
}
```

<!-- OnDemandMigrationTask from Plan 06C-03: -->
```swift
public enum OnDemandMigrationTask {
    public static func runIfNeeded(userDefaults: UserDefaults = .standard) async
}
```

<!-- App entry point wiring pattern (Phase 6 Wave 5 — BBTB_iOSApp.swift:66-88): -->
```swift
let relay = ReconnectStateObserverRelay()
let tunnel = TunnelController(stateObserver: relay.makeStateObserver())
// ... two-phase init for failoverProvider ...
let failoverProvider = SwiftDataFailoverProvider(...)
Task { await tunnel.setFailoverProvider(failoverProvider) }
Task { await tunnel.startReachability() }
```

Wave 3 cutover:
- Drop `relay` (ReconnectStateObserverRelay) — `stateObserver` parameter удаляется из init.
- `TunnelController(failoverProvider:NoFailoverProvider())` — init shape simpler.
- Late-binding setter `setFailoverProvider` сохраняется (cycle resolution).
- Add: `Task { await OnDemandMigrationTask.runIfNeeded() }` BEFORE `tunnel.startReachability()`.

<!-- ReconnectBannerState — needs new mapping per OQ-7. Existing variant (MainScreenViewModel.swift:17-23): -->
```swift
public enum ReconnectBannerState: Equatable, Sendable {
    case hidden
    case killSwitchReconfigure
    case retrying(attempt: Int, delaySeconds: Int)  // → НЕ используется в Phase 6c (no state machine)
    case failover(toServerName: String)              // → используется при watchdog firing
    case allFailed                                   // → DROP (Apple retries длиннее)
}
```

Phase 6c mapping:
- NEVPNStatus.connecting → banner.connecting (new variant)
- NEVPNStatus.reasserting → banner.connecting (Apple's on-demand reconnect in progress)
- NEVPNStatus.disconnected (during userIntent + after manual or unexpected drop) → banner.hidden (туннель действительно off)
- Watchdog firing nextServerAttempt с returned serverName → banner.failover(toServerName:)
- KillSwitch toggle change → banner.killSwitchReconfigure (preserved)

Решение по enum: **сократить enum** в Phase 6c:
```swift
public enum ReconnectBannerState: Equatable, Sendable {
    case hidden
    case killSwitchReconfigure
    case connecting           // нов — обобщает «Подключение/Переподключение»
    case failover(toServerName: String)  // preserved
}
```
- Удалены: `.retrying(attempt:delaySeconds:)`, `.allFailed`.
- Это **breaking** для ReconnectBanner.swift — нужно обновить switch cases в Banner View.

<!-- ReconnectBanner.swift current uses retrying + allFailed — найти switch case и refactor. -->

<!-- MainScreenViewModel banner state observer (current Phase 6) — uses ReconnectStateMachineState observer relay. -->
<!-- New approach: TunnelController exposes `@Published reconnectBannerState` ИЛИ MainScreenViewModel -->
<!-- subscribes к NEVPNStatusDidChange ИЛИ TunnelController has callback to VM. Simplest: VM subscribes -->
<!-- к NEVPNStatusDidChange (mainactor closure) и сама строит state из status + watchdog firing signal. -->

<!-- TunnelWatchdog firing signal: можно добавить optional callback `onFailoverFired: @Sendable (String) -> Void` в init, который VM передаёт → updates banner. Или просто читать `getStableSessionForTest`-style accessor. Лучше callback. -->

<!-- ReconnectStateObserverRelay (lines 111-131 TunnelController) — DELETED в Wave 3. -->

<!-- macOS wake observer (TunnelController:396-409): -->
<!-- PRESERVE pattern. Inside startReachability after Wave 3 cleanup: -->
```swift
#if os(macOS)
wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: nil
) { [weak self] _ in
    Task { [weak self] in await self?.handleWake() }
}
#endif

private func handleWake() async {
    let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
    // Idempotent — startVPNTunnel() no-op если уже up. D-12.
    try? managers.first?.connection.startVPNTunnel()
}
```
- Это ОДИН `loadAllFromPreferences` per wake event — rare event, XPC cost негативен. Простой и понятный.

<!-- D-15 explicit removals in TunnelController: -->
<!-- - handleStatusChange recovery path → теперь delegate в watchdog -->
<!-- - triggerRecoveryIfNeeded → DELETE -->
<!-- - lastKnownStatus cache → DELETE (watchdog читает passed status) -->
<!-- - manualDisconnectInProgress flag → DELETE (нет race с recovery path) -->
<!-- - connectInProgress flag → DELETE -->
<!-- - wakePending flag → DELETE (Apple's on-demand handles iOS wake; macOS direct nudge) -->
<!-- - scheduleClearManualDisconnect → DELETE -->
<!-- - ReconnectStateMachine reference → DELETE -->
<!-- - NetworkReachability reference → DELETE -->
<!-- - handleReachability → DELETE -->
<!-- - scheduleFailoverResetAfterStableSession → DELETE (watchdog has own scheduling) -->
<!-- - firstAttemptOverrideForTest seam → DELETE (no longer needed, watchdog tested separately) -->

<!-- D-15 preserved in TunnelController: -->
<!-- - connect/disconnect bodies — verbatim -->
<!-- - userIntendedConnected + UserIntentStore — passed to watchdog.setUserIntent() -->
<!-- - lastSuccessfulConnectAt — может быть удалён, если watchdog знает свой stableSession. Решение: DELETE — watchdog держит свой timer. -->
<!-- - NEVPNStatusDidChange observer setup — preserved, но delegates в watchdog + banner signal -->
<!-- - macOS wake observer — preserved -->
<!-- - failoverProvider + setFailoverProvider — preserved -->

<!-- TunnelControllerTests.swift (new, replaces TunnelControllerStateTests.swift): -->
<!-- D-24 category 2 — connect/disconnect contract preservation. -->
<!-- Tests should verify behavioral invariants без real entitlements: -->
<!-- - connect() throws «No VPN profile» когда manager не существует (test env returns empty array). -->
<!-- - disconnect() no-throw когда manager не существует. -->
<!-- - userIntendedConnected flag mirroring через actor isolation. -->
<!-- - setUserIntent → watchdog получает значение. -->
</interfaces>

<uat_checklist>
**Critical: UAT-Task E (Pitfall 5 race) must explicitly pass.**

UAT прогоняется на:
- iPhone 11+ с iOS 26.5 (per CORE-04 / DIST-01)
- MacBook Apple Silicon (per DIST-02)

Сценарии:

| # | Сценарий | Ожидание | Plat | Round 2 Severity |
|---|----------|----------|------|------------------|
| A | Wi-Fi off → LTE → reconnect | Туннель сам поднимается в течение ~5s; нет двойных reconnect; logs показывают on-demand путь, watchdog НЕ срабатывает (т.к. это не «сервер мёртв», это «сменил сеть») | iOS | **HARD BLOCKER** |
| B | iPhone overnight (sleep+wake) | Утром туннель уже up без открытия app; ip-check показывает VPN IP | iOS | Non-blocking |
| C | MacBook sleep 10 min → wake | В течение 15s туннель up; logs показывают (a) on-demand сработал ИЛИ (b) NSWorkspace.didWake observer вызвал startVPNTunnel — допустимы оба пути | macOS | **HARD BLOCKER** |
| D | Сменить Wi-Fi сеть (другая SSID) | Reconnect автоматический; нет крашей; нет фантомных reconnect | iOS | Non-blocking |
| E | **Stable session 1min, kill server-side sing-box (или firewall block)** | Watchdog срабатывает после 3s debounce, swap к next серверу; Apple's on-demand не приводит к stuck-on-connecting; UI banner показывает «Переключение на сервер X» | iOS | **HARD BLOCKER (CRITICAL — Pitfall 5)** |
| F | Активировать другой VPN (ProtonVPN), потом вернуться в BBTB | BBTB Connect одним тапом работает; нет «fight-back»; нет автоматического reconnect ДО пользовательского тапа | iOS | **HARD BLOCKER (Round 2 B-10 — was non-critical)** |
| G | App in background 30+ min, проверить crash logs | НИ ОДНОГО EXC_RESOURCE / PORT_SPACE | iOS 26.5 | **HARD BLOCKER (CRITICAL — bug class 4)** |
| H | Toggle «Авто-переподключение» OFF while connected | Туннель остаётся up; банер не показывает | iOS | Non-blocking |
| I | Migration smoke (если есть существующий профиль из Phase 6): первый запуск Phase 6c build | Manager.isOnDemandEnabled = true (проверить через Settings → VPN → BBTB → On Demand Activation toggle); auto-reconnect работает уже сразу без re-import | iOS | **HARD BLOCKER (Round 2 B-10 — D-17b/c safety net)** |

UAT PASS-критерий (Round 2 B-10): **Hard blockers (must PASS): A, C, E, F, G, I.** Non-blocking (may proceed with notes): B, D, H. Decision matrix:
- All 6 hard blockers PASS + 0–3 non-blocking failures: proceed cleanup; record non-blocking failures.
- Any hard blocker FAIL: STOP, do not proceed to Task 3, escalate to user.

Rationale: F (other-VPN fight-back) и I (upgrade migration) — Round 2 elevated to hard blocker per B-10. F — one of 4 bug classes мы explicitly eliminate; I — D-17b/c safety net, без него existing-install users остаются с broken state.
</uat_checklist>
</context>

<tasks>

<task type="auto">
  <name>Task 1: Wire OnDemandMigrationTask в BBTB_iOSApp + BBTB_macOSApp + Replace ReconnectStateMachine wiring в TunnelController на TunnelWatchdog (additive, no deletions yet)</name>
  <files>BBTB/App/iOSApp/BBTB_iOSApp.swift, BBTB/App/macOSApp/BBTB_macOSApp.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift</files>
  <read_first>
    - BBTB/App/iOSApp/BBTB_iOSApp.swift полностью
    - BBTB/App/macOSApp/BBTB_macOSApp.swift полностью
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift полностью (заметить какие методы preserved vs to-be-deleted)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift строки 1-150 (banner state wiring)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift полностью (switch cases на enum)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift (Plan 06C-03)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandMigrationTask.swift (Plan 06C-03)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Pattern 4: macOS wake observer backup (D-11)» и Pitfall 6
  </read_first>
  <action>
    Wiring task — additive. Старая machinery всё ещё работает; новая wired в дополнение. После этой task UAT должен показать что новый путь корректен.

    **Round 2 changes vs Round 1 action:**
    - Step 2 теперь добавляет `cachedManager` property + bbtbProvisionerDidSave observer + uses real `manager.isEnabled` (B-03 fix — replaces broken `lastKnownStatus != .invalid` proxy).
    - Step 2.5 (NEW): после setUserIntent в connect()/disconnect() — call `OnDemandRulesBuilder.applyCurrentState(to: cachedManager) + save + reload` (B-04 wiring complement — Connect immediately flips manager.isOnDemandEnabled).
    - Step 4 (macOS wake nudge) теперь добавляет 3 guards (W-06).
    - Step 5: banner mapping additive — Task 3b будет finalize rewire.

    **Step 1 — App entry points:**

    В `BBTB/App/iOSApp/BBTB_iOSApp.swift` и `BBTB/App/macOSApp/BBTB_macOSApp.swift`:
    - НАЙТИ block где конструируется TunnelController (около line 62-88 в iOS, line 51-74 в macOS).
    - ПЕРЕД конструированием TunnelController, добавить `Task { await OnDemandMigrationTask.runIfNeeded() }`.
    - Это async fire-and-forget — running concurrently с rest of setup. Идемпотентный, безопасно если другая часть приложения тоже могла бы это вызвать.
    - Doc-comment inline: `// Phase 6c / Plan 06C-04 / D-17b/c — one-shot migration of existing manager to on-demand.`

    **Step 2 — TunnelController watchdog wiring + cachedManager (Round 2 B-03 fix):**

    Внутри `TunnelController` (НЕ удаляя ничего из существующего):

    - Добавить stored property `private var watchdog: TunnelWatchdog?` (optional — wired через late-binding setter mirror of failoverProvider).
    - Добавить `public func setWatchdog(_ watchdog: TunnelWatchdog) { self.watchdog = watchdog }`.
    - **Round 2 B-03: добавить stored property** `private var cachedManager: NETunnelProviderManager?` (optional — populated на startReachability + refreshed через notification observer).
    - **Round 2 B-03: добавить private helper** `private func refreshCachedManager() async`:
      ```swift
      private func refreshCachedManager() async {
          do {
              let managers = try await NETunnelProviderManager.loadAllFromPreferences()
              cachedManager = ManagerSelector.ourManagers(from: managers).first
              log.debug("TunnelController cachedManager refreshed (nil=\(self.cachedManager == nil, privacy: .public))")
          } catch {
              log.warning("TunnelController.refreshCachedManager failed: \(String(describing: error), privacy: .public)")
              // cachedManager stays at previous value — graceful degradation; на следующий refresh трюк попробует снова.
          }
      }
      ```
    - **Round 2 B-03: в `startReachability()`**, ПОСЛЕ существующего setup кода (NEVPN observer, macOS wake observer), добавить:
      ```swift
      // Round 2 B-03 — initial cachedManager population.
      await refreshCachedManager()

      // Round 2 B-03 — observe `bbtbProvisionerDidSave` для refresh после ConfigImporter / SettingsViewModel / OnDemandMigrationTask save.
      provisionerObserver = NotificationCenter.default.addObserver(
          forName: .bbtbProvisionerDidSave,
          object: nil,
          queue: nil
      ) { [weak self] _ in
          Task { [weak self] in await self?.refreshCachedManager() }
      }
      ```
      Plus add `private var provisionerObserver: NSObjectProtocol?` stored property and unregister в `stopReachability`.

    - В `connect()`: после `setUserIntendedConnected(true)`, добавить:
      ```swift
      await watchdog?.setUserIntent(true)
      // Round 2 B-04 wiring complement — immediately flip manager.isOnDemandEnabled на основе nового intent.
      // Без этого изменение intent применилось бы ТОЛЬКО на следующий provisioner save, что слишком поздно.
      await applyCurrentStateToCachedManager()
      ```
    - В `disconnect()`: после `setUserIntendedConnected(false)`, добавить:
      ```swift
      await watchdog?.setUserIntent(false)
      // Round 2 B-04 wiring complement — flip manager.isOnDemandEnabled = false → tunnel не auto-resurrect.
      await applyCurrentStateToCachedManager()
      ```
    - **Round 2 B-04 + Round 3 N-01: добавить private helper** `private func applyCurrentStateToCachedManager() async`:
      ```swift
      private func applyCurrentStateToCachedManager() async {
          // Round 3 N-01 fix — load-on-demand if cache miss.
          // Сценарий: пользователь только что импортировал config и тапнул Connect, а observer
          // `.bbtbProvisionerDidSave` ещё не успел нас refresh'нуть (или это вообще первый запуск
          // ДО startReachability refresh). Без этого fallback'а Connect tap не flip'нул бы
          // `manager.isOnDemandEnabled = true` до СЛЕДУЮЩЕГО provisioner save — а до тех пор
          // auto-reconnect был бы выключен (UX regression, обратная сторона B-04 fix).
          if cachedManager == nil {
              await refreshCachedManager()
          }
          guard let manager = cachedManager else {
              // Даже после refresh manager не найден — пользователь ещё не импортировал config.
              // UI должен блокировать Connect tap в этом state; defensive log на случай если нет.
              log.warning("applyCurrentStateToCachedManager — no manager available even after refresh; skipping.")
              return
          }
          OnDemandRulesBuilder.applyCurrentState(to: manager)
          do {
              try await manager.saveToPreferences()
              try await manager.loadFromPreferences()  // RESEARCH §9.1
              // Не постим .bbtbProvisionerDidSave — мы САМИ source of this update; не нужно рефрешить
              // собственный cachedManager (это создаст petty cycle).
          } catch {
              // Round 3 MINOR-01 (Gemini R3) — graceful degradation rationale:
              // User intent (`autoReconnectEnabled` toggle state) уже persisted в UserDefaults через
              // @AppStorage ПЕРЕД вызовом этого helper'а. Если save транзитно упал (XPC glitch,
              // pre-warm race, etc.) — следующий provisioner event (re-import, app relaunch, или
              // любая другая operation, вызывающая ConfigImporter.provisionTunnelProfile) сам
              // re-apply'нет current state через OnDemandRulesBuilder.applyCurrentState с тем же
              // toggle && intent gate. Поэтому log-and-continue, никогда throw/escalate —
              // нет user-visible regression от пропуска одного flip'а.
              log.warning("applyCurrentStateToCachedManager save failed: \(String(describing: error), privacy: .public)")
          }
      }
      ```

    - В `handleStatusChange(_:)`: AFTER existing branches (или вместо обработки в Task 3a slim), добавить **(Round 2 B-03 fix — replaces broken proxy)**:
      ```swift
      // Round 2 B-03 — REAL manager.isEnabled gate (replaces broken `lastKnownStatus != .invalid` proxy).
      // cachedManager.isEnabled false происходит когда: (a) другой VPN активирован (профиль disabled);
      // (b) пользователь отключил профиль в Settings → VPN.
      // В обоих случаях watchdog НЕ должен fire failover (D-08 + bug class 3 mitigation).
      // Если cachedManager == nil (startup race до первого refresh) — conservative default false → skip.
      let managerEnabled = cachedManager?.isEnabled ?? false
      await watchdog?.handleStatusChange(status, managerEnabled: managerEnabled)
      ```

    **Step 3 — App entry point: construct TunnelWatchdog and wire to TunnelController (after failoverProvider):**

    В обоих App entry points, после `Task { await tunnel.setFailoverProvider(failoverProvider) }`:
    ```swift
    // Phase 6c / Plan 06C-04 — TunnelWatchdog for mid-session server failover (D-08, D-09).
    Task {
        let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
        await tunnel.setWatchdog(watchdog)
    }
    ```

    **Step 4 — macOS wake observer (Round 2 W-06 — 3 guards):**

    В обновлении `handleWake()` (macOS only) внутри TunnelController. Round 1 был unconditional `try? managers.first?.connection.startVPNTunnel()`. Round 2:
    ```swift
    #if os(macOS)
    private func handleWake() async {
        let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
        // Round 2 B-06 — фильтруем наши.
        guard let manager = ManagerSelector.ourManagers(from: managers).first else { return }
        // Round 2 W-06 — 3 guards:
        // 1. Профиль не disabled другим VPN-приложением (bug class 3 mitigation).
        guard manager.isEnabled else {
            log.notice("handleWake: manager.isEnabled == false (другой VPN активен?) → skip nudge.")
            return
        }
        // 2. On-demand включен на manager'е (пользовательский выбор уважён).
        guard manager.isOnDemandEnabled else {
            log.notice("handleWake: manager.isOnDemandEnabled == false (manual mode) → skip nudge.")
            return
        }
        // 3. Toggle включен в Settings.
        guard OnDemandRulesBuilder.loadAutoReconnectEnabled() else {
            log.notice("handleWake: autoReconnectEnabled toggle off → skip nudge.")
            return
        }
        try? manager.connection.startVPNTunnel()  // idempotent nudge
    }
    #endif
    ```

    **Step 5 — Banner state mapping (additive — старый relay path всё ещё работает; Task 3b finalize):**

    В `ReconnectBanner.swift`: добавить новый case `.connecting` в enum рендеринг (рядом с existing `.retrying`):
    ```swift
    case .connecting: Text(L10n.bannerConnecting)
    ```
    Использовать существующую локализацию `bannerReconnecting` или добавить новый key `bannerConnecting` (ru="Подключение", en="Connecting") если необходимо.

    В `MainScreenViewModel.swift`: добавить wire-up второго source для banner state. Сейчас banner state идёт через `ReconnectStateObserverRelay`. Добавить дополнительный observer на NEVPNStatusDidChange который ТАКЖЕ обновляет `reconnectBannerState` для simple .connecting/.connected/.disconnected mapping. Old observer (через relay) ОСТАЁТСЯ — Task 3b (cleanup) удалит его. Это parallel-run шаг (priority of last writer wins — может flicker, тоже OK temporary).

    **Step 6 — Build + verify:**

    `swift build --package-path BBTB/Packages/AppFeatures` succeed.
    `swift test --package-path BBTB/Packages/AppFeatures` full suite green — НИКАКИХ regressions. Старые tests (ReconnectStateMachineTests, NetworkReachabilityTests, TunnelControllerStateTests) ВСЕ ЕЩЁ pass.

    КРИТИЧЕСКИ:
    - Никаких deletes в Task 1. Pure additive (Round 2: одно исключение — replaced broken `lastKnownStatus != .invalid` proxy с real `cachedManager?.isEnabled ?? false`; old proxy line REPLACED, not deleted in slim-down sense).
    - Existing failoverProvider.connect closure НЕ модифицируется (D-16 + OQ-6).
    - macOS wake observer body ОБНОВЛЁН с 3 guards (W-06) — не deleted.
    - Connect/disconnect bodies НЕ изменяются — только дополнительные строки после setUserIntendedConnected (watchdog.setUserIntent + applyCurrentStateToCachedManager).
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures && swift test --package-path Packages/AppFeatures</automated>
  </verify>
  <acceptance_criteria>
    - `grep -c "OnDemandMigrationTask.runIfNeeded" BBTB/App/iOSApp/BBTB_iOSApp.swift` returns ≥ 1.
    - `grep -c "OnDemandMigrationTask.runIfNeeded" BBTB/App/macOSApp/BBTB_macOSApp.swift` returns ≥ 1.
    - `grep -c "TunnelWatchdog(failoverProvider:" BBTB/App/iOSApp/BBTB_iOSApp.swift BBTB/App/macOSApp/BBTB_macOSApp.swift` returns ≥ 2 (one each platform).
    - `grep -c "setWatchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 2 (declaration + invocation in App).
    - `grep -c "watchdog?.handleStatusChange\\|watchdog?.setUserIntent" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3 (handleStatusChange + connect + disconnect).
    - `grep -c "ReconnectStateMachine\\|NetworkReachability" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 4 (preserved — старая machinery всё ещё ссылается).
    - **Round 2 B-03:** `grep -c "cachedManager" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3 (property + refresh helper + handleStatusChange consumer).
    - **Round 2 B-03:** `grep -c "bbtbProvisionerDidSave" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 1 (NotificationCenter observer).
    - **Round 2 B-03:** `grep -c "lastKnownStatus != .invalid" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (broken proxy REPLACED).
    - **Round 2 B-04 wiring:** `grep -c "applyCurrentStateToCachedManager\\|OnDemandRulesBuilder.applyCurrentState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3 (helper definition + connect callsite + disconnect callsite).
    - **Round 3 N-01 fix (load-on-demand on cache miss):** body of `applyCurrentStateToCachedManager` must call `refreshCachedManager()` when `cachedManager == nil` BEFORE the guard, so the first Connect tap correctly flips `isOnDemandEnabled` even when the cache hasn't been populated yet. Acceptance: `awk '/private func applyCurrentStateToCachedManager/,/^[[:space:]]*}[[:space:]]*$/' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -c "await refreshCachedManager"` returns ≥ 1.
    - **Round 3 N-01 defensive log:** the post-refresh guard branch must log a `warning` (not silently skip), so any genuine "no manager even after refresh" state is observable. Acceptance: `awk '/private func applyCurrentStateToCachedManager/,/^[[:space:]]*}[[:space:]]*$/' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -c "log.warning.*no manager available even after refresh"` returns ≥ 1.
    - **Round 2 B-06:** `grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 2 (refreshCachedManager + handleWake).
    - **Round 2 W-06:** Внутри macOS `handleWake()`, between `private func handleWake()` and the `try? manager.connection.startVPNTunnel()` line, есть ≥ 3 `guard` statements проверяющие `manager.isEnabled`, `manager.isOnDemandEnabled`, `OnDemandRulesBuilder.loadAutoReconnectEnabled()`. Acceptance: `grep -A 20 "private func handleWake" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -cE "guard.*isEnabled|guard.*isOnDemandEnabled|guard.*loadAutoReconnectEnabled"` returns ≥ 3.
    - Полная AppFeatures test-сюита green.
    - Build iOS + macOS schemes succeeds (если планер запускает `xcodebuild`; иначе оставить как UAT prep).
  </acceptance_criteria>
  <done>Migration task wired в App init для обеих платформ. TunnelWatchdog wired в TunnelController через late-binding setter и получает события из существующего NEVPNStatusDidChange observer. Все pre-existing tests pass. Старая machinery всё ещё работает — parallel run между builder, watchdog, и existing recovery path. Ready for device UAT.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 2 (Checkpoint): Device UAT — 9 scenarios on iPhone iOS 26.5 + macOS</name>
  <what-built>
    Wave 0-1-2 + Task 1 of Wave 3 are now live (Round 2 reflections):
    - OnDemandRulesBuilder produces `[NEOnDemandRuleConnect(.any)]` + isOnDemandEnabled через **applyCurrentState** (gates toggle && intent — B-04).
    - DefaultTunnelProvisioner.provisionTunnelProfile вызывает applyCurrentState на каждый import + posts `.bbtbProvisionerDidSave`.
    - SettingsView показывает раздел «Подключение» с toggle (default ON); helper nonisolated (W-03).
    - OnDemandMigrationTask запускается на app init — мигрирует existing manager к on-demand с B-05 transient-failure safety + B-06 multi-manager + applyCurrentState consumer.
    - TunnelWatchdog wired в TunnelController через `cachedManager.isEnabled` real gate (B-03 — broken proxy GONE), fires failover при stable-session disconnects (3s debounce с .reasserting cancellation — W-05).
    - TunnelController.connect/disconnect дополнительно вызывают `applyCurrentStateToCachedManager` после setUserIntent — immediate manager.isOnDemandEnabled flip (B-04 wiring).
    - macOS NSWorkspace.didWakeNotification observer с **3 guards** (manager.isEnabled + isOnDemandEnabled + loadAutoReconnectEnabled — W-06).
    - Старая custom-reconnect machinery (ReconnectStateMachine class + handleReachability + NetworkReachability, NEVPNStatusDidChange recovery branches) ВСЕ ЕЩЁ работает параллельно — это последний шанс fix-forward без losing rollback path. (`ReconnectClock.swift` уже extracted в Plan 03 Task 2.5 — survives upcoming cleanup.)
  </what-built>
  <how-to-verify>
    На iPhone 11+ iOS 26.5:
    1. Install fresh build (либо upgrade с Phase 6 build если есть TestFlight binary).
    2. Если upgrade: первый запуск — приложение запускается без import; через ~1s видим в logs `ondemand-migration: migration applied` (или `no manager`).
    3. **Сценарий A** — Wi-Fi на устройстве OFF / Cellular ON → реконнект автоматический в течение ~5s. Открыть Settings → VPN → BBTB должен быть connected, IP проверка через ipinfo.io показывает server IP. **PASS критерий**: реконнект < 10s.
    4. **Сценарий B** — оставить iPhone на ночь со связью + lock screen. Утром: открыть app → connected; ipinfo показывает server IP. **PASS**: tunnel up без открытия app.
    5. **Сценарий D** — на ходу сменить Wi-Fi сеть (например, поход в кафе). Tunnel reconnects in ≤ 10s, no crash. **PASS**: reconnect smooth.
    6. **Сценарий E (CRITICAL — Pitfall 5)** — connect, ждать 1 min stable. Затем удалённо kill the sing-box процесс на VPS (`pkill -f sing-box`) или иной server-side block. Ожидание: после 3s debounce watchdog fires failover к next server из round-robin. Banner показывает «Переключение на сервер X». Apple's on-demand на старый dead server не блокирует. **PASS**: failover < 10s, no stuck connecting.
    7. **Сценарий F** — открыть другое VPN-приложение (ProtonVPN или Mullvad), connect там. Вернуться в BBTB → нажать Connect. Tunnel up за один тап. **PASS**: один тап.
    8. **Сценарий G (CRITICAL — bug class 4)** — оставить app в background 30+ min с active tunnel. Открыть Console.app / Mac Console для iPhone → искать crash logs от BBTB. **PASS**: zero EXC_RESOURCE / PORT_SPACE crash logs.
    9. **Сценарий H** — в Settings отключить «Авто-переподключение». Туннель должен **остаться up** (Pitfall 4). Сменить сеть → tunnel падает, баннер не show «reconnecting». **PASS**: toggle off = ручной режим, без tear-down активного туннеля.
    10. **Сценарий I** — если это upgrade: проверить `iOS Settings → VPN → BBTB → On Demand Activation` toggle — должен быть ON.

    На macOS:
    11. **Сценарий C** — Apple → Sleep → подождать 10 min → wake. В течение 15s tunnel up. **PASS**.

    Запись результатов (Round 2 B-10):

    **Hard blockers — MUST PASS: A, C, E, F, G, I.** Non-blocking: B, D, H.

    Decision matrix:
    - **All 6 hard blockers (A/C/E/F/G/I) PASS + 0–3 non-blocking failures** → proceed Task 3 cleanup; record non-blocking failures в SUMMARY.
    - **Any hard blocker FAIL** → STOP. Do NOT proceed to Task 3a/3b/3c. Escalate to user; fix-forward in Task 1 if patch is small, иначе rollback к Plan 06C-03 state.
    - **All 9 PASS** → ideal; proceed cleanup with confidence.

    Rationale per B-10: F (other-VPN fight-back) — one of 4 bug classes мы explicitly eliminate. I (upgrade migration) — D-17b/c safety net; без него existing-install users остаются с broken state. Both Round 2 elevated.
  </how-to-verify>
  <resume-signal>
    Type one of (Round 2 B-10 grammar):
    - `uat passed: hard A,C,E,F,G,I all pass; non-blocking [list any failures]` — all 6 hard blockers passed; proceed to Task 3a/3b/3c cleanup.
    - `uat partial: hard pass, non-blocking [B|D|H] fail [details]` — only non-blocking failures; proceed cleanup; note failures for SUMMARY.
    - `uat failed: hard blocker [A|C|E|F|G|I] fail [details]` — at least one hard blocker failed; STOP cleanup, escalate.
    - `skip uat` — defer UAT (Task 3a/3b/3c blocked; leaves Phase 6c in parallel-run state until UAT done).
  </resume-signal>
  <files>n/a — checkpoint task; no files modified by executor (results recorded in 06C-UAT.md by Plan 06C-05)</files>
  <action>Pause execution and wait for human-verified UAT result (see what-built + how-to-verify above). Do not proceed to Task 3 until resume-signal received.</action>
  <verify>Human reviewer types one of the resume-signal phrases.</verify>
  <done>UAT result recorded; executor receives explicit go/no-go signal for Task 3.</done>
</task>

<task type="auto">
  <name>Task 3a (Round 2 W-01 split): TunnelController slim-down — delete props/methods + use cachedManager.isEnabled gate (B-03 final state)</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift</files>
  <read_first>
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-10, D-14, D-15 (cleanup boundaries)
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции W-01 + B-03 + W-06 + B-06
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (полностью после Task 1 changes)
  </read_first>
  <action>
    **CRITICAL: This task runs ONLY if Task 2 UAT resumed with `uat passed` (all 6 hard blockers PASS).** Do NOT proceed if any of A/C/E/F/G/I had a FAIL.

    **Step 1 — DELETE stored properties from TunnelController.swift:**

    Открыть `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (618 lines after Task 1) и DELETE:

    Stored properties:
    - `reachability: NetworkReachability` (deletion)
    - `stateMachine: ReconnectStateMachine` (deletion)
    - `reconnectClock: ReconnectClock` (deletion — moved into watchdog; TunnelController itself doesn't need a clock)
    - `manualDisconnectInProgress: Bool` (deletion — no recovery path race anymore)
    - `lastKnownStatus: NEVPNStatus` (deletion — watchdog reads passed status from observer; cachedManager gives true `isEnabled` per B-03)
    - `connectInProgress: Bool` (deletion — no recovery path = no reentrance race)
    - `lastSuccessfulConnectAt: Date?` (deletion — watchdog tracks own session)
    - `wakePending: Bool` (deletion — iOS handled by Apple; macOS direct nudge)

    **PRESERVE** (Round 2 B-03 / B-04):
    - `cachedManager: NETunnelProviderManager?` (новое — добавлено в Task 1)
    - `provisionerObserver: NSObjectProtocol?` (новое — добавлено в Task 1)
    - `watchdog: TunnelWatchdog?` (новое — добавлено в Task 1)
    - `intentStore: UserIntentStore` (preserved per OQ-2)
    - `statusProvider` (preserved)
    - `failoverProvider` + `setFailoverProvider` (preserved per D-16)

    **Step 2 — DELETE methods:**

    - `handleReachability(_:)` (deletion)
    - `triggerRecoveryIfNeeded(reason:)` (deletion)
    - `scheduleFailoverResetAfterStableSession(startedAt:)` (deletion — watchdog has own)
    - `scheduleClearManualDisconnect()` + `clearManualDisconnect()` (deletion)
    - `firstAttemptOverrideForTest` + `setFirstAttemptOverrideForTest(_:)` (deletion)
    - `isManualDisconnectInProgress` / `_setManualDisconnectForTest` (deletion)
    - `getLastSuccessfulConnectAt` (deletion)
    - `_setConnectInProgressForTest` / `getConnectInProgressForTest` (deletion)

    From `init`:
    - Remove `reachability:` and `stateMachine:` parameters and assignments.
    - Remove `reconnectClock:` parameter.
    - Remove `stateObserver:` parameter (ReconnectStateObserverRelay deleted в Task 3c).
    - **Keep**: statusProvider, failoverProvider, intentStore (preserved per OQ-2).

    `ReconnectStateObserverRelay` class: DELETE (lines 111-131 of original) — но если она используется только внутри TunnelController.swift, deletion здесь. Если она в отдельном файле — это Task 3c.

    **Step 3 — Simplify handleStatusChange (Round 2 B-03 final):**

    `handleStatusChange(_:)` body simplified:
    ```swift
    internal func handleStatusChange(_ status: NEVPNStatus) async {
        // Round 2 B-03 — real manager.isEnabled gate (replaces broken `lastKnownStatus != .invalid` proxy).
        let managerEnabled = cachedManager?.isEnabled ?? false
        await watchdog?.handleStatusChange(status, managerEnabled: managerEnabled)
        // Banner state mapping moved to MainScreenViewModel в Task 3b — здесь только watchdog delegation.
    }
    ```

    **Step 4 — Simplify startReachability:**

    `startReachability()` body после cleanup:
    ```swift
    public func startReachability() async {
        guard !reachabilityStarted else { return }
        reachabilityStarted = true

        // NEVPNStatusDidChange observer — D-17 narrow: только delegates в watchdog (status passed sync from notification.object — XPC-free).
        nevpnObserver = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let conn = notification.object as? NEVPNConnection else { return }
            let status = conn.status
            Task { [weak self] in
                await self?.handleStatusChange(status)
            }
        }

        // Round 2 B-03 — initial cachedManager population.
        await refreshCachedManager()

        // Round 2 B-03 — observe `.bbtbProvisionerDidSave` for refresh after ConfigImporter / SettingsViewModel / OnDemandMigrationTask save.
        provisionerObserver = NotificationCenter.default.addObserver(
            forName: .bbtbProvisionerDidSave,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in await self?.refreshCachedManager() }
        }

        #if os(macOS)
        // D-11/12/13 + Round 2 W-06 — wake observer с 3 guards в handleWake.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { [weak self] in await self?.handleWake() }
        }
        #endif

        log.notice("TunnelController.startReachability — observers active")
    }
    ```

    **Step 5 — stopReachability cleanup:**

    Update `stopReachability()` to unregister `provisionerObserver` AND `nevpnObserver` (existing). NetworkReachability stop call REMOVED.

    **Step 6 — handleWake (Round 2 W-06 finalized form):**

    Body как в Task 1 Step 4 — 3 guards. **Round 2 B-06:** uses `ManagerSelector.ourManagers(from:).first`.

    После slim-down: TunnelController.swift должен быть ≤ 350 строк (target ~300 per D-15).

    **Step 7 — Build + smoke:**

    `swift build --package-path BBTB/Packages/AppFeatures` — должен компилироваться. ReconnectStateMachine class всё ещё existed в `ReconnectStateMachine.swift` (Plan 03 Task 2.5 убрал только extracted types — class сам ещё ест). NetworkReachability.swift файл всё ещё existed. NO test deletions yet — Task 3c сделает.

    `swift test --package-path BBTB/Packages/AppFeatures` — full suite green. Старые tests (RSM, NetReach, TCS) BUDET pass because их targets ещё существуют. Только TunnelController-direct tests могут fail (deleted methods invocations) — это OK, Task 3c заменит test file.

    Если ReconnectStateMachine class имеет deps на NetworkReachability в свой body — оставить как есть; Task 3c удалит оба класса разом.
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures && wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | awk '{ if ($1 > 350) exit 1; else print "OK: " $1 " lines" }'</automated>
  </verify>
  <acceptance_criteria>
    - `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≤ 350.
    - `grep -c "cachedManager?.isEnabled" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 1 (Round 2 B-03 final).
    - `grep -c "lastKnownStatus" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0 (deleted).
    - `grep -c "manualDisconnectInProgress\\|connectInProgress\\|wakePending" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0.
    - `grep -c "triggerRecoveryIfNeeded\\|handleReachability\\|scheduleFailoverResetAfterStableSession" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0.
    - `grep -c "NSWorkspace.didWakeNotification" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 1 (D-11 preserved).
    - `grep -c "TunnelWatchdog\\|watchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3.
    - `cd BBTB && swift build --package-path Packages/AppFeatures` succeeds. (Tests may fail because of deleted TunnelControllerStateTests methods — это OK, Task 3c заменит.)
  </acceptance_criteria>
  <done>TunnelController.swift slim ≤ 350 lines; cachedManager-based isEnabled gate operational (Round 2 B-03 final); recovery path & old flags removed. Build green. Tests deletion + replacement still pending in Task 3c.</done>
</task>

<task type="auto">
  <name>Task 3b (Round 2 W-01 split): MainScreenViewModel banner state rewire + ReconnectBanner enum trim with W-02 audit + TunnelWatchdog.setFailoverObserver</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift</files>
  <read_first>
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift строки 1-150 (banner state wiring)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift полностью (switch cases на enum)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift (Plan 03 Task 3 — добавим setFailoverObserver setter)
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции W-01 + W-02
  </read_first>
  <action>
    **Step 1 — W-02 audit (BEFORE any enum mutation):**

    Запустить:
    ```bash
    grep -rn 'case \.retrying\|case \.allFailed\|\.retrying(\|\.allFailed' BBTB/Packages/AppFeatures
    ```

    Каждый match зафиксировать в комментарии (или временной заметке в SUMMARY draft). Это identifies ВСЕ consumer sites которые сломаются если enum trimmed BEFORE this step.

    **Step 2 — Mutate ReconnectBanner enum:**

    Update `ReconnectBannerState` enum:
    ```swift
    public enum ReconnectBannerState: Equatable, Sendable {
        case hidden
        case killSwitchReconfigure
        case connecting           // нов — обобщает «Подключение/Переподключение»
        case failover(toServerName: String)  // preserved
    }
    ```
    Удалены: `.retrying(attempt: Int, delaySeconds: Int)`, `.allFailed`.

    **Step 3 — Update every consumer site found in Step 1:**

    Для каждого match, заменить:
    - `.retrying(attempt:delaySeconds:)` → `.connecting` (если context — "Apple's on-demand reconnecting") ИЛИ удалить ветку (если context — old custom retry logic).
    - `.allFailed` → удалить ветку (или заменить на `.hidden` если UI wants graceful degradation).

    Особенно проверить:
    - `ReconnectBanner.swift` rendering — switch case на enum.
    - `MainScreenViewModel.swift` state-set callsites.
    - Любые тесты в test targets (могут понадобиться post-deletion в Task 3c — fix forward).

    **Step 4 — Add `setFailoverObserver` to TunnelWatchdog (Plan 03 Task 3 deferred):**

    Modify `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift`:
    ```swift
    public actor TunnelWatchdog {
        // ... existing fields ...

        private var failoverObserver: (@Sendable (String) async -> Void)?

        public func setFailoverObserver(_ observer: @escaping @Sendable (String) async -> Void) {
            self.failoverObserver = observer
        }

        // В fireFailover() после successful nextServerAttempt + attempt execution:
        // await self.failoverObserver?(serverName)
        // (внутри existing fireFailover helper — добавить call после await attempt())
    }
    ```

    **Step 5 — MainScreenViewModel rewire:**

    В `MainScreenViewModel.swift`:
    - Remove ReconnectStateMachineState consumer (он будет удалён в Task 3c). Заменить на NEVPNStatus observer + watchdog callback.
    - В init (или setup helper):
      ```swift
      NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { [weak self] notification in
          guard let conn = notification.object as? NEVPNConnection else { return }
          let status = conn.status
          Task { @MainActor [weak self] in
              guard let self else { return }
              switch status {
              case .connecting, .reasserting:
                  self.reconnectBannerState = .connecting
              case .connected, .disconnected, .disconnecting, .invalid:
                  self.reconnectBannerState = .hidden
              @unknown default:
                  self.reconnectBannerState = .hidden
              }
          }
      }
      ```
    - When watchdog is wired (via app init), VM injects callback:
      ```swift
      Task {
          await watchdog.setFailoverObserver { [weak self] serverName in
              await MainActor.run { [weak self] in
                  self?.reconnectBannerState = .failover(toServerName: serverName)
              }
          }
      }
      ```

    **Step 6 — Build + smoke:**

    `swift build --package-path BBTB/Packages/AppFeatures` succeeds.

    Note: Old ReconnectStateObserverRelay code in TunnelController + App entry points всё ещё existed (Task 3c removes). Old observer path может ещё пытаться writes в reconnectBannerState — flicker допустим в parallel-run window. Task 3c finalizes.
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures</automated>
  </verify>
  <acceptance_criteria>
    - **`grep -rc 'case \.retrying\|case \.allFailed' BBTB/Packages/AppFeatures/Sources` returns 0** (W-02: enum cases removed, all consumers updated).
    - **`grep -rc '\.retrying(\|\.allFailed' BBTB/Packages/AppFeatures/Sources` returns 0** (W-02: callsites updated; pre-mutation grep result documented в SUMMARY).
    - `grep -c "case connecting" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` returns ≥ 1 (new case added).
    - `grep -c "case failover" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift` returns ≥ 1 (preserved).
    - `grep -c "setFailoverObserver" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift` returns ≥ 1 (new setter).
    - `grep -c "setFailoverObserver" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift BBTB/App/iOSApp/BBTB_iOSApp.swift BBTB/App/macOSApp/BBTB_macOSApp.swift` returns ≥ 1 (consumer side wired — exact location at planner discretion).
    - `swift build --package-path BBTB/Packages/AppFeatures` succeeds.
  </acceptance_criteria>
  <done>Banner enum trimmed + audit complete (W-02); MainScreenViewModel rewired для NEVPNStatus + watchdog signals; TunnelWatchdog.setFailoverObserver setter ready for VM injection. Build green; ready for Task 3c deletes.</done>
</task>

<task type="auto">
  <name>Task 3c (Round 2 W-01 split): DELETE 5 files (preserve ReconnectClock.swift + TestClocks.swift per B-01/B-02) + CREATE TunnelControllerTests.swift + update App entry points + xcodebuild green</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift, BBTB/App/iOSApp/BBTB_iOSApp.swift, BBTB/App/macOSApp/BBTB_macOSApp.swift</files>
  <read_first>
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-10, D-14, D-15, D-17 (cleanup boundaries)
    - .planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md секции B-01 + B-02 + B-08 + W-01
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (после Task 3a slim — final review)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift (Plan 03 Task 2.5 — MUST survive)
    - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift (Plan 03 Task 2.5 — MUST survive)
  </read_first>
  <action>
    **CRITICAL: This task runs ONLY if Task 3a + 3b green.** Continuation of cutover.

    **Step 1 — DELETE 5 files (Round 2 contracts: PRESERVE ReconnectClock.swift + TestClocks.swift):**

    ```bash
    rm BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift
    rm BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift
    ```

    **DO NOT DELETE** (Round 2 B-01 / B-02 cross-plan contract):
    - `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` (B-01 — extracted в Plan 03 Task 2.5; ReconnectClock protocol + SystemReconnectClock struct survive RSM deletion).
    - `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` (B-02 — extracted InstantReconnectClock survives TunnelControllerStateTests deletion).

    После rm `swift build` сломается — это ожидаемо, fix immediately в Steps 2-3.

    **Step 2 — Update App entry points:**

    В `BBTB/App/iOSApp/BBTB_iOSApp.swift` и `BBTB/App/macOSApp/BBTB_macOSApp.swift`:
    - DELETE `let relay = ReconnectStateObserverRelay()` + `relay.makeStateObserver()` usage.
    - Update TunnelController construction: `let tunnel = TunnelController()` (no stateObserver param — был signature update в Task 3a).
    - Migration task + watchdog setup (added в Task 1) preserved.
    - W-02 audit catch-up (если grep в Task 3b пропустил какой-то site): `grep -n '\.retrying\|\.allFailed\|ReconnectStateObserverRelay\|ReconnectStateMachineState' BBTB/App/iOSApp BBTB/App/macOSApp` returns 0.

    **Step 3 — Create TunnelControllerTests.swift (D-24 category 2):**

    `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift` — Replaces deleted TunnelControllerStateTests.

    Coverage minimum (6 tests):
    - Test 1: `connect()` throws when no manager exists в test env (returns empty array из ManagerSelector or загрузка пуста).
    - Test 2: `disconnect()` does not throw when no manager exists.
    - Test 3: `setWatchdog` + subsequent setUserIntent receive value.
    - Test 4: `startReachability` is idempotent.
    - Test 5: After `disconnect`, `failoverProvider.resetCycle` called.
    - Test 6: connect() sets userIntent to true; disconnect() sets to false.

    Tests use existing patterns:
    - FakeStatusProvider (adapt from deleted TunnelControllerStateTests).
    - MockFailoverProvider (adapt from deleted TunnelControllerStateTests).
    - `InstantReconnectClock` из `TestClocks.swift` (Round 2 B-02 preserved file).
    - Header doc-comment ссылается на Plan 06C-04 Task 3c (Round 2 W-01 split), D-24 category 2.

    **Step 4 — Build + xcodebuild green:**

    `swift build --package-path BBTB/Packages/AppFeatures` — должен компилироваться без ошибок.
    `swift test --package-path BBTB/Packages/AppFeatures` — все surviving тесты + новые TunnelControllerTests pass.
    `xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` — full xcode build green.
    `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` — green.

    **Step 5 — Verify metrics (Round 2 B-08 awk comment-stripping):**

    Comment-stripping acceptance grep:
    ```bash
    awk '
      BEGIN { in_block = 0 }
      /\/\*/ { in_block = 1 }
      /\*\// { in_block = 0; next }
      in_block { next }
      { sub(/\/\/.*/, ""); print }
    ' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift \
      | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay|manualDisconnectInProgress|connectInProgress|lastKnownStatus|wakePending|triggerRecoveryIfNeeded"
    ```
    Expected: returns 0 (doc-comments mentioning "Phase 6c replaced ReconnectStateMachine with TunnelWatchdog" are stripped; production code references — none).

    Additional metrics:
    - `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` ≤ 350.
    - `find BBTB/Packages/AppFeatures/Sources/MainScreenFeature -name "ReconnectStateMachine.swift" -o -name "NetworkReachability.swift" | wc -l` = 0 (both deleted).
    - **`test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift`** — file EXISTS (Round 2 B-01 contract).
    - **`test -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift`** — file EXISTS (Round 2 B-02 contract).
    - **`test ! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift`** — file DELETED.
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures && swift test --package-path Packages/AppFeatures && test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift && test -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift</automated>
  </verify>
  <acceptance_criteria>
    - Files DELETED:
      - `! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift`
      - `! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift`
    - Files PRESERVED (Round 2 B-01 + B-02 cross-plan contract):
      - `-f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` — survives RSM deletion.
      - `-f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift` — survives TCST deletion.
    - Files created:
      - `-f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift`
    - `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≤ 350.
    - **Round 2 B-08 awk-stripped grep (replaces broken grep -c on full file):**
      ```bash
      awk 'BEGIN{in_block=0} /\/\*/{in_block=1} /\*\//{in_block=0; next} in_block{next} {sub(/\/\/.*/, ""); print}' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -cE "ReconnectStateMachine|NetworkReachability|ReconnectStateObserverRelay|manualDisconnectInProgress|connectInProgress|lastKnownStatus|wakePending|triggerRecoveryIfNeeded"
      ```
      returns 0.
    - `grep -c "TunnelWatchdog\\|watchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3 (property + setter + uses).
    - `grep -c "NSWorkspace.didWakeNotification" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 1 (D-11 preserved).
    - `grep -v '^#\|^//\|^ *\*' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -c "NWPathMonitor"` returns 0 (NetworkReachability gone).
    - `grep -c "ReconnectStateObserverRelay" BBTB/App/iOSApp/BBTB_iOSApp.swift BBTB/App/macOSApp/BBTB_macOSApp.swift` returns 0.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green (including new TunnelControllerTests — minimum 6 methods).
    - `cd BBTB && xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` succeeds.
    - `cd BBTB && xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` succeeds.
  </acceptance_criteria>
  <done>Cutover complete: 5 files deleted, 2 preserved (B-01/B-02 contract), 1 new (TunnelControllerTests). TunnelController slim ≤ 350. xcodebuild green for both schemes. Awk-stripped grep verifies no symbol references in production code (B-08).</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| TunnelController NEVPN observer ↔ TunnelWatchdog | Status delegated synchronously from observer hot path (XPC-free); watchdog gates on stableSession+userIntent+managerEnabled. |
| App init Task ↔ OnDemandMigrationTask | Fire-and-forget async; migration failures logged; flag NOT set on failure → retry next launch. |
| macOS NSWorkspace.didWake ↔ TunnelController.handleWake | Loads manager (1 XPC trip per wake event); calls startVPNTunnel (idempotent). |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-06C-04-01 | DoS | UAT failure goes undetected → Wave 3 cleanup leaves users in broken state | mitigate | Task 2 explicit checkpoint:human-verify gate. 9 UAT scenarios MUST pass before Task 3 runs. Critical scenarios E/G/A/C are blockers. |
| T-06C-04-02 | DoS | After deletion, hidden compiler error in App entry point references deleted ReconnectStateObserverRelay | mitigate | Task 3 Step 4 explicitly updates App entry points. `xcodebuild` validation in acceptance_criteria catches this. |
| T-06C-04-03 | Tampering | Slim-down accidentally drops macOS wake observer (D-11) | mitigate | Acceptance grep: `NSWorkspace.didWakeNotification` count == 1. |
| T-06C-04-04 | DoS | Migration task races with first provisionTunnelProfile (fresh install + immediate import) | accept | Migration sets flag = true когда managers.isEmpty (Plan 06C-03 Test 2). ConfigImporter.provisionTunnelProfile pisает on-demand на первый import (Plan 06C-02). Both paths converge to correct state. |
| T-06C-04-05 | Information Disclosure | Old Phase 6 logs (Mach-port leak diagnostics) preserved в logs | accept | Не critical — historic context. OSLog hygiene unchanged. |
</threat_model>

<verification>
- Compile: `cd BBTB && swift build --package-path Packages/AppFeatures`
- Package tests: `cd BBTB && swift test --package-path Packages/AppFeatures` — green (Round 2: include 6 TunnelControllerTests, 9 TunnelWatchdogTests, 5 OnDemandMigrationTaskTests, etc.)
- iOS xcodebuild: `cd BBTB && xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` — green
- macOS xcodebuild: `cd BBTB && xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` — green
- Slim-down metric: `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` ≤ 350 (target ~300 per D-15)
- File deletion audit: `git status` shows 5 deleted files (ReconnectStateMachine + tests + NetworkReachability + tests + TunnelControllerStateTests)
- **Round 2 B-01 + B-02 preservation:** `test -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectClock.swift` AND `test -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TestClocks.swift`.
- New file audit: TunnelControllerTests.swift exists (6 tests).
- **Round 2 B-03 fix:** `grep -c "cachedManager?.isEnabled" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 1; `grep -c "lastKnownStatus" ...` returns 0.
- **Round 2 B-04 wiring:** `grep -c "applyCurrentStateToCachedManager\\|applyCurrentState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3.
- **Round 2 B-06:** `grep -c "ManagerSelector.ourManagers" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 2.
- **Round 2 B-08 awk-stripped grep** (replaces Round 1 broken grep): expected count 0 — see Task 3c acceptance.
- **Round 2 W-02:** `grep -rc 'case \.retrying\|case \.allFailed' BBTB/Packages/AppFeatures/Sources` returns 0.
- **Round 2 W-06:** `handleWake` body имеет ≥ 3 guards.
- D-11/12/13 preservation: macOS wake observer present, single startVPNTunnel call (after 3 guards), NO loadAllFromPreferences in observer callback (load happens INSIDE handleWake helper, called from observer — that's one XPC per wake, accepted).
- D-15 cleanup: no references to deleted types in TunnelController.swift или App entry points (verified via awk-stripped grep B-08).
- UAT 9 сценариев captured в SUMMARY.md (pass/fail/notes per scenario; hard-blocker set A/C/E/F/G/I marked Round 2 B-10).
</verification>

<success_criteria>
1. `OnDemandMigrationTask.runIfNeeded()` invoked at App init in both BBTB_iOSApp + BBTB_macOSApp.
2. `TunnelWatchdog` constructed at App init и wired в TunnelController через setWatchdog late-binding.
3. **(Round 2 B-03)** TunnelController имеет `cachedManager: NETunnelProviderManager?` property, populated в startReachability + refreshed через `NotificationCenter` observer на `.bbtbProvisionerDidSave`. Watchdog gate использует `cachedManager?.isEnabled ?? false` (real isEnabled, не broken proxy).
4. **(Round 2 B-04 wiring)** TunnelController.connect()/disconnect() после setUserIntent вызывают `applyCurrentStateToCachedManager` — manager.isOnDemandEnabled immediately flips.
5. TunnelController.swift сократился до ≤ 350 строк (~half size halving per D-15) после Task 3a.
6. ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift — DELETED в Task 3c.
7. **(Round 2 B-01 / B-02 contract)** ReconnectClock.swift + TestClocks.swift PRESERVED (extracted в Plan 03 Task 2.5; они survive RSM/TCST deletion).
8. New TunnelControllerTests.swift с минимум 6 тестами covering connect/disconnect contract.
9. macOS NSWorkspace.didWakeNotification observer preserved (D-11/12/13) **с 3 guards (Round 2 W-06)**: manager.isEnabled + isOnDemandEnabled + loadAutoReconnectEnabled.
10. NEVPNStatusDidChange observer preserved для (a) watchdog delegation и (b) banner state — D-17 narrow.
11. **(Round 2 W-02)** ReconnectBanner enum updated: removed .retrying / .allFailed (audit grep returns 0 across BBTB/Packages/AppFeatures/Sources), added .connecting; .failover(toServerName:) preserved.
12. **(Round 2 Task 3b)** TunnelWatchdog.setFailoverObserver setter added; MainScreenViewModel injects callback at App init для banner.failover wiring.
13. ReconnectStateObserverRelay class — DELETED.
14. Connect/disconnect bodies preserved verbatim (Phase 1-5 polling loops untouched); Round 2 wiring lines добавлены AFTER existing body, не заменяют его.
15. **(Round 2 B-10)** UAT 9 scenarios: hard-blocker set {A, C, E, F, G, I} — ALL must pass before Task 3a/3b/3c run. Non-blocking: {B, D, H}.
16. **(Round 2 B-08)** Task 3c acceptance grep использует awk comment-stripping — doc-comments не дают false positives.
17. **(Round 2 W-01)** Task 3 split into 3a/3b/3c — context-budget safety; each sub-task individually verifiable.
18. Full xcodebuild green for both iOS and macOS schemes.
19. CLAUDE.md соблюдён.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md`. Include:
- Files modified (TunnelController, MainScreenViewModel, ReconnectBanner, BBTB_iOSApp, BBTB_macOSApp, TunnelWatchdog) with diff summary.
- Files DELETED (5) with line counts before deletion: ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift.
- **(Round 2 contract)** Files PRESERVED through cutover: ReconnectClock.swift (B-01), TestClocks.swift (B-02).
- Files CREATED (TunnelControllerTests.swift) с test count (6 minimum).
- TunnelController final line count (target ~300, max 350).
- UAT 9 scenarios result table (A-I with PASS/FAIL/notes per scenario, на которой плате; **hard-blocker set {A, C, E, F, G, I} marked explicitly** per Round 2 B-10).
- Confirmation: macOS wake observer preserved verbatim per D-11/12/13 **с 3 guards (W-06)**.
- Confirmation: connect/disconnect bodies unchanged (only additional lines after setUserIntent).
- **(Round 2)** Confirmation: cachedManager B-03 fix operational; broken `lastKnownStatus != .invalid` proxy GONE.
- **(Round 2)** Confirmation: applyCurrentState wiring complement в connect/disconnect — B-04 phantom-connect mitigation closed.
- **(Round 2)** Confirmation: awk comment-stripped grep returns 0 for deleted symbols (B-08).
- Reference: D-10, D-14, D-15, D-16, D-17, B-01, B-02, B-03, B-04, B-06, B-08, B-10, W-01, W-02, W-06, OQ-2, OQ-3, OQ-6, OQ-7, Pitfall 5.
- Note for Plan 06C-05: regression + Phase 6c UAT formal documentation; update memory entries.
  - **Plan 05 UAT.md table** должна mark A/C/E/F/G/I rows as "Critical / Hard blocker" per Round 2 B-10 cross-plan contract.
- Если UAT had partial failures: explicit list of which scenarios + decision rationale (proceed cleanup with known issues, or fix-forward, or rollback).
</output>
