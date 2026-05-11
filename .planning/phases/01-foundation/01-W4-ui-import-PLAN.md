---
phase: 01-foundation
plan: W4-ui-import
type: execute
wave: 4
depends_on:
  - W0-bootstrap
  - W3-base-tunnel
files_modified:
  - BBTB/Packages/Localization/Package.swift
  - BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings
  - BBTB/Packages/Localization/Sources/Localization/L10n.swift
  - BBTB/Packages/Localization/Tests/LocalizationTests/LocalizationTests.swift
  - BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift
  - BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTests.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift
  - BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift
  - BBTB/Packages/VPNCore/Tests/VPNCoreTests/KeychainStoreTests.swift
  - BBTB/Packages/AppFeatures/Package.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionState.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift
  - BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  - BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift
  - BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionTimerTests.swift
  - BBTB/App/iOSApp/BBTB_iOSApp.swift
  - BBTB/App/macOSApp/BBTB_macOSApp.swift
autonomous: false
requirements:
  - CORE-07
  - CORE-10
  - SEC-05
  - IMP-01
  - UX-02
  - UX-03
  - UX-07
  - LOC-01
  - PROTO-01

must_haves:
  truths:
    - "Main screen имеет 5 состояний: empty, idle, connecting, connected, error"
    - "В состоянии empty показывается кнопка 'Импортировать из буфера'"
    - "В состоянии connected показывается timer формата HH:MM:SS"
    - "Timer обновляется каждую секунду и отражает duration от since до now"
    - "ConfigParser.VLESSURIParser.parse(_:) принимает строку vless://... и возвращает ParsedVLESS struct"
    - "ConfigImporter.importFromPasteboard выполняет цепочку: pasteboard → parse → ConfigBuilder.buildSingBoxJSON → validate → save SwiftData + Keychain → NETunnelProviderManager.saveToPreferences"
    - "ServerConfig — @Model SwiftData с полями id, name, host, port, protocolID, keychainTag, isActive, createdAt"
    - "KeychainStore.save() устанавливает kSecAttrAccessibleWhenUnlocked + accessGroup '<TeamPrefix>.app.bbtb.shared'"
    - "TunnelController.connect() вызывает KillSwitch.apply(to:) перед NETunnelProviderManager.saveToPreferences"
    - "Localizable.xcstrings содержит как минимум 20 ключей с ru+en локализацией"
    - "macOS app имеет MenuBarExtra Scene с popover content (UX-07)"
    - "macOS MenuBarContent показывает status, connection timer (при connected) и кнопку Connect/Disconnect"
  artifacts:
    - path: "BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings"
      provides: "ru+en строки UI Phase 1 (LOC-01)"
    - path: "BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift"
      provides: "Парсер vless:// URI"
      contains: "public enum VLESSURIParser"
    - path: "BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift"
      provides: "SwiftData @Model для метаданных сервера"
      contains: "@Model public final class ServerConfig"
    - path: "BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift"
      provides: "Keychain wrapper с kSecAttrAccessibleWhenUnlocked (SEC-05)"
      contains: "kSecAttrAccessibleWhenUnlocked"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift"
      provides: "UX-02 main screen 5 состояний"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift"
      provides: "UX-03 HH:MM:SS timer"
      contains: "ConnectionTimer"
    - path: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      provides: "IMP-01 import flow"
    - path: "BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift"
      provides: "UX-07 macOS Menu Bar content"
  key_links:
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift"
      via: "VLESSURIParser.parse(pasteboardString)"
      pattern: "VLESSURIParser.parse"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift"
      to: "BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift"
      via: "ConfigBuilder.buildSingBoxJSON(from:)"
      pattern: "ConfigBuilder.buildSingBoxJSON"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift"
      to: "BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift"
      via: "KillSwitch.apply(to: proto) перед saveToPreferences"
      pattern: "KillSwitch.apply"
    - from: "BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift"
      to: "NETunnelProviderManager"
      via: "saveToPreferences + loadFromPreferences + connection.startVPNTunnel()"
      pattern: "NETunnelProviderManager"
    - from: "BBTB/App/macOSApp/BBTB_macOSApp.swift"
      to: "BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift"
      via: "MenuBarExtra Scene"
      pattern: "MenuBarExtra"
---

<objective>
**Wave 4 — UI + Import flow.** Реализовать main screen (UX-02 + UX-03), macOS Menu Bar (UX-07), полный import flow (IMP-01) от pasteboard до working `NETunnelProviderManager`, SwiftData ServerConfig модель (CORE-10), Keychain wrapper (SEC-05), и базовую локализацию ru+en (LOC-01).

После Wave 4 пользователь может (в Xcode UI run) запустить main app, на пустом экране нажать «Импортировать из буфера», и при правильном vless:// URI в буфере — увидеть состояние idle → connecting → connected с работающим таймером. Реальная проверка `api.ipify.org` (что трафик идёт через VPN) — Wave 5.

Purpose: соединить main app (UI) с extension (Wave 3 BaseSingBoxTunnel) через стандартный NetworkExtension API: `NETunnelProviderManager.providerConfiguration["configJSON"]`. UI владеет SwiftData store; Keychain хранит секреты (UUID, publicKey, shortId). KillSwitch (Wave 2) применяется при создании VPN profile.

Output:
- VLESSURIParser с регуляркой prefilter + URLComponents-based parse + 8+ unit-тестов на edge cases.
- ServerConfig (@Model) с ModelContainer на App Group container path.
- KeychainStore с access group based on TeamIdentifierPrefix.
- 7 SwiftUI типов в MainScreenFeature (View, ViewModel, ConnectionState, button, timer, status badge, import button).
- ConfigImporter + TunnelController — orchestration layer.
- macOS MenuBarExtra Scene.
- Localizable.xcstrings с ~25 ключами ru+en.
- iOS+macOS @main App typing'и — подключают MainScreenView.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@.planning/phases/01-foundation/01-W0-bootstrap-SUMMARY.md
@.planning/phases/01-foundation/01-W3-base-tunnel-SUMMARY.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/config-parser-singbox-launcher.md
@Wiki/ux-specification.md

<interfaces>
<!-- From Wave 1, Wave 2, Wave 3 (что Wave 4 потребляет): -->

From Wave 1 PacketTunnelKit:
```swift
public enum SingBoxConfigLoader {
    public static func validate(json: String) throws  // R1 + SEC-06
    public static func loadVLESSRealityTemplate() throws -> String
}
```

From Wave 2 KillSwitch:
```swift
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol)
}
```

From Wave 3 VLESSReality:
```swift
public enum ConfigBuilder {
    public struct VLESSRealityInputs {
        public let host: String; public let port: Int; public let uuid: String
        public let sni: String; public let publicKey: String; public let shortId: String
        public let fingerprint: String
    }
    public static func buildSingBoxJSON(from inputs: VLESSRealityInputs) throws -> String
}
```

From RESEARCH §4 — VLESS URI format:
```
vless://{UUID}@{HOST}:{PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={SNI}&pbk={PUBLIC_KEY}&sid={SHORT_ID}&fp={FINGERPRINT}&type=tcp#{REMARKS}
```

From RESEARCH §4 — `ParsedVLESS` struct:
```swift
public struct ParsedVLESS {
    public let uuid: UUID
    public let host: String; public let port: Int
    public let flow: String; public let security: String
    public let sni: String; public let publicKey: String; public let shortId: String
    public let fingerprint: String; public let networkType: String
    public let remarks: String?
}
```

From RESEARCH §9 — SwiftData ServerConfig & Keychain:
```swift
@Model public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String; public var host: String; public var port: Int
    public var protocolID: String; public var keychainTag: String
    public var isActive: Bool; public var createdAt: Date
    public var lastLatencyMs: Int?
}
```

From RESEARCH §10 — Main screen 5 состояний.
From RESEARCH §11 — macOS MenuBarExtra pattern.
From RESEARCH §13 — Localizable.xcstrings format.
</interfaces>
</context>

<tasks>

<task id="W4-T1" type="auto" tdd="true" autonomous="true">
  <name>Task W4-T1: VLESSURIParser + ServerConfig SwiftData @Model + KeychainStore (Phase 1 storage layer)</name>
  <files>
    BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift,
    BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTests.swift,
    BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift,
    BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift,
    BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift,
    BBTB/Packages/VPNCore/Tests/VPNCoreTests/KeychainStoreTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §4 «vless:// URI parsing» (formal grammar + ParsedVLESS struct + regex)
    - .planning/phases/01-foundation/01-RESEARCH.md §9 «SwiftData ServerConfig» + «Keychain — Shared access group»
    - .planning/phases/01-foundation/01-RESEARCH.md Pitfall 5 «SwiftData + App Group concurrent access»
    - Wiki/config-parser-singbox-launcher.md
  </read_first>
  <behavior>
    - **VLESSURIParser Test 1**: валидный URI с обязательными полями — `parse` возвращает корректный `ParsedVLESS` со всеми полями.
    - **Test 2**: URI с `#Имя%20сервера` фрагментом — `remarks` декодируется до "Имя сервера".
    - **Test 3**: URI без `security=reality` — throws `.notRealityProtocol`.
    - **Test 4**: URI с `encryption != none` — throws `.unsupportedEncryption`.
    - **Test 5**: URI с невалидным UUID — throws `.malformedURI`.
    - **Test 6**: URI без host — throws `.malformedURI`.
    - **Test 7**: URI без port — throws `.malformedURI`.
    - **Test 8**: URI с пропущенным `pbk` — `publicKey == ""` (parse не падает, validation в ConfigBuilder).
    - **KeychainStore Test 1**: save + load возвращает те же bytes.
    - **Test 2**: save с access group без префикса TeamIdentifier работает (Phase 1 fallback на nil access group в тестовой среде; production = с префиксом).
    - **Test 3**: load для несуществующего tag — throws .notFound.
    - **Test 4**: kSecAttrAccessible flag — `kSecAttrAccessibleWhenUnlocked` (assert через SecItemCopyMatching kSecReturnAttributes).
  </behavior>
  <action>
1. **`BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift`:**
```swift
import Foundation
import VPNCore

public struct ParsedVLESS: Sendable, Equatable {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String
    public let security: String
    public let sni: String
    public let publicKey: String
    public let shortId: String
    public let fingerprint: String
    public let networkType: String
    public let remarks: String?

    public init(uuid: UUID, host: String, port: Int, flow: String, security: String,
                sni: String, publicKey: String, shortId: String, fingerprint: String,
                networkType: String, remarks: String?) {
        self.uuid = uuid; self.host = host; self.port = port; self.flow = flow
        self.security = security; self.sni = sni; self.publicKey = publicKey
        self.shortId = shortId; self.fingerprint = fingerprint
        self.networkType = networkType; self.remarks = remarks
    }
}

public enum VLESSURIError: Error, LocalizedError, Equatable {
    case malformedURI
    case notRealityProtocol(String?)
    case unsupportedEncryption(String)

    public var errorDescription: String? {
        switch self {
        case .malformedURI: return "Malformed vless:// URI"
        case .notRealityProtocol(let s): return "Not a Reality protocol URI (security=\(s ?? "missing"))"
        case .unsupportedEncryption(let e): return "Unsupported encryption: \(e) (only 'none' supported)"
        }
    }
}

/// IMP-01 — parser для vless://{UUID}@{HOST}:{PORT}?...
/// Phase 1 поддерживает ТОЛЬКО Reality (security=reality + encryption=none).
public enum VLESSURIParser {
    public static func parse(_ uri: String) throws -> ParsedVLESS {
        let trimmed = uri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let comps = URLComponents(string: trimmed),
              comps.scheme?.lowercased() == "vless",
              let host = comps.host, !host.isEmpty,
              let port = comps.port,
              let user = comps.user,
              let uuid = UUID(uuidString: user)
        else {
            throw VLESSURIError.malformedURI
        }

        // Парсим query params (точно по RFC).
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] {
            if let v = item.value { q[item.name] = v }
        }

        let security = q["security"] ?? ""
        guard security == "reality" else {
            throw VLESSURIError.notRealityProtocol(q["security"])
        }
        let encryption = q["encryption"] ?? "none"
        guard encryption == "none" else {
            throw VLESSURIError.unsupportedEncryption(encryption)
        }

        return ParsedVLESS(
            uuid: uuid,
            host: host,
            port: port,
            flow: q["flow"] ?? "xtls-rprx-vision",
            security: "reality",
            sni: q["sni"] ?? "",
            publicKey: q["pbk"] ?? "",
            shortId: q["sid"] ?? "",
            fingerprint: q["fp"] ?? "chrome",
            networkType: q["type"] ?? "tcp",
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
```

2. **`BBTB/Packages/ConfigParser/Tests/ConfigParserTests/VLESSURIParserTests.swift`** — 8 тестов покрывающих все ветки:
```swift
import XCTest
@testable import ConfigParser

final class VLESSURIParserTests: XCTestCase {
    private let validURI = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=abc123-key&sid=01234567&fp=chrome&type=tcp#My%20Test%20Server"

    func test_parse_valid_returnsAllFields() throws {
        let p = try VLESSURIParser.parse(validURI)
        XCTAssertEqual(p.uuid.uuidString.lowercased(), "550e8400-e29b-41d4-a716-446655440000")
        XCTAssertEqual(p.host, "example.com")
        XCTAssertEqual(p.port, 443)
        XCTAssertEqual(p.flow, "xtls-rprx-vision")
        XCTAssertEqual(p.security, "reality")
        XCTAssertEqual(p.sni, "www.microsoft.com")
        XCTAssertEqual(p.publicKey, "abc123-key")
        XCTAssertEqual(p.shortId, "01234567")
        XCTAssertEqual(p.fingerprint, "chrome")
        XCTAssertEqual(p.networkType, "tcp")
        XCTAssertEqual(p.remarks, "My Test Server")
    }

    func test_parse_withoutReality_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=tls"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.notRealityProtocol = err else {
                XCTFail("Expected .notRealityProtocol, got \(err)")
                return
            }
        }
    }

    func test_parse_wrongEncryption_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=auto&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            guard case VLESSURIError.unsupportedEncryption(let e) = err else {
                XCTFail("Expected .unsupportedEncryption, got \(err)")
                return
            }
            XCTAssertEqual(e, "auto")
        }
    }

    func test_parse_invalidUUID_throws() {
        let uri = "vless://not-a-uuid@example.com:443?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingHost_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@:443?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPort_throws() {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com?encryption=none&security=reality"
        XCTAssertThrowsError(try VLESSURIParser.parse(uri)) { err in
            XCTAssertEqual(err as? VLESSURIError, .malformedURI)
        }
    }

    func test_parse_missingPbk_publicKeyIsEmpty() throws {
        let uri = "vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&security=reality"
        let p = try VLESSURIParser.parse(uri)
        XCTAssertEqual(p.publicKey, "")
        // ConfigBuilder downstream catches empty publicKey if it's actually invalid for sing-box.
    }

    func test_parse_handlesWhitespace() throws {
        let uri = "  \(validURI)\n"
        let p = try VLESSURIParser.parse(uri)
        XCTAssertEqual(p.host, "example.com")
    }
}
```

3. **`BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift`** — SwiftData @Model:
```swift
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
```

4. **`BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift`** — shared ModelContainer на App Group path:
```swift
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
```

5. **`BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift`** — Keychain wrapper:
```swift
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
            return dict[kSecAttrAccessible as String] as CFString?
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
```

6. **`BBTB/Packages/VPNCore/Tests/VPNCoreTests/KeychainStoreTests.swift`** (Phase 1 — простой smoke; SEC-05 unit-тест явно проверяет access flag):
```swift
import XCTest
import Security
@testable import VPNCore

final class KeychainStoreTests: XCTestCase {
    private let testTag = "bbtb-test-\(UUID().uuidString)"

    override func tearDown() {
        try? KeychainStore.delete(tag: testTag)
        super.tearDown()
    }

    func test_saveAndLoad_roundtrip() throws {
        let data = "hello bbtb".data(using: .utf8)!
        try KeychainStore.save(secret: data, tag: testTag)
        let loaded = try KeychainStore.load(tag: testTag)
        XCTAssertEqual(loaded, data)
    }

    func test_load_missingTag_throwsNotFound() {
        XCTAssertThrowsError(try KeychainStore.load(tag: "non-existent-\(UUID().uuidString)")) { err in
            guard case KeychainError.notFound = err else {
                XCTFail("Expected .notFound, got \(err)")
                return
            }
        }
    }

    func test_sec05_accessibleFlag_isWhenUnlocked() throws {
        let data = "secret".data(using: .utf8)!
        try KeychainStore.save(secret: data, tag: testTag)
        let flag = try KeychainStore.accessibleFlag(tag: testTag)
        XCTAssertNotNil(flag)
        // CFEqual вместо ==, т.к. это CFString-references.
        XCTAssertTrue(CFEqual(flag!, kSecAttrAccessibleWhenUnlocked),
                       "SEC-05: kSecAttrAccessible must be kSecAttrAccessibleWhenUnlocked, got \(String(describing: flag))")
    }

    func test_delete_idempotent() throws {
        XCTAssertNoThrow(try KeychainStore.delete(tag: "non-existent-\(UUID().uuidString)"))
    }
}
```
  </action>
  <acceptance_criteria>
    - `grep -q "public enum VLESSURIParser" BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift`
    - `grep -q "comps.scheme?.lowercased() == \"vless\"" BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift`
    - `grep -q "@Model" BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift`
    - `grep -q "public final class ServerConfig" BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift`
    - `grep -q "kSecAttrAccessibleWhenUnlocked" BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift`
    - `grep -q "kSecAttrAccessGroup" BBTB/Packages/VPNCore/Sources/VPNCore/KeychainStore.swift`
    - `grep -q "kSecAttrAccessibleWhenUnlocked" BBTB/Packages/VPNCore/Tests/VPNCoreTests/KeychainStoreTests.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme ConfigParser -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED|Executed [0-9]+ tests"` (≥8 тестов)
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme VPNCore -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED|Executed [0-9]+ tests"` (≥4 KeychainStore теста)
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme ConfigParser -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "VLESSURIParserTests.*passed|Executed [0-9]+ tests"</automated>
  </verify>
  <done>VLESSURIParser, ServerConfig, KeychainStore созданы; SEC-05 invariant (access flag = WhenUnlocked) явно покрыт unit-тестом.</done>
</task>

<task id="W4-T2" type="auto" autonomous="true">
  <name>Task W4-T2: Localizable.xcstrings (ru+en) + L10n type-safe accessor</name>
  <files>
    BBTB/Packages/Localization/Package.swift,
    BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings,
    BBTB/Packages/Localization/Sources/Localization/L10n.swift,
    BBTB/Packages/Localization/Tests/LocalizationTests/LocalizationTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §13 «Localizable.xcstrings (LOC-01)» — формат файла, Bundle.module reference, Pitfall 10
    - .planning/phases/01-foundation/01-CONTEXT.md §5 (UI Phase 1 ~15-20 строк)
  </read_first>
  <action>
1. **Обновить `BBTB/Packages/Localization/Package.swift`:**
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Localization",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "Localization", targets: ["Localization"])],
    targets: [
        .target(
            name: "Localization",
            resources: [
                .process("Resources/Localizable.xcstrings")
            ]
        ),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
    ]
)
```

2. **`BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`** — ~22 ключа для Phase 1 UI:
```json
{
  "sourceLanguage" : "en",
  "version" : "1.0",
  "strings" : {
    "app.display_name" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Bring Back the Bug" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Верни жука" } }
      }
    },
    "app.short_name" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "BBTB" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "BBTB" } }
      }
    },
    "status.empty" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No configuration" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Нет конфигурации" } }
      }
    },
    "status.idle" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Ready" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Готово" } }
      }
    },
    "status.connecting" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connecting…" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключение…" } }
      }
    },
    "status.connected" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connected" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключено" } }
      }
    },
    "status.error" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Error" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Ошибка" } }
      }
    },
    "action.import_from_clipboard" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Import from Clipboard" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Импортировать из буфера" } }
      }
    },
    "action.connect" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connect" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключить" } }
      }
    },
    "action.disconnect" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Disconnect" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Отключить" } }
      }
    },
    "action.retry" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Retry" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Повторить" } }
      }
    },
    "action.details" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Details" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подробнее" } }
      }
    },
    "empty.title" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Add a server configuration" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Добавьте конфигурацию сервера" } }
      }
    },
    "empty.subtitle" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Copy a vless:// link and tap Import" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Скопируйте ссылку vless:// и нажмите Импортировать" } }
      }
    },
    "import.error.no_pasteboard" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Clipboard is empty" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Буфер обмена пуст" } }
      }
    },
    "import.error.malformed" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Not a valid vless:// link" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Это не корректная ссылка vless://" } }
      }
    },
    "import.error.not_reality" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Phase 1 supports only VLESS + Reality" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Phase 1 поддерживает только VLESS + Reality" } }
      }
    },
    "import.success" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Imported successfully" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Импорт успешен" } }
      }
    },
    "menubar.connect" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connect" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключить" } }
      }
    },
    "menubar.disconnect" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Disconnect" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Отключить" } }
      }
    },
    "menubar.open_window" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Open BBTB…" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Открыть BBTB…" } }
      }
    },
    "alert.tunnel_error.title" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Tunnel error" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Ошибка туннеля" } }
      }
    }
  }
}
```

3. **`BBTB/Packages/Localization/Sources/Localization/L10n.swift`:**
```swift
import Foundation

/// LOC-01: type-safe accessor для Localizable.xcstrings.
/// Все строки UI Phase 1 объявлены здесь явно; добавление новой строки = update .xcstrings + новый case ниже.
public enum L10n {
    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    public static let appDisplayName = tr("app.display_name")
    public static let appShortName = tr("app.short_name")
    public static let statusEmpty = tr("status.empty")
    public static let statusIdle = tr("status.idle")
    public static let statusConnecting = tr("status.connecting")
    public static let statusConnected = tr("status.connected")
    public static let statusError = tr("status.error")
    public static let actionImportFromClipboard = tr("action.import_from_clipboard")
    public static let actionConnect = tr("action.connect")
    public static let actionDisconnect = tr("action.disconnect")
    public static let actionRetry = tr("action.retry")
    public static let actionDetails = tr("action.details")
    public static let emptyTitle = tr("empty.title")
    public static let emptySubtitle = tr("empty.subtitle")
    public static let importErrorNoPasteboard = tr("import.error.no_pasteboard")
    public static let importErrorMalformed = tr("import.error.malformed")
    public static let importErrorNotReality = tr("import.error.not_reality")
    public static let importSuccess = tr("import.success")
    public static let menubarConnect = tr("menubar.connect")
    public static let menubarDisconnect = tr("menubar.disconnect")
    public static let menubarOpenWindow = tr("menubar.open_window")
    public static let alertTunnelErrorTitle = tr("alert.tunnel_error.title")
}
```

4. **`BBTB/Packages/Localization/Tests/LocalizationTests/LocalizationTests.swift`** — completeness check (Pitfall 10):
```swift
import XCTest
@testable import Localization

final class LocalizationTests: XCTestCase {
    func test_allKeys_haveEnAndRu() throws {
        // Загружаем .xcstrings JSON напрямую — это smoke на наличие обоих языков для каждого ключа.
        let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")
        XCTAssertNotNil(url, "Localizable.xcstrings must be bundled via Bundle.module")
        let data = try Data(contentsOf: url!)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]

        for (key, raw) in strings {
            let entry = raw as! [String: Any]
            let localizations = entry["localizations"] as! [String: Any]
            XCTAssertNotNil(localizations["en"], "Key '\(key)' missing en localization")
            XCTAssertNotNil(localizations["ru"], "Key '\(key)' missing ru localization")
        }
    }

    func test_keyCount_atLeast20() throws {
        let url = Bundle.module.url(forResource: "Localizable", withExtension: "xcstrings")!
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let strings = json["strings"] as! [String: Any]
        XCTAssertGreaterThanOrEqual(strings.count, 20, "Phase 1 expected ~22 keys; current count: \(strings.count)")
    }

    func test_L10n_namespacedAccessReturnsLocalizedString() {
        // На macOS default locale обычно en. Sanity: app.short_name → "BBTB".
        XCTAssertFalse(L10n.appShortName.isEmpty)
        XCTAssertFalse(L10n.statusIdle.isEmpty)
    }
}
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`
    - `python3 -m json.tool BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings > /dev/null`
    - Количество ключей ≥ 20: `python3 -c "import json; print(len(json.load(open('BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings'))['strings']))"` → ≥ 20
    - `grep -q '"ru"' BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`
    - `grep -q '"Верни жука"' BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings`
    - `grep -q "Bundle.module" BBTB/Packages/Localization/Sources/Localization/L10n.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme Localization -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED"`
  </acceptance_criteria>
</task>

<task id="W4-T3" type="auto" autonomous="true">
  <name>Task W4-T3: MainScreenFeature — все 7 SwiftUI типов (State, View, ViewModel, ConnectionButton, ConnectionTimer, ImportFromClipboardButton, StatusBadge)</name>
  <files>
    BBTB/Packages/AppFeatures/Package.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionState.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift,
    BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionTimerTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §10 «UI Phase 1 (UX-02, UX-03)»
    - .planning/phases/01-foundation/01-CONTEXT.md §5 (UX-триггер импорта, минимальный UI)
    - Wiki/ux-specification.md (общая UX-философия)
  </read_first>
  <action>
1. **Обновить `BBTB/Packages/AppFeatures/Package.swift`** — добавить два product'а (MainScreen + MenuBar) + зависимости:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppFeatures",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "MainScreenFeature", targets: ["MainScreenFeature"]),
        .library(name: "MenuBarFeature", targets: ["MenuBarFeature"]),
    ],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../DesignSystem"),
        .package(path: "../Localization"),
        .package(path: "../ConfigParser"),
        .package(path: "../KillSwitch"),
        .package(path: "../Protocols/VLESSReality"),
    ],
    targets: [
        .target(
            name: "MainScreenFeature",
            dependencies: [
                "VPNCore", "DesignSystem", "Localization",
                "ConfigParser", "KillSwitch", "VLESSReality",
            ]
        ),
        .target(
            name: "MenuBarFeature",
            dependencies: ["MainScreenFeature", "Localization", "VPNCore"]
        ),
        .testTarget(name: "MainScreenFeatureTests", dependencies: ["MainScreenFeature"]),
    ]
)
```

2. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionState.swift`:**
```swift
import Foundation

public enum ConnectionState: Equatable {
    case empty                          // нет сохранённого конфига
    case idle                           // есть конфиг, не подключено
    case connecting
    case connected(since: Date)
    case error(message: String)

    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
    public var connectionStart: Date? {
        if case .connected(let since) = self { return since }
        return nil
    }
}
```

3. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift`:**
```swift
import SwiftUI

/// UX-03: формат HH:MM:SS, обновляется каждую секунду.
public struct ConnectionTimer: View {
    public let since: Date
    @State private var now: Date = .now

    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public init(since: Date) { self.since = since }

    public var body: some View {
        Text(Self.format(interval: now.timeIntervalSince(since)))
            .font(.system(.title, design: .monospaced))
            .monospacedDigit()
            .onReceive(timer) { self.now = $0 }
    }

    public static func format(interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
```

4. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/StatusBadge.swift`:**
```swift
import SwiftUI
import Localization

public struct StatusBadge: View {
    public let state: ConnectionState
    public init(state: ConnectionState) { self.state = state }

    public var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var color: Color {
        switch state {
        case .empty: return .gray
        case .idle: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    private var label: String {
        switch state {
        case .empty: return L10n.statusEmpty
        case .idle: return L10n.statusIdle
        case .connecting: return L10n.statusConnecting
        case .connected: return L10n.statusConnected
        case .error: return L10n.statusError
        }
    }
}
```

5. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift`:**
```swift
import SwiftUI

public struct ConnectionButton: View {
    public let state: ConnectionState
    public let action: () -> Void

    public init(state: ConnectionState, action: @escaping () -> Void) {
        self.state = state; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(fillColor)
                    .frame(width: 200, height: 200)
                Image(systemName: iconName)
                    .font(.system(size: 80, weight: .medium))
                    .foregroundStyle(.white)
                    .symbolEffect(.bounce, value: state)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityIdentifier("BBTB.ConnectionButton")
    }

    private var fillColor: Color {
        switch state {
        case .empty, .idle: return .accentColor.opacity(0.85)
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    private var iconName: String {
        switch state {
        case .empty, .idle, .error: return "power"
        case .connecting: return "bolt"
        case .connected: return "checkmark"
        }
    }
    private var disabled: Bool {
        if case .connecting = state { return true }
        if case .empty = state { return true }
        return false
    }
}
```

6. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift`:**
```swift
import SwiftUI
import Localization

public struct ImportFromClipboardButton: View {
    public let action: () -> Void
    public init(action: @escaping () -> Void) { self.action = action }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(L10n.emptyTitle).font(.headline)
            Text(L10n.emptySubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(L10n.actionImportFromClipboard, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
    }
}
```

7. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`** (важно: Wave 4 фактическая `connect/import` логика — в W4-T4 ConfigImporter/TunnelController; ViewModel — orchestration + UI state):
```swift
import Foundation
import SwiftUI

@MainActor
public final class MainScreenViewModel: ObservableObject {
    @Published public private(set) var state: ConnectionState = .empty
    @Published public private(set) var activeServerName: String?
    @Published public var lastError: String?

    public let importer: ConfigImporting
    public let tunnel: TunnelControlling

    public init(importer: ConfigImporting, tunnel: TunnelControlling) {
        self.importer = importer
        self.tunnel = tunnel
        Task { await refresh() }
    }

    public func refresh() async {
        // Phase 1: один активный конфиг (singleton). Если есть — переходим в .idle.
        if let server = importer.loadActiveServer() {
            activeServerName = server.name
            state = .idle
        } else {
            activeServerName = nil
            state = .empty
        }
    }

    public func importFromPasteboard() {
        Task { await performImport() }
    }

    public func toggleConnection() {
        Task { await performToggle() }
    }

    private func performImport() async {
        lastError = nil
        do {
            let server = try await importer.importFromPasteboard()
            activeServerName = server.name
            state = .idle
        } catch {
            lastError = error.localizedDescription
            state = .error(message: error.localizedDescription)
        }
    }

    private func performToggle() async {
        switch state {
        case .idle, .error:
            state = .connecting
            do {
                let since = try await tunnel.connect()
                state = .connected(since: since)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connected:
            do {
                try await tunnel.disconnect()
                state = .idle
            } catch {
                state = .error(message: error.localizedDescription)
            }
        case .connecting, .empty:
            break
        }
    }
}
```

8. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift`:**
```swift
import SwiftUI
import Localization

public struct MainScreenView: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    public init(viewModel: MainScreenViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            content
            Spacer()
            footer
        }
        .alert(L10n.alertTunnelErrorTitle,
               isPresented: Binding(
                get: { viewModel.lastError != nil && !viewModel.state.isConnected },
                set: { newValue in if !newValue { viewModel.lastError = nil } }
               )
        ) {
            Button("OK") { viewModel.lastError = nil }
        } message: {
            Text(viewModel.lastError ?? "")
        }
    }

    private var header: some View {
        HStack {
            Text(L10n.appShortName).font(.system(.title2, design: .rounded).bold())
            Spacer()
            StatusBadge(state: viewModel.state)
        }
        .padding(.horizontal)
        .padding(.top, 24)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .empty:
            ImportFromClipboardButton(action: viewModel.importFromPasteboard)
        case .idle, .connecting, .connected, .error:
            VStack(spacing: 20) {
                ConnectionButton(state: viewModel.state, action: viewModel.toggleConnection)
                if case .connected(let since) = viewModel.state {
                    ConnectionTimer(since: since)
                }
                if case .error(let msg) = viewModel.state {
                    Text(msg).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let name = viewModel.activeServerName {
            Text(name).font(.caption).foregroundStyle(.secondary)
                .padding(.bottom, 24)
        }
    }
}
```

9. **`BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ConnectionTimerTests.swift`** (UX-03):
```swift
import XCTest
@testable import MainScreenFeature

final class ConnectionTimerTests: XCTestCase {
    func test_format_zero() {
        XCTAssertEqual(ConnectionTimer.format(interval: 0), "00:00:00")
    }
    func test_format_seconds() {
        XCTAssertEqual(ConnectionTimer.format(interval: 5), "00:00:05")
    }
    func test_format_minutes() {
        XCTAssertEqual(ConnectionTimer.format(interval: 65), "00:01:05")
    }
    func test_format_hours() {
        XCTAssertEqual(ConnectionTimer.format(interval: 3661), "01:01:01")
    }
    func test_format_long() {
        XCTAssertEqual(ConnectionTimer.format(interval: 25 * 3600 + 5 * 60 + 7), "25:05:07")
    }
    func test_format_negative_clamps_to_zero() {
        XCTAssertEqual(ConnectionTimer.format(interval: -123), "00:00:00")
    }
}
```
  </action>
  <acceptance_criteria>
    - 7 файлов в `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` существуют
    - `grep -q "@MainActor" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift`
    - `grep -q "ConnectionState" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionState.swift`
    - `grep -q "Timer.publish(every: 1.0" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift`
    - `grep -q '"%02d:%02d:%02d"' BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionTimer.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme MainScreenFeature -destination 'platform=macOS,arch=arm64' -quiet 2>&1 | grep -E "TEST SUCCEEDED"`
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme MainScreenFeature -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "ConnectionTimerTests.*passed|Executed [0-9]+ tests"</automated>
  </verify>
  <done>Main screen UI Phase 1 готов, 6 unit-тестов ConnectionTimer pass.</done>
</task>

<task id="W4-T4" type="auto" autonomous="true">
  <name>Task W4-T4: ConfigImporter + TunnelController — orchestration import flow + tunnel connect/disconnect</name>
  <files>
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift,
    BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §9 «Импорт vless:// из буфера (IMP-01)» — flow diagram
    - .planning/phases/01-foundation/01-RESEARCH.md §1 «NETunnelProviderManager» — точная последовательность создания
    - .planning/phases/01-foundation/01-CONTEXT.md §1 (Bundle ID extension'а для providerBundleIdentifier)
  </read_first>
  <action>
1. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`:**
```swift
import Foundation
import NetworkExtension
import VPNCore
import ConfigParser
import VLESSReality
import KillSwitch
import Localization
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

public protocol ConfigImporting: AnyObject, Sendable {
    func loadActiveServer() -> ServerConfig?
    func importFromPasteboard() async throws -> ServerConfig
}

public enum ImporterError: Error, LocalizedError {
    case emptyPasteboard
    case malformedURI(Error)
    case configBuildFailed(Error)
    case keychainSaveFailed(Error)
    case swiftDataSaveFailed(Error)
    case tunnelProfileSaveFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyPasteboard: return L10n.importErrorNoPasteboard
        case .malformedURI: return L10n.importErrorMalformed
        case .configBuildFailed(let e): return "Config build: \(e.localizedDescription)"
        case .keychainSaveFailed(let e): return "Keychain: \(e.localizedDescription)"
        case .swiftDataSaveFailed(let e): return "Storage: \(e.localizedDescription)"
        case .tunnelProfileSaveFailed(let e): return "VPN profile: \(e.localizedDescription)"
        }
    }
}

public final class ConfigImporter: ConfigImporting, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let providerBundleIdentifier: String

    public init(modelContainer: ModelContainer, providerBundleIdentifier: String) {
        self.modelContainer = modelContainer
        self.providerBundleIdentifier = providerBundleIdentifier
    }

    public func loadActiveServer() -> ServerConfig? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isActive == true }
        )
        return try? context.fetch(descriptor).first
    }

    public func importFromPasteboard() async throws -> ServerConfig {
        guard let raw = readPasteboardString(), !raw.isEmpty else {
            throw ImporterError.emptyPasteboard
        }

        // 1. Parse
        let parsed: ParsedVLESS
        do {
            parsed = try VLESSURIParser.parse(raw)
        } catch {
            throw ImporterError.malformedURI(error)
        }

        // 2. Build JSON config
        let inputs = ConfigBuilder.VLESSRealityInputs(
            host: parsed.host, port: parsed.port, uuid: parsed.uuid.uuidString,
            sni: parsed.sni, publicKey: parsed.publicKey, shortId: parsed.shortId,
            fingerprint: parsed.fingerprint
        )
        let configJSON: String
        do {
            configJSON = try ConfigBuilder.buildSingBoxJSON(from: inputs)
        } catch {
            throw ImporterError.configBuildFailed(error)
        }

        // 3. Persist: Keychain (secrets + full JSON) + SwiftData (metadata)
        let id = UUID()
        let keychainTag = "bbtb-config-\(id.uuidString)"
        let payload: [String: String] = [
            "uuid": parsed.uuid.uuidString,
            "publicKey": parsed.publicKey,
            "shortId": parsed.shortId,
            "sni": parsed.sni,
            "fingerprint": parsed.fingerprint,
            "configJSON": configJSON,
        ]
        let payloadData: Data
        do {
            payloadData = try JSONSerialization.data(withJSONObject: payload)
            try KeychainStore.save(secret: payloadData, tag: keychainTag)
        } catch let kerr as KeychainError {
            throw ImporterError.keychainSaveFailed(kerr)
        } catch {
            throw ImporterError.keychainSaveFailed(error)
        }

        // SwiftData
        let context = ModelContext(modelContainer)
        do {
            // Деактивировать существующие
            let descriptor = FetchDescriptor<ServerConfig>(
                predicate: #Predicate { $0.isActive == true }
            )
            let existing = try context.fetch(descriptor)
            for s in existing { s.isActive = false }
        } catch { /* ignore */ }

        let server = ServerConfig(
            id: id,
            name: parsed.remarks ?? "\(parsed.host):\(parsed.port)",
            host: parsed.host,
            port: parsed.port,
            protocolID: VLESSRealityHandler.identifier,
            keychainTag: keychainTag
        )
        server.isActive = true
        context.insert(server)
        do {
            try context.save()
        } catch {
            throw ImporterError.swiftDataSaveFailed(error)
        }

        // 4. NETunnelProviderManager
        do {
            try await provisionTunnelProfile(server: server, configJSON: configJSON)
        } catch {
            throw ImporterError.tunnelProfileSaveFailed(error)
        }

        return server
    }

    // MARK: - Internals

    private func readPasteboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }

    private func provisionTunnelProfile(server: ServerConfig, configJSON: String) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        proto.serverAddress = server.host
        proto.providerConfiguration = [
            "configJSON": configJSON,
            "keychainTag": server.keychainTag,
        ]
        // KILL-01 + KILL-02 + R4 — единственная точка установки kill switch.
        KillSwitch.apply(to: proto)

        manager.protocolConfiguration = proto
        manager.localizedDescription = "BBTB"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()  // RESEARCH §1 — обязательно после save
    }
}
```

2. **`BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`:**
```swift
import Foundation
import NetworkExtension

public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
}

public final class TunnelController: TunnelControlling, @unchecked Sendable {
    public init() {}

    public func connect() async throws -> Date {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        guard let manager = managers.first else {
            throw NSError(domain: "BBTB.TunnelController", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No VPN profile — import config first"])
        }
        manager.isEnabled = true
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        try manager.connection.startVPNTunnel()

        // Поллим до .connected или error (Phase 1 — простая логика; Phase 6 NET-08 даст auto-reconnect).
        let started = Date()
        for _ in 0..<30 {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            switch manager.connection.status {
            case .connected: return started
            case .disconnecting, .invalid, .disconnected:
                throw NSError(domain: "BBTB.TunnelController", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "Connection failed (status: \(manager.connection.status.rawValue))"])
            default: continue
            }
        }
        throw NSError(domain: "BBTB.TunnelController", code: -3,
                      userInfo: [NSLocalizedDescriptionKey: "Connection timed out after 30s"])
    }

    public func disconnect() async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        managers.first?.connection.stopVPNTunnel()
    }
}
```
  </action>
  <acceptance_criteria>
    - `grep -q "public protocol ConfigImporting" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - `grep -q "VLESSURIParser.parse" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - `grep -q "ConfigBuilder.buildSingBoxJSON" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - `grep -q "KillSwitch.apply(to: proto)" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - `grep -q "saveToPreferences" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - `grep -q "NETunnelProviderManager" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`
    - `grep -q "startVPNTunnel" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`
    - `grep -q "kSecAttrAccessibleWhenUnlocked\|KeychainStore.save" BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift`
    - MainScreenFeature target собирается (`xcodebuild build -scheme MainScreenFeature -destination 'platform=macOS'`)
  </acceptance_criteria>
</task>

<task id="W4-T5" type="auto" autonomous="true">
  <name>Task W4-T5: macOS MenuBarFeature + обновлённые @main App структуры iOS/macOS</name>
  <files>
    BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift,
    BBTB/App/iOSApp/BBTB_iOSApp.swift,
    BBTB/App/macOSApp/BBTB_macOSApp.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §11 «macOS Menu Bar app (UX-07)» — MenuBarExtra pattern
    - .planning/phases/01-foundation/01-CONTEXT.md §5 default Menu Bar (минимальный popover view)
    - .planning/phases/01-foundation/01-RESEARCH.md §9 «SwiftData ServerConfig» — ModelContainer setup
  </read_first>
  <action>
1. **`BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift`:**
```swift
import SwiftUI
import MainScreenFeature
import Localization

public struct MenuBarContent: View {
    @ObservedObject public var viewModel: MainScreenViewModel
    public init(viewModel: MainScreenViewModel) { self.viewModel = viewModel }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.appShortName).font(.headline)
                Spacer()
                StatusBadge(state: viewModel.state)
            }
            Divider()
            switch viewModel.state {
            case .connected(let since):
                ConnectionTimer(since: since)
                Button(L10n.menubarDisconnect, action: viewModel.toggleConnection)
                    .buttonStyle(.borderedProminent)
            case .idle, .error:
                Button(L10n.menubarConnect, action: viewModel.toggleConnection)
                    .buttonStyle(.borderedProminent)
            case .connecting:
                ProgressView()
                    .controlSize(.small)
            case .empty:
                Text(L10n.statusEmpty).foregroundStyle(.secondary)
            }
            Divider()
            if let name = viewModel.activeServerName {
                Text(name).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(width: 280)
    }
}

public extension ConnectionState {
    var menuBarSymbol: String {
        switch self {
        case .empty, .idle: return "bolt.shield"
        case .connecting:   return "bolt.shield.fill"
        case .connected:    return "checkmark.shield.fill"
        case .error:        return "exclamationmark.shield.fill"
        }
    }
}
```

2. **`BBTB/App/iOSApp/BBTB_iOSApp.swift`** — заменить Wave 0 placeholder, подключить MainScreenFeature + SwiftData + ConfigImporter:
```swift
import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import VLESSReality
import ProtocolRegistry

@main
struct BBTB_iOSApp: App {
    private let modelContainer: ModelContainer
    private let viewModel: MainScreenViewModel

    init() {
        // CORE-02: регистрируем протоколы (Phase 1 — только один)
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)

        // SwiftData container
        do {
            self.modelContainer = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        let importer = ConfigImporter(
            modelContainer: modelContainer,
            providerBundleIdentifier: "app.bbtb.client.ios.tunnel"
        )
        let tunnel = TunnelController()
        self.viewModel = MainScreenViewModel(importer: importer, tunnel: tunnel)
    }

    var body: some Scene {
        WindowGroup {
            MainScreenView(viewModel: viewModel)
        }
        .modelContainer(modelContainer)
    }
}
```

3. **`BBTB/App/macOSApp/BBTB_macOSApp.swift`** — main window + MenuBarExtra:
```swift
import SwiftUI
import SwiftData
import VPNCore
import MainScreenFeature
import MenuBarFeature
import VLESSReality
import ProtocolRegistry
import Localization

@main
struct BBTB_macOSApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var viewModel: MainScreenViewModel

    init() {
        ProtocolRegistry.shared.register(VLESSRealityHandler.self)

        let container: ModelContainer
        do {
            container = try SwiftDataContainer.makeShared()
        } catch {
            fatalError("SwiftData container init failed: \(error)")
        }
        self.modelContainer = container
        let importer = ConfigImporter(
            modelContainer: container,
            providerBundleIdentifier: "app.bbtb.client.macos.tunnel"
        )
        let tunnel = TunnelController()
        _viewModel = StateObject(wrappedValue: MainScreenViewModel(importer: importer, tunnel: tunnel))
    }

    var body: some Scene {
        Window(L10n.appShortName, id: "main") {
            MainScreenView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowResizability(.contentSize)
        .modelContainer(modelContainer)

        // UX-07: macOS Menu Bar
        MenuBarExtra(L10n.appShortName, systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
```
  </action>
  <acceptance_criteria>
    - `grep -q "MenuBarExtra" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "menuBarExtraStyle(.window)" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "import MenuBarFeature" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "ProtocolRegistry.shared.register(VLESSRealityHandler.self)" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "ProtocolRegistry.shared.register(VLESSRealityHandler.self)" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "SwiftDataContainer.makeShared" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "ConfigImporter" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "app.bbtb.client.ios.tunnel" BBTB/App/iOSApp/BBTB_iOSApp.swift`
    - `grep -q "app.bbtb.client.macos.tunnel" BBTB/App/macOSApp/BBTB_macOSApp.swift`
    - `grep -q "public struct MenuBarContent" BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift`
  </acceptance_criteria>
</task>

<task id="W4-T6" type="checkpoint:human-action" gate="blocking" autonomous="false">
  <name>Task W4-T6: Подключить новые SwiftPM packages к app target'ам в Xcode + сборка + первый ручной smoke (без vless://)</name>
  <what-built>В Xcode UI добавить новые products (MainScreenFeature, MenuBarFeature, Localization xcstrings resource) в зависимости BBTB-iOS / BBTB-macOS target'ов. Это manual step потому что Project navigator → General → Frameworks, Libraries and Embedded Content требует UI клика. После — собрать и запустить хотя бы один target, увидеть main screen в состоянии empty.</what-built>
  <how-to-verify>
    1. **Xcode → BBTB-iOS target → General → Frameworks, Libraries and Embedded Content:**
       Add (+ → SwiftPM package products):
       - MainScreenFeature
       - Localization
       (другие уже добавлены в W0-T5: VPNCore, ProtocolRegistry, VLESSReality, ConfigParser, KillSwitch, DesignSystem, CrashReporter)

    2. **Xcode → BBTB-macOS target → General → Frameworks:**
       Add:
       - MainScreenFeature
       - MenuBarFeature
       - Localization

    3. **Build обоих:**
       ```bash
       cd /Users/vergevsky/ClaudeProjects/VPN
       xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS \
           -destination 'generic/platform=iOS Simulator' -quiet 2>&1 | tail -10
       xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS \
           -destination 'generic/platform=macOS' -quiet 2>&1 | tail -10
       ```
       Оба должны быть BUILD SUCCEEDED.

    4. **Запустить macOS app локально:**
       Xcode → Scheme BBTB-macOS → Run (Cmd+R). Ожидаемо увидеть:
       - Главное окно с заголовком «BBTB», status badge «Нет конфигурации», крупный SF Symbol clipboard в центре, кнопка «Импортировать из буфера» (русская локализация если macOS на русском, иначе английская).
       - В Menu Bar — иконка `bolt.shield`. По клику открывается popover с такими же контролами.

    5. Записать smoke-результат:
       ```bash
       mkdir -p BBTB/.gsd
       echo "Wave 4 UI smoke verified: $(date -u +%Y-%m-%dT%H:%M:%SZ)" > BBTB/.gsd/wave4-ui-smoke.log
       ```

    **Реальный test с vless:// → connect — в Wave 5** (требует test config от разработчика + Apple Developer signing prompts).

    После — type "wave4 ui green".
  </how-to-verify>
  <resume-signal>Type "wave4 ui green" + опционально скриншот окна / Menu Bar popover.</resume-signal>
  <done>BBTB-iOS и BBTB-macOS собираются с новыми SwiftPM packages в dependencies; macOS app запускается локально и показывает empty state с MenuBarExtra иконкой в строке меню; smoke лог записан.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Pasteboard → ConfigImporter | UIPasteboard / NSPasteboard контент — untrusted; VLESSURIParser валидирует, ConfigBuilder + SingBoxConfigLoader.validate сделают второй слой |
| ConfigImporter → SwiftData store | Pitfall 5: только main app — writer; extension — read-only |
| ConfigImporter → Keychain | SEC-05 access flag; access group `<TeamIdentifierPrefix>.app.bbtb.shared` |
| MainScreenView → ConfigImporter | UI dispatch'ает в @MainActor ViewModel, ViewModel → async ConfigImporter (thread-safe via @unchecked Sendable + actor isolation в `loadActiveServer`/`importFromPasteboard`) |
| MenuBarExtra → main viewModel | Один общий MainScreenViewModel между main window и menu bar — оба наблюдают один @MainActor ObservableObject |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W4-01 | Tampering | Атакующий копирует подменённый vless:// в pasteboard | mitigate | UI требует tap кнопки (D-CONTEXT.md §5 — нет auto-detect, Phase 11 это меняет); VLESSURIParser отказывает на не-Reality |
| T-01-W4-02 | Information Disclosure | Secrets (UUID, publicKey) попадают в OSLog | mitigate | ConfigImporter не logs secret payload; KeychainStore не log'ит при ошибках (только OSStatus); TunnelLogger в extension использует privacy: .private |
| T-01-W4-03 | Information Disclosure | SwiftData ServerConfig содержит host + name → возможна утечка через crash report или iCloud backup | mitigate | host = публичный адрес сервера (не секрет per se); name = user-supplied label; UUID/keys только в Keychain (SEC-05 ловит) |
| T-01-W4-04 | Spoofing | Атакующий импортирует vless с remarks=«Госуслуги» = социальная инженерия | accept | UX-decision Phase 1 — show name из remarks как есть; пользователь сам копировал URI |
| T-01-W4-05 | Tampering | Регрессия в KillSwitch wiring — кто-то забывает позвать KillSwitch.apply | mitigate | grep acceptance в W4-T4: `KillSwitch.apply(to: proto)` обязателен; код-ревью Wave 5 проверяет |
| T-01-W4-06 | Denial of Service | NETunnelProviderManager.saveToPreferences завис → UI бесконечно в .connecting | mitigate | TunnelController.connect имеет 30s timeout с throw |
| T-01-W4-07 | Information Disclosure | iOS pasteboard banner «BBTB has pasted from ...» — UX-noise | accept | Apple-OS notification; Phase 11 заменит на UIPasteControl |
| T-01-W4-08 | Tampering | Регрессия в R1: ConfigBuilder возвращает JSON с inbound секцией | mitigate | ConfigBuilder unit-тест test_buildSingBoxJSON_filled_passesValidate асертит SingBoxConfigLoader.validate проходит; BaseSingBoxTunnel.startTunnel в extension тоже validate (двойной guard) |
</threat_model>

<verification>
**Wave 4 проверки:**

1. **Unit tests (4 scheme):**
   ```bash
   xcodebuild test -workspace BBTB.xcworkspace -scheme ConfigParser -destination 'platform=macOS' -quiet
   xcodebuild test -workspace BBTB.xcworkspace -scheme VPNCore -destination 'platform=macOS' -quiet
   xcodebuild test -workspace BBTB.xcworkspace -scheme Localization -destination 'platform=macOS' -quiet
   xcodebuild test -workspace BBTB.xcworkspace -scheme MainScreenFeature -destination 'platform=macOS' -quiet
   ```
   Все TEST SUCCEEDED.

2. **Build обоих app schemes:**
   ```bash
   xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS -destination 'generic/platform=iOS Simulator' -quiet
   xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-macOS -destination 'generic/platform=macOS' -quiet
   ```
   Оба BUILD SUCCEEDED.

3. **W4-T6 smoke** — macOS app запускается локально, видим empty state + MenuBarExtra (`BBTB/.gsd/wave4-ui-smoke.log`).

4. **LOC-01 invariant:**
   ```bash
   python3 -c "import json; s=json.load(open('BBTB/Packages/Localization/Sources/Localization/Resources/Localizable.xcstrings'))['strings']; missing=[k for k,v in s.items() if 'ru' not in v['localizations'] or 'en' not in v['localizations']]; assert not missing, missing"
   ```

**Не верифицируется в Wave 4:**
- Реальное подключение через vless:// → api.ipify.org — Wave 5.
- KILL-02 manual (server kill → no traffic) — Wave 5.
- SocksProbe scan при активном туннеле — Wave 5.
</verification>

<success_criteria>
Wave 4 завершён когда:

- [ ] **VLESSURIParser** реализован, 8 unit-тестов pass.
- [ ] **ServerConfig** @Model + **SwiftDataContainer** + **KeychainStore** реализованы; SEC-05 unit-тест явно проверяет `kSecAttrAccessibleWhenUnlocked`.
- [ ] **Localizable.xcstrings** содержит ≥20 ключей, каждый с ru+en; LocalizationTests pass.
- [ ] **MainScreenFeature** — 7 SwiftUI типов (State, View, ViewModel, ConnectionButton, ConnectionTimer, ImportFromClipboardButton, StatusBadge); 6 ConnectionTimer тестов pass.
- [ ] **ConfigImporter + TunnelController** — orchestration import flow закрыт; KillSwitch.apply вызывается перед saveToPreferences.
- [ ] **MenuBarContent** реализован; macOS @main App имеет `MenuBarExtra` Scene.
- [ ] **iOS+macOS @main App** регистрируют `VLESSRealityHandler` через `ProtocolRegistry.shared.register`; передают providerBundleIdentifier extension'у.
- [ ] **BBTB-iOS + BBTB-macOS schemes** собираются с новыми SwiftPM dependencies (W4-T6).
- [ ] **Smoke** — macOS app локально показывает empty state + MenuBarExtra работает.
- [ ] **R1 двойная защита** — ConfigBuilder output проходит validate в unit-тесте + extension сделает то же в production path (Wave 3 BaseSingBoxTunnel).
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W4-ui-import-SUMMARY.md` с:
- Снимок `xcodebuild test` для 4 scheme и `xcodebuild build` для 2 app scheme
- Скриншот main screen в empty state (macOS) — если есть
- Скриншот MenuBarExtra popover
- Заметки если пришлось обходить Swift 6 strict concurrency warnings в SwiftData / MainScreenViewModel
- Замечания для Wave 5 — последовательность manual smoke (импорт vless → connect → api.ipify.org → SocksProbe scan)
- Список ключей Localizable.xcstrings (~22 ключа) на случай если Phase 2+ добавит новые — где именно расширять
</output>
