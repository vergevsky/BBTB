import Foundation
import SwiftData
import OSLog

/// Phase 1 SwiftData container, расположенный в App Group для read-доступа из extension.
/// **Pitfall 5:** только main app — writer; extension — read-only (свежий fetch при startTunnel).
///
/// **Phase 3 changes (D-05):**
/// - Регистрируем обе модели: `ServerConfig.self, Subscription.self` в обоих ветках
///   (App Group и in-memory fallback).
/// - Idempotent data migration: на первый запуск (UserDefaults flag не выставлен)
///   `migratePhase2ToPhase3` группирует `ServerConfig.subscriptionURL` → создаёт
///   `Subscription` rows + проставляет FK `subscriptionID`. Pitfall 9: без flag'а
///   повторный launch плодит дубли.
///
/// **Phase 6d-03e Commit 2 (M2):** `makeShared()` возвращает ModelContainer
/// синхронно БЕЗ data migration. Callers вызывают `runMigrationsIfNeeded(in:)`
/// из detached background Task ПОСЛЕ launch чтобы upgrade users не блокировались
/// до первого frame (раньше: 200-1500ms в зависимости от размера pool).
public enum SwiftDataContainer {
    public static let appGroupIdentifier = "group.app.bbtb.shared"

    /// Phase 3 idempotency flag (Pitfall 9). Set после первого успешного migrate.
    /// `internal` чтобы тесты могли очищать в `tearDown`.
    internal static let migrationDoneKey = "app.bbtb.phase3.migrationDone"

    private static let migrationLogger = Logger(subsystem: "app.bbtb.client", category: "swiftdata-migration")

    /// Shared ModelContainer для main app + extension (read).
    ///
    /// **Phase 6d-03e Commit 2 (M2):** теперь только открывает контейнер. Data
    /// migration выполняется отдельно через `runMigrationsIfNeeded(in:)` —
    /// caller'у нужно запустить её в background Task после launch (см. iOS/macOS
    /// app entry). Контейнер регистрирует обе модели (`ServerConfig` + `Subscription`)
    /// — UI consumers должны быть толерантны к `subscriptionID == nil` для rows,
    /// которые ещё не прошли миграцию (это и так было в инварианте схемы).
    public static func makeShared() throws -> ModelContainer {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            // В тестовой среде без App Group entitlement — fallback на in-memory.
            // Миграция в этой ветке смысла не имеет (нет persistent данных), но schema
            // регистрирует обе модели чтобы тесты `Phase3MigrationTests` могли работать с
            // `Subscription.self`.
            return try ModelContainer(
                for: ServerConfig.self, Subscription.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let storeURL = containerURL.appendingPathComponent("ServerConfigStore.sqlite")
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: config
        )
    }

    /// Phase 6d-03e Commit 2 (M2): deferred Phase 2→3 data migration.
    ///
    /// Зовётся **после** `makeShared()` из detached background Task в App entry
    /// point. Guards UserDefaults flag — повторные вызовы на subsequent launches
    /// сразу возвращают без context.fetch (cheap no-op).
    ///
    /// `async` чтобы caller'у можно было `Task.detached { await ... }` без
    /// прокидывания ошибки в App.init (idempotent retry на следующем launch
    /// если что-то пошло не так).
    ///
    /// **Note:** flag устанавливается ТОЛЬКО после успешного `migratePhase2ToPhase3`,
    /// поэтому неудачная миграция не маркирует store как «migrated».
    public static func runMigrationsIfNeeded(in container: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: migrationDoneKey) else { return }
        do {
            try migratePhase2ToPhase3(in: container)
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
            migrationLogger.notice("Phase 2→3 data migration completed (deferred)")
        } catch {
            // Не маркируем флаг — пусть повторится на следующем launch.
            // ErrorReporter уже логирует через OSLog категорию.
            migrationLogger.error("Phase 2→3 data migration failed (will retry next launch): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Phase 3 Wave 1 data migration: для каждой уникальной `ServerConfig.subscriptionURL`
    /// создать `Subscription` row и проставить `ServerConfig.subscriptionID = sub.id`.
    /// Idempotent на уровне данных (per-URL FetchDescriptor check), даже без UserDefaults flag.
    ///
    /// `internal` (не private) — позволяет `Phase3MigrationTests` вызывать миграцию напрямую
    /// с произвольным in-memory `ModelContainer`. Production-сайт вызывает один раз из
    /// `makeShared` под UserDefaults guard.
    internal static func migratePhase2ToPhase3(in container: ModelContainer) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.subscriptionURL != nil }
        )
        let rows = try context.fetch(descriptor)
        guard !rows.isEmpty else { return }

        // Group by subscriptionURL (force-unwrap безопасен — predicate отфильтровал nil).
        let grouped = Dictionary(grouping: rows) { $0.subscriptionURL! }
        for (url, servers) in grouped {
            // Идемпотентность row-level: если Subscription с такой URL уже есть — переиспользуем.
            let subQuery = FetchDescriptor<Subscription>(
                predicate: #Predicate { $0.url == url }
            )
            let sub: Subscription
            if let existing = try context.fetch(subQuery).first {
                sub = existing
            } else {
                sub = Subscription(url: url, name: derivedName(from: url), lastFetched: nil)
                context.insert(sub)
            }
            for srv in servers where srv.subscriptionID == nil {
                srv.subscriptionID = sub.id
                // `subscriptionURL` намеренно сохраняется (DEPRECATED, см. ServerConfig).
            }
        }
        try context.save()
    }

    /// Производное имя Subscription, когда Profile-Title не пришёл с сервера.
    /// Используется как fallback в data-migration; runtime get-or-create в ConfigImporter
    /// использует ту же стратегию (`metadata?.title ?? url.host ?? "Подписка"`).
    internal static func derivedName(from url: String) -> String {
        URL(string: url)?.host ?? "Подписка"
    }
}
