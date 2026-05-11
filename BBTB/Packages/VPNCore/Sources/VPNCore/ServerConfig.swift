import Foundation
import SwiftData

/// CORE-10: SwiftData @Model для метаданных сервера.
/// Секреты (UUID, publicKey, shortId) хранятся в Keychain — поле `keychainTag` указывает на запись.
@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String       // "vless-reality" в Phase 1
    public var keychainTag: String      // ключ в Keychain
    public var isActive: Bool           // singleton в Phase 1
    public var createdAt: Date
    public var lastLatencyMs: Int?      // Phase 3 заполнит

    public init(id: UUID = UUID(), name: String, host: String, port: Int,
                protocolID: String, keychainTag: String) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.protocolID = protocolID; self.keychainTag = keychainTag
        self.isActive = false; self.createdAt = .now
    }
}
