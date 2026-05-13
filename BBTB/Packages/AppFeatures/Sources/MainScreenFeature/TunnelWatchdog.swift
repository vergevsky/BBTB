// TunnelWatchdog.swift — Phase 6c / Plan 06C-03 / Task 3.
//
// Узко-целевой actor для mid-session failover. Запускается параллельно
// Apple's on-demand reconnect (Phase 6c в parallel-run mode); закрывает gap
// «сервер ушёл в downtime во время stable session» — Apple retry'ит тот же
// (теперь мёртвый) сервер, а watchdog знает о пуле и переключает на следующий
// через `SwiftDataFailoverProvider.nextServerAttempt`.
//
// Reference decisions (.planning/phases/06c-on-demand-migration/06C-CONTEXT.md):
// - **D-08:** четыре gate'а — stable session ≥ 30s, status .disconnected,
//   managerEnabled (cached snapshot, passed in — NOT read inside watchdog),
//   userIntent true. Все четыре должны быть выполнены для firing.
// - **D-09:** watchdog вызывает `FailoverProviding.nextServerAttempt` и
//   исполняет returned `attempt` closure. `SwiftDataFailoverProvider` ведёт
//   round-robin курсор; nil = пул исчерпан.
// - **D-10:** 3-секундный debounce после `.disconnected` — даёт Apple's
//   on-demand шанс сам реконнектиться (Pitfall 10). Cancellation:
//   - `.connecting` → отмена (Round 1).
//   - `.reasserting` → отмена (Round 2 W-05 expansion — iOS 26+ путь).
//   - `.connected` → отмена (post-reconnect cleanup).
//
// **Pitfall 5 (RESEARCH):** parallel-run window — watchdog + старый
// custom-reconnect ReconnectStateMachine оба могут реагировать на тот же
// `.disconnected`. Это accepted race — UAT-Task E (Plan 06C-04 Wave 3)
// проверит manifest. Plan 06C-04 Task 3c удалит ReconnectStateMachine.
//
// **Pitfall 10 (RESEARCH):** Apple's on-demand имеет ~3s reconnect window.
// Debounce защищает от double-failover (мы reconnect'имся к next, Apple
// уже подняла tunnel к old — race condition).
//
// **XPC-free invariant:** этот actor НЕ делает XPC trips. Все статусы
// (`NEVPNStatus`, `managerEnabled`) приходят как arguments. Сборщик статусов
// — `NEVPNStatusDidChange` observer в TunnelController (Plan 06C-04 Wave 3
// wiring), который читает status напрямую из `notification.object` без
// вызова preferences-load API (см. TunnelController конкретную реализацию).
//
// **Round 2 B-01:** использует `ReconnectClock` из `ReconnectClock.swift`
// (extracted в Task 2.5). После Plan 06C-04 Task 3c удаления
// `ReconnectStateMachine.swift` watchdog продолжит работать без изменений.
//
// **Cycle prevention:** `failoverProvider` хранится strong. Внутри
// `SwiftDataFailoverProvider` (см. `FailoverProvider.swift`) есть
// `[weak tunnelController]` в `connect` closure → нет cycle.

import Foundation
import NetworkExtension
import OSLog

public actor TunnelWatchdog {

    // MARK: - Stored properties

    private let failoverProvider: any FailoverProviding
    private let stableSessionThreshold: TimeInterval
    private let disconnectDebounce: TimeInterval
    private let clock: ReconnectClock
    private let log = Logger(subsystem: "app.bbtb.client", category: "tunnel-watchdog")

    /// True после `stableSessionThreshold` секунд непрерывного `.connected`.
    /// Сбрасывается на `setUserIntent(false)` или после firing failover.
    private var stableSession: Bool = false

    /// Pending stable-session armor task. Cancelled на re-arm / userIntent=false.
    private var stableSessionTask: Task<Void, Never>?

    /// User intent gate (D-08). Установлен в true пользователем (через
    /// caller — Plan 06C-04 wiring); false до явного Connect.
    private var userIntent: Bool = false

    /// Pending debounce task. Cancelled на .connecting / .reasserting / .connected.
    private var debounceTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        failoverProvider: any FailoverProviding,
        stableSessionThreshold: TimeInterval = 30,
        disconnectDebounce: TimeInterval = 3,
        clock: ReconnectClock = SystemReconnectClock()
    ) {
        self.failoverProvider = failoverProvider
        self.stableSessionThreshold = stableSessionThreshold
        self.disconnectDebounce = disconnectDebounce
        self.clock = clock
    }

    // MARK: - Public API

    /// Called from NEVPNStatusDidChange observer. `managerEnabled` — snapshot
    /// `manager.isEnabled` cached в caller (Plan 06C-04 Task 1 B-03 fix).
    /// Watchdog НИКОГДА не читает `manager.isEnabled` сам (XPC-free invariant).
    public func handleStatusChange(_ status: NEVPNStatus, managerEnabled: Bool) async {
        switch status {
        case .connected:
            // Cancel pending debounce — мы успешно reconnected.
            cancelDebounce()
            // Re-arm stable-session task.
            armStableSessionTask()
            log.debug("watchdog: .connected — armed stableSession task")

        case .disconnected:
            // Гейты по D-08 (все четыре должны пройти).
            guard userIntent else {
                log.debug("watchdog: .disconnected skipped — userIntent=false")
                return
            }
            guard managerEnabled else {
                log.debug("watchdog: .disconnected skipped — managerEnabled=false")
                return
            }
            guard stableSession else {
                log.debug("watchdog: .disconnected skipped — stableSession=false (no stable yet)")
                return
            }
            // Don't double-arm — если debounce уже в полёте, return.
            guard debounceTask == nil else {
                log.debug("watchdog: .disconnected — debounce already in flight, ignoring")
                return
            }
            armDebounceTask()
            log.notice("watchdog: .disconnected after stable session — armed debounce (\(self.disconnectDebounce, privacy: .public)s)")

        case .connecting:
            // Apple's on-demand выиграл race — отменяем debounce, НЕ сбрасываем stableSession.
            if debounceTask != nil {
                log.notice("watchdog: .connecting cancels debounce — Apple's on-demand winning race")
            }
            cancelDebounce()

        case .reasserting:
            // W-05 (Round 2): .reasserting тоже отменяет debounce (iOS 26+
            // путь — Apple's on-demand попадает в reasserting state до full
            // reconnect). Round 1 отменял только на .connecting.
            if debounceTask != nil {
                log.notice("watchdog: .reasserting cancels debounce — Apple's on-demand winning race (W-05)")
            }
            cancelDebounce()

        case .invalid, .disconnecting:
            // Transient — игнорируем; ждём терминальный .disconnected/.connected.
            break

        @unknown default:
            log.debug("watchdog: unknown NEVPNStatus \(String(describing: status), privacy: .public) — ignored")
        }
    }

    /// User intent gate (D-08). Установить true при user-initiated connect,
    /// false при disconnect / app launch без активного profile.
    public func setUserIntent(_ intent: Bool) async {
        userIntent = intent
        if !intent {
            // Полный сброс — пользователь явно отключился; не должно быть
            // pending tasks ни задерживающегося stableSession флага.
            cancelDebounce()
            cancelStableSessionTask()
            stableSession = false
            log.notice("watchdog: userIntent=false — full state reset")
        } else {
            log.debug("watchdog: userIntent=true")
        }
    }

    // MARK: - Internal test seams

    internal func getStableSessionForTest() -> Bool { stableSession }
    internal func getUserIntentForTest() -> Bool { userIntent }
    internal func getDebounceActiveForTest() -> Bool { debounceTask != nil }

    // MARK: - Private helpers

    /// Спавнит новый stable-session task. Cancel'ит предыдущий (re-arm safe).
    private func armStableSessionTask() {
        cancelStableSessionTask()
        let threshold = stableSessionThreshold
        let clock = self.clock
        stableSessionTask = Task { [weak self] in
            do {
                try await clock.sleep(seconds: Int(threshold))
            } catch {
                // Cancelled — silently abort.
                return
            }
            if Task.isCancelled { return }
            await self?.markStableSession()
        }
    }

    private func markStableSession() {
        stableSession = true
        stableSessionTask = nil
        log.notice("watchdog: stableSession=true after \(self.stableSessionThreshold, privacy: .public)s connected")
    }

    private func cancelStableSessionTask() {
        stableSessionTask?.cancel()
        stableSessionTask = nil
    }

    /// Спавнит debounce task. После debounce sleep — fire failover.
    private func armDebounceTask() {
        let debounce = disconnectDebounce
        let clock = self.clock
        let provider = failoverProvider
        let logger = self.log
        debounceTask = Task { [weak self] in
            do {
                try await clock.sleep(seconds: Int(debounce))
            } catch {
                // Cancelled mid-sleep — Apple's on-demand reconnect выиграл race.
                logger.debug("watchdog: debounce cancelled mid-sleep")
                return
            }
            if Task.isCancelled {
                logger.debug("watchdog: debounce cancelled post-sleep check")
                return
            }
            // Fire failover.
            await self?.fireFailover(provider: provider)
        }
    }

    private func cancelDebounce() {
        debounceTask?.cancel()
        debounceTask = nil
    }

    /// Вызывается debounce task'ом после sleep. Спрашивает failoverProvider
    /// за next attempt; executes attempt closure если non-nil.
    /// Reset stableSession=false после firing — следующий .connected re-arm'нит.
    private func fireFailover(provider: any FailoverProviding) async {
        debounceTask = nil
        stableSession = false
        guard let next = await provider.nextServerAttempt() else {
            log.notice("watchdog: failover requested but pool exhausted (nextServerAttempt returned nil)")
            return
        }
        log.notice("watchdog: firing failover to \(next.serverName, privacy: .public)")
        do {
            _ = try await next.attempt()
        } catch {
            log.error("watchdog: failover attempt threw \(String(describing: error), privacy: .public)")
        }
    }
}
