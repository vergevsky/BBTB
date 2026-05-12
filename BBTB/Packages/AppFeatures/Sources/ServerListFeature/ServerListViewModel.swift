// ServerListViewModel.swift — Phase 3 / Plan 03 / Task 1 (skeleton + groupSections),
// Task 2 (onAppear/loadFromStore/pingAllServers).
//
// @MainActor ObservableObject (pattern из MainScreenFeature.MainScreenViewModel).
// Координируется с MainScreenViewModel через ServerSelectionCoordinating protocol —
// избегаем reverse module dependency.
//
// Pure-function `groupSections(...)` static — testable без instantiation, без касания
// SwiftData / @Published. Это контракт SectionGroupingTests.

import Foundation
import SwiftUI
import SwiftData
import VPNCore

/// Секция server-list. id = "manual" для virtual orphan-секции; subscription.id.uuidString иначе.
public struct ServerListSection: Identifiable, Equatable {
    public let id: String
    public let subscription: Subscription?
    public let servers: [ServerConfig]

    public init(id: String, subscription: Subscription?, servers: [ServerConfig]) {
        self.id = id
        self.subscription = subscription
        self.servers = servers
    }

    public static func == (lhs: ServerListSection, rhs: ServerListSection) -> Bool {
        lhs.id == rhs.id && lhs.servers.map(\.id) == rhs.servers.map(\.id)
    }
}

@MainActor
public final class ServerListViewModel: ObservableObject {

    // MARK: Published state

    @Published public private(set) var state: ServerListState = .loading
    @Published public private(set) var sections: [ServerListSection] = []
    @Published public private(set) var pingStates: [UUID: PingState] = [:]
    @Published public var refreshError: String?
    @Published public var pendingDeleteSubscription: Subscription?

    // MARK: Dependencies

    public weak var coordinator: ServerSelectionCoordinating?

    private let modelContainer: ModelContainer
    private let probeService: ServerProbeService

    public init(modelContainer: ModelContainer, probeService: ServerProbeService) {
        self.modelContainer = modelContainer
        self.probeService = probeService
    }

    // MARK: Derived

    /// true ⇔ coordinator?.selectedServerID == nil (Auto mode).
    public var isAutoSelected: Bool {
        coordinator?.selectedServerID == nil
    }

    /// Текущий выбранный сервер (mirror coordinator).
    public var selectedServerID: UUID? {
        coordinator?.selectedServerID
    }

    /// Ping state для конкретного сервера (.idle если нет записи).
    public func pingState(for id: UUID) -> PingState {
        pingStates[id] ?? .idle
    }

    // MARK: Selection wrappers

    /// Tap на ServerRow → set selectedServerID + dismiss sheet.
    /// Plan 05: добавит reconnect-on-active-tunnel.
    public func selectServer(id: UUID) {
        coordinator?.applySelection(id)
        coordinator?.dismissServerList()
    }

    /// Tap на AutoCell → set selectedServerID = nil + dismiss.
    public func selectAuto() {
        coordinator?.applySelection(nil)
        coordinator?.dismissServerList()
    }

    /// Swipe по SubscriptionHeader → confirm dialog (Plan 04 заполнит cascade delete).
    public func requestDeleteSubscription(_ subscription: Subscription) {
        pendingDeleteSubscription = subscription
    }

    // MARK: Lifecycle

    /// Called from `.task { await viewModel.onAppear() }` в ServerListSheet.
    /// Plan 03 Task 2: load from store + ping all supported servers.
    public func onAppear() async {
        state = .loading
        await loadFromStore()
        if sections.isEmpty {
            state = .empty
            return
        }
        state = .pinging
        await pingAllServers()
        state = sections.isEmpty ? .empty : .loaded
    }

    /// Загрузка Subscription + ServerConfig из SwiftData store и группировка через
    /// pure-function `groupSections`.
    private func loadFromStore() async {
        let context = ModelContext(modelContainer)
        let subsDescriptor = FetchDescriptor<Subscription>()
        let serversDescriptor = FetchDescriptor<ServerConfig>()
        let subs = (try? context.fetch(subsDescriptor)) ?? []
        let servers = (try? context.fetch(serversDescriptor)) ?? []
        sections = Self.groupSections(subscriptions: subs, servers: servers)
    }

    /// Параллельный ping всех supported серверов через `ServerProbeService.probeAll`.
    /// Прогрессивно обновляет `pingStates` по мере прихода результатов; persist'ит
    /// latency/probedAt/failedProbeCount обратно в SwiftData в конце цикла.
    private func pingAllServers() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        guard let supported = try? context.fetch(descriptor), !supported.isEmpty else { return }

        // Sendable payload tuple (Pitfall 4 — НЕ передавать [ServerConfig]).
        let payload: [(id: UUID, host: String, port: Int)] = supported.map {
            (id: $0.id, host: $0.host, port: $0.port)
        }

        // Mark all .pinging — UI отображает spinner.
        for srv in supported {
            pingStates[srv.id] = .pinging
        }

        for await (id, agg) in probeService.probeAll(payload) {
            if Task.isCancelled { break }
            if let row = supported.first(where: { $0.id == id }) {
                row.lastLatencyMs = agg.avgLatencyMs
                row.lastPingedAt = agg.probedAt
                row.failedProbeCount = Int(agg.lossRate * 3)
            }
            pingStates[id] = .completed(agg)
        }

        try? context.save()
    }

    // MARK: Pure function — testable groupSections

    /// Группировка серверов по subscriptionID в [ServerListSection]:
    /// - Subscription sections в порядке `lastFetched` DESC (nil → last).
    /// - Пустые subscription-секции (без серверов) исключаются.
    /// - Manual («Добавлены вручную») секция последняя, появляется только если
    ///   есть orphan-серверы с subscriptionID == nil.
    ///
    /// Public static + Sendable-friendly inputs (взяты `ServerConfig` и `Subscription`
    /// массивами с `@MainActor` контекста — функция вызывается только из `@MainActor`).
    ///
    /// `nonisolated` — pure function, не касается @Published state; вызывается также
    /// из тестов в nonisolated XCTestCase контексте.
    public nonisolated static func groupSections(
        subscriptions: [Subscription],
        servers: [ServerConfig]
    ) -> [ServerListSection] {
        // Подписки сортируем по lastFetched DESC; nil идёт последним.
        let sortedSubs = subscriptions.sorted { lhs, rhs in
            switch (lhs.lastFetched, rhs.lastFetched) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true   // lhs newer
            case (nil, _?):    return false  // rhs newer
            case (nil, nil):   return false
            }
        }

        var result: [ServerListSection] = []
        for sub in sortedSubs {
            let mine = servers.filter { $0.subscriptionID == sub.id }
            guard !mine.isEmpty else { continue }
            result.append(ServerListSection(
                id: sub.id.uuidString,
                subscription: sub,
                servers: mine
            ))
        }

        let orphans = servers.filter { $0.subscriptionID == nil }
        if !orphans.isEmpty {
            result.append(ServerListSection(
                id: "manual",
                subscription: nil,
                servers: orphans
            ))
        }

        return result
    }
}
