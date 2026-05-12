# Phase 5: Transports — Research

**Researched:** 2026-05-12
**Domain:** V2Ray-family transports (WebSocket / HTTP-h2 / HTTPUpgrade / gRPC) поверх VLESS+TLS и Trojan + архитектурный рефакторинг под shared `TransportConfig` enum + `TransportRegistry` + per-server override UI (ServerDetailView)
**Confidence:** HIGH (transport JSON-схемы verified против sing-box и v2rayNG; codebase-паттерны verified прямым чтением кода; URI query-mapping verified против FmtBase.kt из v2rayNG)

## Summary

Phase 5 — **архитектурный рефакторинг + 4 transport handlers**, а не «3 новых протокола». Существующие 5 протоколов (VLESS+Reality, VLESS+TLS, Trojan, Shadowsocks, Hysteria2) не получают новой функциональности — но 2 из них (VLESS+TLS, Trojan) теперь могут работать поверх 4 транспортов вместо одного TCP.

С точки зрения архитектуры это рефакторинг под scaling: `PoolBuilder.buildSingBoxJSON` сегодня содержит 5 hardcoded outbound-builder функций. После Phase 5 в нём остаётся `switch parsed` + однострочный вызов `Protocols.X.buildOutbound(transport:)`. Логика построения outbound JSON живёт в protocol package'ах. Логика построения transport block'ов живёт в `TransportRegistry` handler-ах. URI-парсинг transport query-params живёт в shared `TransportParamParser`. Этот рефакторинг — необходимое условие для Phase 7 (4 новых протокола: WireGuard / AmneziaWG / TUIC / OpenVPN) и далее: иначе `PoolBuilder` растёт линейно по числу протоколов × транспортов.

UI-аспект — `ServerDetailView` (TRANSP-05) — простой read-mostly экран с одним editable полем (Transport Picker). Открывается через шеврон `›` в `ServerListSheet` (новая NavigationLink). Выбор сохраняется в `ServerConfig.transportOverride: TransportConfig?` (SwiftData lightweight migration через добавление optional поля).

Главные нестандартные точки:

1. **sing-box VLESS outbound с transport overlay требует `network: "tcp"`** [CITED: sing-box.sagernet.org/configuration/outbound/vless]. Transport block (`ws`/`http`/`httpupgrade`/`grpc`) — самостоятельная секция `transport: {...}` рядом с `network`. Не путать с QUIC, где `network: "udp"`.
2. **WS+ALPN h2 конфликт** уже зафиксирован Phase 2 W4 — ALPN `h2` несовместим с WebSocket HTTP/1.1 upgrade. Существующий код в `PoolBuilder.buildTrojanOutbound` фильтрует `h2` из ALPN если transport=ws. Этот фильтр **переезжает** в protocol packages при рефакторинге и должен сохраниться — это R1-safety invariant.
3. **TransportConfig с associated values в SwiftData** работает через `Codable` conformance [VERIFIED: hackingwithswift.com SwiftData docs]. SwiftData flattens enum + associated values в database record. Подводный камень: cloud sync (CloudKit) не поддерживает Codable-стораджа со сложными типами — для BBTB это не критично (CLOUD-01 — v1.9, не v1.0).
4. **TransportRegistry singleton** — точная копия `ProtocolRegistry` (NSLock + `[String: any TransportHandler.Type]`). Никаких новых паттернов.
5. **URI query-param mapping** — стандарт V2Ray family, verified против `FmtBase.kt` в v2rayNG: `type` → transport kind, `path` + `host` для ws/http/httpupgrade, `serviceName` для grpc. `mode` / `authority` для gRPC — игнорируются в Phase 5 (используются дефолты sing-box).

**Primary recommendation:** Реализовать строго по образцу Phase 4 — package-per-handler структура, рефакторинг через 6 волн (Wave 0 foundation: `TransportConfig` enum + `TransportRegistry` пакет + `TransportParamParser` + tests scaffold; Waves 1-4 per-transport vertical slices ws→http→httpupgrade→grpc; Wave 5 integration с `PoolBuilder` coordinator + `ConfigImporter`; Wave 6 UI — шеврон + `ServerDetailView`). Никаких новых архитектурных решений — все шесть D-04..D-21 уже locked в CONTEXT.md.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Transport scope:**
- **D-01:** Phase 5 реализует **4 транспорта** для обоих протоколов: WebSocket, HTTP (h2), HTTPUpgrade, gRPC. TCP уже реализован, не меняется.
- **D-02:** Оба протокола — **VLESS+TLS и Trojan** — получают все 4 транспорта. Trojan уже имеет WS (Phase 2) — Phase 5 добавляет к нему HTTP, HTTPUpgrade, gRPC.
- **D-03:** VLESS+Reality — только TCP (XTLS несовместим с transport overlay). Не меняется.

**TransportConfig — shared data model:**
- **D-04:** Новый `enum TransportConfig: Sendable, Equatable` в **`VPNCore`**:
  ```
  case tcp
  case ws(path: String, host: String)
  case grpc(serviceName: String)
  case http(path: String)
  case httpUpgrade(path: String, host: String)
  ```
- **D-05:** `ParsedVLESSTLS.networkType: String` **заменяется** на `transport: TransportConfig`. Поле `networkType: String` удаляется.
- **D-06:** `ParsedTrojan.TransportType` (локальный enum) **мигрирует** на общий `TransportConfig`. Поле `transport: ParsedTrojan.TransportType` становится `transport: TransportConfig`.
- **D-07:** Решение в пользу Варианта 3 (shared enum): при 15 протоколах × N транспортах — одно место правки вместо N дублированных enum'ов.

**TransportParamParser:**
- **D-08:** Новая утилита `TransportParamParser` в `ConfigParser`. Принимает `[URLQueryItem]` (или `[String: String]`) и возвращает `TransportConfig`. Покрывает все URI query-params: `type`, `path`, `host`, `serviceName`.
- **D-09:** `VLESSURIParser` и `TrojanURIParser` вызывают `TransportParamParser` вместо собственного парсинга transport params. Все будущие URI-парсеры — тоже.
- **D-10:** Fallback: если `type` отсутствует или `"tcp"` → `TransportConfig.tcp`. Неизвестный тип (`"quic"`, `"kcp"`, `"xhttp"`) → throws `UnsupportedReason.transportUnsupported`.

**TransportRegistry (CORE-03):**
- **D-11:** Новый `protocol TransportHandler: Sendable` в пакете `TransportRegistry`:
  ```
  static var identifier: String { get }          // "ws", "grpc", "http", "httpupgrade", "tcp"
  static var displayName: String { get }          // "WebSocket", "gRPC", …
  static var supportedProtocols: [String] { get } // ["vless-tls", "trojan", …]
  static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
  ```
- **D-12:** `TransportRegistry.shared` — singleton по образцу `ProtocolRegistry.shared`.
- **D-13:** `PoolBuilder` вызывает `TransportRegistry.shared.handler(for: transportType)?.buildTransportBlock(for: config)`.

**PoolBuilder → coordinator:**
- **D-14:** Каждый protocol package получает новый метод: `static func buildOutbound(from parsed: ParsedXxx, transport: TransportConfig, tag: String) -> [String: Any]`. Затрагивает: `VLESSReality`, `VLESSTLS`, `Trojan`, `ShadowsocksHandler`, `Hysteria2Handler`.
- **D-15:** `PoolBuilder.buildSingBoxJSON` превращается в координатора: switch по `AnyParsedConfig` → вызов `ProtocolPackage.buildOutbound(...)` → сборка массива → urltest / direct / dns / route.
- **D-16:** Shadowsocks и Hysteria2 не используют transport overlay. `buildOutbound` для них принимает `transport: TransportConfig` но игнорирует его (только `tcp` имеет смысл). R1 invariant для Hysteria2 сохраняется в `Hysteria2Handler.buildOutbound`.

**ServerDetailView (TRANSP-05):**
- **D-17:** Новый `ServerDetailView` — navigation push из `ServerListSheet`. Триггер: шеврон-кнопка `›` справа у каждого сервера в строке списка.
- **D-18:** Поля в Phase 5 (read-only кроме транспорта):
  - Из `ServerConfig` напрямую: name, host, port, protocolDisplayName, sni, lastLatencyMs, countryCode
  - Из re-parse `rawURI` при открытии экрана: flow, fingerprint, UUID, ALPN, publicKey (Reality), shortId (Reality), текущий transport
  - **Editable:** Transport Picker — «Авто / TCP / WS / gRPC / HTTP / HTTPUpgrade»
- **D-19:** Выбор транспорта сохраняется в `ServerConfig.transportOverride: TransportConfig?` (SwiftData lightweight migration). `nil` = использовать транспорт из URI (Авто).
- **D-20:** Picker всегда виден — не скрыт за Developer Mode.
- **D-21:** Поля добавляются по мере реализации в следующих фазах (Phase 6+). Phase 5 показывает то, что уже готово. Стиль — из существующего `DesignSystem` пакета.

### Claude's Discretion

- Конкретный sing-box JSON для каждого transport block — образец в RESEARCH §«sing-box transport JSON».
- Структура тестов для `TransportParamParser` — по образцу `TrojanURIParserTests`.
- Порядок case'ов в `AnyParsedConfig` switch в `PoolBuilder` — по существующему паттерну.
- Регистрация новых транспортных обработчиков в `AppDelegate` / startup — по образцу Phase 1/2/4 (5 `register(...)` строк ниже existing `ProtocolRegistry.shared.register`).

### Deferred Ideas (OUT OF SCOPE)

- **XHTTP transport** — официальный sing-box 1.13.x не поддерживает (issue #3550). Backlog.
- **QUIC для VLESS/Trojan** — нестандартный паттерн, нет URI param. Backlog.
- **smux / yamux / h2mux** (мультиплексирование) — Phase 7 (DPI-05 Mux).
- **ECH (Encrypted Client Hello)** — Phase 7 (DPI-02 TLS расширение).
- **ServerDetailView — редактирование TLS-полей** (SNI, publicKey, fingerprint override) — Phase 10.
- **Outline ssconf://** — не в скоупе Phase 5.

</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CORE-03 | `TransportRegistry` аналогично `ProtocolRegistry` через `protocol TransportHandler` | Раздел «TransportRegistry — образец», `ProtocolRegistry.swift:6-26` — точный образец singleton+NSLock+dict |
| TRANSP-02 | gRPC — HTTP/2 RPC | Раздел «sing-box transport JSON / gRPC», URI param `serviceName` verified [CITED: github.com/2dust/v2rayNG FmtBase.kt] |
| TRANSP-03 finish | WebSocket — legacy совместимость, расширить за пределы Trojan-WS | Phase 2 PoolBuilder.buildTrojanOutbound:262-270 — образец WS block; Phase 5 переносит в protocol package'и + добавляет VLESS+TLS |
| TRANSP-04 | HTTPUpgrade — минималистичный, легче gRPC | Раздел «sing-box transport JSON / HTTPUpgrade» [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]; URI mapping verified |
| TRANSP-05 | В Расширенных можно вручную выбрать транспорт для дебага | Раздел «ServerDetailView UI», D-17..D-21 в CONTEXT.md |

**Не в Phase 5:**
- TRANSP-01 (XHTTP) — заморожен в backlog (sing-box upstream не поддерживает, см. CONTEXT.md «Не в скоупе»).

</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TransportConfig data model | VPNCore package | — | Shared between ConfigParser, PoolBuilder, ServerListFeature, ServerDetailView; no circular deps |
| URI query → TransportConfig mapping | ConfigParser package | — | URI parsing уже live в ConfigParser; `TransportParamParser` рядом с `VLESSURIParser`/`TrojanURIParser` |
| TransportConfig → sing-box JSON block | TransportRegistry package (new) | — | Per CORE-03 — каждый handler знает один transport type |
| Protocol outbound assembly | Protocols/{X} packages | — | D-14 — `buildOutbound(from:transport:tag:)` живёт рядом с handler-ом, не в PoolBuilder |
| Pool composition (outbounds[] + urltest + route) | ConfigParser/PoolBuilder | — | Coordinator pattern D-15; ConfigParser остаётся caller-side координатором |
| ServerDetailView UI | AppFeatures/ServerListFeature (new screen, same module) | DesignSystem (tokens) | Шит уже в ServerListFeature → новый экран как navigation push того же feature module |
| SwiftData transportOverride persistence | VPNCore (ServerConfig @Model) | — | Поле живёт в существующем `@Model` — lightweight migration |
| Bootstrap (handler registration) | App iOSApp/macOSApp | — | Точная копия `ProtocolRegistry.shared.register(...)` паттерна |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| sing-box (via libbox.xcframework) | 1.13.11 | Engine — все 4 транспорта (ws/http/httpupgrade/grpc) поддерживаются нативно [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport] | Принятый стек Phase 1 (R8) |
| SwiftUI | iOS 18+ / macOS 15+ | ServerDetailView UI + Picker | Уже используется в ServerListSheet/SettingsView |
| SwiftData | iOS 18+ / macOS 15+ | `ServerConfig.transportOverride: TransportConfig?` persistence | Уже используется (CORE-10), lightweight migration |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift `Codable` (stdlib) | — | `TransportConfig: Codable` для SwiftData ([CITED: hackingwithswift.com SwiftData enums]) | Обязательно — без Codable SwiftData не может хранить enum |
| Foundation `URLQueryItem` | — | Парсинг transport query-params | Уже используется в VLESSURIParser/TrojanURIParser |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Shared `TransportConfig` enum | Per-protocol typed enums (ParsedVLESSTLS.Transport, ParsedTrojan.Transport) | Уже отклонено в CONTEXT.md D-07: при 15 протоколах × N транспортах дублирование становится maintenance burden |
| `TransportRegistry` (registry pattern) | Hardcoded switch в PoolBuilder | Уже отклонено в D-11..D-13: registry даёт scale-free выбор handler-а; switch растёт линейно |
| Codable enum для SwiftData | Отдельные SwiftData поля (`transportType: String`, `transportPath: String?`, `transportHost: String?`) | Codable короче (1 поле), но SwiftData может крашить на delete с associated values [CITED: SwiftData enum forum issues]. Mitigation: для Phase 5 поле — Codable enum, при первой проблеме мигрируем на split fields в Phase 10 (Advanced settings) |

**Installation:**

Никаких новых внешних зависимостей в Phase 5 — все необходимое уже в стеке (sing-box, SwiftUI, SwiftData, Foundation).

**Version verification:**

```bash
# libbox.xcframework: vendored binary, см. BBTB/Packages/ProtocolEngine/Vendored/
# Verified в ProtocolEngine/Package.swift:12 — sing-box 1.13.11
# Phase 5 не bumps version.
```

[VERIFIED: BBTB/Packages/ProtocolEngine/Package.swift:12] sing-box 1.13.11 already supports all 4 transports natively.

## Architecture Patterns

### System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│ ServerListSheet  (existing)                                         │
│   └─ ServerRow + chevron ›  ─────────► NavigationLink (NEW)         │
│                                              │                      │
│                                              ▼                      │
│                                       ServerDetailView (NEW)        │
│                                       ├─ read-only fields           │
│                                       └─ Transport Picker           │
│                                          │ on change                │
│                                          ▼                          │
│                                       server.transportOverride =    │
│                                          newValue  ┐                │
└────────────────────────────────────────────────────┼────────────────┘
                                                     │
                                          SwiftData write
                                                     │
                                                     ▼
┌──────────────────────────────────────────────────────────────────┐
│ ServerConfig (@Model in VPNCore)                                 │
│   + transportOverride: TransportConfig?  (NEW — lightweight mig) │
└──────────────────────────────────────────────────────────────────┘

URI Import path (also rewritten):

User pastes URI → UniversalImportParser → VLESSURIParser / TrojanURIParser
                                                  │
                            ┌─────────────────────┘
                            ▼
                  TransportParamParser  (NEW shared util in ConfigParser)
                      reads ?type=ws&path=/x&host=cdn.example
                      reads ?type=grpc&serviceName=tunsvc
                      returns TransportConfig
                            │
                            ▼
                  ParsedVLESSTLS.transport = TransportConfig  (was networkType: String)
                  ParsedTrojan.transport   = TransportConfig  (was ParsedTrojan.TransportType)
                            │
                            ▼
                  AnyParsedConfig stored in ImportResult

Connect path (rewritten — coordinator pattern):

User taps connect → MainScreenViewModel → ConfigImporter.provisionTunnelProfile
                                                    │
                                                    ▼
                                          PoolBuilder.buildSingBoxJSON([AnyParsedConfig])
                                                    │  (now THIN COORDINATOR)
                            ┌───────────────────────┘
                            ▼
                  switch parsed:
                    .vlessReality(v) → VLESSReality.buildOutbound(from: v, transport: .tcp, tag: t)
                    .vlessTLS(v)     → VLESSTLS.buildOutbound(from: v, transport: v.transport, tag: t)
                    .trojan(t)       → Trojan.buildOutbound(from: t, transport: t.transport, tag: t)
                    .shadowsocks(s)  → Shadowsocks.buildOutbound(from: s, transport: .tcp, tag: t)
                    .hysteria2(h)    → Hysteria2.buildOutbound(from: h, transport: .tcp, tag: t)
                                                    │
                            ┌───────────────────────┘
                            ▼
                  protocol package's buildOutbound:
                      ─ assembles outbound dict (server/port/uuid/tls/...)
                      ─ if transport != .tcp:
                            block = TransportRegistry.shared.handler(for: transport.identifier)?
                                       .buildTransportBlock(for: transport)
                            outbound["transport"] = block
                      ─ R1 invariant: insecure: false hardcoded (except Hy2 D-08)
                      ─ ALPN h2-strip for WS (Phase 2 W4 carry-forward)
                            │
                            ▼
                  PoolBuilder assembles [outbounds] + urltest + direct + dns + route
                            │
                            ▼
                  sing-box JSON string → NETunnelProviderManager.providerConfiguration
                            │
                            ▼
                  libbox.xcframework starts engine

Override path (per-server transport):

If server.transportOverride != nil:
   transport_to_use = server.transportOverride        (UI manual)
else:
   transport_to_use = parsed.transport                (URI-derived)

Apply in ConfigImporter just before PoolBuilder call.
```

### Recommended Project Structure

Новый пакет `TransportRegistry` повторяет существующий `ProtocolRegistry`:

```
BBTB/Packages/
├── TransportRegistry/                        # NEW package (CORE-03)
│   ├── Package.swift
│   ├── Sources/
│   │   └── TransportRegistry/
│   │       ├── TransportRegistry.swift       # singleton + NSLock + dict
│   │       ├── TransportHandler.swift        # protocol declaration
│   │       └── Handlers/
│   │           ├── TCPTransportHandler.swift       # type: "tcp", returns nil (no block)
│   │           ├── WSTransportHandler.swift        # type: "ws"
│   │           ├── HTTPTransportHandler.swift      # type: "http"
│   │           ├── HTTPUpgradeTransportHandler.swift  # type: "httpupgrade"
│   │           └── GRPCTransportHandler.swift      # type: "grpc"
│   └── Tests/
│       └── TransportRegistryTests/
│           ├── TransportRegistryTests.swift
│           ├── WSTransportHandlerTests.swift
│           ├── HTTPTransportHandlerTests.swift
│           ├── HTTPUpgradeTransportHandlerTests.swift
│           └── GRPCTransportHandlerTests.swift
│
├── VPNCore/Sources/VPNCore/
│   ├── TransportConfig.swift                 # NEW — enum + Codable
│   └── ServerConfig.swift                     # MODIFIED — + transportOverride
│
├── ConfigParser/Sources/ConfigParser/
│   ├── TransportParamParser.swift            # NEW — D-08 util
│   ├── ImportedServer.swift                   # MODIFIED — ParsedVLESSTLS.transport: TransportConfig
│   ├── VLESSURIParser.swift                   # MODIFIED — calls TransportParamParser
│   ├── TrojanURIParser.swift                  # MODIFIED — calls TransportParamParser; ParsedTrojan.TransportType removed
│   └── PoolBuilder.swift                       # MODIFIED — coordinator (5 switch cases → 5 one-liners)
│
├── Protocols/VLESSReality/Sources/VLESSReality/
│   └── ConfigBuilder.swift                    # MODIFIED — + static buildOutbound (transport: .tcp accepted, only TCP supported)
├── Protocols/VLESSTLS/Sources/VLESSTLS/
│   └── ConfigBuilder.swift                    # MODIFIED — + static buildOutbound with full transport support
├── Protocols/Trojan/Sources/Trojan/
│   ├── ConfigBuilder.swift                    # MODIFIED — TransportType enum REMOVED (migrated to TransportConfig); + buildOutbound
│   └── TrojanHandler.swift                    # unchanged
├── Protocols/Shadowsocks/Sources/Shadowsocks/
│   └── ConfigBuilder.swift                    # MODIFIED — + buildOutbound (ignores transport, returns SS outbound as-is)
└── Protocols/Hysteria2/Sources/Hysteria2/
    └── ConfigBuilder.swift                    # MODIFIED — + buildOutbound (R1 D-08 exception preserved)
│
└── AppFeatures/Sources/ServerListFeature/
    ├── ServerListSheet.swift                  # MODIFIED — ServerRow gets chevron callback
    ├── ServerRow.swift                         # MODIFIED — accepts onDetailTap closure, renders chevron Button
    ├── ServerDetailView.swift                  # NEW — main detail screen
    ├── ServerDetailViewModel.swift             # NEW — re-parse rawURI + persist transportOverride
    └── TransportPicker.swift                   # NEW — DesignSystem-styled SwiftUI Picker
```

### Pattern 1: TransportRegistry — exact analog of ProtocolRegistry

**What:** Singleton registry of `any TransportHandler.Type` keyed by transport identifier ("ws", "grpc", "http", "httpupgrade", "tcp").

**When to use:** Lookup transport handler by string identifier at runtime; never hardcode switch over transport types in PoolBuilder/ConfigImporter.

**Example:**

```swift
// Source: BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift
// Pattern to copy 1:1 for TransportRegistry.

public final class TransportRegistry: @unchecked Sendable {
    public static let shared = TransportRegistry()

    private let lock = NSLock()
    private var handlers: [String: any TransportHandler.Type] = [:]

    public func register<H: TransportHandler>(_ handlerType: H.Type) {
        lock.lock(); defer { lock.unlock() }
        handlers[H.identifier] = handlerType
    }

    public func handler(for identifier: String) -> (any TransportHandler.Type)? {
        lock.lock(); defer { lock.unlock() }
        return handlers[identifier]
    }

    public var registeredIdentifiers: [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(handlers.keys).sorted()
    }
}
```

`TransportHandler` protocol:

```swift
public protocol TransportHandler: Sendable {
    static var identifier: String { get }              // e.g. "ws"
    static var displayName: String { get }              // e.g. "WebSocket"
    static var supportedProtocols: [String] { get }     // e.g. ["vless-tls", "trojan"]
    // Returns sing-box transport block dict OR nil if transport is TCP (no block).
    static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
}
```

### Pattern 2: Per-protocol `buildOutbound(from:transport:tag:)` static method

**What:** Each protocol package owns the assembly of its outbound dict, including R1 invariants and transport block injection.

**When to use:** Always — `PoolBuilder` becomes coordinator; никаких `private static func buildXxxOutbound` функций в `PoolBuilder` после Phase 5.

**Example (VLESS+TLS):**

```swift
// Source: pattern adapted from PoolBuilder.buildVLESSTLSOutbound (PoolBuilder.swift:145-164)
// New location: BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/ConfigBuilder.swift

extension ConfigBuilder {
    public static func buildOutbound(
        from parsed: ParsedVLESSTLS,
        transport: TransportConfig,
        tag: String
    ) -> [String: Any] {
        // WS+h2 mitigation (Phase 2 W4 — preserved invariant).
        let alpn: [String]
        if case .ws = transport {
            let filtered = parsed.alpn.filter { $0 != "h2" }
            alpn = filtered.isEmpty ? ["http/1.1"] : filtered
        } else {
            alpn = parsed.alpn
        }

        var outbound: [String: Any] = [
            "type": "vless",
            "tag": tag,
            "server": parsed.host,
            "server_port": parsed.port,
            "uuid": parsed.uuid.uuidString.lowercased(),
            "flow": parsed.flow ?? "",
            "network": "tcp",  // VLESS over TCP transport (per sing-box VLESS outbound; WS/gRPC/HTTP go in transport block)
            "tls": [
                "enabled": true,
                "server_name": parsed.sni,
                "insecure": false,  // R1 hardcoded — VLESS+TLS strict TLS
                "alpn": alpn,
                "utls": ["enabled": true, "fingerprint": parsed.fingerprint],
            ] as [String: Any],
        ]

        // Transport block (delegated to registry).
        let transportID = transport.identifier
        if let block = TransportRegistry.shared.handler(for: transportID)?.buildTransportBlock(for: transport) {
            outbound["transport"] = block
        }
        // If block is nil (TCP) — no transport block, matching sing-box default.

        return outbound
    }
}
```

### Pattern 3: PoolBuilder as coordinator

**What:** `PoolBuilder.buildSingBoxJSON` keeps the switch, but each case is a single-line call to the protocol package.

**Example:**

```swift
// Source: pattern derived from PoolBuilder.swift:39-64 (existing switch).
// After D-15 refactor:

for (index, parsed) in truncated.enumerated() {
    let outbound: [String: Any]
    let tag: String
    switch parsed {
    case .vlessReality(let v):
        tag = "vless-\(index)"
        outbound = VLESSReality.ConfigBuilder.buildOutbound(from: v, transport: .tcp, tag: tag)
    case .vlessTLS(let v):
        tag = "vless-tls-\(index)"
        // D-19 — transport override or URI-derived.
        let effective = serverOverride[v.identityKey] ?? v.transport
        outbound = VLESSTLS.ConfigBuilder.buildOutbound(from: v, transport: effective, tag: tag)
    case .trojan(let t):
        tag = "trojan-\(index)"
        let effective = serverOverride[t.identityKey] ?? t.transport
        outbound = Trojan.ConfigBuilder.buildOutbound(from: t, transport: effective, tag: tag)
    case .shadowsocks(let s):
        tag = "ss-\(index)"
        outbound = Shadowsocks.ConfigBuilder.buildOutbound(from: s, transport: .tcp, tag: tag)
    case .hysteria2(let h):
        tag = "hy2-\(index)"
        outbound = Hysteria2.ConfigBuilder.buildOutbound(from: h, transport: .tcp, tag: tag)
    }
    outbounds.append(outbound)
    tags.append(tag)
}
```

**Note on transport override delivery:** Поскольку `PoolBuilder.buildSingBoxJSON(from: [AnyParsedConfig])` принимает ImmutableParsed-structs (без знания о ServerConfig), есть два варианта:
1. **Apply override в ConfigImporter перед build** — mutate `ParsedVLESSTLS.transport` / `ParsedTrojan.transport` со значением из ServerConfig.transportOverride. PoolBuilder остаётся в полном неведении. **Рекомендуется** — минимальный diff API.
2. **Передавать override map** в новую сигнатуру `buildSingBoxJSON(from:overrides:)`. Более явно, но шире API surface.

### Anti-Patterns to Avoid

- **Хардкодить switch по transport identifier в PoolBuilder/ConfigImporter** — нарушает CORE-03; используй `TransportRegistry.shared.handler(for:)`.
- **Возвращать non-nil transport block из TCPTransportHandler** — sing-box интерпретирует наличие `transport: {type: "tcp"}` как ошибку. TCP = отсутствие transport блока. `TCPTransportHandler.buildTransportBlock(for:)` → `nil`.
- **Добавлять new transport case в `TransportConfig` без обновления TransportRegistry registration** — handler lookup вернёт nil; outbound будет без transport блока; sing-box повиснет на handshake.
- **Использовать SwiftData #Predicate для transportOverride compare** — известный bug (SwiftData UUID? predicate возвращает empty; см. memory `feedback_swiftdata_uuid_predicate.md`). Использовать fetch-all + Swift filter.
- **Хранить ServerConfig.transportOverride через String JSON encoding** — Codable enum работает быстрее и type-safer. Использовать ТОЛЬКО если поломается lightweight migration (см. Pitfall 4).
- **Применять transport override в PoolBuilder напрямую через ServerConfig lookup** — PoolBuilder не имеет ModelContext. Override применяется в ConfigImporter (выше по стеку) перед вызовом PoolBuilder.
- **Удалять `ParsedTrojan.TransportType` без рефакторинга TrojanURIParser** — компилятор не подскажет, что migration неполна; тесты в TrojanURIParserTests.swift:19 (test_realUserFixture_WSparsedCorrectly) поймают.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Transport block JSON assembly | Custom NSDictionary builder per protocol | `TransportRegistry.shared.handler(for:)?.buildTransportBlock` | sing-box JSON schema стабилен, но field names различаются (`service_name` vs `serviceName`); один registry — единственная точка истины |
| URI query → TransportConfig | Per-parser duplication (текущее состояние — VLESS и Trojan дублируют логику) | `TransportParamParser.parse([URLQueryItem]) -> TransportConfig` | D-08/D-09 — каждый из 15 будущих парсеров избегает 10 строк дублирования |
| Singleton thread-safety | `@MainActor` или actor wrapping | `NSLock + final class @unchecked Sendable` | Образец из `ProtocolRegistry.swift:8-26` — verified Phase 1/2/3/4 |
| SwiftData enum persistence | Manual JSON encode/decode в `String` поле | `TransportConfig: Codable` через @Model native [CITED: hackingwithswift.com SwiftData Codable] | Codable conformance автоматический для enum c associated values (Swift 5.5+ [CITED: SE-0295]) |
| ServerDetailView Picker | Custom HStack + tap-to-toggle | SwiftUI `Picker` с `.pickerStyle(.menu)` или `.segmented` | Apple HIG, accessibility default, dark mode automatic |
| Navigation push из ServerListSheet → ServerDetailView | Sheet-внутри-sheet или manual presentation tracking | `NavigationLink` / `NavigationStack` (уже работает в `BBTBRootView`) | iOS 18 / macOS 15 navigation patterns стабильны; ServerListSheet уже sheet — нужна NavigationStack внутри ServerListSheet |

**Key insight:** Phase 5 — это **архитектурный рефакторинг существующего кода**, а не greenfield. Все паттерны уже отработаны в Phase 1-4. Главная задача — НЕ изобретать новые подходы, а **перенести** существующий код в правильные локации (protocol packages, registry, shared util) и **добавить** недостающие handler-ы по уже-валидированному шаблону.

## Common Pitfalls

### Pitfall 1: ALPN h2 + WebSocket несовместимость

**What goes wrong:** При TLS handshake сервер выбирает h2 (HTTP/2), WebSocket upgrade (HTTP/1.1) отвергается с framing mismatch → i/o timeout.

**Why it happens:** ALPN — TLS-extension для негоциации app-layer protocol. WebSocket upgrade требует HTTP/1.1. Если ALPN включает h2, сервер обязан выбрать его согласно RFC 7301.

**How to avoid:** В `WSTransportHandler` (или в `VLESSTLS.buildOutbound` / `Trojan.buildOutbound` при transport=ws) — filter `h2` из ALPN. Если результат пуст → `["http/1.1"]`.

**Warning signs:** sing-box connection timeout без понятной ошибки; `tcp WriteTo` failures в sing-box.log при WS-серверах.

**Reference:** Phase 2 W4 commit `4255a77` — точно эта проблема для Trojan-WS. Существующий код в `PoolBuilder.swift:236-247` сохраняется при миграции в protocol package. Фиксация в коде ALPN-фильтра — **R1 invariant**, нельзя удалять.

### Pitfall 2: TCP — не registry handler

**What goes wrong:** Если зарегистрировать `TCPTransportHandler` с `buildTransportBlock(for: .tcp)` возвращающим `["type": "tcp"]` — sing-box валидатор отвергает с «unknown transport type» (sing-box не имеет transport `tcp` — TCP = отсутствие transport блока).

**Why it happens:** В V2Ray/sing-box terminology TCP — это default network, не transport. Transport блок поверх TCP — это ws/grpc/http/httpupgrade. Голый TCP не имеет блока.

**How to avoid:** `TCPTransportHandler.buildTransportBlock(for: .tcp)` → `nil`. В `ConfigBuilder.buildOutbound` присваиваем `outbound["transport"] = block` ТОЛЬКО если `block != nil`.

**Alternative:** Не регистрировать `TCPTransportHandler` вообще. В `TransportConfig.identifier` для `.tcp` возвращать пустую строку, и в `buildOutbound` skip lookup. **НЕ рекомендуется** — нарушает CORE-03 принцип «все транспорты в registry».

**Recommended:** Регистрировать `TCPTransportHandler` для consistency и API, но `buildTransportBlock` всегда возвращает `nil`. Это самодокументирующая семантика «TCP = no transport overlay».

### Pitfall 3: SwiftData Codable enum migration на iOS 18

**What goes wrong:** Добавление optional `transportOverride: TransportConfig?` к существующему `@Model ServerConfig` крашит при первом запуске на устройстве с уже наполненной БД.

**Why it happens:** SwiftData lightweight migration работает для optional полей с дефолтом nil [CITED: WWDC23 Model your schema]. Но Codable enum с associated values хранится через JSON encoding во внутреннее BLOB-поле — миграция должна "выдумать" дефолт. Для optional `TransportConfig?` дефолт = `nil` (BLOB пустой), что technically OK, но на практике reported edge case'ы (cloud sync, schema versioning, [CITED: fatbobman.com SwiftData Codable considerations]).

**How to avoid:**
1. Объявить `transportOverride: TransportConfig?` с default value `= nil` в `init(...)`.
2. **Не использовать VersionedSchema** для Phase 5 — lightweight migration достаточна для добавления optional Codable поля.
3. Перед commit'ом ОБЯЗАТЕЛЬНО протестировать на реальном устройстве с pre-Phase-5 SwiftData store: установить Phase 4 build → импортировать сервера → пересобрать Phase 5 → проверить, что серверы сохранены.
4. Fallback план: если миграция падает в UAT — split fields (`transportOverrideType: String?`, `transportOverridePath: String?`, `transportOverrideHost: String?`, `transportOverrideServiceName: String?`) с computed property `transportOverride: TransportConfig?` сверху. Это известный workaround [CITED: hackingwithswift.com SwiftData enums].

**Warning signs:** App crashes on launch после первого install Phase 5 build на устройстве с pre-existing data; `SwiftDataError.modelMigrationFailed` в логах.

### Pitfall 4: SwiftData #Predicate с UUID? / Codable enum возвращает empty

**What goes wrong:** Filter серверов по `transportOverride != nil` через `#Predicate { $0.transportOverride != nil }` молча возвращает empty array.

**Why it happens:** SwiftData #Predicate compilation не поддерживает Codable enum сравнения корректно — то же поведение, что для UUID? в Phase 3 (см. memory `feedback_swiftdata_uuid_predicate.md`).

**How to avoid:** ВСЕГДА использовать `context.fetch(FetchDescriptor<ServerConfig>()).filter { $0.transportOverride != nil }` (Swift-side filter после fetch). Та же стратегия, что для `subscriptionID == UUID?` в `SubscriptionMergeService` и `ServerListViewModel`.

**Warning signs:** "No servers have override applied" логирование, хотя пользователь явно выбрал транспорт в UI.

### Pitfall 5: transport override применяется НЕ для нужного сервера

**What goes wrong:** Пользователь выбрал WS-override для сервера A, при connect-е override применился к серверу B.

**Why it happens:** Если override map в PoolBuilder ключается на `host:port:protocolID` (identity key) — два сервера с одинаковым identity (multi-subscription с дублированием) получат одинаковый override.

**How to avoid:** Override применять по **ServerConfig.id** (UUID — primary key, уникальный), а не identity key. В ConfigImporter перед вызовом PoolBuilder:

```swift
let mutableParsed: [AnyParsedConfig] = serverRowsInPool.map { row in
    var parsed = parsedFor(row)  // re-parse from rawURI/Keychain
    if let override = row.transportOverride {
        parsed = applyTransportOverride(parsed, override)
    }
    return parsed
}
```

`applyTransportOverride(_:_:)` — pure function в ConfigParser:

```swift
switch parsed {
case .vlessTLS(var v): v.transport = override; return .vlessTLS(v)
case .trojan(var t):   t.transport = override; return .trojan(t)
case .vlessReality, .shadowsocks, .hysteria2:
    return parsed  // override игнорируется (D-03, D-16)
}
```

### Pitfall 6: gRPC `service_name` (snake_case) vs `serviceName` (camelCase)

**What goes wrong:** Transport block с `"serviceName": "tunsvc"` отвергается sing-box validator-ом; соединение не устанавливается.

**Why it happens:** sing-box JSON schema требует snake_case: `service_name` [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]. URI query-param — camelCase: `serviceName` (V2Ray standard [CITED: github.com/2dust/v2rayNG FmtBase.kt]).

**How to avoid:** В `TransportParamParser` читать URI query как `q["serviceName"]`. В `GRPCTransportHandler.buildTransportBlock` писать sing-box JSON как `"service_name": cfg.serviceName`.

**Warning signs:** sing-box returns "json: unknown field serviceName" или transport не устанавливается.

### Pitfall 7: HTTP transport `host` — array vs string

**What goes wrong:** Конфиг с `"host": "example.com"` для type=http валидируется sing-box-ом как malformed.

**Why it happens:** sing-box HTTP transport schema требует `host: array of string` (для random selection между доменами [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]). HTTPUpgrade — `host: string`. WebSocket — `headers: { Host: string }`. **Три разных схемы.**

**How to avoid:** Per-handler — точное соответствие схеме:

| Transport | sing-box host format | URI source |
|-----------|---------------------|------------|
| ws | `headers: { "Host": "X" }` | `?host=X` query param |
| http | `host: ["X"]` (array!) | `?host=X` query param wrapped to single-element array |
| httpupgrade | `host: "X"` (string) | `?host=X` query param |
| grpc | — (no host field, use server.server_name) | — |

### Pitfall 8: TransportRegistry registration order vs ProtocolRegistry

**What goes wrong:** ProtocolRegistry зарегистрирован, тут же ConfigImporter пытается parse URI с transport=ws, но TransportRegistry пуст → `buildTransportBlock` возвращает nil → outbound без transport блока → connection fails.

**Why it happens:** `BBTB_iOSApp.init()` регистрирует ProtocolRegistry в линии 37-41. Если забыть добавить TransportRegistry регистрацию рядом, parsers всё ещё компилируются (они используют TransportRegistry lazily).

**How to avoid:** В Wave 5 (integration) explicit registration в `BBTB_iOSApp.init()` и `BBTB_macOSApp.init()`:

```swift
// CORE-03: регистрируем транспорты
TransportRegistry.shared.register(TCPTransportHandler.self)
TransportRegistry.shared.register(WSTransportHandler.self)
TransportRegistry.shared.register(HTTPTransportHandler.self)
TransportRegistry.shared.register(HTTPUpgradeTransportHandler.self)
TransportRegistry.shared.register(GRPCTransportHandler.self)
```

**Verification:** Smoke test в `TransportRegistryTests` — `TransportRegistry.shared.registeredIdentifiers == ["grpc", "http", "httpupgrade", "tcp", "ws"]` после bootstrap.

### Pitfall 9: ServerDetailView re-parse rawURI на supported server fails

**What goes wrong:** `T-02-04` invariant: для supported `ServerConfig`, `rawURI = nil` (секреты в Keychain). ServerDetailView пытается re-parse → fail → пустой экран.

**Why it happens:** Phase 2 W3 T-02-04 mitigation: после успешного импорта `rawURI` обнуляется чтобы не дублировать секреты вне Keychain. Phase 4 D-14 наоборот ставит `rawURI = nil` после auto-upgrade success.

**How to avoid:** ServerDetailView **re-reads из Keychain** через `ConfigImporter.reparseFromKeychain(server:)` — этот метод существует с Phase 4 для re-parse pipeline. Если `rawURI != nil` (unsupported или phase-upgraded) — использовать его. Иначе — Keychain path.

**Alternative:** Сохранять не-секретные fields (flow, fingerprint, alpn, transport) в SwiftData отдельно. Но это противоречит D-21 — поля добавляются по мере роста. **НЕ рекомендуется** на Phase 5.

### Pitfall 10: TransportConfig.tcp лишний в URI parse

**What goes wrong:** URI `vless://uuid@host:443?security=tls&type=tcp` — `type=tcp` явно указан. `TransportParamParser` возвращает `.tcp`, что корректно. Но `VLESSTLS.buildOutbound` всё ещё может попытаться вызвать TransportRegistry, что вернёт nil, и блок не добавится.

**Why it happens:** Тонкость в когорте URI с `type=raw` (некоторые провайдеры используют как алиас TCP).

**How to avoid:** В `TransportParamParser.parse(_:)`:
- `type == nil` или `type == "tcp"` или `type == "raw"` → `.tcp`
- `type == "ws"` → `.ws(...)` (требует path; иначе throws)
- `type == "grpc"` → `.grpc(serviceName: ...)` (default "TunService" если отсутствует)
- `type == "http"` или `type == "h2"` → `.http(...)` (требует path; default "/")
- `type == "httpupgrade"` → `.httpUpgrade(...)` (требует path)
- иначе → throws `UnsupportedReason.transportUnsupported`

## Runtime State Inventory

Phase 5 — частично refactor (TransportType → TransportConfig migration). Проверяем каждую категорию:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **ServerConfig.outboundJSON** содержит уже-built outbound dict (потенциально с inline transport block для Trojan-WS). При апгрейде Phase 4 → Phase 5 эта строка останется в БД. PoolBuilder читает `outboundJSON` ТОЛЬКО как fallback, основной source — re-parse через rawURI/Keychain. → Действие: **никаких миграций не нужно**, outboundJSON будет перестроен при следующем `provisionTunnelProfile` вызове. Однако ServerConfig.transportOverride на старых rows будет nil (default), что корректно (URI-derived transport). | Никаких — auto-rebuild при next connect |
| Live service config | **NETunnelProviderManager.providerConfiguration** содержит JSON с outbound dict. Phase 4 версия (без transport overlay для VLESS+TLS) остаётся на устройстве. После обновления приложения первое `provisionTunnelProfile` перепишет конфиг. До этого момента кнопка connect использует Phase 4 JSON — это OK (backward-compatible, TCP transport работает). | Никаких — manager rewrite на next connect |
| OS-registered state | Нет — Phase 5 не меняет VPN profile registration, на-демандl rules, kill switch settings. | None — verified by reading TunnelController.swift integration patterns |
| Secrets/env vars | Нет — Phase 5 не добавляет секретов. Keychain entries (per-server) — без изменений. | None |
| Build artifacts | **Trojan tests fixture `trojan-ws-user-fixture.txt`** — содержит URI с `type=ws` query, был parse'ом old `ParsedTrojan.TransportType.ws`. После миграции тип меняется на `TransportConfig.ws`, но семантика идентична (`path` + `host`). Test snapshots могут сломаться. | Update `TrojanURIParserTests` assertions: `if case .ws(let path, let host) = parsed.transport` остаётся валидным после миграции, но импорт structure (`ParsedTrojan.TransportType` → `TransportConfig`) — нужно убрать `ParsedTrojan.TransportType` references из tests |

**Канонический вопрос:** *После обновления каждого Swift файла, что в runtime ещё держит старое имя/тип?*

→ **Ответ:** `NETunnelProviderManager.providerConfiguration` cached JSON. Не блокирует — на next `provisionTunnelProfile` всё перестраивается. ServerConfig.outboundJSON — то же самое.

**Никаких data migrations не требуется.** Только schema migration (SwiftData lightweight для transportOverride).

## Code Examples

Verified patterns from official sources and existing codebase.

### Example 1: TransportConfig enum (Codable + Sendable + Equatable)

```swift
// Source: New file BBTB/Packages/VPNCore/Sources/VPNCore/TransportConfig.swift
// Adapted from CONTEXT.md D-04.

import Foundation

/// Phase 5 D-04 — shared transport configuration enum.
/// Used by ParsedVLESSTLS, ParsedTrojan, ServerConfig.transportOverride.
/// Codable conformance enables SwiftData persistence (lightweight migration).
public enum TransportConfig: Sendable, Equatable, Codable, Hashable {
    case tcp
    case ws(path: String, host: String)
    case grpc(serviceName: String)
    case http(path: String)
    case httpUpgrade(path: String, host: String)

    /// Used by TransportRegistry.handler(for:) lookup.
    public var identifier: String {
        switch self {
        case .tcp:         return "tcp"
        case .ws:          return "ws"
        case .grpc:        return "grpc"
        case .http:        return "http"
        case .httpUpgrade: return "httpupgrade"
        }
    }

    /// UI display name (used in ServerDetailView Picker).
    public var displayName: String {
        switch self {
        case .tcp:         return "TCP"
        case .ws:          return "WebSocket"
        case .grpc:        return "gRPC"
        case .http:        return "HTTP/2"
        case .httpUpgrade: return "HTTPUpgrade"
        }
    }
}
```

### Example 2: sing-box transport JSON blocks

Each `buildTransportBlock` returns this exact dict structure:

#### WebSocket
```swift
// Source: PoolBuilder.swift:262-270 (existing) + sing-box v2ray-transport docs
// [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]

// TransportConfig.ws(path: "/buy", host: "cdn.example")
[
    "type": "ws",
    "path": "/buy",
    "headers": [
        "Host": "cdn.example"
    ]
]
// Notes:
// - "Host" — first letter capital (HTTP header convention; sing-box echoes verbatim).
// - max_early_data / early_data_header_name — Phase 5 не использует (defaults).
// - If `host` empty → use parent outbound's SNI (delegated to caller, not handler).
```

#### gRPC
```swift
// Source: [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]

// TransportConfig.grpc(serviceName: "tunsvc")
[
    "type": "grpc",
    "service_name": "tunsvc",  // snake_case! Pitfall 6.
    // idle_timeout, ping_timeout, permit_without_stream — defaults
]
```

#### HTTP (h2)
```swift
// Source: [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]

// TransportConfig.http(path: "/api")
[
    "type": "http",
    "host": ["example.com"],  // ARRAY (Pitfall 7)! Single-element OK.
    "path": "/api",
    // method, headers, idle_timeout, ping_timeout — defaults
]
// Note: host array из outbound.tls.server_name если не указан явно в URI.
// Если URI явно `?host=cdn.example` — array = ["cdn.example"].
```

#### HTTPUpgrade
```swift
// Source: [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport]

// TransportConfig.httpUpgrade(path: "/upgrade", host: "example.com")
[
    "type": "httpupgrade",
    "host": "example.com",  // STRING (not array; Pitfall 7).
    "path": "/upgrade",
    // headers — default empty
]
```

### Example 3: TransportParamParser implementation

```swift
// Source: New file BBTB/Packages/ConfigParser/Sources/ConfigParser/TransportParamParser.swift
// D-08 / D-09 / D-10 / Pitfall 10.

import Foundation
import VPNCore

public enum TransportParamParser {

    public enum ParserError: Error, LocalizedError, Equatable {
        case wsMissingPath
        case httpMissingPath
        case httpUpgradeMissingPath
        case unsupportedType(String)

        public var errorDescription: String? {
            switch self {
            case .wsMissingPath:          return "WebSocket transport requires non-empty path"
            case .httpMissingPath:        return "HTTP transport requires non-empty path"
            case .httpUpgradeMissingPath: return "HTTPUpgrade transport requires non-empty path"
            case .unsupportedType(let t): return "Unsupported transport type: \(t)"
            }
        }
    }

    /// Parse [String: String] dictionary of URI query params → TransportConfig.
    /// - `type` absent / "tcp" / "raw" → .tcp
    /// - `type=ws` requires `path`; `host` defaults to empty (caller substitutes SNI)
    /// - `type=grpc` reads `serviceName` (camelCase per V2Ray) — default "TunService"
    /// - `type=http` or `type=h2` requires `path`; `host` optional
    /// - `type=httpupgrade` requires `path` AND `host`
    /// - other → throws .unsupportedType
    public static func parse(query: [String: String]) throws -> TransportConfig {
        let typeRaw = (query["type"] ?? "tcp").lowercased()
        switch typeRaw {
        case "tcp", "raw", "":
            return .tcp
        case "ws":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.wsMissingPath
            }
            let host = query["host"] ?? ""
            return .ws(path: path, host: host)
        case "grpc":
            let svc = query["serviceName"] ?? "TunService"
            return .grpc(serviceName: svc)
        case "http", "h2":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.httpMissingPath
            }
            return .http(path: path)
        case "httpupgrade":
            guard let path = query["path"], !path.isEmpty else {
                throw ParserError.httpUpgradeMissingPath
            }
            let host = query["host"] ?? ""
            return .httpUpgrade(path: path, host: host)
        default:
            throw ParserError.unsupportedType(typeRaw)
        }
    }
}
```

### Example 4: WSTransportHandler

```swift
// Source: New file BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift

import Foundation
import VPNCore

public enum WSTransportHandler: TransportHandler {
    public static let identifier = "ws"
    public static let displayName = "WebSocket"
    public static let supportedProtocols = ["vless-tls", "trojan"]

    public static func buildTransportBlock(for config: TransportConfig) -> [String: Any]? {
        guard case let .ws(path, host) = config else { return nil }
        var block: [String: Any] = ["type": "ws", "path": path]
        if !host.isEmpty {
            block["headers"] = ["Host": host]
        }
        return block
    }
}
```

### Example 5: ServerDetailView skeleton

```swift
// Source: New file BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailView.swift
// D-17 / D-18 / D-19 / D-20 / D-21.

import SwiftUI
import VPNCore
import DesignSystem
import Localization
import ConfigParser

public struct ServerDetailView: View {
    @ObservedObject var viewModel: ServerDetailViewModel

    public init(viewModel: ServerDetailViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section(header: Text(L10n.serverDetailGeneralSection)) {
                LabeledRow(label: L10n.serverDetailName, value: viewModel.server.name)
                LabeledRow(label: L10n.serverDetailHost, value: viewModel.server.host)
                LabeledRow(label: L10n.serverDetailPort, value: "\(viewModel.server.port)")
                LabeledRow(label: L10n.serverDetailProtocol, value: viewModel.server.protocolDisplayName)
                if let sni = viewModel.server.sni {
                    LabeledRow(label: "SNI", value: sni)
                }
                if let latency = viewModel.server.lastLatencyMs {
                    LabeledRow(label: L10n.serverDetailLatency, value: "\(latency) ms")
                }
            }

            // From re-parsed rawURI / Keychain (D-18).
            if let parsed = viewModel.parsedDetails {
                Section(header: Text(L10n.serverDetailParsedSection)) {
                    if let uuid = parsed.uuid { LabeledRow(label: "UUID", value: uuid.uuidString) }
                    if let flow = parsed.flow { LabeledRow(label: L10n.serverDetailFlow, value: flow) }
                    LabeledRow(label: L10n.serverDetailFingerprint, value: parsed.fingerprint)
                    if !parsed.alpn.isEmpty {
                        LabeledRow(label: "ALPN", value: parsed.alpn.joined(separator: ", "))
                    }
                    if let pbk = parsed.publicKey { LabeledRow(label: L10n.serverDetailPublicKey, value: pbk) }
                    if let sid = parsed.shortId { LabeledRow(label: L10n.serverDetailShortId, value: sid) }
                }
            }

            Section(header: Text(L10n.serverDetailTransportSection)) {
                Picker(L10n.serverDetailTransport, selection: $viewModel.selectedTransport) {
                    Text(L10n.serverDetailTransportAuto).tag(TransportSelection.auto)
                    Text("TCP").tag(TransportSelection.tcp)
                    Text("WebSocket").tag(TransportSelection.ws)
                    Text("gRPC").tag(TransportSelection.grpc)
                    Text("HTTP/2").tag(TransportSelection.http)
                    Text("HTTPUpgrade").tag(TransportSelection.httpUpgrade)
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedTransport) { _, new in
                    Task { await viewModel.applyTransportSelection(new) }
                }
                Text(L10n.serverDetailTransportFooter)
                    .font(DS.Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(viewModel.server.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

public enum TransportSelection: Hashable {
    case auto         // = transportOverride = nil; use URI-derived
    case tcp
    case ws
    case grpc
    case http
    case httpUpgrade
}

private struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).foregroundStyle(.primary).textSelection(.enabled)
        }
    }
}
```

### Example 6: ServerListSheet chevron → NavigationLink

```swift
// Source: Modification to BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift
// D-17: ServerRow получает chevron, NavigationStack оборачивает ScrollView.

// Внутри sheetContent:
NavigationStack {  // NEW wrapper
    ScrollView {
        LazyVStack(spacing: 0, pinnedViews: []) {
            AutoCell(/*…*/)

            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.servers, id: \.id) { server in
                        ServerRow(
                            server: server,
                            isSelected: viewModel.selectedServerID == server.id,
                            pingState: viewModel.pingState(for: server.id),
                            onTap: { viewModel.selectServer(id: server.id) },
                            onDelete: { Task { await viewModel.deleteServer(id: server.id) } },
                            onDetailTap: { viewModel.openDetail(for: server) }  // NEW closure
                        )
                    }
                } header: { sectionHeader(for: section) }
            }
        }
    }
    .navigationDestination(item: $viewModel.openServerDetail) { server in
        ServerDetailView(viewModel: viewModel.makeDetailViewModel(for: server))
    }
}
```

`ServerRow` modification (add trailing chevron Button):

```swift
// Внутри HStack после LatencyBadge и selected checkmark:
Button(action: onDetailTap) {
    Image(systemName: "chevron.right")
        .imageScale(.small)
        .foregroundStyle(.tertiary)
}
.buttonStyle(.plain)
.accessibilityIdentifier("BBTB.ServerListSheet.ServerRow.Detail.\(server.id.uuidString)")
.accessibilityLabel(L10n.serverDetailAccessibilityHint)
```

### Example 7: SwiftData transportOverride field

```swift
// Source: Modification to BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift
// D-19 — добавить optional поле с дефолтом nil для lightweight migration.

@Model
public final class ServerConfig {
    // ... existing fields ...

    /// Phase 5 D-19 — manual transport override.
    /// nil = use URI-derived transport (Авто в Picker).
    /// non-nil = пользователь явно выбрал транспорт в ServerDetailView.
    /// SwiftData lightweight migration: optional Codable enum → дефолт nil, миграция автоматическая.
    public var transportOverride: TransportConfig?

    public init(
        // ... existing parameters ...
        transportOverride: TransportConfig? = nil
    ) {
        // ... existing assignments ...
        self.transportOverride = transportOverride
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Per-protocol typed transport enum | Shared `TransportConfig` in core module | Phase 5 D-04/D-07 | Один enum для всех 15 будущих протоколов; миграция Trojan.TransportType / VLESSTLS.networkType — единственный breaking change в Phase 5 |
| Hardcoded transport JSON в PoolBuilder | TransportRegistry pattern | Phase 5 D-11..D-13 | Новый transport = новый файл handler, не touch PoolBuilder. CORE-03 satisfied. |
| URI transport parsing дублируется | Shared TransportParamParser util | Phase 5 D-08/D-09 | Каждый URI parser теряет 10-15 строк дублирования |
| `PoolBuilder.buildXxxOutbound` private static functions | Per-protocol `ConfigBuilder.buildOutbound(transport:)` | Phase 5 D-14/D-15 | Линейный рост PoolBuilder ❌ → константный (scale-free для протоколов и транспортов) ✅ |
| Per-server config полностью URI-derived | Per-server `transportOverride` field | Phase 5 D-19 | UI ручной override для дебага; UI scaling готова под Phase 10 (Advanced settings) |
| sing-box XHTTP support | Not available in 1.13.x | sing-box upstream | TRANSP-01 заморожен; не Phase 5 |

**Deprecated/outdated:**
- `ParsedTrojan.TransportType` (локальный enum в TrojanURIParser.swift:15-18) — удалить после миграции на TransportConfig (D-06).
- `ParsedVLESSTLS.networkType: String` (поле string-typed) — удалить после миграции на `transport: TransportConfig` (D-05). Это breaking change для existing fixtures.
- `PoolBuilder.buildVLESSOutbound`, `buildVLESSTLSOutbound`, `buildShadowsocksOutbound`, `buildTrojanOutbound`, `buildHysteria2Outbound` — `private static` functions удаляются после миграции в protocol packages (D-14).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | SwiftData lightweight migration корректно обрабатывает добавление optional Codable enum с associated values для уже-заполнённой БД на iOS 18 | Pitfall 3 | Если crash — нужен split-fields fallback (4 поля вместо 1); UAT обнаружит на pre-Phase-5 data |
| A2 | Регистрация `TCPTransportHandler` с `buildTransportBlock → nil` не нарушит sing-box JSON validation | Pitfall 2 | Если нарушит — не регистрируем TCP вообще, skip lookup в ConfigBuilder.buildOutbound при `transport == .tcp` |
| A3 | URI query param `serviceName` — стандарт V2Ray, не `service_name` или `service-name` | Example 2 gRPC, FmtBase.kt CITED | Если разные subscription provider'ы используют `service_name` — нужен fallback chain в TransportParamParser |
| A4 | sing-box HTTP transport `host` — массив строк, HTTPUpgrade — string | Pitfall 7 | Если ошибка — sing-box validation отвергнет JSON, тесты PoolBuilder + R1 invariant test поймают |
| A5 | NavigationStack внутри ServerListSheet (которая sama — `.sheet`) работает корректно на iOS 18 / macOS 15 | Example 6 | iOS sheets с вложенной NavigationStack — поддерживаются с iOS 16, но возможны UX-проблемы при `presentationDetents([.large])`. Fallback: использовать `.fullScreenCover` вместо `.sheet` или sheet-в-sheet через `.sheet(item:)` |
| A6 | Override применяется в ConfigImporter путём mutation parsed-структур перед PoolBuilder | Pitfall 5 / Pattern 3 note | Альтернатива — extending PoolBuilder API сигнатуры; разработчик может выбрать любую из них в Wave 5 |
| A7 | Существующий Phase 2 W4 ALPN h2-strip для WS останется invariant и переедет в protocol packages без потери | Pitfall 1 | Если test test_trojanWS_alpnExcludesH2 после миграции не зелёный — invariant нарушен; стоп-сигнал для UAT |

**Если эта таблица пуста:** Не пуста — 7 ASSUMPTIONS требуют либо UAT-validation (A1, A5, A7), либо принятия решения в Wave 5 (A6), либо verification через sing-box validator при первом build (A2, A3, A4).

## Open Questions

1. **Применять transport override mutation parsed-структур или новой PoolBuilder сигнатурой?**
   - What we know: оба варианта корректны (Assumption A6). Mutation проще (минимальный diff API), сигнатура — explicit (override явно виден в `buildSingBoxJSON(from:overrides:)`).
   - What's unclear: какой подход предпочтительнее для команды.
   - Recommendation: Использовать mutation в ConfigImporter (минимальный diff). Если plan-check или code review укажет на скрытость — refactor в Wave 6.

2. **ServerDetailView re-parse через rawURI или через Keychain reparseFromKeychain?**
   - What we know: rawURI = nil для supported (Phase 2 T-02-04), есть для unsupported. Keychain reparse — существует с Phase 4.
   - What's unclear: один view с two code path-ами vs всегда Keychain (требует декрипт каждый раз при открытии).
   - Recommendation: Always Keychain reparse для supported, rawURI parse для unsupported. Это симметрично с auto-upgrade D-14 паттерном.

3. **NavigationStack внутри ScrollView внутри sheet — UX behavior на iOS 18?**
   - What we know: Поддерживается с iOS 16, но `presentationDetents([.large])` может конфликтовать с push-навигацией (height collapse при push).
   - What's unclear: будет ли visual glitch при push на ServerDetailView когда ServerListSheet был `.height(custom)`.
   - Recommendation: При первом open ServerDetailView force `.large` детент. После dismiss восстановить original. UAT test: T-05-XX (manual on iPhone) — push не collapse-ит шит unexpectedly.

4. **Trojan-WS legacy URI fixtures — full backward-compat?**
   - What we know: `trojan-ws-user-fixture.txt` импортируется в Phase 2/3/4. Phase 5 ломает `ParsedTrojan.TransportType` API.
   - What's unclear: Существуют ли pre-Phase-5 entries в `Subscription.lastFetched` БД с serialized `ParsedTrojan.TransportType` в `outboundJSON`?
   - Recommendation: outboundJSON хранится как **already-built sing-box dict** (не Swift struct), поэтому migration не нужна. Re-build на next connect. Verified by reading `ServerConfig.outboundJSON` docstring (ServerConfig.swift:21).

5. **gRPC `service_name` default — "TunService" (sing-box default) или пусто?**
   - What we know: sing-box default — "TunService" [CITED: sing-box docs]. Server-side админ часто конфигурирует other service names.
   - What's unclear: если URI не содержит `serviceName`, использовать sing-box default или throws?
   - Recommendation: Default "TunService" (D-10 принцип «not-strict, fall back to sing-box default»). Throws только для unsupported type.

## Environment Availability

Phase 5 не добавляет внешних tool-deps — все используемые tools уже в стеке Phase 1-4.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | Build system | ✓ (Phase 1+) | 16.x+ for iOS 18/macOS 15 | — |
| swift toolchain | swiftpm + tests | ✓ | 6.0+ | — |
| libbox.xcframework | sing-box engine | ✓ (vendored) | 1.13.11 | — |
| iOS 18 SDK | App + tests | ✓ (Phase 1+) | iOS 18 | — |
| macOS 15 SDK | App + tests | ✓ (Phase 1+) | macOS 15 | — |
| Yams 6.2.1 | Clash YAML (Phase 4) — Phase 5 не использует | ✓ (Phase 4) | 6.2.1 | n/a (не нужна в Phase 5) |
| Test server with VLESS+TLS+WS configured | UAT | Unknown — пользователь подтверждает | — | UAT может быть deferred to manual, если test-сервера нет |
| Test server with VLESS+TLS+gRPC | UAT | Unknown | — | Same |
| Test server with VLESS+TLS+HTTP/2 | UAT | Unknown | — | Same |
| Test server with VLESS+TLS+HTTPUpgrade | UAT | Unknown | — | Same |
| Test server with Trojan+gRPC | UAT | Unknown | — | Same |

**Missing dependencies with no fallback:** none for code/build path.

**Missing dependencies with fallback:** UAT requires test servers — если у пользователя нет всех 4 transport configurations, UAT defers to manual testing на available combinations (см. Phase 4 precedent — UAT deferred to manual).

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | XCTest (Swift 6.0; уже стек Phase 1-4) |
| Config file | None (XCTest standard `Tests/...Tests/` layout per swiftpm) |
| Quick run command | `cd BBTB/Packages/<package> && swift test --skip-build` (для one package) или per-target: `swift test --filter <TestClassName>` |
| Full suite command | `cd BBTB && for pkg in Packages/*/; do (cd "$pkg" && swift test) || exit 1; done` (per-package iteration, как в Phase 4) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CORE-03 | TransportRegistry stores/retrieves all 5 handlers by identifier | unit | `swift test --filter TransportRegistryTests` | ❌ Wave 0 |
| CORE-03 | Order of registration не важен; lookup case-insensitive если требуется | unit | `swift test --filter TransportRegistryTests.test_caseSensitivity` | ❌ Wave 0 |
| TRANSP-02 | gRPC: URI `?type=grpc&serviceName=svc` → TransportConfig.grpc("svc") → sing-box block `{type: grpc, service_name: svc}` | unit | `swift test --filter TransportParamParserTests.test_grpc` + `swift test --filter GRPCTransportHandlerTests.test_buildBlock` | ❌ Wave 0 |
| TRANSP-02 | VLESS+TLS over gRPC: full outbound dict построен корректно (R1: insecure=false) | unit | `swift test --filter VLESSTLSConfigBuilderTests.test_grpcTransport` | ❌ Wave 0 |
| TRANSP-03 | WS: ALPN h2 не должен попасть в outbound для WS transport (Pitfall 1 invariant) | unit | `swift test --filter VLESSTLSConfigBuilderTests.test_ws_alpn_excludes_h2` + `swift test --filter TrojanConfigBuilderTests.test_ws_alpn_excludes_h2` | ❌ Wave 0 |
| TRANSP-03 | Trojan WS — backward compat: legacy fixtures `trojan-ws-user-fixture.txt` все ещё парсятся в `.trojan` + `transport == .ws(...)` | unit | `swift test --filter TrojanURIParserTests.test_realUserFixture_WSparsedCorrectly` | ✓ существует, нужен update assertions |
| TRANSP-04 | HTTPUpgrade: URI `?type=httpupgrade&path=/x&host=h` → TransportConfig.httpUpgrade → sing-box `{type: httpupgrade, host: "h", path: "/x"}` (Pitfall 7: host string) | unit | `swift test --filter TransportParamParserTests.test_httpUpgrade` + `HTTPUpgradeTransportHandlerTests.test_hostIsString` | ❌ Wave 0 |
| TRANSP-04 | HTTP/h2: host — array (Pitfall 7) | unit | `swift test --filter HTTPTransportHandlerTests.test_hostIsArray` | ❌ Wave 0 |
| TRANSP-05 | ServerDetailView opens via chevron tap; Picker shows current transport derived from rawURI/Keychain | unit (ViewModel) | `swift test --filter ServerDetailViewModelTests` | ❌ Wave 6 |
| TRANSP-05 | Selecting non-Auto transport persists ServerConfig.transportOverride; provision next config applies override | integration | `swift test --filter ServerDetailViewModelTests.test_applyOverride_persists` | ❌ Wave 6 |
| TRANSP-05 | SwiftData lightweight migration: add transportOverride field, existing rows stay accessible | integration | `swift test --filter ServerConfigMigrationTests.test_transportOverride_migration` | ❌ Wave 0 |
| All | R1 invariant — non-Hy2 outbounds никогда insecure=true | unit | `swift test --filter PoolBuilderTests.test_nonHy2_outbounds_neverHaveInsecureTrue` | ✓ существует, должен пройти после рефакторинга |
| All | All 4 transport handlers зарегистрированы в TransportRegistry после bootstrap | smoke | `swift test --filter TransportRegistrySmokeTests.test_allHandlersRegistered` | ❌ Wave 5 |

### Sampling Rate

- **Per task commit:** `swift test --filter <test class>` for the package being modified (~5-15 seconds per package)
- **Per wave merge:** `swift test` per package iteration через wrapper script (full suite ~2 minutes)
- **Phase gate:** Full suite green before `/gsd-verify-work`; manual UAT for actual connectivity per transport (4 transports × 2 protocols = 8 connection tests — может быть deferred to manual как в Phase 4)

### Wave 0 Gaps

- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TransportRegistryTests.swift` — singleton + register + lookup
- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/WSTransportHandlerTests.swift` — WS block schema
- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPTransportHandlerTests.swift` — HTTP block schema (host array!)
- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/HTTPUpgradeTransportHandlerTests.swift` — HTTPUpgrade block schema (host string!)
- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/GRPCTransportHandlerTests.swift` — gRPC block schema (service_name!)
- [ ] `BBTB/Packages/TransportRegistry/Tests/TransportRegistryTests/TCPTransportHandlerTests.swift` — TCP → nil
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/TransportParamParserTests.swift` — 4 transports + tcp default + unsupported throws
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-ws.txt` — VLESS+TLS+WS URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-grpc.txt` — VLESS+TLS+gRPC URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-http.txt` — VLESS+TLS+HTTP URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/vless-tls-httpupgrade.txt` — VLESS+TLS+HTTPUpgrade URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-grpc.txt` — Trojan+gRPC URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-http.txt` — Trojan+HTTP URI
- [ ] `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/Fixtures/trojan-httpupgrade.txt` — Trojan+HTTPUpgrade URI
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/TransportConfigTests.swift` — Codable round-trip + Equatable + identifier mapping
- [ ] `BBTB/Packages/VPNCore/Tests/VPNCoreTests/ServerConfigMigrationTests.swift` — lightweight migration test (add transportOverride field)
- [ ] `BBTB/Packages/Protocols/VLESSTLS/Tests/VLESSTLSTests/BuildOutboundTests.swift` — buildOutbound for each of 4 transports
- [ ] `BBTB/Packages/Protocols/Trojan/Tests/TrojanTests/BuildOutboundTests.swift` — buildOutbound for each of 4 transports
- [ ] `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/ServerDetailViewModelTests.swift` — Picker behavior + persist
- [ ] `BBTB/Packages/AppFeatures/Tests/ServerListFeatureTests/ServerListChevronNavigationTests.swift` — chevron tap opens detail

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 5 не добавляет auth — UUID/password parsing уже в Phase 1/2/4 |
| V3 Session Management | no | Не применимо |
| V4 Access Control | partial | ServerDetailView shows secrets (UUID, password подобие). Same trust boundary как ServerListSheet (already authenticated пользователь приложения). |
| V5 Input Validation | yes | TransportParamParser validate URI query params; ConfigBuilder validate transport block JSON shape; sing-box JSON validation финальный gate |
| V6 Cryptography | no | Phase 5 не меняет TLS/Reality/etc. Все криптографические primitives — sing-box engine. R1 invariant сохраняется. |

### Known Threat Patterns for {sing-box + Swift + iOS}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Malicious URI with transport overlay bypasses R1 (e.g., type=grpc with extra `insecure` param) | Tampering | TransportParamParser ignore-ит non-transport params (insecure не входит в transport scope; обрабатывается на уровне protocol parser-а как и раньше). Tests: `test_unknown_query_params_ignored`. |
| Server-provided rawURI с XSS-подобным content в `path` или `host` (e.g., `path=javascript:alert(...)`) | Tampering / display injection | ServerDetailView отображает строки через `Text(...).textSelection(.enabled)` — никаких HTML/markdown render-ов; XSS не возможен. Sanitize same as Phase 3 sanitizeRowName при необходимости. |
| Невалидный transport JSON (e.g., gRPC с пустым service_name) crash-ит sing-box engine | DoS | Sing-box engine valid input через `SingBoxConfigLoader.validate` перед `startVPNTunnel`. PoolBuilder тесты verify shape против sing-box validator (как в Phase 4). |
| Transport override → user случайно отключает Reality (transport=ws на VLESS+Reality) | Tampering (UX) | D-03 — VLESS+Reality не получает transport overlay. ServerDetailView для Reality серверов либо скрывает Transport Picker, либо показывает disabled state. Логика в ServerDetailViewModel — picker visible только если `server.protocolID in ["vless-tls", "trojan"]`. |
| WS+ALPN h2 leaves connection vulnerable to DPI fingerprinting (HTTP/2 traffic patterns differ from WS) | Information disclosure | ALPN h2-strip для WS (Pitfall 1) — R1-safety invariant с Phase 2. Tests: `test_ws_alpn_excludes_h2`. |
| TransportOverride persists across app uninstall→reinstall via subscription re-fetch | Repudiation (audit) | SubscriptionMergeService при upsert preserve-ит latency/missingFromLastFetch, но **не** transportOverride. Phase 5 решение: при upsert preserve transportOverride если identity совпадает. **Document в SubscriptionMergeService.swift** что transportOverride — user-controlled и преживает re-fetch. |

## Sources

### Primary (HIGH confidence)

- [VERIFIED: codebase] `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` — singleton/NSLock pattern (Phase 5 TransportRegistry copy)
- [VERIFIED: codebase] `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — existing 5-protocol switch + Trojan-WS block (template для transport blocks)
- [VERIFIED: codebase] `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` — current `ParsedTrojan.TransportType.ws` (D-06 migration source)
- [VERIFIED: codebase] `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — current `networkType: String` (D-05 migration source)
- [VERIFIED: codebase] `BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift:36-68` — ParsedVLESSTLS struct (D-05 target)
- [VERIFIED: codebase] `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift:23-92` — @Model patterns (D-19 target)
- [VERIFIED: codebase] `BBTB/Packages/VPNCore/Sources/VPNCore/SwiftDataContainer.swift:14-96` — schema registration and migration pattern (Phase 5 будет добавлять только optional field, lightweight migration без migrate-function)
- [VERIFIED: codebase] `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` — образец protocol package structure (Phase 5 buildOutbound additions)
- [VERIFIED: codebase] `BBTB/App/iOSApp/BBTB_iOSApp.swift:36-41` — ProtocolRegistry registration pattern (TransportRegistry analog)
- [CITED: sing-box.sagernet.org/configuration/shared/v2ray-transport/] — exact JSON schema for ws, http, httpupgrade, grpc transports
- [CITED: sing-box.sagernet.org/configuration/outbound/vless/] — VLESS outbound `network` + `transport` relationship

### Secondary (MEDIUM confidence)

- [CITED: github.com/2dust/v2rayNG FmtBase.kt] — URI query param mapping (verified via WebFetch raw content): `type`, `path`, `host`, `serviceName`, `mode`
- [CITED: hackingwithswift.com SwiftData "Using structs and enums in SwiftData models"] — Codable enum в @Model patterns
- [CITED: hackingwithswift.com SwiftData "Lightweight vs complex migrations"] — adding optional property as lightweight migration

### Tertiary (LOW confidence, marked for validation)

- [LOW] gRPC `mode` URI param (multi vs single channel) — упомянут в v2rayNG FmtBase.kt, но Phase 5 не использует (sing-box default OK)
- [LOW] sing-box HTTP `host` array — single example в search; not authoritative documentation snippet. **Verify** при первом build через sing-box validator или manual test.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — все компоненты verified в codebase (Phase 1-4); no new external dependencies
- Architecture: HIGH — exact analog of ProtocolRegistry/Trojan package patterns
- sing-box transport JSON: HIGH for ws/grpc, MEDIUM for http/httpupgrade (verify host shape at first build)
- URI query mapping: HIGH (v2rayNG FmtBase.kt + Phase 2 TrojanURIParser parsing patterns)
- SwiftData migration: MEDIUM — Codable enum с associated values документирован, но edge cases есть; UAT validates
- ServerDetailView UI: MEDIUM — паттерны DesignSystem существуют, но NavigationStack-в-sheet требует UAT validation (Open Q3)
- Pitfalls: HIGH — все 10 pitfalls имеют existing-code reference или CITED docs

**Research date:** 2026-05-12
**Valid until:** 2026-06-12 (30 days — стек стабилен, sing-box v1.13.x — текущая стабильная major)

---

## Project Constraints (from CLAUDE.md)

Из `/Users/vergevsky/ClaudeProjects/VPN/CLAUDE.md`:

- **Wiki как долговременная память.** Архитектурные решения Phase 5 (TransportRegistry pattern, shared TransportConfig, coordinator pattern PoolBuilder) — обязательно фиксировать в `wiki/security-gaps.md` или новой странице. Не оставлять только в `.planning/`.
- **Имена страниц wiki — lowercase с hyphens.** Применимо если планируется новая страница (например `wiki/transports.md`).
- **Цитирование источников.** Все factual claims в RESEARCH.md имеют `[VERIFIED:]` / `[CITED:]` теги.
- **Ответ на русском.** Эта RESEARCH.md написана преимущественно на русском (per project rule), code блоки/имена и technical terms — на английском по конвенции.
- **Quality over speed.** Соблюдено: рефакторинг под scaling (15 протоколов × N транспортов) выбран вместо «быстро добавить 4 транспорта в текущий PoolBuilder».
- **Подробные ответы.** Соблюдено: каждое решение объяснено + примеры кода + edge cases + pitfalls.
- **Текущий год 2026.** Все ссылки на iOS 18 / macOS 15 / Xcode 16+ актуальны для текущего цикла; sing-box v1.13.11 — текущая стабильная.
- **Файлы в `raw/` не трогать.** Применимо к wiki ingest, не к коду — не релевантно Phase 5.

Sources:
- [V2Ray Transport — sing-box documentation](https://sing-box.sagernet.org/configuration/shared/v2ray-transport/)
- [VLESS outbound — sing-box documentation](https://sing-box.sagernet.org/configuration/outbound/vless/)
- [v2rayNG FmtBase.kt — URI query param mapping](https://github.com/2dust/v2rayNG/blob/master/V2rayNG/app/src/main/java/com/v2ray/ang/fmt/FmtBase.kt)
- [Using structs and enums in SwiftData models — Hacking With Swift](https://www.hackingwithswift.com/quick-start/swiftdata/using-structs-and-enums-in-swiftdata-models)
- [Lightweight vs complex SwiftData migrations — Hacking With Swift](https://www.hackingwithswift.com/quick-start/swiftdata/lightweight-vs-complex-migrations)
- [Considerations for Using Codable and Enums in SwiftData Models — fatbobman](https://fatbobman.com/en/posts/considerations-for-using-codable-and-enums-in-swiftdata-models/)
- [SE-0295 Codable synthesis for enums with associated values](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0295-codable-synthesis-for-enums-with-associated-values.md)
