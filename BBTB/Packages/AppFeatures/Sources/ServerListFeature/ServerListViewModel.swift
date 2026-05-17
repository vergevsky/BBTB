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

    /// 2026-05-16 — collapsible sections в ServerListSheet (Figma BBTB v3 CaretDown
    /// toggle). Containing `ServerListSection.id` строки означает «свёрнута» (rows
    /// не рендерятся). Default expanded (empty set).
    @Published public var collapsedSectionIDs: Set<String> = []

    public func isCollapsed(sectionID: String) -> Bool {
        collapsedSectionIDs.contains(sectionID)
    }

    public func toggleCollapsed(sectionID: String) {
        if collapsedSectionIDs.contains(sectionID) {
            collapsedSectionIDs.remove(sectionID)
        } else {
            collapsedSectionIDs.insert(sectionID)
        }
    }

    /// Phase 6d / Wave 06D-03d (H7 fix): через `didSet` пересчитываем
    /// `pendingDeleteSubscriptionServerCount` ровно один раз при изменении
    /// pending-subscription. Все pathway покрыты:
    /// - `requestDeleteSubscription(_:)` — VM устанавливает non-nil;
    /// - `confirmDeleteSubscription(_:)` — VM очищает в nil (success + early-return);
    /// - `ServerListSheet.deleteSubscriptionBinding` — UI Cancel button очищает в nil.
    @Published public var pendingDeleteSubscription: Subscription? {
        didSet {
            refreshPendingDeleteSubscriptionServerCount()
        }
    }

    /// UI-SPEC §6.1 — confirmation message требует subscriptionServerCount.
    ///
    /// Phase 6d / Wave 06D-03d (H7 fix): stored `@Published`, пересчитывается
    /// **один раз** при изменении `pendingDeleteSubscription` через `didSet`.
    /// Раньше был computed property, который при каждом body refresh confirmationDialog
    /// создавал `ModelContext`, fetch'ил все `ServerConfig` и фильтровал в Swift —
    /// 5-10 fetch'ей/sec во время dialog animation.
    ///
    /// Фильтр по `subscriptionID == sub.id` использует fetch-all + Swift filter,
    /// потому что `ServerConfig.subscriptionID: UUID?` (Optional) — `#Predicate`
    /// с UUID? тихо возвращает empty (см. memory feedback_swiftdata_uuid_predicate.md
    /// и D-09 invariant).
    @Published public private(set) var pendingDeleteSubscriptionServerCount: Int = 0

    /// Plan 04 — UI-SPEC §3.4: inline fetch-error indicator на SubscriptionHeader.
    /// Map sub.id → localized message. Очищается в начале каждого pullToRefresh.
    @Published public private(set) var subscriptionFetchErrors: [UUID: String] = [:]

    /// Phase 5 D-17 — non-nil when user tapped chevron; triggers .navigationDestination push.
    @Published public var openServerDetail: ServerConfig? = nil

    // MARK: Dependencies

    public weak var coordinator: ServerSelectionCoordinating?

    private let modelContainer: ModelContainer
    private let probeService: ServerProbing
    private let importer: ConfigImporting
    private let fetcher: SubscriptionURLFetching
    private let parser: UniversalImportParsing

    // MARK: - Phase 6e Wave 1 M10 — idempotency guard для loadFromStore

    /// Phase 6e Wave 1 M10 (D-01 Part B) — in-progress flag. Если `loadFromStore`
    /// уже выполняется в другом await-suspension chain, повторный вызов
    /// returns immediately (без full body execution). Защищает от race на
    /// `onAppear` + `pullToRefresh` оба которые могут запуститься в пределах
    /// одного frame (SwiftUI sheet present + scenePhase active).
    private var loadInProgress: Bool = false

    /// Phase 6e Wave 1 M10 (D-01 Part B) — 100ms debounce timestamp. Subsequent
    /// `loadFromStore()` вызовы в течение этого окна skip-аются. Снижает SwiftData
    /// fetch storm на cascade-delete / pull-to-refresh hot paths.
    private var lastLoadAt: Date = .distantPast

    /// Phase 6e Wave 1 M10 — test seam. Counter инкрементится ТОЛЬКО в успешных
    /// (non-debounced, non-in-progress) executions `loadFromStore` body. Internal
    /// видимость + `@testable import` достаточно — production callers не имеют
    /// доступа. Используется в `LoadFromStoreIdempotencyTests`.
    internal private(set) var loadFromStoreCallCountForTests: Int = 0

    /// Phase 6e Wave 1 M10 — test seam reset helper. Сбрасывает counter и
    /// `lastLoadAt` в начальное состояние, чтобы каждый тест стартовал с
    /// чистого debounce window.
    internal func resetLoadFromStoreCallCountForTests() {
        loadFromStoreCallCountForTests = 0
        lastLoadAt = .distantPast
        loadInProgress = false
    }

    /// Phase 6e Wave 1 M10 — test seam, делегирует к private `loadFromStore()`.
    /// Production callers продолжают использовать прямой `loadFromStore()`
    /// через self; этот wrapper служит только @testable test access.
    internal func loadFromStoreForTests() async {
        await loadFromStore()
    }

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

    /// Phase 6d / Wave 06D-03d (H7 fix): helper, вызываемый ровно один раз из
    /// `pendingDeleteSubscription.didSet`. Один SwiftData fetch + Swift filter +
    /// count → stored `@Published pendingDeleteSubscriptionServerCount`.
    ///
    /// Когда `pendingDeleteSubscription == nil` (Cancel button / post-delete cleanup)
    /// → reset to 0 без fetch'а.
    ///
    /// `ServerConfig.subscriptionID: UUID?` — fetch-all + Swift filter (НЕ `#Predicate`
    /// с UUID?, который тихо возвращает empty; см. D-09 memory feedback).
    private func refreshPendingDeleteSubscriptionServerCount() {
        guard let sub = pendingDeleteSubscription else {
            pendingDeleteSubscriptionServerCount = 0
            return
        }
        let context = ModelContext(modelContainer)
        let allDesc = FetchDescriptor<ServerConfig>()
        pendingDeleteSubscriptionServerCount =
            (try? context.fetch(allDesc).filter { $0.subscriptionID == sub.id }.count) ?? 0
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

    // MARK: Phase 5 Wave 8 — ServerDetailView navigation (TRANSP-05)

    /// Set openServerDetail to trigger .navigationDestination push for the given server.
    public func openDetail(for server: ServerConfig) {
        openServerDetail = server
    }

    /// Factory for `ServerDetailViewModel`. Called from .navigationDestination in ServerListSheet.
    public func makeDetailViewModel(for server: ServerConfig) -> ServerDetailViewModel {
        return ServerDetailViewModel(
            server: server,
            modelContainer: modelContainer,
            configImporter: importer
        )
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

        // Refresh sections (могут быть добавлены/удалены rows). T-C7': force pull-to-refresh
        // bypass debounce — UI must reflect server-fetch result.
        await loadFromStore(force: true)

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

        // T-C7': silent foreground merge — force reload bypasses debounce
        // (mutation may have changed rows).
        await loadFromStore(force: true)
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

        // T-C7': delete mutation — force reload (UI must reflect removal immediately).
        await loadFromStore(force: true)
    }

    /// Plan 04 — D-07 cascade-delete Subscription + linked ServerConfigs + Keychain cleanup.
    ///
    /// **Phase 6e Wave 1 M10 (D-01 Part A) — single-tail-call refactor:**
    /// раньше в early-exit branch был отдельный `await loadFromStore()` (line 312)
    /// + ещё один в конце normal path (line 323) = 2 calls на cascade-delete normal
    /// path. Теперь оба flow конвергируют к ЕДИНСТВЕННОМУ tail-call в конце метода —
    /// state mutations (context.save, applySelection nil, pendingDeleteSubscription
    /// = nil) выполняются в-flow, потом ОДИН loadFromStore() для UI refresh.
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
        if let row = try? context.fetch(subRowDesc).first {
            context.delete(row)
        } else {
            Self.log.warning("confirmDeleteSubscription: subscription \(lookupID, privacy: .public) already deleted; skipping cross-context delete")
        }
        try? context.save()

        if let selected = coordinator?.selectedServerID, linkedIDs.contains(selected) {
            coordinator?.applySelection(nil)
        }

        pendingDeleteSubscription = nil
        // T-C7': cascade-delete mutation — force reload (UI must show removed
        // subscription + dependent server rows immediately).
        await loadFromStore(force: true)
    }

    // MARK: Internals

    private func loadFromStore(force: Bool = false) async {
        // Phase 6e Wave 1 M10 (D-01 Part B) — idempotency guards.
        //
        // T-C7' (closes C6'-002 MEDIUM): added `force` parameter. Mutation callers
        // (deleteServer, confirmDeleteSubscription, pullToRefresh,
        // silentForegroundRefresh) теперь pass `force: true` чтобы skip debounce —
        // post-mutation reload guaranteed to refresh `sections`. Lifecycle callers
        // (onAppear) keep `force: false` для duplicate-suppression.
        //
        // `loadInProgress` guard still applies в both modes (true concurrent calls
        // skip-аются regardless of force).
        if loadInProgress { return }
        if !force && Date().timeIntervalSince(lastLoadAt) < 0.1 { return }
        loadInProgress = true
        defer {
            loadInProgress = false
            lastLoadAt = Date()
        }
        loadFromStoreCallCountForTests += 1

        let context = ModelContext(modelContainer)
        let subsDescriptor = FetchDescriptor<Subscription>()
        let serversDescriptor = FetchDescriptor<ServerConfig>()
        let subs = (try? context.fetch(subsDescriptor)) ?? []
        let servers = (try? context.fetch(serversDescriptor)) ?? []
        sections = Self.groupSections(subscriptions: subs, servers: servers)
    }

    /// Phase 6d / Wave 06D-03h — M13 fix. `defer`-based cleanup guarantees что
    /// все `.pinging` rows возвращаются в `.idle` на ЛЮБОМ exit-path (нормальный
    /// finish, cancellation mid-stream, throw). До fix'а cleanup стоял ПОСЛЕ
    /// for-await — если outer Task был cancelled mid-stream, rows могли застрять
    /// в `.pinging` (`LatencyBadge` спиннер крутится бесконечно).
    ///
    /// SwiftData save errors теперь surface через `refreshError` вместо silent
    /// swallow (`try? context.save()`) — silent swallow rollback-ил in-memory
    /// `lastLatencyMs` mutation на следующем fetch'е, оставляя stale state.
    private func pingAllServers() async {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        guard let supported = try? context.fetch(descriptor), !supported.isEmpty else { return }

        let payload: [(id: UUID, host: String, port: Int)] = supported.map {
            (id: $0.id, host: $0.host, port: $0.port)
        }

        // Snapshot supported IDs для defer-cleanup (избегаем capture `supported`
        // SwiftData models в defer — они могут переоткрыться в др. context'е).
        let supportedIDs: [UUID] = supported.map(\.id)

        for srv in supported { pingStates[srv.id] = .pinging }

        // M13 — `defer` guarantees cleanup на ВСЕХ exit-paths (normal, cancelled,
        // thrown). `Task { @MainActor }` потому что defer выполняется в текущем
        // execution context, но мутация @Published требует MainActor.
        defer {
            let captureIDs = supportedIDs
            Task { @MainActor [weak self] in
                guard let self else { return }
                for id in captureIDs where self.pingStates[id] == .pinging {
                    self.pingStates[id] = .idle
                }
            }
        }

        for await (id, agg) in probeService.probeAll(payload) {
            if Task.isCancelled { break }
            if let row = supported.first(where: { $0.id == id }) {
                row.lastLatencyMs = agg.avgLatencyMs
                row.lastPingedAt = agg.probedAt
                row.failedProbeCount = agg.failures
            }
            pingStates[id] = .completed(agg)
        }

        // M13 — surface SwiftData save errors через refreshError вместо silent
        // swallow. До fix'а `try?` swallow означал что failed save тихо
        // rollback-ит in-memory `lastLatencyMs` на следующем fetch'е, оставляя
        // stale state — пользователь видел latency badges, которые не persist'или.
        do {
            try context.save()
        } catch {
            Self.log.error("pingAllServers: SwiftData save failed: \(error.localizedDescription, privacy: .public)")
            // Не overwrite-аем existing refreshError (например, от pullToRefresh
            // partial failure) — пишем только если он был nil.
            if refreshError == nil {
                refreshError = L10n.serverListRefreshErrorMessage
            }
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
