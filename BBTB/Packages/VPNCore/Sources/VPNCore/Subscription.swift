import Foundation
import SwiftData

/// Phase 3 / SRV-02: @Model описание подписки (источник пула серверов).
///
/// Каждая подписка — отдельный URL, возвращающий список URI/JSON для импорта.
/// Связь `Subscription -> [ServerConfig]` реализована через manual FK
/// `ServerConfig.subscriptionID == Subscription.id` (per D-05 + RESEARCH Pitfall 2:
/// SwiftData lightweight migration не поддерживает смену типа поля, поэтому
/// `@Relationship` НЕ используется — переход с `String? subscriptionURL` на
/// FK реализован через явное поле UUID).
///
/// **Lifecycle:**
/// - Создаётся при импорте subscription URL (ConfigImporter — Phase 3).
/// - Имя deriv'ается от Profile-Title header → URL.host → fallback «Подписка».
/// - `lastFetched` обновляется при каждом успешном re-import / pull-to-refresh (Plan 04).
///
/// **Security note (T-03-01):** `name` приходит из server-controlled Profile-Title header.
/// Перед persist sanitization (strip `\n\r\t` + clamp до 100 chars) выполняется в
/// `ConfigImporter.getOrCreateSubscription`.
@Model
public final class Subscription {
    @Attribute(.unique) public var id: UUID
    public var url: String
    public var name: String
    public var lastFetched: Date?

    public init(id: UUID = UUID(),
                url: String,
                name: String,
                lastFetched: Date? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.lastFetched = lastFetched
    }
}
