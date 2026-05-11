import Foundation
import Security

public enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case notFound(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .saveFailed(let s): return "Keychain save failed: OSStatus=\(s)"
        case .notFound(let s): return "Keychain item not found: OSStatus=\(s)"
        case .loadFailed(let s): return "Keychain load failed: OSStatus=\(s)"
        case .deleteFailed(let s): return "Keychain delete failed: OSStatus=\(s)"
        }
    }
}

/// SEC-05: Keychain wrapper для секретов VLESS+Reality (uuid, publicKey, shortId, configJSON).
/// `kSecAttrAccessibleWhenUnlocked` — устройство должно быть разблокировано для чтения.
/// `kSecAttrAccessGroup` — shared с extension через TeamIdentifierPrefix + "app.bbtb.shared".
public enum KeychainStore {
    public static let service = "app.bbtb.shared"

    /// Compute access group dynamically: `<TeamIdentifierPrefix>app.bbtb.shared`.
    /// В тестовой / xcodebuild test среде без provisioning — возвращает nil → Keychain
    /// использует default access group тестового процесса.
    public static var accessGroup: String? {
        // Phase 1: hardcoded prefix через AppIdentifierPrefix entitlement. Проще — захардкодить
        // в entitlements: `$(AppIdentifierPrefix)app.bbtb.shared` (см. W0-T4). В рантайме —
        // читать через KVC из main bundle. В тестах — вернуть nil.
        guard let prefix = teamIdentifierPrefix() else { return nil }
        return "\(prefix)\(service)"
    }

    public static func save(secret data: Data, tag: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecValueData as String: data,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public static func load(tag: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            if let data = result as? Data { return data }
            throw KeychainError.loadFailed(status)
        case errSecItemNotFound:
            throw KeychainError.notFound(status)
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    public static func delete(tag: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    /// SEC-05 verification — читает `kSecAttrAccessible` атрибут установленный для записи.
    public static func accessibleFlag(tag: String) throws -> CFString? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let dict = result as? [String: Any] {
            return dict[kSecAttrAccessible as String] as! CFString?
        }
        return nil
    }

    // MARK: TeamIdentifierPrefix

    private static func teamIdentifierPrefix() -> String? {
        // Стандартный путь — AppIdentifierPrefix в Info.plist основного bundle.
        if let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String {
            return prefix
        }
        // Альтернативно — извлечь из существующего keychain-item самого бандла.
        // Phase 1: если AppIdentifierPrefix отсутствует (типичная xcodebuild test среда), вернуть nil.
        return nil
    }
}
