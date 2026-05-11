# Phase 2: Trojan + Import flow — Context

**Gathered:** 2026-05-11
**Status:** Ready for planning
**Workflow:** `/gsd-discuss-phase 2` (default mode, interactive)

---

<domain>
## Phase Boundary

Расширить v0.1 (singleton VLESS+Reality конфиг через буфер обмена + системный kill switch) до v0.2:

1. **Второй протокол — Trojan** в `ProtocolRegistry`, поддержка TCP+TLS и WebSocket+TLS транспорта.
2. **Универсальный парсер импорта** — клиент принимает ВСЕ три формата ссылок, которыми пользователь раздаёт конфигурации друзьям:
   - **Subscription URL** (HTTP GET → base64 / plain-text / JSON-ответ).
   - **Multi-line plain-text** список из нескольких `vless://` / `trojan://` URI разных серверов.
   - **JSON endpoint** (HTTP GET → готовый sing-box config).
3. **QR-код импорт** — камера + permissions iOS/macOS.
4. **Auto-fallback через sing-box `urltest` outbound** — один VPN-профиль с outbound-пулом, sing-box сам выбирает рабочий и переключает при HTTP-проба failure.
5. **Kill Switch toggle** в новой Settings page → раздел «Безопасность». Применяется при следующем connect.
6. **Множественные сервера в SwiftData** — массив `ServerConfig` (UI выбора сервера остаётся в Phase 3).
7. **Главный экран переписывается**: top bar с меню-иконкой слева и «+» справа; в idle — timer → status pill → power-кнопка → server-line; в empty — карточка «Нет конфигурации» с двумя кнопками.
8. **Settings page** — новый экран (новый AppFeatures/SettingsFeature package); на v0.2 содержит только «Безопасность» → Kill Switch toggle.

### НЕ в скоупе Phase 2

- Файл-пикер импорта (IMP-03) — переезжает в **Phase 11** (UX-01 onboarding) как угловая ссылка «У меня уже есть конфиг файл».
- Server-list экран, pull-to-refresh, multi-subscription, server search — остаётся в **Phase 3** (SRV-*, UX-04).
- Остальные разделы Settings (Подписки UI, Уведомления, Внешний вид, Помощь, О приложении, Расширенные с DNS / IPv6 / uTLS / xray-fallback / network diagnostics / config editor) — Phase 4 / 10 / 11.
- Финальный дизайн UI и анимации (UX-08, UX-09) — Phase 11.
- Onboarding flow (UX-01) — Phase 11.
- macOS R5 «Отключить enforceRoutes» toggle — Phase 10 (точка в `KillSwitch.platformShouldDisableEnforceRoutes()` уже зарезервирована).
- Биометрия, DNS-стратегия, IPv6, rules engine, deep links, telemetry, anti-DPI suite — позже по своим фазам.

</domain>

<decisions>
## Implementation Decisions

### Auto-fallback и архитектура импорта (PROTO-10)

- **D-01:** Auto-fallback живёт **внутри sing-box** через `urltest` outbound. В одном `configJSON` лежат: `vless-out` + `trojan-out` (+ далее по фазам больше outbound'ов) + `urltest` selector, и `route.final = urltest-out`. sing-box сам гоняет HTTP-пробы через каждый outbound и переключает на миллисекундах при failure. Это покрывает «молчаливый ТСПУ» (TLS-handshake passed, traffic mangled) через встроенные HTTP-пробы. **Один** NETunnelProviderManager, **один** VPN-профиль в системных настройках. Это совпадает с практикой Hiddify / NekoBox / Leadaxe-singbox-launcher.

- **D-02:** Phase 2 поддерживает **все три формата раздачи ссылок**:
  - `https://vpn.example.ru/sub/<token>` — subscription URL, клиент делает HTTP GET и парсит ответ (base64 → строки URI / plain-text → строки URI / JSON → sing-box outbound list).
  - Multi-line plain-text с несколькими URI (вставка в буфер обмена многострочного блока).
  - `https://1.2.3.4:port/json/...` — JSON endpoint, клиент делает HTTP GET и применяет ответ напрямую как sing-box config (проходит через `SingBoxConfigLoader.validate` для R1-safety).

- **D-03:** `Leadaxe/singbox-launcher` (https://github.com/Leadaxe/singbox-launcher/blob/main/docs/ParserConfig.md) используется как **спецификация форматов и edge cases**, не как dependency. Вендоринг невозможен: чужой проект на JavaScript / Node-стеке, файловая архитектура с маркерами, GPL-совместимая лицензия с риском конфликта с нашей AGPL-ядро+closed-GUI стратегией. Алгоритмы и edge cases портируются в Swift по нашей архитектуре.

- **D-04:** Universal parser в v0.2 распознаёт **все URI-схемы** (vless, trojan, ss, vmess, hy2, wireguard, ssh, socks5, naive+...) — но **handler'ы** в `ProtocolRegistry` для каждого протокола добавляются по фазам. Неподдерживаемые на текущей версии URI парсятся и сохраняются в SwiftData с флагом `isSupported = false`, в sing-box `urltest` не попадают (иначе sing-box упадёт на запуске). UI сообщает пользователю «X конфигов рабочих, Y будут включены в следующих версиях». Когда Phase 4 / 7 добавит handler — флаг снимается, сервер автоматически включается в `urltest` БЕЗ реимпорта.

- **D-05:** Trojan handler (PROTO-02) поддерживает **TCP+TLS и WebSocket+TLS** транспорт в v0.2 — потому что реальные конфигурации пользователя (`trojan://...?type=ws&path=...&sni=vpn.example.ru`) приходят на WebSocket. Это формально кусок TRANSP-03 (WebSocket), который ROADMAP относит к Phase 5 — переезжает сюда как минимум для Trojan. UI выбора транспорта (TRANSP-05) остаётся в Phase 5.

- **D-06:** SwiftData переходит от **singleton `ServerConfig`** (Phase 1: один `isActive=true`) к **массиву** `ServerConfig`'ов с per-pool метаданными (subscription source URL, импортированной datetime, isSupported флаг). UI Phase 2 показывает «активный» один сервер / pool — выбор какой сервер показывать и server-list-экран остаётся в Phase 3 (SRV-*). Server identity для дедупликации — `host + port + protocolID + sni` (Claude-default).

- **D-07:** При импорте, который содержит **subscription source URL** (вариант 1 в твоих ссылках), source URL сохраняется в SwiftData как `subscriptionURL` метаданная пула. Re-import того же URL на v0.2 — **replace pool** (полностью затирает старый пул и создаёт новый). Merge / multi-subscription / ask UX — Phase 3 (SRV-02). Background-refresh / pull-to-refresh — Phase 3.

### Trojan URI schema (Claude-defaults)

- **D-08:** Парсер Trojan URI принимает:
  - **Обязательные**: `password` (userinfo часть), `host`, `port`, `security=tls` (иначе reject — R1 принцип, никаких clear-text trojan).
  - **Transport**: `type=tcp` (default) или `type=ws` (с дополнительными `path` и опциональным `host` для WebSocket Host header — fallback на `sni` если пусто).
  - **TLS**: `sni` (обязательно для DPI-resistance — fallback на `host` если пусто), `fp` / `fingerprint` (uTLS — default `chrome` если пусто), `alpn` (опционально — default `h2,http/1.1`).
  - **R1 принцип**: `allowInsecure=1` **игнорируется** — TLS-валидация всегда строго через certificate chain. Параметр в URI не приводит к ошибке, просто игнорируется.
  - **Remark**: из URL fragment (например `#Латвия — Trojan` → `name = "Латвия — Trojan"`).

### UI и навигация

- **D-09:** Главный экран — минималистичный layout (приближен к Phase 11 target из `wiki/ux-specification.md`):
  ```
  [≡ menu]                                     [+ import]      ← top bar
  
  (если есть конфиг — содержимое ниже видно;
   если нет — вместо всего этого центральная карточка empty-state)
  
              Время подключения
                00:00:00
              [pill: Отключено]
  
                  ┌─────┐
                  │  ⏻  │
                  └─────┘
  
            Сервер: Авто  (или имя)
  ```
  - **TabBar нет**. **Поисковой иконки нет**.
  - Иконка меню в **левом верхнем углу** top bar → NavigationStack push на Settings page. Claude-default SF Symbol — `line.3.horizontal` (гамбургер); финал в Phase 11.
  - Иконка «+» в **правом верхнем углу** — `SwiftUI Menu` с двумя пунктами: «Сканировать QR» и «Добавить из буфера». IMP-03 (Из файла) в этом меню **нет** — отложено в Phase 11.
  - Pill статуса **без disclosure arrow**.
  - Server-line tap **disabled на v0.2** (server-list UI — Phase 3). Стрелка `›` скрыта на v0.2.

- **D-10:** Empty-state — **центрированная карточка** со следующим содержимым:
  ```
  ┌──────────────────────────────────┐
  │       📦 (или коробочная икон)   │
  │       Нет конфигурации           │
  │                                  │
  │     Добавьте первую конфигурацию │
  │       с помощью кнопок ниже      │
  │                                  │
  │   ┌──────────────────────────┐   │
  │   │   Добавить из буфера     │   │  ← primary (filled)
  │   └──────────────────────────┘   │
  │   ┌──────────────────────────┐   │
  │   │   Отсканировать QR-код   │   │  ← secondary (outlined)
  │   └──────────────────────────┘   │
  └──────────────────────────────────┘
  ```
  - Текст копируется **дословно** из v2raytune-референса. Финальная формулировка / тон под BBTB-бренд — Phase 11.
  - В empty-state СКРЫТЫ: timer, power-кнопка, status pill, server-line.
  - Иконка «+» в top bar **остаётся видимой** в empty-state — она дублирует кнопки на карточке и становится основным entry point после первого импорта.

- **D-11:** Server-line content (когда конфиг есть):
  - **Один outbound** в пуле → имя из URI `remark` / fragment (например `Латвия — VLESS`).
  - **Несколько outbound'ов** в `urltest` пуле → «Авто».
  - Tap по строке disabled на v0.2 (полный server-list — Phase 3).

### Kill Switch toggle (KILL-03)

- **D-12:** Settings page на v0.2 содержит **только раздел «Безопасность»** с одним toggle «Kill Switch». Footer-текст под toggle: «Блокирует весь интернет при разрыве VPN — защищает от случайной утечки трафика» (Claude-default — финал Phase 11). Toggle включён по дефолту (наследуется от KILL-01).

- **D-13:** Toggle переключается **без confirmation alert** — простой `SwiftUI Toggle`. При включении или выключении нет всплывающего окна.

- **D-14:** Изменение toggle **применяется на следующем connect**. State хранится в `UserDefaults` (key `app.bbtb.killSwitchEnabled`) — простой ключ, не SwiftData (не привязан к конкретному `ServerConfig`). `ConfigImporter.provisionTunnelProfile` читает флаг при создании / обновлении `NETunnelProviderProtocol` и передаёт его в `KillSwitch.apply(to:enabled:)`. Если туннель **активен** в момент toggle — в top bar показывается баннер «Переподключитесь для применения изменений» (не делаем принудительный reconnect — он создал бы 4-8 секундную паузу, ломая stream / звонки).

- **D-15:** `KillSwitch.apply()` параметризуется флагом `enabled: Bool`. Сигнатура: `public static func apply(to proto: NETunnelProviderProtocol, enabled: Bool)`. Когда `enabled = false`: `includeAllNetworks = false` и `enforceRoutes = false`. Остальные настройки (`excludeLocalNetworks = false`, `disconnectOnSleep = false`) остаются без изменения. R5 macOS-hook сохраняется (`platformShouldDisableEnforceRoutes()` — Phase 10 заполнит).

### Claude's Discretion

- **Иконка меню top bar left:** `line.3.horizontal` (гамбургер) — пользователь явно не задал.
- **Иконка карточки empty-state:** `tray` или `shippingbox` SF Symbol — финал в Phase 11.
- **HTTP-probe URL для `urltest`:** Рекомендую `https://cp.cloudflare.com/generate_204` (НЕ Google `gstatic.com` — может стать менее надёжным в РФ; и `cloudflare` совпадает с нашим DNS-bootstrap-провайдером). Окончательное решение — planner с research, с учётом инфры на `vpn.vergevsky.ru` (можешь захостить свой generate_204 на VPS если хочешь полную независимость от внешних доменов).
- **`urltest` interval:** sing-box default `1m` (полная проба каждую минуту в фоне). Tolerance `50ms`. idle_timeout `30m`. Можно тюнить в research.
- **Subscription parser fallback chain:** сначала detect — если response body начинается с `{` → JSON; иначе base64-decode попытка → если декодировался ASCII-printable текст с URI → split по `\n`; иначе plain-text split по `\n`.
- **Subscription HTTP request:** `User-Agent: BBTB/0.2 (iOS / macOS)` — стандарт для subscription-protocol совместимости. TLS-certificate-pinning для subscription URL **не делаем** на v0.2 (DPI-08 — Phase 7).
- **macOS Settings:** на macOS использовать `Settings { ... }` Scene из SwiftUI 4+ (Cmd+, открытие). На iOS — NavigationStack push из меню-иконки.
- **Camera permissions copy:** `NSCameraUsageDescription` — «BBTB использует камеру для сканирования QR-кодов с конфигурациями VPN-серверов».
- **Trojan template:** новый файл `Resources/SingBoxConfigTemplate.trojan.json` с placeholder'ами `${TROJAN_PASSWORD}`, `${SERVER_HOST}`, `${SERVER_PORT}`, `${SNI_DOMAIN}`, `${UTLS_FINGERPRINT}`, `${WS_PATH}`, `${WS_HOST}`, `${TRANSPORT_TYPE}`. Conditional WebSocket-секция включается только при `type=ws`.
- **ConfigBuilder refactor:** placeholder-substitution из Phase 1 (`VLESSReality/ConfigBuilder`) расширяется до **универсального builder'а**, либо общий `OutboundBuilder` строит per-protocol outbound, а потом `PoolBuilder` собирает их в один `urltest`-config. Финальная структура — за planner'ом с research; пометить как «D-02 follow-up из Phase 1 CONTEXT» (там было прямо сказано «Phase 2 улучшит через Codable model»).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these перед work.**

### Источник истины по релизу v0.2 — авторитет

- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` секция `<release_roadmap>` v0.2 (строки ~796-806) — точный состав фичи фазы и DoD
- `prompts/v2 <swift_package_layout>` (строки 85-142) — модульная структура: Trojan/, ConfigParser/, SettingsFeature/, ServerListFeature/, Transports/
- `prompts/v2 <protocols>` (строки ~188) — Trojan-определение
- `prompts/v2 <tech_stack>` (строки 160-173) — sing-box через libbox.xcframework, swift-crypto, OSLog

### Парсер и формат конфигов

- `wiki/config-parser-singbox-launcher.md` — спецификация Leadaxe ParserConfig: что копировать (URI-схемы, edge cases), что не копировать (CLI-маркеры, file-output)
- `wiki/protocols-overview.md` секция «Auto-fallback» (строки 60-62) — v0.2 поведение
- `wiki/protocols-overview.md` секция «Trojan» (таблица протоколов, v0.2)
- `wiki/architecture.md` секция «Packages/» — ConfigParser scope, ProtocolRegistry mechanism

### UI и UX

- `wiki/ux-specification.md` секция «Главный экран» (строки 37-59) — target UX Phase 11 (timer + center button + bottom server-bar)
- `wiki/ux-specification.md` секция «Расширенные настройки» (строки 83-99) — full Settings scope, что переезжает на v0.10/v0.11

### Security и kill switch (Phase 1 carry-forward — НЕ нарушать)

- `wiki/security-gaps.md` R1 + `prompts/v2 <security>` секция — SOCKS5 / gRPC / inbound-whitelist принципы; Trojan outbound + WebSocket transport не нарушают R1 inbound-whitelist
- `wiki/security-gaps.md` R6 — `P2P=false` на туннельном интерфейсе остаётся включённым
- `wiki/security-gaps.md` R10 — TUN inbound runtime expansion для PacketTunnelKit (наследуется без изменений)
- `wiki/kill-switch.md` — KILL-01 / KILL-02 семантика; KILL-03 toggle добавляется поверх как параметризация
- `wiki/security-gaps.md` R11 — Phase 1 security audit 37/37; Phase 2 не должна откатывать ни одно из закрытых решений

### Требования и контракты

- `.planning/REQUIREMENTS.md` REQ-IDs **в Phase 2 scope**: PROTO-02, PROTO-10, IMP-02, KILL-03. **Foundation расширение из других фаз**: IMP-04 (parser part), IMP-05 (Outline / Clash YAML — частично), TRANSP-03 (WebSocket для Trojan), SRV-01..03 (SwiftData массив + isSupported флаг)
- `.planning/REQUIREMENTS.md` REQ-ID **отложен в Phase 11**: IMP-03 (file picker)
- `.planning/ROADMAP.md` Phase 2 — оригинал; этот CONTEXT.md расширяет scope по согласованию с пользователем

### Phase 1 carry-forwards

- `.planning/phases/01-foundation/01-CONTEXT.md` — все carry-forwards (ConfigImporter pipeline, KillSwitch.apply singleton, SingBoxConfigLoader R1 whitelist, ConfigBuilder placeholder model)
- `.planning/phases/01-foundation/01-PLAN.md` (если будет нужен — старый план для проверки нерегрессий)
- `.planning/phases/01-foundation/01-SECURITY.md` — 37/37 закрытых threats; Phase 2 не должна re-open

### Конкретные исходники, которые будут затронуты

- `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift` — расширяется или становится фасадом + добавляются `TrojanURIParser`, `SubscriptionURLFetcher`, `JSONEndpointFetcher`, унифицированный `UniversalImportParser`
- `BBTB/Packages/ConfigParser/Tests/ConfigParserTests/` — расширяется тестами на все 3 формата + на каждую URI-схему (vless, trojan, ss-stub, vmess-stub, hy2-stub, wg-stub)
- `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift` — рефакторится в общий `OutboundBuilder` (или сохраняется и появляется параллельный `TrojanConfigBuilder` + общий `PoolBuilder`)
- `BBTB/Packages/Protocols/` — новый под-package `Trojan/` (per `<swift_package_layout>` структура)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/SingBoxConfigLoader.swift` — допускает Trojan outbound + WS transport (R1 inbound whitelist остаётся `{tun, direct}`, outbound types не whitelist'ятся — оба типа OK)
- `BBTB/Packages/PacketTunnelKit/Sources/PacketTunnelKit/Resources/` — новый `SingBoxConfigTemplate.trojan.json` + опционально `SingBoxConfigTemplate.pool.json` для urltest-обёртки
- `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` — без изменений, регистрация Trojan handler в `BBTB_iOSApp.init` / `BBTB_macOSApp.init`
- `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift` — параметризация `apply(to:enabled:)` (signature change!)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenView.swift` — переписывается (top bar + новый layout + empty-state карточка)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` + `ConnectionTimer.swift` + `StatusBadge.swift` — пересборка под новый layout (timer всегда сверху, pill под кнопкой, статичный badge удаляется из header)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ImportFromClipboardButton.swift` — удаляется (замена на карточку)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — переписывается под массив `ServerConfig`'ов + universal parser + kill switch флаг чтение
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift` — переписывается под массив + новый state machine (.empty / .idle / .connecting / .connected / .error остаются, но содержимое state меняется)
- `BBTB/Packages/AppFeatures/Sources/` — новый sub-module `SettingsFeature/` (SettingsView, SettingsViewModel)
- `BBTB/Packages/AppFeatures/Sources/MenuBarFeature/MenuBarContent.swift` — обновление под Settings link на macOS
- `BBTB/Packages/VPNCore/Sources/VPNCore/ServerConfig.swift` — добавление полей `isSupported: Bool`, `subscriptionURL: String?`, `outboundJSON: String` (raw outbound для урлтеста)
- `BBTB/Packages/Localization/Sources/Localization/L10n.swift` + `Localizable.xcstrings` — расширяется новыми keys: empty-state, menu items, server-line labels, kill switch toggle, settings page title
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` + `BBTB/App/macOSApp/BBTB_macOSApp.swift` — регистрация Trojan handler, NavigationStack обёртка

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets

- **`SingBoxConfigLoader.validate(json:)`** в PacketTunnelKit — R1 inbound-whitelist уже принимает Trojan outbound и WebSocket transport. Trojan outbound type `"trojan"` не нарушает whitelist `{tun, direct}` (он outbound, не inbound). **Без изменений.**
- **`SingBoxConfigLoader.expandConfigForTunnel(json:)`** — TUN inbound injection + DNS-hijack 1.13 migration. Работает identично для Trojan и multi-outbound urltest-конфигов. **Без изменений.**
- **`KillSwitch.apply(to:)`** — единственная точка установки kill switch флагов. Параметризуется в Phase 2 как `apply(to:enabled:)`. R4 default остаётся, R5 macOS-hook остаётся.
- **`KeychainStore.save(secret:tag:)`** + `kSecAttrAccessibleWhenUnlocked` — pattern для секретов остаётся без изменений. Используется для `password` Trojan'а так же как для `uuid`/`publicKey` VLESS Reality.
- **`ConfigImporter.provisionTunnelProfile`** — pattern «save → loadFromPreferences после save» из Phase 1 RESEARCH §1 сохраняется обязательно.
- **`VLESSURIParser.parse`** + `ConfigBuilder.buildSingBoxJSON` — pattern «URI → ParsedX → templateSubstitution → JSON → validate» переносится на Trojan (`TrojanURIParser.parse` + `TrojanConfigBuilder.buildSingBoxJSON`).
- **`ConnectionState` / `MainScreenViewModel`** — state machine .empty / .idle / .connecting / .connected / .error остаётся; меняется только рендеринг (см. D-09, D-10) и payload state'ов.
- **`L10n.swift` + `Localizable.xcstrings`** — pattern «one key per UI string, ru+en сразу» из Phase 1 продолжается.
- **`SwiftDataContainer.makeShared()`** — общий контейнер уже настроен, в Phase 2 расширяется новыми полями `ServerConfig`.

### Established Patterns

- **Module separation:** один Package per протокол в `Packages/Protocols/<Name>/` (Phase 1 VLESSReality — рабочий пример; Phase 2 добавляет Trojan по тому же шаблону).
- **Template-substitution для sing-box config:** `Resources/SingBoxConfigTemplate.<protocol>.json` с `${PLACEHOLDER}` плейсхолдерами + `loadXxxTemplate()` метод в `SingBoxConfigLoader` (или в per-protocol Config Builder'е).
- **R1 default-deny whitelist** для inbound types — Phase 2 НЕ расширяет whitelist (только outbound types меняются, что R1 не контролирует).
- **R6 P2P=false** — TunnelSettings.makeR6Safe вызывается без изменений.
- **Phase 1 W5 device-debug learnings (commit 9aa3e93):** `${VLESS_FLOW}` placeholder в template + parser default `""` — паттерн «URI → field → template» extracting защищает от server-client mismatch. **Trojan template должен следовать тому же принципу:** все поля параметризуются, никаких hard-coded значений в template.

### Integration Points

- **Trojan handler в ProtocolRegistry:** `ProtocolRegistry.shared.register(TrojanHandler.self)` в `BBTB_iOSApp.init` и `BBTB_macOSApp.init` — после `VLESSRealityHandler.self`.
- **Universal parser feed point:** `ConfigImporter.importFromPasteboard()` (Phase 1 path) расширяется в `ConfigImporter.import(rawInput:)` — `rawInput` сразу классифицируется (URI / URL / JSON), затем routed в подпарсер.
- **Subscription URL fetch:** новый `SubscriptionURLFetcher` использует `URLSession.shared.data(from:)` с User-Agent header. HTTPS only — `http://` reject (R1-spirit: subscription URL не должен ходить в clear-text).
- **JSON endpoint fetch:** аналогично `SubscriptionURLFetcher`, но `Accept: application/json` header + parsing через `SingBoxConfigLoader.validate` сразу.
- **SettingsFeature ↔ KillSwitch flag:** `UserDefaults.standard.bool(forKey: "app.bbtb.killSwitchEnabled")` — простой ключ. `SettingsView` использует `@AppStorage`. `ConfigImporter.provisionTunnelProfile` читает через `UserDefaults.standard.object(forKey: ...) as? Bool ?? true` (default true).
- **Top bar баннер «Переподключитесь»:** через `MainScreenViewModel` published flag `needsReconnectForKillSwitch`, который выставляется в true когда `UserDefaults` killSwitchEnabled flag меняется И туннель активен. Сбрасывается на следующем disconnect / connect.
- **NavigationStack iOS:** `MainScreenView` оборачивается в `NavigationStack` в `BBTB_iOSApp.body`. Menu icon → `NavigationLink(destination: SettingsView())`.
- **macOS Settings:** через SwiftUI `Settings { SettingsView() }` Scene в `BBTB_macOSApp.body` — открывается через Cmd+,. Дублирующий entry-point — menu icon в основном окне через `NavigationStack` тоже.

</code_context>

<specifics>
## Specific Ideas

### Реальные ссылки пользователя (тест-кейсы)

Эти конкретные ссылки **должны парситься без ошибок** на v0.2 (с graceful skip для неподдержанных протоколов):

**Вариант 1 — Subscription URL:**
```
https://vpn.vergevsky.ru/sub/VGVzdCwxNzc4NTIzNzExdXbmcsiR_Y
```

**Вариант 2 — Multi-line plain-text (4 VLESS+Reality + 2 Trojan-WS-TLS, 6 разных серверов):**
```
vless://fd2d4820-52c8-4e81-a104-d5b1c5601cd6@93.77.187.150:8443?security=reality&type=tcp&flow=xtls-rprx-vision&sni=s3.yandexcloud.net&fp=chrome&pbk=8dP_z0Cps...&sid=d7cae13f...#WL Латвия
vless://fd2d4820-52c8-4e81-a104-d5b1c5601cd6@93.77.187.150:443?security=reality&...#WL Финляндия
vless://fd2d4820-52c8-4e81-a104-d5b1c5601cd6@185.237.218.81:2054?security=reality&...#Латвия — VLESS
vless://fd2d4820-52c8-4e81-a104-d5b1c5601cd6@144.31.27.48:2054?security=reality&...#Финляндия — VLESS
trojan://LN8x95baqueFriHJLnFuDQ@185.237.218.81:2087?security=tls&type=ws&path=/ba0ca9ffa1d4&sni=vpn.vergevsky.ru&fp=chrome#Латвия — Trojan
trojan://LN8x95baqueFriHJLnFuDQ@144.31.27.48:2087?security=tls&type=ws&path=/ba0ca9ffa1d4&sni=vpn.vergevsky.ru&fp=chrome#Финляндия — Trojan
```

**Вариант 3 — JSON endpoint:**
```
https://185.237.218.81:24527/json/v3ry-53cur3-p4th-98231/g8ogx6367znwvy95
```
(Внутри предполагается готовый sing-box config с urltest-обёрткой; R1 validate всё равно применяется.)

### Референс UI

- v2raytune iOS-приложение (скриншоты `~/Downloads/IMG_0496.PNG` и `~/Downloads/Снимок экрана 2026-05-11 в 23.22.05.png`) — empty-state карточка и меню «+».

### Конкретные дефолты

- **VPN-профиль display name** в iOS / macOS Settings → VPN: `BBTB` (без суффикса `— Primary`/`— Fallback`, потому что fallback живёт внутри одного профиля через `urltest`).
- **Subscription User-Agent**: `BBTB/0.2`.

</specifics>

<deferred>
## Deferred Ideas

Идеи, которые всплыли но НЕ в Phase 2:

- **IMP-03 (file picker)** — переезжает в Phase 11 как угловая ссылка «У меня уже есть конфиг файл» (per `wiki/ux-specification.md`).
- **Server-list UI** (UX-04, SRV-01..03 полный функционал, pull-to-refresh, секции по подпискам) — Phase 3 как было.
- **Множественные subscription URL** (SRV-02) — Phase 3.
- **Pull-to-refresh / background-fetch subscription** — Phase 3 (паттерн RULES-04 даст scheduled fetch).
- **Финальный onboarding** (UX-01) — Phase 11.
- **Финальный дизайн Settings со всеми разделами** (Подписки UI, Уведомления, Внешний вид, Помощь, О приложении, Расширенные) — Phase 4 / 10 / 11.
- **Анимации переходов главной кнопки** (UX-08) — Phase 11.
- **macOS «Отключить enforceRoutes»** toggle (R5, KILL-04) — Phase 10, hook уже зарезервирован в `KillSwitch.platformShouldDisableEnforceRoutes()`.
- **Auto-reconnect при изменении kill switch toggle** — на v0.2 отказались (показываем баннер вместо принудительного reconnect; не ломаем активные stream/zoom-звонки).
- **Certificate pinning для subscription URL** (DPI-08) — Phase 7.
- **TLS-fragmentation, packet padding, random delay, mux** — Phase 7 (anti-DPI suite).
- **Custom HTTP-probe URL для urltest** (свой `generate_204` на VPS пользователя) — опционально на v0.2, окончательное решение оставлено planner+research.
- **xray-core fallback** для специфичных случаев Reality (CORE-09) — Phase 4+.
- **«Manual server pick» в server-line tap** — Phase 3 (UX-04).
- **Apple Distribution credentials** (DIST-02 follow-up из Phase 1) — Phase 12 prerequisite (см. `project_phase12_distribution_creds_prerequisite` memory).
- **Empty-state UX issue из Phase 11 follow-up** (после удаления VPN profile из iOS Settings, MainScreen остаётся в `error` state без recovery) — Phase 11, REQ UX-02 + CORE-07.
- **SocksProbe UX уточнение** (PID attribution для отличия BBTB-процесса от других) — Phase 11 follow-up.

</deferred>

---

*Phase: 2-Trojan-import-flow*
*Context gathered: 2026-05-11*
*Workflow: `/gsd-discuss-phase 2` (default mode, interactive)*
*Decisions captured: 15 across 4 areas (Auto-fallback / Import foundation, UI entry, KILL-03 + Settings stub, Trojan URI schema)*
*Downstream: `gsd-phase-researcher`, `gsd-planner`*
