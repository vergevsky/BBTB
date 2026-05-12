import Foundation
import SwiftData

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
public enum SwiftDataContainer {
    public static let appGroupIdentifier = "group.app.bbtb.shared"

    /// Phase 3 idempotency flag (Pitfall 9). Set после первого успешного migrate.
    /// `internal` чтобы тесты могли очищать в `tearDown`.
    internal static let migrationDoneKey = "app.bbtb.phase3.migrationDone"

    /// Shared ModelContainer для main app + extension (read).
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
        let container = try ModelContainer(
            for: ServerConfig.self, Subscription.self,
            configurations: config
        )

        // Phase 3 one-time idempotent data migration.
        // Guard: только при отсутствии flag — внутренняя `migratePhase2ToPhase3` сама
        // безусловна (для testability — RED test использует её напрямую с in-memory контейнером).
        if !UserDefaults.standard.bool(forKey: migrationDoneKey) {
            try migratePhase2ToPhase3(in: container)
            UserDefaults.standard.set(true, forKey: migrationDoneKey)
        }

        return container
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
