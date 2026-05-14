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

- [x] **KILL-01**: Kill switch системный (`NEVPNProtocol.includeAllNetworks=true` + `enforceRoutes=true`), **выключен по дефолту** (изменено 2026-05-12: было включён; UX-решение — снизить friction при первом запуске)
- [x] **KILL-02**: При падении туннеля ОС блокирует весь сетевой трафик до восстановления или ручного отключения VPN
- [x] **KILL-03**: Тоггл для отключения kill switch в разделе «Расширенные» (с v0.2) — Phase 2 UAT T7-T9 PASS 2026-05-12
- [ ] **KILL-04** (R5): На macOS — отдельный тоггл «Отключить принудительную маршрутизацию» (`enforceRoutes=false`) в Расширенных (с v0.10)

### Протоколы (PROTO)

- [x] **PROTO-01**: VLESS + XTLS Vision + Reality — главный anti-ТСПУ протокол. Конфиг включает `serverName`, `publicKey`, `shortId`
- [x] **PROTO-02**: Trojan — TLS-based, выглядит как обычный HTTPS — Phase 2 UAT T5 PASS 2026-05-12 (TCP+TLS и WS+TLS)
- [ ] **PROTO-03**: VLESS + XTLS-Vision (без Reality) — для серверов без поддержки Reality
- [ ] **PROTO-04**: Shadowsocks-2022 (SS-2022, AEAD-2022) — AES-128-GCM
- [ ] **PROTO-05**: Hysteria2 — UDP-based, QUIC-обёртка
- [ ] ~~**PROTO-06**: WireGuard через WireGuardKit от ZX2C4~~ → **Out of Scope** _(Phase 7 discuss 2026-05-14 D-02. ТСПУ blocks plain WG behaviorally с Feb 2026; UDP в РФ closed Lehnen 2025; AmneziaWG 2.0 покрывает WG-нишу. Conditional return on TestFlight demand for non-RU WG servers. См. `wiki/wireguard-deferral-2026.md`.)_
- [ ] **PROTO-07**: AmneziaWG **2.0** — модифицированный WireGuard с anti-DPI обфускацией (S1-S4, H1-H4, I1-I5, Jc/Jmin/Jmax junk packets). Phase 7b via `amneziawg-apple` SwiftPM library (MIT) + engine abstraction. **v1.5 conditional на demand** (Phase 7 discuss 2026-05-14 D-03).
- [x] **PROTO-08**: TUIC v5 — QUIC-based, альтернатива Hysteria2 (Phase 7a v0.7.1 ✅ Validated 2026-05-14 — TUICHandler + TUICURIParser + ConfigBuilder + Clash YAML mapping + integration в 8 consumer switches; 44 unit tests + iPhone regression UAT PASS на Trojan-based subscription без TUIC connection test, который carved-out до появления реального TUIC сервера)
- [ ] ~~**PROTO-09**: OpenVPN over TLS — legacy совместимость~~ → **Out of Scope** _(Phase 7 discuss 2026-05-14 D-01. ТСПУ blocks OpenVPN полностью с Feb 2026; OpenVPN+Cloak phased out from Amnezia Premium 2026; sing-box не умеет OpenVPN, требует separate Partout engine (GPLv3 + commercial для AppStore). Conditional return on TestFlight demand. См. `wiki/openvpn-deferral-2026.md`.)_
- [x] **PROTO-10**: Auto-fallback — если основной протокол не подключился за N секунд, автоматически пробуется второй из конфига без вмешательства пользователя — Phase 2 UAT T6 PASS 2026-05-12 (via sing-box urltest outbound, interval=1m)

### Транспорты (TRANSP)

- [ ] **TRANSP-01**: XHTTP — новый рекомендуемый, маскировка под HTTP/2 multiplexed traffic
- [ ] **TRANSP-02**: gRPC — HTTP/2 RPC
- [ ] **TRANSP-03**: WebSocket — legacy совместимость — **Phase 2 partial** (WebSocket transport для Trojan), Phase 5 finish (расширить за пределы Trojan + UI выбор транспорта)
- [ ] **TRANSP-04**: HTTPUpgrade — минималистичный, легче gRPC
- [ ] **TRANSP-05**: В Расширенных можно вручную выбрать транспорт для дебага

### Anti-DPI техники (DPI)

- [x] **DPI-01**: uTLS fingerprint mimicking — клиент представляется как Chrome/Firefox/Safari, по умолчанию **randomized**. Phase 7a smart default: `tls.utls.fingerprint = "random"` для всех TLS-протоколов (VLESS+Reality, VLESS+Vision, VLESS+TLS, Trojan, TUIC v5). URI override `fp=chrome` уважается. (Phase 7a v0.7.1 ✅ Validated 2026-05-14 — iPhone regression PASS на Trojan subscription, sing-box logs показывают ноль TLS handshake errors после смены default). UI picker — Phase 10 (DPI-09).
- [x] **DPI-02**: TLS ClientHello фрагментация — первый пакет TLS разбивается на несколько TCP-пакетов чтобы DPI не успел распарсить SNI. Phase 7a smart default: `tls.record_fragment = true` для VLESS+TLS / Trojan (Codex Q4 follow-up: НЕ для TUIC v5 — QUIC «only ECH»). НЕ для Reality/Vision — там собственный XTLS-механизм. (Phase 7a v0.7.1 ✅ Validated 2026-05-14 — Trojan-based subscription с record_fragment=true успешно подключается к Instagram/Facebook/Apple Push, ноль TLS errors в sing-box logs).
- [ ] **DPI-03**: ~~Packet padding — случайные байты к пакетам~~ → reframed _(Phase 7 discuss 2026-05-14)_: sing-box не имеет generic packet padding. Реализуется через `multiplex.padding = true` ТОЛЬКО когда mux включён per-server (см. DPI-05). Глобальный default отсутствует. AmneziaWG 2.0 junk packets (Jc/Jmin/Jmax) дают аналогичный эффект для AWG-протокола (Phase 7b).
- [ ] **DPI-04**: ~~Random TCP/UDP delay — рандомные задержки между пакетами~~ → reframed _(Phase 7 discuss 2026-05-14)_: sing-box не поддерживает random delay для не-AWG протоколов. Covered by **AmneziaWG 2.0 junk packets** (Jc/Jmin/Jmax) в Phase 7b. Не отдельное требование для sing-box-протоколов.
- [ ] **DPI-05**: Mux — мультиплексирование (smux/yamux/h2mux) через `multiplex.enabled = true` для VLESS+TLS / Trojan / Shadowsocks-2022. Phase 7a smart default: **off** (mux ломает Vision/Reality, не нужен для TUIC/Hysteria2 — там QUIC уже multiplex; не для WireGuard). Включается per-server только если URI указывает `mux=true` или Clash `smux:enabled:true`.
- [ ] **DPI-06**: CDN-фронтинг (Cloudflare/Fastly) как fallback transport — Phase 10 (v0.10)
- [x] **DPI-07**: Поддержка разных портов: 443 приоритет, плюс 80, 8443, 2096 и др. (Phase 7a v0.7.1 ✅ Validated 2026-05-14 — URI парсеры уже принимали любой порт, явно задокументировано в `wiki/anti-dpi-techniques.md`)
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
- [x] **UX-04**: Server list screen — кнопка «Авто» + список с флагами стран и latency + pull-to-refresh + секции по подпискам; шит адаптируется по высоте контента (полноэкранный только если контент превышает ~88% высоты экрана) — Phase 3 UAT T1-T5 PASS 2026-05-12
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
- [x] **NET-08**: Auto-reconnect при смене Wi-Fi ↔ LTE *(Phase 6c ✓ Complete 2026-05-13 — реализован через Apple's `NEOnDemandRuleConnect(.any)`; UAT Round 1 PASS + re-UAT PASS на iPhone iOS 26.5 — F-reverse + Settings-disable + G passive)*
- [x] **NET-09**: Auto-reconnect после выхода из sleep *(Phase 6c — iOS на on-demand, macOS на `NSWorkspace.didWakeNotification` observer + 3 guards; UAT PASS на macOS; iOS path validated через re-UAT)*
- [x] **NET-10**: Auto-reconnect при смене IP *(Phase 6c — covered Apple's on-demand evaluator; carry-over из Phase 6 validated через re-UAT)*
- [x] **NET-11**: Failover на другой сервер при падении *(Phase 6 `SwiftDataFailoverProvider` сохранён в Phase 6c; mid-session failover теперь через `TunnelWatchdog` actor с 3s debounce + .reasserting cancellation. Pitfall 5 — soft kill server — выделен в NET-12 как отдельный gap, не блокирует closure NET-11)*
- [ ] **NET-12** *(backlog, добавлено Phase 6c)*: liveness probe — server-side stall detection (sing-box `Cmd_LogClient` polling ИЛИ app-side ping каждые N секунд). Покрывает edge case Pitfall 5 где tunnel formally `.connected` но реально не передаёт трафик. Defer to Phase 7-8.

### Performance & Code Quality (PERF / QUAL) — Phase 6d

- [x] **PERF-01**: Cold-start path не блокирует main thread non-critical работой (SwiftData migrations, parser allocations, scene-active triggers). Pattern DEC-06d-01: defer в `Task.detached(priority: .utility)` или `.onAppear`. *(Phase 6d ✓ Closed 2026-05-14 — M1/M2/M3/M4 closed; expected −500..−1100 мс cold-start)*
- [x] **PERF-02**: Connect/disconnect path ≤ 2 XPC trips через `applyCurrentStateToCachedManager()` single save+load. Pattern DEC-06d-02. *(Phase 6d ✓ Closed 2026-05-14 — H2/M1; expected −200+ мс на tap)*
- [x] **PERF-03**: NEVPNStatus polling event-driven (`AsyncStream<NEVPNStatus>`), не `sleep`-based loops. Pattern DEC-06d-03. *(Phase 6d ✓ Closed 2026-05-14 — H3/H8; expected −800 мс connect + −2.5 сек disconnect)*
- [x] **PERF-04**: Probe-style operations с bounded concurrency (limit 4-8) + cancellation-safe defer cleanup. Pattern DEC-06d-04. *(Phase 6d ✓ Closed 2026-05-14 — H4/M13)*
- [x] **PERF-05**: Shipping builds не имеют `logLevel: trace` или multi-MB log export на cold-start. *(Phase 6d ✓ Closed 2026-05-14 — H1 `c2d54ea` gated за `#if DEBUG`)*
- [x] **QUAL-01**: Phase 6c D-09 invariants preserved через regression gate каждого fix-commit (forbidden symbols grep ≤ 7, observer queue=.main = 0, #Predicate UUID? = 0, applyVPNStatus single authority + Round 5 carve-out, sliding window). *(Phase 6d ✓ Closed 2026-05-14 — 19 fix-commits + 6 post-fix commits passed gate)*
- [x] **QUAL-02**: Multi-AI peer review pattern (Opus + Codex + Gemini, identical 7-section brief) установлен как стандарт для cross-cutting audit phases. *(Phase 6d ✓ Closed 2026-05-14 — 45 findings synthesized → 06D-FINDINGS.md, methodology в `wiki/performance-baseline.md`)*
- [x] **QUAL-03**: Apple-canonical `options["manualStart"]` discriminator + sticky App Group marker (ExternalVPNStopMarker) для Settings-disable correctness — pattern DEC-06d-05. *(Phase 6d ✓ Closed 2026-05-14 — `cff3f46` open-source-derived from WireGuard iOS pattern; UAT PASS)*
- [x] **QUAL-04**: Carved-out backlog Phase 6d (26 finding IDs) полностью accounted; baseline maximally clean перед Phase 7. *(Phase 6e ✓ Closed 2026-05-14 — SCENARIO B + L18 deferral: 19 code-fixed (Wave 1: 5 atomic MEDIUM = M7/M10/M8+L12/M11; Wave 2 bundles: 14 LOW = L1/L2/L3/L4/L5/L7/L8/L9/L10/L11/L13/L14/L15/L20) + 5 bookkeeping subsumed-by-Phase-6d (M6/M15/L6/L17/L19) + 2 deferred = 26 ✓. **Exception note:** L16 deferred per Codex Plan Reviewer HIGH-RISK no-go + AUTO_MODE safe-default; L18 deferred per architectural incompatibility (lazy var + init-time coordinator backlink + ObservedObject ABI). L16/L18 carry-forward → Phase 6f либо Phase 7+ refactor. Closure SUMMARY: 06E-Final-SUMMARY.md)*
- [x] **QUAL-05**: Periphery dead-code scan на post-Phase-6e baseline: actionable count = 0 (down from 3 в Phase 6d closure). *(Phase 6e ✓ Closed 2026-05-14 — 3 trivial unused imports removed в Wave 2 Theme D commit `f42499f` (ServerDetailView ConfigParser + ServerListSheet ConfigParser + TransportPicker DesignSystem); remaining 37 Periphery findings — все false-positive / architectural (XCTest reflection helpers + NotificationCenter token ownership + protocol stub-parameters + cross-package indirect dependencies, documented в 06D-PERIPHERY-POST-FIX.md))*

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

**Coverage:** v1 requirements ≈ 140 (130 + 8 PERF/QUAL added Phase 6d + 2 QUAL added Phase 6e), все mapped (см. ROADMAP).

---
*Requirements defined: 2026-05-11*
*Last updated: 2026-05-14 — Phase 6e closure added QUAL-04 + QUAL-05 as Validated (с явным L16/L18 deferral exception note для QUAL-04). PERF-01..05 + QUAL-01..03 (Phase 6d) preserved Validated. См. wiki/performance-baseline.md для деталей.*
