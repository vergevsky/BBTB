import Foundation
import NetworkExtension

/// R6-safe builder для NEPacketTunnelNetworkSettings.
///
/// **SEC-04 / R6 (CRITICAL):** этот тип — ЕДИНСТВЕННАЯ точка в коде, где строится
/// `NEPacketTunnelNetworkSettings`. BaseSingBoxTunnel (Wave 3) и любой другой
/// код в проекте должны вызывать только `makeR6Safe(...)`. Это гарантирует, что
/// `NEIPv4Settings.destinationAddresses` НИКОГДА не выставляется — иначе ОС
/// автоматически выставит флаг `IFF_POINTOPOINT` на интерфейсе `utun*`, что и
/// есть «P2P=true» в терминологии методички РКН (см. Wiki/apple-detection-surface.md).
///
/// **Архитектурная связь:**
/// - Wave 3 `BaseSingBoxTunnel.openTun(_:)` (через ExtensionPlatformInterface) → `makeR6Safe`
/// - Wave 3 `BaseSingBoxTunnel.startTunnel` → `setTunnelNetworkSettings(result)` → assert через `InterfaceFlagsInspector`
/// - Wave 5 SocksProbe (внешняя проверка) использует `InterfaceInspector` (отдельный, в Tools/) — это второй уровень
public enum TunnelSettings {
    public struct Inputs {
        public let tunnelIP: String
        public let tunnelSubnetMask: String
        public let serverAddress: String  // server.com — отображается в Settings → VPN
        public let dnsServers: [String]
        public let mtu: Int

        public init(
            tunnelIP: String = "198.18.0.1",
            tunnelSubnetMask: String = "255.255.255.0",
            serverAddress: String,
            dnsServers: [String] = ["1.1.1.1", "1.0.0.1"],
            mtu: Int = 1500
        ) {
            self.tunnelIP = tunnelIP
            self.tunnelSubnetMask = tunnelSubnetMask
            self.serverAddress = serverAddress
            self.dnsServers = dnsServers
            self.mtu = mtu
        }
    }

    /// R6: P2P=false. Использует `subnetMasks`, НИКОГДА не `destinationAddresses`.
    /// Это превращает `utun*` в обычный network interface, не point-to-point.
    public static func makeR6Safe(_ inputs: Inputs) -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: inputs.serverAddress)

        let ipv4 = NEIPv4Settings(addresses: [inputs.tunnelIP],
                                  subnetMasks: [inputs.tunnelSubnetMask])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // R6 critical (см. Wiki/security-gaps.md R6 + RESEARCH §1):
        //   ipv4.destinationAddresses НЕ выставляется — это превратит utun в IFF_POINTOPOINT.
        settings.ipv4Settings = ipv4

        // IPv6 — Phase 6 (NET-05..07). На v0.1 — nil (заблокирован на уровне OS).
        settings.ipv6Settings = nil

        let dns = NEDNSSettings(servers: inputs.dnsServers)
        dns.matchDomains = [""]  // ← все DNS-запросы через VPN (защита от DNS leak)
        settings.dnsSettings = dns

        settings.mtu = NSNumber(value: inputs.mtu)
        return settings
    }

    /// Удобная overload-сигнатура для типичных случаев (Wave 3 вызовет это).
    public static func makeR6Safe(serverAddress: String) -> NEPacketTunnelNetworkSettings {
        makeR6Safe(Inputs(serverAddress: serverAddress))
    }
}
