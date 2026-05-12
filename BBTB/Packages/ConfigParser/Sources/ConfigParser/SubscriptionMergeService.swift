// SubscriptionMergeService.swift — Phase 3 / Plan 04.
//
// D-14 merge-by-identity для pull-to-refresh подписки:
// - composite key host:port:protocolID:sni (см. `ServerConfig.identity` + здесь же
//   локальный `identity(for: ImportedServer)`);
// - existing identity → preserve lastLatencyMs / lastPingedAt / failedProbeCount,
//   обновить name = fetched.displayName (sanitized);
// - new identity → insert через injected closures (persistKeychain + buildServerConfig);
// - disappeared identities → row.missingFromLastFetch = true (НЕ удаляются — D-14);
// - per-subscription isolation: merge А не трогает rows подписки Б;
// - subscription.lastFetched = .now.
//
// Caller controls транзакцию — SubscriptionMergeService НЕ вызывает context.save().
//
// T-03-17 — fetched.displayName приходит из server-controlled `Profile-Title` /
// remarks; sanitize'ится через `sanitizeRowName` (strip \n\r\t, clamp 100 chars).

import Foundation
import SwiftData
import OSLog
import VPNCore

public enum SubscriptionMergeService {

    private static let log = Logger(subsystem: "app.bbtb.subscription-merge", category: "merge")

    /// Merge `fetchedSupported + fetchedUnsupported` в существующий ServerConfig pool
    /// для одной подписки (`subscription`).
    ///
    /// - Parameters:
    ///   - fetchedSupported: ImportedServer.supported из fetch-результата.
    ///   - fetchedUnsupported: ImportedServer.unsupported из fetch-результата (keychainTag = nil).
    ///   - subscription: Subscription row, владеющая pool'ом.
    ///   - context: ModelContext для fetch/insert/mutate (caller выполняет save).
    ///   - persistKeychain: closure-делегат сохранения Keychain entry; возвращает
    ///     KeychainPersistResult (id + tag). Для unsupported — return nil.
    ///   - buildServerConfig: closure-фабрика ServerConfig из ImportedServer +
    ///     id + subscriptionID + keychainTag. Caller (`SubscriptionMergeService.merge`)
    ///     вызывает `context.insert` после построения.
    public static func merge(
        fetchedSupported: [ImportedServer],
        fetchedUnsupported: [ImportedServer],
        into subscription: Subscription,
        context: ModelContext,
        persistKeychain: (ImportedServer) throws -> KeychainPersistResult?,
        buildServerConfig: (ImportedServer, UUID, UUID, String?) -> ServerConfig
    ) throws {
        // (1) Fetch existing serverConfigs for this subscription.
        // #Predicate { $0.subscriptionID == uuid? } silently returns empty on some SwiftData
        // versions — use fetch-all + Swift filter to avoid phantom duplicates on each refresh.
        let allDesc = FetchDescriptor<ServerConfig>()
        let existing = try context.fetch(allDesc).filter { $0.subscriptionID == subscription.id }

        // (2) Build identity → row dictionary; delete stale duplicates accumulated
        // from previous buggy refreshes (first-seen row wins for each identity).
        var existingByIdentity: [String: ServerConfig] = [:]
        var duplicatesToDelete: [ServerConfig] = []
        for row in existing {
            if existingByIdentity[row.identity] != nil {
                duplicatesToDelete.append(row)
            } else {
                existingByIdentity[row.identity] = row
            }
        }
        for dup in duplicatesToDelete {
            if let tag = dup.keychainTag, !tag.isEmpty {
                try? KeychainStore.delete(tag: tag)
            }
            context.delete(dup)
            log.info("merge: removed duplicate row \(dup.identity, privacy: .public)")
        }

        // (3) Объединить supported + unsupported, проходить циклом — каждый fetched
        // получает identity и upsert по нему. Hard rule (D-14): existing row сохраняет
        // lastLatencyMs / lastPingedAt / failedProbeCount.
        var newIdentities = Set<String>()
        let combined: [(ImportedServer, isSupported: Bool)] =
            fetchedSupported.map { ($0, true) } + fetchedUnsupported.map { ($0, false) }

        for (server, _) in combined {
            guard let id = identity(for: server) else {
                // .invalid / нет host:port — skip (логируем, не падаем).
                log.warning("merge: skipping server без identity \(server.displayName, privacy: .public)")
                continue
            }
            newIdentities.insert(id)

            if let row = existingByIdentity[id] {
                // (3a) Identity совпала — обновляем display-метаданные + mutable config fields.
                row.name = sanitizeRowName(server.displayName)
                row.missingFromLastFetch = false
                // SNI ротируется подпиской (anti-fingerprint) → обновляем вместе с name.
                if case let .supported(_, parsed, _) = server {
                    switch parsed {
                    case .vlessReality(let v): row.sni = v.sni
                    case .trojan(let t):       row.sni = t.sni
                    case .vlessTLS(let v):     row.sni = v.sni
                    case .shadowsocks:         break   // SS не имеет SNI
                    case .hysteria2(let h):    row.sni = h.sni
                    }
                }
                // lastLatencyMs / lastPingedAt / failedProbeCount — НЕ трогаем.
            } else {
                // (3b) Новый identity — persist Keychain (для supported), insert.
                let persistResult: KeychainPersistResult?
                do {
                    persistResult = try persistKeychain(server)
                } catch {
                    log.error("merge: persistKeychain failed for \(server.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    throw error
                }
                let rowID = persistResult?.id ?? UUID()
                let tag = persistResult?.tag
                let cfg = buildServerConfig(server, rowID, subscription.id, tag)
                // Гарантируем, что caller не забыл — proxy: name sanitize'нут.
                cfg.name = sanitizeRowName(cfg.name)
                cfg.missingFromLastFetch = false
                context.insert(cfg)
            }
        }

        // (4) Mark disappeared rows (canonical rows only — duplicates deleted above).
        for row in existingByIdentity.values where !newIdentities.contains(row.identity) {
            row.missingFromLastFetch = true
        }

        // (5) Update subscription.lastFetched.
        subscription.lastFetched = .now

        log.info("merge: subscription \(subscription.url, privacy: .public) — fetched \(combined.count) total, existing \(existing.count), new identities \(newIdentities.count)")
    }

    // MARK: Identity computation

    /// Composite identity для ImportedServer — соответствует ServerConfig.identity
    /// для будущего merge lookup.
    static func identity(for server: ImportedServer) -> String? {
        switch server {
        case let .supported(_, parsed, _):
            switch parsed {
            case .vlessReality(let v):
                return "\(v.host):\(v.port):vless-reality"
            case .trojan(let t):
                return "\(t.host):\(t.port):trojan"
            case .vlessTLS(let v):
                return "\(v.host):\(v.port):vless-tls"
            case .shadowsocks(let s):
                return "\(s.host):\(s.port):shadowsocks"
            case .hysteria2(let h):
                return "\(h.host):\(h.port):hysteria2"
            }
        case let .unsupported(_, scheme, host, port, _, _):
            return "\(host):\(port):\(scheme)"
        case .invalid:
            return nil
        }
    }

    /// T-03-17 — strip control chars `\n\r\t` и clamp до 100 chars.
    ///
    /// fetched.displayName приходит из server-controlled Profile-Title / remarks → может
    /// содержать unicode RTL override / control chars / overly long strings. Reused
    /// pattern из `ConfigImporter.sanitizeSubscriptionName`.
    static func sanitizeRowName(_ raw: String) -> String {
        let stripped = raw
            .replacingOccurrences(of: "[\\n\\r\\t]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !stripped.isEmpty else { return "—" }
        return String(stripped.prefix(100))
    }
}
