# Requirements: BBTB

**Defined:** 2026-05-11
**Core Value:** В один тап получить VPN-соединение, обходящее ТСПУ, без необходимости разбираться в протоколах.
**Source of truth:** `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md`

## v1 Requirements

Требования для публичного TestFlight (v1.0). Каждое маппится в `.planning/ROADMAP.md` на конкретную фазу.

### Core architecture (CORE)

- [x] **CORE-01**: Проект организован как SwiftPM monorepo с модулями для каждого протокола, транспорта, подсистемы
- [x] **CORE-02**: `ProtocolRegistry` регистрирует протоколы через `protocol VPNProtocolHandler`; убрать протокол = удалить registration, остальное компилируется
- [ ] **CORE-03**: `TransportRegistry` аналогично для транспортов через `protocol TransportHandler`
- [x] **CORE-04**: `PacketTunnelExtension` таргеты для iOS и macOS на базе `NEPacketTunnelProvider`
- [ ] **CORE-05**: `AppProxyExtension` таргет на macOS (для per-app routing, активируется в v0.8)
- [x] **CORE-06**: Entitlements выписаны: `networking.networkextension` (packet-tunnel + app-proxy), `networking.vpn.api`, `app-sandbox`, `network.client/server`
- [x] **CORE-07**: Конфигурация туннеля проксируется через App Group между main app и extension
- [x] **CORE-08**: Sing-box интегрирован через `libbox.xcframework` (gomobile-биндинги)
- [ ] **CORE-09**: xray-core доступен как опциональный fallback xcframework для специфичных случаев Reality
- [x] **CORE-10**: SwiftData для конфигов/серверов/истории, Keychain (`kSecAttrAccessibleWhenUnlocked`) для секретов

### Security review до v0.1 (SEC)

- [x] **SEC-01** (R1): Конфиг sing-box, передаваемый в `libbox.xcframework`, **не запускает** локальный SOCKS5 на 127.0.0.1 ни на iOS, ни на macOS. Секции `inbounds` не содержат `type: socks` или `mixed`.
- [x] **SEC-02** (R1): gRPC API sing-box отключён в production-сборке на обеих платформах
- [x] **SEC-03** (R1): Тест-кейс на iOS и macOS — второе приложение не находит отвечающих портов на `127.0.0.1:N` для стандартных портов SOCKS из методички РКН (`1080, 9000, 5555, 16000-16100`)
- [x] **SEC-04** (R6): При настройке `NEPacketTunnelNetworkSettings` параметр `P2P=true` не выставляется на интерфейсе
- [x] **SEC-05**: Конфиги сохраняются в Keychain с access flag `kSecAttrAccessibleWhenUnlocked`
- [x] **SEC-06**: Перед применением конфига выполняется валидация структуры, чтобы не упасть на malformed input
- [ ] **SEC-07**: Code signing + notarization для macOS .app

### Kill switch (KILL)

- [x] **KILL-01**: Kill switch системный (`NEVPNProtocol.includeAllNetworks=true` + `enforceRoutes=true`), включён по дефолту
- [x] **KILL-02**: При падении туннеля ОС блокирует весь сетевой трафик до восстановления или ручного отключения VPN
- [x] **KILL-03**: Тоггл для отключения kill switch в разделе «Расширенные» (с v0.2) — Phase 2 UAT T7-T9 PASS 2026-05-12
- [ ] **KILL-04** (R5): На macOS — отдельный тоггл «Отключить принудительную маршрутизацию» (`enforceRoutes=false`) в Расширенных (с v0.10)

### Протоколы (PROTO)

- [x] **PROTO-01**: VLESS + XTLS Vision + Reality — главный anti-ТСПУ протокол. Конфиг включает `serverName`, `publicKey`, `shortId`
- [x] **PROTO-02**: Trojan — TLS-based, выглядит как обычный HTTPS — Phase 2 UAT T5 PASS 2026-05-12 (TCP+TLS и WS+TLS)
- [ ] **PROTO-03**: VLESS + XTLS-Vision (без Reality) — для серверов без поддержки Reality
- [ ] **PROTO-04**: Shadowsocks-2022 (SS-2022, AEAD-2022) — AES-128-GCM
- [ ] **PROTO-05**: Hysteria2 — UDP-based, QUIC-обёртка
- [ ] **PROTO-06**: WireGuard через WireGuardKit от ZX2C4
- [ ] **PROTO-07**: AmneziaWG — модифицированный WireGuard с anti-DPI обфускацией
- [ ] **PROTO-08**: TUIC v5 — QUIC-based, альтернатива Hysteria2
- [ ] **PROTO-09**: OpenVPN over TLS — legacy совместимость
- [x] **PROTO-10**: Auto-fallback — если основной протокол не подключился за N секунд, автоматически пробуется второй из конфига без вмешательства пользователя — Phase 2 UAT T6 PASS 2026-05-12 (via sing-box urltest outbound, interval=1m)

### Транспорты (TRANSP)

- [ ] **TRANSP-01**: XHTTP — новый рекомендуемый, маскировка под HTTP/2 multiplexed traffic
- [ ] **TRANSP-02**: gRPC — HTTP/2 RPC
- [ ] **TRANSP-03**: WebSocket — legacy совместимость — **Phase 2 partial** (WebSocket transport для Trojan), Phase 5 finish (расширить за пределы Trojan + UI выбор транспорта)
- [ ] **TRANSP-04**: HTTPUpgrade — минималистичный, легче gRPC
- [ ] **TRANSP-05**: В Расширенных можно вручную выбрать транспорт для дебага

### Anti-DPI техники (DPI)

- [ ] **DPI-01**: uTLS fingerprint mimicking — клиент представляется как Chrome/Firefox/Safari, по умолчанию randomized
- [ ] **DPI-02**: TLS ClientHello фрагментация — первый пакет TLS разбивается на несколько TCP-пакетов чтобы DPI не успел распарсить SNI
- [ ] **DPI-03**: Packet padding — случайные байты к пакетам, статистические характеристики не палят VPN-трафик
- [ ] **DPI-04**: Random TCP/UDP delay — рандомные задержки между пакетами
- [ ] **DPI-05**: Mux — мультиплексирование логических соединений в одно TCP
- [ ] **DPI-06**: CDN-фронтинг (Cloudflare/Fastly) как fallback transport
- [ ] **DPI-07**: Поддержка разных портов: 443 приоритет, плюс 80, 8443, 2096 и др.
- [ ] **DPI-08**: Certificate pinning для соединения с панелью подписок и rules.json
- [ ] **DPI-09**: Выбор uTLS fingerprint в Расширенных

### Import flow (IMP)

- [x] **IMP-01**: Импорт через буфер обмена — проверяет на `vless://`/`ss://`/`trojan://` и subscription URL
- [x] **IMP-02**: Импорт через QR-код — открывает камеру с permission, при сканировании импортирует — Phase 2 UAT T4 PASS 2026-05-12
- [ ] **IMP-03**: Импорт через файл (`.json`/`.yaml`) — **переехал в Phase 11** (был в Phase 2; перенесён в `/gsd-discuss-phase 2` 2026-05-11 — пользователь хочет сначала закрыть QR + universal-parser path, file-picker как угловая ссылка в финальном onboarding-экране)
- [ ] **IMP-04**: ConfigParser поддерживает все популярные URI-форматы (vless://, ss://, trojan://, hy2://, vmess://, wireguard://) и subscription URL формата v2ray — **Phase 2 foundation** (universal URI parser + subscription URL fetch + JSON endpoint fetch), Phase 4 finish (handler'ы для всех протоколов)
- [ ] **IMP-05**: ConfigParser поддерживает Outline access keys и Clash YAML — **Phase 2 foundation** (все URI-схемы парсятся, неподдерживаемые сохраняются с `isSupported=false`), Phase 4 finish (Outline + Clash YAML format)

### UX экраны (UX)

- [ ] **UX-01**: Onboarding — один экран с тремя опциями импорта (буфер, QR, файл); никаких слайдов «что такое VPN»
- [x] **UX-02**: Main screen — top bar + connection timer + большая центральная кнопка (idle/connecting/connected/error состояния) + статус + bottom bar c выбором сервера
- [x] **UX-03**: Connection timer — формат `HH:MM:SS`, отсчёт от установки соединения, виден всегда
- [x] **UX-04**: Server list screen — кнопка «Авто» + поиск + список с флагами стран и latency + pull-to-refresh + секции по подпискам — Phase 3 UAT T1-T5 PASS 2026-05-12
- [ ] **UX-05**: Settings screen — Подписки, Уведомления, Внешний вид, Безопасность (Face ID), Помощь, О приложении, Расширенные
- [ ] **UX-06**: Advanced screen — ручной выбор протокола, DNS-провайдер, тоггл STUN-блок, тоггл аналитики, IPv6 режим, uTLS fingerprint, просмотр rules.json read-only, кнопка обновить правила, тоггл xray-core fallback, **macOS only** тоггл `enforceRoutes`, конфиг-эдитор, network diagnostics
- [x] **UX-07**: Menu Bar app на macOS — минимальный, через `NSStatusItem`
- [ ] **UX-08**: Анимации переходов состояний главной кнопки (финал в v0.11)
- [ ] **UX-09**: Финальный дизайн всех экранов соответствует Figma (v0.11)

### Server management (SRV)

- [x] **SRV-01**: Auto-select сервера по пингу + потерям пакетов — **Phase 2 foundation** (sing-box `urltest` outbound выполняет HTTP-пробу, выбирает рабочий outbound из пула; SwiftData массив `ServerConfig` с `isSupported` флагом), Phase 3 finish (server-list UI, ping monitor + потери, smart-метрика) — Phase 3 UAT T3-T5 PASS 2026-05-12
- [x] **SRV-02**: Поддержка нескольких subscription URL — секции в списке серверов — **Phase 2 foundation** (одна `subscriptionURL` метаданная на pool, re-import = replace), Phase 3 finish (несколько источников + секции) — Phase 3 UAT T1-T2 PASS 2026-05-12
- [x] **SRV-03**: Pull-to-refresh перепинговывает все серверы — Phase 3 UAT T3 PASS 2026-05-12

### Network resilience (NET)

- [ ] **NET-01**: DNS-over-HTTPS (DoH) внутри туннеля к whitelisted провайдерам (Cloudflare default, NextDNS, AdGuard, Quad9)
- [ ] **NET-02**: Опция «свой DNS» в Расширенных
- [ ] **NET-03**: Опция «AdBlock через DNS» — переключение на AdGuard/NextDNS с фильтрами
- [ ] **NET-04**: Encrypted bootstrap DNS до подключения (через `1.1.1.1` или `8.8.8.8`)
- [ ] **NET-05**: IPv6 туннелируется через VPN по умолчанию (full-tunnel)
- [ ] **NET-06**: Если сервер не поддерживает IPv6 — fallback на блокировку через `ipv6Settings = nil` + `excludeRoutes` для всех IPv6 destinations
- [ ] **NET-07**: IPv6 mode опция в Расширенных (`auto`/`tunnel`/`block`)
- [ ] **NET-08**: Auto-reconnect при смене Wi-Fi ↔ LTE
- [ ] **NET-09**: Auto-reconnect после выхода из sleep
- [ ] **NET-10**: Auto-reconnect при смене IP
- [ ] **NET-11**: Failover на другой сервер при падении

### Rules Engine (RULES)

- [ ] **RULES-01**: Приложение скачивает `rules.json` с primary VPS + failover-зеркала (до 3 URL захардкожены массивом)
- [ ] **RULES-02**: Проверка Ed25519-подписи `rules.json` через swift-crypto; публичный ключ захардкожен
- [ ] **RULES-03**: Битая подпись — приложение игнорирует обновление, использует кеш
- [ ] **RULES-04**: Скачивание при старте + раз в 6 часов в фоне
- [ ] **RULES-05**: Применение правил `always_through_vpn` (включая когда VPN формально «отключён»), `never_through_vpn` (split-tunnel exclude), `block_completely` (дроп независимо от VPN)
- [ ] **RULES-06**: Иерархия приоритетов: block_completely > never_through_vpn > always_through_vpn > default toggle пользователя
- [ ] **RULES-07**: Split tunneling по доменам, IP/CIDR, странам (geo-IP)
- [ ] **RULES-08**: Поле `min_app_version` — если выше текущей, показывается экран «Обновитесь через TestFlight»
- [ ] **RULES-09**: Просмотр текущих правил (read-only) в Расширенных
- [ ] **RULES-10**: Кнопка «Принудительно обновить правила» в Расширенных
- [ ] **RULES-11**: AppProxyProvider таргет на macOS для per-app routing

### Deep links (DEEP)

- [ ] **DEEP-01**: Custom URL Scheme `bbtb://` (import/connect/disconnect)
- [ ] **DEEP-02**: Universal Links через `import.bbtb.app` с `apple-app-site-association`
- [ ] **DEEP-03**: Endpoint `https://import.bbtb.app/c/{token}` на VPS отдаёт конфиг
- [ ] **DEEP-04**: Landing page для тех, у кого приложение не установлено — отправляет на TestFlight invite
- [ ] **DEEP-05**: `DeepLinkRouter` — actor в модуле `DeepLinks`, парсит URL → вызывает handler

### Detection / Awareness (DETECT)

- [ ] **DETECT-01**: MAX-detection на iOS — `UIApplication.canOpenURL(URL(string: "max://")!)`, URL-схема в `LSApplicationQueriesSchemes`. БЕЗ UI-уведомлений, только в локальный debug-лог
- [ ] **DETECT-02**: MAX-detection на macOS — `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`
- [ ] **DETECT-03**: Известные домены MAX добавляются в `block_completely` через rules.json

### Telemetry (TELEM)

- [x] **TELEM-01**: Локальный crash reporter — собирает крашлоги
- [ ] **TELEM-02**: Кнопка «Отправить лог разработчику» в Settings — собирает последние 24ч + версия приложения + версия ОС + анонимный device-id, маскирует последний октет IP в логах
- [ ] **TELEM-03**: Crash reporter с UI отправки при следующем запуске после краша
- [ ] **TELEM-04**: Privacy-respecting аналитика на собственном VPS, эндпоинт `/v1/telemetry`
- [ ] **TELEM-05**: POST с JSON-батчем раз в 24 часа в неактивный период, HTTPS + Ed25519-подпись приватным ключом приложения (из Keychain)
- [ ] **TELEM-06**: Собирается только: количество запусков, количество подключений, успешность по протоколам (без серверных адресов), версия приложения и ОС, анонимный device-token (UUID в Keychain)
- [ ] **TELEM-07**: Не собирается: IP-адреса, серверные адреса полностью, геолокация, пользовательские данные, посещённые сайты
- [ ] **TELEM-08**: Тоггл «Отключить аналитику» в Расширенных — выкл по умолчанию (то есть сбор включён, тоггл его выключает)
- [ ] **TELEM-09**: App Privacy declaration в App Store Connect — Diagnostic data, NOT linked to user, NOT used for tracking

### Biometrics + Privacy toggles (BIO)

- [ ] **BIO-01**: Face ID / Touch ID для входа в приложение — опционально, выкл по умолчанию
- [ ] **BIO-02**: При включении биометрии — приложение блокируется при backgrounding, требует биометрию для разблокировки
- [ ] **BIO-03**: Биометрия НЕ требуется для каждого подключения
- [ ] **BIO-04** (R3): Тоггл «Блокировать STUN-трафик» (WebRTC leak protection) в Расширенных — выкл по умолчанию. Блокирует UDP-порты 3478, 5349. Предупреждение: «сломает звонки в браузерных мессенджерах»

### On-Demand + Cert pinning (ONDEMAND)

- [ ] **ONDEMAND-01**: On-Demand rules — «всегда вкл» по дефолту + опция автоконнекта в публичных Wi-Fi

### Localization (LOC)

- [x] **LOC-01**: Локализация ru + en с первого дня, formирование `Localizable.xcstrings`
- [ ] **LOC-02**: Финальная полная локализация: никаких «hardcoded English strings» (v0.11)
- [ ] **LOC-03**: FAQ на двух языках в разделе Help
- [ ] **LOC-04**: FAQ содержит секцию «известные ограничения детектирования VPN» (см. wiki/vpn-detection-by-apps.md): 22 приложения в РФ детектят VPN

### Distribution (DIST)

- [x] **DIST-01**: iOS-сборка работает на iPhone 11+ (минимум для iOS 18)
- [x] **DIST-02**: macOS-сборка работает на Apple Silicon
- [ ] **DIST-03**: TestFlight build готов для External Testing
- [ ] **DIST-04**: Beta App Review submission
- [ ] **DIST-05**: Public invite link через TestFlight
- [ ] **DIST-06**: Сайт лендинга с invite-ссылкой
- [ ] **DIST-07**: About-screen с версией, ссылкой на open-source ядро (GitHub), лицензиями
- [ ] **DIST-08**: Documentation для конечных пользователей (как импортировать, как поделиться, как сообщить о баге)

## v2 Requirements (post-MVP)

Отложены за пределы v1.0; задокументированы для трекинга.

### Smart auto-select (v1.1)
- **SMART-01**: Smart-метрика auto-select — latency + jitter + DPI-успех с локальной памятью
- **SMART-02**: Локальная статистика по серверам (success rate)
- **SMART-03**: Recommendation engine

### Stats Pro (v1.2)
- **STATS-01**: Speed test до серверов
- **STATS-02**: Полные логи соединений с тогглом приватности (по дефолту off)
- **STATS-03**: График latency / jitter в реальном времени
- **STATS-04**: Traceroute, MTU
- **STATS-05**: Traffic stats по серверам и протоколам

### Multi-hop (v1.3)
- **CHAIN-01**: Поддержка цепочек протоколов
- **CHAIN-02**: UI для конфигурирования цепочек

### Widgets / Live Activity (v1.4)
- **WIDG-01**: Home screen widget
- **WIDG-02**: Lock screen widget
- **WIDG-03**: Live Activity на Dynamic Island

### Apple Watch (v1.5)
- **WATCH-01**: watchOS app (independent)
- **WATCH-02**: Complication

### Push (v1.6)
- **PUSH-01**: «Правила обновлены»
- **PUSH-02**: «VPN отключился непредвиденно»

### Shortcuts & Siri (v1.7)
- **SIRI-01**: Siri Intents
- **SIRI-02**: Shortcuts integration

### Stealth & Panic (v1.8)
- **STEALTH-01**: alternateIcons маскировка
- **STEALTH-02**: PIN на удаление конфигов
- **STEALTH-03**: Decoy режим
- **STEALTH-04**: Quick wipe

### iCloud Sync (v1.9)
- **CLOUD-01**: Sync конфигов между устройствами

### Managed Infrastructure (v2.0)
- **MANAGED-01**: Свои managed-серверы
- **MANAGED-02**: Биллинг через App Store auto-renewable
- **MANAGED-03**: Sign in with Apple
- **MANAGED-04**: Server-side admin panel

## Out of Scope (excluded permanently or by category)

| Feature | Reason |
|---------|--------|
| Анализ маршрутизации/getifaddrs скрытие на macOS | Невозможно без root; документируется как known limitation в FAQ |
| Защита от таргетированной слежки | Приложение не для журналистов под прицельной слежкой; только массовый DPI (см. PROJECT.md target audience) |
| Сторонние аналитические SDK (Crashlytics, Mixpanel, Sentry) | Privacy, App Store review, поверхность атаки |
| Управление подпиской вне App Store | Нарушение Apple policies на MVP |
| Хостинг серверной части в РФ | Юридический риск; смотри `prompts/v2 <final_notes>` |
| Резидентные exit-прокси на MVP | Дороже бюджета; направление для v1.x |
| Полные логи соединений как фича на MVP | Privacy + complexity; v1.2 с тогглом |
| Jailbreak-detection / anti-debug | Не нужны для целевой аудитории |

## Traceability

См. `.planning/ROADMAP.md` для распределения REQ-ID по фазам. Каждый v1 requirement маппится ровно в одну фазу.

**Coverage:** v1 requirements ≈ 130, все mapped (см. ROADMAP).

---
*Requirements defined: 2026-05-11*
*Last updated: 2026-05-11 after initialization from prompts/v2*
