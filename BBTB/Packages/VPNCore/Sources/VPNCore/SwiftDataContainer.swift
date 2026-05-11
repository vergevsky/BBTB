import Foundation
import SwiftData

/// Phase 1 SwiftData container, расположенный в App Group для read-доступа из extension.
/// **Pitfall 5:** только main app — writer; extension — read-only (свежий fetch при startTunnel).
public enum SwiftDataContainer {
    public static let appGroupIdentifier = "group.app.bbtb.shared"

    /// Shared ModelContainer для main app + extension (read).
    public static func makeShared() throws -> ModelContainer {
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        else {
            // В тестовой среде без App Group entitlement — fallback на default in-memory store.
            return try ModelContainer(
                for: ServerConfig.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }
        let storeURL = containerURL.appendingPathComponent("ServerConfigStore.sqlite")
        let config = ModelConfiguration(url: storeURL)
        return try ModelContainer(for: ServerConfig.self, configurations: config)
    }
}
