import Foundation
import os
import Security

/// T-B3 (closes A2-001) — logger для KeychainStore diagnostic events
/// (особенно missing AppIdentifierPrefix fallback).
private let keychainLogger = Logger(subsystem: "app.bbtb.client", category: "keychain")

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
        // T-B3 (closes C2-001 HIGH): separate `lookupQuery` (без add-only fields)
        // от `addQuery` (full payload). Previously the same dict containing
        // `kSecValueData` was passed to `SecItemDelete`, which Apple docs warn
        // against — delete operation should use a lookup query, не add payload.
        // If delete is rejected (item present but unmatched), the subsequent
        // SecItemAdd fails с `errSecDuplicateItem`.
        //
        // T-B3 (closes A2-002 / C2-002 HIGH/MEDIUM): pin
        // `kSecAttrSynchronizable=false` explicitly to prevent VPN secrets
        // syncing to iCloud Keychain. Platform default usually false но
        // делаем invariant explicit.
        var lookupQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
        if let group = accessGroup { lookupQuery[kSecAttrAccessGroup as String] = group }

        // Delete existing item (если есть). Ignore errSecItemNotFound; surface
        // other errors so caller sees Keychain failure rather than silent.
        let deleteStatus = SecItemDelete(lookupQuery as CFDictionary)
        if deleteStatus != errSecSuccess && deleteStatus != errSecItemNotFound {
            keychainLogger.warning(
                "KeychainStore.save: pre-delete OSStatus=\(deleteStatus, privacy: .public) (proceeding к Add anyway)"
            )
        }

        var addQuery = lookupQuery
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public static func load(tag: String) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: tag,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,  // T-B3 / A2-002
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
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,  // T-B3 / A2-002
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
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,  // T-B3 / A2-002
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let group = accessGroup { query[kSecAttrAccessGroup as String] = group }
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let dict = result as? [String: Any] {
            // T-B3 (closes C2-003 LOW): replace force-cast `as! CFString?` с String bridge
            // через `as? String`. If Security framework returns unexpected bridged type,
            // return nil rather than crash the app/test process. Convert resulting String
            // back к CFString for API contract preservation.
            if let s = dict[kSecAttrAccessible as String] as? String {
                return s as CFString
            }
        }
        return nil
    }

    // MARK: TeamIdentifierPrefix

    private static func teamIdentifierPrefix() -> String? {
        // Стандартный путь — AppIdentifierPrefix в Info.plist основного bundle.
        if let prefix = Bundle.main.infoDictionary?["AppIdentifierPrefix"] as? String {
            return prefix
        }
        // T-B3 (closes A2-001 HIGH): emit diagnostic warning when fallback к private
        // access group. In production this would mean entitlement misconfiguration —
        // shared Keychain между main app + extension breaks silently, user sees
        // "no servers" in app. Test environment (xcodebuild) hits this legitimately.
        keychainLogger.warning(
            "KeychainStore.teamIdentifierPrefix: AppIdentifierPrefix missing — falling back к private access group (production = entitlement misconfiguration; tests = normal)"
        )
        return nil
    }
}
