// ReconnectClock.swift — Phase 6c / Plan 06C-03 / Round 2 B-01.
//
// Extracted из `ReconnectStateMachine.swift` чтобы выжить после Plan 06C-04
// Task 3c cleanup, который удалит сам файл ReconnectStateMachine.swift.
//
// Protocol + production-clock — semantic no-op move: signature и body идентичны
// прежним declarations в `ReconnectStateMachine.swift` (lines 36–46 в Phase 6 версии).
// Consumer'ы (`TunnelController.reconnectClock`, новый `TunnelWatchdog` из Plan 06C-03
// Task 3, любые будущие compositions) импортируют этот тип через `MainScreenFeature`
// — никаких изменений import-statement не требуется (same module).
//
// **Parallel-run invariant:** ReconnectStateMachine class сам ОСТАЁТСЯ в
// `ReconnectStateMachine.swift` до Plan 06C-04 Task 3c, когда custom-reconnect
// machinery будет удалена в пользу OS-managed on-demand reconnect (Phase 6c).
// Этот файл (ReconnectClock.swift) переживёт удаление, обеспечивая зависимость
// TunnelWatchdog'у.
//
// См. `.planning/phases/06c-on-demand-migration/06C-REVISION-LOG.md` § B-01
// для полного контекста почему extract произошёл в Plan 03 Task 2.5, а не вместе
// с cleanup в Plan 04.

import Foundation

// MARK: - Clock protocol (test seam)

/// Abstraction over async sleeps so consumers can be tested without
/// burning real wall-clock seconds. Production uses `SystemReconnectClock`.
public protocol ReconnectClock: Sendable {
    func sleep(seconds: Int) async throws
}

/// Production clock — delegates to `Task.sleep(nanoseconds:)`.
public struct SystemReconnectClock: ReconnectClock {
    public init() {}
    public func sleep(seconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(seconds, 0)) * 1_000_000_000)
    }
}
