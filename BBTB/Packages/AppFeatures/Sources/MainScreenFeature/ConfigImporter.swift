import Foundation
import NetworkExtension
import VPNCore
import ConfigParser
import VLESSReality
import VLESSTLS
import Shadowsocks
import Hysteria2
import KillSwitch
import Localization
import SwiftData
import PacketTunnelKit

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// IMP-04 ConfigImporting protocol — Phase 3 / Plan 04 переехал в ConfigParser
// (см. BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift),
// чтобы ServerListFeature мог импортировать его без reverse dep на MainScreenFeature.
// ConfigImporter ниже conforms к этому протоколу.

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

/// Phase 3 — protocol over NETunnelProviderManager save flow.
/// Default impl — `DefaultTunnelProvisioner` (calls real iOS/macOS NetworkExtension API).
/// Tests inject a stub что захватывает inputs без OS-вызовов (без entitlement).
public protocol TunnelProvisioning: Sendable {
    func provisionTunnelProfile(configJSON: String, serverHost: String) async throws
}

public final class ConfigImporter: ConfigImporting, @unchecked Sendable {
    private let modelContainer: ModelContainer
    private let providerBundleIdentifier: String
    private let parser: UniversalImportParsing
    private let tunnelProvisioner: TunnelProvisioning

    public convenience init(modelContainer: ModelContainer,
                            providerBundleIdentifier: String,
                            parser: UniversalImportParser = UniversalImportParser()) {
        self.init(modelContainer: modelContainer,
                  providerBundleIdentifier: providerBundleIdentifier,
                  parser: parser as UniversalImportParsing,
                  tunnelProvisioner: DefaultTunnelProvisioner(providerBundleIdentifier: providerBundleIdentifier))
    }

    /// Phase 3 — full DI ctor для тестов (stub parser + stub provisioner).
    public init(modelContainer: ModelContainer,
                providerBundleIdentifier: String,
                parser: UniversalImportParsing,
                tunnelProvisioner: TunnelProvisioning) {
        self.modelContainer = modelContainer
        self.providerBundleIdentifier = providerBundleIdentifier
        self.parser = parser
        self.tunnelProvisioner = tunnelProvisioner
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

        // 2. Phase 3 / Plan 04 (D-14 merge): subscription URL branch использует
        //    SubscriptionMergeService.merge (preserve lastLatencyMs / mark missing).
        //    Single-paste branch продолжает использовать deleteAllExistingConfigs
        //    + persistSupported (Phase 2 behavior unchanged).
        let context = ModelContext(modelContainer)
        var subscription: Subscription? = nil
        var savedConfigs: [ServerConfig] = []

        if let subURL = result.subscriptionURL {
            // Subscription URL branch — D-14 merge.
            let sub: Subscription
            do {
                sub = try getOrCreateSubscription(
                    url: subURL,
                    name: result.metadata?.title,
                    in: context
                )
                subscription = sub
            } catch {
                throw ImporterError.swiftDataSaveFailed(error)
            }

            do {
                try SubscriptionMergeService.merge(
                    fetchedSupported: result.supported,
                    fetchedUnsupported: result.unsupported,
                    into: sub,
                    context: context,
                    persistKeychain: { [self] server in
                        try self.persistKeychainSecret(for: server)
                    },
                    buildServerConfig: { [self] server, id, subID, tag in
                        self.buildServerConfig(from: server, id: id, subscriptionID: subID, keychainTag: tag)
                    }
                )
                try context.save()
            } catch let err as ImporterError {
                throw err
            } catch let err as KeychainError {
                throw ImporterError.keychainSaveFailed(err)
            } catch {
                throw ImporterError.swiftDataSaveFailed(error)
            }

            // For UI footer (Phase 1 carry-forward) — взять first supported config
            // из текущего pool под этой подпиской.
            // SwiftData #Predicate strict typing: subscriptionID — UUID?, sub.id — UUID,
            // явно поднять в Optional через let bind.
            let subOptID: UUID? = sub.id
            let postMergeDescriptor = FetchDescriptor<ServerConfig>(
                predicate: #Predicate { $0.subscriptionID == subOptID && $0.isSupported == true }
            )
            savedConfigs = (try? context.fetch(postMergeDescriptor)) ?? []
        } else {
            // Single-paste branch — Phase 2 behavior unchanged (replace всех orphan pool).
            do {
                try deleteAllExistingConfigs(in: context)
            } catch {
                throw ImporterError.swiftDataSaveFailed(error)
            }

            for server in result.supported {
                do {
                    let cfg = try persistSupported(server,
                                                   subscriptionURL: nil,
                                                   subscriptionID: nil,
                                                   in: context)
                    savedConfigs.append(cfg)
                } catch let err as ImporterError {
                    throw err
                } catch {
                    throw ImporterError.swiftDataSaveFailed(error)
                }
            }
            for server in result.unsupported {
                try? persistUnsupported(server,
                                        subscriptionURL: nil,
                                        subscriptionID: nil,
                                        in: context)
            }
            do {
                try context.save()
            } catch {
                throw ImporterError.swiftDataSaveFailed(error)
            }
        }

        // 4. Mark exactly one supported server as isActive (Phase 1 carry-forward
        //    для UI footer). CR-04 fix: clear isActive=false на ВСЕХ ServerConfig
        //    (включая чужие подписки) перед установкой, чтобы инвариант «ровно один
        //    isActive==true» держался после merge. Sort by `id.uuidString` —
        //    лексикографический порядок воспроизводим между запусками и не зависит
        //    от SwiftData fetch ordering (которое unspecified).
        do {
            let allDesc = FetchDescriptor<ServerConfig>()
            let allConfigs = (try? context.fetch(allDesc)) ?? []
            for row in allConfigs { row.isActive = false }
        }
        let sortedSaved = savedConfigs.sorted { $0.id.uuidString < $1.id.uuidString }
        if let first = sortedSaved.first {
            first.isActive = true
            try? context.save()
        }
        _ = subscription  // keep ref for downstream tunnel provisioning extensions

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
                case .vlessTLS(let v): return v.host
                case .shadowsocks(let s): return s.host
                case .hysteria2(let h): return h.host
                }
            }
            return "127.0.0.1"  // unreachable — supportedParsed гарантированно не пуст здесь
        }()

        // 7. Provision NETunnelProviderManager (delegate to injected provisioner —
        //    tests inject stub to skip OS NetworkExtension API).
        do {
            try await tunnelProvisioner.provisionTunnelProfile(configJSON: poolJSON, serverHost: serverHost)
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
                                   subscriptionID: UUID? = nil,
                                   in context: ModelContext) throws -> ServerConfig {
        // Phase 3 / Plan 04 — delegate to public helpers persistKeychainSecret +
        // buildServerConfig (single source of truth для serialization+Keychain).
        guard case .supported = server else {
            throw ImporterError.swiftDataSaveFailed(NSError(domain: "BBTB.ConfigImporter", code: -1))
        }
        let persistResult: KeychainPersistResult
        do {
            guard let r = try persistKeychainSecret(for: server) else {
                throw ImporterError.swiftDataSaveFailed(
                    NSError(domain: "BBTB.ConfigImporter", code: -2,
                            userInfo: [NSLocalizedDescriptionKey: "persistKeychainSecret returned nil for supported"]))
            }
            persistResult = r
        } catch let err as ImporterError {
            throw err
        } catch let err as KeychainError {
            throw ImporterError.keychainSaveFailed(err)
        } catch {
            throw ImporterError.keychainSaveFailed(error)
        }
        let cfg = buildServerConfig(
            from: server,
            id: persistResult.id,
            subscriptionID: subscriptionID ?? UUID(),  // placeholder, не используется в single-paste path
            keychainTag: persistResult.tag
        )
        // Single-paste path может передать subscriptionID == nil — переписать.
        cfg.subscriptionID = subscriptionID
        // subscriptionURL — deprecated Phase 2 field, ставим для backward compat.
        cfg.subscriptionURL = subscriptionURL
        context.insert(cfg)
        return cfg
    }

    // MARK: Phase 3 / Plan 04 — ConfigImporting public helpers

    /// Plan 04 — persist Keychain secret for one ImportedServer; returns
    /// `KeychainPersistResult(id, tag)`. Для `.unsupported` / `.invalid` — nil.
    public func persistKeychainSecret(for server: ImportedServer) throws -> KeychainPersistResult? {
        switch server {
        case .supported:
            let id = UUID()
            let tag = "bbtb-config-\(id.uuidString)"
            let payload = buildKeychainPayload(for: server)
            do {
                let payloadData = try JSONSerialization.data(withJSONObject: payload)
                try KeychainStore.save(secret: payloadData, tag: tag)
            } catch let kerr as KeychainError {
                throw ImporterError.keychainSaveFailed(kerr)
            } catch {
                throw ImporterError.keychainSaveFailed(error)
            }
            return KeychainPersistResult(id: id, tag: tag)
        case .unsupported, .invalid:
            return nil
        }
    }

    /// Plan 04 — построить ServerConfig из ImportedServer + id + subscriptionID + tag.
    /// Не делает context.insert — caller отвечает.
    public func buildServerConfig(from server: ImportedServer,
                                   id: UUID,
                                   subscriptionID: UUID,
                                   keychainTag: String?) -> ServerConfig
    {
        switch server {
        case let .supported(name, parsed, _):
            let host: String
            let port: Int
            let protocolID: String
            let displayName: String
            let sni: String?
            switch parsed {
            case .vlessReality(let v):
                host = v.host; port = v.port; sni = v.sni
                protocolID = VLESSRealityHandler.identifier
                displayName = "VLESS + Reality"
            case .trojan(let t):
                host = t.host; port = t.port; sni = t.sni
                protocolID = "trojan"
                displayName = "Trojan"
            case .vlessTLS(let v):
                host = v.host; port = v.port; sni = v.sni
                protocolID = VLESSTLSHandler.identifier
                displayName = "VLESS + TLS"
            case .shadowsocks(let s):
                host = s.host; port = s.port; sni = nil
                protocolID = ShadowsocksHandler.identifier
                displayName = "Shadowsocks"
            case .hysteria2(let h):
                host = h.host; port = h.port; sni = h.sni
                protocolID = Hysteria2Handler.identifier
                displayName = "Hysteria2"
            }
            return ServerConfig(
                id: id,
                name: name,
                host: host,
                port: port,
                protocolID: protocolID,
                keychainTag: keychainTag,
                isSupported: true,
                subscriptionURL: nil,
                outboundJSON: "",
                protocolDisplayName: displayName,
                sni: sni,
                // T-02-04: НЕ сохраняем rawURI для supported — секреты в Keychain.
                rawURI: nil,
                subscriptionID: subscriptionID
            )
        case let .unsupported(name, scheme, host, port, rawURI, _):
            return ServerConfig(
                id: id,
                name: name,
                host: host,
                port: port,
                protocolID: scheme,
                keychainTag: nil,
                isSupported: false,
                subscriptionURL: nil,
                outboundJSON: "",
                protocolDisplayName: "\(scheme.uppercased()) (не поддерживается v0.2)",
                sni: nil,
                rawURI: rawURI,
                subscriptionID: subscriptionID
            )
        case let .invalid(rawURI, _):
            // .invalid не должен попадать сюда — defensive fallback.
            return ServerConfig(
                id: id,
                name: "invalid",
                host: "0.0.0.0",
                port: 0,
                protocolID: "invalid",
                keychainTag: nil,
                isSupported: false,
                subscriptionURL: nil,
                outboundJSON: "",
                protocolDisplayName: "Invalid",
                sni: nil,
                rawURI: rawURI,
                subscriptionID: subscriptionID
            )
        }
    }

    // MARK: Phase 3 / Plan 05 — provisionTunnelProfile(for: selectedID)

    /// Phase 3 / Plan 05 — пересобрать NETunnelProviderManager.providerConfiguration
    /// для конкретного выбранного сервера (или для всего pool при `nil`).
    ///
    /// **D-09 explicit-selection contract (CR-01 fix):** при `selectedID != nil`
    /// мы НЕ подключаемся к другому серверу. Stale ID (после delete) → throw
    /// `ImporterError.noSupportedServers` (vызывающий код через
    /// `reconcileSelectionWithStore()` сбрасывает selection в nil и user'у
    /// предлагается re-select). Decode failure (Keychain miss / corrupt) →
    /// throw `ImporterError.configBuildFailed` — UI отображает ошибку, silent
    /// substitution на другой сервер не происходит.
    ///
    /// При `selectedID == nil` — full pool с urltest (auto-mode).
    public func provisionTunnelProfile(for selectedID: UUID?) async throws {
        let context = ModelContext(modelContainer)
        let supportedDesc = FetchDescriptor<ServerConfig>(
            predicate: #Predicate { $0.isSupported == true }
        )
        let supported: [ServerConfig]
        do {
            supported = try context.fetch(supportedDesc)
        } catch {
            throw ImporterError.swiftDataSaveFailed(error)
        }
        guard !supported.isEmpty else {
            throw ImporterError.noSupportedServers
        }

        // CR-01: branch разделяет explicit selection и auto-mode так, чтобы
        // explicit-selection НИКОГДА не подменялся другим сервером silently.
        var parsedList: [AnyParsedConfig] = []
        if let id = selectedID {
            // Explicit selection: stale ID → noSupportedServers (caller сбрасывает
            // selection). Decode failure → configBuildFailed — не fallback на pool.
            guard let cfg = supported.first(where: { $0.id == id }) else {
                throw ImporterError.noSupportedServers
            }
            guard let tag = cfg.keychainTag,
                  let parsed = try? reparseFromKeychain(cfg, tag: tag) else {
                throw ImporterError.configBuildFailed(
                    NSError(domain: "BBTB.ConfigImporter", code: -10,
                            userInfo: [NSLocalizedDescriptionKey:
                                "Selected server \(id) cannot be decoded from Keychain"])
                )
            }
            // Phase 5 D-19 — apply per-server transport override (currently always nil; Wave 8 wires real field).
            let withOverride = applyTransportOverride(parsed, transportOverride(for: cfg))
            parsedList = [withOverride]
        } else {
            // Auto-mode: iterate all supported, skip on decode failure, build pool.
            for cfg in supported {
                guard let tag = cfg.keychainTag,
                      let parsed = try? reparseFromKeychain(cfg, tag: tag) else { continue }
                // Phase 5 D-19 — apply per-server transport override (currently always nil; Wave 8 wires real field).
                let withOverride = applyTransportOverride(parsed, transportOverride(for: cfg))
                parsedList.append(withOverride)
            }
        }
        guard !parsedList.isEmpty else {
            throw ImporterError.noSupportedServers
        }

        let json: String
        do {
            if parsedList.count == 1 {
                json = try PoolBuilder.buildSingleOutboundJSON(from: parsedList[0])
            } else {
                json = try PoolBuilder.buildSingBoxJSON(from: parsedList)
            }
        } catch {
            throw ImporterError.configBuildFailed(error)
        }

        // R1 self-validate (Phase 1 carry-forward).
        do {
            try SingBoxConfigLoader.validate(json: json)
        } catch {
            throw ImporterError.configBuildFailed(error)
        }

        // Server host для tunnelRemoteAddress — берём host первого parsed.
        let serverHost: String = {
            switch parsedList[0] {
            case .vlessReality(let v): return v.host
            case .trojan(let t): return t.host
            case .vlessTLS(let v): return v.host
            case .shadowsocks(let s): return s.host
            case .hysteria2(let h): return h.host
            }
        }()

        do {
            try await tunnelProvisioner.provisionTunnelProfile(configJSON: json, serverHost: serverHost)
        } catch {
            throw ImporterError.tunnelProfileSaveFailed(error)
        }
    }

    /// Reconstruct `AnyParsedConfig` from `ServerConfig` metadata + Keychain payload.
    /// Mirrors `buildKeychainPayload` structure (inverse op).
    private func reparseFromKeychain(_ cfg: ServerConfig, tag: String) throws -> AnyParsedConfig? {
        let data: Data
        do {
            data = try KeychainStore.load(tag: tag)
        } catch {
            return nil
        }
        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return nil
        }
        switch cfg.protocolID {
        case "vless-reality":
            guard
                let uuidStr = payload["uuid"],
                let uuid = UUID(uuidString: uuidStr)
            else { return nil }
            let publicKey = payload["publicKey"] ?? ""
            let shortId = payload["shortId"] ?? ""
            let sni = payload["sni"] ?? cfg.sni ?? cfg.host
            let fingerprint = payload["fingerprint"] ?? "chrome"
            let flow = payload["flow"] ?? ""
            let parsed = ParsedVLESS(
                uuid: uuid, host: cfg.host, port: cfg.port,
                flow: flow, security: "reality",
                sni: sni, publicKey: publicKey, shortId: shortId,
                fingerprint: fingerprint, networkType: "tcp",
                remarks: cfg.name
            )
            return .vlessReality(parsed)
        case "trojan":
            guard let password = payload["password"] else { return nil }
            let sni = payload["sni"] ?? cfg.sni ?? cfg.host
            let fingerprint = payload["fingerprint"] ?? "chrome"
            let alpnRaw = payload["alpn"] ?? "h2,http/1.1"
            let alpn = alpnRaw.split(separator: ",").map { String($0) }
            // Phase 5 D-06 — ParsedTrojan.TransportType удалён, заменён на TransportConfig.
            // Keychain payload-keys "transportType" / "wsPath" / "wsHost" сохранены
            // для backward-compat с existing user installs (Pitfall — смена ключей
            // сломает re-parse от записей до Phase 5).
            let transport: TransportConfig
            if payload["transportType"] == "ws" {
                let path = payload["wsPath"] ?? "/"
                let host = payload["wsHost"] ?? ""
                transport = .ws(path: path, host: host)
            } else {
                transport = .tcp
            }
            let parsed = ParsedTrojan(
                password: password, host: cfg.host, port: cfg.port,
                security: "tls", sni: sni, fingerprint: fingerprint,
                alpn: alpn, transport: transport, remarks: cfg.name
            )
            return .trojan(parsed)
        case "vless-tls":
            guard let uuidStr = payload["uuid"], let uuid = UUID(uuidString: uuidStr) else { return nil }
            let alpn = payload["alpn"]?.split(separator: ",").map(String.init) ?? ["h2", "http/1.1"]
            let flowVal = payload["flow"] ?? ""
            // Phase 5 D-05 — networkType:String мигрировано в transport:TransportConfig.
            // Legacy Keychain payload-ключ "networkType" сохранён для backward-compat
            // (Pitfall — смена ключа сломает re-parse от записей до Phase 5).
            // Преобразуем legacy строку → TransportConfig через TransportParamParser.
            let legacyNetwork = payload["networkType"] ?? "tcp"
            let vlessTLSTransport: TransportConfig
            do {
                vlessTLSTransport = try TransportParamParser.parse(query: ["type": legacyNetwork])
            } catch {
                // Legacy Keychain payload ушёл бы в .tcp при unsupported — это безопасно
                // (fallback на TCP, не throws upward — user не теряет сервер).
                vlessTLSTransport = .tcp
            }
            let parsed = ParsedVLESSTLS(
                uuid: uuid, host: cfg.host, port: cfg.port,
                flow: flowVal.isEmpty ? nil : flowVal,
                sni: payload["sni"] ?? "",
                fingerprint: payload["fingerprint"] ?? "chrome",
                alpn: alpn,
                transport: vlessTLSTransport,
                remarks: cfg.name
            )
            return .vlessTLS(parsed)
        case "shadowsocks":
            guard let method = payload["method"], let password = payload["password"] else { return nil }
            return .shadowsocks(ParsedShadowsocks(host: cfg.host, port: cfg.port, method: method, password: password, remarks: cfg.name))
        case "hysteria2":
            guard let password = payload["password"] else { return nil }
            let fp = payload["fingerprint"] ?? ""
            let obfs = payload["obfs"] ?? ""
            let obfsPwd = payload["obfsPassword"] ?? ""
            let pin = payload["pinSHA256"] ?? ""
            let parsed = ParsedHysteria2(
                host: cfg.host, port: cfg.port, auth: password,
                sni: payload["sni"] ?? cfg.host,
                fingerprint: fp.isEmpty ? nil : fp,
                obfs: obfs.isEmpty ? nil : obfs,
                obfsPassword: obfsPwd.isEmpty ? nil : obfsPwd,
                allowInsecure: payload["allowInsecure"] == "true",
                pinSHA256: pin.isEmpty ? nil : pin,
                remarks: cfg.name
            )
            return .hysteria2(parsed)
        default:
            return nil
        }
    }

    /// Internal — Keychain payload builder для supported серверов.
    /// Extracted из старого persistSupported для reuse в persistKeychainSecret.
    private func buildKeychainPayload(for server: ImportedServer) -> [String: String] {
        guard case let .supported(_, parsed, _) = server else { return [:] }
        switch parsed {
        case .vlessReality(let v):
            return [
                "uuid": v.uuid.uuidString,
                "publicKey": v.publicKey,
                "shortId": v.shortId,
                "sni": v.sni,
                "fingerprint": v.fingerprint,
                "flow": v.flow,
            ]
        case .trojan(let t):
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
            return p
        case .vlessTLS(let v):
            // Phase 5 D-05 — `v.networkType: String` мигрировано в `v.transport: TransportConfig`.
            // Persist `TransportConfig.identifier` (single-token string) под legacy ключом
            // "networkType" для backward-compat. Wave 5 расширит payload отдельными ws/grpc
            // полями при добавлении транспорт-overlay в outbound builder.
            return [
                "uuid": v.uuid.uuidString,
                "flow": v.flow ?? "",
                "sni": v.sni,
                "fingerprint": v.fingerprint,
                "alpn": v.alpn.joined(separator: ","),
                "networkType": v.transport.identifier,
            ]
        case .shadowsocks(let s):
            return ["method": s.method, "password": s.password]
        case .hysteria2(let h):
            return [
                "password": h.auth,
                "sni": h.sni,
                "fingerprint": h.fingerprint ?? "",
                "allowInsecure": h.allowInsecure ? "true" : "false",
                "obfs": h.obfs ?? "",
                "obfsPassword": h.obfsPassword ?? "",
                "pinSHA256": h.pinSHA256 ?? "",
            ]
        }
    }

    private func persistUnsupported(_ server: ImportedServer,
                                     subscriptionURL: String?,
                                     subscriptionID: UUID? = nil,
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
            rawURI: rawURI,
            subscriptionID: subscriptionID  // Phase 3 — unsupported тоже в той же подписке
        )
        context.insert(cfg)
    }

    /// Phase 3 D-06: get-or-create Subscription для URL импорта.
    ///
    /// Если по URL уже существует — обновляет `name` (если новое имя непустое после
    /// санитизации) и возвращает existing row. Иначе — создаёт новую запись с дериватом
    /// имени из Profile-Title → URL.host → fallback «Подписка».
    ///
    /// **T-03-01 mitigation:** `name` (источник — server-controlled Profile-Title header)
    /// санитизируется через `sanitizeSubscriptionName` — strip `\n\r\t` и clamp до 100 chars.
    private func getOrCreateSubscription(url: String,
                                          name: String?,
                                          in context: ModelContext) throws -> Subscription {
        let query = FetchDescriptor<Subscription>(predicate: #Predicate { $0.url == url })
        let sanitized = name.flatMap(Self.sanitizeSubscriptionName)
        if let existing = try context.fetch(query).first {
            if let newName = sanitized, !newName.isEmpty {
                existing.name = newName
            }
            return existing
        }
        let derived = sanitized ?? (URL(string: url)?.host) ?? "Подписка"
        let sub = Subscription(url: url, name: derived, lastFetched: .now)
        context.insert(sub)
        return sub
    }

    /// T-03-01 — strip control chars (`\n\r\t`) и clamp длины. Trim whitespace edges.
    /// Возвращает nil если после санитизации строка стала пустой (тогда вызывающий
    /// упадёт на fallback `host || "Подписка"`).
    internal static func sanitizeSubscriptionName(_ raw: String) -> String? {
        let stripped = raw
            .replacingOccurrences(of: "[\\n\\r\\t]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return nil }
        return String(stripped.prefix(100))
    }

    // Plan 04 D-14 note: helper `deleteExistingPool` removed; subscription URL
    // branch now calls SubscriptionMergeService.merge. Single-paste branch uses
    // `deleteAllExistingConfigs` below (Phase 2 behaviour unchanged).

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

    // MARK: D-14 isSupported upgrade — background reconciliation

    /// D-14: migrate unsupported rows that now have a rawURI into supported rows
    /// if the URI can be parsed by a Phase 4 handler. Throttled to 5-minute window.
    public func runIsSupportedUpgrade() async {
        let throttleKey = "bbtb.lastIsSupportedUpgrade"
        let last = UserDefaults.standard.double(forKey: throttleKey)
        let now = Date().timeIntervalSince1970
        guard now - last >= 300 else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<ServerConfig>(predicate: #Predicate { !$0.isSupported })
        guard let candidates = try? context.fetch(descriptor) else { return }

        var upgradedCount = 0
        for cfg in candidates {
            guard let rawURI = cfg.rawURI, !rawURI.isEmpty else { continue }
            let uParser = UniversalImportParser()
            guard let result = try? await uParser.import(rawInput: rawURI, source: .pasteboard),
                  let supported = result.supported.first else { continue }
            guard case let .supported(_, parsed, _) = supported else { continue }

            // Re-fetch by ID to handle delete race (Pitfall 5).
            // #Predicate with UUID comparison silently returns empty on some SwiftData versions —
            // use fetch-all + Swift filter (same pattern as SubscriptionMergeService).
            let cfgID = cfg.id
            guard let live = (try? context.fetch(FetchDescriptor<ServerConfig>()))?.first(where: { $0.id == cfgID }) else { continue }

            let keychainTag = "bbtb-config-\(live.id.uuidString)"
            let payload = buildKeychainPayload(for: supported)
            if let data = try? JSONSerialization.data(withJSONObject: payload) {
                try? KeychainStore.save(secret: data, tag: keychainTag)
            }

            live.isSupported = true
            live.keychainTag = keychainTag
            live.protocolID = protocolIDString(from: parsed)
            live.protocolDisplayName = displayNameString(from: parsed)
            live.rawURI = nil  // T-02-04 invariant

            do { try context.save(); upgradedCount += 1 } catch { continue }
        }

        UserDefaults.standard.set(now, forKey: throttleKey)
        print("runIsSupportedUpgrade: upgraded \(upgradedCount)/\(candidates.count) servers")
    }

    internal func protocolIDString(from parsed: AnyParsedConfig) -> String {
        switch parsed {
        case .vlessReality: return "vless-reality"
        case .vlessTLS: return "vless-tls"
        case .trojan: return "trojan"
        case .shadowsocks: return "shadowsocks"
        case .hysteria2: return "hysteria2"
        }
    }

    internal func displayNameString(from parsed: AnyParsedConfig) -> String {
        switch parsed {
        case .vlessReality: return "VLESS + Reality"
        case .vlessTLS: return "VLESS + TLS"
        case .trojan: return "Trojan"
        case .shadowsocks: return "Shadowsocks"
        case .hysteria2: return "Hysteria2"
        }
    }

    // MARK: Phase 5 Wave 7 — Transport override accessor

    /// Phase 5 D-19 — returns the user-selected per-server transport override.
    /// nil = Auto (use URI-derived transport). Wave 8: reads real SwiftData field.
    private func transportOverride(for cfg: ServerConfig) -> TransportConfig? {
        return cfg.transportOverride
    }

    // MARK: Phase 5 Wave 8 — reparseAnyParsedConfig (ConfigImporting protocol)

    /// Re-parse `AnyParsedConfig` from `ServerConfig` (Keychain preferred, rawURI fallback).
    /// Used by `ServerDetailViewModel` to display protocol detail fields.
    @MainActor
    public func reparseAnyParsedConfig(from cfg: ServerConfig) async -> AnyParsedConfig? {
        // Strategy: prefer Keychain (supported servers had rawURI cleared per T-02-04 invariant).
        if let tag = cfg.keychainTag, let parsed = try? reparseFromKeychain(cfg, tag: tag) {
            return parsed
        }
        // rawURI fallback: for unsupported / Phase-4-upgraded servers.
        // Phase 5 acceptable: return nil if Keychain fails. Wave 11 may add rawURI parse path.
        return nil
    }

}

/// Phase 3 — default impl `TunnelProvisioning`. Phase 2 carry-forward логика
/// `NETunnelProviderManager` (load → set protocol → save → reload).
///
/// На тестовых стендах без NetworkExtension entitlement (CLI swift test) `ConfigImporter`
/// принимает stub `TunnelProvisioning` через DI ctor (см. `ConfigImporterSubscriptionTests`).
public final class DefaultTunnelProvisioner: TunnelProvisioning, @unchecked Sendable {
    private let providerBundleIdentifier: String

    public init(providerBundleIdentifier: String) {
        self.providerBundleIdentifier = providerBundleIdentifier
    }

    public func provisionTunnelProfile(configJSON: String, serverHost: String) async throws {
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
