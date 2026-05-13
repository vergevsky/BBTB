# Phase 6c: On-demand Reconnect Migration — Research

**Researched:** 2026-05-13
**Domain:** Apple NetworkExtension on-demand VPN configuration; replacement of custom auto-reconnect machinery with iOS/macOS-native mechanism
**Confidence:** HIGH (Apple-documented API + WireGuard reference impl + Apple Developer Forums staff guidance)

## Summary

Phase 6c заменяет custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange observer-driven recovery + NWPathMonitor triggers + три bool-флага intent-tracking) на нативный механизм Apple `NETunnelProviderManager.isOnDemandEnabled = true` + `onDemandRules: [NEOnDemandRule]`. Это remediation-фаза с **сохранением поведенческого контракта** для пользователя — все NET-08..11 success criteria выполняются по тем же признакам, но через Apple's evaluation loop вместо нашего observer pipeline. By design уходят 4 класса багов: race conditions из actor reentrance, XPC storm на iOS 26 (EXC_RESOURCE/PORT_SPACE), фантомные reconnect'ы на fresh install / post-import, конкуренция с другими VPN-приложениями.

WireGuard's `wireguard-apple` reference implementation подтверждает паттерн: они используют `NEOnDemandRuleConnect(interfaceType: .any)` для простого "всегда подключаться" сценария (НЕ `NEEvaluateConnectionRule` — последний требует non-empty `matchDomains` и применяется только для domain-based правил). Это **расхождение с CONTEXT.md D-01**, который декларирует `NEEvaluateConnectionRule` как стартовый rule type. См. секцию "Open Questions" — рекомендую использовать `NEOnDemandRuleConnect` для Phase 6c с тем же архитектурным фундаментом (rules-builder), который расширяется на `NEOnDemandRuleEvaluateConnection` в Phase 8 без breaking API change.

macOS на on-demand-only не надёжен после wake: Apple staff confirms (Apple Developer Forums thread/688021), что VPN transport может не reconnect после wake, и рекомендует **manual lifecycle management** дополнительно к on-demand. CONTEXT.md D-11 уже фиксирует hybrid-подход: основной механизм on-demand плюс `NSWorkspace.didWakeNotification` observer как backup. Watchdog для mid-session server failover (D-08) сохраняем — single observer без XPC, читающий статус из `notification.object`.

**Primary recommendation:** Создать `OnDemandRulesBuilder.swift` в `MainScreenFeature` — single source of truth. Wave 0 — пишем builder + новые тесты. Wave 1 — `ConfigImporter.provisionTunnelProfile` пишет правила и `isOnDemandEnabled` в новый/существующий manager. Wave 2 — параллельный run (старый код жив, новые правила пишутся, но `isOnDemandEnabled = false` дефолтно). Wave 3 — device UAT 6 сценариев (Wi-Fi↔LTE, sleep iOS/macOS, server kill, manual disconnect, app-switch, toggle off live). Wave 4 — finalize: delete ReconnectStateMachine + NetworkReachability + ~50% TunnelController; flip toggle default ON; ship watchdog + macOS wake observer backup. Этот порядок даёт rollback safety: если UAT обнаруживает регрессию, мы flip default OFF и старый код тушит пожар.

## Project Constraints (from CLAUDE.md)

| Constraint | Source | Impact на Phase 6c |
|------------|--------|--------------------|
| Russian UI / English code | CLAUDE.md «Rules» | Toggle label "Автоматическое переподключение" в локализуемых строках; имена символов в коде на английском |
| Quality over speed | CLAUDE.md «Rules» | Парallel-run migration (Wave 2 → 4) обязателен; нельзя выкинуть старый код одним PR |
| Scalability prioritized | CLAUDE.md «Rules» | `OnDemandRulesBuilder` API должен поддерживать future Phase 8 SSID/domain rules без рефакторинга |
| User non-programmer | CLAUDE.md «Rules» | Toggle с понятным footer'ом «Восстанавливать соединение при смене сети или после сна» |
| Wiki sync after decisions | CLAUDE.md GSD section | Phase 6c должен закрыться wiki entry о замене custom-reconnect → on-demand; обновить security-gaps.md если есть security implications |
| Wiki в `raw/` неизменна | CLAUDE.md «Rules» | Не применимо |
| App Group `group.app.bbtb.shared`, team `UAN8W9Q82U` | `.planning/config.json` | Bundle IDs: `app.bbtb.client.ios.tunnel`, `app.bbtb.client.macos.tunnel` — не меняются |
| `.planning/config.json` workflow.nyquist_validation = (absent) | `.planning/config.json` | Validation Architecture section требуется |
| `.planning/config.json` granularity = fine | `.planning/config.json` | Тонкие waves (4-5 шт), fine-grained tasks |

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Apple-механизм конфигурации:**
- **D-01:** Использовать **`NEEvaluateConnectionRule`** с самого начала, не простой `NEOnDemandRuleConnect`. На старте Phase 6c одно правило: «любой interface available → action = connect». Архитектурно: массив правил с `connectionAction = .connect`. Это позволяет Phase 8 Rules Engine добавлять кастомные правила пользователя в тот же массив без изменения API.
- **D-02:** Правила хранятся на уровне `NETunnelProviderManager.onDemandRules`. `isOnDemandEnabled` — toggle всей системы (управляется пользовательской настройкой, см D-04).
- **D-03:** Single source of truth для правил — новый файл `OnDemandRulesBuilder.swift` в `MainScreenFeature`. Все callsites (`ConfigImporter.provisionTunnelProfile`, future toggle handlers) идут через него.

**User-facing toggle:**
- **D-04:** Добавить переключатель **«Автоматическое переподключение»** в Settings → новый раздел «Подключение». Default = **ON**.
- **D-05:** Persistence через UserDefaults ключ `app.bbtb.autoReconnectEnabled`. Аналогично существующему `app.bbtb.killSwitchEnabled` паттерну (`SettingsViewModel` + `handleUserDefaultsChange`).
- **D-06:** Toggle меняет `manager.isOnDemandEnabled` через `saveToPreferences` + `loadFromPreferences`. Применяется немедленно (не отложенно как KillSwitch). UI-баннер «Переподключитесь для применения» не нужен — toggle переключает уже работающий механизм.
- **D-07:** Раздел «Подключение» в Settings создаётся в Phase 6c с одним переключателем. Phase 10 добавит остальные connection-related settings в тот же раздел.

**Mid-session server failover:**
- **D-08:** Сохранить **узко-целевой watchdog observer** для сценария «сервер умер во время стабильной сессии». Реагирует ТОЛЬКО при условиях:
  - Туннель был `.connected` >= 30 секунд (stable session marker)
  - Статус упал в `.disconnected` (читается прямо из notification.object — без XPC, паттерн уже отработан в Phase 6 fix)
  - `manager.isEnabled == true` (наш профиль не был внешне переопределён другим VPN)
  - `userIntendedConnected == true` (пользователь не нажимал disconnect)
- **D-09:** Watchdog при срабатывании запускает уже существующий `SwiftDataFailoverProvider.nextServerAttempt()` — round-robin к следующему серверу. Apple's on-demand параллельно reconnect'ит к тому же — это нормально, наш swap manager config обгонит.
- **D-10:** **`ReconnectStateMachine` удаляется полностью** — её роль (3 attempts × exp backoff) забирает on-demand. Watchdog проще: одна попытка failover на следующий сервер при «сервер умер»; если failover failed → пользователь видит обрыв и тапает Connect сам.

**macOS wake handling:**
- **D-11:** **Гибридный подход**: основной механизм — on-demand (как iOS), плюс `NSWorkspace.didWakeNotification` observer как **backup nudge** для known macOS edge cases.
- **D-12:** Observer на macOS делает ОДНО действие при wake: `manager.connection.startVPNTunnel()` (idempotent — если on-demand уже сработал и туннель up, повторный start no-op). НЕТ XPC через `loadAllFromPreferences`, НЕТ status reading — cheap.
- **D-13:** Iterates через `manager` сохранённый в actor (cached at startReachability). Wake observer работает только с этим reference.

**Cleanup of old code:**
- **D-14:** Удалить полностью: `ReconnectStateMachine.swift` (182 строки), `NetworkReachability.swift` actor (168 строк). Также все тесты `ReconnectStateMachineTests.swift`, `NetworkReachabilityTests.swift`.
- **D-15:** `TunnelController.swift` сократить примерно вдвое (618 → ~300 строк). Удалить: `handleStatusChange` recovery path, `triggerRecoveryIfNeeded`, `lastKnownStatus` cache, `userIntendedConnected`/`connectInProgress`/`manualDisconnectInProgress` флаги (часть из них может остаться для других целей — финализируется в плане).
- **D-16:** `FailoverProvider.swift` сохранить — он используется и для initial-connect failover (Wave 6), и для watchdog (D-09). Никаких изменений.
- **D-17:** Удалить статус-обработчики кроме narrow ones для UI status indicator (Banner). NEVPNStatusDidChange observer остаётся, но только обновляет `@Published` свойство для banner, не триггерит логику.

**Regression preservation:**
- **D-18:** Phase 6 success criteria 1, 2 (DNS/IPv6 leak tests) — не затронуты, отдельная подсистема.
- **D-19:** Phase 6 success criteria 3 (Wi-Fi↔LTE) — проверяется через on-demand `NEEvaluateConnectionRule` (interface change → re-evaluate → connect).
- **D-20:** Phase 6 success criteria 4 (wake) — iOS: on-demand; macOS: on-demand + wake observer backup (D-11).
- **D-21:** Phase 6 success criteria 5 (failover) — initial-connect через SwiftDataFailoverProvider (без изменений); mid-session через watchdog (D-08).
- **D-22:** Полный UAT smoke на iPhone iOS 26.5 ПЛЮС macOS после миграции — список регрессий собрать на planning.

**Test strategy:**
- **D-23:** Удалить `ReconnectStateMachineTests.swift`, `NetworkReachabilityTests.swift`, большую часть `TunnelControllerStateTests.swift`.
- **D-24:** Написать новые тесты по 3 категориям:
  1. `OnDemandRulesBuilderTests` — конфигурация правил, миграция между состояниями enabled/disabled
  2. `TunnelControllerTests` (новый) — connect/disconnect contract preservation, manager configuration assertions
  3. `WatchdogObserverTests` — only-fires-after-stable-session, manager.isEnabled gate, intent gate
- **D-25:** Сохранить `FailoverProviderTests` (актуальный) и тесты ConfigImporter.

### Claude's Discretion

- Точная структура `OnDemandRulesBuilder.swift` API (методы, наблюдаемость состояния) — определяется planner'ом.
- Расположение watchdog логики (внутри TunnelController vs отдельный actor) — определяется planner'ом.
- Конкретный wording «Автоматическое переподключение» в Settings — обсуждается через UI-spec при необходимости.
- Migration строй (one big PR vs пошагово) — определяется planner'ом, но рекомендуется по-фазно: сначала on-demand параллельно со старым; убрать старое после device-UAT.

### Deferred Ideas (OUT OF SCOPE)

- **Per-SSID rules** («Подключаться только в незнакомых Wi-Fi») — Phase 8 Rules Engine. Архитектура `NEEvaluateConnectionRule` уже к этому готова в Phase 6c.
- **Per-domain trusted networks** («Не включать VPN дома») — Phase 8 Rules Engine.
- **Per-app VPN routing** (только Telegram через тоннель) — Phase 8 Split tunneling. Использует `NEAppRule` поверх `NETunnelProviderManager` — совместимо с on-demand.
- **Extension-level server rotation** (вариант 3 mid-session failover) — Phase 7+ когда будет полноценный protocol-engine с in-extension state. Сейчас watchdog observer проще и достаточно.
- **«Always-on VPN»** в виде первоклассного UX-выбора (как у Mullvad) — Phase 10 Advanced settings. Технически уже работает в Phase 6c через `isOnDemandEnabled = true` + базовое правило.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| NET-08 | Auto-reconnect при смене Wi-Fi ↔ LTE | iOS evaluates on-demand rules on path change automatically — `NEOnDemandRuleConnect(interfaceType: .any)` matches and re-establishes tunnel. См. §Architecture Patterns / §Code Examples. |
| NET-09 | Auto-reconnect после выхода из sleep | iOS: on-demand fires after network associates post-wake. macOS: on-demand + `NSWorkspace.didWakeNotification` observer fallback (D-11) per Apple staff guidance on Apple Developer Forums thread/688021. |
| NET-10 | Auto-reconnect при смене IP | iOS evaluates rules when network reachability changes — same mechanism as NET-08. |
| NET-11 | Failover на другой сервер при падении | Phase 6 SwiftDataFailoverProvider (preserved) для initial-connect; **new** watchdog observer (D-08) для mid-session — реагирует на `.connected → .disconnected` при stable-session > 30s. Apple's on-demand паралельно пытается reconnect — наш swap manager config обгонит (D-09). |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Auto-reconnect trigger evaluation (path change / wake / IP change) | OS (NetworkExtension daemon) | — | We delegate to Apple's evaluation loop. This is the entire point of Phase 6c: stop owning this code. |
| On-demand rules configuration | Main App (`OnDemandRulesBuilder` + `ConfigImporter.provisionTunnelProfile`) | — | Rules are persisted in `NETunnelProviderManager`. Builder is single source of truth so Phase 8 can extend without rewriting callsites. |
| Auto-reconnect on/off toggle | Main App (`SettingsViewModel` → UserDefaults) | OS (reads `isOnDemandEnabled`) | UI lives in Settings; flag mirrored to `manager.isOnDemandEnabled` via `saveToPreferences`. |
| Mid-session server failover detection | Main App (Watchdog observer) | — | OS only knows "tunnel up/down"; can't know "sing-box reports the upstream sing-box server is dead". Watchdog reads `.disconnected` after stable session and runs `SwiftDataFailoverProvider` to swap config. |
| macOS wake handling (backup nudge) | Main App (`NSWorkspace.didWakeNotification` observer) | OS (on-demand primary) | Apple staff (Forums thread/688021) confirms on-demand may not re-trigger reliably after wake on macOS; backup nudge calls `startVPNTunnel()` idempotently. |
| iOS wake / foreground handling | OS (on-demand) | — | iOS's on-demand path change evaluation already covers wake. No app-side observer needed. |
| Banner state (UI feedback during reconnect) | Main App (`MainScreenViewModel`) | — | NEVPNStatusDidChange observer remains, but only feeds `@Published` property — no logic. |
| Tunnel start / stop (manual connect / disconnect) | Main App (`TunnelController.connect()` / `disconnect()`) | OS (NetworkExtension) | Contract preserved verbatim — same polling loops, same timeouts. |
| Persistent intent (user wants tunnel on) | OS (`isOnDemandEnabled` flag IS the intent now) | Main App (UserIntentStore — to be evaluated for deletion) | Apple's on-demand semantics: `isOnDemandEnabled = true` means "user wants tunnel". Our `userIntendedConnected` flag becomes redundant for the auto-reconnect gate. |

## Runtime State Inventory

> Phase 6c is a refactor/replacement phase. Runtime state inventory mandatory.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | UserDefaults key `app.bbtb.userIntendedConnected` (from Phase 6 UAT fix) — bool persisted across launches; `app.bbtb.killSwitchEnabled` — unchanged | Code edit: remove `UserIntentStore` if planner decides `userIntendedConnected` is redundant after migration (D-15 hints "может остаться для других целей"). If kept, **no data migration needed** — existing stored bool stays valid semantic. If removed, optional cleanup task: delete key on first launch of Phase 6c version. |
| **Live service config** | `NETunnelProviderManager` saved preference — currently has `isOnDemandEnabled` either unset or false (Phase 6 never set it); `onDemandRules` likely nil | **Critical data migration**: на первый запуск Phase 6c при наличии существующего manager Run `provisionTunnelProfile` (или равноценный update path) чтобы записать новые rules + `isOnDemandEnabled` per current toggle. Без этого пользователи с уже установленным профилем не получат on-demand до следующего import. |
| **OS-registered state** | NEVPNStatusDidChange observer (per-process, system-managed); macOS `NSWorkspace.didWakeNotification` observer | Code edit: remove old observer's recovery-path branches; add new wake observer (macOS) per D-11. iOS wake observer stays only for `handleForeground()` no-op or fully deleted. |
| **Secrets / env vars** | Keychain `app.bbtb.client.tunnel.config` items — unchanged; no on-demand-related secrets | None — no migration. |
| **Build artifacts / installed packages** | None — pure Swift code change, no new SPM dependencies, no xcframework changes | None. |

**Critical migration step (must be explicit task in plan):** Existing installs after Phase 6c upgrade may have a manager with `isOnDemandEnabled = false` and `onDemandRules = nil`. On first launch of Phase 6c, app code must detect this and patch the manager (load → set rules + isOnDemandEnabled → save → load). Otherwise UAT fails: «обновился — auto-reconnect не работает пока не переимпортирую конфиг».

## Standard Stack

### Core

| Library / API | Version | Purpose | Why Standard |
|---------------|---------|---------|--------------|
| `NetworkExtension` framework | iOS 18+ / macOS 15+ (project min) | `NETunnelProviderManager`, `NEOnDemandRule*` hierarchy, `isOnDemandEnabled` | [VERIFIED: Apple framework — already used throughout codebase] |
| `NEOnDemandRuleConnect` | iOS 9+ / macOS 10.11+ | Simple "connect on matching interface" rule. `interfaceTypeMatch: .any` для D-01 «любой interface available → connect». | [CITED: developer.apple.com — used by WireGuard reference (`ActivateOnDemandOption.swift:35`)] |
| `NEOnDemandRuleDisconnect` | iOS 9+ / macOS 10.11+ | Counter-rule to filter out interfaces if needed (Phase 8 use case; not Phase 6c). | [CITED: developer.apple.com — used by WireGuard for `.wiFiInterfaceOnly` mode] |
| `NEOnDemandRuleEvaluateConnection` + `NEEvaluateConnectionRule` | iOS 8+ / macOS 10.11+ | Domain-based rules. Requires non-empty `matchDomains: [String]`. Use this in **Phase 8**, not Phase 6c. | [CITED: developer.apple.com — confirmed in Apple Developer Forums thread/695899 Apple staff response] |
| `NSWorkspace.didWakeNotification` | macOS 10+ | Backup wake observer (D-11) — fires on `NSWorkspace.shared.notificationCenter`, NOT `.default` | [CITED: developer.apple.com/documentation/appkit/nsworkspace/didwakenotification — Phase 6 §5 already proven] |
| `NEVPNConnection.status` (direct read from `notification.object`) | iOS 9+ / macOS 10.11+ | Watchdog observer reads status WITHOUT XPC — proven Phase 6 UAT fix pattern | [VERIFIED: `feedback_nevpn_xpc_mach_port.md` + current `TunnelController.swift:389-394` implementation] |
| `UserDefaults` + `@AppStorage` | iOS 18 / macOS 15 | Persistence of `app.bbtb.autoReconnectEnabled` toggle (same pattern as `killSwitchEnabled`) | [VERIFIED: `SettingsViewModel.swift:16` precedent] |

### Supporting

| File / Class | Purpose | Where Used |
|--------------|---------|------------|
| `KillSwitch.apply(to:enabled:)` (existing) | Reference pattern for "apply boolean toggle to NETunnelProviderProtocol" | Mirror pattern for on-demand: a static method that takes `manager` and writes rules + `isOnDemandEnabled`. |
| `UserDefaults.standard.object(forKey:) as? Bool ?? <default>` | Pattern for reading toggle with default. Returning **default ON** when key absent (D-04) | `KillSwitch` already uses `?? true`; on-demand will use `?? true` per D-04. |
| `SwiftDataFailoverProvider` (Phase 6 Wave 6) | Round-robin server rotation — used by watchdog (D-09) | Already proven, no changes needed. |
| `ConfigProvisioning` protocol | Existing seam — `failoverProvider` calls `provisioner.provisionTunnelProfile(for:)` | Watchdog reuses same call path; no new protocol needed. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `NEOnDemandRuleConnect(interfaceType: .any)` (recommended for D-01) | `NEEvaluateConnectionRule(matchDomains: ["*"], andAction: .connectIfNeeded)` (what CONTEXT.md D-01 literally says) | **CONTEXT.md D-01 misnames the API**: `NEEvaluateConnectionRule` requires non-empty `matchDomains` per Apple staff (forum thread/81249) and was designed for domain-based filtering. Using it for "always connect on any interface" is unidiomatic — WireGuard, sing-box-for-apple, and SimpleTunnel all use `NEOnDemandRuleConnect`. Phase 8 use case (per-domain) IS the right place for `NEEvaluateConnectionRule`. Recommendation: use `NEOnDemandRuleConnect(interfaceType: .any)` in Phase 6c; D-01's stated intent (Phase 8 extensibility) preserved via builder API. |
| Custom retry state machine (current implementation) | Apple's `isOnDemandEnabled` + rules array | Custom: explicit control, debuggable, but couples to NEVPNStatusDidChange firehose → iOS 26 EXC_RESOURCE crash. Apple-native: opaque, but battle-tested, no XPC churn from our code, future-proof for SSID/domain rules. **Phase 6c chooses Apple-native.** |
| `disconnectOnSleep = true` | Keep `disconnectOnSleep = false` (current setting in KillSwitch.swift:43) | Setting `true` triggers sleep→connecting→sleep loop per Apple staff (forum thread/688021 known issue r. 74473825). Keep `false` and let on-demand handle wake. |
| Extension-level reconnect (`reasserting = true`) | Main-app watchdog observer | Extension can be killed by iOS on path changes per Phase 6 RESEARCH §10. Watchdog in main app survives. Defer extension-level to Phase 7+ libbox status subscription. |

**Installation:** No new packages. Uses already-imported `NetworkExtension` + `AppKit` (macOS) frameworks.

**Version verification:**
```bash
# Check NetworkExtension framework availability (built into SDK):
xcrun --show-sdk-platform-version --sdk iphoneos
# iOS SDK 26.x ships with NetworkExtension on-demand APIs unchanged from iOS 18
```
- `NEOnDemandRuleConnect`: available since iOS 9.0 (Apple docs, stable)
- `isOnDemandEnabled`: NEVPNManager property, stable since iOS 8
- No deprecation notices for on-demand APIs in iOS 26 release notes (verified via Apple Developer release notes; no on-demand changes documented in iOS 26.0-26.5 release notes)

## Architecture Patterns

### System Architecture Diagram

```
USER ACTION                        ←→     OS (NetworkExtension daemon)              ←→     APP STATE
  │                                        │                                               │
  ▼                                        │                                               ▼
Settings toggle                            │                                       SettingsViewModel.autoReconnectEnabled
  «Авто-переподключение»  ON/OFF           │                                       (@AppStorage app.bbtb.autoReconnectEnabled)
  │                                        │                                               │
  ▼                                        │                                               │
saveToPreferences() with                   │                                               │
isOnDemandEnabled = autoReconnectEnabled   │                                               │
  │                                        │                                               │
  └──→  NETunnelProviderManager  ──→  Apple's on-demand evaluation loop                    │
                                            │  (network change / wake / app launch)        │
                                            │                                               │
                                            ▼                                               │
                                  Match onDemandRules:                                      │
                                  [NEOnDemandRuleConnect(interfaceType: .any)]              │
                                            │                                               │
                                            ▼ (matches → action=connect)                    │
                                  OS starts tunnel transparently                            │
                                            │                                               │
                                            ▼                                               │
                                  NEVPNStatus: connecting → connected                       │
                                            │                                               │
                                            ▼                                               │
        ┌────  NEVPNStatusDidChange notification                                            │
        │       (observer reads status from notification.object — NO XPC)                   │
        ▼                                                                                   │
TunnelController status                                                                     │
observer updates                                                                            │
@Published reconnectState  ──────────────────────────────────────────────→  MainScreen banner
        │
        │  Mid-session watchdog path (D-08):
        │  if was stable-connected >= 30s AND status drops to .disconnected
        │  AND manager.isEnabled == true AND userIntendedConnected:
        │
        ▼
SwiftDataFailoverProvider.nextServerAttempt()
        │  (Phase 6 Wave 6, preserved)
        ▼
ConfigImporter.provisionTunnelProfile(for: nextServerID)
        │
        ▼
manager.saveToPreferences() — OS sees new config + still isOnDemandEnabled = true
        │
        └──→ Apple's on-demand re-evaluates → tunnel comes up with new server

────────────────────────────────────────────────────────────────────────────────

macOS-only WAKE PATH (D-11 backup):
NSWorkspace.didWakeNotification
        │
        ▼
TunnelController.handleWake()  →  manager.connection.startVPNTunnel()  (idempotent — no-op if tunnel already up)
```

### Recommended Project Structure

```
BBTB/Packages/AppFeatures/Sources/MainScreenFeature/
├── TunnelController.swift              # REDUCED from 618 → ~300 lines
├── OnDemandRulesBuilder.swift          # NEW — single source of truth for on-demand rules
├── TunnelWatchdog.swift                # NEW (or inlined in TunnelController per planner choice) — mid-session failover observer
├── FailoverProvider.swift              # PRESERVED — used by watchdog
├── ConfigImporter.swift                # MODIFIED — provisionTunnelProfile applies on-demand rules
├── MainScreenViewModel.swift           # SIMPLIFIED — banner observer only, no recovery wiring
├── ReconnectStateMachine.swift         # DELETED
├── NetworkReachability.swift           # DELETED
└── ...

BBTB/Packages/AppFeatures/Sources/SettingsFeature/
├── SettingsView.swift                  # MODIFIED — new «Подключение» section with toggle
├── SettingsViewModel.swift             # MODIFIED — add @AppStorage autoReconnectEnabled
└── ConnectionSettingsToggle.swift      # NEW — реусабельный component (если planner решит выделить)

BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/
├── OnDemandRulesBuilderTests.swift     # NEW — D-24 category 1
├── TunnelControllerTests.swift         # NEW (replaces TunnelControllerStateTests) — D-24 category 2
├── TunnelWatchdogTests.swift           # NEW — D-24 category 3
├── FailoverProviderTests.swift         # PRESERVED
├── ConfigImporter*.swift               # PRESERVED
├── ReconnectStateMachineTests.swift    # DELETED
├── NetworkReachabilityTests.swift      # DELETED
└── TunnelControllerStateTests.swift    # DELETED (replaced by TunnelControllerTests)
```

### Pattern 1: OnDemandRulesBuilder API

**What:** Static enum-based namespace (mirroring `KillSwitch` pattern) that takes `NETunnelProviderProtocol` (или manager) и применяет on-demand rules согласно текущему пользовательскому toggle. Single callsite — every place that configures a manager (currently `DefaultTunnelProvisioner.provisionTunnelProfile`, и future toggle handler в `SettingsViewModel`).

**When to use:** Каждый раз когда `NETunnelProviderManager` создаётся или обновляется. Аналог KillSwitch.apply.

**Example (recommended shape — exact API decided by planner):**
```swift
// Source: NEW file BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnDemandRulesBuilder.swift
// Pattern mirrors KillSwitch.apply in BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift

import Foundation
import NetworkExtension

/// Phase 6c — single source of truth for `NETunnelProviderManager.onDemandRules`.
///
/// Phase 6c ships ONE rule: "any interface → connect". This is the equivalent of
/// «всегда вкл VPN, когда есть сеть». Phase 8 Rules Engine will extend this builder
/// to emit additional rules for SSID matching, domain matching, etc. — без изменения
/// API callsites: `apply(to:autoReconnectEnabled:)` will keep the same signature.
public enum OnDemandRulesBuilder {

    /// Apply on-demand configuration to a `NETunnelProviderManager`.
    /// Caller is responsible for invoking `saveToPreferences()` afterwards.
    ///
    /// - Parameters:
    ///   - manager: live `NETunnelProviderManager` ready to receive config updates.
    ///   - autoReconnectEnabled: пользовательский toggle. Когда `true` —
    ///     `isOnDemandEnabled = true` плюс rules устанавливаются. Когда `false` —
    ///     `isOnDemandEnabled = false`, rules **сохраняются** (чтобы re-enable был cheap).
    public static func apply(
        to manager: NETunnelProviderManager,
        autoReconnectEnabled: Bool
    ) {
        manager.onDemandRules = buildRules()
        manager.isOnDemandEnabled = autoReconnectEnabled
    }

    /// Phase 6c — единственное правило «любой interface → connect».
    /// Phase 8 расширит: дополнительные правила перед этим (first-match-wins evaluation).
    private static func buildRules() -> [NEOnDemandRule] {
        let connectRule = NEOnDemandRuleConnect()
        connectRule.interfaceTypeMatch = .any
        return [connectRule]
    }

    /// Phase 6c — convenience reader, mirror to UserDefaults pattern (KillSwitch).
    public static func loadAutoReconnectEnabled(
        userDefaults: UserDefaults = .standard,
        key: String = "app.bbtb.autoReconnectEnabled"
    ) -> Bool {
        // Default ON per D-04. `object(forKey:)` returns nil if never set; bool(...) returns false.
        // Using `as? Bool ?? true` preserves the «default ON» invariant for fresh installs.
        userDefaults.object(forKey: key) as? Bool ?? true
    }
}
```

**Note on D-01 wording:** CONTEXT.md says «использовать `NEEvaluateConnectionRule` с самого начала» с массивом правил `connectionAction = .connect`. По Apple API: `NEEvaluateConnectionRule` живёт ВНУТРИ `NEOnDemandRuleEvaluateConnection.connectionRules: [NEEvaluateConnectionRule]` — это nested структура для domain-based правил. Простое «любой interface → connect» — это `NEOnDemandRuleConnect`. WireGuard, sing-box-for-apple, и Apple's SimpleTunnel sample используют именно `NEOnDemandRuleConnect` для аналогичного use case. **Расхождение по терминологии — но архитектурное намерение D-01 (extensibility для Phase 8) выполняется идентично с `NEOnDemandRuleConnect`**: Phase 8 добавит в массив `NEOnDemandRuleEvaluateConnection` правила перед текущим `NEOnDemandRuleConnect` (first-match-wins evaluation). См. **Open Question 1** ниже.

### Pattern 2: Toggle live-apply через handleUserDefaultsChange

**What:** SettingsViewModel observes UserDefaults change для `app.bbtb.autoReconnectEnabled`. On change — fire side effect: load manager, apply new on-demand state, save. Аналог `handleUserDefaultsChange` для `killSwitchEnabled` уже существует в проекте.

**When to use:** Когда пользователь тапает toggle в Settings. D-06 — апликация немедленная.

**Example:**
```swift
// Source: BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift (MODIFIED)

@AppStorage("app.bbtb.autoReconnectEnabled") public var autoReconnectEnabled: Bool = true {
    didSet {
        // @AppStorage already writes; trigger live-apply.
        Task { await applyAutoReconnectToManager() }
    }
}

private func applyAutoReconnectToManager() async {
    do {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else { return }  // no profile → nothing to apply
        OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: autoReconnectEnabled)
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()  // RESEARCH 06 §9.1 — mandatory after save
    } catch {
        // Log and surface to UI; toggle stays in user-chosen state, OS just doesn't apply
        // until next provisionTunnelProfile.
    }
}
```

**Note:** D-06 says «применяется немедленно». Single XPC trip per toggle press — это OK; не observer hot path. Pattern is identical to KillSwitch toggle (which doesn't apply live — but D-06 explicitly diverges for на on-demand).

### Pattern 3: Watchdog observer (D-08)

**What:** Узко-целевой observer на `NEVPNStatusDidChange`, который реагирует ТОЛЬКО на «сервер умер во время стабильной сессии». Никакой XPC, никакой `loadAllFromPreferences()` в hot path — все условия проверяются по cached state + notification.object.

**When to use:** Detection: tunnel was `.connected` for >= 30s, then status drops to `.disconnected`. Trigger: `SwiftDataFailoverProvider.nextServerAttempt()` to swap to next server config. Apple's on-demand параллельно держит retry — наш swap обгонит, OS подхватит новый manager config.

**Example:**
```swift
// Source: NEW file BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelWatchdog.swift
// (or inlined inside TunnelController — planner choice per CONTEXT.md Claude's Discretion)

import Foundation
import NetworkExtension
import OSLog

public actor TunnelWatchdog {
    private weak var failoverProvider: (any FailoverProviding)?
    private let log = Logger(subsystem: "app.bbtb.client", category: "tunnel-watchdog")

    /// Set true after a `.connected` transition that held for 30s.
    private var stableSession: Bool = false
    private var stableSessionTask: Task<Void, Never>?

    /// Set true when user pressed Connect (used as intent gate).
    /// Cleared on user disconnect. Mirrors current `userIntendedConnected` semantics
    /// but locally scoped to watchdog logic.
    private var userIntent: Bool = false

    public init(failoverProvider: any FailoverProviding) {
        self.failoverProvider = failoverProvider
    }

    /// Called from NEVPNStatusDidChange observer (which reads status from notification.object).
    /// `manager` is the cached reference stored at startWatchdog time — NOT re-fetched here.
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async {
        switch status {
        case .connected:
            // Schedule "stable session reached after 30s" marker.
            stableSessionTask?.cancel()
            stableSessionTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                if !Task.isCancelled {
                    await self?.markStable()
                }
            }
        case .disconnected:
            // Watchdog fires ONLY if: stable session AND user intent AND profile not externally disabled.
            if stableSession && userIntent && managerEnabled {
                log.notice("watchdog: stable-session disconnect detected — running failover")
                await failoverProvider?.nextServerAttempt().map { next in
                    Task { try? await next.attempt() }
                }
            }
            // Reset stable session marker — any new .connected re-arms.
            stableSession = false
            stableSessionTask?.cancel()
        default:
            break
        }
    }

    private func markStable() { stableSession = true }

    public func setUserIntent(_ value: Bool) {
        userIntent = value
        if !value {
            stableSession = false
            stableSessionTask?.cancel()
        }
    }
}
```

**Why this is safe under iOS 26 XPC storm:** observer reads status from `notification.object` (sync property — proven Phase 6 fix). No `loadAllFromPreferences()` in hot path. Apple's on-demand handles transient disconnects (it'll retry); watchdog ONLY swaps server config when the disconnect persists past Apple's reconnect attempts AND was during a stable session. With Apple's evaluation handling the firehose, our observer sees substantially fewer events.

### Pattern 4: macOS wake observer backup (D-11)

**What:** `NSWorkspace.shared.notificationCenter.addObserver(forName: .NSWorkspaceDidWake)` — single observer that does ONE thing on wake: call `manager.connection.startVPNTunnel()`. Idempotent: если on-demand уже сработал и туннель up — `startVPNTunnel()` no-op (returns immediately). Если on-demand НЕ сработал по macOS-quirk — наш nudge поднимет туннель.

**When to use:** macOS only. Apple staff confirmed (Apple Developer Forums thread/688021) что VPN transport может не reconnect properly после wake.

**Example:**
```swift
// Source: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift (MODIFIED)
#if os(macOS)
private func installMacWakeObserver(manager: NETunnelProviderManager) {
    wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.didWakeNotification,
        object: nil,
        queue: nil
    ) { [weak manager] _ in
        // Idempotent nudge — startVPNTunnel() returns immediately if already up.
        try? manager?.connection.startVPNTunnel()
    }
}
#endif
```

**No `NWPathMonitor` here — by design.** Phase 6 had `wakePending` flag waiting for path-satisfied — that's removed. Apple's on-demand evaluation has its own path-readiness check; if it works, our nudge is no-op; if it doesn't, our nudge runs whether path is ready or not (and OS queues correctly). The Pitfall 10 «wake before network» problem is delegated to Apple.

### Anti-Patterns to Avoid

- **Calling `loadAllFromPreferences()` in NEVPNStatusDidChange observer.** Causes iOS 26 EXC_RESOURCE crash (per `feedback_nevpn_xpc_mach_port.md`). Read status from `notification.object` only.
- **Multi-rule conflict pattern.** Per Apple staff (Forum thread/695899) — combining aggressive `NEOnDemandRuleConnect(.any)` with `NEEvaluateConnectionRule(.neverConnect)` causes the aggressive rule to win. Phase 6c ships ONE rule. Phase 8 must order rules carefully.
- **Forgetting `loadFromPreferences()` after `saveToPreferences()`.** All Apple sample code and current ConfigImporter.swift:1028 do this. Without reload, subsequent reads see stale manager state.
- **Setting `disconnectOnSleep = true`.** Triggers sleep→connecting→sleep loop per Apple staff. Current `KillSwitch.swift:43` correctly sets to `false` — don't change.
- **Putting wake observer on `NotificationCenter.default`.** macOS wake events ONLY fire on `NSWorkspace.shared.notificationCenter`. Current code already correct (`TunnelController.swift:400`).
- **Empty `matchDomains` in `NEEvaluateConnectionRule`.** Per Apple Developer Forums (thread/81249), empty/nil `matchDomains` is unsupported and may match nothing OR everything depending on iOS version. If Phase 6c uses `NEEvaluateConnectionRule` (per D-01 wording), the rule MUST have non-empty matchDomains — but that contradicts «любой interface → connect» semantics.
- **Adding wake observer to iOS (versus macOS).** iOS wake handling is delegated to on-demand. Adding an observer is wasted code + battery.
- **Triggering reconnect from `scenePhase = .active`.** Phase 6 RESEARCH §14 Pitfall 8 already covers this. `handleForeground()` becomes no-op (or removed entirely if no other consumers).
- **Re-implementing user-intent flag in main app when `isOnDemandEnabled` IS the intent.** D-15 hints that `userIntendedConnected` может остаться — но если watchdog can read `manager.isOnDemandEnabled` as the source of truth, the local flag becomes redundant. Planner decides.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Auto-reconnect retry state machine (3 attempts × exp backoff) | `ReconnectStateMachine` actor (CURRENTLY 182 lines, to be DELETED) | `isOnDemandEnabled = true` + `[NEOnDemandRuleConnect]` | Apple's evaluation loop has been retried, debugged, and battle-tested in MDM/enterprise for 10+ years. Custom = race conditions + XPC storm + actor reentrance bugs. |
| Path change detection (Wi-Fi↔LTE handoff trigger) | `NetworkReachability` actor with `NWPathMonitor` (CURRENTLY 168 lines, to be DELETED) | Apple's evaluation loop reacts to path changes natively | Apple's loop knows when to re-evaluate — same triggers, no main-app code. Watchdog ONLY runs on `.disconnected` after stable-session. |
| Wake handling | iOS scenePhase + macOS NSWorkspace observers + wake-pending flag + reachability handshake (Phase 6 §14 Pitfall 10) | macOS-only single observer + `manager.connection.startVPNTunnel()` idempotent nudge | iOS: Apple handles. macOS: 5-line backup. Old code wakes 4-5 paths with handshake logic — fragile. |
| User-intent persistence (was `UserIntentStore` UserDefaults wrapper) | `userIntendedConnected` bool в UserDefaults | `manager.isOnDemandEnabled` IS the persistent intent | Apple persists this in system preferences for us. Free state machine. |
| Multi-rule precedence logic | Custom rule evaluator | Apple's `onDemandRules: [NEOnDemandRule]` array (first-match-wins) | Phase 8 just appends rules — no Swift code change. |
| Manual disconnect vs auto-reconnect race protection (Pitfall 3) | `manualDisconnectInProgress` flag + 1s deferred clear | `manager.isOnDemandEnabled = false` on disconnect (or per-disconnect semantics) | When user taps Disconnect, set `isOnDemandEnabled = false` for the disconnect duration; restore on next Connect. Planner decides exact semantics. |

**Key insight:** Custom auto-reconnect logic was Phase 6's biggest mistake in retrospect — every bug class (XPC storm, actor reentrance, wake handshake fragility) traces back to «мы строим то, что у iOS уже есть». Phase 6c is the architectural simplification that gets us back to the Apple-native baseline that 99% of well-behaved VPN apps use.

## Common Pitfalls

### Pitfall 1: Existing installed managers don't have on-demand configured after upgrade

**What goes wrong:** Пользователь обновляется с Phase 6 → 6c. На устройстве уже есть `NETunnelProviderManager` с `isOnDemandEnabled = false` (Phase 6 never set it) и `onDemandRules = nil`. Phase 6c app launches — UI показывает toggle «Авто-переподключение» ON (default), но на manager-level ничего не применено. Юзер ожидает auto-reconnect; его нет.

**Why it happens:** Phase 6c НЕ переимпортирует config автоматически. Без явного migration step manager остаётся в Phase 6 state.

**How to avoid:** На первом запуске Phase 6c (detected by absence of `app.bbtb.autoReconnectMigrated` flag), запустить single-shot migration: `loadAllFromPreferences()` → if manager exists, apply `OnDemandRulesBuilder.apply(to:autoReconnectEnabled: <toggle value>)` → save → load → mark migration done. Это **обязательный task в plan** — Wave 1 или Wave 4 (final flip).

**Warning signs:** UAT после upgrade — toggle ON, но Wi-Fi↔LTE handoff не реконнектит до нового импорта config.

### Pitfall 2: «Auto-reconnect OFF» + «User Connected» — what does the OS do?

**What goes wrong:** Пользователь отключил «Авто-переподключение» (`isOnDemandEnabled = false`), потом нажал Connect. Туннель up. Сменилась сеть Wi-Fi→LTE. **Apple: ничего не делает** — on-demand off. Tunnel падает. Пользователь видит обрыв и думает «toggle off сломал».

**Why it happens:** Это by design. CONTEXT.md описывает toggle как «авто-восстановление»; UI footer должен быть однозначным: «Если выключено, при смене сети или потере связи туннель не восстановится сам — нужно нажать Подключиться вручную».

**How to avoid:** Footer text для toggle (D-04 wording обсуждается): "Восстанавливать соединение при смене сети или после сна. Если выключено — после обрыва нужно подключиться вручную." Planner: финализировать wording через UI-spec.

**Warning signs:** UAT bug report «выключил авто-реконнект, туннель отвалился через 5 минут».

### Pitfall 3: Switching to another VPN app while ours is active with on-demand

**What goes wrong:** Юзер активен в BBTB. Открывает другой VPN (ProtonVPN, Mullvad). iOS: «Активный VPN — ProtonVPN, BBTB.isEnabled = false». Когда юзер потом возвращается в BBTB и тапает Connect — наш `isOnDemandEnabled = true` ничего не значит, если `isEnabled = false`.

**Why it happens:** iOS позволяет одновременно один активный VPN. При активации другого — наш `isEnabled` сбрасывается в `false` системой (но не наш `isOnDemandEnabled` — это **отдельные флаги**).

**How to avoid:** В `TunnelController.connect()` ВСЕГДА сначала проверять `manager.isEnabled` и при необходимости поднимать в `true` перед `startVPNTunnel()`. **Current code (line 276) уже делает это.** Watchdog (D-08) уже включает gate `manager.isEnabled == true` чтобы не запускать failover пока юзер в другом VPN.

**Warning signs:** UAT bug «после ProtonVPN мой VPN не подключается одним тапом, нужно дважды».

### Pitfall 4: Toggle OFF while tunnel is UP — what happens?

**What goes wrong:** Tunnel `.connected`. Юзер выключает toggle. Что должна сделать iOS?

**Apple behavior:** `isOnDemandEnabled = false` НЕ tear down active tunnel. Tunnel остаётся up до следующего естественного события (path change, wake, manual disconnect). Phase 6c: это правильно — пользователь explicit'но не сказал «отключи»; он сказал «больше не авто-восстанавливай».

**How to avoid:** Документировать в footer toggle. Не звать `stopVPNTunnel()` в `applyAutoReconnectToManager()`. **CONTEXT.md D-06 — пишет именно так: «применяется немедленно, баннер не нужен»** — это означает «применить флаг немедленно», но НЕ «отключить туннель».

**Warning signs:** UAT — юзер ожидает, что toggle off отключит активный туннель. (Это user perception issue, не bug.)

### Pitfall 5: Watchdog double-trigger with Apple's on-demand

**What goes wrong:** Сервер умер. Status: `.connected` → `.disconnected`. Watchdog (D-08) фиксирует «mid-session failover»; запускает `nextServerAttempt()` → `provisionTunnelProfile(for: nextID)` → `saveToPreferences()`. Параллельно Apple's on-demand видит `.disconnected` + reachable network → пытается re-evaluate rules → запускает старый сервер ЕЩЁ РАЗ. Получаем race: два `startVPNTunnel()` параллельно.

**Why it happens:** Both Apple and our watchdog see the same trigger.

**How to avoid:** Watchdog при срабатывании ДОЛЖЕН выполнить полный цикл: `saveToPreferences()` сначала меняет provider configuration (для нового server), потом `startVPNTunnel()`. Если Apple's on-demand успел запустить старую конфигу — manager.connection.status will be `.connecting`, наш startVPNTunnel будет no-op или error. Сам touch saveToPreferences с новой config форсирует OS перезагрузить config. **Verify via UAT** что race не приводит к crash или connecting-stuck.

**Mitigation if race manifests:** в watchdog добавить `isOnDemandEnabled = false` непосредственно перед swap, потом restore в `true` после `startVPNTunnel()`. Это даёт нашему swap exclusive control.

**Warning signs:** UAT manual server-kill test — туннель «висит на connecting» 30+ секунд.

### Pitfall 6: macOS wake observer fires BEFORE manager is loaded

**What goes wrong:** App только что запущен; SwiftUI ещё не вызвал `tunnel.startReachability()`; manager не cached. NSWorkspace.didWakeNotification fires (если запущено сразу после wake). Observer пытается обратиться к не-инициализированному manager → guard fails → silent miss.

**Why it happens:** Запуск app после long suspended period может coincide с wake.

**How to avoid:** Observer должен быть установлен в `startReachability()` (или его replacement), которое вызывается ПОСЛЕ first `loadAllFromPreferences()`. Текущий код (TunnelController.swift:400-409) уже соответствует этому паттерну.

**Warning signs:** Logs: `handleWake` invoked, but no `startVPNTunnel` call.

### Pitfall 7: «UserIntentStore» state divergence after on-demand semantics shift

**What goes wrong:** D-15 говорит «удалить `userIntendedConnected`/`connectInProgress`/`manualDisconnectInProgress`», но Watchdog (D-08) требует intent gate. Если planner оставляет `userIntendedConnected` для watchdog — есть риск divergence: `isOnDemandEnabled = true` но `userIntendedConnected = false` (или наоборот). Какой источник истины?

**How to avoid:** Унифицировать. Recommend: после Phase 6c watchdog gate читает `manager.isOnDemandEnabled` напрямую (cached at watchdog start). Это устраняет local mutable state + UserDefaults sync issues. Если planner предпочитает оставить local flag — обязательно double-write при каждой toggle change.

**Warning signs:** Race tests fail intermittently на CI; toggle change → watchdog fires inconsistent.

### Pitfall 8: provisionTunnelProfile rebuilds and OVERWRITES user toggle

**What goes wrong:** ConfigImporter.provisionTunnelProfile (line 1004) создаёт NEW manager или fetches existing, set `isEnabled = true`, set protocolConfiguration. Если builder также пишет `isOnDemandEnabled` — какой источник истины? Если builder hardcoded `isOnDemandEnabled = true` — пользовательский toggle игнорируется.

**How to avoid:** `OnDemandRulesBuilder.apply(to:autoReconnectEnabled:)` READS the current toggle (`OnDemandRulesBuilder.loadAutoReconnectEnabled()`) перед setting flag. ConfigImporter передаёт явно либо builder сам читает. Wave 1 task: в `DefaultTunnelProvisioner.provisionTunnelProfile` добавить вызов `OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: loadFlag())`.

**Warning signs:** UAT — toggle off, потом импорт нового config, потом toggle ON по-факту в manager.

### Pitfall 9: «Auto toggle on» but no servers in pool

**What goes wrong:** Fresh install. Toggle default ON (D-04). User ещё не импортировал config. `NETunnelProviderManager` doesn't exist. `OnDemandRulesBuilder.apply` ничего не делает (нет manager). User импортирует config — but our migration code runs ONLY once, on app start before import. Result: первый импорт не получает on-demand rules.

**How to avoid:** ConfigImporter.provisionTunnelProfile ВСЕГДА вызывает `OnDemandRulesBuilder.apply`. Это идемпотентно: каждый import (initial + reimport) пишет правильный state на основе текущего toggle. Migration step (Pitfall 1) — orthogonal one-shot для существующих installs.

**Warning signs:** Fresh install, import config, toggle ON in UI but no on-demand rules in manager.

### Pitfall 10: NEVPNStatus reporting differences iOS vs macOS

**What goes wrong:** On macOS, when on-demand fires reconnect, `NEVPNStatus` cycle может выглядеть как `disconnected → connecting → connected` BUT в edge case `→ disconnecting → disconnected → connecting → connected` (Apple bug r. 74473825 in Catalina). Watchdog логика «`.disconnected` после stable-session → failover» может сработать на этом transient `.disconnected` несмотря на subsequent on-demand reconnect.

**How to avoid:** Watchdog adds short debounce (~3s): после `.disconnected` ждём 3s; если за это время статус вернулся к `.connecting`/`.connected` — abort failover. Apple's on-demand имеет окно ~1-2s для самостоятельного reconnect, debounce покрывает.

**Warning signs:** UAT macOS: stable session, network blip — watchdog ushers in failover, но Apple's on-demand также сам пытается. Race.

## Code Examples

Verified patterns from official sources or reference implementations.

### Example 1: `NEOnDemandRuleConnect` with `.any` interface (RECOMMENDED for Phase 6c)

```swift
// Source: WireGuard wireguard-apple/Sources/WireGuardApp/Tunnel/ActivateOnDemandOption.swift:35
// (BSD/MIT license, verified via raw GitHub fetch 2026-05-13)

let connectRule = NEOnDemandRuleConnect()
connectRule.interfaceTypeMatch = .any
manager.onDemandRules = [connectRule]
manager.isOnDemandEnabled = true
try await manager.saveToPreferences()
try await manager.loadFromPreferences()  // mandatory reload — see Pitfall 8 / ConfigImporter.swift:1028
```

### Example 2: `NEEvaluateConnectionRule` with domains (Phase 8 use, NOT Phase 6c)

```swift
// Source: Apple Developer Forums thread/695899 (Apple DTS staff response)
// Use case: «when connecting to corporate domains → connect VPN»

let evaluateRule = NEEvaluateConnectionRule(
    matchDomains: ["corp.example.com", "internal.example.com"],
    andAction: .connectIfNeeded
)
evaluateRule.probeURL = URL(string: "https://corp.example.com/probe")  // optional probe

let onDemandRule = NEOnDemandRuleEvaluateConnection()
onDemandRule.connectionRules = [evaluateRule]
onDemandRule.interfaceTypeMatch = .any

manager.onDemandRules = [onDemandRule]
manager.isOnDemandEnabled = true
```

**Note:** Phase 6c does NOT use this. Document it here as a Phase 8 reference so the planner knows how the builder API extends.

### Example 3: Toggle on/off while tunnel is active

```swift
// Source: WireGuard wireguard-apple/Sources/WireGuardApp/Tunnel/TunnelsManager.swift
// setOnDemandEnabled function pattern (verified via WebFetch 2026-05-13)

func setAutoReconnect(_ enabled: Bool, for manager: NETunnelProviderManager) async throws {
    manager.isOnDemandEnabled = enabled
    manager.isEnabled = true  // ensure profile is not disabled in iOS Settings
    try await manager.saveToPreferences()
    if enabled {
        try await manager.loadFromPreferences()  // WireGuard pattern: reload to ensure status updates propagate
    }
}
```

**Note:** `manager.isEnabled = true` is preserved — disabling the profile entirely requires user action in iOS Settings, not our toggle.

### Example 4: Reading status from `notification.object` (XPC-free) — preserved from Phase 6

```swift
// Source: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:384-394
// (current implementation — proven Phase 6 UAT fix)

nevpnObserver = NotificationCenter.default.addObserver(
    forName: .NEVPNStatusDidChange,
    object: nil,
    queue: nil
) { [weak self] notification in
    guard let conn = notification.object as? NEVPNConnection else { return }
    let status = conn.status  // SYNCHRONOUS property — NO XPC
    Task { [weak self] in
        await self?.watchdog.handleStatusChange(status, managerEnabled: ...)
    }
}
```

### Example 5: One-shot migration on Phase 6c first launch

```swift
// NEW — to be added in Wave 1 or Wave 4 (final flip)
// Pattern: idempotent migration guarded by UserDefaults flag

func migrateExistingManagerForOnDemand() async {
    let migratedKey = "app.bbtb.autoReconnectMigratedV6c"
    if UserDefaults.standard.bool(forKey: migratedKey) { return }

    do {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        if let manager = managers.first {
            let enabled = OnDemandRulesBuilder.loadAutoReconnectEnabled()
            OnDemandRulesBuilder.apply(to: manager, autoReconnectEnabled: enabled)
            try await manager.saveToPreferences()
            try await manager.loadFromPreferences()
        }
        UserDefaults.standard.set(true, forKey: migratedKey)
    } catch {
        // Don't set the flag — retry on next launch
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Custom retry state machine + main-app observer pipeline | Apple's `isOnDemandEnabled` + `onDemandRules` | Phase 6c (2026-05-13) | -570 lines of custom logic; eliminates 4 bug classes; aligns with WireGuard / sing-box-for-apple pattern. |
| `NWPathMonitor` in main app | Apple's evaluation loop (path change detection internal) | Phase 6c | Removes 168 lines + entire dedup/throttle complexity. |
| Per-interface manual flag tracking (`userIntendedConnected`, etc.) | `isOnDemandEnabled` as canonical persistent intent | Phase 6c | Reduces state machine surface area; UserDefaults `app.bbtb.userIntendedConnected` becomes either no-op or kept for watchdog gate (planner choice). |
| Wake handshake (Pitfall 10: wake + reachability-satisfied) | iOS: Apple handles; macOS: simple idempotent nudge | Phase 6c | Removes wake-pending flag, removes ReachabilityListener-wake coupling. Aligns with sing-box-for-apple. |

**Deprecated/outdated:**
- **`ReconnectStateMachineState`** enum and observer types — used by `ReconnectBanner` indirectly. Banner needs to consume new state source (likely simpler: `NEVPNStatus` direct or computed reconnecting flag). Banner code preservation per D-17.
- **`NetworkReachabilityEvent`** types — used internally only. Delete.
- **Phase 6 RESEARCH §3 NWPathMonitor recipe** — superseded by «Apple's evaluation loop». Phase 6 RESEARCH stays as historical record.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Swift Testing not used in project per Phase 1-6 precedent) |
| Config file | Per-package `Package.swift` test targets (`Tests/MainScreenFeatureTests` etc.) |
| Quick run command | `cd BBTB/Packages/AppFeatures && swift test --filter OnDemandRulesBuilderTests` |
| Full suite command | `cd BBTB && xcodebuild test -scheme BBTB-iOS -destination 'platform=iOS Simulator,name=iPhone 16'` (или per-package `swift test`) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| NET-08 | Wi-Fi↔LTE handoff reconnect | manual UAT (Apple loop, not unit-testable in-process) | UAT-Task A: Wi-Fi off; LTE; verify reconnect via banner + ip-check | ❌ Manual — Wave 4 UAT |
| NET-08 (config) | Builder produces `[NEOnDemandRuleConnect(.any)]` when enabled | unit | `swift test --filter OnDemandRulesBuilderTests/test_apply_enabled_writesConnectAnyRule` | ❌ Wave 0 — NEW test file |
| NET-09 | iOS wake reconnect | manual UAT (delegated to Apple) | UAT-Task B: iPhone overnight; wake; verify auto-reconnect | ❌ Manual — Wave 4 UAT |
| NET-09 | macOS wake nudge + on-demand | manual UAT + unit | UAT-Task C: MacBook sleep 10min + wake; verify reconnect within 15s. Unit: `swift test --filter TunnelControllerTests/test_macOS_wake_observer_calls_startVPNTunnel_idempotently` | ❌ Wave 0 + Wave 4 UAT |
| NET-10 | IP change reconnect | manual UAT (Apple loop) | UAT-Task D: subway → station Wi-Fi; verify reconnect | ❌ Manual — Wave 4 UAT |
| NET-11 | Initial-connect failover (preserved Phase 6 Wave 6) | unit | `swift test --filter FailoverProviderTests` | ✅ Existing — preserved |
| NET-11 | Mid-session watchdog failover | unit + manual UAT | Unit: `swift test --filter TunnelWatchdogTests/test_fires_only_after_stable_session_30s_with_intent`. UAT-Task E: connect; let stable 1min; kill server; verify swap to next server. | ❌ Wave 0 (unit) + Wave 4 UAT |
| (cross-cutting) | Toggle live-apply | unit | `swift test --filter SettingsViewModelTests/test_autoReconnectEnabled_toggle_writes_isOnDemandEnabled` | ❌ Wave 0 — NEW test |
| (cross-cutting) | Existing-manager migration | unit | `swift test --filter MigrationTests/test_migrate_idempotent_writes_isOnDemandEnabled_once` | ❌ Wave 0 — NEW test |
| (regression) | Connect/disconnect contract preserved | unit | `swift test --filter TunnelControllerTests/test_connect_polls_until_connected_or_throws` | ❌ Wave 0 — replaces TunnelControllerStateTests |

### Sampling Rate

- **Per task commit:** `swift test --filter MainScreenFeatureTests` (target ~3-5s for changed-area tests)
- **Per wave merge:** Full `swift test` on `AppFeatures` + `KillSwitch` + smoke на iOS Simulator
- **Phase gate:** Full xcodebuild test suite (all packages) green + UAT 6 scenarios PASS

### Wave 0 Gaps

- [ ] `OnDemandRulesBuilderTests.swift` — covers NET-08 (config), NET-09 (config), cross-cutting
- [ ] `TunnelControllerTests.swift` — covers connect/disconnect contract, macOS wake observer (replaces deleted TunnelControllerStateTests)
- [ ] `TunnelWatchdogTests.swift` — covers NET-11 mid-session
- [ ] `SettingsViewModelTests.swift` (auto-reconnect coverage) — toggle live-apply OR add tests to existing `SettingsViewModelDNSTests.swift`
- [ ] `MigrationTests.swift` — Pitfall 1 idempotent migration
- [ ] `ReconnectBanner` test update — banner state source change (D-17)

*(NO framework install needed — XCTest project standard.)*

## Security Domain

Phase 6c is a **refactor**, not a feature addition. New attack surface: zero (using Apple's existing API differently). Threat model is largely inherited from Phase 6 + Phase 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth in Phase 6c — unchanged from Phase 6 |
| V3 Session Management | no | Tunnel session managed by NetworkExtension — Apple-controlled |
| V4 Access Control | no | iOS sandbox + entitlement model — Phase 1 carry-forward |
| V5 Input Validation | yes | UserDefaults `app.bbtb.autoReconnectEnabled` — `Bool` only, no parse path; UAT must verify malformed UserDefaults values don't cause crash |
| V6 Cryptography | no | No new crypto in Phase 6c |

### Known Threat Patterns for NetworkExtension / on-demand

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Stale `onDemandRules` array persists across upgrades, attacker manipulates UserDefaults | Tampering | UserDefaults values are sandbox-protected per app. Phase 6c's `app.bbtb.autoReconnectEnabled` is `Bool`-only — no injection vector. |
| Manager pre-existing from Phase 6 used by malicious app | Tampering | NETunnelProviderManager preferences are sandbox-protected; no cross-app access. |
| Race between watchdog and Apple's on-demand triggers concurrent `startVPNTunnel()` causing stuck state | DoS (to user, not security) | Pitfall 5/10 mitigations: debounce, optional `isOnDemandEnabled = false` during swap. |
| `isOnDemandEnabled = true` but user revoked manager in iOS Settings — app can't tell without XPC | Information disclosure (UX, not security) | Watchdog gate `manager.isEnabled == true` cached. If user disables profile externally, watchdog stays silent (acceptable UAT behavior). |
| Wake observer registered before manager loaded — observer keeps weak ref | DoS (silent miss) | Pitfall 6: install observer in `startReachability` AFTER `loadAllFromPreferences` returns. |
| Existing R1 / R6 (Phase 1 security audit) — SOCKS local port, P2P=true | Information disclosure | Unchanged by Phase 6c. UAT-Task R1/R6 regression check remains. |

**No new BLOCKER-class threats identified.** Carry-forward: Phase 4 WR-* gaps remain, no new contributions.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| iOS 18 SDK / NetworkExtension framework | All on-demand APIs | ✓ | Project min iOS 18 — verified via `IPHONEOS_DEPLOYMENT_TARGET` | — |
| macOS 15 SDK / AppKit / NSWorkspace | macOS wake observer (D-11) | ✓ | Project min macOS 15 | — |
| Apple NEPacketTunnelProvider entitlement | Tunnel start | ✓ | Already provisioned (Phase 1 CORE-04) | — |
| Apple NetworkExtension entitlement | NETunnelProviderManager API | ✓ | Already provisioned (Phase 1 CORE-04 + entitlements) | — |
| iOS Simulator (testing) | xcodebuild test smoke | ✓ | Xcode 26 default (iPhone 16 / iOS 26.x) | — |
| Physical iPhone for UAT | NET-08 / NET-09 / NET-10 manual tests | ✓ | iPhone 11+ (CORE-04) | — |
| Physical MacBook for UAT | NET-09 macOS wake test | ✓ | Apple Silicon (DIST-02) | — |
| Tunnel sandbox / dev profile | UAT on device | ✓ | Phase 1 profiles | — |

**No external dependencies.** No new SPM packages, no xcframeworks, no system tools.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | CONTEXT.md D-01's stated `NEEvaluateConnectionRule` was a terminological slip — author meant the Phase 8 evolution path, not literal Phase 6c API | Standard Stack alternatives; Open Question 1 | If user actually wants literal `NEEvaluateConnectionRule` from start, the matchDomains requirement forces a domain-based config like `matchDomains: ["*"]` which Apple does not officially support per forum thread/81249. Planner should resolve before implementation. |
| A2 | `userIntendedConnected` flag becomes redundant after on-demand migration; planner may delete | Don't Hand-Roll table | If watchdog can't read `isOnDemandEnabled` cheaply (or if Apple's flag semantics differ from "user intent"), local flag must stay. |
| A3 | macOS on-demand WILL fire after wake in most cases, with wake observer as backup nudge | macOS wake handling | If on-demand never fires after wake on macOS (worst case), our 5-line nudge IS the primary mechanism — but it's idempotent and works either way. |
| A4 | Apple's on-demand re-evaluation handles Wi-Fi↔LTE handoff faster than 4-5 seconds (user-perceptible threshold) | NET-08 UAT | If Apple's evaluation is slower than 5s, UAT may "fail" subjectively (user sees long banner) — though technically correct. Mitigation: documentation, not code. |
| A5 | iOS 26 does not introduce on-demand API changes or new behaviors | Standard Stack version verification | If iOS 26 changes rule evaluation order, our single-rule config is unaffected (no order to break). Risk LOW. |
| A6 | Watchdog observer reading `notification.object` status remains XPC-free in iOS 26 | Pattern 3 / Pitfall 4 of Phase 6 | If Apple changes the API in iOS 27+ to require XPC for status reads, observer needs redesign. Risk: future-fixable. |
| A7 | Existing `NETunnelProviderManager` from Phase 6 upgrades correctly to Phase 6c after one-shot migration | Pitfall 1 / Code Example 5 | If saveToPreferences after migration corrupts existing manager (e.g., resets protocolConfiguration), users must re-import config. Wave 4 UAT must verify upgrade path. |
| A8 | Toggle live-apply via `saveToPreferences()` does not cause tunnel restart when only `isOnDemandEnabled` changes | Pitfall 4 / Pattern 2 | If saveToPreferences forces tunnel reconnect, toggle becomes disruptive UX. Apple's behavior: `isOnDemandEnabled` changes do not interrupt active connection. Verified via WireGuard reference; minor risk. |
| A9 | Removing `ReconnectStateMachine` doesn't break `ReconnectBanner` if planner wires banner to new state source | D-17 | If banner has implicit assumptions about state machine lifecycle (e.g., visible duration computed from `retrying(attempt:)` payload), refactor needs care. UI-side smoke test in Wave 3. |
| A10 | `NEOnDemandRuleConnect(interfaceType: .any)` does not match utun (our own tunnel) — only physical interfaces | Pattern 1 | If `.any` includes utun, we get the same Pitfall 2 issue Phase 6 had with NWPathMonitor. Apple docs do NOT explicitly clarify this — based on WireGuard's universal use of `.any` without filters, the assumption is safe. |

## Open Questions

1. **D-01 terminology vs. API**
   - **What we know:** CONTEXT.md D-01 says «использовать `NEEvaluateConnectionRule` с самого начала ... массив правил с `connectionAction = .connect`». Per Apple staff: `NEEvaluateConnectionRule` requires non-empty `matchDomains` and lives inside `NEOnDemandRuleEvaluateConnection.connectionRules`. WireGuard, sing-box-for-apple, and Apple's SimpleTunnel sample all use `NEOnDemandRuleConnect(interfaceType: .any)` for the «always-connect» semantic.
   - **What's unclear:** Did the user intend literal `NEEvaluateConnectionRule` (which would require synthetic `matchDomains` like `[""]` or `["*"]`, behavior undefined), or did the user use the term loosely to mean «the evolved rules-engine architecture»?
   - **Recommendation:** Implement `NEOnDemandRuleConnect` in Phase 6c for technical correctness; design `OnDemandRulesBuilder` API to accept future rule types (Phase 8). This satisfies D-01's stated intent («extensibility for Phase 8 user rules») without misusing Apple API. Surface this to user during planning if they want literal API match.

2. **Should `userIntendedConnected` be deleted or kept for watchdog gate?**
   - **What we know:** D-15 lists it for removal; D-08 requires intent gate for watchdog.
   - **What's unclear:** Can watchdog read `manager.isOnDemandEnabled` as canonical intent? Or does «intent» need a separate concept (e.g., «user explicitly tapped Connect at least once»)?
   - **Recommendation:** Planner decides. If `isOnDemandEnabled` is treated as intent, delete `UserIntentStore`. Otherwise, retain but document that it's watchdog-internal, not auto-reconnect logic gate.

3. **Watchdog: inline in `TunnelController` or separate actor?**
   - **What we know:** CONTEXT.md Claude's Discretion explicitly says planner decides.
   - **What's unclear:** Tradeoff is testability (separate actor easier to unit-test) vs simplicity (inline = no new file).
   - **Recommendation:** Separate actor (`TunnelWatchdog.swift`) — explicit testability advantage given D-24 watchdog test category. Cost: one new file.

4. **Toggle OFF — should it tear down active tunnel?**
   - **What we know:** Pitfall 4 — Apple doesn't tear down. CONTEXT.md D-06 doesn't specify explicit behavior.
   - **What's unclear:** User expectation. If toggle is framed as «авто-восстановление», then toggle OFF = «don't auto-restore but keep current session» is consistent. If framed as «auto-VPN», then OFF = «disable VPN» is consistent.
   - **Recommendation:** Stay with Apple's default behavior (don't tear down). Footer text must clarify.

5. **Apple's on-demand vs watchdog race (Pitfall 5)**
   - **What we know:** Both can trigger after `.disconnected`. Apple's on-demand will retry the SAME (now-dead) server; watchdog wants to swap to NEXT server.
   - **What's unclear:** Without device testing, hard to know if race manifests as user-visible problem (extra 5s on connecting?) or invisible.
   - **Recommendation:** Wave 4 UAT-Task E is critical. If race manifests: add `isOnDemandEnabled = false` during swap, restore after.

6. **What does FailoverProvider see when watchdog runs it?**
   - **What we know:** Existing `SwiftDataFailoverProvider.nextServerAttempt()` returns a closure that does `provisionTunnelProfile + connect()`.
   - **What's unclear:** With on-demand on, does `connect()`'s explicit `startVPNTunnel()` interfere with Apple's parallel attempt? Or just hits "already connecting" state?
   - **Recommendation:** UAT verification. May need to skip `connect()` after `provisionTunnelProfile` since on-demand handles the start — but then we don't await success/failure.

7. **What happens to `ReconnectBanner` state source?**
   - **What we know:** D-17 says NEVPNStatusDidChange observer remains for `@Published` banner state. Old source was `ReconnectStateMachineState` enum.
   - **What's unclear:** Mapping. `.connecting` → banner "Подключение"; `.reasserting` → banner "Переподключение"; `.disconnected` after recent connect → banner "Обрыв"?
   - **Recommendation:** Planner specs simpler mapping using `NEVPNStatus` only. Existing banner UI keeps render code; ViewModel adapter is minor.

## Sources

### Primary (HIGH confidence)

**Apple Developer Documentation:**
- [NETunnelProviderManager | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager)
- [NEOnDemandRule | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neondemandrule)
- [NEOnDemandRuleConnect | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neondemandruleconnect)
- [NEOnDemandRuleAction.connect | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neondemandruleaction/connect)
- [NEEvaluateConnectionRule | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neevaluateconnectionrule)
- [NEEvaluateConnectionRuleAction.connectIfNeeded | Apple Developer Documentation](https://developer.apple.com/documentation/networkextension/neevaluateconnectionruleaction/connectifneeded)
- [NSWorkspace.didWakeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification) — proven Phase 6 §5 pattern
- [iOS & iPadOS 26 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26-release-notes) + 26.1-26.5 — no on-demand API changes documented

**Codebase (verified by direct read):**
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift` (618 lines, current implementation)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectStateMachine.swift` (to-be-deleted)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/NetworkReachability.swift` (to-be-deleted)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/FailoverProvider.swift` (preserved)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:1004-1029`
- `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` (reference pattern for `apply(to:enabled:)`)
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` (toggle persistence pattern)

**WireGuard reference implementation (BSD/MIT licensed, raw GitHub fetch 2026-05-13):**
- [WireGuard wireguard-apple ActivateOnDemandOption.swift](https://github.com/WireGuard/wireguard-apple/blob/master/Sources/WireGuardApp/Tunnel/ActivateOnDemandOption.swift) — exact rules pattern for Connect/Disconnect/SSID
- [WireGuard wireguard-apple TunnelsManager.swift](https://github.com/WireGuard/wireguard-apple/blob/master/Sources/WireGuardApp/Tunnel/TunnelsManager.swift) — modify(), setOnDemandEnabled(), startActivation() flows

**Project memory (verified by direct read):**
- `feedback_nevpn_xpc_mach_port.md` — iOS 26 EXC_RESOURCE/PORT_SPACE root cause, observer pattern fix
- `feedback_auto_reconnect_user_intent_guard.md` — userIntendedConnected + connectInProgress UAT rationale
- `feedback_failover_two_phase_init.md` — actor-actor cycle resolution pattern (already in use)
- `feedback_netunnelnetworksettings_tunnelRemoteAddress.md` — provisionTunnelProfile invariant

### Secondary (MEDIUM confidence — verified via Apple staff posts)

**Apple Developer Forums (Apple staff responses):**
- [Apple Developer Forums thread 688021 — Sleep + on demand rules](https://developer.apple.com/forums/thread/688021) — Apple staff: macOS on-demand may not re-trigger reliably after wake; recommend manual lifecycle management
- [Apple Developer Forums thread 737122 — Connect On Demand not working as expected](https://developer.apple.com/forums/thread/737122) — Apple staff: macOS third-party browsers bypass on-demand (not relevant to BBTB but documents limitation)
- [Apple Developer Forums thread 695899 — on-demand rules conflict](https://developer.apple.com/forums/thread/695899) — Apple staff: aggressive `interfaceTypeMatch = .any` overrides `.neverConnect` rules when combined
- [Apple Developer Forums thread 81249 — NEOnDemandRules evaluation with NEEvaluateConnectionRule](https://developer.apple.com/forums/thread/81249) — community: `matchDomains: []` not supported

**Third-party references:**
- [kean.blog — VPN, Part 1: VPN Profiles](https://kean.blog/post/vpn-configuration-manager) — basic on-demand recipe (confirms WireGuard pattern is mainstream)
- [Derman Enterprises — Example iOS VPN OnDemand Rules](https://www.derman.com/blogs/Example-iOS-VPN-OnDemand-Rules) — practical SimpleTunnel-derived examples
- [SimpleTunnel OnDemandRuleListController.swift](https://github.com/ios-sample-code/SimpleTunnel/blob/master/SimpleTunnel/OnDemandRuleListController.swift) — Apple sample code

### Tertiary (LOW confidence — flagged for validation)

- WebSearch results without official source backing for «iOS 26 on-demand specifics» — confidence: no NEW on-demand changes documented in iOS 26 release notes, but absence of evidence isn't evidence of absence. Mitigation: device UAT on iOS 26.5 is mandatory per D-22.

## Metadata

**Confidence breakdown:**

- Standard stack: **HIGH** — Apple's NetworkExtension on-demand API is documented, stable since iOS 9, used by WireGuard / sing-box-for-apple / Apple's own samples. WireGuard pattern directly fetched 2026-05-13.
- Architecture: **HIGH** — D-01..D-25 from CONTEXT.md are concrete; only one terminological discrepancy (D-01 wording vs API), surfaced as Open Question 1.
- Pitfalls: **HIGH** — 10 pitfalls identified, 5 of them backed by Apple staff statements (Apple Developer Forums); remainder grounded in current codebase + Phase 6 UAT learnings.
- iOS 26 specifics: **MEDIUM-HIGH** — no documented changes in 26.0-26.5 release notes for on-demand; assumes API stability (A5). UAT on real iOS 26.5 device required.
- macOS wake quirks: **HIGH** — Apple staff explicitly confirms the issue; D-11 hybrid approach aligns with their recommendation.
- Testing strategy: **HIGH** — XCTest patterns established Phase 1-6, three new test categories well-scoped.

**Research date:** 2026-05-13
**Valid until:** 2026-08-13 (~3 months — NetworkExtension on-demand API is mature, low churn risk)

---

*Researched by gsd-researcher 2026-05-13. Consumer: gsd-planner. Phase: 6c-on-demand-migration.*
