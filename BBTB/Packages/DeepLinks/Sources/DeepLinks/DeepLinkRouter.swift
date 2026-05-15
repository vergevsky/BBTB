import Foundation
import os.signpost

// MARK: - PerfSignposter integration (DEC-06d-06)

/// Local subsystem-scoped Signposter mirroring `RulesEngineCoordinator` / AppFeatures
/// `PerfSignposter` pattern.
///
/// DeepLinks — leaf package; main app side (AppFeatures, Wave 3) consume'ит DeepLinks,
/// поэтому нельзя зависеть от AppFeatures. Локальный enum даёт ту же signposter category
/// (`performance`) + subsystem (`app.bbtb.client`), что делает Instruments → Points of
/// Interest unified view across all client-side measurements.
enum PerfSignposter {
    /// Shared client-side subsystem.
    static let client = OSSignposter(
        subsystem: "app.bbtb.client",
        category: "performance"
    )
}

// MARK: - DeepLinkRouter actor

/// Phase 9 / DEEP-05 — deep-link routing coordinator.
///
/// ```
/// ┌────────────────────────────────────────────────────────────────────┐
/// │ DeepLinkRouter (actor)                                             │
/// │                                                                    │
/// │  register(_:)        ─── add DeepLinkHandler to ordered list      │
/// │                                                                    │
/// │  handle(_:) async    ─── iterate handlers in registration order;   │
/// │    └─→ first canHandle == true wins → try await handler.handle()  │
/// │    └─→ no match → throw DeepLinkError.unhandled                   │
/// └────────────────────────────────────────────────────────────────────┘
/// ```
///
/// **Thread-safety:** `actor` гарантирует mutual exclusion над `handlers` array.
/// Register + handle сериализуются automatically.
///
/// **Order semantics:** handlers iterating в registration order. First-match wins.
/// Caller отвечает за «register more specific handlers first» (e.g. specific scheme
/// перед catch-all wildcard).
///
/// **Extensibility:** Phase 9 регистрирует ONE handler (ImportHandler в Wave 2).
/// В v1+ — добавляется RemoteTokenFetchHandler. Router НЕ изменяется.
///
/// **Cold-start consideration:** D-09 cold-start race — `init` cheap (no I/O), но
/// `handle(_:)` invoked только после `MainScreenViewModel.applyInitialStatusSnapshot`
/// (см. Wave 3 wiring + `pendingDeepLink` buffer). Wave 1 не контактирует с этим
/// сценарием — buffer живёт в App entry point.
public actor DeepLinkRouter {

    // MARK: - State

    /// Зарегистрированные обработчики. Order matters: first registered, first asked.
    private var handlers: [any DeepLinkHandler] = []

    // MARK: - Init

    /// Создаёт router без обработчиков. Wave 3 wiring зарегистрирует concrete handler'ов
    /// из main app's `init()`.
    public init() {}

    // MARK: - Public API

    /// Регистрирует handler в конце ordered list.
    ///
    /// **Idempotency:** duplicate registrations НЕ блокируются — если caller дважды
    /// регистрирует один и тот же тип, оба instances попадут в list. В Wave 3 wiring
    /// caller отвечает за single-shot registration.
    public func register(_ handler: any DeepLinkHandler) {
        handlers.append(handler)
        DeepLinksLogger.router.notice(
            "registered handler=\(type(of: handler).identifier, privacy: .public)"
        )
    }

    /// Maршрутизирует URL на первый matching handler.
    ///
    /// - Parameter url: incoming URL (custom scheme `bbtb://...` или Universal Link
    ///   `https://import.bbtb.app/...`).
    /// - Throws:
    ///     - `DeepLinkError.unhandled(url:)` — ни один handler не вернул
    ///       `canHandle == true`.
    ///     - Любая ошибка, брошенная concrete handler'ом (e.g. `DeepLinkError.importFailed`).
    ///
    /// **Signpost:** `DeepLinkHandle` span обнимает весь body для Instruments Points
    /// of Interest (DEC-06d-06). Используется в Phase 11/12 baseline.
    public func handle(_ url: URL) async throws {
        let signpostID = PerfSignposter.client.makeSignpostID()
        let signpostState = PerfSignposter.client.beginInterval(
            "DeepLinkHandle",
            id: signpostID
        )
        defer {
            PerfSignposter.client.endInterval(
                "DeepLinkHandle",
                signpostState
            )
        }

        DeepLinksLogger.router.notice(
            "handle url=\(url.absoluteString, privacy: .public)"
        )

        for handler in handlers {
            if handler.canHandle(url) {
                DeepLinksLogger.router.notice(
                    "dispatching to handler=\(type(of: handler).identifier, privacy: .public)"
                )
                try await handler.handle(url)
                return
            }
        }

        DeepLinksLogger.router.error(
            "unhandled url=\(url.absoluteString, privacy: .public) (no handler matched, \(self.handlers.count, privacy: .public) registered)"
        )
        throw DeepLinkError.unhandled(url: url)
    }
}
