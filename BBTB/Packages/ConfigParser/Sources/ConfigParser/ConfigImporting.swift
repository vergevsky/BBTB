// ConfigImporting.swift — Phase 3 / Plan 04.
//
// Public protocol declaring ConfigImporter API surface (concrete impl —
// `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`).
//
// Жил в MainScreenFeature до Plan 04. Перенесён в ConfigParser, чтобы
// `ServerListFeature` (consumer for pull-to-refresh) мог импортировать его
// без reverse module dependency на MainScreenFeature.
//
// Все методы protocol используют типы, доступные в ConfigParser (ImportedServer,
// ImportResult, ImportSource) или VPNCore (ServerConfig, KeychainPersistResult).

import Foundation
import VPNCore

/// IMP-04 — public protocol для ConfigImporter. Phase 2 W3.T1 расширил Phase 1
/// (singleton import) до multi-server / multi-format universal pipeline.
///
/// **Phase 3 / Plan 04 extension:** добавлены `persistKeychainSecret(for:)` и
/// `buildServerConfig(from:id:subscriptionID:keychainTag:)` — helpers, которые
/// `SubscriptionMergeService.merge` использует через closure-injection. Это
/// позволяет `ServerListViewModel` вызывать merge через **protocol reference**
/// (без force-cast к concrete ConfigImporter).
public protocol ConfigImporting: AnyObject, Sendable {
    /// Phase 2 entry point — принимает любой raw input.
    func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult

    /// Phase 1 convenience wrapper — читает pasteboard, вызывает importFromRawInput.
    func importFromPasteboard() async throws -> ImportResult

    /// Phase 2 — entry point для QR-scanned text.
    func importFromQRCode(_ scanned: String) async throws -> ImportResult

    /// Загружает «активный» сервер для UI footer (Phase 1 carry-forward).
    func loadActiveServer() -> ServerConfig?

    /// Phase 2: count supported configs (для ViewModel decision .empty vs .idle).
    func countSupportedConfigs() -> Int

    /// Phase 3 / Plan 04 — persist Keychain secret для одного ImportedServer.
    ///
    /// Возвращает `KeychainPersistResult` (сгенерированный UUID + tag в формате
    /// `"bbtb-config-<uuid>"`). Для `.unsupported` / `.invalid` возвращает nil.
    ///
    /// Используется через closure-injection в `SubscriptionMergeService.merge(...)`.
    func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult?

    /// Phase 3 / Plan 04 — построить ServerConfig из ImportedServer + id (из
    /// `KeychainPersistResult.id`, либо свежий UUID для unsupported) + subscriptionID
    /// + keychainTag.
    ///
    /// НЕ insert'ит в context — caller (`SubscriptionMergeService.merge`) выполняет
    /// `context.insert` после построения.
    func buildServerConfig(from server: ImportedServer,
                            id: UUID,
                            subscriptionID: UUID,
                            keychainTag: String?) -> ServerConfig

    /// Phase 3 / Plan 05 — пересобрать NETunnelProviderManager.providerConfiguration
    /// для конкретного выбранного сервера (или для всего pool при `nil`).
    ///
    /// **Контракт:**
    /// - `selectedID != nil` AND server present в store → 1-outbound pool через
    ///   `PoolBuilder.buildSingleOutboundJSON` (без urltest). D-04 / D-09.
    /// - `selectedID != nil` BUT server отсутствует в store (race: deleted) → fallback
    ///   на full pool через `PoolBuilder.buildSingBoxJSON` (Pitfall 10 graceful).
    /// - `selectedID == nil` → full pool через urltest (Phase 2 behaviour).
    /// - 0 supported servers → throw `noSupportedServers` (caller обрабатывает).
    ///
    /// Используется MainScreenViewModel.performToggle:
    /// - Auto-mode после autoSelect → `provisionTunnelProfile(for: winnerID)`.
    /// - Manual selection → `provisionTunnelProfile(for: selectedID)`.
    /// - applySelection в .connected → disconnect → provisionTunnelProfile(for:) → connect.
    func provisionTunnelProfile(for selectedID: UUID?) async throws

    /// Phase 4 / Plan 04-06 D-14 — background upgrade pass: attempts to re-parse
    /// unsupported rows that have a rawURI using Phase 4 handlers.
    /// Throttled to at most once per 5 minutes. Fire-and-forget safe.
    func runIsSupportedUpgrade() async

    /// Phase 5 Wave 8 — re-parse `AnyParsedConfig` from `ServerConfig` (Keychain or rawURI).
    ///
    /// Used by `ServerDetailViewModel` to display protocol detail fields (flow, fingerprint, etc.)
    /// without duplicating secrets in SwiftData.
    ///
    /// Strategy: prefer Keychain (supported servers — rawURI cleared per T-02-04 invariant);
    /// fallback to rawURI for unsupported / Phase-4-upgraded servers.
    /// Returns nil if parsing fails (corrupted Keychain, missing fields, or unsupported protocol).
    ///
    /// @MainActor: `ServerConfig` is a `@Model` class; calling from MainActor context
    /// ensures safe access to its properties under Swift 6 strict concurrency.
    @MainActor
    func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig?
}
