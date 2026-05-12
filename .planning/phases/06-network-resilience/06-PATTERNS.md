# Phase 6: Network Resilience — Pattern Map

**Mapped:** 2026-05-13
**Files analyzed:** 9 (3 new, 6 modified — including ReconnectBanner reuse-only)
**Analogs found:** 8 / 9

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `VPNCore/DNSConfig.swift` (new) | model (value-type config) | transform/persisted | `VPNCore/TransportConfig.swift` | exact (Phase 5 sibling) |
| `AdvancedSettingsView.swift` (new) | component (SwiftUI Form) | request-response | `SettingsFeature/SettingsView.swift` + `KillSwitchToggleSection.swift` | exact |
| `RetryStateMachine` (new — место уточнит планер) | service (state machine) | event-driven (timer + NWPath) | `MainScreenFeature/TunnelController.swift` (polling loop) + `MainScreenViewModel.reconnectAfterSelectionChange` | role-match |
| `NWPathMonitor wrapper` (new — место уточнит планер) | service (observer) | event-driven (path callbacks) | `PacketTunnelKit/ExtensionPlatformInterface.swift` lines 247–315 | exact |
| `ConfigParser/PoolBuilder.swift` (modified) | service (config builder) | transform | — (self) | self |
| `App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift` + macOS (modified) | controller (NEPacketTunnelProvider shell) | request-response | — (self, almost-empty shells) | self |
| `PacketTunnelKit/TunnelSettings.swift` (modified) | service (settings builder) | transform | — (self) | self |
| `SettingsFeature/SettingsViewModel.swift` (modified) | model (ObservableObject) | persisted (AppStorage) | — (self) | self |
| `MainScreenFeature/TunnelController.swift` (modified) | controller (NETunnelProviderManager wrapper) | request-response + polling | — (self) | self |
| `MainScreenFeature/ReconnectBanner.swift` (reuse) | component (SwiftUI) | request-response | — (already exists, see «Modified» section ниже) | self |

---

## Pattern Assignments — New Files

### `VPNCore/DNSConfig.swift` (model, transform)

**Analog:** `BBTB/Packages/VPNCore/Sources/VPNCore/TransportConfig.swift` (50 lines, Phase 5/CORE-03, недавно добавлен).

**Why this is the right analog:**
- Тоже value-type конфиг внутри `VPNCore` (никаких зависимостей кроме Foundation).
- Тоже передаётся вниз по графу в builder'ы (`TransportConfig` → `*.ConfigBuilder.buildOutbound`; `DNSConfig` → `PoolBuilder.dnsBlock`).
- Тоже `Codable`/`Sendable`/`Equatable` для SwiftData lightweight migration и для теста-сравнений.
- Тоже хочется *single source of truth* для wire-format-идентификаторов (для `DNSConfig` — список bootstrap-серверов и адрес туннельного DNS).

**Imports pattern** (`TransportConfig.swift:1`):
```swift
import Foundation
```
Только `Foundation`. Никакого `SwiftUI`, `NetworkExtension`, `Network`.

**Header doc pattern** (`TransportConfig.swift:3-18`):
```swift
/// Phase 5 / CORE-03 — shared transport overlay type для всех VPN-протоколов
/// (Decision D-04 в `.planning/phases/05-transports/05-CONTEXT.md`).
///
/// Один enum заменяет per-protocol `TransportType` (...). При 15+ протоколах × N
/// транспортах это единое место правки — каждый новый транспорт добавляется
/// как один case плюс один handler в `TransportRegistry`.
///
/// Codable: используется synthesized conformance (SE-0295, Swift 5.5+) — никаких
/// custom `CodingKeys` / `init(from:)` / `encode(to:)`, это снижает риск
/// рассинхрона при будущих SwiftData миграциях.
```
**Copy this pattern:** заголовочный doc должен ссылаться на `.planning/phases/06-network-resilience/06-CONTEXT.md` (D-01..D-05) и явно сказать «один тип — три параметра DNS-стратегии (bootstrap / tunnel / adBlock)».

**Type declaration pattern** (`TransportConfig.swift:19-49`):
```swift
public enum TransportConfig: Sendable, Equatable, Codable, Hashable {
    case tcp
    case ws(path: String, host: String)
    case grpc(serviceName: String)
    case http(path: String)
    case httpUpgrade(path: String, host: String)

    /// Wire-уровневый идентификатор: совпадает с `type` в sing-box outbound JSON.
    public var identifier: String {
        switch self {
        case .tcp:         return "tcp"
        case .ws:          return "ws"
        ...
        }
    }
}
```

**Key conformances to copy:** `Sendable, Equatable, Codable, Hashable` — этот же набор нужен `DNSConfig` (Sendable для передачи в actor-isolated `TunnelController`, Codable для persistence, Equatable для тестов, Hashable если когда-нибудь окажется в `Set`/`Dictionary`).

**Shape suggestion для `DNSConfig`** (NOT prescription — финал решит планер по D-01..D-04):

```swift
public struct DNSConfig: Sendable, Equatable, Codable, Hashable {
    /// Bootstrap-серверы — используются ДО поднятия туннеля (виден ТСПУ).
    /// D-01: трёхступенчатый порядок [server.IP, "94.140.14.14", "1.1.1.1"].
    /// PoolBuilder выберет первый валидный.
    public let bootstrapServers: [String]

    /// Туннельный DNS (приоритет: customDNS → AdGuard если AdBlock → Cloudflare).
    /// D-02..D-04: уже разрешённое значение, без логики выбора в `DNSConfig`.
    public let tunnelDNS: String

    /// D-04 — флаг для аналитики/логов (не используется PoolBuilder напрямую,
    /// логика выбора tunnelDNS уже отработала на уровне `SettingsViewModel`).
    public let adBlockEnabled: Bool

    public static let `default` = DNSConfig(
        bootstrapServers: ["94.140.14.14", "1.1.1.1"],
        tunnelDNS: "1.1.1.1",
        adBlockEnabled: false
    )

    public init(bootstrapServers: [String], tunnelDNS: String, adBlockEnabled: Bool) {
        self.bootstrapServers = bootstrapServers
        self.tunnelDNS = tunnelDNS
        self.adBlockEnabled = adBlockEnabled
    }
}
```

**Файл должен лежать:** `BBTB/Packages/VPNCore/Sources/VPNCore/DNSConfig.swift`.
**Package.swift не нужно править** — `VPNCore` собирает `.target(name: "VPNCore")` без явного `sources:` (см. `BBTB/Packages/VPNCore/Package.swift:7-10`), новые `.swift` файлы подхватываются автоматически.

---

### `AdvancedSettingsView.swift` (component, request-response)

**Analog 1 (container/Form):** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsView.swift` (30 lines).
**Analog 2 (toggle row):** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/KillSwitchToggleSection.swift` (19 lines).

**Why these are the right analogs:**
- Тот же модуль (`SettingsFeature`) — навигация уже корректно завязана из `SettingsView` → `AdvancedSettingsView` через `NavigationLink`/`NavigationStack` (где именно — пусть решит планер на основе CONTEXT D-03/D-04).
- `SettingsView` показывает шаблон **`Form` + `Section { ... } header: { ... } footer: { ... }`**.
- `KillSwitchToggleSection` показывает шаблон **отдельной reusable `View`-обёртки над `@Binding Bool` с L10n-меткой**.

**Container pattern — `SettingsView.swift:5-30` (полностью):**
```swift
public struct SettingsView: View {
    @ObservedObject public var viewModel: SettingsViewModel

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section {
                KillSwitchToggleSection(
                    isOn: $viewModel.killSwitchEnabled,
                    footerText: L10n.settingsKillSwitchFooter
                )
            } header: {
                Text(L10n.settingsSecuritySection)
            } footer: {
                Text(L10n.settingsKillSwitchFooter)
            }
        }
        .navigationTitle(L10n.settingsTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
    }
}
```

**Toggle-row pattern — `KillSwitchToggleSection.swift:5-18` (полностью):**
```swift
public struct KillSwitchToggleSection: View {
    @Binding public var isOn: Bool
    public let footerText: String

    public init(isOn: Binding<Bool>, footerText: String) {
        self._isOn = isOn
        self.footerText = footerText
    }

    public var body: some View {
        Toggle(L10n.settingsKillSwitchLabel, isOn: $isOn)
            .accessibilityHint(Text(footerText))
    }
}
```

**Patterns to copy для `AdvancedSettingsView`:**
1. `@ObservedObject public var viewModel: SettingsViewModel` — тот же VM, не создавай отдельный.
2. `public init(viewModel: SettingsViewModel) { ... }` — explicit init для public type из библиотеки (без него SwiftPM не даёт использовать структуру cross-module).
3. `Form { Section { ... } header: { Text(L10n....) } footer: { Text(L10n....) } }` — для секции «DNS».
4. Toggle row для AdBlock → отдельный `AdBlockToggleSection` (mirror `KillSwitchToggleSection`).
5. Text-field для Custom DNS → новый `CustomDNSField` со своим `@Binding String` (можно сделать inline, но reusable wrapper — каноничнее для модуля).
6. `#if os(iOS) .navigationBarTitleDisplayMode(.large) #endif` — обязательная iOS-only ветка для navigation title.
7. Все строки **через `L10n.tr("...")`** — новые ключи в `BBTB/Packages/Localization/Sources/Localization/L10n.swift` (см. существующие `settingsKillSwitchLabel` / `settingsKillSwitchFooter` как образец naming).

**Файл должен лежать:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` (рядом с `SettingsView.swift`).
**Package.swift НЕ требует правки** — target `SettingsFeature` собирает всё содержимое директории; зависимостей у нового view хватает (`VPNCore` для `DNSConfig`, `Localization` для `L10n`, `DesignSystem` если будут пользовательские стили — все три уже в `dependencies: [...]` target'а, см. `Package.swift:43-45`).

---

### Retry state machine (new — место выбирает планер)

**Analog 1 (polling loop):** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift:26-53` — `for _ in 0..<30 { try await Task.sleep ... switch status { case .connected: ...; case .invalid, .disconnected: throw } }`.
**Analog 2 (reconnect-on-event):** `MainScreenViewModel.swift:344-359` (`reconnectAfterSelectionChange`) — state-машина из 3 шагов (`disconnect` → `provision` → `connect`) с `do/catch`-ловлей `MainScreenError`.
**Analog 3 (throttle):** `ConfigImporter.runIsSupportedUpgrade` (`MainScreenFeature/ConfigImporter.swift:782-823`) — UserDefaults-throttle на 5 минут.

**Why these are the right analogs:**
- В кодбазе **нет** готового retry-state-machine класса; ближайший по структуре — поллинг в `TunnelController.connect()` и линейная reconnect-sequence в `MainScreenViewModel`. Планер должен явно зафиксировать, что это **новая абстракция**, без перекладывания всей логики в `TunnelController` (там уже достаточно ответственности).

**Polling pattern (TunnelController.swift:26-38):**
```swift
let started = Date()
for _ in 0..<30 {
    try await Task.sleep(nanoseconds: 1_000_000_000)
    switch manager.connection.status {
    case .connected: return started
    case .invalid, .disconnected:
        throw NSError(domain: "BBTB.TunnelController", code: -2,
                      userInfo: [NSLocalizedDescriptionKey: "Connection failed (status: \(manager.connection.status.rawValue))"])
    default: continue
    }
}
throw NSError(domain: "BBTB.TunnelController", code: -3,
              userInfo: [NSLocalizedDescriptionKey: "Connection timed out after 30s"])
```
**Что копировать:**
- `Task.sleep(nanoseconds:)` — единый паттерн для всех async-задержек в проекте (никаких `DispatchQueue.asyncAfter` внутри Swift Concurrency-частей).
- `for _ in 0..<N { switch }` для bounded loop с явным финальным `throw` на таймаут.
- `NSError(domain: "BBTB.<Component>", code: -N, userInfo: [NSLocalizedDescriptionKey: ...])` — это **существующий проектный стандарт** для controller-уровневых ошибок (см. также `ExtensionPlatformInterface.openTun` — те же домены).

**Reconnect-sequence pattern (MainScreenViewModel.swift:344-359):**
```swift
private func reconnectAfterSelectionChange(newID: UUID?) async {
    state = .connecting
    do {
        try await tunnel.disconnect()
        try await importer.provisionTunnelProfile(for: newID)
        let since = try await tunnel.connect()
        state = .connected(since: since)
        needsReconnectForKillSwitch = false
    } catch let err as MainScreenError {
        state = .error(message: err.errorDescription ?? "\(err)")
    } catch {
        state = .error(message: error.localizedDescription)
    }
}
```
**Что копировать:**
- Линейный async-flow (`disconnect → provision → connect`).
- Два `catch`-блока: типизированный (`MainScreenError`) + общий fallback.
- Перед началом сразу выставить промежуточное `state = .connecting` (для UI).
- В retry-machine это превращается в `state = .reconnecting(attempt: N, of: 3)`.

**Throttle pattern (ConfigImporter.swift:782-823):**
```swift
public func runIsSupportedUpgrade() async {
    let throttleKey = "bbtb.lastIsSupportedUpgrade"
    let last = UserDefaults.standard.double(forKey: throttleKey)
    let now = Date().timeIntervalSince1970
    guard now - last >= 300 else { return }

    // ... work ...

    UserDefaults.standard.set(now, forKey: throttleKey)
}
```
**Что копировать (опционально, если планер решит throttle'нуть NWPathMonitor callback):** `UserDefaults.standard.double(forKey:)` + `Date().timeIntervalSince1970` — этого достаточно, никакого `Combine.throttle`.

**Recommendation для планера:**
- Создать `MainScreenFeature/ReconnectStateMachine.swift` (или `VPNCore/ReconnectStateMachine.swift`, если планер захочет переиспользования) — отдельный `actor` или `@MainActor final class`, принимающий `TunnelControlling` через init и публикующий `@Published var phase: ReconnectPhase` (`.idle / .reconnecting(attempt: Int, of: Int) / .failover(toServerID: UUID) / .failed`).
- Exponential backoff (D-07: 2с → 4с → 8с) — `try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)`.
- Сброс счётчика — таймер на 30s `.connected` (D-08: «успешной сессии дольше 30 секунд»). Использовать `Task.sleep` + `Task.isCancelled` для отмены при ручном disconnect.

---

### NWPathMonitor wrapper (new — место выбирает планер)

**Analog:** `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/ExtensionPlatformInterface.swift` lines 247-315.

**Why this is the right analog:**
- Это **единственный** NWPathMonitor в кодбазе (grep подтвердил — других нет). Уже встроен в extension-side, его трогать **нельзя** (он критичен для R10 + sing-box outbound binding).
- В Phase 6 нужен **второй** NWPathMonitor — на стороне main app внутри `TunnelController`/`MainScreenFeature` (extension-side монитор не виден main app — это отдельный процесс).
- Паттерн callback'а, фильтрация physical interfaces, semaphore-bootstrap — всё это надо позаимствовать.

**Setup pattern (ExtensionPlatformInterface.swift:251-275):**
```swift
public func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    TunnelLogger.lifecycle.info("startDefaultInterfaceMonitor called by libbox")
    guard let listener else { return }
    let monitor = NWPathMonitor()
    nwMonitor = monitor

    let boxedListener = UncheckedSendableBox(listener)

    let semaphore = DispatchSemaphore(value: 0)
    monitor.pathUpdateHandler = { [weak self] path in
        self?.notifyInterfaceUpdate(boxedListener.value, path: path)
        semaphore.signal()
        // Последующие обновления — без сигнала.
        monitor.pathUpdateHandler = { [weak self] path in
            self?.notifyInterfaceUpdate(boxedListener.value, path: path)
        }
    }
    monitor.start(queue: DispatchQueue.global())
    semaphore.wait()
}
```

**Physical-interface filter (ExtensionPlatformInterface.swift:284, 301-310):**
```swift
let physical = path.availableInterfaces.first(where: Self.isPhysical)
// ...

private static func isPhysical(_ iface: NWInterface) -> Bool {
    switch iface.type {
    case .wifi, .cellular, .wiredEthernet:
        return true
    default:
        return false
    }
}
```

**Cleanup pattern (ExtensionPlatformInterface.swift:312-315 + reset() at line 62-67):**
```swift
public func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListenerProtocol?) throws {
    nwMonitor?.cancel()
    nwMonitor = nil
}

func reset() {
    networkSettings = nil
    nwMonitor?.cancel()
    nwMonitor = nil
    currentInterfaceIndex = 0
}
```

**Что копировать для main-app NWPathMonitor:**
1. `import Network` + `import NetworkExtension` (если нужен `.status` сравнить с `.unsatisfied`).
2. **Не использовать semaphore-bootstrap из ExtensionPlatformInterface** — этот трюк нужен только для синхронного libbox API. Для main app callback может быть честно асинхронным.
3. **Обязательно фильтровать `path.availableInterfaces` через `isPhysical`** (или принять, что в main app проблема TUN-loopback не стоит — но безопаснее повторить фильтр).
4. **Дедуп переключений:** трекать `lastPhysicalInterfaceType: NWInterface.InterfaceType?` — callback NWPathMonitor стреляет на каждый микро-чих (изменение isExpensive флага, например). Запускать reconnect ТОЛЬКО при смене типа (Wi-Fi ↔ Cellular ↔ Ethernet) или при `path.status == .unsatisfied → .satisfied`.
5. **Threading:** `monitor.start(queue: DispatchQueue.global(qos: .userInitiated))` (или собственная dedicated queue — `DispatchQueue(label: "app.bbtb.network-monitor")`); callback оборачивать через `Task { @MainActor in ... }` чтобы добраться до `MainScreenViewModel`/`ReconnectStateMachine`.
6. **Cleanup в deinit/stopMonitoring:** `monitor.cancel(); monitor = nil` — точная копия паттерна из `reset()`.

**Recommendation для планера:**
- Создать `MainScreenFeature/NetworkPathObserver.swift` (или `VPNCore/NetworkPathObserver.swift` — планер решит) как `final class NetworkPathObserver: @unchecked Sendable` с API: `func start(onChange: @MainActor @Sendable @escaping (PathChange) -> Void)` / `func stop()`. Эту инстанцию держит `MainScreenViewModel` или сам `ReconnectStateMachine`.

---

## Pattern Assignments — Modified Files

### Modified: `ConfigParser/PoolBuilder.swift`

**Текущее состояние** (см. `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift`):
- `public enum PoolBuilder` (namespace, не type) с `public static func buildSingBoxJSON(from supportedConfigs: [AnyParsedConfig]) throws -> String`.
- Внутри: build N outbounds → `dns: dnsBlock(detour: finalTag)` (line 92) → serialize JSON.
- **Хардкод Yandex в `dnsBlock(detour:)` lines 133-168:** `"address": "tcp://77.88.8.8"` для bootstrap, `"address": "https://cloudflare-dns.com/dns-query"` для remote.
- `dnsBlock` — `private static func`, принимает только `detour: String`.

**Integration points (что нужно знать планеру):**
1. **Все вызовы `buildSingBoxJSON` и `buildSingleOutboundJSON`** должны быть обновлены чтобы передавать `DNSConfig` (или дефолт). Текущие callers:
   - `MainScreenFeature/ConfigImporter.swift:241` — `PoolBuilder.buildSingBoxJSON(from: supportedParsed)`
   - `MainScreenFeature/ConfigImporter.swift:507-509` — `buildSingleOutboundJSON(from: parsedList[0])` / `buildSingBoxJSON(from: parsedList)`
   - Тесты: `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/*.swift` (PoolBuilderTests, PoolBuilderSingleOutboundTests, IntegrationTests, DualProtocolSmokeTests).
2. **R1 validation invariants** (см. header doc lines 17-21): `experimental: {}`, `insecure: false`, no clash_api. Любая правка `dnsBlock` НЕ должна добавить запрещённых полей — `SingBoxConfigLoader.validate` отловит, но лучше не вызывать regression.
3. **Backward compat:** добавь overload `buildSingBoxJSON(from configs:)` (старая сигнатура без `dnsConfig`) → внутри вызывает новую с `DNSConfig.default` — это минимизирует diff на 4 тестовых файла и `ConfigImporter`.
4. **sing-box JSON format unchanged:** структура `dns: { servers: [...], rules: [...], fakeip: {...}, final: "dns-remote", strategy: "ipv4_only" }` остаётся. Меняются только значения `address` внутри.

**Migration pattern (suggested):**
```swift
public static func buildSingBoxJSON(from supportedConfigs: [AnyParsedConfig],
                                     dnsConfig: DNSConfig = .default) throws -> String {
    // ...
    "dns": dnsBlock(detour: finalTag, dnsConfig: dnsConfig),
    // ...
}

private static func dnsBlock(detour: String, dnsConfig: DNSConfig) -> [String: Any] {
    // Bootstrap: первый из dnsConfig.bootstrapServers вместо hardcoded "tcp://77.88.8.8"
    // Remote: dnsConfig.tunnelDNS (может быть DoH URL или plain IP) вместо "https://cloudflare-dns.com/dns-query"
    // ...
}
```

**Pitfall:** bootstrap DNS в sing-box принимает формат `tcp://IP`, `udp://IP`, `https://hostname/dns-query`, `tls://hostname`. Планер должен в `DNSConfig` решить — храним голый IP и сами добавляем `tcp://`, или храним полные URL'ы. Из CONTEXT D-01 видно, что bootstrap — это IP-адреса (`94.140.14.14`, `1.1.1.1`), tunnel может быть hostname (`cloudflare-dns.com`) — то есть **два разных формата**, и оба надо корректно сериализовать.

---

### Modified: `App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift` + `App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`

**Текущее состояние:**
- iOS shell — 16 строк, **пустой override** (см. `App/PacketTunnelExtension-iOS/PacketTunnelProvider.swift`). Вся логика в `BaseSingBoxTunnel`.
- macOS shell — 14 строк, тоже пустой override (см. `App/PacketTunnelExtension-macOS/PacketTunnelProvider.swift`).
- Оба `@objc(PacketTunnelProvider) final class PacketTunnelProvider: BaseSingBoxTunnel` — нет реального override методов.

**Integration points:**
1. **CONTEXT говорит** «PacketTunnelProvider: NEIPv6Settings blackhole `::/0`». Это **НЕ должно** редактироваться в этих 14-16-строчных shell'ах. Это должно лежать в `BaseSingBoxTunnel` или, точнее, в **TunnelSettings.swift** (см. ниже).
2. Shell'ы остаются пустыми — никакого override `startTunnel`, никакого override `wake`. Если что-то добавить — нарушаем R10/R6 architecture decision (вся логика тоннеля централизована в `BaseSingBoxTunnel`).
3. `@objc(PacketTunnelProvider)` alias **обязателен** (см. iOS PacketTunnelProvider.swift line 10, macOS line 9) — без него iOS 18+ silently fails при загрузке extension.

**Planner action:** не трогай `App/PacketTunnelExtension-{iOS,macOS}/PacketTunnelProvider.swift`. Всё IPv6-blackhole делается в `TunnelSettings.swift` (см. ниже).

---

### Modified: `PacketTunnelKit/TunnelSettings.swift` (это и есть «PacketTunnelProvider» из CONTEXT)

**Текущее состояние:** 67 строк, `public enum TunnelSettings` с `Inputs` структурой и `makeR6Safe(_:)` / `makeR6Safe(serverAddress:)`. См. `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift`.

**Critical lines** (lines 52-54):
```swift
// IPv6 — Phase 6 (NET-05..07). На v0.1 — nil (заблокирован на уровне OS).
settings.ipv6Settings = nil
```
**Это явный TODO для Phase 6.**

**Integration points:**
1. `Inputs` struct (lines 18-38) уже принимает `dnsServers: [String]` (default `["1.1.1.1", "1.0.0.1"]`). **Этот параметр не используется PoolBuilder'ом — он используется setTunnelNetworkSettings**. Phase 6 надо решить: передавать `DNSConfig.tunnelDNS` как один из dnsServers, или оставить отдельно. **CONTEXT не требует этого** — настройка DNS уже происходит на уровне sing-box JSON через PoolBuilder. Но если планер захочет — точка интеграции `NEDNSSettings(servers: inputs.dnsServers)` на line 55.
2. **Где зовётся `makeR6Safe`:** только из `ExtensionPlatformInterface.openTun` (line 95: `let settings = TunnelSettings.makeR6Safe(serverAddress: serverAddressHint)`). Этот вызов нужно расширить чтобы он передавал `DNSConfig` (например, через `providerConfiguration["dnsConfig"]` → парсится в `BaseSingBoxTunnel.startTunnel` → передаётся в `ExtensionPlatformInterface` через init).
3. **R6 invariant:** НИКОГДА не выставлять `NEIPv4Settings.destinationAddresses` — комментарий на line 49 это явно фиксирует. Для IPv6 — аналогичный invariant: НЕ выставлять `NEIPv6Settings.destinationAddresses` (иначе тот же IFF_POINTOPOINT).

**Migration pattern для IPv6 blackhole (D-06):**
```swift
// Phase 6 / NET-05..07 — IPv6 blackhole: захватываем ::/0 в туннель,
// внутри туннеля sing-box роутит в никуда (нет IPv6 outbound).
let ipv6 = NEIPv6Settings(addresses: ["fd00::1"], networkPrefixLengths: [128])
ipv6.includedRoutes = [NEIPv6Route.default()]
// R6: НИКОГДА не выставлять ipv6.destinationAddresses.
settings.ipv6Settings = ipv6
```
*Точный адрес `fd00::1/128` (ULA) — Claude's Discretion из CONTEXT; в sing-box TUN inbound одновременно надо выставить `inet6_address: "fd00::1/128"` (см. CONTEXT D-06: `"inet6_address": "::1/128"` — но `::1/128` это loopback, обычно используют ULA range `fd00::/8`. Планер должен сверить с sing-box docs).*

**Pitfall:** sing-box TUN inbound generation идёт через `SingBoxConfigLoader.expandConfigForTunnel` (см. `BaseSingBoxTunnel.swift:155-160`). Чтобы добавить `inet6_address` в TUN inbound, нужно править `SingBoxConfigLoader.expandConfigForTunnel` тоже — это **третий** файл, который CONTEXT упустил.

---

### Modified: `MainScreenFeature/TunnelController.swift`

**Текущее состояние:** 55 строк. См. `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/TunnelController.swift`.

**API surface:**
```swift
public protocol TunnelControlling: AnyObject, Sendable {
    func connect() async throws -> Date
    func disconnect() async throws
}
public final class TunnelController: TunnelControlling, @unchecked Sendable {
    public init() {}
    public func connect() async throws -> Date { ... }
    public func disconnect() async throws { ... }
}
```

**Integration points:**
1. **Protocol-based DI:** `TunnelControlling` — этот protocol уже инжектится во все callers (`MainScreenViewModel.tunnel: TunnelControlling`). Если расширять API — расширять protocol.
2. **`@unchecked Sendable`:** класс без локов; вся state-mutation идёт через async-методы. Если добавлять `nwPathMonitor: NWPathMonitor?` и `retryStateMachine: ReconnectStateMachine` — те же правила: либо `@unchecked Sendable` с serial-вызовами, либо превратить в `actor TunnelController`.
3. **Polling timeout 30s** (line 27: `for _ in 0..<30`) — это полное время на `.connecting → .connected`. Retry-machine из Phase 6 на этом уровне НЕ должен ретрить — TunnelController остаётся однотактным. Ретрай — обёртка вокруг, в `MainScreenViewModel` или `ReconnectStateMachine`.
4. **Disconnect race fix** (lines 49-53) — уже отрабатывает `disconnecting → disconnected` поллингом. Retry-machine должен дёргать `disconnect()` ПЕРЕД `connect()` — этот контракт уже выполнен.
5. **NETunnelProviderManager singleton:** `loadAllFromPreferences().first` — в проекте один manager. Failover (D-08) НЕ создаёт второй manager — он зовёт `ConfigImporter.provisionTunnelProfile(for: nextServerID)` чтобы перезаписать `providerConfiguration["configJSON"]` существующего manager'а.

**Recommendation для планера:**
- Не трогать `TunnelController.connect`/`disconnect`. Добавить **новый метод** `startMonitoringAndRetry()` или вынести retry+monitor в отдельный `ReconnectStateMachine` который инжектится в `MainScreenViewModel` рядом с `tunnel`. Второй вариант чище: `TunnelController` остаётся примитивом.

---

### Modified: `SettingsFeature/SettingsViewModel.swift`

**Текущее состояние:** 9 строк. См. `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift`.

```swift
@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false
    public init() {}
}
```

**Integration points:**
1. **`@AppStorage` ключи в проекте всегда префиксуются `"app.bbtb."`** (см. также `MainScreenViewModel.swift:38`: `"app.bbtb.selectedServerID"`).
2. **Default values важны** — `killSwitchEnabled: Bool = false` здесь, но `KillSwitch.apply` читает с дефолтом `true` (см. `ConfigImporter.swift:898`: `as? Bool ?? true`). Это **известная коллизия** (баг? compat-fix? — но факт: дефолты могут не совпадать). Phase 6 не должна это менять для AdBlock/CustomDNS — задавать ОДНУ точку дефолтов.
3. **UserDefaults observer** для D-14 (KillSwitch toggle ↔ ReconnectBanner) — уже реализован в `MainScreenViewModel.handleUserDefaultsChange` (lines 295-303). Для DNS settings нужен **тот же подход** — `UserDefaults.didChangeNotification` → `MainScreenViewModel` обнаруживает, что DNS-настройка поменялась во время `.connected` → показывает `ReconnectBanner` с текстом «DNS изменены, переподключитесь».

**Migration pattern (suggested):**
```swift
@MainActor
public final class SettingsViewModel: ObservableObject {
    @AppStorage("app.bbtb.killSwitchEnabled") public var killSwitchEnabled: Bool = false

    // Phase 6 / NET-02
    @AppStorage("app.bbtb.customDNS") public var customDNS: String = ""

    // Phase 6 / NET-03
    @AppStorage("app.bbtb.adBlockEnabled") public var adBlockEnabled: Bool = false

    public init() {}

    /// Phase 6 — derive DNSConfig from current settings (D-01..D-04 priority).
    public var dnsConfig: DNSConfig {
        let tunnel: String
        if !customDNS.isEmpty {
            tunnel = customDNS                  // D-03 highest priority
        } else if adBlockEnabled {
            tunnel = "94.140.14.14"             // D-04 AdGuard
        } else {
            tunnel = "1.1.1.1"                  // D-02 Cloudflare default
        }
        return DNSConfig(
            bootstrapServers: ["94.140.14.14", "1.1.1.1"],  // D-01
            tunnelDNS: tunnel,
            adBlockEnabled: adBlockEnabled
        )
    }
}
```
**Important:** `import VPNCore` нужно добавить в SettingsViewModel.swift (сейчас его нет; см. `Package.swift:44` — `SettingsFeature` уже зависит от `VPNCore`, так что только import).

---

### Reused: `MainScreenFeature/ReconnectBanner.swift`

**Текущее состояние:** 36 строк. См. `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ReconnectBanner.swift`.

**Public API:**
```swift
public struct ReconnectBanner: View {
    public let onDismiss: () -> Void
    public init(onDismiss: @escaping () -> Void) { ... }
}
```

**Текущее использование:** показывается через `MainScreenViewModel.needsReconnectForKillSwitch` (видно `MainScreenView.swift:14-16: @Published public private(set) var needsReconnectForKillSwitch: Bool`).

**Текст:** `L10n.bannerReconnectNeeded` — уже существующий ключ (см. `L10n.swift:61`).

**Integration points для Phase 6:**
- **Option A (reuse as-is):** для авто-реконнекта (D-07) показывать **тот же** баннер, но с другим текстом. Это требует **расширения API** — добавить параметр `message: String` или `kind: ReconnectKind`. Это пограничный refactor.
- **Option B (extend минимально):** добавить второй конструктор `init(message: String, onDismiss:)` сохранив существующий — тогда callsite-ы Phase 2 не ломаются.
- **Option C (новый view):** создать `ReconnectingProgressBanner` отдельно — это чище, ибо «переподключитесь» (KILL-03, manual) и «переподключение...» (NET-09, automatic) — семантически разные баннеры (первый — call-to-action, второй — статус).

**CONTEXT explicit choice:** «Переиспользуется как есть или расширяется». Recommendation — **Option B**: добавить новый init со строкой, default messsage = `L10n.bannerReconnectNeeded` для backward-compat.

**Pattern для добавления нового баннера:**
```swift
public struct ReconnectBanner: View {
    public let message: String
    public let onDismiss: () -> Void

    public init(message: String = L10n.bannerReconnectNeeded,
                onDismiss: @escaping () -> Void) {
        self.message = message
        self.onDismiss = onDismiss
    }
    // body уже использует L10n.bannerReconnectNeeded — заменить на self.message
}
```

---

## Shared Patterns

### Localization
**Source:** `BBTB/Packages/Localization/Sources/Localization/L10n.swift`
**Apply to:** все user-visible строки в `AdvancedSettingsView`, новые banner messages, error descriptions.

**Pattern:**
```swift
public enum L10n {
    public static let settingsKillSwitchLabel = tr("settings.kill_switch.label")
    public static let bannerReconnectNeeded = tr("banner.reconnect_needed")
    // ...
}
```
**Phase 6 new keys (naming):**
- `settings.advanced.title`
- `settings.dns.section`
- `settings.dns.adblock.label`
- `settings.dns.adblock.footer`
- `settings.dns.custom.label`
- `settings.dns.custom.placeholder`
- `settings.dns.custom.footer`
- `banner.reconnecting` («Переподключение...»)
- `banner.failover` («Переключаюсь на резервный сервер»)
- `notification.connection_failed` («Не удалось подключиться к {server}»)
- `notification.all_servers_down` («Все серверы недоступны»)

Strings ru/en должны быть добавлены в `BBTB/Packages/Localization/Sources/Localization/Resources/{ru,en}.lproj/Localizable.strings` (проверить путь — у Localization есть test target, см. tests дир).

### Error Handling
**Source:** existing patterns в `TunnelController.swift:15` (`NSError(domain: "BBTB.TunnelController", ...)`) и `ConfigImporter.swift:25-47` (`enum ImporterError: Error, LocalizedError`).
**Apply to:** retry state machine, NWPath observer.

**Pattern для service errors (typed):**
```swift
public enum ReconnectError: Error, LocalizedError, Equatable {
    case allAttemptsFailed
    case allServersDown
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .allAttemptsFailed: return L10n.notificationConnectionFailed
        case .allServersDown:    return L10n.notificationAllServersDown
        case .cancelled:         return nil  // user-initiated, не показывать
        }
    }
}
```

### Threading / Concurrency
**Source:** `MainScreenViewModel` (`@MainActor`), `TunnelController` (`@unchecked Sendable` + async), `ExtensionPlatformInterface` (`@unchecked Sendable` + callbacks).
**Apply to:** все новые типы.

**Правила (из существующего кода):**
- View-models: `@MainActor final class ... : ObservableObject`.
- Сервисы и controllers: `public final class X: SomeProtocol, @unchecked Sendable` + async-методы с `try await`.
- Async-задержки: всегда `Task.sleep(nanoseconds:)`, никаких `DispatchQueue.asyncAfter`.
- Hop на MainActor из background callback: `Task { @MainActor in ... }`.

### Test patterns
**Source:** `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/*.swift` (особенно `IsSupportedUpgradeTests.swift` для async/SwiftData, `ConnectionTimerTests.swift` для pure-value).
**Apply to:** все новые типы.

**Pattern:**
```swift
import XCTest
@testable import MainScreenFeature  // или SettingsFeature / VPNCore — куда положен код

@MainActor                          // если тестируется ObservableObject / async
final class FooTests: XCTestCase {
    override func setUp() async throws {
        try await super.setUp()
        UserDefaults.standard.removeObject(forKey: "...")   // сброс throttle/storage
    }

    func test_<scenario>_<expectation>() async throws {
        // Arrange ...
        // Act
        let result = try await sut.someMethod()
        // Assert
        XCTAssertEqual(result, expected)
    }
}
```

**Naming:** `test_<scenario>_<expectation>` (`test_format_zero`, `test_dnsBlock_usesBootstrapFromConfig`). Не `testFormatZero` — в кодбазе используется snake_case с подчёркиваниями (см. `ConnectionTimerTests.swift`).

**Test target placement:**
- DNSConfig tests → `BBTB/Packages/VPNCore/Tests/VPNCoreTests/DNSConfigTests.swift` (target `VPNCoreTests` уже существует, см. `Package.swift:9`).
- PoolBuilder.dnsBlock tests → `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/PoolBuilderDNSTests.swift` (расширение existing PoolBuilderTests).
- ReconnectStateMachine tests → `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/ReconnectStateMachineTests.swift` (target `MainScreenFeatureTests` уже линкует libbox transitive — линкер-настройки переиспользуются, см. `Package.swift:53-63`).
- AdvancedSettingsView tests (если нужны view-tests) — пока в проекте нет precedent'а view-тестов (только ViewModel-тесты), так что можно пропустить.

---

## No Analog Found

| File | Reason |
|------|--------|
| (none) | Все 9 файлов имеют либо прямой analog (`DNSConfig` ← `TransportConfig`, `AdvancedSettingsView` ← `SettingsView`+`KillSwitchToggleSection`, `NWPathMonitor wrapper` ← `ExtensionPlatformInterface`), либо являются модификациями существующих файлов. |

Единственный partial-match — **Retry state machine**: в кодбазе нет готового state-machine класса (только линейный polling в `TunnelController` и линейный reconnect-flow в `MainScreenViewModel`). Это новая абстракция; analog даёт паттерны идиом (Task.sleep, do/catch, NSError domain), но архитектура самой машины — green field.

---

## Pattern checklist (для планера)

Эти правила планер ДОЛЖЕН зафиксировать в PLAN.md действиях:

### Файловое расположение
- [ ] `DNSConfig.swift` → `BBTB/Packages/VPNCore/Sources/VPNCore/DNSConfig.swift` (НЕ `AppFeatures/`).
- [ ] `AdvancedSettingsView.swift` → `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` (рядом с `SettingsView.swift`).
- [ ] `NetworkPathObserver.swift` / `ReconnectStateMachine.swift` → планер решает: либо `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/` (просто), либо `BBTB/Packages/VPNCore/Sources/VPNCore/` (если планируется переиспользование). По умолчанию — MainScreenFeature, ибо тесно связано с `TunnelController`.
- [ ] **НЕ трогать** `App/PacketTunnelExtension-{iOS,macOS}/PacketTunnelProvider.swift`.
- [ ] IPv6 blackhole — в `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/TunnelSettings.swift` (не в shell'ах). Параллельно править `SingBoxConfigLoader.expandConfigForTunnel` для добавления `inet6_address` в TUN inbound.

### Init / API сигнатуры
- [ ] DNSConfig: `public struct DNSConfig: Sendable, Equatable, Codable, Hashable` с `public init(bootstrapServers:tunnelDNS:adBlockEnabled:)` + `public static let default`.
- [ ] AdvancedSettingsView: `public struct AdvancedSettingsView: View` + `@ObservedObject public var viewModel: SettingsViewModel` + `public init(viewModel: SettingsViewModel)`.
- [ ] Toggle/field rows: отдельные reusable structs (`AdBlockToggleSection`, `CustomDNSField`) с `@Binding` входами, как `KillSwitchToggleSection`.
- [ ] PoolBuilder: добавить overload `buildSingBoxJSON(from:dnsConfig:)` с дефолтом `DNSConfig.default` чтобы не ломать существующие callers.
- [ ] SettingsViewModel: добавить `@AppStorage("app.bbtb.customDNS")` и `@AppStorage("app.bbtb.adBlockEnabled")` + computed `dnsConfig: DNSConfig`.

### Conformances и протоколы
- [ ] Value-types в VPNCore: `Sendable, Equatable, Codable, Hashable`.
- [ ] View-models в AppFeatures: `@MainActor final class ... : ObservableObject` + public init.
- [ ] Сервисы с async: `public final class X: SomeProtocol, @unchecked Sendable`.
- [ ] DI через protocol: `TunnelControlling`, `ConfigImporting`, `ServerProbing` — добавь `NetworkPathObserving` если выделяешь NWPath wrapper.

### Naming
- [ ] AppStorage ключи: префикс `"app.bbtb."` (см. `app.bbtb.killSwitchEnabled`, `app.bbtb.selectedServerID`).
- [ ] L10n ключи: dot-separated (`settings.dns.adblock.label`, `banner.reconnecting`).
- [ ] Test names: `test_<scenario>_<expectation>` snake_case (см. `test_format_zero`).
- [ ] NSError domain: `"BBTB.<Component>"` (см. `BBTB.TunnelController`, `BBTB.openTun`).

### Threading
- [ ] Async sleep: только `Task.sleep(nanoseconds:)`, никаких `DispatchQueue.asyncAfter`.
- [ ] Background → MainActor hop: `Task { @MainActor in ... }`.
- [ ] NWPathMonitor callback queue: dedicated или `DispatchQueue.global(qos: .userInitiated)` (см. `ExtensionPlatformInterface.swift:273`).

### Localization
- [ ] Все user-visible строки — через `L10n.tr("...")`. Никаких inline-строк типа `Text("Переподключение")`.
- [ ] Новые ключи добавлять в `BBTB/Packages/Localization/Sources/Localization/L10n.swift` + `.lproj/Localizable.strings`.

### Tests
- [ ] DNSConfig: unit-тесты в `VPNCoreTests` — `init`, `default`, JSON-roundtrip (Codable).
- [ ] PoolBuilder dnsBlock: расширить `PoolBuilderTests` — три кейса (default, custom DNS, AdBlock) → assert на `dns.servers[*].address`.
- [ ] ReconnectStateMachine: тесты с `MockTunnelControlling` (см. `IsSupportedUpgradeTests.NoOpTunnelProvisioner` как образец mock'а) → проверить (a) 3 retry с задержками, (b) reset счётчика через 30s, (c) failover после 3 fails, (d) all-servers-down stop.
- [ ] NetworkPathObserver: тесты без живого `NWPathMonitor` (через инжекцию `PathSource` protocol) — Apple API не позволяет мокать живой монитор.
- [ ] SettingsViewModel `dnsConfig` computed: 4 кейса (default, customDNS only, adBlock only, customDNS+adBlock — customDNS wins).

### R-invariants (security)
- [ ] R6: НЕ выставлять `NEIPv6Settings.destinationAddresses` (как и для IPv4 — это создаст IFF_POINTOPOINT).
- [ ] R10: post-expand R1-валидация (повторный вызов `SingBoxConfigLoader.validate`) после любых правок sing-box JSON — уже встроена в `BaseSingBoxTunnel.startTunnel`, не сломать.
- [ ] R1: `experimental: {}` пустой, нет clash_api/v2ray_api/cache_file — PoolBuilder уже даёт это, новый `dnsBlock` не должен добавить.

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/VPNCore/Sources/`
- `BBTB/Packages/ConfigParser/Sources/`
- `BBTB/Packages/PacketTunnelKit/Sources/`
- `BBTB/Packages/AppFeatures/Sources/{MainScreenFeature,SettingsFeature,ServerListFeature}/`
- `BBTB/App/PacketTunnelExtension-{iOS,macOS}/`

**Files scanned:** 11 source files read in full; 5 directories indexed via `find`.

**Files NOT scanned (not relevant):** `Protocols/*`, `TransportRegistry/*`, `ProtocolRegistry/*`, `CrashReporter/*`, `DesignSystem/*`, `Localization/*` (известные внешние deps, никаких NWPathMonitor / DNS / retry-логики там нет).

**Pattern extraction date:** 2026-05-13.
