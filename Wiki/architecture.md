---
name: Архитектура
description: Модульная SwiftPM-структура, Network Extension таргеты, plugin-pattern для протоколов
type: project
---

# Архитектура

**Summary**: SwiftPM-monorepo с plugin-pattern для протоколов и транспортов, отдельные Network Extension таргеты под платформы, общая бизнес-логика в Swift Package.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-15 (Phase 10 closure — FrontingEngine SwiftPM пакет добавлен; PinStore/PinnedSessionDelegate/SubscriptionPinManager для cert pinning. Phase 8 — RulesEngine + split-tunnel. Phase 7c — Engine Boundary Cleanup. См. [[cdn-fronting-architecture-2026]], [[cert-pinning-spki]], [[rules-engine]], [[engine-abstraction-decision-2026]].)

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
│   └── (AppProxyExtension-macOS/)    — DELETED Phase 8 W0 (D-08/D-09, [[appproxy-deferral-2026]])
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
│   │   ├── PoolBuilder.swift         — [AnyParsedConfig] → sing-box JSON; buildSingleOutboundJSON для pre-connect auto-select (v0.3); Phase 10: uTLS picker override via App Group UserDefaults
│   │   ├── ConfigImporting.swift     — protocol ConfigImporting (relocated из MainScreenFeature в v0.3 для DI без circular deps)
│   │   ├── SubscriptionMergeService.swift — identity merge (host+port+protocolID, SNI excluded — ротируется subscription-серверами); missingFromLastFetch pattern (v0.3)
│   │   ├── SubscriptionURLFetcher.swift   — HTTPS-only + isBlockedHost() SSRF-guard (loopback/RFC-1918/link-local) (v0.3)
│   │   ├── PinStore.swift            — Phase 10 ✓: bootstrap SPKI SHA-256 pins (placeholder → replace via generate-spki-pin.swift pre-TestFlight); см. [[cert-pinning-spki]]
│   │   └── PinnedSessionDelegate.swift   — Phase 10 ✓: URLSessionDelegate для cert pinning verification
│   ├── ServerSelector/               — auto-select по пингу + потерям (Phase 5+, в v0.3 логика в VPNCore/ServerProbeService)
│   ├── KillSwitch/                   — системный killswitch через includeAllNetworks
│   ├── DNSManager/                   — DoH, encrypted bootstrap, whitelist
│   ├── RulesEngine/                  — Phase 8 ✓: Ed25519-signed rules pipeline + split-tunnel via sing-box rule_set; см. [[rules-engine]]
│   ├── FrontingEngine/               — Phase 10 ✓: CDN-фронтинг (DPI-06): FrontingProfile, 3 CDN adapters, FrontingConfigApplier, FrontingFailureCache actor, FrontingFallbackChain actor; см. [[cdn-fronting-architecture-2026]]
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

- **`PacketTunnelProvider`** (iOS + macOS) — основной таргет. Все 6 in-scope протоколов (VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, Shadowsocks-2022, Hysteria2, TUIC v5) ходят через него. Layer 3 туннелирование. Базовый класс `NEPacketTunnelProvider`. Внутри запущен sing-box через `libbox.xcframework`, читает конфиг из `providerConfiguration` (передаётся из main app через `NETunnelProviderManager`). **Phase 7c (2026-05-14):** sing-box-specific код контейнерезирован в `PacketTunnelKit/SingBox/` namespace; engine-agnostic utilities (App Group paths, R6-safe TunnelSettings, Phase 6d ExternalVPNStopMarker, OSLog wrappers) остались at top level. См. [[engine-abstraction-decision-2026]] для триггеров будущего введения engine abstraction.
- **`AppProxyProvider`** (только macOS) — **DEFERRED to v0.10+** (Phase 8 D-08/D-09). L4 `NEAppProxyProvider` ↔ L3 sing-box TUN архитектурный mismatch; mutual exclusivity с `NETunnelProviderManager`. Target удалён из Tuist. Вместо него Phase 8 реализует `never_through_vpn` rule_set (L3 IP-level split-tunnel). См. [[appproxy-deferral-2026]].

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
- Auto-select запускается **перед каждым connect** (не кешируется до pull-to-refresh) — **с Phase 6d (DEC-06d-04 + H4 cached snapshot)** auto-mode tap fast path использует cached ranking < 30 sec; full probe только при stale cache или pull-to-refresh
- Серверы с 3/3 timeout пропускаются; если все недоступны — `MainScreenError.noReachableServers`
- **Bounded concurrency (Phase 6d DEC-06d-04):** `probeAll` limit 8 simultaneous; cancellation-safe defer cleanup для `pingAllServers` (M13)

## Phase 6d additions (2026-05-14) — performance & code quality patterns

См. полный детал в [[performance-baseline]]. Краткая выжимка architectural decisions:

- **DEC-06d-01 — Cold-start init defer.** Non-critical inits → `Task.detached(priority: .utility)` или `.onAppear`, не в `BBTB_iOSApp.init` body.
- **DEC-06d-02 — XPC consolidation в TunnelController.** Connect/disconnect ≤ 2 XPC trips через `applyCurrentStateToCachedManager()`.
- **DEC-06d-03 — Event-driven status polling.** Никаких `sleep`-based loops для `NEVPNStatus`; `AsyncStream<NEVPNStatus>` observer-stream.
- **DEC-06d-04 — Bounded concurrency для probe-style operations.** Limit 4-8 + defer cleanup.
- **DEC-06d-05 — Apple-canonical options discriminator.** `startVPNTunnel(options: ["manualStart": NSNumber(true)])` для app-initiated; sticky App Group marker (`ExternalVPNStopMarker.isPending`) для OS/Settings-driven flow.
- **DEC-06d-06 — PerfSignposter spans** (`ColdLaunch`, `ConnectTap`, `PreConnectProbe`, `ProvisionProfile`, `LibboxStart`) сохранены как standard tooling для будущих Instruments capture.

Все 6 decisions применять в Phase 7+ (WireGuard family + anti-DPI suite).

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
