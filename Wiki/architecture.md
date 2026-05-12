---
name: Архитектура
description: Модульная SwiftPM-структура, Network Extension таргеты, plugin-pattern для протоколов
type: project
---

# Архитектура

**Summary**: SwiftPM-monorepo с plugin-pattern для протоколов и транспортов, отдельные Network Extension таргеты под платформы, общая бизнес-логика в Swift Package.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-12 (Phase 3)

---

## Принцип модульности

Compile-time модульность через SwiftPM (Swift Package Manager — менеджер пакетов Swift). Каждый VPN-протокол, каждый transport, каждая подсистема (DNS, kill switch, rules engine, и т.д.) — отдельный модуль с публичным API (Application Programming Interface — программный интерфейс) через `protocol`.

## Plugin-pattern для протоколов

```swift
public protocol VPNProtocolHandler: Sendable {
    static var identifier: String { get }
    static var displayName: String { get }
    var isAvailable: Bool { get }

    func validate(config: ProtocolConfig) throws
    func connect(config: ProtocolConfig) async throws -> TunnelHandle
    func disconnect(handle: TunnelHandle) async throws
    func diagnostics() async -> ProtocolDiagnostics
}
```

Регистрация: `ProtocolRegistry.shared.register(VLESSRealityHandler.self)` при старте. Чтобы убрать протокол из сборки — удалить registration, остальное компилируется. Условная компиляция через `#if canImport(VLESSReality)`.

Аналогичный реестр (`TransportRegistry`) для транспортов.

## Структура пакетов

```
BBTB/
├── App/                              — главные таргеты
│   ├── iOSApp/                       — iOS app (SwiftUI)
│   ├── macOSApp/                     — macOS app (SwiftUI + AppKit Menu Bar)
│   ├── PacketTunnelExtension-iOS/    — NetworkExtension target iOS
│   ├── PacketTunnelExtension-macOS/  — NetworkExtension target macOS
│   └── AppProxyExtension-macOS/      — AppProxyProvider target (только macOS)
│
├── Packages/
│   ├── VPNCore/                      — protocol VPNProtocolHandler, типы Config
│   ├── ProtocolRegistry/             — реестр зарегистрированных протоколов
│   ├── ProtocolEngine/               — обёртка над libbox.xcframework
│   │   ├── SingBoxBridge/            — Swift API над Go-биндингами
│   │   └── XrayFallback/             — опциональная обёртка над xray-core
│   ├── Protocols/                    — реализации по одной на протокол
│   │   ├── VLESSReality/             — VLESS+Reality handler (v0.1)
│   │   └── Trojan/                   — Trojan TCP+TLS + WS+TLS handler (v0.2)
│   ├── Transports/                   — XHTTP, gRPC, WebSocket, HTTPUpgrade
│   ├── ConfigParser/                 — парсинг URI + генерация sing-box JSON (см. [[config-importer]], [[config-parser-singbox-launcher]])
│   │   ├── VLESSURIParser.swift      — vless:// URI → ParsedVLESS
│   │   ├── TrojanURIParser.swift     — trojan:// URI → ParsedTrojan (v0.2)
│   │   ├── PoolBuilder.swift         — [AnyParsedConfig] → sing-box JSON; buildSingleOutboundJSON для pre-connect auto-select (v0.3)
│   │   ├── ConfigImporting.swift     — protocol ConfigImporting (relocated из MainScreenFeature в v0.3 для DI без circular deps)
│   │   ├── SubscriptionMergeService.swift — identity merge (host+port+protocolID, SNI excluded — ротируется subscription-серверами); missingFromLastFetch pattern (v0.3)
│   │   └── SubscriptionURLFetcher.swift   — HTTPS-only + isBlockedHost() SSRF-guard (loopback/RFC-1918/link-local) (v0.3)
│   ├── ServerSelector/               — auto-select по пингу + потерям (Phase 5+, в v0.3 логика в VPNCore/ServerProbeService)
│   ├── KillSwitch/                   — системный killswitch через includeAllNetworks
│   ├── DNSManager/                   — DoH, encrypted bootstrap, whitelist
│   ├── RulesEngine/                  — split tunneling + rules.json
│   ├── DeepLinks/                    — bbtb:// + Universal Links
│   ├── StatsCollector/               — ping monitor + traffic stats
│   ├── Telemetry/                    — privacy-respecting аналитика
│   ├── CrashReporter/                — локальный crash collector
│   ├── BiometricAuth/                — Face ID / Touch ID
│   ├── DesignSystem/                 — общие SwiftUI-компоненты
│   ├── Localization/                 — ru + en строки
│   ├── AppFeatures/                  — модули по экранам
│   ├── AppFeatures/                  — модули по экранам (v0.2+)
│   │   ├── MainScreenFeature/        — главный экран + ConfigImporter + ReconnectBanner
│   │   ├── ServerListFeature/        — sheet со списком серверов, latency badges, auto-select (v0.3)
│   │   ├── SettingsFeature/          — настройки: Kill Switch тоггл, Безопасность
│   │   └── QRScanner/                — сканирование QR-кода (v0.2)
│   └── PlatformDetection/            — MAX-detection через canOpenURL и т.п.
│
└── Tests/                            — по тесту на каждый Package
```

## Network Extension таргеты

- **`PacketTunnelProvider`** (iOS + macOS) — основной таргет. Все протоколы (VLESS, WireGuard, Hysteria2, ...) ходят через него. Layer 3 туннелирование. Базовый класс `NEPacketTunnelProvider`. Внутри запущен sing-box через `libbox.xcframework`, читает конфиг из `providerConfiguration` (передаётся из main app через `NETunnelProviderManager`).
- **`AppProxyProvider`** (только macOS) — split-tunneling по приложениям. На iOS Apple не даёт такого API. Включается опционально из настроек macOS-приложения.

Конфигурация туннеля проксируется через **App Group** между main app и extension — чтобы туннель мог читать актуальный конфиг и rules.json без дёрганья main app.

## Entitlements

- `com.apple.developer.networking.networkextension` со значениями `packet-tunnel-provider` и (macOS) `app-proxy-provider`
- `com.apple.developer.networking.vpn.api` со значением `allow-vpn`
- `com.apple.security.app-sandbox` (macOS)
- `com.apple.security.network.client`
- `com.apple.security.network.server`

## Зависимости

Только SwiftPM. Никаких CocoaPods/Carthage. Внешние зависимости только проверенные:

- sing-box через `libbox.xcframework` (gomobile-биндинги) — https://github.com/SagerNet/sing-box
- xray-core через отдельный xcframework — fallback для специфичных случаев Reality
- WireGuardKit от ZX2C4 — нативный WireGuard
- swift-crypto от Apple — Ed25519 проверка подписи [[rules-engine]]

## Решения, которые НЕ делаем

- Версионирование модулей независимо друг от друга — все модули в одном monorepo, общая версия приложения.
- Multi-hop / chain-proxy на MVP — архитектура должна позволять добавить позже без рефакторинга.
- Никаких сторонних аналитических SDK (Crashlytics, Mixpanel, Sentry).

## SwiftData-схема (v0.3)

Два `@Model`-класса, связанных по FK:

| Модель | Ключевые поля | Примечание |
|--------|---------------|------------|
| `Subscription` | `id: UUID` (@unique), `url: String`, `name: String`, `lastFetched: Date?` | Cascade delete через `@Relationship(deleteRule: .cascade)` |
| `ServerConfig` | `subscriptionID: UUID?` (FK), `countryCode: String?`, `missingFromLastFetch: Bool`, `lastLatencyMs: Int?` | `subscriptionURL: String?` deprecated, оставлен для migration compatibility |

Миграция Phase 2 → Phase 3: `SwiftDataContainer.migratePhase2ToPhase3()`, идемпотентная (guard через `UserDefaults` флаг `app.bbtb.phase3.migrationDone`). Группирует существующие `ServerConfig` по `subscriptionURL`, создаёт `Subscription` строки, прописывает FK.

## TCP-пробы и auto-select (v0.3)

`VPNCore/ServerProbeService` — `public actor` с `AsyncStream<(UUID, ProbeAggregate)>`. Логика:

- 3 последовательных TCP-пробы на сервер (timeout 500 ms через `Task.sleep` race), `NWConnection` к `host:port`
- `score = latencyMs × (1 + lossRate)`, `lossRate = ProbeAggregate.failures / 3` (Int, не Float — исключает IEEE-754 truncation)
- Все серверы параллельно через `TaskGroup`; UI обновляется прогрессивно по мере приходящих результатов
- Auto-select запускается **перед каждым connect** (не кешируется до pull-to-refresh)
- Серверы с 3/3 timeout пропускаются; если все недоступны — `MainScreenError.noReachableServers`

## Related pages

- [[product-overview]]
- [[tech-stack]]
- [[protocols-overview]]
- [[trojan]]
- [[transports]]
- [[rules-engine]]
- [[kill-switch]]
- [[config-importer]]
- [[config-parser-singbox-launcher]]
