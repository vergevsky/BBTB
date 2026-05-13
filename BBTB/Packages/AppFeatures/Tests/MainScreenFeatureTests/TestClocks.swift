// TestClocks.swift — Phase 6c / Plan 06C-03 / Round 2 B-02.
//
// Extracted из `TunnelControllerStateTests.swift` (private nested `actor
// InstantReconnectClock`) чтобы выжить после Plan 06C-04 Task 3c удаления
// `TunnelControllerStateTests.swift` файла. Изменение видимости: было `private`
// (вложенный в test class), стало `internal` — теперь shared seam для всех тестов
// в этом target'е (особенно `TunnelWatchdogTests` из Plan 06C-03 Task 3).
//
// Body verbatim из старого declaration в `TunnelControllerStateTests.swift`
// (lines ~57–62): `try Task.checkCancellation()` + `await Task.yield()` —
// instant yield для тестов без burning real wall-clock seconds.

import Foundation
@testable import MainScreenFeature

/// Test clock — yields immediately so consuming code progresses but doesn't
/// burn real wall-clock seconds. Shared internal seam.
internal actor InstantReconnectClock: ReconnectClock {
    func sleep(seconds: Int) async throws {
        try Task.checkCancellation()
        await Task.yield()
    }
}
