import Foundation
import Darwin

public struct UtunInterfaceFlags: Equatable {
    public let name: String
    public let flagsHex: String
    public let hasPointToPoint: Bool
    public let hasBroadcast: Bool
    public let hasMulticast: Bool
    public let isUp: Bool
    public let isRunning: Bool
}

/// Runtime self-introspection для R6 verification.
///
/// **Уровень 1 (DEBUG-only):** `assertNoPointToPointOnUtun()` вызывается из
/// `BaseSingBoxTunnel.startTunnel` сразу после `setTunnelNetworkSettings` — в DEBUG-сборке
/// падает с assertion failure если хоть один `utun*` имеет `IFF_POINTOPOINT`. Это catches
/// regressions при разработке.
///
/// **Уровень 2 (external):** SocksProbe app (BBTB/Tools/SocksProbe) использует свою копию
/// этой логики (Tools/SocksProbe/Shared/InterfaceInspector.swift) для production verification
/// со стороны «стороннего приложения».
public enum InterfaceFlagsInspector {
    /// Snapshot всех `utun*` интерфейсов с разобранными IFF_* флагами.
    public static func utunSnapshot() -> [UtunInterfaceFlags] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var seen: [String: Int32] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun") {
                seen[name] = Int32(p.pointee.ifa_flags)
            }
            ptr = p.pointee.ifa_next
        }

        return seen.map { (name, flags) in
            UtunInterfaceFlags(
                name: name,
                flagsHex: String(format: "0x%X", UInt32(bitPattern: flags)),
                hasPointToPoint: (flags & IFF_POINTOPOINT) != 0,
                hasBroadcast: (flags & IFF_BROADCAST) != 0,
                hasMulticast: (flags & IFF_MULTICAST) != 0,
                isUp: (flags & IFF_UP) != 0,
                isRunning: (flags & IFF_RUNNING) != 0
            )
        }.sorted { $0.name < $1.name }
    }

    /// DEBUG-only assertion: бросает assertion failure если найден `utun*` с IFF_POINTOPOINT.
    /// В Release-сборке — no-op.
    ///
    /// **DEBUG/TEMP 2026-05-11:** на iOS 26 все `utun*` имеют `IFF_POINTOPOINT` независимо
    /// от отсутствия `destinationAddresses` в `NEPacketTunnelNetworkSettings`. Это новое
    /// поведение Apple, R6-fix на стороне клиента больше не работает. Заменили fatal assert
    /// на лог-предупреждение, чтобы туннель не падал. R6 как фича требует переосмысления
    /// (см. wiki/security-gaps.md — TODO).
    public static func assertNoPointToPointOnUtun(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #if DEBUG
        let violations = utunSnapshot().filter { $0.hasPointToPoint }
        if !violations.isEmpty {
            // T-C-D4 (closes A1'-3-010 LOW Plan 06): use TunnelLogger вместо
            // `print()`. CLAUDE.md security rule «никаких print()» (TunnelLogger.swift:6)
            // contradicted previous print() call here. Routed к security category
            // для proper Console.app filtering.
            let v = violations.map { "\($0.name) [\($0.flagsHex)]" }.joined(separator: ", ")
            TunnelLogger.security.warning("[R6] iOS 26 sets IFF_POINTOPOINT on all utun by default — R6 client-side mitigation no longer effective. Violators: \(v, privacy: .public)")
        }
        #endif
    }
}
