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
            flow: parsed.flow,
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
