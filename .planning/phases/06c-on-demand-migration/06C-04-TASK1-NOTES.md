---
phase: 06c-on-demand-migration
plan: 04
task: 1
type: interim-checkpoint-notes
status: complete
parallel_run_mode: active
next_step: Task 2 (Device UAT — checkpoint:human-verify)
---

# Phase 6c / Plan 06C-04 / Task 1 — Wiring Complete (Interim Notes)

> Этот файл — **промежуточный checkpoint** между Task 1 и Task 2 UAT.
> Финальный `06C-04-SUMMARY.md` напишет Task 3c после успешного UAT pass.

## Что сделано в Task 1

Task 1 — **pure additive wiring**: новые компоненты (TunnelWatchdog,
OnDemandMigrationTask) wired в `TunnelController` + App entry points;
старая custom-reconnect machinery (`ReconnectStateMachine`,
`NetworkReachability`, `ReconnectStateObserverRelay`) **ОСТАЁТСЯ работать
параллельно** для UAT validation. Plan 04 Task 3a/3b/3c удалит старую
machinery только после UAT pass.

### Step 1 — App entry points (iOS + macOS)

Файлы:
- `BBTB/App/iOSApp/BBTB_iOSApp.swift`
- `BBTB/App/macOSApp/BBTB_macOSApp.swift`

Добавлено в init():
1. `Task { await OnDemandMigrationTask.runIfNeeded() }` — D-17b/c one-shot
   migration existing manager (idempotent, UserDefaults flag).
   Запускается ПЕРЕД конструированием `TunnelController` (race-safe — init
   `startReachability` всё равно подхватит result через
   `.bbtbProvisionerDidSave` observer).
2. После `Task { await tunnel.setFailoverProvider(failoverProvider) }`:
   `Task { let watchdog = TunnelWatchdog(failoverProvider: failoverProvider); await tunnel.setWatchdog(watchdog) }`
   — D-08/D-09 mid-session failover.

### Step 2 — TunnelController.swift additive wiring

Файл: `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`

**Новые stored properties:**
- `private var watchdog: TunnelWatchdog?` — late-binding (mirror failoverProvider pattern).
- `private var cachedManager: NETunnelProviderManager?` — Round 2 B-03 real
  `manager.isEnabled` gate (replaces broken proxy).
- `private var provisionerObserver: NSObjectProtocol?` — NotificationCenter
  token для `.bbtbProvisionerDidSave`.

**Новые public/private members:**
- `public func setWatchdog(_ watchdog: TunnelWatchdog)` — late-binding setter.
- `private func refreshCachedManager() async` — обновляет `cachedManager`
  через `loadAllFromPreferences()` + `ManagerSelector.ourManagers` (B-06).
- `private func applyCurrentStateToCachedManager() async` — Round 2 B-04
  wiring complement + Round 3 N-01 load-on-demand fallback + Round 3
  MINOR-01 graceful degradation. Применяет `OnDemandRulesBuilder.applyCurrentState`
  к cached manager'у + save + reload.

**Обновлённые методы:**
- `startReachability()`:
  - Добавлен initial `await refreshCachedManager()` после macOS wake observer
    (single XPC call per actor lifetime).
  - Добавлен `bbtbProvisionerDidSave` observer — refresh cachedManager на
    каждое save event от ConfigImporter / SettingsViewModel / OnDemandMigrationTask.
- `stopReachability()`:
  - Unregister provisioner observer.
- `connect()`:
  - После `setUserIntendedConnected(true)`:
    `await watchdog?.setUserIntent(true)`
    `await applyCurrentStateToCachedManager()` — B-04 wiring complement.
- `disconnect()`:
  - После `setUserIntendedConnected(false)`:
    `await watchdog?.setUserIntent(false)`
    `await applyCurrentStateToCachedManager()`.
- `handleStatusChange(_:)`:
  - ДО существующего switch, добавлен:
    `let managerEnabled = cachedManager?.isEnabled ?? false`
    `await watchdog?.handleStatusChange(status, managerEnabled: managerEnabled)`
  - Существующий switch (с `.connected` reportConnected + `.disconnected`
    triggerRecoveryIfNeeded path) ПРЕСЕРВИРОВАН — старая machinery работает
    параллельно.
- `triggerRecoveryIfNeeded(reason:)`:
  - Заменён сломанный `guard lastKnownStatus != .invalid` на real
    `cachedManager?.isEnabled ?? false` gate (B-03 fix). Test seam
    `cachedManagerEnabledOverrideForTest: Bool?` добавлен для tests без
    entitlements.

### Step 4 — macOS handleWake() — Round 2 W-06 3 guards

Body `handleWake()` теперь:
1. `wakePending = true` (Phase 6 parallel-run preserve — Plan 04 Task 3a removes).
2. `loadAllFromPreferences()` → `ManagerSelector.ourManagers(...).first`
   (B-06 multi-manager safety).
3. **3 guards** (W-06):
   - `manager.isEnabled` (bug class 3 — fight-back mitigation).
   - `manager.isOnDemandEnabled` (user choice respected).
   - `OnDemandRulesBuilder.loadAutoReconnectEnabled()` (Settings toggle).
4. Если все guards pass — `try? manager.connection.startVPNTunnel()`
   (idempotent nudge).

### Step 5 — Banner additive parallel-run prep

Файлы:
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift`
- `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`

Изменения:
- `ReconnectBannerState` enum: добавлен `.connecting` case (Plan 04 Task 3b
  удалит `.retrying` / `.allFailed`). `.retrying` / `.allFailed` пресервированы.
- `reconnectBannerMessage`: добавлена ветка `.connecting → L10n.bannerConnecting`.
- Новый `nevpnStatusObserver: NSObjectProtocol?` — NEVPNStatusDidChange observer
  для baseline `.connecting → .connecting banner` mapping. Читает status
  напрямую из `notification.object` (sync property, не XPC) — bug class 4
  mitigation.
- Новый `applyVPNStatusToBanner(_:)` метод — non-override активного auto-reconnect
  banner; last-writer-wins parallel-run приемлемо temporary.
- L10n:
  - Добавлен `bannerConnecting = tr("banner.connecting")` в `L10n.swift`.
  - Добавлен ru/en string entry в `Localizable.xcstrings`:
    en="Connecting…", ru="Подключение…".

## Tests

**Полная AppFeatures test-сюита: 163/163 PASS, 0 failures.**

Изменения в tests:
- `TunnelControllerStateTests.swift`:
  - `test_handleStatusChange_triggersRecoveryOnUnexpectedDisconnect` —
    добавлен `await controller._setCachedManagerEnabledOverrideForTest(true)`
    (новый gate требует `cachedManager.isEnabled == true`).
  - `test_allFailed_consults_failoverProvider` — добавлен тот же seam.

Test seam в production: `cachedManagerEnabledOverrideForTest: Bool?` —
production sets nil → behavior unchanged; tests opt-in.

## Build verification

- `swift build --package-path BBTB/Packages/AppFeatures`: **green** (3.76s).
- `swift test --package-path BBTB/Packages/AppFeatures`: **163/163 PASS** (5.45s).
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB -destination 'platform=iOS Simulator,name=iPhone 17'`: **BUILD SUCCEEDED**.
- `xcodebuild -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`: **BUILD SUCCEEDED**
  (полный build с code signing отдельно blocked test-машиной без dev certs —
  pre-existing limitation, не Phase-6c-specific).

## Parallel-run invariant — что PRESERVED для UAT validation

Эти системы продолжают работать ПАРАЛЛЕЛЬНО с новой watchdog/migration
machinery. Plan 04 Task 3a/3b/3c удалит их только после успешного UAT:

1. **ReconnectStateMachine** — `triggerRecoveryIfNeeded → stateMachine.run`
   path активен; на `.disconnected` без `manualDisconnectInProgress` всё ещё
   запускается старая retry-3-attempts logic.
2. **NetworkReachability** — actor-based NWPathMonitor observer; `handleReachability`
   всё ещё trigger'ит recovery на `.satisfied` / `.changed`.
3. **ReconnectStateObserverRelay** — relay box между TunnelController и
   MainScreenViewModel; конструируется в App entry points; passes observer
   через `TunnelController.init(stateObserver:)`.
4. **`.retrying`/`.allFailed`** banner cases — feeded старой
   `applyReconnectStateMachineState` path через relay observer.
5. **`triggerRecoveryIfNeeded` path в `handleStatusChange`** — старая
   `.disconnected → triggerRecoveryIfNeeded` ветка switch'а сохранена.
6. **`wakePending = true` в `handleWake()`** — macOS старый path
   (handleReachability consumes wakePending) preserved параллельно с
   новым nudge.

## Pending — что будет в Task 3a/3b/3c после UAT pass

### Task 3a (TunnelController slim-down — ≤ 350 lines)
- DELETE stored props: `reachability`, `stateMachine`, `reconnectClock`,
  `manualDisconnectInProgress`, `lastKnownStatus`, `connectInProgress`,
  `lastSuccessfulConnectAt`, `wakePending`, `intentStore` (move to watchdog
  via setUserIntent path), `firstAttemptOverrideForTest`,
  `cachedManagerEnabledOverrideForTest` (Phase 6 test seam — больше не нужен
  после удаления triggerRecoveryIfNeeded).
- DELETE methods: `handleReachability`, `triggerRecoveryIfNeeded`,
  `scheduleFailoverResetAfterStableSession`, `scheduleClearManualDisconnect`,
  `clearManualDisconnect`, старая часть `handleWake` (wakePending),
  `_setManualDisconnectForTest`, `_setUserIntendedConnectedForTest`,
  `_setConnectInProgressForTest`, `setFirstAttemptOverrideForTest`,
  `_setCachedManagerEnabledOverrideForTest`.
- DELETE init parameters: `reachability`, `reconnectClock`, `stateObserver`,
  `intentStore`.
- DELETE `ReconnectStateObserverRelay` class.

### Task 3b (Banner rewire — W-02 audit first)
- grep all `case .retrying` / `case .allFailed` consumer sites BEFORE
  enum mutation.
- REMOVE `.retrying` / `.allFailed` cases from `ReconnectBannerState`.
- Update `MainScreenViewModel`: drop `applyReconnectStateMachineState`,
  `makeReconnectStateObserver`. Keep `applyVPNStatusToBanner` as primary
  source.
- Add `setFailoverObserver` to TunnelWatchdog (deferred from Plan 03 Task 3) —
  watchdog notifies VM на firing nextServerAttempt для `.failover` banner.

### Task 3c (Cleanup + create TunnelControllerTests)
- DELETE 5 files: `ReconnectStateMachine.swift`, `NetworkReachability.swift`,
  `ReconnectStateMachineTests.swift`, `NetworkReachabilityTests.swift`,
  `TunnelControllerStateTests.swift`.
- PRESERVE: `ReconnectClock.swift` (B-01 — used by watchdog),
  `TestClocks.swift` (B-02 — test infrastructure).
- CREATE: `TunnelControllerTests.swift` (≥ 6 tests, D-24 category 2 —
  connect/disconnect contract preservation).
- Update App entry points: drop `ReconnectStateObserverRelay` references,
  drop `relay.makeStateObserver()` argument, drop relay binding line.
- Acceptance: awk-stripped grep returns 0 for deleted symbol references (B-08).

## Round-2/3 invariants verified in Task 1 implementation

| Invariant | Status | Evidence |
|-----------|--------|----------|
| B-03 cachedManager + bbtbProvisionerDidSave observer | DONE | `cachedManager` populated в startReachability + refreshed on notification |
| B-03 lastKnownStatus != .invalid proxy REPLACED | DONE | grep returns 0; gate теперь `cachedManager?.isEnabled ?? false` |
| B-04 wiring complement в connect/disconnect | DONE | `applyCurrentStateToCachedManager()` called после setUserIntent |
| B-06 ManagerSelector.ourManagers usage | DONE | refreshCachedManager + handleWake (2 callsites) |
| N-01 load-on-demand fallback в applyCurrentStateToCachedManager | DONE | `if cachedManager == nil { await refreshCachedManager() }` |
| N-01 defensive log на failed-even-after-refresh | DONE | `log.warning("...no manager available even after refresh...")` |
| MINOR-01 graceful degradation в catch | DONE | log.warning + return; никогда throw |
| W-05 .reasserting cancellation | INHERITED (Plan 03) | TunnelWatchdog.handleStatusChange handles .reasserting |
| W-06 macOS handleWake 3 guards | DONE | isEnabled + isOnDemandEnabled + loadAutoReconnectEnabled |
| Parallel-run preserved | DONE | RSM/NetReach/relay/recovery branches все intact |

## UAT prerequisites (для Task 2)

1. Развернуть Phase 6c build на physical iPhone iOS 26.5 + macOS test machine.
2. Если upgrade flow тестируется (Сценарий I) — иметь существующий Phase 6
   build установленный заранее (через TestFlight или дев build).
3. Получить VPS access для Сценария E (kill server-side sing-box процесс).
4. Открыть Console.app для streaming logs обоих процессов (app +
   tunnel extension) — поиск `ondemand-migration:`, `tunnel-watchdog:`,
   `tunnel-controller:` категорий.
5. Подготовить ProtonVPN или Mullvad для Сценария F (other-VPN fight-back).
6. Подготовить второй Wi-Fi для Сценария D (network switching).

## UAT decision criteria (Round 2 B-10)

**Hard blockers (MUST pass):** A, C, E, F, G, I.
**Non-blocking (may proceed with notes):** B, D, H.

- All 6 hard blockers PASS + 0–3 non-blocking failures → `uat passed`; resume Task 3a/3b/3c cleanup.
- Any hard blocker FAIL → STOP; do not proceed Task 3; escalate to user; rollback OR fix-forward Task 1.
- All 9 PASS → ideal; proceed cleanup with confidence.

## Files touched (Task 1)

| File | Status | Notes |
|------|--------|-------|
| `BBTB/App/iOSApp/BBTB_iOSApp.swift` | modified | OnDemandMigrationTask + TunnelWatchdog wiring |
| `BBTB/App/macOSApp/BBTB_macOSApp.swift` | modified | OnDemandMigrationTask + TunnelWatchdog wiring |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` | modified | Additive: cachedManager, watchdog, applyCurrentStateToCachedManager, handleWake guards |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` | modified | .connecting banner case + NEVPNStatusDidChange observer |
| `BBTB/Packages/Localization/Sources/Localization/L10n.swift` | modified | bannerConnecting key |
| `BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings` | modified | banner.connecting ru/en entries |
| `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/TunnelControllerStateTests.swift` | modified | 2 tests opt into cachedManagerEnabledOverrideForTest seam |

## What's NOT in Task 1 (orchestrator owns)

- STATE.md / ROADMAP.md updates — orchestrator handles.
- Final SUMMARY.md (`06C-04-SUMMARY.md`) — Task 3c writes after cleanup completes.
- Device UAT execution — Task 2 (human-verify checkpoint).
