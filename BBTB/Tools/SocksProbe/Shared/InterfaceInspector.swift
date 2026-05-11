import Foundation
import Darwin

public struct InterfaceSnapshot: Identifiable {
    public let id = UUID()
    public let name: String
    public let addresses: [String]
    public let flagsHex: String
    public let hasPointToPoint: Bool
    public let hasBroadcast: Bool
    public let hasMulticast: Bool
    public let isUp: Bool
    public let isRunning: Bool
}

public enum InterfaceInspector {
    /// Вернуть snapshot всех utun* интерфейсов с разбором IFF_* флагов.
    /// R6 (SEC-04) external check: `hasPointToPoint` должно быть `false` для всех `utun*`
    /// когда наш BBTB tunnel активен. Это второй уровень верификации R6
    /// (первый — DEBUG-assertion внутри BaseSingBoxTunnel.assertR6_NoP2P, см. Wave 3).
    public static func snapshotUtunInterfaces() -> [InterfaceSnapshot] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        // Сгруппировать по name (IPv4 + IPv6 могут быть в разных записях для одного интерфейса).
        var byName: [String: (addrs: [String], flags: Int32)] = [:]
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("utun") {
                let flags = Int32(p.pointee.ifa_flags)
                var addresses = byName[name]?.addrs ?? []
                if let sa = p.pointee.ifa_addr {
                    var addr = sockaddr_storage()
                    memcpy(&addr, sa, MemoryLayout<sockaddr_storage>.size)
                    var hostBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    let saLen: socklen_t = {
                        switch Int32(sa.pointee.sa_family) {
                        case AF_INET: return socklen_t(MemoryLayout<sockaddr_in>.size)
                        case AF_INET6: return socklen_t(MemoryLayout<sockaddr_in6>.size)
                        default: return socklen_t(sa.pointee.sa_len)
                        }
                    }()
                    let code = withUnsafePointer(to: &addr) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sap in
                            getnameinfo(sap, saLen, &hostBuf, socklen_t(hostBuf.count),
                                         nil, 0, NI_NUMERICHOST)
                        }
                    }
                    if code == 0 {
                        addresses.append(String(cString: hostBuf))
                    }
                }
                byName[name] = (addresses, flags)
            }
            ptr = p.pointee.ifa_next
        }

        return byName.map { (name, tuple) in
            let flags = tuple.flags
            return InterfaceSnapshot(
                name: name,
                addresses: tuple.addrs,
                flagsHex: String(format: "0x%X", UInt32(bitPattern: flags)),
                hasPointToPoint: (flags & IFF_POINTOPOINT) != 0,
                hasBroadcast: (flags & IFF_BROADCAST) != 0,
                hasMulticast: (flags & IFF_MULTICAST) != 0,
                isUp: (flags & IFF_UP) != 0,
                isRunning: (flags & IFF_RUNNING) != 0
            )
        }.sorted { $0.name < $1.name }
    }
}
