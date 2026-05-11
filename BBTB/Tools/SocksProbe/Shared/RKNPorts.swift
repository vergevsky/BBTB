import Foundation

/// Список портов из методички РосКомНадзора (РКН — Roskomnadzor) для R1-проверки.
/// Источник: Wiki/apple-detection-surface.md + Wiki/xray-localhost-vulnerability.md.
public enum RKNPorts {
    public static let socks: [UInt16] = [1080, 9000, 5555]
    public static let socksRange: ClosedRange<UInt16> = 16000...16100
    public static let httpProxy: [UInt16] = [3128, 3127, 8000, 8080, 8081, 8888]
    // ВНИМАНИЕ: 80 и 443 НЕ сканируем — конфликт с нормальным HTTP/HTTPS на устройстве.
    public static let tor: [UInt16] = [9050, 9051, 9150]

    /// Полный список для Phase 1 R1 проверки (SEC-03).
    public static var phase1: [UInt16] {
        socks + Array(socksRange) + httpProxy + tor
    }
}
