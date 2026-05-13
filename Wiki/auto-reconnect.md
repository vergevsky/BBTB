---
name: Auto-reconnect mechanism (Phase 6c on-demand migration)
description: Apple-managed NEOnDemandRule reconnect, заменяет custom state machine из Phase 6. Sliding session window — on-demand активен только между явным BBTB Connect и любым session-closing событием.
type: feature
---

# Auto-reconnect — Apple's NEOnDemandRule (Phase 6c)

**Summary**: Phase 6c заменила custom auto-reconnect machinery (ReconnectStateMachine + NEVPNStatusDidChange observer + NetworkReachability) на iOS-нативный механизм `manager.isOnDemandEnabled = true` + `[NEOnDemandRuleConnect(interfaceTypeMatch: .any)]`. Решение принято для устранения четырёх классов багов Phase 6 (phantom reconnect на fresh install, XPC storm на iOS 26 → EXC_RESOURCE crashes, fight-back с другими VPN-приложениями, Mach port exhaustion). Auto-reconnect — это **sliding session window**: `isOnDemandEnabled` истинно только между явным BBTB Connect и любым session-closing событием (явный Disconnect, iOS Settings disable, такеовер другим VPN).

**Sources**:
- `.planning/phases/06c-on-demand-migration/06C-CONTEXT.md` — 25 D-decisions
- `.planning/phases/06c-on-demand-migration/06C-RESEARCH.md` — 10 pitfalls, 7 open questions, WireGuard/sing-box-for-apple reference patterns
- `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` — Round 1-5 history (planning + UAT discoveries)
- `.planning/phases/06c-on-demand-migration/06C-ARCHITECT-R5.md` — Codex GPT-5.2 architect review (parallel-run diagnosis, pull-cleanup-forward decision)
- Apple docs: NEVPNManager, NEOnDemandRule, NETunnelProviderManager

**Last updated**: 2026-05-13 (Phase 6c — **Wave 3 cutover complete на main**, commits `19f3fe7` + `5b0e28c` + `69b8ae8`; AppFeatures 133/133 + xcodebuild iOS + macOS green; awaiting re-UAT pair F-reverse + Settings-disable on iPhone iOS 26.5).

---

## Зачем такой переход (контекст)

Phase 6 шипила **custom auto-reconnect machinery**:
- `ReconnectStateMachine` actor с 3 retry attempts × exponential backoff
- `NetworkReachability` actor поверх `NWPathMonitor` для триггера retry на network change
- `NEVPNStatusDidChange` observer в `TunnelController` для триггера recovery на `.disconnected`
- Ручные флаги: `userIntendedConnected`, `connectInProgress`, `manualDisconnectInProgress`, `wakePending`, `lastKnownStatus`, `manualDisconnectInProgress`, и т.д.

**Что показал UAT Phase 6**: четыре класса багов, каждый из которых ронял UX:

| # | Bug class | Что | Источник в коде |
|---|---|---|---|
| 1 | Phantom reconnect на fresh install | После `saveToPreferences` приходит NEVPNStatusDidChange → recovery видит .satisfied network + intent stub → запускает connect стартовым "auto" событием, до явного тапа Connect | NEVPNStatusDidChange observer + NetworkReachability path |
| 2 | XPC storm на iOS 26 → EXC_RESOURCE/PORT_SPACE crash | iOS 26 поднимает 40+ status notifications в секунду под network churn. Recovery path делал XPC `loadAllFromPreferences()` в каждом → Mach port exhaustion → crash | recovery path + status observer reading via XPC |
| 3 | Fight-back с другим VPN-приложением | Пользователь активирует Happ/ProtonVPN — наш `NEVPNStatusDidChange` ловит `.disconnected`, recovery state machine starts retry, наш `connect()` re-enables BBTB profile → выпинывает чужой VPN | recovery on .disconnected + connect path re-enabling manager |
| 4 | Phantom reconnect после import конфига | Импорт нового config → `provisionTunnelProfile` saveToPreferences → status fires → recovery видит intent=true + profile-exists → auto-connect до пользовательского тапа | NEVPNStatusDidChange observer reactive to save |

Architectural insight: **мы переизобретали то, что iOS уже делает нативно** через `NEOnDemandRule` + `manager.isOnDemandEnabled`. WireGuard iOS делает именно так. sing-box-for-apple — тоже. Мы стояли на собственной кастомной реализации потому что не знали про это; Phase 6c — coursecorrect.

## Финальная архитектура (после Phase 6c Plan 04 Task 3 cleanup)

### Один источник правды для on-demand: `OnDemandRulesBuilder`

```swift
public enum OnDemandRulesBuilder {
    // Low-level: write rules + isOnDemandEnabled = passed Bool. Caller computes the Bool.
    public static func apply(to: NETunnelProviderManager, isOnDemandEnabled: Bool)

    // High-level single source of truth:
    // isOnDemandEnabled = loadAutoReconnectEnabled() && loadUserIntendedConnected()
    public static func applyCurrentState(to: NETunnelProviderManager, userDefaults: UserDefaults = .standard)

    public static func loadAutoReconnectEnabled(...) -> Bool   // UserDefaults `app.bbtb.autoReconnectEnabled` default ON
    public static func loadUserIntendedConnected(...) -> Bool  // UserDefaults `app.bbtb.userIntendedConnected` default false
}
```

Ключевой инвариант: `isOnDemandEnabled = (пользовательский тогл) && (намерение)`. **Не "always reconnect forever"** — это **скользящее окно сессии**.

### Sliding session window — главный инвариант

| Событие | `userIntendedConnected` | `isOnDemandEnabled` |
|---|---|---|
| Свежая установка (intent ещё не сетили) | false | false (даже если toggle ON по default) |
| Пользователь тапнул Connect | → true | → toggle && true = toggle |
| Подключение установлено | true | unchanged |
| Wi-Fi → LTE handoff (transient .disconnected/.reasserting) | unchanged | unchanged (iOS на on-demand сам reconnect'нет) |
| Пользователь тапнул Disconnect | → false | → false |
| Другой VPN захватил route (Happ, ProtonVPN, etc.) | → false | → false |
| iOS Settings → VPN → toggle BBTB off | → false | → false |
| Server-side disconnect (sing-box died on VPS) | unchanged | unchanged (watchdog swap'ит сервер) |

**Settings-disable и other-VPN-takeover трактуются одинаково**: оба закрывают intent, BBTB сидит off до явного тапа Connect. Это сознательное design-решение (см. Codex R5 архитекторский review): пользователь сделал явное действие, мы уважаем его.

### Три компонента сменили custom state machine

| Компонент | Роль | Где |
|---|---|---|
| **Apple NEOnDemandRule** | Reconnect на network change, wake, transient drops | iOS managed (мы только конфигурируем) |
| **TunnelWatchdog actor** | Mid-session failover при «сервер умер» — swap на следующий сервер из round-robin | `MainScreenFeature/TunnelWatchdog.swift`. Fires только при `.disconnected` после ≥30s stable session + intent + isEnabled. 3s debounce + cancellation на `.connecting`/`.reasserting`/`.connected`. XPC-free hot path |
| **OnDemandMigrationTask** | One-shot migration существующих установок Phase 6 → Phase 6c при первом запуске | `MainScreenFeature/OnDemandMigrationTask.swift`. Идемпотентна, transient-failure safe (flag не сетится при ошибке) |

### macOS специфика: hybrid

- Основной механизм — то же Apple on-demand (как iOS).
- Плюс backup nudge: `NSWorkspace.didWakeNotification` observer → `manager.connection.startVPNTunnel()` (idempotent — no-op если уже up). С тремя guards: `manager.isEnabled` + `manager.isOnDemandEnabled` + `loadAutoReconnectEnabled()`.

iOS этого backup не нужен — Apple on-demand evaluator сам справляется с wake.

### Reactive UI driver

`MainScreenViewModel.state` (отображает «Подключение» / «Подключено» / etc.) **обновляется реактивно из NEVPNStatusDidChange**, а не императивно в `connect()` / `disconnect()`:

| NEVPNStatus | `state` | `bannerState` |
|---|---|---|
| `.connecting` / `.reasserting` | `.connecting` | `.connecting` (если ничего не висит) |
| `.connected` | `.connected(since: Date())` | `.hidden` (preserve `.killSwitchReconfigure` / `.failover`) |
| `.disconnected` / `.invalid` / `.disconnecting` | `.idle` (preserve `.error` если был от команды) | `.hidden` (preserve `.killSwitchReconfigure`) |

`connect()` / `disconnect()` остаются как **command-методы** — они инициируют операцию, но не устанавливают UI state из себя. NEVPNStatus — авторитет.

При init MainScreenViewModel делает один seed-read статуса чтобы избежать flicker'а до первой нотификации.

## Pitfalls обнаруженные в UAT

Phase 6c прошла **триплет ревью** (gsd-plan-checker + Codex GPT-5.2 + Gemini 2.5 Pro) с вердиктом APPROVE до execute. UAT всё равно вскрыл **runtime-specific gaps**, которые static review не мог увидеть:

### Bug A — UI freeze на initial Connect (Wave 3 Task 1 / Round 4.1 stage)

Симптом: VPN физически подключается за ~3с, UI зависает с баннером «Переподключение... попытка 1 из 3».

Root cause (Codex R5): **parallel-run hybrid**. Старая `ReconnectStateMachine` всё ещё была wired в `TunnelController` (намеренно — для rollback safety). Она публиковала `.retrying(attempt:1)` в `MainScreenViewModel.reconnectBannerState`. `applyVPNStatusToBanner(.connected)` сознательно не очищал `.retrying` баннер (под assumption «active auto-reconnect баннер должен выиграть»). И главное: `MainScreenViewModel.state = .connecting` ставился в `performToggleImpl` и **снимался только когда наш `tunnel.connect()` возвращал успех**. Если OS реально подключился через on-demand вне `connect()` await — VM не повышал state.

Fix: Plan 04 Task 3a/3b cleanup (см. ниже).

### Bug B — Settings → VPN off → BBTB сам подключается обратно

Симптом: пользователь выключает BBTB toggle в iOS Settings → VPN. UI показывает «не подключён». Туннель возвращается через несколько секунд.

Root cause (Codex R5): тот же parallel-run. Старый `triggerRecoveryIfNeeded` был wired в `handleStatusChange(.disconnected)` AND в reachability/wake observers. После `await refreshCachedManager()` (Round 4 patch) actor отпускался, reachability observer мог запустить `triggerRecoveryIfNeeded` с `userIntendedConnected == true` и stale cached `isEnabled`. Старая state machine стартовала retry, первая попытка — `self.connect()`, который **явно ставит `manager.isEnabled = true` + save + reload + startTunnel**. То есть BBTB сам себя реактивирует **изнутри** через старый recovery path.

Fix: Plan 04 Task 3a — удаление всех `triggerRecoveryIfNeeded` callsites + добавление intent-closing на external disconnect.

### Bug E (deferred to Phase 7-8) — soft kill server

Сценарий «отключить inbound в 3x-ui панели» (не убивая sing-box процесс) не триггерит watchdog. Причина: tunnel-level handshake не падает (sing-box client пытается переподключиться к мёртвому inbound внутри туннеля), `NEVPNStatus` остаётся `.connected`, watchdog не видит сигнал.

Это **feature gap, не bug**. Требует active liveness probe (periodic HTTP probe to known target, swap server после N consecutive failures). Записано в Phase 7-8 backlog как `NET-12: active liveness probe`. Phase 6c покрывает только tunnel-level disconnect events.

## Lessons learned

1. **Parallel-run window — не free safety net.** Изначально оставлять старую machinery работать рядом казалось «rollback safety». На практике параллельная работа двух reconnect paths создаёт race conditions и UI inconsistencies, которые гораздо сложнее диагностировать чем clean cutover. **Делай cutover atomically; rollback держи через git revert, не через runtime co-existence.**

2. **Triple-reviewer APPROVE ≠ runtime-correct.** Static plan review (даже Codex+Gemini+internal triple) ловит structural gaps, но не симулирует actor reentrance или OS-specific NEVPNStatus sequencing. **UAT на реальном iOS-устройстве с реальными conditions (другие VPN apps, Settings disable, network churn) — обязательный gate**, не опциональный.

3. **Actor reentrance — реальная угроза для hot paths.** Любой `await` в actor-методе отпускает actor, позволяя другим operations interleave. Если patch добавляет `await` в путь, обработанный assumption синхронного выполнения — нужны **post-await re-checks**, не только pre-await guards.

4. **`isOnDemandEnabled` ≠ user toggle.** Это **низкоуровневый switch для OS evaluator**, не пользовательская настройка. Пользовательский toggle (`autoReconnectEnabled`) — отдельная UserDefaults `app.bbtb.autoReconnectEnabled`. Финальный флаг = toggle && intent. Семантическая путаница между этими двумя — источник Bug B и phantom-connect rollback'а.

5. **Apple's framework respects `isEnabled = false`.** Когда iOS флипает `manager.isEnabled = false` (другой VPN активировался ИЛИ пользователь в Settings выключил профиль), Apple's on-demand evaluator skip'ает наш профиль. **Если BBTB всё равно подключается** — это BBTB code re-enabling от себя (через connect call), а не Apple игнорирующий disabled state. **Проверка: grep `manager.isEnabled = true` в production коде.**

## Operational план (`.planning/`)

Оперативные артефакты Phase 6c — в `.planning/phases/06c-on-demand-migration/`:

- `06C-CONTEXT.md` — 25 locked D-decisions (D-01..D-22 + D-17b/c + D-24)
- `06C-RESEARCH.md` — 10 runtime pitfalls + 7 open questions resolved, WireGuard/sing-box reference patterns
- `06C-01-PLAN.md` ... `06C-05-PLAN.md` — 5 atomic waves
- `06C-01-SUMMARY.md` ... `06C-04-TASK1-NOTES.md` — wave-by-wave outcomes
- `06C-REVISION-LOG.md` — Round 1-5 history (planning revisions + UAT discoveries + architect pivot)
- `06C-ARCHITECT-R5.md` — Codex GPT-5.2 architect review с pull-cleanup-forward decision
- `06C-REVIEWS-R2-INTERNAL.md` + `R2-CODEX.md` + `R3-CODEX.md` + `R3-GEMINI.md` — triple-reviewer APPROVE Round 2-3 records
- `06C-PLANNER-REVISION-BRIEF.md` — Round 2 revision brief для planner agent

## Open items / next phases

- **macOS validation** — deferred к более позднему циклу (iOS-only focus в Phase 6c)
- **Liveness probe** (`NET-12`) — Phase 7-8 backlog. Triggers server failover при protocol-level failures когда tunnel-level handshake остаётся up
- **Apple's `NEEvaluateConnectionRule`** для per-SSID/per-domain rules — Phase 8 Rules Engine territory. `OnDemandRulesBuilder.buildRules()` private hook готов к prepend новых rules перед catch-all `.any` (W-08 ordering contract documented)
- **"Resume after other VPN disconnects"** — opt-in feature, если UX потребует (можно делать через wake observer-style poll на `manager.isEnabled` transitioning false→true)

## Related pages

- [[apple-detection-surface]] — поверхность атрибутирования через Apple-managed APIs
- [[architecture]] — общая архитектура BBTB
- [[release-roadmap]] — где Phase 6c в общем плане релизов
- [[product-overview]] — user-facing описание продукта
