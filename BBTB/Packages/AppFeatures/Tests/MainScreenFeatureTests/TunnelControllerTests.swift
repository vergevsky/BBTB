// TunnelControllerTests.swift — Phase 6c / Plan 06C-04 / Task 3c.
//
// D-24 category 2 — contract tests для slim TunnelController, который выжил
// после Task 3a cleanup. Покрываем `connect()` / `disconnect()` / observer
// wiring без real-VPN entitlements: actor isolation, intent-store mutation,
// failover-provider invocation, watchdog forwarding, idempotency
// `startReachability`.
//
// Этот файл заменяет удалённый `TunnelControllerStateTests.swift` (Wave 5
// Phase 6 + Phase 6c parallel-run версия). Старые test seams (`_setX...`,
// `getX...`) удалены вместе с custom-reconnect machinery; новые тесты
// driveят public surface через injected mocks.
//
// **Round 2 W-01 / B-08 split:** новый файл = `TunnelControllerTests.swift`,
// удалённый = `TunnelControllerStateTests.swift`. Они не сосуществуют ни в
// одном коммите.
//
// **Round 5 carve-out:** `connectInProgress` + `manualDisconnectInProgress`
// флаги остаются `internal var` в production code (intent-closing gate в
// `handleStatusChange`). Тесты не дёргают эти флаги напрямую — поведение
// проверяется через `connect()` / `disconnect()` invocations.
//
// **InstantReconnectClock + cross-target seams:** Watchdog тестам нужны fast
// clocks, но `TunnelControllerTests` сами по себе не используют clock;
// `setWatchdog` принимает уже сконструированный watchdog. Используем real
// `TunnelWatchdog` с `InstantReconnectClock` из `TestClocks.swift`.

import XCTest
import NetworkExtension
@testable import MainScreenFeature

final class TunnelControllerTests: XCTestCase {

    // MARK: - Test doubles

    /// Sendable holder для `NEVPNStatus` (передаётся в `FakeStatusProvider`).
    /// `NEVPNStatus` сам по себе — Int-backed enum, Sendable; обёртка нужна,
    /// чтобы тесты могли менять значение без race condition.
    final class StatusBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: NEVPNStatus = .invalid
        func set(_ s: NEVPNStatus) {
            lock.lock(); defer { lock.unlock() }
            value = s
        }
        func get() -> NEVPNStatus {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }

    /// Минимальный `VPNStatusProviding` для DI. Не используется напрямую в
    /// проверяемых сценариях (slim TunnelController не консультирует provider
    /// в `connect`/`disconnect` — он ходит в `NETunnelProviderManager`
    /// напрямую), но требуется для конструктора.
    final class FakeStatusProvider: VPNStatusProviding, @unchecked Sendable {
        let box: StatusBox
        init(box: StatusBox = StatusBox()) { self.box = box }
        func currentStatus() async -> NEVPNStatus { box.get() }
    }

    /// Spy `FailoverProviding` — фиксирует `resetCycle()` и `nextServerAttempt`
    /// invocations. Реализован как `actor`, чтобы быть Sendable без `@unchecked`.
    actor SpyFailoverProvider: FailoverProviding {
        private(set) var resetCount = 0
        private(set) var nextCount = 0
        private var stub: (serverName: String, attempt: @Sendable () async throws -> Date)?

        func setStub(_ stub: (serverName: String, attempt: @Sendable () async throws -> Date)?) {
            self.stub = stub
        }
        func nextServerAttempt() async -> (serverName: String, attempt: @Sendable () async throws -> Date)? {
            nextCount += 1
            return stub
        }
        func resetCycle() async {
            resetCount += 1
        }
        func getResetCount() -> Int { resetCount }
        func getNextCount() -> Int { nextCount }
    }

    // MARK: - Helpers

    /// Per-test изолированный `UserIntentStore` — prevents cross-test leakage
    /// через persisted `userIntendedConnected`. Уникальный suite name на
    /// каждый вызов, синхронно удаляется в tearDown.
    private func makeIsolatedIntentStore(suiteName: String = "TunnelControllerTests-\(UUID().uuidString)")
        -> (store: UserIntentStore, suite: String)
    {
        let defaults = UserDefaults(suiteName: suiteName)!
        return (UserIntentStore(defaults: defaults), suiteName)
    }

    private func clearSuite(_ name: String) {
        let defaults = UserDefaults(suiteName: name)
        defaults?.removePersistentDomain(forName: name)
    }

    private func makeController(
        statusProvider: VPNStatusProviding = FakeStatusProvider(),
        failoverProvider: FailoverProviding = NoFailoverProvider(),
        intentStore: UserIntentStore? = nil
    ) -> (controller: TunnelController, suiteCleanup: () -> Void) {
        let (store, suite) = makeIsolatedIntentStore()
        let actualStore = intentStore ?? store
        let controller = TunnelController(
            statusProvider: statusProvider,
            failoverProvider: failoverProvider,
            intentStore: actualStore
        )
        return (controller, { self.clearSuite(suite) })
    }

    // MARK: - Tests

    /// Test 1 — `connect()` бросает, когда `NETunnelProviderManager.loadAllFromPreferences()`
    /// возвращает пустой массив (никакого VPN-профиля нет). В XCTest sandbox
    /// без entitlements этот путь — реальный поведенческий контракт: запуск
    /// без импорта конфига должен fail-fast с понятным error message.
    func testConnectThrowsWhenNoManagerExists() async {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        do {
            _ = try await controller.connect()
            XCTFail("connect() должен бросить, когда VPN-профиль не установлен")
        } catch let error as NSError {
            XCTAssertEqual(error.domain, "BBTB.TunnelController",
                           "Domain должен быть BBTB.TunnelController")
            // code = -1 (No VPN profile) либо -2 (status проверка после save).
            // В XCTest без entitlements `loadAllFromPreferences()` обычно
            // возвращает пустой массив → попадаем в `code = -1`.
            XCTAssertTrue(error.code == -1 || error.code == -2,
                          "Expected code -1 or -2, got \(error.code)")
        } catch {
            XCTFail("Expected NSError, got \(type(of: error)): \(error)")
        }
    }

    /// Test 2 — `disconnect()` НЕ бросает, когда manager отсутствует. Это
    /// preservation контракт из Phase 1–5: повторный disconnect / disconnect
    /// без active session — silent no-op, не error. Slim Task 3a code path:
    /// `guard let manager = managers.first else { scheduleClearManualDisconnect(); return }`
    func testDisconnectDoesNotThrowWhenNoManagerExists() async {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        do {
            try await controller.disconnect()
        } catch {
            XCTFail("disconnect() без manager должен быть no-op, не throw. Got: \(error)")
        }
    }

    /// Test 3 — `setWatchdog` затем `disconnect()` — watchdog получает
    /// `setUserIntent(false)`. Проверяем forwarding contract: command methods
    /// (connect/disconnect) транзитивно обновляют watchdog state. После
    /// `disconnect()` watchdog `userIntent` должен быть false.
    ///
    /// Точно так же `connect()` бы выставил `userIntent=true`, но `connect()` в
    /// тестовом окружении бросает на `loadAllFromPreferences()` ДО точки
    /// возврата — что усложняет проверку. `disconnect()` проще: `setUserIntent(false)`
    /// вызывается ДО первого `try await NETunnelProviderManager.loadAllFromPreferences()`,
    /// поэтому даже если NE кидает, watchdog уже получил уведомление.
    func testSetWatchdogThenDisconnectForwardsUserIntentFalse() async {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        // Real TunnelWatchdog — public API consumers: `setUserIntent(_:)` +
        // `getUserIntentForTest()`. Не нужно мокать; watchdog actor-isolated
        // и instant-clock делает thresholds моментальными.
        let failover = SpyFailoverProvider()
        let watchdog = TunnelWatchdog(
            failoverProvider: failover,
            clock: InstantReconnectClock()
        )
        // Pre-arrange: user intent = true (как если был успешный connect).
        await watchdog.setUserIntent(true)
        let before = await watchdog.getUserIntentForTest()
        XCTAssertTrue(before, "Precondition: userIntent должен быть true перед disconnect")

        await controller.setWatchdog(watchdog)
        try? await controller.disconnect()

        let after = await watchdog.getUserIntentForTest()
        XCTAssertFalse(after, "disconnect() должен forward setUserIntent(false) в watchdog")
    }

    /// Test 4 — `startReachability()` идемпотентен. Два последовательных
    /// вызова не должны crash'ить или дублировать NotificationCenter observers.
    /// Контракт Phase 6c: первый вызов — install observer + initial seed;
    /// последующие — early return.
    func testStartReachabilityIsIdempotent() async {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        await controller.startReachability()
        await controller.startReachability()  // должен быть no-op
        // Clean-up — иначе observers подвешены до конца test target.
        await controller.stopReachability()

        // Если бы был crash — мы сюда не дошли бы. Двойной `stopReachability`
        // тоже должен быть безопасен.
        await controller.stopReachability()
        // Pass — отсутствие throw/crash = успех.
    }

    /// Test 5 — `disconnect()` вызывает `failoverProvider.resetCycle()`. D-08
    /// контракт: явный пользовательский disconnect сбрасывает failover курсор,
    /// чтобы следующий connect стартовал с первого сервера в пуле, а не с
    /// середины round-robin.
    func testDisconnectResetsFailoverCycle() async {
        let spy = SpyFailoverProvider()
        let (controller, cleanup) = makeController(failoverProvider: spy)
        defer { cleanup() }

        try? await controller.disconnect()

        let count = await spy.getResetCount()
        XCTAssertEqual(count, 1, "disconnect() должен вызвать resetCycle() ровно один раз")
    }

    /// Test 6 — `disconnect()` сбрасывает `userIntendedConnected` в
    /// UserIntentStore (persisted в UserDefaults). Это критично для D-17b
    /// migration safety: если пользователь disconnect'нулся, следующий
    /// app launch не должен авто-реконнектить.
    ///
    /// `disconnect()` бросает на отсутствии NEManager, но `setUserIntendedConnected(false)`
    /// вызывается ДО `loadAllFromPreferences()` — flag mutation гарантирована.
    func testDisconnectClearsUserIntendedConnected() async {
        let (store, suite) = makeIsolatedIntentStore()
        defer { clearSuite(suite) }
        // Pre-arrange: user previously consented.
        store.save(true)
        XCTAssertTrue(store.load(), "Precondition: intent должен быть true")

        let (controller, _) = makeController(intentStore: store)
        // Second cleanup тот же suite — no-op (already cleaned by defer above).

        try? await controller.disconnect()

        XCTAssertFalse(store.load(),
                       "disconnect() должен очистить persisted userIntendedConnected")
    }

    /// Test 7 (extra, robustness) — `disconnect()` forward работает даже если
    /// watchdog не был привязан через `setWatchdog`. Slim Task 3a: `watchdog`
    /// — optional, `await watchdog?.setUserIntent(false)` — graceful no-op.
    func testDisconnectWithoutWatchdogDoesNotThrow() async {
        let (controller, cleanup) = makeController()
        defer { cleanup() }

        // No setWatchdog call — watchdog stays nil.
        do {
            try await controller.disconnect()
        } catch {
            XCTFail("disconnect() без watchdog должен быть graceful, не throw. Got: \(error)")
        }
    }

    /// **Plan 09 L-A3-4-02 (closes ExternalVPNStopMarker key-drift LOW):**
    /// Host-side `TunnelController.swift` internal ExternalVPNStopMarker
    /// duplicates suite + keys от PacketTunnelKit's public ExternalVPNStopMarker
    /// (avoid pulling extension-only symbols). This test exercises the host
    /// internal API — `isPending()` — после writing pinned raw key.
    /// If the host's internal `pendingKey` constant drifts, isPending() won't
    /// recognise our pinned write → test fails.
    ///
    /// Matching mirror test в PacketTunnelKit verifies extension-side
    /// (`ExternalVPNStopMarker.mark()` writes к pinned keys).
    ///
    /// Long-term fix: extract shared constants к VPNCore. Tracked в wiki «v1.1+».
    func test_L_A3_4_02_externalVPNStopMarker_keys_pinned() {
        let suite = UserDefaults(suiteName: "group.app.bbtb.shared")
        XCTAssertNotNil(suite, "App Group suite must be reachable")

        let expectedPendingKey = "app.bbtb.externalVPNStop.pending"
        let expectedTimestampKey = "app.bbtb.externalVPNStop.timestamp"

        // Cleanup before/after — host internal `clear()` covers same суite+keys.
        ExternalVPNStopMarker.clear()
        defer { ExternalVPNStopMarker.clear() }

        // Write directly к pinned raw keys. If host's internal `pendingKey` /
        // `timestampKey` constants drift, isPending() reads OTHER keys → false
        // → test fails. This proves host internal constants STILL match
        // pinned values.
        let now = Date().timeIntervalSince1970
        suite?.set(true, forKey: expectedPendingKey)
        suite?.set(now, forKey: expectedTimestampKey)

        XCTAssertTrue(ExternalVPNStopMarker.isPending(maxAge: 600),
                      "Plan 09 L-A3-4-02: host ExternalVPNStopMarker.isPending() must read " +
                      "pinned `app.bbtb.externalVPNStop.pending` key — drift в TunnelController.swift " +
                      "internal constants would silently break extension↔host disconnect-intent signal.")
    }
}
