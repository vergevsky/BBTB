// PingState.swift — Phase 3 / Plan 03 / Task 1.
//
// Per-server ping state used by ServerRow / LatencyBadge. Хранится в
// `ServerListViewModel.pingStates: [UUID: PingState]` и обновляется progressively
// по мере поступления событий из `ServerProbeService.probeAll` AsyncStream.

import Foundation
import VPNCore

public enum PingState: Equatable {
    /// Сервер ещё не пинговался в текущей сессии sheet.
    case idle
    /// Probe запущен, результата ещё нет.
    case pinging
    /// 3-probe цикл завершён; agg может содержать nil avgLatencyMs (isUnreachable).
    case completed(ProbeAggregate)
}
