# Phase 6c: On-demand Reconnect Migration - Context

**Gathered:** 2026-05-13
**Status:** Ready for planning

<domain>
## Phase Boundary

Заменить custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange observer + NetworkReachability NWPathMonitor triggers + ручные флаги userIntendedConnected/connectInProgress/manualDisconnectInProgress) на **iOS-нативный механизм** `isOnDemandEnabled` + `NEOnDemandRule*`.

**Это remediation-фаза, не feature-добавка.** Все Phase 6 success criteria (Wi-Fi↔LTE handoff, wake-from-sleep, failover при падении сервера) сохраняются. Поведенческий контракт остаётся идентичным с точки зрения пользователя.

**Что фикс уносит by design:**
- Race conditions из actor reentrance (phantom reconnect на fresh install, post-import)
- XPC storm на iOS 26 (EXC_RESOURCE/PORT_SPACE краш)
- Fighting с другими VPN-приложениями (iOS сама управляет приоритетом)
- ~570 строк хрупкой custom-логики (ReconnectStateMachine + NetworkReachability + большая часть TunnelController observer pipeline)

**Что фаза закладывает на будущее:**
- Фундамент для Phase 8 Rules Engine (per-SSID, per-domain rules через `NEEvaluateConnectionRule`)
- Фундамент для Phase 10 Advanced Settings («подключаться только в публичных Wi-Fi», etc.)
- Apple-managed wake/sleep/network-change — мы перестаём это поддерживать сами

</domain>

<decisions>
## Implementation Decisions

### Apple-механизм конфигурации

- **D-01:** Использовать **`NEEvaluateConnectionRule`** с самого начала, не простой `NEOnDemandRuleConnect`. На старте Phase 6c одно правило: «любой interface available → action = connect». Архитектурно: массив правил с `connectionAction = .connect`. Это позволяет Phase 8 Rules Engine добавлять кастомные правила пользователя в тот же массив без изменения API.
- **D-02:** Правила хранятся на уровне `NETunnelProviderManager.onDemandRules`. `isOnDemandEnabled` — toggle всей системы (управляется пользовательской настройкой, см D-04).
- **D-03:** Single source of truth для правил — новый файл `OnDemandRulesBuilder.swift` в `MainScreenFeature`. Все callsites (`ConfigImporter.provisionTunnelProfile`, future toggle handlers) идут через него.

### User-facing toggle

- **D-04:** Добавить переключатель **«Автоматическое переподключение»** в Settings → новый раздел «Подключение». Default = **ON**.
- **D-05:** Persistence через UserDefaults ключ `app.bbtb.autoReconnectEnabled`. Аналогично существующему `app.bbtb.killSwitchEnabled` паттерну (`SettingsViewModel` + `handleUserDefaultsChange`).
- **D-06:** Toggle меняет `manager.isOnDemandEnabled` через `saveToPreferences` + `loadFromPreferences`. Применяется немедленно (не отложенно как KillSwitch). UI-баннер «Переподключитесь для применения» не нужен — toggle переключает уже работающий механизм.
- **D-07:** Раздел «Подключение» в Settings создаётся в Phase 6c с одним переключателем. Phase 10 добавит остальные connection-related settings в тот же раздел.

### Mid-session server failover

- **D-08:** Сохранить **узко-целевой watchdog observer** для сценария «сервер умер во время стабильной сессии». Реагирует ТОЛЬКО при условиях:
  - Туннель был `.connected` >= 30 секунд (stable session marker)
  - Статус упал в `.disconnected` (читается прямо из notification.object — без XPC, паттерн уже отработан в Phase 6 fix)
  - `manager.isEnabled == true` (наш профиль не был внешне переопределён другим VPN)
  - `userIntendedConnected == true` (пользователь не нажимал disconnect)
- **D-09:** Watchdog при срабатывании запускает уже существующий `SwiftDataFailoverProvider.nextServerAttempt()` — round-robin к следующему серверу. Apple's on-demand параллельно reconnect'ит к тому же — это нормально, наш swap manager config обгонит.
- **D-10:** **`ReconnectStateMachine` удаляется полностью** — её роль (3 attempts × exp backoff) забирает on-demand. Watchdog проще: одна попытка failover на следующий сервер при «сервер умер»; если failover failed → пользователь видит обрыв и тапает Connect сам.

### macOS wake handling

- **D-11:** **Гибридный подход**: основной механизм — on-demand (как iOS), плюс `NSWorkspace.didWakeNotification` observer как **backup nudge** для known macOS edge cases.
- **D-12:** Observer на macOS делает ОДНО действие при wake: `manager.connection.startVPNTunnel()` (idempotent — если on-demand уже сработал и туннель up, повторный start no-op). НЕТ XPC через `loadAllFromPreferences`, НЕТ status reading — cheap.
- **D-13:** Iiterates через `manager` сохранённый в actor (cached at startReachability). Wake observer работает только с этим reference.

### Cleanup of old code

- **D-14:** Удалить полностью: `ReconnectStateMachine.swift` (182 строки), `NetworkReachability.swift` actor (168 строк). Также все тесты `ReconnectStateMachineTests.swift`, `NetworkReachabilityTests.swift`.
- **D-15:** `TunnelController.swift` сократить примерно вдвое (618 → ~300 строк). Удалить: `handleStatusChange` recovery path, `triggerRecoveryIfNeeded`, `lastKnownStatus` cache, `userIntendedConnected`/`connectInProgress`/`manualDisconnectInProgress` флаги (часть из них может остаться для других целей — финализируется в плане).
- **D-16:** `FailoverProvider.swift` сохранить — он используется и для initial-connect failover (Wave 6), и для watchdog (D-09). Никаких изменений.
- **D-17:** Удалить статус-обработчики кроме narrow ones для UI status indicator (Banner). NEVPNStatusDidChange observer остаётся, но только обновляет `@Published` свойство для banner, не триггерит логику.

### Regression preservation

- **D-18:** Phase 6 success criteria 1, 2 (DNS/IPv6 leak tests) — не затронуты, отдельная подсистема.
- **D-19:** Phase 6 success criteria 3 (Wi-Fi↔LTE) — проверяется через on-demand `NEEvaluateConnectionRule` (interface change → re-evaluate → connect).
- **D-20:** Phase 6 success criteria 4 (wake) — iOS: on-demand; macOS: on-demand + wake observer backup (D-11).
- **D-21:** Phase 6 success criteria 5 (failover) — initial-connect через SwiftDataFailoverProvider (без изменений); mid-session через watchdog (D-08).
- **D-22:** Полный UAT smoke на iPhone iOS 26.5 ПЛЮС macOS после миграции — список регрессий собрать на planning.

### Test strategy

- **D-23:** Удалить `ReconnectStateMachineTests.swift`, `NetworkReachabilityTests.swift`, большую часть `TunnelControllerStateTests.swift`.
- **D-24:** Написать новые тесты по 3 категориям:
  1. `OnDemandRulesBuilderTests` — конфигурация правил, miграция между состояниями enabled/disabled
  2. `TunnelControllerTests` (новый) — connect/disconnect contract preservation, manager configuration assertions
  3. `WatchdogObserverTests` — only-fires-after-stable-session, manager.isEnabled gate, intent gate
- **D-25:** Сохранить `FailoverProviderTests` (актуальный) и тесты ConfigImporter.

### Claude's Discretion

- Точная структура `OnDemandRulesBuilder.swift` API (методы, наблюдаемость состояния) — определяется planner'ом.
- Расположение watchdog логики (внутри TunnelController vs отдельный actor) — определяется planner'ом.
- Конкретный wording «Автоматическое переподключение» в Settings — обсуждается через UI-spec при необходимости.
- Migration строй (one big PR vs пошагово) — определяется planner'ом, но рекомендуется по-фазно: сначала on-demand параллельно со старым; убрать старое после device-UAT.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Текущая реализация (что заменяется/сохраняется)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` — главный файл миграции. Сократится ~50%.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` — УДАЛЯЕТСЯ полностью.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift` — УДАЛЯЕТСЯ полностью (Apple's on-demand reads network state сама).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift` — СОХРАНЯЕТСЯ (initial-connect failover + watchdog mid-session failover).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1004-1029` — `DefaultTunnelProvisioner.provisionTunnelProfile` нужно расширить on-demand rules при сохранении конфига.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — backlink на TunnelController, banner-state observer; будет упрощено.
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/App/macOSApp/BBTB_macOSApp.swift` — wiring TunnelController на старте; `startReachability` заменяется на `setUp` или подобное.

### Prior phase context
- `.planning/phases/06-network-resilience/06-CONTEXT.md` — D-07 (custom auto-reconnect 3 attempts × exp backoff), D-08 (failover round-robin). **Эти решения заменяются Apple-механизмом**, но семантика поведения сохраняется.
- `.planning/phases/06-network-resilience/06-RESEARCH.md` — §5 macOS wake handshake, §14 Pitfalls 2/3/4/8/10. Pitfall 10 (wake handshake) — переходит в D-11 (hybrid).
- `.planning/phases/06-network-resilience/06-06-SUMMARY.md` — Wave 6 SwiftDataFailoverProvider description, сохраняется.

### Project-level decisions
- `.planning/PROJECT.md` — Core Value «один тап для VPN без разбирательства с протоколами». Auto-reconnect должен соответствовать этому: невидим, надёжен.
- `.planning/REQUIREMENTS.md` — NET-08..11 (auto-reconnect, failover, wake recovery). Все re-validated в Phase 6c.

### Memory entries (lessons from Phase 6 UAT)
- `feedback_nevpn_xpc_mach_port.md` — почему мы не делаем XPC в observer hot path. После Phase 6c этот класс багов уходит by design (нет observer hot path).
- `feedback_auto_reconnect_user_intent_guard.md` — userIntendedConnected паттерн. Останется ли в Phase 6c — решается планировщиком (в D-15 предложено убрать, но если watchdog requires — может остаться).

### Apple documentation (внешнее)
- `NETunnelProviderManager` — base manager class
- `NEEvaluateConnectionRule` — конкретный rule type который мы используем
- `NEOnDemandRuleInterfaceType` / `NEOnDemandRuleConnectionAction` — параметры правил
- `NEVPNManager.isOnDemandEnabled` — toggle всей системы
- WireGuard iOS reference: https://github.com/WireGuard/wireguard-apple/tree/master/Sources/WireGuardApp — pattern reference for on-demand wiring

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`SwiftDataFailoverProvider` (Wave 6)** — round-robin server rotation logic. Используется и для initial-connect (по существующему flow), и теперь для mid-session watchdog (D-09).
- **`ReconnectBanner` + `ReconnectBannerState`** — UI компонент остаётся. Источник состояния меняется: вместо state machine — на on-demand-status reading + watchdog events.
- **`UserIntentStore` (Phase 6 UAT fix)** — Sendable UserDefaults wrapper. Может быть переиспользован для `autoReconnectEnabled` persistence.
- **`SettingsViewModel.handleUserDefaultsChange`** — паттерн для observable settings. Используется для добавления Auto-reconnect toggle.
- **`KillSwitch.apply(to:enabled:)`** — show-by-example как применять boolean toggle к `NETunnelProviderProtocol`. Параллель для on-demand wiring.

### Established Patterns
- **Two-phase init для actor-actor циклов** (`feedback_failover_two_phase_init.md`) — паттерн A(stub) → B([weak A]) → A.setX(B). Может потребоваться для watchdog ↔ TunnelController если их разносим.
- **`NETunnelNetworkSettings.tunnelRemoteAddress` нужен валидный IP/hostname** (`feedback_netunnelnetworksettings_tunnelRemoteAddress.md`) — учитываем в provisionTunnelProfile.
- **OSLog subsystem `app.bbtb.client`** — все категории. Watchdog получит новую category `tunnel-watchdog`.

### Integration Points
- `ConfigImporter.provisionTunnelProfile` (для каждого протокола) — добавить on-demand rules при build manager configuration.
- `MainScreenViewModel.tunnel` — `TunnelControlling` protocol. Контракт `connect()`/`disconnect()` сохраняется, добавляется `setAutoReconnect(_:Bool)`.
- `SettingsViewModel` — добавить `autoReconnectEnabled` published property.
- `MainScreenView` — нет изменений (banner state уже observable).

</code_context>

<specifics>
## Specific Ideas

- **WireGuard iOS** упоминался как эталонная реализация. Их `wireguard-apple` репозиторий — главный source-of-truth для on-demand wiring pattern. Особенно интересен `WireGuardApp/Sources/WireGuardApp/Tunnel/TunnelsManager.swift` (если структура совпадает).
- **«Auto-reconnect»** — финальное русское наименование toggle в Settings: предложение **«Автоматическое переподключение»**. Описание: «Восстанавливать соединение при смене сети или после сна».
- Раздел в Settings: **«Подключение»** (новый).
- **TunnelController после Phase 6c должен быть простой**: connect, disconnect, setAutoReconnect, observe-status-for-UI. Без actor reentrance gymnastics.

</specifics>

<deferred>
## Deferred Ideas

- **Per-SSID rules** («Подключаться только в незнакомых Wi-Fi») — Phase 8 Rules Engine. Архитектура `NEEvaluateConnectionRule` уже к этому готова в Phase 6c.
- **Per-domain trusted networks** («Не включать VPN дома») — Phase 8 Rules Engine.
- **Per-app VPN routing** (только Telegram через тоннель) — Phase 8 Split tunneling. Использует `NEAppRule` поверх `NETunnelProviderManager` — совместимо с on-demand.
- **Extension-level server rotation** (вариант 3 mid-session failover) — Phase 7+ когда будет полноценный protocol-engine с in-extension state. Сейчас watchdog observer проще и достаточно.
- **«Always-on VPN»** в виде первоклассного UX-выбора (как у Mullvad) — Phase 10 Advanced settings. Технически уже работает в Phase 6c через `isOnDemandEnabled = true` + базовое правило.

</deferred>

---

*Phase: 6c-on-demand-migration*
*Context gathered: 2026-05-13*
