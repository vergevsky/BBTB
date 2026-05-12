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
///
/// **Phase 6 / Wave 2 (NET-05/06, D-06):** NEIPv6Settings настроен на blackhole
/// (ULA fd00::1/128 + ::/0 includedRoute), заменив Phase 1 nil placeholder.
/// Парный sing-box patch — `SingBoxConfigLoader.expandConfigForTunnel` (добавлен
/// `fd00::1/126` в address + `route_address: ["::/0"]`).
public enum TunnelSettings {
    public struct Inputs {
        public let tunnelIP: String
        public let tunnelSubnetMask: String
        public let serverAddress: String  // server.com — отображается в Settings → VPN
        public let dnsServers: [String]
        public let mtu: Int

        public init(
            tunnelIP: String = "198.18.0.1",
            tunnelSubnetMask: String = "255.255.255.240",  // /28 — Phase 1 W5 plan B.2
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

        // Phase 6 / Wave 2 (D-06, NET-05/06) — IPv6 blackhole.
        //
        // ULA адрес fd00::1/128 из RFC 4193 (fd00::/8). Upstream v6 gateway'я нет —
        // пакеты входят в TUN через `::/0` includedRoute и droppаются внутри sing-box
        // (никакого v6 outbound не настроено). Закрывает leak, описанный в
        // 06-RESEARCH.md Pitfall 1: «nil NEIPv6Settings → v6 трафик идёт мимо TUN».
        //
        // R6 invariant: НИКОГДА не выставлять ipv6.destinationAddresses — тот же
        // капкан что и для ipv4 (создаст IFF_POINTOPOINT флаг на utun*, см. R6 в
        // wiki/security-gaps.md).
        let ipv6 = NEIPv6Settings(addresses: ["fd00::1"],
                                   networkPrefixLengths: [NSNumber(value: 128)])
        ipv6.includedRoutes = [NEIPv6Route.default()]
        ipv6.excludedRoutes = []
        settings.ipv6Settings = ipv6

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
