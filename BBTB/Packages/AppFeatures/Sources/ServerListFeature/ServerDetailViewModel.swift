// ServerDetailViewModel.swift — Phase 5 Wave 8 / Task 2.
//
// TRANSP-05: ViewModel for ServerDetailView.
// Responsibilities:
//   - Re-parses rawURI/Keychain on appear to populate protocol detail fields
//   - Persists transport override via fetch-all + Swift filter (Pitfall 4 — NO #Predicate)
//   - Exposes selectedTransport (@Published) for TransportPicker binding

import Foundation
import SwiftUI
import SwiftData
import OSLog
import VPNCore
import ConfigParser

// MARK: - ParsedDetails

/// Protocol detail fields extracted from AnyParsedConfig for display in ServerDetailView.
/// Only available for supported servers whose Keychain entry can be decoded.
public struct ParsedDetails: Equatable, Sendable {
    public let uuid: UUID?
    public let flow: String?
    public let fingerprint: String
    public let alpn: [String]
    public let publicKey: String?
    public let shortId: String?
    public let currentTransport: TransportConfig
}

// MARK: - ServerDetailViewModel

@MainActor
public final class ServerDetailViewModel: ObservableObject {

    private static let log = Logger(subsystem: "app.bbtb.server-list", category: "detail")

    // MARK: Published state

    @Published public private(set) var parsedDetails: ParsedDetails?

    /// Current transport selection — reflects `server.transportOverride` initially,
    /// updated when user picks a new transport.
    @Published public var selectedTransport: TransportSelection

    // MARK: Dependencies

    /// Read-only server config for displaying static fields (name, host, port, etc.).
    public let server: ServerConfig

    private let modelContainer: ModelContainer
    private let configImporter: ConfigImporting

    // MARK: Init

    public init(server: ServerConfig,
                modelContainer: ModelContainer,
                configImporter: ConfigImporting) {
        self.server = server
        self.modelContainer = modelContainer
        self.configImporter = configImporter
        self.selectedTransport = TransportSelection.from(server.transportOverride)
    }

    // MARK: Lifecycle

    /// Re-parse rawURI / Keychain on screen appear to populate `parsedDetails`.
    public func onAppear() async {
        // Both `self` and `reparseAnyParsedConfig` are @MainActor-isolated —
        // `server` can be safely accessed and passed here.
        let parsed = await configImporter.reparseAnyParsedConfig(from: server)
        self.parsedDetails = parsed.map { extractDetails(from: $0) }
    }

    // MARK: Transport persistence

    /// Persist the selected transport override to SwiftData.
    ///
    /// **Pitfall 4** (SwiftData #Predicate with Codable enum silently returns empty):
    /// Uses fetch-all + Swift filter, NOT #Predicate, to locate the server by ID.
    ///
    /// **Pitfall 5** (apply by ServerConfig.id, not by object reference):
    /// We re-fetch the live object in a fresh ModelContext to avoid cross-context mutations.
    public func applyTransportSelection(_ new: TransportSelection) async {
        let context = ModelContext(modelContainer)
        // Pitfall 4: fetch ALL, filter in Swift — never #Predicate with Codable enum
        let allServers = (try? context.fetch(FetchDescriptor<ServerConfig>())) ?? []
        guard let cfg = allServers.first(where: { $0.id == server.id }) else {
            Self.log.warning("ServerDetailVM: server \(self.server.id) not found in store")
            return
        }
        let newOverride = new.toOverride()
        cfg.transportOverride = newOverride
        do {
            try context.save()
            selectedTransport = new
            Self.log.info("ServerDetailVM: persisted transportOverride=\(String(describing: newOverride)) for \(cfg.id)")
        } catch {
            Self.log.error("ServerDetailVM: save failed: \(error.localizedDescription)")
        }
    }

    // MARK: Private helpers

    private func extractDetails(from parsed: AnyParsedConfig) -> ParsedDetails {
        switch parsed {
        case .vlessReality(let v):
            return ParsedDetails(
                uuid: v.uuid,
                flow: v.flow.isEmpty ? nil : v.flow,
                fingerprint: v.fingerprint,
                alpn: [],
                publicKey: v.publicKey,
                shortId: v.shortId,
                currentTransport: .tcp       // Reality is always TCP
            )
        case .vlessTLS(let v):
            return ParsedDetails(
                uuid: v.uuid,
                flow: v.flow,
                fingerprint: v.fingerprint,
                alpn: v.alpn,
                publicKey: nil,
                shortId: nil,
                currentTransport: v.transport
            )
        case .trojan(let t):
            return ParsedDetails(
                uuid: nil,
                flow: nil,
                fingerprint: t.fingerprint,
                alpn: t.alpn,
                publicKey: nil,
                shortId: nil,
                currentTransport: t.transport
            )
        case .shadowsocks:
            return ParsedDetails(
                uuid: nil,
                flow: nil,
                fingerprint: "—",
                alpn: [],
                publicKey: nil,
                shortId: nil,
                currentTransport: .tcp
            )
        case .hysteria2(let h):
            return ParsedDetails(
                uuid: nil,
                flow: nil,
                fingerprint: h.fingerprint ?? "—",
                alpn: ["h3"],
                publicKey: nil,
                shortId: nil,
                currentTransport: .tcp
            )
        case .tuic(let t):
            // Phase 7a Wave 1 — PROTO-08 TUIC v5. QUIC-based, no transport overlay.
            return ParsedDetails(
                uuid: nil,
                flow: nil,
                fingerprint: t.fingerprint,
                alpn: t.alpn,
                publicKey: nil,
                shortId: nil,
                currentTransport: .tcp   // TUIC = QUIC, transport ignored
            )
        }
    }
}
