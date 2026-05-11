---
phase: 01-foundation
plan: W2-killswitch-r6
type: execute
wave: 2
depends_on:
  - W0-bootstrap
files_modified:
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/iOS.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift
  - BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift
  - BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsTests.swift
  - BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift
  - BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift
autonomous: true
requirements:
  - SEC-04
  - KILL-01
  - KILL-02

must_haves:
  truths:
    - "TunnelSettings.makeR6Safe(...) возвращает NEPacketTunnelNetworkSettings с заполненными ipv4Settings"
    - "ipv4Settings.destinationAddresses == nil — R6: точка, в которой кончается весь P2P-флаг"
    - "ipv6Settings == nil в Phase 1 (IPv6 туннелирование — Phase 6)"
    - "NEIPv4Settings создаётся через init(addresses:subnetMasks:) без последующего вызова destinationAddresses setter'а"
    - "settings.dnsSettings.matchDomains == [\"\"] — защита от DNS-leak"
    - "settings.mtu == 1400 (sing-box safe default)"
    - "KillSwitch.apply(to:) выставляет includeAllNetworks=true и enforceRoutes=true на NETunnelProviderProtocol"
    - "KillSwitch.apply(to:) выставляет disconnectOnSleep=false"
    - "KillSwitch.apply(to:) НЕ трогает excludeLocalNetworks (оставляет дефолт)"
    - "DEBUG-сборка PacketTunnelKit умеет вызвать InterfaceFlagsInspector.assertNoPointToPointOnUtun() — runtime self-check R6"
  artifacts:
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift"
      provides: "R6-safe builder для NEPacketTunnelNetworkSettings (SEC-04)"
      contains: "public enum TunnelSettings"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/iOS.swift"
      provides: "iOS-specific quirks (Phase 1 — placeholder для будущих)"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift"
      provides: "macOS-specific hook (заглушка под Phase 10 R5 toggle)"
    - path: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift"
      provides: "Runtime R6 self-check (IFF_POINTOPOINT на utun*)"
      contains: "IFF_POINTOPOINT"
    - path: "BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift"
      provides: "KILL-01 / KILL-02 apply: includeAllNetworks + enforceRoutes"
      contains: "public enum KillSwitch"
  key_links:
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift"
      to: "NEIPv4Settings.init(addresses:subnetMasks:)"
      via: "R6: создание ipv4 без destinationAddresses"
      pattern: "NEIPv4Settings\\(addresses:"
    - from: "BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift"
      to: "NETunnelProviderProtocol.includeAllNetworks/.enforceRoutes"
      via: "выставить kill switch флаги при создании provider profile"
      pattern: "includeAllNetworks = true"
    - from: "BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift"
      to: "Phase 10 R5 toggle hook"
      via: "PlatformHooks.shouldDisableEnforceRoutes() — Phase 1 hardcoded false"
      pattern: "shouldDisableEnforceRoutes"
---

<objective>
**Wave 2 — Kill switch + R6.** Реализовать `TunnelSettings.makeR6Safe(...)` (избегая `destinationAddresses` на `NEIPv4Settings`/`NEIPv6Settings`, что предотвращает выставление `IFF_POINTOPOINT` флага на `utun*`), `InterfaceFlagsInspector.assertNoPointToPointOnUtun()` для runtime DEBUG-self-check, и `KillSwitch.apply(to:)` который выставляет `includeAllNetworks=true` + `enforceRoutes=true` на `NETunnelProviderProtocol`. Это вторая security-foundation волна, которая идёт параллельно с Wave 1 (обе зависят только от Wave 0).

Purpose: закрыть R6 (P2P=false, SEC-04) и KILL-01 / KILL-02 (системный kill switch) до того как Wave 3 запустит реальный туннель через libbox. Без этой волны Wave 3 либо построит туннель с дефолтным `destinationAddresses` (=R6 violation), либо забудет выставить `includeAllNetworks` (=KILL-01 violation). Wave 2 предотвращает оба сценария на уровне API: BaseSingBoxTunnel в Wave 3 не должен вручную строить `NEIPv4Settings` — он зовёт `TunnelSettings.makeR6Safe(...)`. И не должен трогать `NEVPNProtocol` в main app — он зовёт `KillSwitch.apply(to:)`.

Также Wave 2 кладёт заглушку под Phase 10 R5 toggle через `PlatformHooks.shouldDisableEnforceRoutes()` в `PlatformSpecific/macOS.swift` — в Phase 1 функция захардкожено возвращает `false`, но точка интеграции уже на месте.

Output:
- `TunnelSettings.makeR6Safe(serverAddress:dnsServers:)` — единственная точка построения `NEPacketTunnelNetworkSettings` в проекте.
- `InterfaceFlagsInspector` с `assertNoPointToPointOnUtun()` (DEBUG only) — Wave 3 BaseSingBoxTunnel вызовет после `setTunnelNetworkSettings`.
- `KillSwitch.apply(to: NETunnelProviderProtocol)` — единственная точка установки KILL-флагов.
- Unit-тесты: проверка инвариантов destinationAddresses == nil, ipv6Settings == nil, mtu == 1400, includeAllNetworks == true, enforceRoutes == true.
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/01-foundation/01-CONTEXT.md
@.planning/phases/01-foundation/01-RESEARCH.md
@.planning/phases/01-foundation/01-W0-bootstrap-SUMMARY.md
@CLAUDE.md
@prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md
@Wiki/security-gaps.md
@Wiki/kill-switch.md
@Wiki/apple-detection-surface.md

<interfaces>
<!-- Уже созданные интерфейсы из Wave 0; Wave 2 наполняет PacketTunnelKit и KillSwitch package'ы. -->

From RESEARCH §1 — NEIPv4Settings API:
```swift
open class NEIPv4Settings : NSObject {
    public init(addresses: [String], subnetMasks: [String])
    @NSCopying open var addresses: [String]
    @NSCopying open var subnetMasks: [String]?
    @NSCopying open var destinationAddresses: [String]?  // ← НЕ ИСПОЛЬЗОВАТЬ (R6!)
    @NSCopying open var includedRoutes: [NEIPv4Route]?
    @NSCopying open var excludedRoutes: [NEIPv4Route]?
}
```

From RESEARCH §1 — NEVPNProtocol / NETunnelProviderProtocol:
```swift
open class NEVPNProtocol : NSObject {
    open var includeAllNetworks: Bool    // ← KILL-01
    open var enforceRoutes: Bool         // ← R4
    open var excludeLocalNetworks: Bool  // НЕ выставляем
    open var disconnectOnSleep: Bool     // false
}
```

From RESEARCH §7 — Runtime self-check pattern для R6:
```swift
#if DEBUG
private func assertR6_NoP2P() {
    var addrs: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addrs) == 0, let first = addrs else { return }
    defer { freeifaddrs(addrs) }
    var ptr: UnsafeMutablePointer<ifaddrs>? = first
    while let p = ptr {
        let name = String(cString: p.pointee.ifa_name)
        if name.hasPrefix("utun") {
            let flags = Int32(p.pointee.ifa_flags)
            assert(flags & IFF_POINTOPOINT == 0,
                   "R6 violation: utun interface \(name) has IFF_POINTOPOINT flag set!")
        }
        ptr = p.pointee.ifa_next
    }
}
#endif
```

From CONTEXT.md §5 — IP range:
- `198.18.0.x/30` (RFC 2544 benchmarking range) — рекомендованный диапазон для tunnel IP
- subnetMask `255.255.255.0` (или `/24` для аналогии sing-box-for-apple)
</interfaces>
</context>

<tasks>

<task id="W2-T1" type="auto" tdd="true" autonomous="true">
  <name>Task W2-T1: TunnelSettings.makeR6Safe + InterfaceFlagsInspector + PlatformSpecific hooks с тестами</name>
  <files>
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/iOS.swift,
    BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift,
    BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §1 «NEPacketTunnelNetworkSettings + NEIPv4Settings (R6 — критическое!)» — финальный pattern + DEBUG runtime check
    - .planning/phases/01-foundation/01-RESEARCH.md §7 «R6 — P2P=false детальный план верификации»
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 2 (TunnelSettings без destinationAddresses; runtime check; macOS-stub под R5 в Phase 10)
    - Wiki/security-gaps.md R6 секция (контекст zachem)
    - Wiki/apple-detection-surface.md (откуда «P2P» как косвенный признак VPN)
    - prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md строки 237-239 (P2P=false требование)
  </read_first>
  <behavior>
    - **Test 1**: `TunnelSettings.makeR6Safe()` возвращает non-nil `NEPacketTunnelNetworkSettings` с `ipv4Settings != nil` и `ipv6Settings == nil`.
    - **Test 2 (R6 invariant)**: `settings.ipv4Settings!.destinationAddresses == nil` — критическая проверка R6.
    - **Test 3**: `settings.ipv4Settings!.addresses == ["198.18.0.1"]` (или whatever default передан).
    - **Test 4**: `settings.ipv4Settings!.subnetMasks == ["255.255.255.0"]`.
    - **Test 5**: `settings.ipv4Settings!.includedRoutes != nil && includedRoutes!.contains(where: { $0 === NEIPv4Route.default() || ... })` — default route включена.
    - **Test 6**: `settings.dnsSettings!.servers == ["1.1.1.1", "1.0.0.1"]` (default) и `matchDomains == [""]`.
    - **Test 7**: `settings.mtu == 1400`.
    - **Test 8**: при кастомных `tunnelIP: "10.0.0.42"` и `dnsServers: ["9.9.9.9"]` — settings отражают эти значения.
    - **Test 9 (InterfaceFlagsInspector)**: `InterfaceFlagsInspector.utunSnapshot()` возвращает массив (на тестовой macOS машине обычно есть `utun0`/`utun1`); ни одна запись НЕ имеет `hasPointToPoint == true` без активного VPN (это test-only smoke — на CI без VPN; если на машине разработчика есть посторонний VPN, тест может flake-but-acceptable).
    - **Test 10**: `PlatformHooks.shouldDisableEnforceRoutes()` в Phase 1 захардкожено возвращает `false` (на iOS — undefined, returns false; на macOS — Phase 1 default false).
  </behavior>
  <action>
1. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`** — главный билдер NEPacketTunnelNetworkSettings:
```swift
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
            mtu: Int = 1400
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
```

2. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift`** — runtime R6 self-check:
```swift
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
    public static func assertNoPointToPointOnUtun(
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #if DEBUG
        let violations = utunSnapshot().filter { $0.hasPointToPoint }
        assert(
            violations.isEmpty,
            "R6 violation: \(violations.map { "\($0.name) [\($0.flagsHex)]" }.joined(separator: ", ")) has IFF_POINTOPOINT flag set!",
            file: file,
            line: line
        )
        #endif
    }
}
```

3. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/iOS.swift`:**
```swift
#if os(iOS)
import Foundation

/// iOS-specific hooks для PacketTunnelKit.
///
/// Phase 1 — placeholder. Будущие фазы могут добавить:
/// - Pasteboard auto-detect (Phase 11)
/// - iOS-specific extension memory accounting (Phase 6+)
public enum PlatformHooks {
    /// CORE-os: на iOS нет R5 toggle — `enforceRoutes` всегда `true` (см. R4 default).
    public static func shouldDisableEnforceRoutes() -> Bool {
        return false
    }
}
#endif
```

4. **`BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift`:**
```swift
#if os(macOS)
import Foundation

/// macOS-specific hooks для PacketTunnelKit.
///
/// **Phase 10 заглушка:** `shouldDisableEnforceRoutes()` пока всегда возвращает `false`,
/// но точка интеграции уже определена. Когда в Phase 10 (R5) появится UI-тоггл
/// «Отключить принудительную маршрутизацию», эта функция будет читать UserDefaults
/// или SwiftData-флаг и возвращать его. KillSwitch.apply(to:) уже учитывает эту функцию,
/// так что Phase 10 не потребует менять KillSwitch — только эту implementation.
public enum PlatformHooks {
    /// R5 (Phase 10): macOS-only тоггл в Расширенных. Phase 1 — hardcoded false.
    public static func shouldDisableEnforceRoutes() -> Bool {
        return false
    }
}
#endif
```

5. **`BBTB/Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/TunnelSettingsTests.swift`:**
```swift
import XCTest
import NetworkExtension
@testable import PacketTunnelKit

final class TunnelSettingsTests: XCTestCase {

    // MARK: R6 critical invariants

    func test_makeR6Safe_doesNotSetDestinationAddresses() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertNotNil(settings.ipv4Settings, "ipv4Settings must be non-nil")
        // R6: destinationAddresses MUST remain nil
        XCTAssertNil(
            settings.ipv4Settings?.destinationAddresses,
            "R6 violation: destinationAddresses is set — utun will get IFF_POINTOPOINT"
        )
    }

    func test_makeR6Safe_ipv6Settings_areNilOnPhase1() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertNil(settings.ipv6Settings, "Phase 1: IPv6 blocked at OS level (NET-05+06 in Phase 6)")
    }

    // MARK: Default values

    func test_makeR6Safe_default_tunnelIP() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["198.18.0.1"])
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.0"])
    }

    func test_makeR6Safe_includesDefaultRoute() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        let routes = settings.ipv4Settings?.includedRoutes ?? []
        XCTAssertFalse(routes.isEmpty, "Must include default route to push all IPv4 traffic into tunnel")
    }

    func test_makeR6Safe_dnsServers() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.dnsSettings?.servers, ["1.1.1.1", "1.0.0.1"])
        XCTAssertEqual(settings.dnsSettings?.matchDomains, [""], "matchDomains [\"\"] is the DNS-leak protection")
    }

    func test_makeR6Safe_mtu() {
        let settings = TunnelSettings.makeR6Safe(serverAddress: "example.com")
        XCTAssertEqual(settings.mtu?.intValue, 1400, "sing-box safe default MTU")
    }

    // MARK: Custom inputs

    func test_makeR6Safe_customInputs() {
        let inputs = TunnelSettings.Inputs(
            tunnelIP: "10.0.0.42",
            tunnelSubnetMask: "255.255.255.252",
            serverAddress: "your.server.example",
            dnsServers: ["9.9.9.9", "149.112.112.112"],
            mtu: 1500
        )
        let settings = TunnelSettings.makeR6Safe(inputs)
        XCTAssertEqual(settings.ipv4Settings?.addresses, ["10.0.0.42"])
        XCTAssertEqual(settings.ipv4Settings?.subnetMasks, ["255.255.255.252"])
        XCTAssertEqual(settings.dnsSettings?.servers, ["9.9.9.9", "149.112.112.112"])
        XCTAssertEqual(settings.mtu?.intValue, 1500)
        XCTAssertNil(settings.ipv4Settings?.destinationAddresses, "R6 still holds for custom inputs")
    }

    // MARK: InterfaceFlagsInspector (smoke)

    func test_interfaceFlagsInspector_returnsArray() {
        // На CI / macOS без VPN — обычно есть utun0/utun1 от системных служб (Continuity, FaceTime).
        // Не утверждаем что массив не пустой (может быть на новой headless-машине), только что
        // вызов не падает и возвращает корректные данные.
        let snapshot = InterfaceFlagsInspector.utunSnapshot()
        for iface in snapshot {
            XCTAssertTrue(iface.name.hasPrefix("utun"), "Filter must restrict to utun*")
            XCTAssertFalse(iface.flagsHex.isEmpty)
        }
    }

    // MARK: PlatformHooks

    func test_platformHooks_shouldDisableEnforceRoutes_isFalseInPhase1() {
        // Phase 10 (R5) включит этот тоггл на macOS. В Phase 1 — всегда false для обеих платформ.
        XCTAssertFalse(PlatformHooks.shouldDisableEnforceRoutes())
    }
}
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "public enum TunnelSettings" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "public static func makeR6Safe" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "NEIPv4Settings(addresses:" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `! grep -q "destinationAddresses = " BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift` (R6 invariant — destinationAddresses не присваивается)
    - `grep -q "settings.ipv6Settings = nil" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "matchDomains = \[\"\"\]" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "mtu = NSNumber(value: inputs.mtu)" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`
    - `grep -q "IFF_POINTOPOINT" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift`
    - `grep -q "public static func assertNoPointToPointOnUtun" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift`
    - `grep -q "#if DEBUG" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/InterfaceFlagsInspector.swift`
    - `grep -q "#if os(iOS)" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/iOS.swift`
    - `grep -q "#if os(macOS)" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift`
    - `grep -q "Phase 10" BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/PlatformSpecific/macOS.swift`
    - Все 9 unit-тестов TunnelSettingsTests + 1 InterfaceFlagsInspector smoke + 1 PlatformHooks = ~11 тестов pass через xcodebuild test
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64' -only-testing:PacketTunnelKitTests/TunnelSettingsTests -quiet 2>&amp;1 | grep -E "Test Suite 'TunnelSettingsTests'.*passed|Executed [0-9]+ tests"</automated>
  </verify>
  <done>TunnelSettings.makeR6Safe реализован, R6 invariant покрыт unit-тестом который явно ассертит `destinationAddresses == nil`; InterfaceFlagsInspector умеет делать runtime self-check в DEBUG; PlatformHooks-заглушки на месте на обеих платформах.</done>
</task>

<task id="W2-T2" type="auto" tdd="true" autonomous="true">
  <name>Task W2-T2: KillSwitch.apply(to:) — wrapper для KILL-01 + KILL-02 + R4 default</name>
  <files>
    BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift,
    BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift
  </files>
  <read_first>
    - .planning/phases/01-foundation/01-RESEARCH.md §6 «Kill switch (KILL-01, KILL-02)» — точная реализация KillSwitch.apply
    - .planning/phases/01-foundation/01-RESEARCH.md §1 «NEVPNProtocol / NETunnelProviderProtocol»
    - .planning/phases/01-foundation/01-CONTEXT.md §4 Wave 2 (KillSwitch + TunnelSettings — обе security-foundation вместе)
    - Wiki/kill-switch.md (контекст trade-off enforceRoutes)
    - Wiki/security-gaps.md R4 (R4 default = enforceRoutes=true, R5 toggle — Phase 10)
    - prompts/v2 строки 228-235 (Kill switch system-level)
  </read_first>
  <behavior>
    - **Test 1**: после `KillSwitch.apply(to: proto)` имеем `proto.includeAllNetworks == true`.
    - **Test 2**: `proto.enforceRoutes == true` (R4 default).
    - **Test 3**: `proto.disconnectOnSleep == false`.
    - **Test 4**: `proto.excludeLocalNetworks == false` (по умолчанию NEVPNProtocol даёт false; убедиться что мы его не выставили в true).
    - **Test 5**: повторный `apply` идемпотентен — те же флаги.
    - **Test 6**: на macOS если `shouldDisableEnforceRoutes()` вернёт true (Phase 10 hook) → `enforceRoutes = false` (но в Phase 1 это всегда false на обеих платформах, поэтому тест проверит дефолт).
  </behavior>
  <action>
1. **`BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`** (заменить placeholder из Wave 0):
```swift
import Foundation
import NetworkExtension

/// **KILL-01, KILL-02, R4 default.**
///
/// Единственная точка установки kill switch флагов на `NETunnelProviderProtocol`.
/// Вызывается из main app (Wave 4 ConfigImporter) при создании
/// `NETunnelProviderManager`'а. Никакой другой код не должен трогать
/// `includeAllNetworks` / `enforceRoutes` напрямую.
///
/// **Архитектурная связь:**
/// - Wave 4 `ConfigImporter` → создаёт `NETunnelProviderProtocol` → `KillSwitch.apply(to:)`
/// - Phase 2 (v0.2) добавит KILL-03 toggle (Расширенные → «Отключить kill switch»)
/// - Phase 10 (v0.10) добавит R5 macOS-toggle через `PlatformHooks.shouldDisableEnforceRoutes()`
///   — реализация уже учитывает это hook'ом ниже.
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol) {
        // KILL-01: системный kill switch (iOS 14+, macOS 11+)
        proto.includeAllNetworks = true

        // R4: enforceRoutes default (DNS-leak protection приоритетнее снижения детекта).
        // Phase 10 R5 hook: на macOS может вернуть true, тогда enforceRoutes=false.
        // В Phase 1 hook всегда возвращает false → enforceRoutes остаётся true.
        proto.enforceRoutes = !platformShouldDisableEnforceRoutes()

        // НЕ выставляем excludeLocalNetworks — нам нужен maximum lockdown.
        proto.excludeLocalNetworks = false

        // Всегда в туннеле — disconnectOnSleep=false важно для On-Demand (Phase 10).
        proto.disconnectOnSleep = false
    }

    // MARK: Platform-specific hook (R5 Phase 10)

    /// Phase 1 — hardcoded false на обеих платформах. Phase 10 на macOS включит чтение
    /// UserDefaults / SwiftData флага.
    private static func platformShouldDisableEnforceRoutes() -> Bool {
        // Импортировать PlatformHooks из PacketTunnelKit нельзя (KillSwitch не зависит от PacketTunnelKit
        // по архитектуре — он используется в main app, PacketTunnelKit в extension).
        // Phase 10 заменит на чтение @AppStorage/UserDefaults флага.
        return false
    }
}
```

2. **`BBTB/Packages/KillSwitch/Tests/KillSwitchTests/KillSwitchTests.swift`** (создать testTarget; Package.swift уже имеет .testTarget в Wave 0):
```swift
import XCTest
import NetworkExtension
@testable import KillSwitch

final class KillSwitchTests: XCTestCase {

    func test_apply_setsIncludeAllNetworks() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        XCTAssertTrue(proto.includeAllNetworks, "KILL-01: includeAllNetworks must be true")
    }

    func test_apply_setsEnforceRoutes_inPhase1() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        // R4 default — enforceRoutes=true в Phase 1 (Phase 10 даст macOS-toggle).
        XCTAssertTrue(proto.enforceRoutes, "R4 default: enforceRoutes must be true in Phase 1")
    }

    func test_apply_disconnectOnSleep_isFalse() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        XCTAssertFalse(proto.disconnectOnSleep, "KILL-02: tunnel must persist across sleep")
    }

    func test_apply_excludeLocalNetworks_isFalse() {
        let proto = NETunnelProviderProtocol()
        proto.excludeLocalNetworks = true  // simulate alien code setting it
        KillSwitch.apply(to: proto)
        XCTAssertFalse(proto.excludeLocalNetworks,
                       "Maximum lockdown: excludeLocalNetworks must be false")
    }

    func test_apply_isIdempotent() {
        let proto = NETunnelProviderProtocol()
        KillSwitch.apply(to: proto)
        let snapshot = (
            proto.includeAllNetworks,
            proto.enforceRoutes,
            proto.disconnectOnSleep,
            proto.excludeLocalNetworks
        )
        KillSwitch.apply(to: proto)
        XCTAssertEqual(snapshot.0, proto.includeAllNetworks)
        XCTAssertEqual(snapshot.1, proto.enforceRoutes)
        XCTAssertEqual(snapshot.2, proto.disconnectOnSleep)
        XCTAssertEqual(snapshot.3, proto.excludeLocalNetworks)
    }
}
```
  </action>
  <acceptance_criteria>
    - `test -f BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "public enum KillSwitch" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "public static func apply(to proto: NETunnelProviderProtocol)" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "proto.includeAllNetworks = true" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "proto.enforceRoutes = !platformShouldDisableEnforceRoutes()" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "proto.disconnectOnSleep = false" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "proto.excludeLocalNetworks = false" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `grep -q "Phase 10" BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift`
    - `xcodebuild test -workspace BBTB.xcworkspace -scheme KillSwitch -destination 'platform=macOS,arch=arm64' -quiet` завершается с TEST SUCCEEDED и 5 тестами
  </acceptance_criteria>
  <verify>
    <automated>cd /Users/vergevsky/ClaudeProjects/VPN && xcodebuild test -workspace BBTB.xcworkspace -scheme KillSwitch -destination 'platform=macOS,arch=arm64' -quiet 2>&amp;1 | grep -E "Test Suite 'KillSwitchTests'.*passed|Executed [0-9]+ tests"</automated>
  </verify>
  <done>KillSwitch.apply реализован; все 5 unit-тестов KillSwitchTests pass; KILL-01, KILL-02, R4 default закрыты на API-уровне.</done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Wave 3 BaseSingBoxTunnel → NEPacketTunnelNetworkSettings | Должен звать TunnelSettings.makeR6Safe; manual construction NEIPv4Settings бы обошёл R6 защиту. Wave 3 PLAN.md обязан включить grep что в BaseSingBoxTunnel нет `NEIPv4Settings(` вне TunnelSettings module |
| Wave 4 ConfigImporter → NETunnelProviderProtocol | Должен звать KillSwitch.apply; manual установка флагов = регрессия |
| utun interface state → DEBUG assertion | InterfaceFlagsInspector.assertNoPointToPointOnUtun() — only DEBUG; в Release это ничего не проверит. Production verification — SocksProbe (Wave 5) |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-01-W2-01 | Information Disclosure | utun-интерфейс с IFF_POINTOPOINT детектируется как VPN методичкой РКН | mitigate | TunnelSettings.makeR6Safe — единственная точка построения settings; `destinationAddresses` физически не присваивается в коде; unit-тест ассертит `XCTAssertNil(destinationAddresses)`; runtime DEBUG check через InterfaceFlagsInspector; SocksProbe Wave 5 — production check |
| T-01-W2-02 | Tampering | Регрессия — кто-то добавит `ipv4.destinationAddresses = [...]` через PR | mitigate | unit-тест test_makeR6Safe_doesNotSetDestinationAddresses падает; grep в Wave 3 acceptance `! grep destinationAddresses = ` |
| T-01-W2-03 | Denial of Service | Tunnel падает → трафик утекает мимо VPN | mitigate | KillSwitch.apply ставит includeAllNetworks=true → ОС блокирует весь трафик при падении extension; KILL-02 verification — Wave 5 manual smoke (отключение сервера → нет интернета) |
| T-01-W2-04 | Information Disclosure | DNS-запросы утекают в bypass | mitigate | TunnelSettings.dnsSettings.matchDomains = [""] (все запросы через VPN); enforceRoutes=true (R4); KillSwitch блокирует bypass |
| T-01-W2-05 | Information Disclosure | iOS 16.1+ leak: трафик к Apple-серверам всегда idёт мимо VPN при includeAllNetworks=true | accept | Системное ограничение Apple; задокументировано в Wiki/security-gaps.md и в Phase 11 FAQ; не наша ответственность |
</threat_model>

<verification>
**Wave 2 проверки:**

1. **Unit tests green (TunnelSettings + KillSwitch + InterfaceFlagsInspector smoke):**
   ```bash
   xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64' -only-testing:PacketTunnelKitTests/TunnelSettingsTests -quiet
   xcodebuild test -workspace BBTB.xcworkspace -scheme KillSwitch -destination 'platform=macOS,arch=arm64' -quiet
   ```
   Должны вывести TEST SUCCEEDED.

2. **R6 source code invariant:**
   ```bash
   # `destinationAddresses =` (с любыми пробелами) должно встречаться ТОЛЬКО как `nil` или `XCTAssertNil(...destinationAddresses)`,
   # никогда как присваивание массива/строки внутри Sources/.
   ! grep -rE "destinationAddresses\s*=" BBTB/Packages/PacketTunnelKit/Sources/
   ```

3. **API surface (Wave 3 предзависимость):**
   - `TunnelSettings.makeR6Safe(serverAddress:)` доступен публично
   - `InterfaceFlagsInspector.assertNoPointToPointOnUtun()` доступен публично
   - `KillSwitch.apply(to:)` доступен публично

**Не верифицируется в Wave 2:**
- Реальный `setTunnelNetworkSettings` вызов и его эффект на `utun*` — Wave 3.
- KILL-02 manual smoke (отключить сервер → нет интернета) — Wave 5.
- R6 production check через SocksProbe — Wave 5.
</verification>

<success_criteria>
Wave 2 завершён когда:

- [ ] `TunnelSettings.makeR6Safe` реализован — единственная точка построения NEPacketTunnelNetworkSettings в проекте.
- [ ] R6 invariant защищён unit-тестом `test_makeR6Safe_doesNotSetDestinationAddresses` (assertion `XCTAssertNil(...destinationAddresses)`).
- [ ] `InterfaceFlagsInspector.assertNoPointToPointOnUtun()` реализован (#if DEBUG); Wave 3 будет вызывать после `setTunnelNetworkSettings`.
- [ ] `PlatformHooks.shouldDisableEnforceRoutes()` существует на обеих платформах (Phase 1 = всегда false; Phase 10 заменит на macOS).
- [ ] `KillSwitch.apply(to:)` устанавливает все 4 флага (`includeAllNetworks=true`, `enforceRoutes=true`, `disconnectOnSleep=false`, `excludeLocalNetworks=false`).
- [ ] Unit-тесты KillSwitchTests (5 тестов) и TunnelSettingsTests (≥9 тестов) проходят через xcodebuild test.
- [ ] Source-code grep ассертит что `destinationAddresses =` присваивание НЕ встречается в `BBTB/Packages/PacketTunnelKit/Sources/`.
</success_criteria>

<output>
After completion, create `.planning/phases/01-foundation/01-W2-killswitch-r6-SUMMARY.md` с:
- Список созданных типов с их публичными API (signature lines)
- Снимок вывода `xcodebuild test` (последние 10 строк) для PacketTunnelKit и KillSwitch scheme
- Заметка для Wave 3 — где именно `BaseSingBoxTunnel` обязан вызвать `TunnelSettings.makeR6Safe` и `InterfaceFlagsInspector.assertNoPointToPointOnUtun`
- Заметка для Wave 4 — где `ConfigImporter` обязан вызвать `KillSwitch.apply(to:)`
- Заметка для Phase 10 — что нужно изменить в `PlatformSpecific/macOS.swift` + `KillSwitch.swift` для добавления R5 toggle
</output>
