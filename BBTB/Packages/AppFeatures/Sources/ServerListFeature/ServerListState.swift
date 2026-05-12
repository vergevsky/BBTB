// ServerListState.swift — Phase 3 / Plan 03 / Task 1.
//
// Enum-FSM для ServerListSheet (UI-SPEC §1.3). Pattern аналогичный MainScreenFeature.ConnectionState.
//
// State transitions:
//   loading → loaded (после onAppear + первый ping cycle)
//   loaded → pinging (при ручном retry — Plan 04)
//   loaded → refreshing (при pull-to-refresh — Plan 04)
//   refreshing → loaded | refreshError(_)
//   loaded → empty (после удаления всех серверов — Plan 04)

import Foundation

public enum ServerListState: Equatable {
    case loading
    case loaded
    case pinging
    case refreshing
    case refreshError(String)
    case empty
}
