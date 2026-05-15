import Foundation

/// Phase 10 / DPI-06 / D-05 — JSON overlay для CDN-фронтинга над expandConfigForTunnel output.
///
/// **Design:** Pure static function — zero instance state, thread-safe, actor-friendly.
/// Mirrors `SingBoxConfigLoader.expandConfigForTunnel` approach: deserialize JSON dict →
/// mutate outbound fields → re-serialize. Pattern source: 08-PATTERNS.md Pattern 5.
///
/// **D-05 blacklist** делегируется в adapter.applyFronting — каждый outbound решает
/// сам на основе type / tls.reality.enabled / flow. Этот applier не дублирует логику.
///
/// **Usage pipeline (Plan 06 ConfigImporter wiring):**
/// 1. `expandConfigForTunnel` → sing-box JSON string
/// 2. `FrontingConfigApplier.apply(json: singBoxJSON, profile: profile, adapter: CloudflareAdapter.self)`
/// 3. Pass modified JSON to BaseSingBoxTunnel (instead of raw expandConfigForTunnel output)
///
/// **Threat T-10-W5-05:** D-05 blacklist в adapters защищает Reality/Vision outbounds
/// от ошибочного overlay. Tests 4-7 в FrontingConfigApplierTests покрывают.
public enum FrontingConfigApplier {

    // MARK: - Batch JSON variant

    /// Применить CDN overlay к всем outbounds в sing-box JSON строке.
    ///
    /// - Parameters:
    ///   - json:    Полный sing-box JSON string (output от `expandConfigForTunnel`).
    ///   - profile: CDN dial target overlay (sniHost, httpHost, connectHost, connectPort).
    ///   - adapter: CDN provider adapter type (CloudflareAdapter.self / FastlyAdapter.self / etc.).
    /// - Returns: Модифицированный JSON string со всеми совместимыми outbounds overridden.
    /// - Throws:  `FrontingError.malformedJSON` если input не парсится или output не сериализуется.
    ///
    /// Incompatible outbounds (Reality/TUIC/Hysteria2/Vision) возвращаются неизменёнными —
    /// adapter.applyFronting вернёт false, изменения не применяются.
    public static func apply(
        json: String,
        profile: FrontingProfile,
        adapter: any CDNProviderAdapter.Type
    ) throws -> String {
        guard let data = json.data(using: .utf8),
              var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw FrontingError.malformedJSON
        }

        var outbounds = (root["outbounds"] as? [[String: Any]]) ?? []

        for i in outbounds.indices {
            var ob = outbounds[i]
            // Return value ignored — each outbound decides its own compatibility.
            // Logging deferred to Plan 06 ConfigImporter wiring layer.
            _ = adapter.applyFronting(to: &ob, profile: profile)
            outbounds[i] = ob
        }

        root["outbounds"] = outbounds

        guard let modified = try? JSONSerialization.data(withJSONObject: root, options: []),
              let result = String(data: modified, encoding: .utf8)
        else {
            throw FrontingError.malformedJSON
        }

        return result
    }

    // MARK: - Single-outbound variant

    /// Применить CDN overlay к одному outbound dict (без JSON roundtrip).
    ///
    /// Inline вариант для использования в ConfigImporter когда outbound dict
    /// уже в памяти (zero-copy, no JSON serialization overhead).
    ///
    /// - Parameters:
    ///   - outbound: Mutable sing-box outbound dict.
    ///   - profile:  CDN overlay profile.
    ///   - adapter:  CDN provider adapter type.
    /// - Returns: `true` если overlay applied; `false` если outbound в D-05 blacklist.
    @discardableResult
    public static func apply(
        outbound: inout [String: Any],
        profile: FrontingProfile,
        adapter: any CDNProviderAdapter.Type
    ) -> Bool {
        return adapter.applyFronting(to: &outbound, profile: profile)
    }
}
