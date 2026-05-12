import Foundation

/// Phase 3 / Plan 04 — payload, возвращаемый из `ConfigImporting.persistKeychainSecret(for:)`.
///
/// Несёт **сгенерированный** `id` (UUID для ServerConfig) и `tag` (ключ в Keychain,
/// формат `"bbtb-config-<uuid>"`). Caller (SubscriptionMergeService) использует обе
/// величины при последующем вызове `ConfigImporting.buildServerConfig(...)`, чтобы
/// связать ServerConfig.id с keychainTag консистентно (без out-of-band shared mutable
/// state в ConfigImporter).
///
/// Возвращается `nil` для `.unsupported` ImportedServer — у них нет Keychain entry.
public struct KeychainPersistResult: Sendable, Equatable {
    public let id: UUID
    public let tag: String

    public init(id: UUID, tag: String) {
        self.id = id
        self.tag = tag
    }
}
