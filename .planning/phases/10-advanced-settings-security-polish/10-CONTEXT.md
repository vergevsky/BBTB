# Phase 10: Advanced settings + Security polish — Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

> **Scope amendment (decided 2026-05-15 в discuss-phase):** BIO-01..04 (биометрия) и ONDEMAND-01 (On-Demand rules UI) перенесены в deferred. Phase 10 реализует DPI-05/06/08/09 + STUN-блок + macOS KILL-04 + полная компоновка Advanced Settings экрана. REQUIREMENTS.md и ROADMAP.md обновляются planner'ом в первой задаче плана.

<domain>
## Phase Boundary

**Что фаза делает (v0.10):** Завершает экран Advanced Settings — добавляет все anti-DPI toggles (CDN-фронтинг, Mux, uTLS picker, STUN-блок), cert pinning для subscription URL и macOS-специфичный enforceRoutes toggle. Версия — **v0.10**.

**Платформы:** iOS + macOS (enforceRoutes toggle только macOS).

### В скоупе v0.10

1. **DPI-05: Mux per-server + глобальный toggle** — auto из URI/YAML (если `mux=true`) + ручной toggle в Advanced Settings → Anti-DPI. Только для VLESS+TLS / Trojan / Shadowsocks-2022. Reality/Vision/TUIC/Hysteria2 — запрещено.
2. **DPI-06: CDN-фронтинг** — глобальный toggle в Advanced Settings → Anti-DPI. Применяется к серверам, у которых в конфиге подписки указаны CDN-данные. Архитектурно: `FrontingProfile` отдельный слой поверх HTTP-compatible транспортов (WS, HTTPUpgrade, gRPC, HTTP). НЕ работает для Reality/TUIC/Hysteria2.
3. **DPI-08: Cert pinning** — включён по умолчанию, toggle видим в Advanced Settings → Безопасность. SPKI SHA-256 pin через `URLSessionDelegate`. Scope: только subscription URL endpoint (Marzban). Rules.json уже Ed25519-защищён — pinning не нужен.
4. **DPI-09: uTLS fingerprint picker** — picker в Advanced Settings → Anti-DPI. Default: `random` (сохранён из Phase 7a).
5. **BIO-04: STUN-блок toggle** — Advanced Settings → Anti-DPI, выкл по умолчанию. Блокирует UDP 3478/5349. Предупреждение: сломает браузерные видеозвонки.
6. **KILL-04: macOS enforceRoutes toggle** — Advanced Settings → Безопасность (macOS only). Default: `enforceRoutes=true` (текущий). Toggle → `enforceRoutes=false` (мягкий kill switch).
7. **UX-06: Полный Advanced Settings экран** — реструктуризация в 4 именованных секции (DNS / Anti-DPI / Безопасность / Rules).

### НЕ в скоупе v0.10 (scope amendment)

- **BIO-01..04** (Face ID / Touch ID для UI блокировки) — deferred. Нет смысла для текущей friends-and-family аудитории.
- **ONDEMAND-01** (On-Demand rules UI — вариант «только в публичных Wi-Fi») — deferred. Текущего `NEOnDemandRuleConnect(.any)` достаточно.
- **NET-12** (liveness probe) — повторный carry-out, deferred Phase 11+.
- **Config editor / Network diagnostics** (упомянуты в UX-06 spec) — если есть в v2 prompt, deferred Phase 11+.

</domain>

<decisions>
## Implementation Decisions

### Area A — Scope amendment

- **D-01: BIO-01..04 → deferred.** Биометрия исключена из Phase 10. Нет подтверждённого use case для friends-and-family TestFlight. При возврате (v1.x) — отдельная фаза.
- **D-02: ONDEMAND-01 → deferred.** «Только в публичных Wi-Fi» on-demand вариант исключён. Проблема: нет надёжного способа определить «публичная ли сеть» без пользовательской конфигурации SSID-списка. Текущий `NEOnDemandRuleConnect(.any)` покрывает основной use case.

### Area B — CDN-фронтинг архитектура

- **D-03: FrontingProfile — отдельный слой, не часть TransportConfig.** _(Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235` recommendation.)_
  - CDN-фронтинг меняет `server`/`server_port`/`tls.server_name`/`Host` header — это dial target override, не семантика транспорта.
  - Если встроить в TransportConfig: получим дублирование `WebSocketCDNTransport`, `GrpcCDNTransport` и т.д. при 50+ транспортах. Неприемлемо.
  - Структура:
    ```swift
    struct FrontingProfile: Codable, Sendable {
        let provider: CDNProvider       // .cloudflare, .fastly, .custom
        let connectHost: String         // CDN IP или домен
        let connectPort: Int            // обычно 443
        let sniHost: String             // fronted hostname (для TLS)
        let httpHost: String            // Host/:authority header
        let mode: FrontingMode          // .domain, .ipPool, .remoteSigned
    }
    ```

- **D-04: CDN providers — `CDNProviderAdapter` protocol.** Масштабируемость: добавление Cloudflare/Fastly/Bunny/Custom CDN не меняет TransportRegistry. FrontingConfigApplier поверх TransportHandler меняет `server`, `tls.server_name`, `Host`.

- **D-05: Sing-box 1.13.11 CDN mapping.** Для WS: `transport.headers.Host = frontingHost`. Для HTTPUpgrade: `transport.host = frontingHost`. Для gRPC: `tls.server_name = frontingHost`. Поле `server` → CDN IP/domain. **НЕ применять** к Reality / TUIC / Hysteria2.

- **D-06: CDN IP fallback chain.** При блокировке IP в РФ — автоматически: domain mode → IP pool (разные ASN) → другой CDN provider → direct Reality/Vision profile → следующая нода из подписки. Failure score по `(provider, ip, networkType)` кэшируется в App Group JSON. Blocked IP → cooldown 6-24ч.

- **D-07: CDN toggle UX — глобальный в Advanced Settings.** Применяется ко всем серверам, у которых конфиг подписки содержит `frontingProfile`. Если у сервера нет CDN-данных — toggle игнорируется для него.

### Area C — Mux

- **D-08: Mux — двойной контроль (auto + global toggle).** Auto: если URI содержит `mux=true` или Clash YAML `smux: {enabled: true}` — Mux включается для этого сервера автоматически. Глобальный toggle в Advanced Settings → Anti-DPI: позволяет принудительно включить Mux для всех совместимых серверов.
- **D-09: Протокольный whitelist для Mux.** Включать Mux ТОЛЬКО для: VLESS+TLS (без Reality/Vision), Trojan, Shadowsocks-2022. Запрещено для: Reality, Vision (XTLS собственный механизм), TUIC, Hysteria2 (QUIC уже multiplexed). `SingBoxConfigLoader` проверяет протокол перед инъекцией `multiplex.*` в конфиг.
- **D-10: Mux тип — smux по умолчанию.** При включении: `multiplex.protocol = "smux"`, `multiplex.max_connections = 4`, `multiplex.padding = true` (это DPI-03 per-packet padding). На усмотрение planner'а — можно сделать picker smux/yamux/h2mux в отдельной итерации.

### Area D — Cert Pinning

- **D-11: URLSessionDelegate custom + SPKI SHA-256 pin.** _(Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235` recommendation.)_ Без сторонних библиотек. Пинируем публичный ключ (SPKI SHA-256), не сам сертификат — переживает перевыпуск Let's Encrypt на том же ключе.
  ```swift
  final class PinnedSessionDelegate: NSObject, URLSessionDelegate {
      private let pinStore: PinStore
      // URLSession(_:didReceive:completionHandler:) — SPKI matching
  }
  ```

- **D-12: Хранение пинов — bootstrap + remote Ed25519 manifest.** Hardcoded bootstrap pins (current + backup key) в коде. Для ротации без релиза: `subscription-pins.json` подписанный Ed25519, кэшируется в App Group (аналог rules.json). Manifest: `validFrom`, `validUntil`, `host`, `spkiSha256Pins`, `backupPins`, `version`.

- **D-13: Cert pinning scope — только subscription URL (SubscriptionURLFetcher).** Rules.json уже Ed25519-protected — pinning избыточен. PacketTunnel extension НЕ делает URLSession напрямую — pinning только в main app.

- **D-14: Cert pinning включён по умолчанию, toggle виден.** В Advanced Settings → Безопасность: `Toggle «Pinning подписок»` (on по умолчанию). Если пин сломался после смены сертификата — пользователь может временно отключить.

### Area E — Advanced Settings экран (UX-06)

- **D-15: Структура экрана Advanced Settings v0.10.**
  ```
  Form {
    // 1. MinAppVersionBanner (conditional, Phase 8)

    // Секция «DNS» (Phase 6, existing)
    //   AdBlock toggle
    //   Custom DNS field

    // Секция «Anti-DPI» (Phase 10, NEW)
    //   CDN-фронтинг toggle  [DPI-06]
    //   Mux toggle            [DPI-05]
    //   uTLS fingerprint picker [DPI-09]
    //   STUN-блок toggle      [BIO-04]

    // Секция «Безопасность» (Phase 10, NEW)
    //   Cert pinning toggle   [DPI-08]
    //   (macOS only) enforceRoutes toggle [KILL-04]

    // Секция «Rules» (Phase 8, existing)
    //   RulesViewerSection    [RULES-09]
    //   ForceUpdateRulesButton [RULES-10]
  }
  ```

- **D-16: STUN-блок — выкл по умолчанию, с предупреждением.** Footer: «Сломает видеозвонки в браузере (Google Meet, Zoom). Не влияет на нативные приложения.» Блокирует UDP 3478 + 5349 через sing-box `route.rules` reject.

- **D-17: macOS enforceRoutes toggle — macOS only, в секции Безопасность.** Default: on (текущий enforceRoutes=true). Footer: «Выкл = трафик идёт напрямую если VPN упал. Безопаснее держать включённым.» Только macOS (`#if os(macOS)`). iOS игнорируется (iOS 26 принудительно ставит includeAllNetworks).

### Claude's Discretion

- uTLS picker options: `random` (default) + `chrome` + `firefox` + `safari` + `ios` + `android` + `edge`. Planner выбирает финальный набор по sing-box 1.13.11 supported fingerprints.
- CDNProviderAdapter конкретные реализации: CloudflareAdapter + FastlyAdapter + CustomCDNAdapter. IP pool JSON schema — на усмотрение planner'а.
- Мux picker type (smux/yamux/h2mux) — в v0.10 smux default, picker откладывается на v1.x.
- Порядок секций внутри Anti-DPI и Безопасность — на усмотрение, выше D-15.
- pin manifest `validUntil` enforcement policy (hard reject vs soft warn) — на усмотрение, рекомендую hard reject.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & ROADMAP

- `.planning/REQUIREMENTS.md` §Anti-DPI (DPI-05..09) — детальный список требований с REQ-IDs
- `.planning/REQUIREMENTS.md` §UX-06 — Advanced screen spec
- `.planning/REQUIREMENTS.md` §BIO-04 — STUN block
- `.planning/REQUIREMENTS.md` §KILL-04 — macOS enforceRoutes
- `.planning/ROADMAP.md` Phase 10 entry — Success Criteria + Requirements mapping. **NB: BIO-01..04 + ONDEMAND-01 → deferred per D-01/D-02 этого CONTEXT.**

### Промт v2 (источник истины для Advanced Settings spec)

- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` §`<advanced_settings>` — авторитетный список всех настроек Advanced экрана, их поведение, default values.

### Существующий Advanced Settings код

- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift` — текущий экран (4 секции Phase 6+8). **Реструктурируется в D-15.**
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift` — ViewModel для Advanced Settings. Новые toggles добавляются как `@Published` properties.
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsStore.swift` — persistent store (паттерн для новых toggles: CDN, Mux, STUN, pinning, enforceRoutes).

### Транспорты и конфиг sing-box

- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBox/SingBoxConfigLoader.swift` — `expandConfigForTunnel(_:)` — точка инъекции Mux + CDN fronting overrides.
- `BBTB/Packages/AppFeatures/Sources/` (TransportRegistry) — паттерн для CDNProviderAdapter (protocol + register + lookup).
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/AppGroupContainer.swift` — App Group paths для CDN failure cache + cert pin manifest cache.

### Subscription URL fetch (cert pinning target)

- `BBTB/Packages/AppFeatures/Sources/` — `SubscriptionURLFetcher` — добавить `PinnedSessionDelegate` wrapper. **Только в main app.**

### Паттерн по аналогии (Phase 8)

- `.planning/phases/08-rules-engine-split-tunneling/08-CONTEXT.md` — паттерны Ed25519-подписанного manifest (D-05/D-07) применяются для cert pin manifest (D-12). Bootstrap resource в bundle + App Group cache + background refresh.
- `BBTB/Packages/RulesEngine/` — структура пакета для `FrontingEngine` пакета (если выносить CDN-фронтинг в отдельный SwiftPM модуль).

### Codex architectural review

- Codex thread `019e2b02-09fc-77b1-8acc-cc4f794c5235` — CDN-фронтинг: FrontingProfile layer + CDNProviderAdapter protocol + fallback chain + sing-box 1.13.11 mapping. Cert pinning: URLSessionDelegate + SPKI SHA-256 + remote Ed25519 pin manifest.

### Sing-box документация (verified by Codex)

- https://sing-box.sagernet.org/configuration/outbound/vless/ — VLESS outbound fields (server, tls, transport)
- https://sing-box.sagernet.org/configuration/shared/v2ray-transport/ — WebSocket/HTTPUpgrade/gRPC transport headers
- https://sing-box.sagernet.org/configuration/shared/tls/ — tls.server_name
- https://sing-box.sagernet.org/configuration/shared/multiplex/ — Mux (multiplex.protocol, max_connections, padding)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`AdvancedSettingsView.swift`** — текущая структура Form с 4 секциями. Phase 10 добавляет 2 новые именованные секции (Anti-DPI, Безопасность) и переименовывает существующие (DNS, Rules). Расширяется хвостом.
- **`AdvancedSettingsStore`** — паттерн для persistent toggles. Новые свойства: `cdnFrontingEnabled`, `muxEnabled`, `stunBlockEnabled`, `certPinningEnabled`, `enforceRoutesMacOS`. Аналогично существующим `adBlockEnabled`, `customDNS`.
- **`SingBoxConfigLoader.expandConfigForTunnel(_:)`** — единственная точка инъекции. D-09 Mux: добавить `multiplex` блок для совместимых протоколов. D-05 CDN: применить `FrontingProfile` overlay после transport expansion.
- **`AppGroupContainer`** — App Group paths. Добавить: `cdnFailureCacheURL` (JSON failure scores), `certPinManifestURL` (Ed25519-signed pins).
- **`RulesEngine` пакет** — структурный паттерн для `FrontingEngine` (если выносить в отдельный SwiftPM модуль): actor + protocol + bootstrap resource.
- **`SubscriptionURLFetcher`** — обернуть в `PinnedSessionDelegate`. Добавить `SubscriptionSessionFactory` (D-11).
- **Phase 8 MinAppVersionBanner + RulesViewerSection** — переиспользуются as-is в новом layout.

### Established Patterns

- **R1 invariant** (нет SOCKS5 на localhost) — CDN fronting не вводит новых SOCKS5 inbound. FrontingConfigApplier меняет только outbound dial target.
- **R10 invariant** (TUN inbound whitelist) — Mux outbound `urltest-auto` + `reject` action совместимы с существующим whitelist.
- **DEC-06d-01 cold-start defer** — CDN IP fetch и cert pin manifest fetch НЕ блокируют TunnelController startup. Bootstrap cache применяется synchronously из bundle/App Group.
- **DEC-06d-04 bounded concurrency** — CDN fallback chain: sequential, concurrency=1 (аналог rules.json mirrors). Cert pin fetch: аналогично.
- **NEVPNStatusDidChange XPC pitfall** (memory: `feedback_nevpn_xpc_mach_port.md`) — новые toggles (CDN, Mux) не делают XPC в observer callback.
- **Two-phase init** (memory: `feedback_failover_two_phase_init.md`) — если FrontingEngine actor нужен в TunnelController: late-binding setter.

### Integration Points

- `SingBoxConfigLoader.expandConfigForTunnel(_:)` → Mux injection (D-08/D-09) + CDN overlay (D-03/D-05).
- `SubscriptionURLFetcher` → `PinnedSessionDelegate` wrapper (D-11/D-13).
- `AdvancedSettingsView` → новые секции Anti-DPI + Безопасность (D-15).
- `SettingsViewModel` → новые `@Published` properties для toggles.
- `AppGroupContainer` → новые cache paths для CDN + pin manifest.
- Tuist `Project.swift` → новый SwiftPM пакет `FrontingEngine` (если CDN выносится в пакет, discretion).

</code_context>

<specifics>
## Specific Ideas

- **CDN-фронтинг как "невидимый failover"**: пользователь включил toggle в Advanced. Приложение пробует обычное соединение (быстрее). Если не удалось за N секунд — автоматически пробует CDN-вариант. Пользователь видит только что «VPN подключён».
- **Codex Architect recommendation** по CDN: FrontingProfile НЕ часть TransportConfig — это ключевое архитектурное решение для масштабируемости (50+ транспортов не дублируют CDN логику).
- **Cert pin manifest = аналог rules.json pipeline**: подписан тем же Ed25519 ключом. Если pin manifest недоступен — fallback на hardcoded bootstrap pins. Graceful degradation.
- **STUN block реализация**: sing-box `route.rules` с `protocol: stun` + `action: reject` (или `port: [3478, 5349]` + `network: udp` + reject). Проверить sing-box 1.13.11 поддержку STUN protocol matcher.
- **macOS enforceRoutes**: применяется в `TunnelSettings.applyNESettings(_:)` — уже есть setter. Toggle меняет значение перед `applyCurrentStateToCachedManager()`.

</specifics>

<deferred>
## Deferred Ideas

- **BIO-01..04 (Face ID / Touch ID)** — deferred. Нет use case для friends-and-family. Вернуть при наличии 3+ запросов от TestFlight пользователей.
- **ONDEMAND-01 («только в публичных Wi-Fi»)** — deferred. Нет надёжного способа определить публичность сети без SSID whitelist (слишком сложно для MVP). Может вернуться в v1.x с UI для manual SSID list.
- **Mux picker (smux/yamux/h2mux)** — smux по умолчанию достаточно. Picker откладывается до v1.x.
- **NET-12** (active liveness probe) — повторный carry-out, deferred Phase 11+.
- **Config editor / Network diagnostics** — упомянуты в UX-06 spec, deferred Phase 11+.
- **CDN IP pool remote sync** — в v0.10 CDN IP может быть статичным из bundle. Remote signed IP pool — v1.x если Cloudflare anycast начнёт блокироваться в РФ.

</deferred>

---

*Phase: 10-Advanced-settings-Security-polish*
*Context gathered: 2026-05-15*
