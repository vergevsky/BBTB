// ServerRowFixtures.swift — Phase 12 / Plan 12-02 / Task 8 / DS-15 / N2.
//
// Deterministic ServerConfig для snapshot тестов (UUID/host/port фиксированы,
// чтобы baseline PNG не дрейфовал между прогонами). `.preview` static не
// существует в VPNCore.ServerConfig (verified 2026-05-16 revision iteration 1),
// потому создаём local-to-test fixture. Если в Phase 13+ потребуется shared
// fixture — promote в VPNCore как `public static let preview: ServerConfig`.
//
// Init signature совпадает с `ServerConfig.init(id:name:host:port:protocolID:
// keychainTag:isSupported:subscriptionURL:outboundJSON:protocolDisplayName:
// sni:rawURI:subscriptionID:countryCode:lastPingedAt:failedProbeCount:
// missingFromLastFetch:transportOverride:)` (VPNCore/ServerConfig.swift L66-99).
// keychainTag — explicit value, не nil (deterministic стандарт для snapshot
// baselines).

import Foundation
import VPNCore
import ServerListFeature

enum ServerRowFixtures {
    /// Deterministic supported VLESS Reality server (UUID/host/port фиксированы).
    /// Используется в ServerListSnapshotTests как стандартная фикстура.
    static let sample = ServerConfig(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Amsterdam #1",
        host: "ams1.example.test",
        port: 443,
        protocolID: "vless-reality",
        keychainTag: "snapshot-fixture-tag",
        isSupported: true,
        subscriptionURL: nil,
        outboundJSON: "",
        protocolDisplayName: "VLESS Reality",
        sni: "www.cloudflare.com",
        rawURI: nil,
        subscriptionID: nil,
        countryCode: "NL",
        lastPingedAt: nil,
        failedProbeCount: 0,
        missingFromLastFetch: false,
        transportOverride: nil
    )

    /// Detereministic completed ping state — 28ms avg, 0 failures.
    /// avgLatencyMs/failures/lossRate/probedAt фиксированы для baseline stability.
    static let completedPing: PingState = .completed(
        ProbeAggregate(
            avgLatencyMs: 28,
            failures: 0,
            lossRate: 0.0,
            probedAt: Date(timeIntervalSince1970: 0)
        )
    )
}
