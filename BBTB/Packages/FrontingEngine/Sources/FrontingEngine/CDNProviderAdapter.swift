import Foundation

/// Phase 10 / DPI-06 / D-04 — Protocol для CDN provider-specific fronting logic.
///
/// **Mirror TransportHandler structure** (Phase 5 CORE-03) — open protocol позволяет
/// добавлять Cloudflare/Fastly/Bunny/Custom без изменения TransportRegistry или PacketTunnelKit.
///
/// **D-05 blacklist** реализован в каждом adapter'е:
///   - `outbound.type ∈ {tuic, hysteria2}` → return false (own-crypto обфускация несовместима)
///   - `outbound.tls.reality.enabled == true` → return false (XTLS Reality = MITM-proof)
///   - `outbound.flow == "xtls-rprx-vision"` → return false (Vision protocol = XTLS-protected)
///
/// **Protocol design:** static-only (value-type semantics, enum conformance). No instance state.
/// `applyFronting` is `inout` mutating для zero-copy JSON dict update — mirrors Pattern 5 from
/// SingBoxConfigLoader.expandConfigForTunnel approach (08-PATTERNS.md).
public protocol CDNProviderAdapter: Sendable {

    /// CDNProvider identifier — должен совпадать с `FrontingProfile.provider` для dispatch.
    static var provider: CDNProvider { get }

    /// UI-facing имя провайдера для display в Advanced Settings.
    static var displayName: String { get }

    /// Применить CDN overlay к sing-box outbound dict.
    ///
    /// - Parameters:
    ///   - outbound: Mutable sing-box outbound dict (`[String: Any]`).
    ///   - profile:  FrontingProfile с dial target + SNI + Host header overrides.
    /// - Returns: `true` если overlay applied; `false` если outbound несовместим с CDN-фронтингом
    ///   (D-05 blacklist: Reality / TUIC / Hysteria2 / Vision) или transport type unknown.
    ///
    /// **Thread safety:** actor isolation в FrontingConfigApplier.apply обеспечивает единственный
    /// вызывающий. Protocol не накладывает ограничений на вызов из синхронного контекста.
    @discardableResult
    static func applyFronting(to outbound: inout [String: Any], profile: FrontingProfile) -> Bool
}
