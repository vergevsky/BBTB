// ServerSelectionCoordinating.swift — Phase 3 / Plan 03 / Task 1.
//
// Protocol для one-way coordination MainScreenFeature → ServerListFeature.
// MainScreenViewModel conforms к этому протоколу; ServerListViewModel держит
// `weak var coordinator: ServerSelectionCoordinating?` чтобы избегать reverse module
// dependency (ServerListFeature не должен импортировать MainScreenFeature).
//
// Plan 05 расширит: при applySelection(_:) во время active tunnel → reconnect через
// MainScreenViewModel.tunnel + ConfigImporter.provisionTunnelProfile. Plan 03 — только
// запись selectedServerID + dismiss sheet.

import Foundation

/// `@MainActor` — все члены протокола обновляют UI state (selectedServerID,
/// isPresentingServerList) и должны выполняться на main actor. Conformers
/// (MainScreenViewModel) уже @MainActor — annotation удовлетворяет ConformanceIsolation.
@MainActor
public protocol ServerSelectionCoordinating: AnyObject {
    /// Текущий выбранный сервер. nil = Авто-режим.
    var selectedServerID: UUID? { get }

    /// Применить выбор пользователя. nil = переключиться на Auto.
    /// Plan 03: пишет selectedServerID. Plan 05: + reconnect-on-active-tunnel.
    func applySelection(_ id: UUID?)

    /// Закрыть server-list sheet (isPresentingServerList = false).
    func dismissServerList()
}
