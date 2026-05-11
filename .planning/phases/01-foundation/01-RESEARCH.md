# Phase 1: Foundation — Research

**Researched:** 2026-05-11
**Domain:** Apple Network Extension + sing-box libbox.xcframework + SwiftPM monorepo для VLESS+Vision+Reality VPN-клиента (iOS 18 / macOS 15, Xcode 16+, Swift 6)
**Confidence:** HIGH по Apple-API контрактам и sing-box-конфигу; MEDIUM по libbox lifecycle (источник — чтение `SagerNet/sing-box-for-apple`, не официальные API-доки); LOW по поведенческим багам iOS 18 / macOS 15 vs предыдущих версий.

---

## Сводка для планировщика

Три вещи, которые planner обязан зафиксировать в PLAN.md правильно с первого раза:

1. **R6 (`P2P=false`) — это про `NEIPv4Settings.destinationAddresses` и `NEIPv6Settings.destinationAddresses`.** Конкретная архитектурная команда: при настройке `NEPacketTunnelNetworkSettings` создавать `NEIPv4Settings(addresses: ["10.x.y.1"], subnetMasks: ["255.255.255.0"])` — НЕ вызывать `.destinationAddresses = ...`. Использование `destinationAddresses` превращает `utun*` в point-to-point интерфейс (флаг `POINTOPOINT` в `ifconfig` / `getifaddrs()`), что и есть «P2P=true» в терминологии методички РКН (РосКомНадзор). Это **верифицируется через `getifaddrs()` + проверку флага `IFF_POINTOPOINT`** в самом `BaseSingBoxTunnel` (development-assertion) и через внешний CLI/runtime-snapshot из SocksProbe-приложения. `[VERIFIED: developer.apple.com/documentation/networkextension/neipv4settings]`

2. **R1 (нет SOCKS5 на 127.0.0.1) реализуется на двух уровнях.** (a) Декларативно — в sing-box JSON-конфиге **полностью отсутствует** секция `inbounds[]` (нужны только `outbounds[]` + `route` + `dns` + `log`); никаких `experimental.clash_api` и `experimental.cache_file`. (b) Runtime — `SingBoxConfigLoader.validate()` парсит JSON, отказывает при обнаружении любого `inbounds[i].type` ∈ {`socks`, `mixed`, `http`, `tun`}, отказывает при наличии непустого `experimental.clash_api` или `experimental.v2ray_api`. (c) Внешняя проверка — отдельный bundle `SocksProbe` сканирует loopback при активном туннеле. На iOS sandbox даёт нам бесплатную защиту (другое приложение архитектурно не дойдёт до loopback нашего extension-процесса), но это **не освобождает** от пунктов (a) и (b) — особенно на macOS, где sandbox слабее. `[VERIFIED: SagerNet/sing-box experimental docs]`

3. **libbox.xcframework — это gomobile-биндинг, который называется СНАРУЖИ Swift через C-style API.** Канонический паттерн (читается из `SagerNet/sing-box-for-apple/Library/Network/ExtensionProvider.swift`): `LibboxSetup(options, &setupError)` → `LibboxNewCommandServer(platformInterface, platformInterface, &error)` → `LibboxNewService(configContent, platformInterface)` → `boxService.start()` → … → `boxService.close()`. Хост-приложение реализует `LibboxPlatformInterface` (Swift-протокол, экспортируется gomobile из Go): методы `openTun()` (возвращает TUN file descriptor), `writeLog()`, `getInterfaces()`, `useProcfs()` и т.д. Конкретно для нашего Phase 1 — `openTun()` должен вернуть FD из `packetFlow.value(forKeyPath: "socket.fileDescriptor")` (приватный путь, но это **единственный** способ получить FD у NEPacketTunnelFlow). `[CITED: github.com/SagerNet/sing-box-for-apple/blob/main/Library/Network/ExtensionProvider.swift]`

---

## User Constraints (from CONTEXT.md)

### Locked Decisions (нельзя пересматривать)

**Идентификаторы и брендинг:**
- Project codename: `BBTB`, display name «Верни жука» / «Bring Back the Bug»
- Bundle IDs: `app.bbtb.client.{ios,macos}`, `app.bbtb.client.{ios,macos}.tunnel`, зарезервирован `app.bbtb.client.macos.appproxy`
- App Group: `group.app.bbtb.shared`
- Apple Developer Team ID: `UAN8W9Q82U`
- Custom URL scheme: `bbtb://`, Universal Links: `import.bbtb.app` (только зарезервированы, активация в Phase 9)

**Структура PacketTunnelExtension:**
- Общий Swift Package `PacketTunnelKit` + два тонких NSExtension target-shell (iOS + macOS).
- `BaseSingBoxTunnel: NEPacketTunnelProvider` в `PacketTunnelKit/Sources/`.
- `TunnelSettings.swift` строит `NEPacketTunnelNetworkSettings` с **обязательной R6-проверкой** (никаких `destinationAddresses`).
- `SingBoxConfigLoader.swift` делает runtime-валидацию R1.
- Platform-specific quirks через `#if os(iOS)` / `#if os(macOS)` внутри `PacketTunnelKit/PlatformSpecific/`.

**Wave-структура (security-first):**
- Wave 0 — Bootstrap (Xcode проект + пустые SPM пакеты + Team ID `.xcconfig`)
- Wave 1 — R1 (sing-box config + SingBoxConfigLoader.validate + SocksProbe app)
- Wave 2 — R6 + Kill Switch (TunnelSettings + KillSwitch module)
- Wave 3 — BaseSingBoxTunnel (startTunnel/stopTunnel + libbox lifecycle)
- Wave 4 — UI + Import (MainScreen + MenuBarExtra + IMP-01 vless:// parser + SwiftData + Keychain)
- Wave 5 — Crash reporter + Distribution + Validation (MXMetricManager + TestFlight + R1/R6 verification)

**Технологии:**
- Storage: SwiftData для `ServerConfig` метаданных + Keychain (`kSecAttrAccessibleWhenUnlocked`) для секретов из vless://.
- Crash reporter v0.1: только `MXMetricManager` запись в App Group, без UI отправки.
- Localization: `Localizable.xcstrings` с ru+en с первого дня.
- Menu Bar: SwiftUI `MenuBarExtra` (macOS 13+), не legacy `NSStatusItem`.

### Claude's Discretion (свобода в этих рамках)

- Точная версия libbox.xcframework: использовать sing-box 1.13.x stable (последняя на 2026-04 — 1.13.11), НЕ 1.14.0-alpha. Если в 1.14 alpha есть критические Swift 6 / Reality улучшения — пересмотреть в Phase 2.
- IP-диапазон туннеля (`NEIPv4Settings.addresses`): рекомендуется `198.18.0.x/30` (RFC 2544 benchmarking range, минимальный риск коллизии с домашними сетями). Подтверждается Apple Developer Forums thread на тему «не использовать `10.0.0.0/8`» (конфликт с AirPort NAT).
- Структура `PacketTunnelKit/Sources/` внутри package — на усмотрение planner'а, но `BaseSingBoxTunnel`, `TunnelSettings`, `SingBoxConfigLoader` — обязательные публичные типы.
- Минимальный UI: системные SF Symbols + system colors. Кнопка состояния — большой круг 200×200pt с иконкой состояния (idle/connecting/connected/error).
- Packaging libbox.xcframework: либо vendored binary в `Packages/ProtocolEngine/Frameworks/`, либо отдельный pinned-commit submodule. Решение planner'а; рекомендация — vendored с явным `BinaryTarget` в `Package.swift`.

### Deferred Ideas (OUT OF SCOPE — игнорировать)

- macOS toggle «Отключить принудительную маршрутизацию» (R5) — Phase 10.
- AppProxyExtension-macOS — target создаётся как пустая заготовка в Wave 0, но не реализуется (Phase 8).
- Pasteboard auto-detect — Phase 11.
- xray-core fallback (CORE-09) — placeholder в `Packages/ProtocolEngine/XrayFallback/`, пустой.
- TestFlight Beta App Review submission — Phase 12 (DIST-04).
- Crash reporter UI отправки (TELEM-03) — Phase 12.

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **CORE-01** | SwiftPM monorepo | Раздел 6 «SwiftPM + Xcode workspace структура» |
| **CORE-02** | `ProtocolRegistry` + `VPNProtocolHandler` | Раздел 6 + cite на `<modular_structure>` из v2-промта |
| **CORE-04** | PacketTunnelExtension targets iOS+macOS | Раздел 2 «Apple-API контракт» + раздел 6 |
| **CORE-06** | Entitlements | Раздел 6 — таблица entitlements |
| **CORE-07** | App Group для конфига | Раздел 2 (`NETunnelProviderManager.setProviderConfiguration` + App Group container) |
| **CORE-08** | Sing-box через libbox.xcframework | Раздел 3 «libbox.xcframework контракт» |
| **CORE-10** | SwiftData + Keychain | Раздел 10 «Импорт vless://» |
| **SEC-01** (R1) | Нет SOCKS5 на 127.0.0.1 в конфиге sing-box | Разделы 4, 9 |
| **SEC-02** (R1) | gRPC API sing-box отключён | Раздел 4 — `experimental.{}` пустое |
| **SEC-03** (R1) | Тест-приложение для портов 1080, 9000, 5555, 16000-16100 | Раздел 9 «SocksProbe» |
| **SEC-04** (R6) | `P2P=false` на интерфейсе | Раздел 8 «R6 P2P=false — детальный план» |
| **SEC-05** | Keychain `kSecAttrAccessibleWhenUnlocked` | Раздел 10 |
| **SEC-06** | Валидация конфига перед применением | Раздел 4 — `SingBoxConfigLoader.validate()` |
| **KILL-01** | Kill switch системный | Раздел 7 |
| **KILL-02** | ОС блокирует при разрыве | Раздел 7 |
| **PROTO-01** | VLESS+Vision+Reality | Разделы 4 + 5 |
| **IMP-01** | Импорт через буфер | Раздел 10 |
| **UX-02** | Main screen | Раздел 11 |
| **UX-03** | Connection timer `HH:MM:SS` | Раздел 11 |
| **UX-07** | macOS Menu Bar app | Раздел 12 |
| **TELEM-01** | Локальный crash reporter | Раздел 13 |
| **LOC-01** | ru+en `Localizable.xcstrings` | Раздел 14 |
| **DIST-01** | iOS build на iPhone 11+ | Раздел 15 |
| **DIST-02** | macOS build на Apple Silicon | Раздел 15 |

---

## Project Constraints (from CLAUDE.md)

Извлекаем директивы из `/Users/vergevsky/ClaudeProjects/VPN/CLAUDE.md`:

1. **`raw/` is immutable** — никогда не модифицировать `raw/`-файлы. (Не релевантно Phase 1, нет работы с raw.)
2. **Wiki синхронизация** — после каждого важного шага в `.planning/` обновлять wiki. Архитектурные решения (например, итоговый выбор IP-диапазона туннеля, точная сигнатура `SingBoxConfigLoader.validate()`) фиксировать в `Wiki/security-gaps.md` секция «Закрытые / принятые решения» или в новой странице.
3. **Не дублировать содержимое** между `.planning/` и wiki — линковать.
4. **Все архитектурные/технологические решения** в ходе GSD-работы обязательно фиксируются в wiki — пользователь не хочет принимать одно и то же дважды.
5. **Wiki page format** — каждая страница имеет `**Summary**`, `**Sources**`, `**Last updated**`, заголовок, `[[wiki-links]]`, секцию «Related pages».
6. **Lowercase-with-hyphens** для имён wiki-страниц.
7. **Все ответы на русском** — narrative RESEARCH.md/PLAN.md/VERIFICATION.md на русском. Field labels (Summary, Sources, Confidence), API names, code, file paths остаются на английском. Аббревиатуры при первом упоминании дают русский перевод в скобках.
8. **Source of truth** — `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` секции `<included_in_v0_1>` (строки 645-662) и `<release_roadmap>` v0.1 (779-792). Всё остальное (ROADMAP.md, REQUIREMENTS.md) — производное.

Planner должен включить wiki-update step в финальный wave (Wave 5 либо отдельный wave) — минимум обновить `Wiki/security-gaps.md` (фиксация R1/R6 как closed), `Wiki/architecture.md` (зафиксировать итоговую структуру `PacketTunnelKit`), `Wiki/log.md` (запись о завершении Phase 1).

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| VLESS+Reality handshake + TLS-маскировка | NSExtension (PacketTunnelExtension process) | — | Sing-box работает внутри extension через libbox, никакой логики в main app |
| Packet forwarding (TUN ↔ exit-server) | NSExtension | — | `NEPacketTunnelFlow.readPackets`/`writePackets` доступны только внутри extension |
| Kill switch (`includeAllNetworks`+`enforceRoutes`) | Main app (создание `NETunnelProviderManager`) | OS (enforcement) | Main app конфигурирует VPN profile, ОС выполняет блокировку при разрыве |
| Config import (vless:// parsing) | Main app UI layer | SwiftData persistence | Парсер живёт в `Packages/ConfigParser`, UI в main app дёргает |
| Config storage (метаданные) | Main app process (SwiftData) | App Group shared container | SwiftData @Model хранится в App Group container, чтобы extension мог читать |
| Config secrets (uuid/privateKey/shortId) | Main app + extension (Keychain shared) | — | Keychain access group `group.app.bbtb.shared` для shared access |
| App ↔ Extension communication (config delivery) | `NETunnelProviderManager.providerConfiguration` | App Group container (для крупных blob'ов) | iOS limit ~256 KB на `providerConfiguration`; для крупных конфигов писать файл в App Group |
| Crash report collection (TELEM-01) | Main app (MXMetricManager subscriber) | App Group (запись отчётов) | MetricKit доставляет в main app process, extension'у не доступен |
| UI rendering (Main screen, Menu Bar) | Main app (SwiftUI) | — | Extension не имеет UI вообще, по архитектуре Apple |
| R6 verification (P2P=false) | NSExtension (self-introspection через getifaddrs) | SocksProbe app (snapshot) | Внешняя проверка ограничена sandbox; основная — внутри extension |
| R1 verification (SOCKS5 scan) | Standalone SocksProbe app (bundle `app.bbtb.tools.socksprobe`) | — | Должен быть отдельный bundle ID без App Group — иначе тест нерепрезентативен |

---

## Standard Stack

### Core (verified versions 2026-04/05)

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| sing-box | 1.13.11 | proxy engine (Reality, VLESS, Vision) | Единственный движок с Reality + активной поддержкой; latest stable на 2026-04-22 `[VERIFIED: github.com/SagerNet/sing-box/releases]` |
| libbox.xcframework | соответствует sing-box 1.13.11 | gomobile-биндинги в Swift | Канонический способ интеграции на Apple `[VERIFIED: sing-box.sagernet.org/clients/apple]` |
| Swift | 5.10 / 6.0 mode | язык | Phase 1 minimum — Swift 5.10, целимся в strict concurrency Swift 6 `[CITED: prompts/v2 <tech_stack>]` |
| Xcode | 16+ | IDE / SDK | iOS 18 / macOS 15 SDK `[CITED: prompts/v2]` |
| iOS deployment target | 18.0 | min OS | `includeAllNetworks` + современный NetworkExtension API `[VERIFIED: developer.apple.com]` |
| macOS deployment target | 15.0 | min OS | Sequoia, унифицированный SwiftUI `MenuBarExtra` API `[VERIFIED]` |

### Apple Frameworks (built-in)

| Framework | Used For | Notes |
|-----------|----------|-------|
| `NetworkExtension` | `NEPacketTunnelProvider`, `NETunnelProviderManager`, `NEVPNProtocol`, `NEPacketTunnelNetworkSettings`, `NEIPv4Settings`/`NEIPv6Settings`, `NEDNSSettings` | Основа всего туннеля |
| `Network` | `NWPathMonitor` (для default-interface monitoring внутри libbox PlatformInterface) | Используется через libbox через `getInterfaces()` |
| `SwiftUI` | Main screen, MenuBarExtra | Не AppKit для Menu Bar (см. раздел 12) |
| `SwiftData` | `@Model ServerConfig` метаданные | Шаринг в App Group через `ModelConfiguration(groupContainer:)` |
| `Security` | Keychain API (`SecItemAdd`, `SecItemCopyMatching`) | Через тонкую обёртку — НЕ использовать сторонние Keychain wrappers, см. CLAUDE.md «no third-party SDK» |
| `MetricKit` | `MXMetricManager`, `MXCrashDiagnostic` для TELEM-01 | iOS 13+, macOS 12+ — Phase 1 безопасно `[VERIFIED]` |
| `OSLog` | структурированное логирование (`Logger(subsystem: "app.bbtb.tunnel", category: ...)`) | Никаких `print()`, никаких сторонних log libs |
| `os` (Atomics, allocators) | atomic state в `BaseSingBoxTunnel` под Swift 6 | Стандартная альтернатива actor для лёгкой синхронизации |

### Supporting (Phase 1)

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| **(none — третьесторонних библиотек в Phase 1 нет)** | — | — | Все нужные функции — Apple frameworks + libbox.xcframework |

### Out of Phase 1 (отложено)

| Library | Phase | Notes |
|---------|-------|-------|
| `swift-crypto` | Phase 8 | Ed25519 для rules.json подписи — Phase 1 не использует крипто |
| `WireGuardKit` | Phase 7 | WireGuard family |
| `xray-core` xcframework | Phase 4+ | Fallback для специфичных Reality конфигов |
| `xcstrings-tool` (Swift Package plugin) | возможно Phase 1 если SPM build нужен | См. раздел 14 — для Xcode build не нужен |

### Alternatives Considered

| Instead of | Could Use | Tradeoff | Verdict |
|------------|-----------|----------|---------|
| sing-box / libbox.xcframework | xray-core (через GoMobile) | xray-core старше, чаще баги; Reality поддерживает; сообщество мигрирует на sing-box | Stay with sing-box (R2 закрыт) |
| Vendored libbox.xcframework | Build libbox локально через `gomobile bind` каждый раз | Build занимает 5-10 мин, требует Go + Xcode; vendored бинарь — pinned hash + faster CI | **Vendored** (Phase 1); CI pipeline для build — Phase 12 |
| SwiftUI `MenuBarExtra` | AppKit `NSStatusItem` + `NSPopover` (legacy) | MenuBarExtra has API gaps (programmatic close), но достаточно для v0.1 | **MenuBarExtra** + fallback на `MenuBarExtraAccess` (third-party) если нужно — но **в Phase 1 не нужно** |
| `NEPacketTunnelFlow.readPackets(completionHandler:)` (legacy) | `readPacketObjects` (новее, возвращает `NEPacket[]` с metadata) | `readPacketObjects` поддерживает per-packet metadata, нужен с iOS 11+ | **`readPacketObjects`** через libbox (libbox сам решает, какой API дёргать через `openTun()` + FD) |
| SwiftData + App Group | UserDefaults в App Group | UserDefaults — для маленьких primitives; SwiftData — для structured data; CONTEXT.md залочил SwiftData | **SwiftData** через `ModelConfiguration(groupContainer:)` |

**Installation:**
```bash
# Нет npm/pip — Phase 1 целиком на Apple-нативном стеке + vendored libbox.xcframework.
# libbox.xcframework: скачать релиз sing-box 1.13.11 → достать `libbox.xcframework`
#   ИЛИ собрать: gomobile bind -target ios,iossimulator,macos -o libbox.xcframework ./experimental/libbox
#
# Vendored расположение:
#   Packages/ProtocolEngine/Frameworks/libbox.xcframework
# Package.swift:
#   targets: [.binaryTarget(name: "Libbox", path: "Frameworks/libbox.xcframework")]
```

**Version verification (verified 2026-05-11):**
- sing-box `1.13.11` released `2026-04-22` (note: alpha `1.14.0-alpha.13` released `2026-04-17` — НЕ использовать) `[VERIFIED: github.com/SagerNet/sing-box/releases]`
- Latest sing-box-for-apple commit на main — reference architecture, не используем напрямую `[CITED]`
- gomobile (SagerNet fork `github.com/sagernet/gomobile`) — поддерживает Xcode 15+/16 xcframework format `[VERIFIED]`

---

## 1. Apple-API контракт (iOS 18 / macOS 15)

### NEPacketTunnelProvider (базовый класс)

Жизненный цикл и ключевые методы. `[VERIFIED: developer.apple.com/documentation/networkextension/nepackettunnelprovider]`

```swift
open class NEPacketTunnelProvider : NETunnelProvider {
    // Lifecycle
    open func startTunnel(options: [String : NSObject]?,
                          completionHandler: @escaping (Error?) -> Void)
    open func stopTunnel(with reason: NEProviderStopReason,
                         completionHandler: @escaping () -> Void)
    open func sleep(completionHandler: @escaping () -> Void)  // вызывается перед device sleep
    open func wake()  // после resume

    // Messaging from main app (через NETunnelProviderSession.sendProviderMessage)
    open func handleAppMessage(_ messageData: Data,
                               completionHandler: ((Data?) -> Void)?)

    // Inherited from NETunnelProvider
    open var packetFlow: NEPacketTunnelFlow { get }   // <-- TUN read/write
    open var protocolConfiguration: NEVPNProtocol { get }  // конфиг, переданный из main app
    open func setTunnelNetworkSettings(_ tunnelNetworkSettings: NETunnelNetworkSettings?,
                                       completionHandler: ((Error?) -> Void)? = nil)
}
```

**Канонический паттерн `startTunnel`** (после setTunnelNetworkSettings — обязательно вызвать completionHandler с `nil`):

```swift
override func startTunnel(options: [String : NSObject]?,
                         completionHandler: @escaping (Error?) -> Void) {
    let settings = TunnelSettings.makeR6Safe(serverAddress: "198.18.0.1")
    setTunnelNetworkSettings(settings) { [weak self] error in
        if let error { completionHandler(error); return }
        do {
            try self?.startSingBox(configJSON: self?.loadConfig() ?? "")
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }
}
```

### NETunnelProviderManager (main app side)

Используется в main app для **создания и активации** VPN-профиля. `[VERIFIED: developer.apple.com/documentation/networkextension/netunnelprovidermanager]`

```swift
// Шаги создания VPN profile в main app:
let manager = NETunnelProviderManager()
let proto = NETunnelProviderProtocol()
proto.providerBundleIdentifier = "app.bbtb.client.ios.tunnel"  // ← НСExtension bundle ID
proto.serverAddress = "your.server.com"  // отображается в Settings → VPN
proto.providerConfiguration = ["configJSON": singBoxConfigString]
proto.includeAllNetworks = true   // ← KILL-01 / KILL-02
proto.enforceRoutes = true        // ← R4 default
proto.disconnectOnSleep = false
manager.protocolConfiguration = proto
manager.localizedDescription = "BBTB"
manager.isEnabled = true
try await manager.saveToPreferences()
try await manager.loadFromPreferences()  // ← обязательно после save
try manager.connection.startVPNTunnel()
```

**iOS 18 / macOS 15 особенности:**
- `includeAllNetworks` известно течёт трафиком к Apple-серверам (Apple Maps, Push, OCSP) на iOS 16.1+. `[VERIFIED: ivpn.net/blog kill-switch removal]`. Это **системное ограничение**, обходить нет; задокументировать в FAQ как known limitation в Phase 11.
- Bug на iOS 17+: при `includeAllNetworks=true` смена Wi-Fi↔LTE может вызвать temporary loss of connectivity до 30s. `[CITED: developer.apple.com/forums/thread/706963]`. В Phase 1 не лечится; задокументировать в Wiki как landmine.

### NEPacketTunnelNetworkSettings + NEIPv4Settings (R6 — критическое!)

`[VERIFIED: developer.apple.com/documentation/networkextension/neipv4settings]`

```swift
open class NEIPv4Settings : NSObject {
    public init(addresses: [String], subnetMasks: [String])
    @NSCopying open var addresses: [String]
    @NSCopying open var subnetMasks: [String]?           // ← ИСПОЛЬЗОВАТЬ ЭТО
    @NSCopying open var destinationAddresses: [String]?  // ← НЕ ИСПОЛЬЗОВАТЬ (P2P!)
    @NSCopying open var includedRoutes: [NEIPv4Route]?
    @NSCopying open var excludedRoutes: [NEIPv4Route]?
}
```

**R6-safe pattern (обязательно для PacketTunnelKit/TunnelSettings.swift):**

```swift
public enum TunnelSettings {
    /// R6: P2P=false. Использует subnetMasks, НИКОГДА не destinationAddresses.
    /// Это превращает `utun*` в обычный network interface, не point-to-point.
    public static func makeR6Safe(tunnelIP: String = "198.18.0.1") -> NEPacketTunnelNetworkSettings {
        let settings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: tunnelIP)

        let ipv4 = NEIPv4Settings(addresses: [tunnelIP], subnetMasks: ["255.255.255.0"])
        ipv4.includedRoutes = [NEIPv4Route.default()]
        // ОБРАТИТЕ ВНИМАНИЕ: ipv4.destinationAddresses НЕ выставляется (R6, см. wiki/security-gaps.md)
        settings.ipv4Settings = ipv4

        // IPv6 — Phase 6 (NET-05..07). На v0.1 — nil (блокировка IPv6).
        settings.ipv6Settings = nil

        let dns = NEDNSSettings(servers: ["1.1.1.1", "1.0.0.1"])
        dns.matchDomains = [""]   // ← все DNS-запросы через VPN (защита от DNS leak)
        settings.dnsSettings = dns

        settings.mtu = 1400  // sing-box default safe MTU
        return settings
    }
}
```

**Runtime self-check R6** (внутри `BaseSingBoxTunnel.startTunnel`, после `setTunnelNetworkSettings`, в DEBUG-сборке):

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

### NEVPNProtocol / NETunnelProviderProtocol (kill switch)

```swift
open class NEVPNProtocol : NSObject {
    open var serverAddress: String?
    open var includeAllNetworks: Bool    // ← KILL-01 (iOS 14+, macOS 11+)
    open var enforceRoutes: Bool          // ← R4 (iOS 14.2+, macOS 11+)
    open var excludeLocalNetworks: Bool   // iOS 14+ — НЕ выставляем для kill switch
    open var disconnectOnSleep: Bool      // false для всегда-в-туннеле
    // ...
}

open class NETunnelProviderProtocol : NEVPNProtocol {
    open var providerBundleIdentifier: String?   // ← обязательно
    open var providerConfiguration: [String : Any]?  // ≤ 256 KB на iOS
}
```

`[VERIFIED: developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks + .../enforceroutes]`

---

## 2. libbox.xcframework контракт (sing-box gomobile)

### Архитектура

`libbox.xcframework` — это **gomobile binding**, скомпилированный из `github.com/sagernet/sing-box/experimental/libbox`. Экспортирует C-style API, который Swift видит как auto-generated `Libbox` модуль (Objective-C bridging).

**Ключевые типы и функции** `[CITED: github.com/SagerNet/sing-box-for-apple/blob/main/Library/Network/ExtensionProvider.swift + DeepWiki SagerNet/sing-box 6.3 libbox-command-system]`:

```swift
import Libbox

// === Setup (один раз при старте extension process) ===
LibboxSetup(
    /* basePath */ String,        // путь к рабочей директории (App Group container)
    /* workingPath */ String,
    /* tempPath */ String,
    /* error */ NSErrorPointer
) -> Bool

// === Создать command server (для IPC с main app) ===
LibboxNewCommandServer(
    /* serverHandler */ LibboxCommandServerHandler,  // ← Swift-implements
    /* maxLines */ Int32,
    /* error */ NSErrorPointer
) -> LibboxCommandServer?

// === Создать service ===
LibboxNewService(
    /* configContent */ String,                       // ← JSON sing-box config
    /* platformInterface */ LibboxPlatformInterface,  // ← Swift-implements
    /* error */ NSErrorPointer
) -> LibboxBoxService?

// === Жизненный цикл BoxService ===
public class LibboxBoxService {
    public func start() throws         // запустить sing-box
    public func close() throws         // остановить
    public func pause() throws         // временно (device sleep)
    public func wake() throws          // resume
}

// === Command server lifecycle (для подключения main app GUI) ===
public class LibboxCommandServer {
    public func start() throws
    public func close() throws
}
```

### LibboxPlatformInterface (Swift-implementation)

Это **протокол, экспортируемый из Go через gomobile**, и Swift-сторона должна реализовать все методы. На Apple-платформах основные:

```swift
final class ExtensionPlatformInterface: NSObject, LibboxPlatformInterface {
    weak var provider: NEPacketTunnelProvider?

    // === КРИТИЧЕСКИЙ метод — открыть TUN ===
    func openTun(_ options: LibboxTunOptions) throws -> Int32 {
        // 1. Прочитать IPv4/IPv6 addresses, routes, DNS из options
        // 2. Построить NEPacketTunnelNetworkSettings (R6-safe!)
        // 3. provider.setTunnelNetworkSettings(settings) { ... }
        // 4. Вернуть FD: provider.packetFlow.value(forKeyPath: "socket.fileDescriptor") as! Int32
        //    (приватный путь, но это единственный способ — используется во всех клиентах)
    }

    // === Логирование ===
    func writeLog(_ message: String?) { /* OSLog */ }

    // === Default interface monitoring ===
    func startDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws
    func closeDefaultInterfaceMonitor(_ listener: LibboxInterfaceUpdateListener?) throws
    func getInterfaces() throws -> LibboxNetworkInterfaceIterator
    func underNetworkExtension() -> Bool { true }   // ← мы внутри extension
    func includeAllNetworks() -> Bool { true }      // ← KILL-01

    // === WiFi (только iOS, для DNS/routing-rules) ===
    func readWIFIState() -> LibboxWIFIState?

    // === Service notifications (опционально) ===
    func serviceReload() throws
    func clearDNSCache()
}
```

### Lifecycle (полная последовательность для `BaseSingBoxTunnel.startTunnel`)

```swift
class BaseSingBoxTunnel: NEPacketTunnelProvider {
    private var boxService: LibboxBoxService?
    private var commandServer: LibboxCommandServer?
    private var platformInterface: ExtensionPlatformInterface?

    override func startTunnel(options: [String : NSObject]?,
                             completionHandler: @escaping (Error?) -> Void) {
        // 1. Извлечь providerConfiguration
        guard let proto = protocolConfiguration as? NETunnelProviderProtocol,
              let config = proto.providerConfiguration?["configJSON"] as? String
        else { completionHandler(TunnelError.missingConfig); return }

        // 2. R1 валидация
        do { try SingBoxConfigLoader.validate(json: config) }
        catch { completionHandler(error); return }

        // 3. libbox setup
        let basePath = appGroupContainerURL.appendingPathComponent("singbox").path
        var setupError: NSError?
        LibboxSetup(basePath, basePath, basePath, &setupError)
        if let setupError { completionHandler(setupError); return }

        // 4. Создать PlatformInterface
        let pi = ExtensionPlatformInterface(provider: self)
        self.platformInterface = pi

        // 5. Создать BoxService
        var serviceError: NSError?
        guard let service = LibboxNewService(config, pi, &serviceError) else {
            completionHandler(serviceError); return
        }
        self.boxService = service

        // 6. Запустить
        do {
            try service.start()
        } catch {
            completionHandler(error); return
        }

        // 7. Setup network settings (R6-safe!) ВНИМАНИЕ: libbox сам это вызовет
        //    через PlatformInterface.openTun(). Завершение startTunnel —
        //    когда openTun вернул FD, что мы делаем синхронно через DispatchSemaphore
        //    внутри openTun().
        completionHandler(nil)
    }

    override func stopTunnel(with reason: NEProviderStopReason,
                            completionHandler: @escaping () -> Void) {
        try? boxService?.close()
        try? commandServer?.close()
        boxService = nil
        commandServer = nil
        platformInterface = nil
        completionHandler()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        try? boxService?.pause()
        completionHandler()
    }

    override func wake() {
        try? boxService?.wake()
    }
}
```

**Подводный камень:** `openTun()` — синхронный с точки зрения Go (он должен ВЕРНУТЬ FD сразу). Но `setTunnelNetworkSettings` — async. Стандартный паттерн — `DispatchSemaphore` внутри `openTun()`:

```swift
func openTun(_ options: LibboxTunOptions) throws -> Int32 {
    let settings = TunnelSettings.makeR6Safe(/* ... apply options ... */)
    let semaphore = DispatchSemaphore(value: 0)
    var settingsError: Error?
    provider?.setTunnelNetworkSettings(settings) { err in
        settingsError = err
        semaphore.signal()
    }
    semaphore.wait()
    if let settingsError { throw settingsError }
    let fd = provider?.packetFlow.value(forKeyPath: "socket.fileDescriptor") as! Int32
    return fd
}
```

**Swift 6 concurrency caveat:** `DispatchSemaphore.wait()` блокирует тред. В Swift 6 strict concurrency это допустимо в isolated context, НО `BaseSingBoxTunnel` нельзя сделать просто `@MainActor` — libbox callbacks приходят из Go-runtime threads. Решение: `BaseSingBoxTunnel` — обычный `final class`, `platformInterface` — `final class` без actor-изоляции, доступ к mutable state через `os.OSAllocatedUnfairLock<State>` (iOS 16+, macOS 13+). Объявить класс как `@unchecked Sendable`, документировать инварианты в комментариях.

---

## 3. sing-box JSON schema для VLESS+Vision+Reality (Phase 1)

### Минимальный валидный конфиг (R1-compliant)

`[VERIFIED: sing-box.sagernet.org/configuration/outbound/vless + experimental docs]`

```json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "dns": {
    "servers": [
      { "tag": "cf-doh", "address": "https://1.1.1.1/dns-query", "detour": "vless-out" },
      { "tag": "bootstrap", "address": "1.1.1.1", "detour": "direct" }
    ],
    "rules": [
      { "domain_suffix": [".microsoft.com"], "server": "bootstrap" }
    ],
    "strategy": "ipv4_only"
  },
  "outbounds": [
    {
      "type": "vless",
      "tag": "vless-out",
      "server": "${SERVER_HOST}",
      "server_port": 443,
      "uuid": "${VLESS_UUID}",
      "flow": "xtls-rprx-vision",
      "network": "tcp",
      "packet_encoding": "xudp",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_DOMAIN}",
        "utls": {
          "enabled": true,
          "fingerprint": "chrome"
        },
        "reality": {
          "enabled": true,
          "public_key": "${REALITY_PUBLIC_KEY}",
          "short_id": "${REALITY_SHORT_ID}"
        }
      }
    },
    { "type": "direct", "tag": "direct" }
  ],
  "route": {
    "rules": [
      { "protocol": "dns", "outbound": "dns-out" }
    ],
    "final": "vless-out",
    "auto_detect_interface": true
  },
  "experimental": {}
}
```

### Запрещённые секции (R1 — `SingBoxConfigLoader.validate()` отказывает)

| Секция | Почему запрещено | Detection rule |
|--------|-----------------|----------------|
| `inbounds[]` любого размера > 0 | NEPacketTunnelProvider сам делает TUN через openTun(); inbound в sing-box не нужен | reject if `config.inbounds != nil && !config.inbounds.isEmpty` |
| `inbounds[].type == "socks"` | R1 — открытый SOCKS5 на 127.0.0.1 | reject |
| `inbounds[].type == "mixed"` | R1 — открытый SOCKS+HTTP | reject |
| `inbounds[].type == "http"` | R1 — открытый HTTP proxy | reject |
| `inbounds[].type == "tun"` | sing-box pожидает рулить TUN сам, у нас управление через NEPacketTunnelProvider | reject |
| `experimental.clash_api` non-empty | R1 — gRPC API позволяет вытащить outbounds с ключами | reject if `config.experimental?.clash_api != nil` |
| `experimental.v2ray_api` non-empty | то же | reject if non-nil |
| `experimental.cache_file.enabled == true` | пишет конфиги/ключи на диск открыто | reject if `.cache_file?.enabled == true` |

### `SingBoxConfigLoader.validate()` — signature и поведение

```swift
public enum SingBoxConfigError: Error, LocalizedError {
    case malformedJSON
    case forbiddenInboundType(String)
    case forbiddenInboundExists
    case experimentalApiEnabled(String)
    case missingOutbounds
    case noVLESSOutbound
}

public enum SingBoxConfigLoader {
    /// R1 + SEC-06 validation. Бросает SingBoxConfigError при первом нарушении.
    /// Не модифицирует конфиг.
    public static func validate(json: String) throws {
        guard let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw SingBoxConfigError.malformedJSON }

        // R1: запретить inbounds[]
        if let inbounds = root["inbounds"] as? [[String: Any]], !inbounds.isEmpty {
            // в Phase 1 любой inbound — нарушение, т.к. extension рулит TUN
            let firstType = inbounds.first?["type"] as? String ?? "<unknown>"
            throw SingBoxConfigError.forbiddenInboundType(firstType)
        }

        // R1: запретить experimental APIs
        if let exp = root["experimental"] as? [String: Any] {
            if let clash = exp["clash_api"] as? [String: Any], !clash.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("clash_api")
            }
            if let v2ray = exp["v2ray_api"] as? [String: Any], !v2ray.isEmpty {
                throw SingBoxConfigError.experimentalApiEnabled("v2ray_api")
            }
            if let cache = exp["cache_file"] as? [String: Any],
               cache["enabled"] as? Bool == true {
                throw SingBoxConfigError.experimentalApiEnabled("cache_file")
            }
        }

        // SEC-06: должен быть хотя бы один VLESS outbound
        guard let outbounds = root["outbounds"] as? [[String: Any]], !outbounds.isEmpty else {
            throw SingBoxConfigError.missingOutbounds
        }
        let hasVLESS = outbounds.contains { ($0["type"] as? String) == "vless" }
        guard hasVLESS else { throw SingBoxConfigError.noVLESSOutbound }
    }
}
```

`[ASSUMED]` точная schema sing-box 1.13.x не проверялась через Context7 (MCP unavailable). Поля и структура взяты из официальной документации sing-box.sagernet.org `[VERIFIED]`, но возможны минорные дополнения в 1.13. Planner должен прогнать минимальный config через `sing-box check --config config.json` локально на разработческой машине перед commit'ом — это команда из самого sing-box CLI.

---

## 4. vless:// URI parsing

### Формат

`[VERIFIED: github.com/XTLS/Xray-examples/blob/main/VLESS-TCP-XTLS-Vision-REALITY/REALITY.ENG.md]`

```
vless://{UUID}@{HOST}:{PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni={SNI}&pbk={PUBLIC_KEY}&sid={SHORT_ID}&fp={FINGERPRINT}&type=tcp#{REMARKS}
```

**Пример:**
```
vless://550e8400-e29b-41d4-a716-446655440000@example.com:443?encryption=none&flow=xtls-rprx-vision&security=reality&sni=www.microsoft.com&pbk=abc123xyz789base64url&sid=01234567&fp=chrome&type=tcp#My%20Server
```

### Маппинг URI → sing-box JSON

| URI field | sing-box JSON path |
|-----------|--------------------|
| `{UUID}` (userinfo) | `outbounds[0].uuid` |
| `{HOST}` | `outbounds[0].server` |
| `{PORT}` | `outbounds[0].server_port` |
| `encryption=none` | (validation only — must be "none" for Reality) |
| `flow=xtls-rprx-vision` | `outbounds[0].flow` |
| `security=reality` | enables `outbounds[0].tls.reality.enabled = true` |
| `sni={SNI}` | `outbounds[0].tls.server_name` |
| `pbk={PUBLIC_KEY}` | `outbounds[0].tls.reality.public_key` |
| `sid={SHORT_ID}` | `outbounds[0].tls.reality.short_id` |
| `fp={FINGERPRINT}` | `outbounds[0].tls.utls.fingerprint` (chrome/firefox/safari/random/ios) |
| `type=tcp` | `outbounds[0].network = "tcp"` |
| `#{REMARKS}` (fragment) | `ServerConfig.name` (UI label) |

### Регулярка валидации vless://

```swift
// Грубый prefilter (полный парсинг через URLComponents)
let prefix = "^vless://[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}@[^:]+:\\d+\\?.+"
```

### `VLESSURIParser` — рекомендуемая структура

```swift
public struct ParsedVLESS {
    public let uuid: UUID
    public let host: String
    public let port: Int
    public let flow: String           // "xtls-rprx-vision"
    public let security: String       // "reality"
    public let sni: String
    public let publicKey: String      // base64url
    public let shortId: String        // hex
    public let fingerprint: String    // "chrome", "firefox", "safari", "random"
    public let networkType: String    // "tcp"
    public let remarks: String?       // имя для UI
}

public enum VLESSURIParser {
    public static func parse(_ uri: String) throws -> ParsedVLESS {
        guard let comps = URLComponents(string: uri),
              comps.scheme == "vless",
              let host = comps.host,
              let port = comps.port,
              let user = comps.user,
              let uuid = UUID(uuidString: user)
        else { throw IMP01Error.malformedURI }

        let q = Dictionary(uniqueKeysWithValues:
            (comps.queryItems ?? []).compactMap { item in
                item.value.map { (item.name, $0) }
            })
        guard q["security"] == "reality" else { throw IMP01Error.notRealityProtocol }
        guard q["encryption"] == "none" else { throw IMP01Error.unsupportedEncryption }

        return ParsedVLESS(
            uuid: uuid, host: host, port: port,
            flow: q["flow"] ?? "xtls-rprx-vision",
            security: "reality",
            sni: q["sni"] ?? "",
            publicKey: q["pbk"] ?? "",
            shortId: q["sid"] ?? "",
            fingerprint: q["fp"] ?? "chrome",
            networkType: q["type"] ?? "tcp",
            remarks: comps.fragment?.removingPercentEncoding
        )
    }
}
```

Дальше `ConfigBuilder.buildSingBoxJSON(from: ParsedVLESS) -> String` собирает JSON по шаблону раздела 3.

---

## 5. SwiftPM + Xcode workspace структура (greenfield)

### Рекомендованный layout

```
BBTB/                                  ← репо root (рядом с Wiki/, .planning/, prompts/)
├── BBTB.xcworkspace/                  ← Xcode workspace (top-level)
├── BBTB.xcodeproj/                    ← один Xcode project с всеми app+extension targets
├── App/
│   ├── iOSApp/
│   │   ├── BBTB_iOSApp.swift          ← @main App struct
│   │   ├── Info.plist
│   │   ├── BBTB-iOS.entitlements
│   │   └── Assets.xcassets
│   ├── macOSApp/
│   │   ├── BBTB_macOSApp.swift
│   │   ├── Info.plist
│   │   ├── BBTB-macOS.entitlements
│   │   └── Assets.xcassets
│   ├── PacketTunnelExtension-iOS/
│   │   ├── PacketTunnelProvider.swift ← class PacketTunnelProvider: BaseSingBoxTunnel
│   │   ├── Info.plist                 ← NSExtension dict
│   │   └── PacketTunnelExtension-iOS.entitlements
│   ├── PacketTunnelExtension-macOS/
│   │   ├── PacketTunnelProvider.swift
│   │   ├── Info.plist
│   │   └── PacketTunnelExtension-macOS.entitlements
│   └── AppProxyExtension-macOS/       ← пустая заготовка для CORE-05 (Phase 8)
│       ├── AppProxyProvider.swift     ← // TODO: Phase 8
│       └── Info.plist
├── Packages/                          ← все local Swift Packages
│   ├── VPNCore/
│   │   ├── Package.swift
│   │   └── Sources/VPNCore/
│   ├── ProtocolRegistry/
│   ├── ProtocolEngine/
│   │   ├── Package.swift              ← exposes Libbox через binaryTarget
│   │   ├── Frameworks/libbox.xcframework  ← VENDORED binary
│   │   └── Sources/
│   │       ├── SingBoxBridge/
│   │       └── XrayFallback/          ← пустой placeholder
│   ├── Protocols/
│   │   └── VLESSReality/              ← VPNProtocolHandler impl, ConfigBuilder
│   ├── ConfigParser/                  ← VLESSURIParser
│   ├── KillSwitch/                    ← обёртки для NEVPNProtocol kill switch flags
│   ├── PacketTunnelKit/               ← *** НОВЫЙ Phase-1 пакет ***
│   │   ├── Package.swift
│   │   └── Sources/PacketTunnelKit/
│   │       ├── BaseSingBoxTunnel.swift
│   │       ├── TunnelSettings.swift   ← R6-safe builder
│   │       ├── SingBoxConfigLoader.swift  ← R1 validation
│   │       ├── ExtensionPlatformInterface.swift  ← Libbox platform impl
│   │       └── PlatformSpecific/
│   │           ├── iOS.swift           ← #if os(iOS)
│   │           └── macOS.swift         ← #if os(macOS) + R5 hook (заглушка)
│   ├── DesignSystem/                  ← placeholder tokens (BBTB color, font)
│   ├── Localization/                  ← Localizable.xcstrings + Bundle helper
│   ├── AppFeatures/
│   │   └── MainScreenFeature/         ← Phase 1 UI
│   ├── CrashReporter/                 ← MXMetricManager subscriber
│   └── (другие — пустые placeholder'ы)
├── Tools/
│   └── SocksProbe/                    ← отдельный Xcode-проект
│       ├── SocksProbe.xcodeproj
│       └── (iOS + macOS targets, bundle ID app.bbtb.tools.socksprobe)
└── Tests/
    └── Fixtures/
        └── test-config.vless.local.txt.gitignored  ← не коммитится
```

### Package.swift — пример для PacketTunnelKit

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PacketTunnelKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "PacketTunnelKit", targets: ["PacketTunnelKit"])
    ],
    dependencies: [
        .package(path: "../VPNCore"),
        .package(path: "../ProtocolEngine"),
    ],
    targets: [
        .target(
            name: "PacketTunnelKit",
            dependencies: [
                "VPNCore",
                .product(name: "Libbox", package: "ProtocolEngine"),
            ]
        ),
        .testTarget(name: "PacketTunnelKitTests", dependencies: ["PacketTunnelKit"]),
    ]
)
```

### Package.swift — пример для ProtocolEngine (с vendored libbox)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProtocolEngine",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "Libbox", targets: ["Libbox"]),
        .library(name: "SingBoxBridge", targets: ["SingBoxBridge"]),
    ],
    targets: [
        .binaryTarget(
            name: "Libbox",
            path: "Frameworks/libbox.xcframework"
        ),
        .target(
            name: "SingBoxBridge",
            dependencies: ["Libbox"]
        ),
    ]
)
```

### Entitlements (CORE-06)

**iOS app (`BBTB-iOS.entitlements`):**
```xml
<key>com.apple.developer.networking.networkextension</key>
<array><string>packet-tunnel-provider</string></array>
<key>com.apple.developer.networking.vpn.api</key>
<array><string>allow-vpn</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.app.bbtb.shared</string></array>
<key>keychain-access-groups</key>
<array><string>$(TeamIdentifierPrefix)app.bbtb.shared</string></array>
```

**iOS PacketTunnelExtension (`PacketTunnelExtension-iOS.entitlements`):**
```xml
<key>com.apple.developer.networking.networkextension</key>
<array><string>packet-tunnel-provider</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.app.bbtb.shared</string></array>
<key>keychain-access-groups</key>
<array><string>$(TeamIdentifierPrefix)app.bbtb.shared</string></array>
```

**macOS app (`BBTB-macOS.entitlements`):**
```xml
<key>com.apple.developer.networking.networkextension</key>
<array>
  <string>packet-tunnel-provider</string>
  <string>app-proxy-provider</string>  <!-- заготовка для Phase 8, не активирована -->
</array>
<key>com.apple.developer.networking.vpn.api</key>
<array><string>allow-vpn</string></array>
<key>com.apple.security.application-groups</key>
<array><string>group.app.bbtb.shared</string></array>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.network.client</key><true/>
<key>com.apple.security.network.server</key><true/>
<key>keychain-access-groups</key>
<array><string>$(TeamIdentifierPrefix)app.bbtb.shared</string></array>
```

### NSExtension Info.plist (для PacketTunnelExtension-iOS)

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.networkextension.packet-tunnel</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).PacketTunnelProvider</string>
</dict>
```

### .xcconfig для Team ID

```
// BBTB/Config/Common.xcconfig
DEVELOPMENT_TEAM = UAN8W9Q82U
APP_BUNDLE_ID_PREFIX = app.bbtb.client
```

---

## 6. Kill switch (KILL-01, KILL-02)

### Точная последовательность

`[VERIFIED: developer.apple.com/documentation/networkextension/nevpnprotocol/{includeallnetworks,enforceroutes}]`

```swift
// В main app — KillSwitch.configure(manager:):
public enum KillSwitch {
    public static func apply(to proto: NETunnelProviderProtocol) {
        proto.includeAllNetworks = true   // ← KILL-01
        proto.enforceRoutes = true        // ← R4 default
        proto.excludeLocalNetworks = false // НЕ выставляем — нам нужен maximum lockdown
        proto.disconnectOnSleep = false
    }
}
```

### Что блокирует ОС при разрыве туннеля

Из официальной документации Apple `[CITED: developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks]`:

> «If this value is true and the tunnel is unavailable, the system drops all network traffic.»

Конкретное поведение iOS 18 / macOS 15 (verified empirically by community):

| Сценарий | Что происходит при `includeAllNetworks=true` + `enforceRoutes=true` |
|----------|---------------------------------------------------------------------|
| Tunnel process крашится | ОС немедленно блокирует весь IP-трафик до restart tunnel или ручного `isOnDemandEnabled=false` |
| Сервер недоступен (TCP timeout) | sing-box внутри extension продолжает retry-loop; пользовательские connection attempts блокируются |
| Wi-Fi отключается | На iOS 17+ — известный bug: до 30s connectivity loss; на iOS 18 — улучшилось, но не исправлено |
| Apple internal traffic (Apple Maps, Push, OCSP) | **УТЕЧКА** — Apple servers всегда доступны мимо VPN (документированное системное ограничение iOS 16.1+) |

**Решение R6/R4 trade-off для BBTB:** `enforceRoutes=true` остаётся; Apple-leak документируется в `Wiki/security-gaps.md` как «known platform limitation» — это **не наша ответственность**.

### KILL-02 verification (manual в Phase 1)

DoD проверка в Wave 5:

1. Подключить VPN, открыть `https://api.ipify.org` → IP сменился.
2. На сервере — отключить sing-box процесс (через SSH).
3. На устройстве — попробовать открыть `https://example.com`.
4. Ожидаемый результат — connection error / timeout.
5. Зафиксировать скриншот в `.planning/phases/01-foundation/security-evidence/kill-switch-verify.png`.

---

## 7. R6 — P2P=false детальный план верификации

### Что такое «P2P» в контексте методички РКН

Методичка РосКомНадзора (см. `Wiki/apple-detection-surface.md` раздел «iOS косвенные признаки») упоминает «параметр P2P на интерфейсе» как косвенный признак VPN. В Apple-терминологии это означает **flag `IFF_POINTOPOINT` (0x10) на сетевом интерфейсе `utun*`**, видимый через `getifaddrs()` / `ifconfig`.

### Откуда берётся флаг

Флаг выставляется ОС автоматически, когда `NEIPv4Settings.destinationAddresses` (или `NEIPv6Settings.destinationAddresses`) — non-nil. Если использовать только `subnetMasks` — интерфейс остаётся «normal network interface» без P2P-флага. `[VERIFIED: developer.apple.com/documentation/networkextension/neipv4settings + Apple Developer Forums thread 736602]`

### Защитный паттерн (см. раздел 2)

```swift
let ipv4 = NEIPv4Settings(addresses: ["198.18.0.1"], subnetMasks: ["255.255.255.0"])
ipv4.includedRoutes = [NEIPv4Route.default()]
// ipv4.destinationAddresses не выставляется!
```

### Runtime verification (два уровня)

**Level 1 — assertion в DEBUG-сборке внутри `BaseSingBoxTunnel`** (см. раздел 2, метод `assertR6_NoP2P`). Падает с assertion failure при `IFF_POINTOPOINT` на `utun*`.

**Level 2 — внешняя проверка через SocksProbe app** (см. раздел 9). SocksProbe вызывает `getifaddrs()`, перебирает интерфейсы, для каждого `utun*` показывает: имя, addresses, flags (с явным указанием POINTOPOINT присутствует или нет).

### Лог-output для DoD evidence

```
[R6 check] utun3: addresses=[198.18.0.1], flags=0x8843 (UP|BROADCAST|RUNNING|MULTICAST), POINTOPOINT=NO
✓ R6 verified
```

Сохранить в `.planning/phases/01-foundation/security-evidence/r6-no-p2p.log` + скриншот вывода SocksProbe.

---

## 8. SocksProbe — тестовое приложение для R1 (SEC-03)

### Назначение и архитектура

**Цель:** независимое от нашего основного приложения проверить, что при активном `BBTB`-туннеле ни один из стандартных SOCKS-портов из методички РКН не отвечает на 127.0.0.1.

**Bundle ID:** `app.bbtb.tools.socksprobe`
**Team ID:** `UAN8W9Q82U` (тот же — иначе нужны два provisioning)
**App Group:** **НЕТ** (это критично — иначе проверка нерепрезентативна; SocksProbe должен быть как «любое стороннее приложение»)
**Platforms:** iOS 18 + macOS 15 (один Xcode-проект, два таргета)

### Apple Sandbox для loopback — что нужно знать

`[VERIFIED]` На **iOS** sandbox изолирует loopback **между процессами в разных app sandboxes**: один app не может прочитать listening socket другого app на 127.0.0.1. Однако SocksProbe всё равно ДОЛЖЕН попытаться connect — это и есть тест: успешный `connect()` = открытая дыра.

На **macOS** с `app-sandbox=true` + `network.client=true` — connect к 127.0.0.1 разрешён, и это **точно та же поверхность атаки, что Android scenario** из `wiki/xray-localhost-vulnerability.md`. Проверка на macOS особенно ценна.

### UI Spec

```
┌──────────────────────────────────────┐
│  BBTB SocksProbe                     │
│  Scan 127.0.0.1 for SOCKS/proxy      │
├──────────────────────────────────────┤
│  Status:  [ Idle | Scanning | Done ] │
│                                      │
│  [   Start Scan   ]   [ Stop ]       │
│                                      │
│  Ports tested:                       │
│  ┌────────────────────────────────┐  │
│  │ :1080    closed                 │  │
│  │ :9000    closed                 │  │
│  │ :5555    closed                 │  │
│  │ :16000   closed                 │  │
│  │   ...                           │  │
│  │ :16100   closed                 │  │
│  └────────────────────────────────┘  │
│                                      │
│  utun interfaces (R6 check):         │
│  ┌────────────────────────────────┐  │
│  │ utun3  198.18.0.1               │  │
│  │   POINTOPOINT: NO ✓             │  │
│  └────────────────────────────────┘  │
│                                      │
│  [   Export Results   ]              │
└──────────────────────────────────────┘
```

### Ports list (из методички РКН)

```swift
enum RKNPorts {
    static let socks: [UInt16] = [1080, 9000, 5555]
    static let socksRange: ClosedRange<UInt16> = 16000...16100
    static let httpProxy: [UInt16] = [3128, 3127, 8000, 8080, 8081, 8888]
    // ВНИМАНИЕ: 80 и 443 НЕ сканируем — конфликт с нормальными HTTP/HTTPS на устройстве
    static let tor: [UInt16] = [9050, 9051, 9150]

    /// Полный список для Phase 1 R1 проверки
    static var phase1: [UInt16] {
        socks + Array(socksRange) + httpProxy + tor
    }
}
```

### TCP-connect implementation (через `Network` framework, async-friendly)

```swift
import Network

func probe(port: UInt16, host: String = "127.0.0.1", timeout: TimeInterval = 1.0) async -> PortStatus {
    let conn = NWConnection(host: .init(host), port: NWEndpoint.Port(integerLiteral: port), using: .tcp)
    return await withCheckedContinuation { cont in
        let timer = DispatchSource.makeTimerSource(queue: .global())
        var resumed = false
        let resume: (PortStatus) -> Void = { status in
            guard !resumed else { return }
            resumed = true
            timer.cancel()
            conn.cancel()
            cont.resume(returning: status)
        }
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler { resume(.timeout) }
        timer.activate()

        conn.stateUpdateHandler = { state in
            switch state {
            case .ready:           resume(.open)
            case .failed, .cancelled: resume(.closed)
            case .waiting:         resume(.closed)
            default: break
            }
        }
        conn.start(queue: .global())
    }
}

enum PortStatus { case open, closed, timeout }
```

### DoD criteria for SocksProbe

1. SocksProbe собирается, устанавливается на iOS + macOS device.
2. При **выключенном BBTB**-туннеле: scan завершается с результатом «closed» для всех portов из `RKNPorts.phase1`.
3. При **включённом BBTB**-туннеле и активном sing-box: scan завершается с тем же результатом «closed» для всех портов.
4. R6 check показывает `POINTOPOINT: NO` для всех `utun*`.
5. Скриншоты сохранены в `.planning/phases/01-foundation/security-evidence/`.

---

## 9. Импорт vless:// из буфера (IMP-01)

### Flow

```
┌─────────────────────────┐
│  Main Screen (empty)    │
│  "Импортируйте конфиг"  │
│  [📋 Из буфера обмена] │
└─────────────┬───────────┘
              │ tap
              ▼
   UIPasteboard.general.string (iOS) │ NSPasteboard.general.string(forType: .string) (macOS)
              │
              ▼
   VLESSURIParser.parse(...)
              │  ✗ throws → toast "Не похоже на vless:// конфиг"
              │  ✓ success
              ▼
   ConfigBuilder.buildSingBoxJSON(from: parsed) -> String
              │
              ▼
   SingBoxConfigLoader.validate(json:)  ← двойная защита R1
              │
              ▼
   Persistence:
   ┌─────────────────────────────────────┐
   │ SwiftData @Model ServerConfig:      │
   │   id: UUID                          │
   │   name: String (= parsed.remarks)   │
   │   host: String                      │
   │   port: Int                         │
   │   protocolID: "vless-reality"       │
   │   keychainTag: "bbtb-config-\(id)"  │
   │   isActive: Bool = true (singleton) │
   │   createdAt: Date                   │
   └─────────────────────────────────────┘
              │
              ▼
   ┌─────────────────────────────────────┐
   │ Keychain (kSecAttrAccessibleWhenUnlocked) │
   │   account: keychainTag              │
   │   service: "app.bbtb.shared"        │
   │   data: JSON {                      │
   │     "uuid": "...",                  │
   │     "publicKey": "...",             │
   │     "shortId": "...",               │
   │     "sni": "...",                   │
   │     "fingerprint": "chrome",        │
   │     "configJSON": "<full sing-box>"│
   │   }                                  │
   │   accessGroup: "<team>.app.bbtb.shared" │
   └─────────────────────────────────────┘
              │
              ▼
   NETunnelProviderManager creation + saveToPreferences
              │
              ▼
   UI updated → "Готово к подключению"
```

### SwiftData ServerConfig (CORE-10)

```swift
import SwiftData

@Model
public final class ServerConfig {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var protocolID: String         // "vless-reality"
    public var keychainTag: String        // ключ в Keychain
    public var isActive: Bool             // singleton в Phase 1 — только один active
    public var createdAt: Date
    public var lastLatencyMs: Int?        // для Phase 3 — Phase 1 не заполняется

    public init(id: UUID = UUID(), name: String, host: String, port: Int,
                protocolID: String, keychainTag: String) {
        self.id = id; self.name = name; self.host = host; self.port = port
        self.protocolID = protocolID; self.keychainTag = keychainTag
        self.isActive = false; self.createdAt = .now
    }
}

// ModelContainer setup — shared App Group для extension доступа
let url = FileManager.default
    .containerURL(forSecurityApplicationGroupIdentifier: "group.app.bbtb.shared")!
    .appendingPathComponent("ServerConfigStore.sqlite")
let config = ModelConfiguration(url: url)
let container = try ModelContainer(for: ServerConfig.self, configurations: config)
```

**ВНИМАНИЕ:** `ModelConfiguration(url:)` принимает URL внутри App Group container — это позволяет extension читать те же данные. Но **запись из extension не рекомендуется** (concurrency conflicts с SwiftData). В Phase 1 extension только читает; main app — единственный writer.

### Keychain (SEC-05) — Shared access group

```swift
public enum KeychainStore {
    static let accessGroup = "\(Bundle.main.teamIdentifierPrefix)app.bbtb.shared"  // ← shared with extension

    public static func save(secret data: Data, tag: String) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.bbtb.shared",
            kSecAttrAccount as String: tag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,  // ← SEC-05
            kSecAttrAccessGroup as String: accessGroup,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.saveFailed(status) }
    }

    public static func load(tag: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "app.bbtb.shared",
            kSecAttrAccount as String: tag,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.notFound(status)
        }
        return data
    }
}
```

`teamIdentifierPrefix` извлекается из main bundle (через Info.plist key `AppIdentifierPrefix` или programmatically).

---

## 10. UI Phase 1 (UX-02, UX-03)

### Main Screen — состояния

| State | Top bar | Center | Bottom bar |
|-------|---------|--------|------------|
| **Empty** (нет конфигов) | «BBTB» | `[📋 Импортировать из буфера]` (большая кнопка) | пусто |
| **Idle** (есть конфиг, не подключено) | «BBTB» + status «Готово» | большой круг с иконкой `power` (200×200pt) | имя сервера (read-only, без выбора) |
| **Connecting** | «BBTB» + spinner | круг с pulsing animation, иконка `bolt` | имя сервера |
| **Connected** | «BBTB» + status «Подключено» | круг с иконкой `checkmark`, под ним **connection timer** `HH:MM:SS` | имя сервера |
| **Error** | «BBTB» + красный status | круг с иконкой `exclamationmark.triangle` | имя сервера + кнопка «Подробнее» |

### SwiftUI structure (cross-platform, в `Packages/AppFeatures/MainScreenFeature`)

```swift
import SwiftUI

public struct MainScreenView: View {
    @StateObject private var viewModel: MainScreenViewModel

    public init(viewModel: MainScreenViewModel = .init()) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 24) {
            // Top bar
            HStack {
                Text("BBTB").font(.system(.title2, design: .rounded).bold())
                Spacer()
                StatusBadge(state: viewModel.state)
            }
            .padding()

            Spacer()

            // Center — состояние-зависимый контент
            switch viewModel.state {
            case .empty:
                ImportFromClipboardButton(action: viewModel.importFromPasteboard)
            case .idle, .connecting, .connected, .error:
                ConnectionButton(
                    state: viewModel.state,
                    action: viewModel.toggleConnection
                )
                if case .connected(let since) = viewModel.state {
                    ConnectionTimer(since: since)
                }
            }

            Spacer()

            // Bottom bar (placeholder в Phase 1)
            if let activeName = viewModel.activeServerName {
                Text(activeName).font(.caption).foregroundStyle(.secondary)
                    .padding(.bottom)
            }
        }
    }
}
```

### Connection Timer (UX-03)

```swift
public struct ConnectionTimer: View {
    let since: Date
    @State private var now: Date = .now
    private let timer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    public var body: some View {
        Text(formatted)
            .font(.system(.title, design: .monospaced))
            .onReceive(timer) { now = $0 }
    }

    private var formatted: String {
        let interval = Int(now.timeIntervalSince(since))
        let h = interval / 3600
        let m = (interval % 3600) / 60
        let s = interval % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}
```

### Cross-platform layout

iOS+macOS используют один и тот же `MainScreenView`. Различие:
- **iOS** — встроен в `NavigationStack` внутри `BBTB_iOSApp` (полный экран).
- **macOS** — внутри `Window` (фиксированный размер 380×520) ИЛИ как content для MenuBarExtra popover (см. раздел 11).

---

## 11. macOS Menu Bar app (UX-07)

### Pattern — SwiftUI `MenuBarExtra`

`[VERIFIED: developer.apple.com/documentation/swiftui/menubarextra]` macOS 13+ — нативный SwiftUI API. На macOS 15 — рекомендованный путь.

### Минимальная реализация

```swift
import SwiftUI

@main
struct BBTB_macOSApp: App {
    @StateObject private var viewModel = MainScreenViewModel()

    var body: some Scene {
        // Главное окно
        Window("BBTB", id: "main") {
            MainScreenView(viewModel: viewModel)
                .frame(minWidth: 380, minHeight: 520)
        }
        .windowResizability(.contentSize)

        // Menu Bar extra
        MenuBarExtra("BBTB", systemImage: viewModel.state.menuBarSymbol) {
            MenuBarContent(viewModel: viewModel)
                .frame(width: 280)
        }
        .menuBarExtraStyle(.window)  // popover-стиль, не menu
    }
}

private struct MenuBarContent: View {
    @ObservedObject var viewModel: MainScreenViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("BBTB").font(.headline)
                Spacer()
                StatusBadge(state: viewModel.state)
            }
            Divider()
            switch viewModel.state {
            case .connected(let since):
                ConnectionTimer(since: since)
                Button("Отключить", action: viewModel.toggleConnection)
            case .idle:
                Button("Подключить", action: viewModel.toggleConnection)
            case .connecting:
                ProgressView()
            case .empty:
                Text("Нет конфигурации")
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Text(msg).font(.caption).foregroundStyle(.red)
            }
            Divider()
            Button("Открыть BBTB...") {
                NSWorkspace.shared.open(URL(string: "bbtb://main")!)
                // Phase 1: deep link не работает, но кнопка должна быть.
                // Альтернатива — открыть main window через NSApp.activate(...)
            }
        }
        .padding()
    }
}

// SF Symbol для menu bar — реагирует на state
extension ConnectionState {
    var menuBarSymbol: String {
        switch self {
        case .empty, .idle: return "bolt.shield"
        case .connecting:   return "bolt.shield.fill"
        case .connected:    return "checkmark.shield.fill"
        case .error:        return "exclamationmark.shield.fill"
        }
    }
}
```

### Известное ограничение `MenuBarExtra`

`[CITED: feedback-assistant/reports#383]` — на macOS 13/14/15 нет API для программного `dismiss()` popover'а. Для Phase 1 это не критично (пользователь сам закрывает). Если в будущем понадобится — third-party `MenuBarExtraAccess` package. **В Phase 1 не подключаем.**

---

## 12. MXMetricManager crash reporting (TELEM-01)

### API surface

`[VERIFIED: developer.apple.com/documentation/metrickit + Apple Developer guides]`

```swift
import MetricKit

final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    func install() {
        MXMetricManager.shared.add(self)
    }

    // MARK: MXMetricManagerSubscriber
    func didReceive(_ payloads: [MXMetricPayload]) {
        // Performance метрики — в Phase 1 не используем
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            saveDiagnosticPayload(payload)
        }
    }

    private func saveDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.app.bbtb.shared")!
        let diagnosticsDir = container.appendingPathComponent("crash-reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: diagnosticsDir,
                                                  withIntermediateDirectories: true)

        let timestamp = ISO8601DateFormatter().string(from: payload.timeStampBegin)
        let filename = "crash-\(timestamp).json"
        let url = diagnosticsDir.appendingPathComponent(filename)

        let json = payload.jsonRepresentation()  // MetricKit provides this
        try? json.write(to: url, options: .atomic)
    }
}
```

### Подписка

Вызывать `CrashReporter.shared.install()` в `BBTB_iOSApp.init()` и `BBTB_macOSApp.init()` (НЕ в extension — MetricKit доставляет только в main app process).

### Платформенная поддержка

`[VERIFIED]`
- iOS 13+ — `MXMetricManager` доступен; iOS 14+ — `didReceive([MXDiagnosticPayload])` для crash reports
- macOS 12+ — full support, **macOS 15 включён**
- Phase 1 deployment target iOS 18 / macOS 15 — без проблем

### Phase 1 scope

- Только сохранение `.json` в App Group container.
- Никакого UI отправки (TELEM-03 — Phase 12).
- Никакой автоотправки на сервер (TELEM-04 — Phase 12).

---

## 13. Localizable.xcstrings (LOC-01)

### Где разместить

Для cross-platform shared строк — **отдельный package `Localization`** с одним файлом `Localizable.xcstrings`:

```
Packages/Localization/
├── Package.swift
└── Sources/Localization/
    ├── Resources/
    │   └── Localizable.xcstrings
    └── L10n.swift   ← helper для type-safe доступа
```

```swift
// Package.swift
.target(
    name: "Localization",
    resources: [
        .process("Resources/Localizable.xcstrings")
    ]
)
```

### Bundle reference

```swift
// Sources/Localization/L10n.swift
import Foundation

public enum L10n {
    public static let appDisplayName = NSLocalizedString(
        "app.display_name",
        bundle: .module,                  // ← Bundle.module для SwiftPM resources
        comment: "App display name"
    )
    public static func connected(since: String) -> String {
        let format = NSLocalizedString("status.connected_since",
                                       bundle: .module, comment: "")
        return String(format: format, since)
    }
    // ...
}
```

### Файл `Localizable.xcstrings` (фрагмент)

```json
{
  "sourceLanguage" : "en",
  "strings" : {
    "app.display_name" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Bring Back the Bug" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Верни жука" } }
      }
    },
    "status.idle" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Ready" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Готово" } }
      }
    },
    "status.connecting" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connecting…" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключение…" } }
      }
    },
    "status.connected" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Connected" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Подключено" } }
      }
    },
    "action.import_from_clipboard" : {
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Import from Clipboard" } },
        "ru" : { "stringUnit" : { "state" : "translated", "value" : "Импортировать из буфера" } }
      }
    }
  },
  "version" : "1.0"
}
```

### Важный нюанс — SwiftPM + .xcstrings

`[CITED: danielsaidi.com blog 2025/12/02 + elegantchaos.com 2026/02/12]`

> SwiftPM не поддерживает .xcstrings нативно, но **при сборке через Xcode (или `xcodebuild`)** Resources обрабатываются корректно. При `swift build`/`swift test` локализация ломается.

**Phase 1 решение:** сборка идёт исключительно через Xcode (главный workspace `BBTB.xcworkspace`). `swift build` напрямую не используется. Этого достаточно. Если в Phase 1 будут unit-тесты для Localization, они тоже запускаются через Xcode (`xcodebuild test`), не `swift test`.

**Альтернатива (если planner сочтёт нужным):** добавить `xcstrings-tool` Swift Package Plugin для type-safe генерации. **Не обязательно для Phase 1.**

---

## 14. TestFlight build (DIST-01, DIST-02)

### Что нужно настроить в Xcode для iOS+macOS archive

1. **Bundle Identifiers** — registered в Apple Developer Portal под Team `UAN8W9Q82U`:
   - `app.bbtb.client.ios`
   - `app.bbtb.client.macos`
   - `app.bbtb.client.ios.tunnel`
   - `app.bbtb.client.macos.tunnel`
   - `app.bbtb.tools.socksprobe` (для security audit, не TestFlight)

2. **Capabilities** в Apple Developer Portal для каждого App ID:
   - Network Extensions (с packet-tunnel-provider)
   - Personal VPN
   - App Groups (`group.app.bbtb.shared`)
   - Keychain Sharing (`app.bbtb.shared`)
   - Associated Domains (только зарегистрировать `import.bbtb.app`, активация в Phase 9)

3. **Provisioning Profiles** — generated по каждому App ID для Development + Distribution. В Xcode 16 — automatic signing работает; manual signing — option для CI.

4. **App Group registration** — `group.app.bbtb.shared` в Identifiers → App Groups.

5. **Marketing version / Build number:**
   - `CFBundleShortVersionString` = `0.1.0`
   - `CFBundleVersion` = `1` (далее автоинкремент через `agvtool what-version` + bump в CI)

6. **App Store Connect**:
   - Создать iOS app record `BBTB` с bundle ID `app.bbtb.client.ios`
   - Создать macOS app record `BBTB` с bundle ID `app.bbtb.client.macos`
   - Внутренний tester группа TestFlight Internal — добавить 1-3 тестера

### Что НЕ нужно в Phase 1

- ❌ Beta App Review submission (DIST-04) — Phase 12
- ❌ External Testing group (DIST-03) — Phase 12
- ❌ Public TestFlight invite link (DIST-05) — Phase 12
- ❌ Privacy declaration в App Store Connect (полная) — Phase 12 / TELEM-09
- ❌ Notarization для macOS (вне TestFlight context) — Phase 12 / SEC-07
- ❌ Landing page (DIST-06) — Phase 12

### Archive process (Wave 5)

```bash
# iOS
xcodebuild archive \
  -workspace BBTB.xcworkspace \
  -scheme BBTB-iOS \
  -destination 'generic/platform=iOS' \
  -archivePath build/BBTB-iOS.xcarchive

xcodebuild -exportArchive \
  -archivePath build/BBTB-iOS.xcarchive \
  -exportPath build/iOS-Distribution \
  -exportOptionsPlist Config/ExportOptions-iOS.plist
# upload via Transporter app or `xcrun altool --upload-app`

# macOS — аналогично с -destination 'generic/platform=macOS'
```

### ExportOptions.plist для TestFlight (Internal-only)

```xml
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store</string>          <!-- TestFlight uses app-store method -->
  <key>teamID</key>
  <string>UAN8W9Q82U</string>
  <key>uploadBitcode</key>
  <false/>
  <key>uploadSymbols</key>
  <true/>
</dict>
</plist>
```

---

## 15. Reference implementations

Production-quality источники для planner'а — указать в `read_first` для соответствующих задач:

### 1. **SagerNet/sing-box-for-apple** (★ ОСНОВНОЙ референс)

- **Repo:** https://github.com/SagerNet/sing-box-for-apple
- **Лицензия:** GPL-3.0 (значит мы — AGPL-3.0 для ядра, что у нас и так)
- **Critical files для planner'a:**
  - `Library/Network/ExtensionProvider.swift` — образец `NEPacketTunnelProvider` + libbox lifecycle
  - `Library/Network/ExtensionPlatformInterface.swift` — образец `LibboxPlatformInterface` impl
  - `Library/Network/SettingsView.swift` (если есть) — UI patterns
  - `Frameworks/Libbox/Libbox.xcframework` — vendored framework (можно стащить под GPL для starter Phase 1, но обязательно перебилдить из upstream sing-box перед v0.1)
- **Что использовать:** структуру `BoxService` lifecycle, `LibboxSetup` → `LibboxNewService` → `service.start()` паттерн. Адаптировать к нашей `PacketTunnelKit` структуре.
- **Что НЕ копировать:** их UI (Flutter-like custom design), весь Database/SwiftData код (у них своё, у нас — структура из CONTEXT.md).

### 2. **EbrahimTahernejad/sing-box-lib**

- **Repo:** https://github.com/EbrahimTahernejad/sing-box-lib
- **Лицензия:** проверить (LOW confidence — не verified)
- **Useful for:** Альтернативный взгляд на packaging libbox.xcframework как SwiftPM package. 22 stars, последний релиз май 2025. Меньше features чем sing-box-for-apple, проще для понимания базового pattern'а.
- **Что использовать:** структуру `Package.swift` с `.binaryTarget`. Один из вариантов — fork и pin commit, если хотим SwiftPM-friendly distribution libbox без vendored framework в нашем repo.

### 3. **WireGuardKit-Apple от ZX2C4**

- **Repo:** https://git.zx2c4.com/wireguard-apple/
- **Лицензия:** MIT
- **Useful for:** **Идеальная архитектура** для PacketTunnelProvider — Swift, без Go-биндингов, чистый SPM-проект, две extension targets (iOS+macOS), App Group, kill switch.
- **Что использовать:** структура `Sources/WireGuardKit/PacketTunnelProvider.swift` — паттерн `setTunnelNetworkSettings` → start engine. Структура `WireGuardApp/` — пример main app + extension wiring.
- **Phase 1 read_first для Wave 2-3.**

### 4. **PIA Tunnel (Private Internet Access)**

- **Repo:** https://github.com/pia-foss/tunnel-apple
- **Лицензия:** GPL-3.0
- **Useful for:** Production-grade NEPacketTunnelProvider, OpenVPN-based. Не Reality, но качественный код. `Sources/AppExtension/PIATunnelProvider.swift` — образец.

### 5. **Hiddify-Apple — NOT useful**

- Flutter UI слой неприменим к нашей чисто-Swift архитектуре.
- Их libbox integration — да, в `hiddify-app/libcore` подобный sing-box pattern, но Flutter-bridge всё закрывает.
- **НЕ использовать как референс в Phase 1.**

### 6. **FoXray, Streisand**

- **Closed-source**, недоступны для чтения кода.
- Полезны как demo/UI референсы — установить и поработать, чтобы понять UX (не Phase 1 work, но фоновое знание).

---

## 16. Common Pitfalls / Landmines

### Pitfall 1: `destinationAddresses` случайно выставится через copy-paste из старого примера

**Что:** Многие туториалы (включая Apple sample SimpleTunnel) показывают `ipv4Settings.destinationAddresses = ["10.0.0.2"]`. Скопировать и забыть — = R6 violation.
**Prevention:** В `TunnelSettings.makeR6Safe` физически нет вызова `destinationAddresses =`. Plus runtime-assertion (DEBUG) + external SocksProbe check.
**Warning signs:** В `ifconfig utun3` (на dev-устройстве в Console.app) присутствует флаг `POINTOPOINT`.

### Pitfall 2: libbox.xcframework + Swift 6 strict concurrency

**Что:** Auto-generated `Libbox` модуль из gomobile не имеет Sendable annotations. В Swift 6 mode при `strict concurrency = complete` будут warnings и потенциально errors.
**Prevention:** В `BaseSingBoxTunnel` объявить `nonisolated(unsafe)` для libbox-объектов, или `@unchecked Sendable` обёртки. Документировать что lifecycle-методы вызываются из Go threads.
**Warning signs:** Warning «Capture of 'X' with non-sendable type ... in a `@Sendable` closure».

### Pitfall 3: NEPacketTunnelProvider extension process memory limit (iOS only)

**Что:** На iOS extension processes имеют memory limit **15 MB**. Запуск sing-box внутри может превысить (особенно с rule engine — Phase 8).
**Prevention:** В Phase 1 это не критично (минимальный конфиг, один outbound). НО в Phase 6+ нужно мониторить через MXMetricManager `MXMemoryMetric`.
**Warning signs:** Extension crashes с `EXC_RESOURCE` в crash log; `wasTerminatedByOS` в `MXAppExitMetric`.

### Pitfall 4: `includeAllNetworks=true` + смена Wi-Fi/LTE → connectivity loss

**Что:** Известный bug iOS 16+/17 ([Apple Forums thread 706963](https://developer.apple.com/forums/thread/706963)). На iOS 18 ситуация улучшилась, но не идеальна.
**Prevention:** Phase 1 — НЕ лечим. Документировать в Wiki как platform limitation. В Phase 6 (NET-08) auto-reconnect compensirует частично.
**Warning signs:** Юзер пишет «отвалился интернет когда зашёл в метро».

### Pitfall 5: SwiftData + App Group + extension concurrent access

**Что:** SwiftData не thread-safe для concurrent writes. Если main app пишет, а extension одновременно читает, можно получить crash или corrupt store.
**Prevention:** В Phase 1 — extension только читает (свежий `ModelContainer.mainContext.fetch()` при `startTunnel`). Main app — единственный writer. Через App Group container — file lock работает корректно для read-only.
**Warning signs:** `SQLite database is locked` в OSLog; SwiftData fetch returns nil unexpectedly.

### Pitfall 6: NEPacketTunnelFlow FD extraction через KVC — приватный API

**Что:** `packetFlow.value(forKeyPath: "socket.fileDescriptor")` использует KVC к приватному property. Может перестать работать в будущих iOS versions. Все sing-box-based клиенты так делают.
**Prevention:** Wrap в utility-функцию с try/catch. В Phase 12 audit перед public release — проверить, не отлетит ли это в App Review.
**Warning signs:** App rejected by App Review с упоминанием «private API»; iOS update ломает tunnel.

### Pitfall 7: vendored libbox.xcframework не пересобран под Xcode 16

**Что:** gomobile produces XCFramework с метаданными для конкретной Xcode версии. `libbox.xcframework` собранный под Xcode 15 может работать в Xcode 16 с warnings, но **по-новой собирать обязательно** перед production. `[CITED: golang/go#66500]`
**Prevention:** В Wave 0 — собрать libbox локально через `gomobile bind -target ios,iossimulator,macos -o libbox.xcframework github.com/sagernet/sing-box/experimental/libbox` (требует Go 1.24+).
**Warning signs:** Xcode warning «Module compiled with Xcode 15.x cannot be imported by Xcode 16.x»; UB при runtime.

### Pitfall 8: MetricKit на macOS — historically unreliable

**Что:** До macOS 14 MetricKit не приходил `MXDiagnosticPayload` в значительной части случаев (тихо ничего не присылал). На macOS 15 ситуация улучшилась, но **community reports — всё ещё бывает silence**.
**Prevention:** Phase 1 — accept-it-as-is, не блокируем DoD на «должен прийти crash report». Если в Phase 12 будет проблема — рассмотреть `PLCrashReporter` (open source, не SDK типа Sentry).
**Warning signs:** Краш на macOS воспроизводится, но `didReceive([MXDiagnosticPayload])` не вызывается часами.

### Pitfall 9: TestFlight Internal требует тестера в Apple Developer team

**Что:** Internal Testing на TestFlight (бесплатно, без Beta App Review) — **только для users в App Store Connect team**. Friends-tier тестировщики «извне» — только External Testing, который требует Beta App Review.
**Prevention:** Phase 1 — internal-only через TestFlight Internal группу для самого разработчика + 1-2 близких людей с Apple ID в Developer team как «Developer» role. Реальный friends-roll-out — Phase 12.
**Warning signs:** Tester получает email «not eligible» при попытке принять invite.

### Pitfall 10: `Localizable.xcstrings` + Bundle.module + extension target

**Что:** В Swift Package resources — обращение через `Bundle.module`. Внутри NSExtension target shell это работает только если sample.xcstrings включён в extension's resource set. Иначе — fallback на source language без localized fallback.
**Prevention:** Извлечь все user-facing strings из `BaseSingBoxTunnel` и других kit-types в `Localization` package; либо дублировать строки в extension. В Phase 1 в extension нет UI-строк, только log messages (которые OSLog — не локализуются), так что **проблемы нет**.

---

## Runtime State Inventory

> Greenfield phase — не rename/refactor. Однако зафиксируем для полноты картины:

| Категория | Найдено | Действие |
|-----------|---------|----------|
| Stored data | Нет (greenfield) | — |
| Live service config | Apple Developer Portal — App IDs / Provisioning Profiles нужно зарегистрировать (Wave 0). App Store Connect app records (iOS + macOS) — создать в Wave 5. | Manual setup в Apple Developer Portal перед Wave 0; в Wave 5 — App Store Connect manual |
| OS-registered state | На разработческой машине — VPN profile создаётся при первом запуске (через `NETunnelProviderManager`); хранится в Settings → VPN. **Перед запуском SocksProbe для Wave 5 R1 check** — убедиться что только наш VPN активен, посторонние profiles удалены. | Pre-test checklist в Wave 5 |
| Secrets/env vars | `.gitignore`-шенный `Tests/Fixtures/test-config.vless.local.txt` с реальным vless:// конфигом тестового сервера разработчика | Создать в Wave 1, не коммитить |
| Build artifacts | Vendored `Packages/ProtocolEngine/Frameworks/libbox.xcframework` — будет в git LFS или просто в git как binary (≈ 30 MB). Решение в Wave 0. | Wave 0 decision: LFS vs plain git |

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | вся Phase 1 | ✓ (assumed installed) | 16+ | — |
| Apple Developer account active | TestFlight upload | ✓ (Team `UAN8W9Q82U`) | — | — |
| Apple Silicon Mac | macOS build + iOS sim | ✓ (assumed) | — | — |
| Реальный iPhone (iOS 18+) | DoD device test (Wave 5) | предполагается у разработчика | — | iOS sim — частичная проверка (без kill switch verification) |
| Реальный Mac (macOS 15+) | DoD device test | ✓ (dev machine) | — | — |
| Тестовый VLESS+Reality сервер | smoke test (Wave 5 DoD #1) | предполагается у разработчика | — | Без — DoD не пройти |
| `go` 1.24+ | libbox rebuild (опционально Wave 0) | uncertain | — | Использовать vendored xcframework из sing-box releases |
| `gomobile` CLI | libbox rebuild | uncertain | — | то же |
| `sing-box` CLI | локальная валидация JSON-конфига перед commit | uncertain | 1.13.11 | `SingBoxConfigLoader.validate()` тестируется через unit-tests |

**Missing dependencies with no fallback:**
- Тестовый VLESS+Reality сервер — без него Wave 5 DoD #1 (`api.ipify.org`) не пройти. **Действие planner'а:** в Wave 1 task «подготовить test fixture config» добавить human checkpoint — «разработчик предоставляет реальный test config».

**Missing dependencies with fallback:**
- Go + gomobile — можно использовать prebuilt libbox.xcframework из sing-box releases. Локальный build — nice-to-have для Phase 12 CI, не блокер Phase 1.

---

## Validation Architecture

> `nyquist_validation: true` в `.planning/config.json` → раздел обязателен.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | **XCTest** (стандартный Swift Testing — XCTest, не новый swift-testing на v0.1 — он ещё не стандарт для extension targets на iOS 18) |
| Config file | в каждом Package — `Tests/<PackageName>Tests/` + `swift-tools-version: 6.0` в Package.swift |
| Quick run command | `xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS,arch=arm64'` |
| Full suite command | `xcodebuild test -workspace BBTB.xcworkspace -scheme BBTB-AllTests -destination 'platform=macOS' && xcodebuild test ... -destination 'generic/platform=iOS Simulator'` |

`[ASSUMED]` Использование XCTest вместо swift-testing — выбор из соображений совместимости с NSExtension targets и stable tooling в Xcode 16. Planner может пересмотреть; swift-testing работает в Xcode 16 для library targets, но для NSExtension через Xcode scheme — XCTest стабильнее.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| CORE-01 | Все packages компилируются | smoke (build) | `xcodebuild build -workspace BBTB.xcworkspace -scheme BBTB-iOS` | ❌ Wave 0 |
| CORE-08 | libbox.xcframework импортируется и линкуется | smoke (build) | то же | ❌ Wave 0 |
| SEC-01 (R1) | `SingBoxConfigLoader.validate` rejects inbounds[socks] | unit | `xcodebuild test ... -scheme PacketTunnelKit -only-testing:PacketTunnelKitTests/SingBoxConfigLoaderTests/test_rejectsSocksInbound` | ❌ Wave 1 |
| SEC-01 | rejects inbounds[mixed] | unit | то же, `test_rejectsMixedInbound` | ❌ Wave 1 |
| SEC-01 | rejects inbounds[tun] | unit | `test_rejectsTunInbound` | ❌ Wave 1 |
| SEC-02 (R1) | rejects experimental.clash_api | unit | `test_rejectsClashAPI` | ❌ Wave 1 |
| SEC-02 | rejects experimental.v2ray_api | unit | `test_rejectsV2RayAPI` | ❌ Wave 1 |
| SEC-02 | rejects experimental.cache_file.enabled | unit | `test_rejectsCacheFile` | ❌ Wave 1 |
| SEC-03 (R1) | SocksProbe не находит порты | **manual + device** | SocksProbe app run на устройстве при активном туннеле | ❌ Wave 5 |
| SEC-04 (R6) | `TunnelSettings.makeR6Safe` не выставляет destinationAddresses | unit | `xcodebuild test ... -only-testing:PacketTunnelKitTests/TunnelSettingsTests/test_noDestinationAddresses` | ❌ Wave 2 |
| SEC-04 | runtime: `IFF_POINTOPOINT` отсутствует на `utun*` | **manual + device** | self-introspect в `BaseSingBoxTunnel` (DEBUG) + SocksProbe screenshot | ❌ Wave 5 |
| SEC-05 | Keychain item имеет `kSecAttrAccessibleWhenUnlocked` | unit | `KeychainStoreTests/test_accessibilityFlag` | ❌ Wave 4 |
| SEC-06 | malformed JSON → throws | unit | `SingBoxConfigLoaderTests/test_malformedJSON` | ❌ Wave 1 |
| KILL-01 | NETunnelProviderProtocol имеет includeAllNetworks=true | unit | `KillSwitchTests/test_includeAllNetworksApplied` | ❌ Wave 2 |
| KILL-01 | enforceRoutes=true | unit | `KillSwitchTests/test_enforceRoutesApplied` | ❌ Wave 2 |
| KILL-02 | OS блокирует трафик при разрыве | **manual + device** | manual в Wave 5 — отключить сервер, проверить нет трафика | ❌ Wave 5 |
| PROTO-01 | sing-box config с VLESS+Reality валиден и стартует | integration | `BaseSingBoxTunnelTests/test_canStartWithValidVLESSConfig` (macOS only — extension targets не unit-testable на iOS) | ❌ Wave 3 |
| IMP-01 | vless:// URL парсится корректно | unit | `VLESSURIParserTests` — набор фикстур | ❌ Wave 4 |
| IMP-01 | Импорт записывает в SwiftData + Keychain | integration | `ConfigImportTests/test_endToEndImport` | ❌ Wave 4 |
| UX-02 | MainScreen рендерит все 5 состояний | snapshot | `MainScreenViewSnapshotTests` через `swift-snapshot-testing` (опционально) — иначе manual | ❌ Wave 4 |
| UX-03 | ConnectionTimer формат `HH:MM:SS` | unit | `ConnectionTimerTests/test_formatting` | ❌ Wave 4 |
| TELEM-01 | CrashReporter подписан и пишет файлы | integration | `CrashReporterTests/test_writesPayloadToAppGroup` (с fake MXDiagnosticPayload через subclass — Apple даёт mockability через `init()` который public) | ❌ Wave 5 |
| LOC-01 | строки доступны на ru+en | unit | `LocalizationTests/test_allKeysHaveRuAndEn` (читает `.xcstrings` JSON) | ❌ Wave 4 |
| DIST-01 | iOS archive строится | smoke | `xcodebuild archive -workspace BBTB.xcworkspace -scheme BBTB-iOS ...` | ❌ Wave 5 |
| DIST-02 | macOS archive строится | smoke | то же `-scheme BBTB-macOS` | ❌ Wave 5 |

### Sampling Rate

- **Per task commit:** `xcodebuild test -workspace BBTB.xcworkspace -scheme PacketTunnelKit -destination 'platform=macOS'` (быстро — только unit-тесты текущего пакета)
- **Per wave merge:** full unit suite через aggregate scheme `BBTB-AllTests` на macOS + iOS Simulator
- **Phase gate:** full suite green + manual device tests из таблицы выше + screenshots в `security-evidence/` перед `/gsd-verify-work`

### Wave 0 Gaps

- [ ] Создать `Packages/PacketTunnelKit/Tests/PacketTunnelKitTests/` с stub тестов для SingBoxConfigLoader, TunnelSettings, KillSwitch
- [ ] Создать `Packages/ConfigParser/Tests/ConfigParserTests/` для VLESSURIParser
- [ ] Создать `Packages/Localization/Tests/LocalizationTests/` для xcstrings completeness check
- [ ] Создать aggregate scheme `BBTB-AllTests` в BBTB.xcodeproj (Wave 0)
- [ ] Опционально: установить `swift-snapshot-testing` для UI snapshots — **отложено, не Phase 1 must**
- [ ] Framework install: ничего отдельно — XCTest идёт со Swift toolchain

---

## Security Domain

> security_enforcement не отключён в `.planning/config.json` → раздел обязателен.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Phase 1 — нет user auth (биометрия — Phase 10) |
| V3 Session Management | no | Нет server-side session — конфиг хранится локально |
| V4 Access Control | partial | Keychain access group `app.bbtb.shared` ограничивает доступ Team-bound apps |
| V5 Input Validation | **yes** | `SingBoxConfigLoader.validate` (R1), `VLESSURIParser.parse` (malformed URI), JSON parsing strictness |
| V6 Cryptography | no | Phase 1 не делает крипто — sing-box внутри управляет TLS/Reality. Phase 8 — swift-crypto для Ed25519 |
| V7 Errors & Logging | partial | OSLog с redacted secrets (UUID/privateKey НИКОГДА в logs); crash payloads в App Group container, не cleartext в `print()` |
| V8 Data Protection | **yes** | Keychain `kSecAttrAccessibleWhenUnlocked` (SEC-05); App Group container — file protection class `complete` |
| V9 Communication | partial | TLS внутри sing-box — управляется engine; main app→server connection — нет (нет subscription server в Phase 1) |
| V10 Malicious Code | no | Нет user-supplied code execution; конфиги — declarative JSON, проходят validation |
| V11 Business Logic | partial | Single-tunnel-active invariant в SwiftData (CONTEXT.md §5) |
| V12 Files & Resources | partial | Vendored libbox.xcframework — integrity через git SHA (Phase 12: добавить codesign verification в CI) |
| V13 API & Web Service | no | Phase 1 — нет API клиента |
| V14 Configuration | **yes** | Entitlements строго ограничены (CORE-06); только нужные capabilities в Apple Developer Portal |

### Known Threat Patterns for Apple Network Extension + sing-box stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Сторонний app сканирует loopback и находит SOCKS5 нашего туннеля (R1, описано в `Wiki/xray-localhost-vulnerability.md`) | Information Disclosure | (a) Конфиг без inbounds[]; (b) `SingBoxConfigLoader.validate`; (c) SocksProbe verification (SEC-03) |
| Сторонний app определяет VPN по `IFF_POINTOPOINT` флагу через `getifaddrs()` (R6, методичка РКН) | Information Disclosure | НЕ выставлять `destinationAddresses` на `NEIPv4Settings`/`NEIPv6Settings` |
| Утечка секретов (UUID, publicKey, shortId) через logs / crash reports | Information Disclosure | OSLog с `OSLogPrivacy.private` для секретов; Keychain (не файлы) для хранения; redact в crash payloads |
| Сторонний app читает Keychain нашего приложения | Tampering / Info Disclosure | Keychain access group bound to Team Identifier prefix — стороннее приложение от другого Apple Developer не может прочитать |
| Подделка конфига через clipboard на чужом устройстве (атакующий копирует свой vless://) | Tampering | Пользователь должен подтвердить импорт (UX-decision — НЕ auto-apply при появлении в pasteboard, см. CONTEXT.md §5 Deferred Ideas) |
| MITM атака на vless+reality handshake | Spoofing | Reality protocol сам защищает через `publicKey` server-binding — нет нашей mitigation в Phase 1, доверяем sing-box |
| Replay vless:// URI attack (тот же URI применяется повторно) | Replay | Phase 1 — single-active config, новый импорт перезаписывает старый. Risk низкий. |
| Compromised libbox.xcframework (supply chain) | Tampering | Vendored binary в git с известным SHA; Phase 12 — codesign + reproducible build из upstream sing-box source |
| Side-channel detection через MTU / packet timing (DPI fingerprinting) | Information Disclosure | sing-box делает anti-DPI (uTLS, padding) — не наш уровень; задокументировано в `Wiki/anti-dpi-techniques.md` |

---

## State of the Art (2026)

| Old Approach | Current Approach | When Changed | Impact для Phase 1 |
|--------------|------------------|--------------|--------------------|
| `NSStatusItem` + `NSPopover` (AppKit) для Menu Bar | `MenuBarExtra` Scene (SwiftUI) | macOS 13 (2022) | UX-07 — используем `MenuBarExtra` |
| Localizable.strings + .stringsdict (legacy) | `Localizable.xcstrings` (String Catalogs) | Xcode 15 / iOS 17 (2023) | LOC-01 — сразу .xcstrings |
| Combine для async streams | `AsyncSequence` / `AsyncStream` | Swift 5.5+ (2021) | Никаких новых Combine кодов в Phase 1 |
| Completion handlers | `async/await` | Swift 5.5+ (2021) | Все новые APIs — async; Apple ObjC bridges имеют generated async overloads |
| sing-box 1.10 — separate inbound types | sing-box 1.12+ — rule actions, унифицированный routing | sing-box 1.11.0 | Phase 1 конфиг — без legacy inbounds-based routing |
| sing-box `independent_cache` | `store_dns` cache file option | sing-box 1.13.0 | Phase 1 не использует cache_file вообще (R1) — нерелевантно |

**Deprecated/outdated (НЕ использовать в Phase 1):**
- `Combine` для новых модулей (legacy)
- `NSStatusItem` напрямую (используем MenuBarExtra)
- `Localizable.strings` (используем .xcstrings)
- sing-box 1.10.x — older API, нет некоторых Reality features
- xray-core напрямую — sing-box покрывает все наши потребности (xray-core оставлен как опциональный fallback модуль для редких edge cases в Phase 4+)

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | sing-box 1.13.11 schema для VLESS+Reality не имеет breaking changes vs 1.12.x по полям outbound/tls/reality | Раздел 3 | LOW — Reality структура стабильна с 1.10; если в 1.13 переименовали поля, fix занимает 15 мин |
| A2 | `LibboxNewService` принимает JSON string как первый аргумент (а не путь к файлу) | Раздел 2 | MEDIUM — если на самом деле path, нужно писать config в temp file. Verifiable через 5 минут чтения SagerNet/sing-box-for-apple |
| A3 | KVC `"socket.fileDescriptor"` работает на iOS 18 / macOS 15 для извлечения TUN FD | Раздел 2, Pitfall 6 | HIGH — если Apple убрал этот path, нет очевидной замены. **Planner: добавить smoke-test в Wave 3 на dev-device early** |
| A4 | App Group container `group.app.bbtb.shared` доступен и из main app, и из extension через `containerURL(forSecurityApplicationGroupIdentifier:)` без дополнительных хаков на iOS 18 | Раздел 9 | LOW — стандартный pattern |
| A5 | Memory limit для NEPacketTunnelProvider extension на iOS 18 остался ~15 MB как в iOS 16/17 | Pitfall 3 | MEDIUM — если Apple поднял, лучше; если опустил — ломаемся в Phase 6+. Для Phase 1 с минимальным sing-box конфигом — не блокер |
| A6 | XCTest, а не swift-testing, для Phase 1 — выбор из стабильности; swift-testing может работать, не проверено для NSExtension target schemes | Validation Architecture | LOW — обе работают; XCTest гарантированно совместим |
| A7 | Vendored libbox.xcframework в `Packages/ProtocolEngine/Frameworks/` через `.binaryTarget` корректно линкуется в NSExtension target | Раздел 5 | MEDIUM — путь хорошо протестирован SagerNet, но **planner должен в Wave 0 первым шагом сделать end-to-end build test** |
| A8 | Apple sandbox на iOS изолирует loopback connect между разными app sandboxes (т.е. SocksProbe не сможет connect'нуться к нашему extension даже если 127.0.0.1:N открыт) | Раздел 8 | HIGH for SEC-03 verification semantics — если **может** connect'нуться (как на macOS), значит R1 нарушение реально на iOS. Это **именно то, что мы хотим проверить**, поэтому не блокер |
| A9 | `MetricKit` доставляет crash reports надёжно на macOS 15 (улучшение vs macOS 13/14) | Раздел 12, Pitfall 8 | LOW for Phase 1 — Phase 12 рассмотрит fallback если нужно |
| A10 | Existing `Wiki/security-gaps.md` R-нумерация (R1–R6) останется стабильной — Phase 1 не вводит новых архитектурных решений с R7+ | CLAUDE.md sync | LOW — но planner должен после Phase 1 обновить R1, R6 как «closed (verified in Phase 1)» |

**Если эта таблица была бы пустой:** все claims были verified. Здесь 10 ASSUMED items — **planner и discuss-phase должны учесть, что эти точки имеют risk** и предусмотреть либо early-validation steps, либо human-decision points.

---

## Open Questions

1. **A3 — KVC path `"socket.fileDescriptor"` на iOS 18 / macOS 15**
   - Что знаем: на iOS 13-17 и macOS 11-14 работало (все sing-box/xray клиенты). На iOS 18 не verified.
   - Что неясно: убрал ли Apple внутренний KVC path или хотя бы deprecated.
   - Рекомендация: Wave 3 — first task = «спайк на dev-устройстве: extract FD через KVC, проверить что не nil». Если broken — research альтернатива (`packetFlow.value(forKey: "fd")` или приватный селектор).

2. **Сборка libbox.xcframework — vendored vs build-from-source в Wave 0**
   - Что знаем: оба варианта работают.
   - Что неясно: предпочтения maintainer'а (single dev), какой подход надёжнее долгосрочно.
   - Рекомендация: Wave 0 — vendored (быстрый старт). Phase 12 — CI pipeline для reproducible build. **Planner decision needed.**

3. **macOS unsandboxed vs sandboxed для PacketTunnelExtension-macOS**
   - Что знаем: NetworkExtension работает в обоих режимах на macOS.
   - Что неясно: для TestFlight нужен sandbox? Для Mac App Store — да, для TestFlight — формально тоже да.
   - Рекомендация: `app-sandbox=true` в Phase 1 для consistency. Если будут проблемы с capabilities (например, gomobile не может read/write конкретный path) — раскапывать в Wave 5.

4. **MetricKit + Swift 6 + actor-isolated subscribers**
   - Что знаем: `MXMetricManagerSubscriber` protocol pre-dates Sendable.
   - Что неясно: warnings в Swift 6 strict concurrency mode при `MXMetricManager.shared.add(self)`.
   - Рекомендация: Wave 5 — если warnings блокируют, использовать `nonisolated(unsafe)` для `add()` или `@unchecked Sendable` для CrashReporter.

5. **iOS Pasteboard permission prompts (iOS 16+)**
   - Что знаем: iOS показывает «AppName has pasted from ...» banner при `UIPasteboard.general.string` access — это **не блокер**, но новые юзеры могут пугаться.
   - Что неясно: единичный prompt при первом импорте или каждый раз.
   - Рекомендация: Phase 1 — accept; в Phase 11 (UX polish) — добавить custom Paste button через `UIPasteControl` (новый API iOS 16+) для безбаннерного UX.

---

## Phase 1 не-цели

Кратко, чтобы planner не уходил в скоуп v0.2+:

- ❌ Импорт QR (IMP-02) и файл (IMP-03) — Phase 2
- ❌ Auto-fallback между протоколами (PROTO-10) — Phase 2
- ❌ Server list, выбор сервера (UX-04, SRV-01..03) — Phase 3
- ❌ Trojan (PROTO-02), Vision-no-Reality (PROTO-03), SS-2022 (PROTO-04), Hysteria2 (PROTO-05) — Phase 2/4
- ❌ Транспорты (TRANSP-01..05) — Phase 5
- ❌ DPI техники (DPI-01..09) — Phase 7
- ❌ DNS strategy (NET-01..04), IPv6 (NET-05..07) — Phase 6
- ❌ Auto-reconnect (NET-08..11) — Phase 6
- ❌ Rules Engine (RULES-01..11) — Phase 8
- ❌ AppProxyExtension реализация (CORE-05) — Phase 8 (target создаётся пустым в Wave 0)
- ❌ Deep links (DEEP-01..05) — Phase 9
- ❌ Биометрия (BIO-01..04) — Phase 10
- ❌ STUN block (BIO-04 / R3) — Phase 10
- ❌ Advanced settings screen (UX-06), Settings (UX-05) — Phase 10
- ❌ macOS toggle «Отключить enforceRoutes» (KILL-04 / R5) — Phase 10
- ❌ Onboarding screen (UX-01) — Phase 11
- ❌ MAX-detection (DETECT-01..03) — Phase 11
- ❌ TELEM analytics на VPS (TELEM-04..09) — Phase 12
- ❌ Crash reporter UI (TELEM-03) — Phase 12
- ❌ Beta App Review submission (DIST-04) — Phase 12
- ❌ Public TestFlight (DIST-05) — Phase 12
- ❌ Cert pinning (DPI-08) — Phase 10
- ❌ Send log to developer button (TELEM-02) — Phase 11
- ❌ Notarization для macOS .app (SEC-07) — Phase 12

---

## Sources

### Primary (HIGH confidence)

- Apple Developer Documentation:
  - [NEPacketTunnelProvider](https://developer.apple.com/documentation/networkextension/nepackettunnelprovider)
  - [NEIPv4Settings (включая destinationAddresses — R6 critical)](https://developer.apple.com/documentation/networkextension/neipv4settings)
  - [NEPacketTunnelNetworkSettings](https://developer.apple.com/documentation/networkextension/nepackettunnelnetworksettings)
  - [NEVPNProtocol.includeAllNetworks](https://developer.apple.com/documentation/networkextension/nevpnprotocol/includeallnetworks)
  - [NEVPNProtocol.enforceRoutes](https://developer.apple.com/documentation/networkextension/nevpnprotocol/enforceroutes)
  - [NETunnelProviderManager](https://developer.apple.com/documentation/networkextension/netunnelprovidermanager)
  - [MetricKit / MXCrashDiagnostic](https://developer.apple.com/documentation/metrickit/mxcrashdiagnostic)
  - [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
  - [Apple Developer Forums thread 736602 — NEIPv4Settings addresses/subnetMasks](https://developer.apple.com/forums/thread/736602)
- sing-box official docs:
  - [VLESS outbound](https://sing-box.sagernet.org/configuration/outbound/vless/)
  - [Experimental](https://sing-box.sagernet.org/configuration/experimental/)
  - [Apple clients](https://sing-box.sagernet.org/clients/apple/)
  - [Changelog](https://sing-box.sagernet.org/changelog/)
- [SagerNet/sing-box releases — verified 1.13.11 latest stable 2026-04-22](https://github.com/SagerNet/sing-box/releases)
- [SagerNet/sing-box-for-apple repo (reference implementation)](https://github.com/SagerNet/sing-box-for-apple)
- [XTLS/Xray-examples — VLESS Reality URI spec](https://github.com/XTLS/Xray-examples/blob/main/VLESS-TCP-XTLS-Vision-REALITY/REALITY.ENG.md)

### Secondary (MEDIUM confidence)

- [DeepWiki SagerNet/sing-box — libbox Command System](https://deepwiki.com/SagerNet/sing-box/6.3-libbox-command-system) — third-party docs derived from source code
- [kean.blog VPN Part 2: Packet Tunnel Provider](https://kean.blog/post/packet-tunnel-provider) — Swift idiomatic patterns
- [IVPN blog — Kill switch removed from iOS due to Apple leak issue](https://www.ivpn.net/blog/removal-of-kill-switch-from-our-ios-app-due-to-apple-ip-leak-issue/) — known limitation of includeAllNetworks
- [Apple Developer Forums — includeAllNetworks problems](https://developer.apple.com/forums/thread/706963)
- [Habr article — xray/sing-box localhost vulnerability](https://habr.com/en/articles/1020080/) — основа для R1
- [danielsaidi.com — Localize Swift Packages with String Catalogs](https://danielsaidi.com/blog/2025/12/02/a-better-way-to-localize-swift-packages-with-xcode-string-catalogs)
- [elegantchaos.com — String Catalogues in Swift Packages](https://elegantchaos.com/2026/02/12/string-catalogues.html)
- [orchetect/MenuBarExtraAccess (fallback library, не Phase 1)](https://github.com/orchetect/MenuBarExtraAccess)

### Tertiary (LOW confidence — verify if used)

- [EbrahimTahernejad/sing-box-lib (community SwiftPM wrapper)](https://github.com/EbrahimTahernejad/sing-box-lib) — license unverified
- [Apple Developer Forums — NEPacketTunnelFlow questions](https://developer.apple.com/forums/thread/722492) — community-only
- [Various medium.com articles на MetricKit](https://medium.com/@bahalek/tracking-your-ios-app-crashes-ooms-and-other-terminations-with-metrickit-891e77a6e6d5) — community

### Internal sources (HIGH confidence — repo)

- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` — единственный спецификационный источник истины
- `Wiki/security-gaps.md` (R1, R4, R5, R6)
- `Wiki/xray-localhost-vulnerability.md`
- `Wiki/apple-detection-surface.md`
- `Wiki/architecture.md`
- `Wiki/vless-reality.md`
- `Wiki/kill-switch.md`
- `Wiki/config-parser-singbox-launcher.md`
- `Wiki/tech-stack.md`
- `.planning/PROJECT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md`
- `.planning/phases/01-foundation/01-CONTEXT.md`

---

## Metadata

**Confidence breakdown:**
- **Apple-API contract** (раздел 2, 7, 8): **HIGH** — все verified через developer.apple.com, кросс-проверено community
- **libbox.xcframework lifecycle** (раздел 3): **MEDIUM** — source — SagerNet/sing-box-for-apple, нет официальных Apple-style docs; pattern проверен в нескольких production-клиентах
- **sing-box JSON schema** (раздел 4): **HIGH** для VLESS/Reality базовых полей; **MEDIUM** для experimental раздела (могут быть подразделы в 1.13.x не покрытые)
- **vless:// URI parsing** (раздел 5): **HIGH** — XTLS-Examples репо плюс independent docs совпадают
- **SwiftPM + Xcode workspace** (раздел 6): **HIGH** — стандартные patterns
- **Kill switch** (раздел 7): **HIGH** — Apple docs точны; известные quirks задокументированы
- **R6 P2P verification** (раздел 8): **HIGH** для API surface; **MEDIUM** для эмпирической верификации (нужен device test)
- **SocksProbe** (раздел 9): **HIGH** — стандартная TCP probe via Network framework
- **Reference implementations** (раздел 16): **HIGH** для SagerNet/sing-box-for-apple, WireGuardKit; **LOW** для community wrappers
- **Pitfalls** (раздел 17): **MEDIUM-HIGH** — все из verified sources, но iOS 18 behavioral changes не полностью verified

**Research date:** 2026-05-11
**Valid until:** 2026-06-11 (30 дней — Apple-API стабилен; sing-box релизы могут быть быстрыми, проверять перед каждым merge'ом 1.14 alpha changes)

**Ready for planning:** Researcher закончил. Planner может составлять PLAN.md по 6 wave'ам из CONTEXT.md §4 с привязкой к REQ-IDs и тестам из этого RESEARCH.md.

## RESEARCH COMPLETE
