// ServerListViewModel.swift — Phase 3 / Plan 03 + Plan 04.
//
// @MainActor ObservableObject (pattern из MainScreenFeature.MainScreenViewModel).
// Координируется с MainScreenViewModel через ServerSelectionCoordinating protocol —
// избегаем reverse module dependency.
//
// Pure-function `groupSections(...)` static — testable без instantiation, без касания
// SwiftData / @Published. Это контракт SectionGroupingTests.
//
// Plan 04 ADD:
// - pullToRefresh / silentForegroundRefresh — 2-phase (D-13: fetch all → ping all),
//   structured concurrency only (Pitfall 5).
// - deleteServer / confirmDeleteSubscription — cascade + Keychain cleanup + selection reset
//   (D-07, D-14, Pitfall 10).
// - subscriptionFetchErrors — partial-failure map (UI-SPEC §3.4 inline indicator).
// - importer + fetcher + parser DI: ConfigImporting protocol reference (без cast
//   к concrete ConfigImporter — compile-time invariant).

import Foundation
import SwiftUI
import SwiftData
import OSLog
import VPNCore
import ConfigParser
import Localization

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

    private static let log = Logger(subsystem: "app.bbtb.server-list", category: "viewmodel")

    // MARK: Published state

    @Published public private(set) var state: ServerListState = .loading
    @Published public private(set) var sections: [ServerListSection] = []
    @Published public private(set) var pingStates: [UUID: PingState] = [:]
    @Published public var refreshError: String?
    @Published public var pendingDeleteSubscription: Subscription?

    /// Plan 04 — UI-SPEC §3.4: inline fetch-error indicator на SubscriptionHeader.
    /// Map sub.id → localized message. Очищается в начале каждого pullToRefresh.
    @Published public private(set) var subscriptionFetchErrors: [UUID: String] = [:]

    // MARK: Dependencies

    public weak var coordinator: ServerSelectionCoordinating?

    private let modelContainer: ModelContainer
    private let probeService: ServerProbing
    private let importer: ConfigImporting
    private let fetcher: SubscriptionURLFetching
    private let parser: UniversalImportParsing

    /// Plan 04 init (полный DI). `fetcher`/`parser`/`importer` обязательны для pull-to-refresh
    /// и cascade-delete (последний — через ConfigImporting protocol reference).
    public init(modelContainer: ModelContainer,
                probeService: ServerProbing,
                importer: ConfigImporting,
                fetcher: SubscriptionURLFetching = DefaultSubscriptionURLFetcher(),
                parser: UniversalImportParsing = UniversalImportParser())
    {
        self.modelContainer = modelContainer
        self.probeService = probeService
        self.importer = importer
        self.fetcher = fetcher
        self.parser = parser
    }

    // MARK: Derived

    public var isAutoSelected: Bool { coordinator?.selectedServerID == nil }

    public var selectedServerID: UUID? { coordinator?.selectedServerID }

    public func pingState(for id: UUID) -> PingState {
        pingStates[id] ?? .idle
    }

    /// UI-SPEC §6.1 — confirmation message требует subscriptionServerCount.
    public var pendingDeleteSubscriptionServerCount: Int {
        guard let sub = pendingDeleteSubscription else { return 0 }
        let context = ModelContext(modelContainer)
        let allDesc = FetchDescriptor<ServerConfig>()
        return (try? context.fetch(allDesc).filter { $0.subscriptionID == sub.id }.count) ?? 0
    }

    // MARK: Selection wrappers

    public func selectServer(id: UUID) {
        coordinator?.applySelection(id)
        coordinator?.dismissServerList()
    }

    public func selectAuto() {
        coordinator?.applySelection(nil)
        coordinator?.dismissServerList()
    }

    public func requestDeleteSubscription(_ subscription: Subscription) {
        pendingDeleteSubscription = subscription
    }

    // MARK: Lifecycle

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

    /// Plan 04 — pull-to-refresh:
    /// (1) fetch all subscription URLs SEQUENTIALLY (D-13 — fully completes phase 1),
    /// (2) ping all supported servers (D-13 phase 2).
    /// Structured concurrency only — никаких unstructured `Task { ... }` (Pitfall 5).
    public func pullToRefresh() async {
        state = .refreshing
        subscriptionFetchErrors = [:]
        refreshError = nil

        let context = ModelContext(modelContainer)
        let subDesc = FetchDescriptor<Subscription>()
        let subscriptions = (try? context.fetch(subDesc)) ?? []

        // Phase 1: sequential fetch + merge per subscription.
        for sub in subscriptions {
            if Task.isCancelled { break }
            do {
                try await fetchAndMerge(sub: sub, in: context)
            } catch {
                subscriptionFetchErrors[sub.id] = error.localizedDescription
                Self.log.error("pullToRefresh fetch failed for \(sub.url, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        try? context.save()

        // Если все fetch failed (и subscriptions не пустой) — выставляем .refreshError.
        if !subscriptions.isEmpty && subscriptionFetchErrors.count == subscriptions.count {
            let msg = L10n.serverListRefreshErrorMessage
            refreshError = msg
            state = .refreshError(msg)
        }

        // Refresh sections (могут быть добавлены/удалены rows).
        await loadFromStore()

        // Phase 2: ping all (даже если все fetch failed — пинг existing servers).
        await pingAllServers()

        // Final state — preserve .refreshError если был, иначе .loaded / .empty.
        if case .refreshError = state {
            // оставляем .refreshError видимым
        } else {
            state = sections.isEmpty ? .empty : .loaded
        }
    }

    /// Plan 04 — foreground refresh (scenePhase .active → silent re-fetch).
    /// Идентично pullToRefresh, но НЕ меняет state (.loaded остаётся .loaded) и
    /// silent error logging (без UI alert).
    public func silentForegroundRefresh() async {
        // Save current state — не трогаем.
        let savedState = state
        let context = ModelContext(modelContainer)
        let subDesc = FetchDescriptor<Subscription>()
        let subscriptions = (try? context.fetch(subDesc)) ?? []

        for sub in subscriptions {
            if Task.isCancelled { break }
            do {
                try await fetchAndMerge(sub: sub, in: context)
            } catch {
                Self.log.info("silentForegroundRefresh: fetch failed silently for \(sub.url, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        try? context.save()

        await loadFromStore()
        await pingAllServers()

        // Restore state, не трогая .refreshing — silent flow.
        state = savedState
    }

    /// Plan 04 — Pitfall 10: cascade-delete one server + Keychain cleanup + selection reset.
    public func deleteServer(id: UUID) async {
        let context = ModelContext(modelContainer)
        let desc = FetchDescriptor<ServerConfig>(predicate: #Predicate { $0.id == id })
        guard let srv = try? context.fetch(desc).first else {
            Self.log.warning("deleteServer: no row for id=\(id, privacy: .public)")
            return
        }
        if let tag = srv.keychainTag, !tag.isEmpty {
            try? KeychainStore.delete(tag: tag)
        }
        context.delete(srv)
        try? context.save()

        if coordinator?.selectedServerID == id {
            coordinator?.applySelection(nil)
        }

        await loadFromStore()
    }

    /// Plan 04 — D-07 cascade-delete Subscription + linked ServerConfigs + Keychain cleanup.
    public func confirmDeleteSubscription(_ subscription: Subscription) async {
        let context = ModelContext(modelContainer)
        let allDesc = FetchDescriptor<ServerConfig>()
        let linked = ((try? context.fetch(allDesc)) ?? []).filter { $0.subscriptionID == subscription.id }
        let linkedIDs = Set(linked.map(\.id))

        for srv in linked {
            if let tag = srv.keychainTag, !tag.isEmpty {
                try? KeychainStore.delete(tag: tag)
            }
            context.delete(srv)
        }
        // CR-02 — same-context delete only. Subscription row look up по id
        // в нашем local `context`. Если row не найден — подписка уже удалена
        // (concurrent delete или non-persisted), НЕ удаляем caller's foreign-context
        // объект напрямую: caller's `subscription` может быть из чужого ModelContext,
        // что в SwiftData = undefined behaviour (crash на save или silent no-op).
        let lookupID: UUID = subscription.id
        let subRowDesc = FetchDescriptor<Subscription>(predicate: #Predicate { $0.id == lookupID })
        guard let row = try? context.fetch(subRowDesc).first else {
            Self.log.warning("confirmDeleteSubscription: subscription \(lookupID, privacy: .public) already deleted; skipping cross-context delete")
            try? context.save()
            if let selected = coordinator?.selectedServerID, linkedIDs.contains(selected) {
                coordinator?.applySelection(nil)
            }
            pendingDeleteSubscription = nil
            await loadFromStore()
            return
        }
        context.delete(row)
        try? context.save()

        if let selected = coordinator?.selectedServerID, linkedIDs.contains(selected) {
            coordinator?.applySelection(nil)
        }

        pendingDeleteSubscription = nil
        await loadFromStore()
    }

    // MARK: Internals

    private func loadFromStore() async {
        let context = ModelContext(modelContainer)
        let subsDescriptor = FetchDescriptor<Subscription>()
        let serversDescriptor = FetchDescriptor<ServerConfig>()
        let subs = (try? context.fetch(subsDescriptor)) ?? []
        let servers = (try? context.fetch(serversDescriptor)) ?? []
        sections = Self.groupSections(subscriptions: subs, servers: servers)
    }

    private func pingAllServers() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        guard let supported = try? context.fetch(descriptor), !supported.isEmpty else { return }

        let payload: [(id: UUID, host: String, port: Int)] = supported.map {
            (id: $0.id, host: $0.host, port: $0.port)
        }

        for srv in supported { pingStates[srv.id] = .pinging }

        for await (id, agg) in probeService.probeAll(payload) {
            if Task.isCancelled { break }
            if let row = supported.first(where: { $0.id == id }) {
                row.lastLatencyMs = agg.avgLatencyMs
                row.lastPingedAt = agg.probedAt
                row.failedProbeCount = agg.failures
            }
            pingStates[id] = .completed(agg)
        }
        try? context.save()
        // Reset any servers that didn't receive a result (task cancelled mid-flight)
        // so LatencyBadge doesn't spin indefinitely.
        for id in pingStates.keys where pingStates[id] == .pinging {
            pingStates[id] = .idle
        }
    }

    /// Plan 04 — fetch one subscription + parse body + merge into pool.
    /// Throws на fetch failures (caller — pullToRefresh — фиксирует в subscriptionFetchErrors).
    /// **CRITICAL** — вызывает Keychain/build helpers через `importer` protocol reference,
    /// без cast'ов к concrete ConfigImporter.
    private func fetchAndMerge(sub: Subscription, in context: ModelContext) async throws {
        guard let url = URL(string: sub.url) else {
            throw URLError(.badURL)
        }
        let fetched = try await fetcher.fetch(url: url)
        let bodyStr = String(data: fetched.body, encoding: .utf8) ?? ""
        let parseResult = try await parser.import(rawInput: bodyStr, source: .subscriptionURL(url))

        let importerRef = importer
        try SubscriptionMergeService.merge(
            fetchedSupported: parseResult.supported,
            fetchedUnsupported: parseResult.unsupported,
            into: sub,
            context: context,
            persistKeychain: { server in
                try importerRef.persistKeychainSecret(for: server)
            },
            buildServerConfig: { server, id, subID, tag in
                importerRef.buildServerConfig(from: server, id: id, subscriptionID: subID, keychainTag: tag)
            }
        )
    }

    // MARK: Pure function — testable groupSections

    public nonisolated static func groupSections(
        subscriptions: [Subscription],
        servers: [ServerConfig]
    ) -> [ServerListSection] {
        let sortedSubs = subscriptions.sorted { lhs, rhs in
            switch (lhs.lastFetched, rhs.lastFetched) {
            case let (l?, r?): return l > r
            case (_?, nil):    return true
            case (nil, _?):    return false
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
