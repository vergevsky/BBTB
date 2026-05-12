import Foundation
import NetworkExtension
import VPNCore
import ConfigParser
import VLESSReality
import KillSwitch
import Localization
import SwiftData
import PacketTunnelKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// IMP-04 — public protocol для ConfigImporter. Phase 2 W3.T1 расширяет Phase 1
/// (singleton import) до multi-server / multi-format universal pipeline.
public protocol ConfigImporting: AnyObject, Sendable {
    /// Phase 2 entry point — принимает любой raw input.
    func importFromRawInput(_ raw: String, source: ImportSource) async throws -> ImportResult

    /// Phase 1 convenience wrapper — читает pasteboard, вызывает importFromRawInput.
    /// **Возвращает** `ImportResult`, как Phase 2 path; Phase 1 callers получают
    /// `.supported.first` через ViewModel adapter.
    func importFromPasteboard() async throws -> ImportResult

    /// Phase 2 — entry point для QR-scanned text.
    func importFromQRCode(_ scanned: String) async throws -> ImportResult

    /// Загружает «активный» сервер для UI footer (Phase 1 carry-forward в новом shape).
    /// Phase 2: returns first supported ServerConfig если есть; nil если pool пустой.
    func loadActiveServer() -> ServerConfig?

    /// Phase 2: count supported configs (для ViewModel decision .empty vs .idle).
    func countSupportedConfigs() -> Int
}

public enum ImporterError: Error, LocalizedError {
    case emptyPasteboard
    case malformedURI(Error)
    case noSupportedServers
    case configBuildFailed(Error)
    case keychainSaveFailed(Error)
    case swiftDataSaveFailed(Error)
    case tunnelProfileSaveFailed(Error)
    case parserFailed(Error)

    public var errorDescription: String? {
        switch self {
        case .emptyPasteboard: return L10n.importErrorNoPasteboard
        case .malformedURI: return L10n.importErrorMalformed
        case .noSupportedServers: return "В источнике нет поддерживаемых конфигураций."
        case .configBuildFailed(let e): return "Config build: \(e.localizedDescription)"
        case .keychainSaveFailed(let e): return "Keychain: \(e.localizedDescription)"
        case .swiftDataSaveFailed(let e): return "Storage: \(e.localizedDescription)"
        case .tunnelProfileSaveFailed(let e): return "VPN profile: \(e.localizedDescription)"
        case .parserFailed(let e): return "Parse: \(e.localizedDescription)"
        }
    }
}

public final class ConfigImporter: ConfigImporting, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let providerBundleIdentifier: String
    private let parser: UniversalImportParser

    public init(modelContainer: ModelContainer,
                providerBundleIdentifier: String,
                parser: UniversalImportParser = UniversalImportParser()) {
        self.modelContainer = modelContainer
        self.providerBundleIdentifier = providerBundleIdentifier
        self.parser = parser
    }

    // MARK: ConfigImporting

    public func loadActiveServer() -> ServerConfig? {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isActive == true && $0.isSupported == true }
        )
        if let active = try? context.fetch(descriptor).first { return active }
        // Fallback — first supported (Phase 2: после массивного pool import isActive может
        // быть не выставлен — берём first supported).
        let supportedDescriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        return try? context.fetch(supportedDescriptor).first
    }

    public func countSupportedConfigs() -> Int {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        return (try? context.fetch(descriptor).count) ?? 0
    }

    public func importFromPasteboard() async throws -> ImportResult {
        guard let raw = readPasteboardString(), !raw.isEmpty else {
            throw ImporterError.emptyPasteboard
        }
        return try await importFromRawInput(raw, source: .pasteboard)
    }

    public func importFromQRCode(_ scanned: String) async throws -> ImportResult {
        return try await importFromRawInput(scanned, source: .qrCode)
    }

    public func importFromRawInput(_ raw: String, source: ImportSource = .pasteboard) async throws -> ImportResult {
        // 1. Parse via UniversalImportParser
        let result: ImportResult
        do {
            result = try await parser.import(rawInput: raw, source: source)
        } catch {
            throw ImporterError.parserFailed(error)
        }
        guard !result.supported.isEmpty else {
            throw ImporterError.noSupportedServers
        }

        // 2. Replace-pool semantics (D-07)
        let context = ModelContext(modelContainer)
        do {
            if let subURL = result.subscriptionURL {
                try deleteExistingPool(subscriptionURL: subURL, in: context)
            } else {
                try deleteAllExistingConfigs(in: context)
            }
        } catch {
            throw ImporterError.swiftDataSaveFailed(error)
        }

        // 3. Persist each ImportedServer (Keychain + SwiftData)
        var savedConfigs: [ServerConfig] = []
        for server in result.supported {
            do {
                let cfg = try persistSupported(server, subscriptionURL: result.subscriptionURL, in: context)
                savedConfigs.append(cfg)
            } catch let err as ImporterError {
                throw err
            } catch {
                throw ImporterError.swiftDataSaveFailed(error)
            }
        }
        for server in result.unsupported {
            try? persistUnsupported(server, subscriptionURL: result.subscriptionURL, in: context)
        }
        do {
            try context.save()
        } catch {
            throw ImporterError.swiftDataSaveFailed(error)
        }

        // 4. Mark first supported as isActive (Phase 1 carry-forward для UI footer).
        if let first = savedConfigs.first {
            first.isActive = true
            try? context.save()
        }

        // 5. Build pool config JSON
        let supportedParsed = result.supported.compactMap { srv -> AnyParsedConfig? in
            if case let .supported(_, parsed, _) = srv { return parsed }
            return nil
        }
        let poolJSON: String
        do {
            poolJSON = try PoolBuilder.buildSingBoxJSON(from: supportedParsed)
        } catch {
            throw ImporterError.configBuildFailed(error)
        }

        // 6. R1 self-validate
        do {
            try SingBoxConfigLoader.validate(json: poolJSON)
        } catch {
            throw ImporterError.configBuildFailed(error)
        }

        // Extract first outbound host for tunnelRemoteAddress (iOS NEPacketTunnelNetworkSettings
        // требует валидный IP/hostname, не произвольную строку). Phase 1 carry-forward:
        // прокидывали host из VLESS URI; Phase 2 регрессия — был hardcoded "BBTB" → extension
        // падал на openTun с "Invalid NETunnelNetworkSettings tunnelRemoteAddress".
        let serverHost: String = {
            for parsed in supportedParsed {
                switch parsed {
                case .vlessReality(let v): return v.host
                case .trojan(let t): return t.host
                }
            }
            return "127.0.0.1"  // unreachable — supportedParsed гарантированно не пуст здесь
        }()

        // 7. Provision NETunnelProviderManager
        do {
            try await provisionTunnelProfile(configJSON: poolJSON, serverHost: serverHost)
        } catch {
            throw ImporterError.tunnelProfileSaveFailed(error)
        }

        return result
    }

    // MARK: Internals

    private func readPasteboardString() -> String? {
        #if os(iOS)
        return UIPasteboard.general.string
        #elseif os(macOS)
        return NSPasteboard.general.string(forType: .string)
        #endif
    }

    private func persistSupported(_ server: ImportedServer,
                                   subscriptionURL: String?,
                                   in context: ModelContext) throws -> ServerConfig {
        guard case let .supported(name, parsed, rawURI) = server else {
            throw ImporterError.swiftDataSaveFailed(NSError(domain: "BBTB.ConfigImporter", code: -1))
        }
        let id = UUID()
        let keychainTag = "bbtb-config-\(id.uuidString)"

        let host: String
        let port: Int
        let protocolID: String
        let displayName: String
        let sni: String?
        let payload: [String: String]

        switch parsed {
        case .vlessReality(let v):
            host = v.host; port = v.port; sni = v.sni
            protocolID = VLESSRealityHandler.identifier
            displayName = "VLESS + Reality"
            payload = [
                "uuid": v.uuid.uuidString,
                "publicKey": v.publicKey,
                "shortId": v.shortId,
                "sni": v.sni,
                "fingerprint": v.fingerprint,
                "flow": v.flow,
            ]
        case .trojan(let t):
            host = t.host; port = t.port; sni = t.sni
            protocolID = "trojan"
            displayName = "Trojan"
            var p: [String: String] = [
                "password": t.password,
                "sni": t.sni,
                "fingerprint": t.fingerprint,
                "alpn": t.alpn.joined(separator: ","),
            ]
            if case let .ws(path, wsHost) = t.transport {
                p["transportType"] = "ws"
                p["wsPath"] = path
                p["wsHost"] = wsHost
            } else {
                p["transportType"] = "tcp"
            }
            payload = p
        }

        do {
            let payloadData = try JSONSerialization.data(withJSONObject: payload)
            try KeychainStore.save(secret: payloadData, tag: keychainTag)
        } catch let kerr as KeychainError {
            throw ImporterError.keychainSaveFailed(kerr)
        } catch {
            throw ImporterError.keychainSaveFailed(error)
        }

        let cfg = ServerConfig(
            id: id,
            name: name,
            host: host,
            port: port,
            protocolID: protocolID,
            keychainTag: keychainTag,
            isSupported: true,
            subscriptionURL: subscriptionURL,
            outboundJSON: "",  // pool builder use ParsedX, не outboundJSON — оставляем пустым на v0.2
            protocolDisplayName: displayName,
            sni: sni,
            // T-02-04: НЕ сохранять rawURI для supported рядов — секреты уже в Keychain
            // через keychainTag. rawURI хранится только для unsupported (нужен для
            // повторного парса при handler upgrade в Phase 4/7). См. 02-SECURITY.md.
            rawURI: nil
        )
        context.insert(cfg)
        return cfg
    }

    private func persistUnsupported(_ server: ImportedServer,
                                     subscriptionURL: String?,
                                     in context: ModelContext) throws {
        guard case let .unsupported(name, scheme, host, port, rawURI, _) = server else { return }
        let cfg = ServerConfig(
            id: UUID(),
            name: name,
            host: host,
            port: port,
            protocolID: scheme,
            keychainTag: nil,  // unsupported → no Keychain
            isSupported: false,
            subscriptionURL: subscriptionURL,
            outboundJSON: "",
            protocolDisplayName: "\(scheme.uppercased()) (не поддерживается v0.2)",
            sni: nil,
            rawURI: rawURI
        )
        context.insert(cfg)
    }

    private func deleteExistingPool(subscriptionURL: String, in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.subscriptionURL == subscriptionURL }
        )
        let existing = try context.fetch(descriptor)
        for cfg in existing {
            if let tag = cfg.keychainTag {
                try? KeychainStore.delete(tag: tag)
            }
            context.delete(cfg)
        }
    }

    private func deleteAllExistingConfigs(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ServerConfig>()
        let existing = try context.fetch(descriptor)
        for cfg in existing {
            if let tag = cfg.keychainTag {
                try? KeychainStore.delete(tag: tag)
            }
            context.delete(cfg)
        }
    }

    private func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        let manager = managers.first ?? NETunnelProviderManager()

        let proto = NETunnelProviderProtocol()
        proto.providerBundleIdentifier = providerBundleIdentifier
        // serverAddress прокидывается в NEPacketTunnelNetworkSettings.tunnelRemoteAddress
        // (см. BaseSingBoxTunnel.startTunnel → ExtensionPlatformInterface(serverAddressHint:)
        // → TunnelSettings.makeR6Safe). iOS требует валидный IP/hostname — произвольная
        // строка отвергается с ошибкой "Invalid NETunnelNetworkSettings tunnelRemoteAddress".
        proto.serverAddress = serverHost
        proto.providerConfiguration = [
            "configJSON": configJSON,
        ]

        // D-14: read kill switch flag from UserDefaults (default true — KILL-01 carry-forward)
        let killSwitchEnabled = UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true
        KillSwitch.apply(to: proto, enabled: killSwitchEnabled)

        manager.protocolConfiguration = proto
        manager.localizedDescription = "BBTB"
        manager.isEnabled = true

        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()  // RESEARCH §9.1 — обязательно после save
    }
}
