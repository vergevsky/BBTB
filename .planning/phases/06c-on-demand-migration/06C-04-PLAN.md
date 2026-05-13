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
    - "macOS NSWorkspace.didWakeNotification observer сохранён (D-11/12/13) — единственное действие startVPNTunnel() идемпотентный nudge, БЕЗ XPC trips для status reading"
    - "ReconnectBanner state теперь derived из NEVPNStatus snapshots + TunnelWatchdog state (а не ReconnectStateMachineState enum)"
    - "Files DELETED: ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift"
    - "TunnelController.swift сократился: removed handleReachability, triggerRecoveryIfNeeded, scheduleFailoverResetAfterStableSession, manualDisconnectInProgress/connectInProgress/wakePending flags, ReconnectStateObserverRelay, lastKnownStatus cache, scheduleClearManualDisconnect"
    - "UserIntentStore и userIntendedConnected flag сохранены — watchdog читает их через TunnelController.setUserIntent передающий вниз; OnDemandMigrationTask и watchdog gate используют один источник истины"
    - "Connect()/disconnect() контракт сохранён verbatim: Phase 1-5 polling loops + timeouts identical"
    - "Новый TunnelControllerTests.swift покрывает connect/disconnect contract (replaces deleted TunnelControllerStateTests)"
    - "Device UAT 6 сценариев PASS на iPhone iOS 26.5 + macOS перед merge cutover commit (checkpoint)"
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
      via: "await watchdog.handleStatusChange(status, managerEnabled: cachedIsEnabled)"
      pattern: "watchdog\\.handleStatusChange"
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

Структура wave:
1. **Wire** OnDemandMigrationTask в App init (iOS + macOS), wire TunnelWatchdog в TunnelController, replace ReconnectStateMachine recovery path с watchdog delegation. PRESERVE macOS wake observer (D-11/12/13 — текущий pattern correct). PRESERVE connect()/disconnect() contract verbatim.
2. **Build + test** — полная сюита AppFeatures green после wiring (старые tests ReconnectStateMachineTests / NetworkReachabilityTests / TunnelControllerStateTests всё ещё проходят, потому что мы ещё их не удалили — это checkpoint!).
3. **Device UAT** — checkpoint:human-verify. 6 сценариев на iPhone iOS 26.5 + macOS smoke. Если PASS → proceed to cleanup. Если FAIL → fix-forward или rollback toggle до plan 06C-03 state.
4. **Cleanup** — DELETE: ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift; SLIM TunnelController.swift halving (~618 → ~300 lines); CREATE replacement TunnelControllerTests.swift covering connect/disconnect contract.
5. **Final build + test** — full xcodebuild green; commit как cutover commit.

Purpose:
- D-10/D-14/D-15 cleanup полностью выполнен — ~570 строк custom auto-reconnect logic удалено.
- D-16 preservation invariant: FailoverProvider.swift, SwiftDataFailoverProvider остаются unchanged.
- D-11/D-12/D-13: macOS wake observer specifically preserved (cheap idempotent nudge `startVPNTunnel()`, NO XPC).
- D-17 narrow: NEVPNStatusDidChange observer остаётся ТОЛЬКО для (a) banner UI feeding и (b) delegate в watchdog для mid-session failover. Никаких recovery branches.
- OQ-2 решение: `userIntendedConnected` (UserIntentStore) **сохраняем как локальный gate watchdog'а** — переименовать переменную нет necessity, semantics остаётся «user wants tunnel». connectInProgress/manualDisconnectInProgress flags **удалены** — они нужны были только для recovery path race protection, в новой архитектуре нет recovery path.
- OQ-3 решение: TunnelWatchdog как **отдельный actor file** (создан в Plan 06C-03), wired в TunnelController через late-binding setter (mirror того как failoverProvider wires).
- OQ-6 решение: FailoverProvider.connect closure НЕ изменяется. Apple's on-demand параллельно reconnect'ит — может попасть в «уже .connecting»; TunnelController.connect() polling loop уже трактует `.disconnecting` как transient (line 282 comment). Если Apple's запустил с старого config — наш swap saveToPreferences с новым config заставит OS перезагрузить config. UAT-Task E validate this.
- OQ-7 решение: Banner state map — `.connecting` → "Подключение"; `.reasserting` → "Переподключение"; watchdog `nextServerAttempt called` → "Переключение на другой сервер" (failover signal); никакого `allFailed` (Apple's on-demand крутится дольше — UX-неправильно говорить «всё failed», пока iOS retries).

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

| # | Сценарий | Ожидание | Plat |
|---|----------|----------|------|
| A | Wi-Fi off → LTE → reconnect | Туннель сам поднимается в течение ~5s; нет двойных reconnect; logs показывают on-demand путь, watchdog НЕ срабатывает (т.к. это не «сервер мёртв», это «сменил сеть») | iOS |
| B | iPhone overnight (sleep+wake) | Утром туннель уже up без открытия app; ip-check показывает VPN IP | iOS |
| C | MacBook sleep 10 min → wake | В течение 15s туннель up; logs показывают (a) on-demand сработал ИЛИ (b) NSWorkspace.didWake observer вызвал startVPNTunnel — допустимы оба пути | macOS |
| D | Сменить Wi-Fi сеть (другая SSID) | Reconnect автоматический; нет крашей; нет фантомных reconnect | iOS |
| E | **Stable session 1min, kill server-side sing-box (или firewall block)** | Watchdog срабатывает после 3s debounce, swap к next серверу; Apple's on-demand не приводит к stuck-on-connecting; UI banner показывает «Переключение на сервер X» | iOS |
| F | Активировать другой VPN (ProtonVPN), потом вернуться в BBTB | BBTB Connect одним тапом работает; нет «fight-back»; нет автоматического reconnect ДО пользовательского тапа | iOS |
| G | App in background 30+ min, проверить crash logs | НИ ОДНОГО EXC_RESOURCE / PORT_SPACE | iOS 26.5 |
| H | Toggle «Авто-переподключение» OFF while connected | Туннель остаётся up; банер не показывает | iOS |
| I | Migration smoke (если есть существующий профиль из Phase 6): первый запуск Phase 6c build | Manager.isOnDemandEnabled = true (проверить через Settings → VPN → BBTB → On Demand Activation toggle); auto-reconnect работает уже сразу без re-import | iOS |

UAT PASS-критерий: 9/9 сценариев PASS. **6/9 минимум** для proceed to cleanup; 7+ recommended. Любая критическая регрессия из E/G — **STOP cleanup**, fix-forward в этой wave.
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

    **Step 1 — App entry points:**

    В `BBTB/App/iOSApp/BBTB_iOSApp.swift` и `BBTB/App/macOSApp/BBTB_macOSApp.swift`:
    - НАЙТИ block где конструируется TunnelController (около line 62-88 в iOS, line 51-74 в macOS).
    - ПЕРЕД конструированием TunnelController, добавить `Task { await OnDemandMigrationTask.runIfNeeded() }`.
    - Это async fire-and-forget — running concurrently с rest of setup. Идемпотентный, безопасно если другая часть приложения тоже могла бы это вызвать.
    - Doc-comment inline: `// Phase 6c / Plan 06C-04 / D-17b/c — one-shot migration of existing manager to on-demand.`

    **Step 2 — TunnelController watchdog wiring:**

    Внутри `TunnelController` (НЕ удаляя ничего из существующего):
    - Добавить stored property `private var watchdog: TunnelWatchdog?` (optional — wired через late-binding setter mirror of failoverProvider).
    - Добавить `public func setWatchdog(_ watchdog: TunnelWatchdog) { self.watchdog = watchdog }`.
    - В `connect()`: после `setUserIntendedConnected(true)`, добавить `await watchdog?.setUserIntent(true)`.
    - В `disconnect()`: после `setUserIntendedConnected(false)`, добавить `await watchdog?.setUserIntent(false)`.
    - В `handleStatusChange(_:)`: AFTER existing branches, добавить `let cachedEnabled = lastKnownStatus != .invalid; await watchdog?.handleStatusChange(status, managerEnabled: cachedEnabled)`. **Cache hint**: `cachedEnabled` имитирует «manager.isEnabled» — в test env мы не можем проверять manager напрямую без entitlement, поэтому используем proxy (status != .invalid ≈ profile установлен и не disabled). Это conservative — если manager .invalid, не fire failover. UAT-Task F verify.

    **Step 3 — App entry point: construct TunnelWatchdog and wire to TunnelController (after failoverProvider):**

    В обоих App entry points, после `Task { await tunnel.setFailoverProvider(failoverProvider) }`:
    ```swift
    // Phase 6c / Plan 06C-04 — TunnelWatchdog for mid-session server failover (D-08, D-09).
    Task {
        let watchdog = TunnelWatchdog(failoverProvider: failoverProvider)
        await tunnel.setWatchdog(watchdog)
    }
    ```

    **Step 4 — Banner state mapping (additive — старый relay path всё ещё работает):**

    В `ReconnectBanner.swift`: добавить новый case `.connecting` в enum рендеринг (рядом с existing `.retrying`):
    ```swift
    case .connecting: Text(L10n.bannerConnecting)
    ```
    Использовать существующую локализацию `bannerReconnecting` или добавить новый key `bannerConnecting` (ru="Подключение", en="Connecting") если необходимо.

    В `MainScreenViewModel.swift`: добавить wire-up второго source для banner state. Сейчас banner state идёт через `ReconnectStateObserverRelay`. Добавить дополнительный observer на NEVPNStatusDidChange который ТАКЖЕ обновляет `reconnectBannerState` для simple .connecting/.connected/.disconnected mapping. Old observer (через relay) ОСТАЁТСЯ — Task 3 (cleanup) удалит его. Это parallel-run шаг (priority of last writer wins — может flicker, тоже OK temporary).

    **Step 5 — Build + verify:**

    `swift build --package-path BBTB/Packages/AppFeatures` succeed.
    `swift test --package-path BBTB/Packages/AppFeatures` full suite green — НИКАКИХ regressions. Старые tests (ReconnectStateMachineTests, NetworkReachabilityTests, TunnelControllerStateTests) ВСЕ ЕЩЁ pass.

    КРИТИЧЕСКИ:
    - Никаких deletes в Task 1. Pure additive.
    - Existing failoverProvider.connect closure НЕ модифицируется (D-16 + OQ-6).
    - macOS wake observer НЕ модифицируется в Task 1 (preserved as-is).
    - Connect/disconnect bodies НЕ изменяются — только две новые строки watchdog.setUserIntent в каждом.
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
    - Полная AppFeatures test-сюита green.
    - Build iOS + macOS schemes succeeds (если планер запускает `xcodebuild`; иначе оставить как UAT prep).
  </acceptance_criteria>
  <done>Migration task wired в App init для обеих платформ. TunnelWatchdog wired в TunnelController через late-binding setter и получает события из существующего NEVPNStatusDidChange observer. Все pre-existing tests pass. Старая machinery всё ещё работает — parallel run между builder, watchdog, и existing recovery path. Ready for device UAT.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 2 (Checkpoint): Device UAT — 9 scenarios on iPhone iOS 26.5 + macOS</name>
  <what-built>
    Wave 0-1-2 + Task 1 of Wave 3 are now live:
    - OnDemandRulesBuilder produces `[NEOnDemandRuleConnect(.any)]` + isOnDemandEnabled.
    - DefaultTunnelProvisioner.provisionTunnelProfile вызывает builder на каждый import.
    - SettingsView показывает раздел «Подключение» с toggle (default ON).
    - OnDemandMigrationTask запускается на app init — мигрирует existing manager к on-demand.
    - TunnelWatchdog wired в TunnelController, fires failover при stable-session disconnects (3s debounce).
    - macOS NSWorkspace.didWakeNotification observer preserved.
    - Старая custom-reconnect machinery (ReconnectStateMachine, NetworkReachability, NEVPNStatusDidChange recovery branches) ВСЕ ЕЩЁ работает параллельно — это последний шанс fix-forward без losing rollback path.
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

    Запись результатов:
    - 9 сценариев → 9/9 PASS = full success → proceed Task 3 cleanup.
    - 6-8/9 PASS = partial success → анализировать failure. Если non-critical (B, D, H) → may proceed cleanup с known issues. Если critical (E, G, A, C) → STOP cleanup, fix-forward в Task 1.
    - <6/9 PASS → STOP, escalate to user.
  </how-to-verify>
  <resume-signal>
    Type one of:
    - `uat passed` — all critical scenarios passed; proceed to Task 3 cleanup.
    - `uat partial: <details>` — some non-critical failures; describe and decide.
    - `uat failed: <details>` — critical failure; stop and fix.
    - `skip uat` — defer UAT (then Task 3 cleanup blocked; this leaves Phase 6c in parallel-run state indefinitely until UAT done).
  </resume-signal>
  <files>n/a — checkpoint task; no files modified by executor (results recorded in 06C-UAT.md by Plan 06C-05)</files>
  <action>Pause execution and wait for human-verified UAT result (see what-built + how-to-verify above). Do not proceed to Task 3 until resume-signal received.</action>
  <verify>Human reviewer types one of the resume-signal phrases.</verify>
  <done>UAT result recorded; executor receives explicit go/no-go signal for Task 3.</done>
</task>

<task type="auto">
  <name>Task 3: Cutover Cleanup — DELETE ReconnectStateMachine + NetworkReachability + stale TunnelController code; CREATE TunnelControllerTests replacement</name>
  <files>BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift, BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift, BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift, BBTB/App/iOSApp/BBTB_iOSApp.swift, BBTB/App/macOSApp/BBTB_macOSApp.swift</files>
  <read_first>
    - .planning/phases/06c-on-demand-migration/06C-CONTEXT.md D-10, D-14, D-15, D-17 (cleanup boundaries)
    - .planning/phases/06c-on-demand-migration/06C-RESEARCH.md «Recommended Project Structure» (target layout)
    - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (final review — какие методы куда)
    - .planning/phases/06-network-resilience/06-05-PLAN.md строки 1-100 (для понимания связности существующего wiring)
  </read_first>
  <action>
    **CRITICAL: This task runs ONLY if Task 2 UAT resumed with `uat passed` (or partial with explicit confirmation).** Do NOT proceed if UAT had critical failures.

    **Step 1 — DELETE files:**
    ```
    rm BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift
    rm BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift
    rm BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift
    ```

    После удаления `swift build` сломается — это ожидаемо, fix immediately в Steps 2-4.

    **Step 2 — TunnelController.swift slim down:**

    Открыть `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (618 строк) и DELETE:

    - Stored properties:
      - `reachability: NetworkReachability` (deletion)
      - `stateMachine: ReconnectStateMachine` (deletion)
      - `reconnectClock: ReconnectClock` (deletion — moved into watchdog; TunnelController itself doesn't need a clock)
      - `manualDisconnectInProgress: Bool` (deletion — no recovery path race anymore)
      - `lastKnownStatus: NEVPNStatus` (deletion — watchdog reads passed status from observer)
      - `connectInProgress: Bool` (deletion — no recovery path = no reentrance race)
      - `lastSuccessfulConnectAt: Date?` (deletion — watchdog tracks own session)
      - `wakePending: Bool` (deletion — iOS handled by Apple; macOS direct nudge)
    - Methods:
      - `handleReachability(_:)` (deletion)
      - `triggerRecoveryIfNeeded(reason:)` (deletion)
      - `scheduleFailoverResetAfterStableSession(startedAt:)` (deletion — watchdog has own)
      - `scheduleClearManualDisconnect()` + `clearManualDisconnect()` (deletion)
      - `firstAttemptOverrideForTest` + `setFirstAttemptOverrideForTest(_:)` (deletion)
      - `isManualDisconnectInProgress` / `_setManualDisconnectForTest` (deletion)
      - `getLastSuccessfulConnectAt` (deletion)
      - `_setConnectInProgressForTest` / `getConnectInProgressForTest` (deletion)
    - From `init`:
      - Remove `reachability:` and `stateMachine:` parameters and assignments.
      - Remove `reconnectClock:` parameter.
      - Remove `stateObserver:` parameter (ReconnectStateObserverRelay gone in Step 4).
      - **Keep**: statusProvider, failoverProvider, intentStore (preserved per OQ-2).
    - `ReconnectStateObserverRelay` class: DELETE (lines 111-131).
    - `handleStatusChange(_:)`: keep, но body упрощается:
      ```swift
      internal func handleStatusChange(_ status: NEVPNStatus) async {
          // Update banner state through a separate publication path (TODO: see Step 3).
          let cachedEnabled = status != .invalid
          await watchdog?.handleStatusChange(status, managerEnabled: cachedEnabled)
      }
      ```
    - `startReachability()`: SIMPLIFIED — больше нет reachability actor. Body:
      ```swift
      public func startReachability() async {
          guard !reachabilityStarted else { return }
          reachabilityStarted = true

          // NEVPNStatusDidChange observer — D-17 narrow: только delegates в watchdog + banner.
          // CRITICAL: reads status from notification.object (synchronous — NO XPC).
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

          #if os(macOS)
          // D-11/12/13 — wake observer backup. NSWorkspace.shared.notificationCenter (NOT .default).
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
    - `handleWake()` (macOS only): simplified per RESEARCH Pattern 4:
      ```swift
      #if os(macOS)
      private func handleWake() async {
          let managers = (try? await NETunnelProviderManager.loadAllFromPreferences()) ?? []
          try? managers.first?.connection.startVPNTunnel()  // idempotent nudge
      }
      #endif
      ```
    - `stopReachability()`: simplified — remove reachability.stop() call.
    - `handleForeground()`: keep как cheap no-op (или DELETE if no callers; check `grep handleForeground` остальной codebase).

    После slim-down: TunnelController.swift должен быть ≤ 350 строк (target ~300 per D-15).

    **Step 3 — MainScreenViewModel banner state rewire:**

    Удалить ReconnectStateMachineState consumption. Reconnect banner state теперь derived из:
    - `NEVPNStatus` notification (`.connecting` / `.reasserting` → `.connecting`; `.disconnected` → `.hidden`).
    - Watchdog failover signal (`callback: @Sendable (String) -> Void` injected в watchdog init from VM-side; VM маппит в `.failover(toServerName:)`).
    
    Implementation:
    - Update `ReconnectBannerState` enum:
      ```swift
      public enum ReconnectBannerState: Equatable, Sendable {
          case hidden
          case killSwitchReconfigure
          case connecting
          case failover(toServerName: String)
      }
      ```
      Удалить `.retrying`, `.allFailed` cases (breaking change).
    - In MainScreenViewModel.init: установить NEVPNStatusDidChange observer (mainactor closure), маппить status → reconnectBannerState через `@Published` setter.
    - Watchdog failover signaling: Plan 06C-03's TunnelWatchdog API НЕ имела callback. Wave 3 modification: добавить optional callback в init либо в setter. Минимально-инвазивное решение — добавить `public func setFailoverObserver(_ observer: @escaping @Sendable (String) async -> Void)` к TunnelWatchdog (~5 строк). VM передаёт closure что updates `@Published`.

    **Step 4 — Wave 3 cleanup of App entry points:**

    В обоих App entry points:
    - DELETE `let relay = ReconnectStateObserverRelay()` + `relay.makeStateObserver()` usage.
    - Update TunnelController construction: `let tunnel = TunnelController()` (no stateObserver).
    - Watchdog setup (added in Task 1) preserved.

    **Step 5 — Create TunnelControllerTests.swift (D-24 category 2):**

    `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift` — Replaces deleted TunnelControllerStateTests:

    Coverage minimum:
    - Test 1: `connect()` throws when no manager exists в test env (returns empty array).
    - Test 2: `disconnect()` does not throw when no manager exists.
    - Test 3: `setWatchdog` + subsequent setUserIntent receive value.
    - Test 4: `startReachability` is idempotent.
    - Test 5: After `disconnect`, `failoverProvider.resetCycle` called.
    - Test 6: connect() sets userIntent to true; disconnect() sets to false.

    Tests use FakeStatusProvider, MockFailoverProvider patterns existing in deleted TunnelControllerStateTests.swift (можно adapt, не копировать целиком — D-23 говорит «удалить большую часть»).

    **Step 6 — Build + test:**

    `swift build --package-path BBTB/Packages/AppFeatures` — должен компилироваться без ошибок.
    `swift test --package-path BBTB/Packages/AppFeatures` — все surviving тесты + новые TunnelControllerTests pass.
    `xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` — full xcode build green.
    `xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` — green.

    **Step 7 — Verify metrics:**
    - `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` ≤ 350.
    - `find BBTB/Packages/AppFeatures/Sources/MainScreenFeature -name "ReconnectStateMachine.swift" -o -name "NetworkReachability.swift" | wc -l` = 0 (both deleted).
    - `grep -c "ReconnectStateMachine\\|NetworkReachability" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` = 0 (no references left).
  </action>
  <verify>
    <automated>cd BBTB && swift build --package-path Packages/AppFeatures && swift test --package-path Packages/AppFeatures && wc -l Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | awk '{ if ($1 > 350) exit 1; else print "OK: " $1 " lines" }'</automated>
  </verify>
  <acceptance_criteria>
    - Files DELETED:
      - `! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift`
      - `! -f BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/NetworkReachabilityTests.swift`
      - `! -f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift`
    - Files created:
      - `-f BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerTests.swift`
    - `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≤ 350.
    - `grep -c "ReconnectStateMachine\\|NetworkReachability\\|ReconnectStateObserverRelay\\|manualDisconnectInProgress\\|connectInProgress\\|lastKnownStatus\\|wakePending\\|triggerRecoveryIfNeeded" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 0.
    - `grep -c "TunnelWatchdog\\|watchdog" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns ≥ 3 (property + setter + uses).
    - `grep -c "NSWorkspace.didWakeNotification" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` returns 1 (D-11 preserved).
    - `grep -v '^#\\|^//\\|^ *\\*' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift | grep -c "NWPathMonitor"` returns 0 (NetworkReachability gone).
    - `grep -c "ReconnectStateObserverRelay" BBTB/App/iOSApp/BBTB_iOSApp.swift BBTB/App/macOSApp/BBTB_macOSApp.swift` returns 0.
    - `cd BBTB && swift test --package-path Packages/AppFeatures` full suite green (including new TunnelControllerTests).
    - `cd BBTB && xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` succeeds.
    - `cd BBTB && xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` succeeds.
  </acceptance_criteria>
  <done>Custom auto-reconnect machinery fully removed. TunnelController slim (~300 lines). Watchdog + on-demand handle all D-19/20/21 success criteria. New TunnelControllerTests cover connect/disconnect contract. Cutover commit ready.</done>
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
- Package tests: `cd BBTB && swift test --package-path Packages/AppFeatures` — green
- iOS xcodebuild: `cd BBTB && xcodebuild -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16' build` — green
- macOS xcodebuild: `cd BBTB && xcodebuild -scheme BBTB-macOS -destination 'platform=macOS' build` — green
- Slim-down metric: `wc -l BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` ≤ 350 (target ~300 per D-15)
- File deletion audit: `git status` shows 5 deleted files (ReconnectStateMachine + tests + NetworkReachability + tests + TunnelControllerStateTests)
- New file audit: TunnelControllerTests.swift exists
- D-11/12/13 preservation: macOS wake observer present, single startVPNTunnel call, NO loadAllFromPreferences in observer callback (load happens INSIDE handleWake helper, called from observer — that's one XPC per wake, accepted)
- D-15 cleanup: no references to deleted types in TunnelController.swift или App entry points
- UAT 9 сценариев captured в SUMMARY.md (pass/fail/notes per scenario)
</verification>

<success_criteria>
1. `OnDemandMigrationTask.runIfNeeded()` invoked at App init in both BBTB_iOSApp + BBTB_macOSApp.
2. `TunnelWatchdog` constructed at App init и wired в TunnelController через setWatchdog late-binding.
3. TunnelController.swift сократился до ≤ 350 строк (~half size halving per D-15).
4. ReconnectStateMachine.swift, NetworkReachability.swift, ReconnectStateMachineTests.swift, NetworkReachabilityTests.swift, TunnelControllerStateTests.swift — DELETED.
5. New TunnelControllerTests.swift с минимум 6 тестами covering connect/disconnect contract.
6. macOS NSWorkspace.didWakeNotification observer preserved (D-11/12/13 — единственный startVPNTunnel idempotent nudge).
7. NEVPNStatusDidChange observer preserved для (a) watchdog delegation и (b) banner state — D-17 narrow.
8. ReconnectBanner enum updated: removed .retrying / .allFailed, added .connecting; .failover(toServerName:) preserved.
9. ReconnectStateObserverRelay class — DELETED.
10. Connect/disconnect bodies preserved verbatim (Phase 1-5 polling loops untouched).
11. UAT 9 scenarios PASS (critical: E, G, A, C, F).
12. Full xcodebuild green for both iOS and macOS schemes.
13. CLAUDE.md соблюдён.
</success_criteria>

<output>
After completion, create `.planning/phases/06c-on-demand-migration/06C-04-SUMMARY.md`. Include:
- Files modified (TunnelController, MainScreenViewModel, ReconnectBanner, BBTB_iOSApp, BBTB_macOSApp) with diff summary.
- Files DELETED (5) with line counts before deletion.
- Files CREATED (TunnelControllerTests.swift) с test count.
- TunnelController final line count (target ~300, max 350).
- UAT 9 scenarios result table (A-I with PASS/FAIL/notes per scenario, на которой плате).
- Confirmation: macOS wake observer preserved verbatim per D-11/12/13.
- Confirmation: connect/disconnect bodies unchanged.
- Reference: D-10, D-14, D-15, D-16, D-17, OQ-2, OQ-3, OQ-6, OQ-7, Pitfall 5.
- Note for Plan 06C-05: regression + Phase 6c UAT formal documentation; update memory entries.
- Если UAT had partial failures: explicit list of which scenarios + decision rationale (proceed cleanup with known issues, or fix-forward, or rollback).
</output>
