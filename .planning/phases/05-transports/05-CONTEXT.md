# Phase 5: Transports — Context

**Gathered:** 2026-05-12
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 5 доставляет полную transport-overlay поддержку для протоколов VLESS+TLS и Trojan,
плюс архитектурный рефакторинг под масштаб 15+ протоколов.

Конкретно:
1. **4 транспорта** поверх VLESS+TLS и Trojan: WebSocket, HTTP (h2), HTTPUpgrade, gRPC.
   TCP уже реализован — не переделываем.
2. **Shared `TransportConfig` enum** в `VPNCore` — единый тип транспорта для всех протоколов.
   `ParsedTrojan.TransportType` мигрирует на него.
3. **`TransportParamParser`** — общая утилита в `ConfigParser` для чтения transport query-params
   из URI. Устраняет дублирование между `VLESSURIParser`, `TrojanURIParser` и будущими парсерами.
4. **`TransportRegistry`** (CORE-03) — реестр транспортных обработчиков по аналогии с
   `ProtocolRegistry`. Каждый `TransportHandler` знает свой идентификатор, displayName,
   список поддерживаемых протоколов и умеет строить transport-блок sing-box JSON.
5. **PoolBuilder → координатор** — логика построения outbound JSON переезжает из `PoolBuilder`
   в каждый protocol package (`buildOutbound(transport:TransportConfig) -> [String: Any]`).
   `PoolBuilder` становится тонким координатором: вызывает `handler.buildOutbound()`,
   собирает массив, добавляет urltest / direct / dns / route.
6. **`ServerDetailView`** (TRANSP-05) — новый экран деталей сервера с editable Transport Picker.
   Открывается нажатием шеврона `›` справа у каждого сервера в `ServerListSheet`.

### Не в скоупе Phase 5

- XHTTP (SplitHTTP) — официальный sing-box 1.13.x не поддерживает (подтверждено issue #3550).
  Backlog: ждать sing-box upstream или реализовывать через xray-core (CORE-09).
- QUIC как transport для VLESS/Trojan — нестандартный паттерн, нет URI param. Backlog.
- smux / yamux / h2mux — мультиплексирование, Phase 7 (DPI-05).
- ECH (Encrypted Client Hello) — TLS-расширение, Phase 7 (DPI-02).
- WireGuard, AmneziaWG, TUIC v5, OpenVPN — Phase 7.
- Полные Расширенные настройки — Phase 10.

</domain>

<decisions>
## Implementation Decisions

### Transport scope

- **D-01:** Phase 5 реализует **4 транспорта** для обоих протоколов: WebSocket, HTTP (h2),
  HTTPUpgrade, gRPC. TCP уже реализован, не меняется.
- **D-02:** Оба протокола — **VLESS+TLS и Trojan** — получают все 4 транспорта. Trojan уже
  имеет WS (Phase 2) — Phase 5 добавляет к нему HTTP, HTTPUpgrade, gRPC.
- **D-03:** VLESS+Reality — только TCP (XTLS несовместим с transport overlay). Не меняется.

### TransportConfig — shared data model

- **D-04:** Новый `enum TransportConfig: Sendable, Equatable` в **`VPNCore`** (доступен
  всем пакетам без циклических зависимостей):
  ```
  case tcp
  case ws(path: String, host: String)
  case grpc(serviceName: String)
  case http(path: String)
  case httpUpgrade(path: String, host: String)
  ```
- **D-05:** `ParsedVLESSTLS.networkType: String` **заменяется** на `transport: TransportConfig`.
  Поле `networkType: String` удаляется.
- **D-06:** `ParsedTrojan.TransportType` (локальный enum) **мигрирует** на общий `TransportConfig`.
  Поле `transport: ParsedTrojan.TransportType` становится `transport: TransportConfig`.
- **D-07:** Решение в пользу Варианта 3 (shared enum): при 15 протоколах × N транспортах —
  одно место правки вместо N дублированных enum'ов.

### TransportParamParser — устранение дублирования URI-парсинга

- **D-08:** Новая утилита `TransportParamParser` в `ConfigParser`. Принимает
  `[URLQueryItem]` (или `[String: String]`) и возвращает `TransportConfig`.
  Покрывает все URI query-params: `type`, `path`, `host`, `serviceName`.
- **D-09:** `VLESSURIParser` и `TrojanURIParser` вызывают `TransportParamParser` вместо
  собственного парсинга transport params. Все будущие URI-парсеры — тоже.
- **D-10:** Fallback: если `type` отсутствует или `"tcp"` → `TransportConfig.tcp`.
  Неизвестный тип (например `"quic"`) → throws `UnsupportedReason.transportUnsupported`
  (уже есть в `UnsupportedReason`).

### TransportRegistry (CORE-03)

- **D-11:** Новый `protocol TransportHandler: Sendable` в пакете `TransportRegistry` (новый
  пакет, аналогично `ProtocolRegistry`):
  ```
  static var identifier: String { get }          // "ws", "grpc", "http", "httpupgrade", "tcp"
  static var displayName: String { get }          // "WebSocket", "gRPC", …
  static var supportedProtocols: [String] { get } // ["vless-tls", "trojan", …]
  static func buildTransportBlock(for config: TransportConfig) -> [String: Any]?
  ```
- **D-12:** `TransportRegistry.shared` — singleton по образцу `ProtocolRegistry.shared`.
  Хранит `[String: any TransportHandler.Type]`.
- **D-13:** `PoolBuilder` вызывает `TransportRegistry.shared.handler(for: transportType)?
  .buildTransportBlock(for: config)` — не знает о конкретных транспортах напрямую.

### PoolBuilder → координатор

- **D-14:** Каждый protocol package получает новый метод:
  `static func buildOutbound(from parsed: ParsedXxx, transport: TransportConfig, tag: String) -> [String: Any]`
  Затрагивает: `VLESSReality`, `VLESSTLS`, `Trojan`, `ShadowsocksHandler`, `Hysteria2Handler`.
- **D-15:** `PoolBuilder.buildSingBoxJSON` превращается в координатора:
  switch по `AnyParsedConfig` → вызов `ProtocolPackage.buildOutbound(...)` → сборка массива →
  urltest (если > 1) / direct / dns / route. Switch остаётся, но каждый case — одна строка.
- **D-16:** Shadowsocks и Hysteria2 не используют transport overlay (их протоколы не имеют
  transport layer в sing-box). `buildOutbound` для них принимает `transport: TransportConfig`
  но игнорирует его (только `tcp` имеет смысл). R1 invariant для Hysteria2 (`allowInsecure`)
  сохраняется в `Hysteria2Handler.buildOutbound`.

### ServerDetailView (TRANSP-05)

- **D-17:** Новый `ServerDetailView` — navigation push из `ServerListSheet`.
  Триггер: шеврон-кнопка `›` справа у каждого сервера в строке списка.
- **D-18:** Поля в Phase 5 (read-only кроме транспорта):
  - Из `ServerConfig` напрямую: name, host, port, protocolDisplayName, sni, lastLatencyMs, countryCode
  - Из re-parse `rawURI` при открытии экрана: flow, fingerprint, UUID, ALPN, publicKey (Reality),
    shortId (Reality), текущий transport
  - **Editable:** Transport Picker — «Авто / TCP / WS / gRPC / HTTP / HTTPUpgrade»
- **D-19:** Выбор транспорта сохраняется в `ServerConfig.transportOverride: TransportConfig?`
  (SwiftData lightweight migration). `nil` = использовать транспорт из URI (Авто).
- **D-20:** Picker всегда виден — не скрыт за Developer Mode.
- **D-21:** Поля добавляются по мере реализации в следующих фазах (Phase 6+). Phase 5 показывает
  то, что уже готово. Стиль — из существующего `DesignSystem` пакета проекта.

### Claude's Discretion

- Конкретный sing-box JSON для каждого transport block (поля в `transport: { type: "ws", ... }`).
  Образец — существующий WS-блок в `buildTrojanOutbound` в `PoolBuilder.swift`.
- Структура тестов для `TransportParamParser` — по образцу `TrojanURIParserTests`.
- Порядок case'ов в `AnyParsedConfig` switch в `PoolBuilder` — по существующему паттерну.
- Регистрация новых транспортных обработчиков в `AppDelegate` / startup — по образцу Phase 1/2.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Планирование и требования
- `.planning/ROADMAP.md` — Phase 5 scope, success criteria, CORE-03 / TRANSP-01..05
- `.planning/REQUIREMENTS.md` — TRANSP-01..05, CORE-03 детали

### Существующая архитектура (точки расширения)
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — `@Model`; Phase 5 добавляет
  `transportOverride: TransportConfig?` (SwiftData lightweight migration)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ImportedServer.swift` — `AnyParsedConfig` enum,
  `ParsedVLESSTLS` (D-05: заменить `networkType: String` на `transport: TransportConfig`),
  `UnsupportedReason` (уже содержит `.transportUnsupported`)
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift` — рефакторинг D-14/D-15
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — обновить под D-09
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift` — `ParsedTrojan.TransportType`
  мигрирует на `TransportConfig` (D-06); обновить под D-09

### Образцы для новых компонентов
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` — образец для
  `TransportRegistry` (singleton, NSLock, `[String: any Handler.Type]`)
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/ConfigBuilder.swift` — существующий WS transport
  block; образец sing-box transport JSON для Phase 5
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/TrojanHandler.swift` — образец protocol package

### Существующие protocol packages (получат buildOutbound в D-14)
- `BBTB/Packages/Protocols/VLESSReality/` — D-14: добавить `buildOutbound`
- `BBTB/Packages/Protocols/VLESSTLS/` — D-14: добавить `buildOutbound`
- `BBTB/Packages/Protocols/Trojan/` — D-14: добавить `buildOutbound`; D-06: мигрировать TransportType
- `BBTB/Packages/Protocols/ShadowsocksHandler/` — D-14: добавить `buildOutbound`
- `BBTB/Packages/Protocols/Hysteria2Handler/` — D-14: добавить `buildOutbound`; R1 exception сохранить

### Архитектурные решения из предыдущих фаз
- `.planning/phases/04-protocol-expansion/04-CONTEXT.md` — D-03 (networkType: String в Phase 4,
  Phase 5 заменяет), D-08 (R1 exception для Hysteria2 — сохраняется)
- `wiki/security-gaps.md` — R1 принцип (TLS strict), R8 (libbox integration)

### UI-референс ServerDetailView
- `/Users/vergevsky/Downloads/IMG_0508.PNG` — состав полей экрана деталей (ознакомительно, не pixel-perfect)
- `/Users/vergevsky/Downloads/IMG_0509.PNG` — продолжение: TLS-секция

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ParsedTrojan.TransportType` — `.tcp` и `.ws(path:host:)` — точная модель для первых двух case'ов
  нового `TransportConfig`. Migrate, не копировать.
- `PoolBuilder.buildTrojanOutbound()` — единственный существующий transport-aware builder;
  содержит WS-блок `["type": "ws", "path": ..., "headers": ["Host": ...]]` — образец для Phase 5.
- `TrojanURIParser` — паттерн switch по `typeRaw` для dispatch транспортов; Phase 5 заменяет
  на вызов `TransportParamParser`.
- `UnsupportedReason.transportUnsupported` — уже определён в `ImportedServer.swift`; Phase 5
  использует для неизвестных transport types (например `quic`).
- `ProtocolRegistry.shared` — точная структура для `TransportRegistry.shared`.
- `ServerListSheet` — существующий sheet; Phase 5 добавляет шеврон `›` к каждой строке сервера.

### Established Patterns
- **Package-per-handler** — `Protocols/Trojan/`, `Protocols/VLESSReality/` → новый пакет
  `TransportRegistry/` по той же структуре
- **Phase 4 `buildXxx` приватные методы** — переезжают в protocol packages как public static
- **SwiftData lightweight migration** — применялась в Phase 1→2→3→4; Phase 5: добавить
  `transportOverride: TransportConfig?` (optional → no default value нужен, auto-migration)
- **Re-parse rawURI on demand** — используется в `ConfigImporter`; Phase 5 применяет в
  `ServerDetailView` для получения flow/fingerprint/UUID без добавления полей в SwiftData

### Integration Points
- `VPNCore` → добавить `TransportConfig` enum (новый файл `TransportConfig.swift`)
- `ConfigParser` → добавить `TransportParamParser` (новый файл); обновить `VLESSURIParser`,
  `TrojanURIParser`, `ImportedServer.swift` (`ParsedVLESSTLS`)
- `TransportRegistry` → новый пакет; регистрация в App startup
- Каждый Protocol package → добавить `buildOutbound(from:transport:tag:) -> [String: Any]`
- `PoolBuilder` → рефакторинг на coordinator pattern
- `ServerListSheet` → добавить шеврон; `ServerDetailView` — новый View + ViewModel
- `ServerConfig` → добавить `transportOverride: TransportConfig?`

</code_context>

<specifics>
## Specific Ideas

- **sing-box XHTTP подтверждённо отсутствует** — issue #3550 в SagerNet/sing-box; официальный
  мейнтейнер не планирует добавлять. Libbox v1.13.11 не содержит XHTTP. TRANSP-01 переходит
  в backlog.
- **Масштабируемость как приоритет** — все архитектурные решения (D-04 shared enum, D-08/D-09
  shared parser, D-14/D-15 coordinator pattern, D-11 registry) приняты под критерий
  «15 протоколов × 50 транспортов без роста PoolBuilder». Quality over speed.
- **ServerDetailView наполнение по мере роста** — экран показывает только готовые поля;
  новые поля добавляются в Phase 6+ без переработки структуры экрана.
- **Re-parse rawURI** — вместо дублирования полей в SwiftData, при открытии ServerDetailView
  `rawURI` парсится заново → получаем все детали без миграции схемы.

</specifics>

<deferred>
## Deferred Ideas

- **XHTTP transport** — официальный sing-box не поддерживает. Backlog: ждать sing-box upstream
  или реализовать через xray-core (CORE-09 в roadmap). TRANSP-01 заморожен.
- **QUIC для VLESS/Trojan** — нестандартный паттерн, нет URI param. Backlog.
- **smux / yamux / h2mux** (мультиплексирование) — Phase 7 (DPI-05 Mux).
- **ECH (Encrypted Client Hello)** — Phase 7 (DPI-02 TLS расширение).
- **ServerDetailView — редактирование TLS-полей** (SNI, publicKey, fingerprint override) —
  Phase 10 (Advanced settings + Security polish).

</deferred>

---

*Phase: 5-transports*
*Context gathered: 2026-05-12*
