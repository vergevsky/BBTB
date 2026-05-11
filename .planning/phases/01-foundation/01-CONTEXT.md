# Phase 1: Foundation — CONTEXT.md

**Phase:** 1
**Name:** Foundation
**Version:** v0.1 (internal alpha TestFlight)
**Date:** 2026-05-11
**Workflow:** `/gsd-discuss-phase 1` (default mode, interactive)

---

<domain>
Минимально жизнеспособная сборка iOS+macOS приложения **BBTB** («Верни жука»), которая:

1. Импортирует один VLESS+Vision+Reality конфиг через буфер обмена.
2. Поднимает туннель через sing-box (libbox.xcframework) и меняет IP пользователя (`https://api.ipify.org`).
3. Блокирует весь сетевой трафик при разрыве туннеля через системный kill switch (`includeAllNetworks=true` + `enforceRoutes=true`).
4. Проходит security review: ни SOCKS5, ни gRPC API sing-box не слушают `127.0.0.1`; `P2P=false` на туннельном интерфейсе.
5. Имеет базовую SwiftPM-структуру согласно `prompts/v2 <swift_package_layout>` с модулями VPNCore, ProtocolRegistry, ProtocolEngine, Protocols/VLESSReality, KillSwitch, плюс `PacketTunnelKit` (новый — см. ниже).

**НЕ в скоупе Phase 1** (приходит позже): импорт через QR/файл, ещё 8 протоколов, транспорты, anti-DPI suite, DNS-стратегия, IPv6, rules engine, server list, settings/advanced screens, onboarding, deep links, биометрия, telemetry.
</domain>

<spec_lock>
Источник истины по требованиям Phase 1:
- `.planning/ROADMAP.md` (Phase 1 secting): requirements list + success criteria
- `.planning/REQUIREMENTS.md`: CORE-01/02/04/06/07/08/10, SEC-01..06, KILL-01/02, PROTO-01, IMP-01, UX-02/03/07, TELEM-01, LOC-01, DIST-01/02
- `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` `<included_in_v0_1>` (LOCKED — authoritative)

`prompts/v2` имеет приоритет при расхождении (`<release_roadmap>` приоритетнее `<phases>`).
</spec_lock>

<canonical_refs>
Документы, которые **обязательно** читать downstream-агентам (researcher, planner) перед работой:

| Ref | Полный путь | Назначение |
|-----|-------------|------------|
| Источник истины по релизу v0.1 | `prompts/VPN-клиент для macOS и iOS — Промт для Claude Code v2.md` секция `<included_in_v0_1>` (строки ~645-662), `<release_roadmap>` v0.1 (строки ~779-792) | Точный состав фичи фазы и DoD |
| Архитектура SwiftPM | `prompts/v2 <swift_package_layout>` (строки 74-142) | Модульная структура — нельзя нарушать |
| Tech stack | `prompts/v2 <tech_stack>` (строки 160-173) | Swift 6, sing-box, libbox.xcframework, swift-crypto, OSLog |
| Network Extension targets | `prompts/v2 <network_extension_targets>` (строки 144-154) | Entitlements, App Group, NETunnelProviderManager |
| Security review (R1) | `wiki/security-gaps.md` R1 + `prompts/v2 <security>` секция (строки ~241+) + `wiki/xray-localhost-vulnerability.md` | SOCKS5/gRPC проверка |
| R6 — P2P=false | `wiki/security-gaps.md` R6 + `prompts/v2` строка ~239 | NEPacketTunnelNetworkSettings setup |
| Kill switch | `wiki/kill-switch.md` + `prompts/v2 <kill_switch>` | `includeAllNetworks` + `enforceRoutes`, R4 контекст |
| VLESS+Reality конфиг | `wiki/vless-reality.md` + `prompts/v2 <protocols>` PROTO-01 | Поля `serverName`, `publicKey`, `shortId` |
| Apple detection surface (актуально для R1+R6) | `wiki/apple-detection-surface.md` | Что РКН-методика проверяет |
| ConfigParser референс | `wiki/config-parser-singbox-launcher.md` | Парсинг vless:// URI |
| Имена и идентификаторы | `wiki/product-overview.md` секция «Имя и идентификаторы» | Bundle ID, App Group, Team ID, URL scheme — каноничный список |
</canonical_refs>

<decisions>

## 1. Идентификаторы и брендинг

**Project codename:** `BBTB` (Bring Back The Bug, аббревиатура). Использовать в:
- Xcode-проекте: корневая папка `BBTB/` в репозитории.
- Bundle ID — префикс `app.bbtb.*`.
- App Group — `group.app.bbtb.shared`.
- Custom URL scheme (для DEEP-01 в Phase 9) — `bbtb://`.
- Universal Links домен (для DEEP-02/03 в Phase 9) — `import.bbtb.app`.
- Имена файлов, переменных, констант — `BBTB`/`bbtb`.

**Display name** (то, что видит конечный пользователь):
- `CFBundleDisplayName` (ru): **«Верни жука»**
- `CFBundleDisplayName` (en): **«Bring Back the Bug»**

**Bundle IDs (полный список для Phase 1):**
| Таргет | Bundle ID |
|---|---|
| iOS app | `app.bbtb.client.ios` |
| macOS app | `app.bbtb.client.macos` |
| iOS PacketTunnelExtension | `app.bbtb.client.ios.tunnel` |
| macOS PacketTunnelExtension | `app.bbtb.client.macos.tunnel` |
| (отложено до v0.8) macOS AppProxyExtension | `app.bbtb.client.macos.appproxy` |

**Apple Developer Team ID:** `UAN8W9Q82U` (зафиксирован).

**Entitlements (см. CORE-06):**
- `com.apple.developer.networking.networkextension`: `packet-tunnel-provider` (iOS+macOS), `app-proxy-provider` (только macOS, оставляем заготовку для v0.8)
- `com.apple.developer.networking.vpn.api`: `allow-vpn`
- `com.apple.security.application-groups`: `group.app.bbtb.shared`
- `com.apple.security.app-sandbox` (macOS)
- `com.apple.security.network.client`
- `com.apple.security.network.server`

## 2. Тестовая инфраструктура

**VLESS+Reality сервер для smoke-теста:** у разработчика уже есть рабочий sing-box (или Xray) сервер с настроенным Reality. Серверный setup **НЕ в скоупе Phase 1** — server URL и `publicKey` предоставляются разработчиком вручную при выполнении DoD #1 (smoke-тест с проверкой `api.ipify.org`).

**Хранение тестового конфига:** не коммитить в git (содержит секреты). Расположение для локального тестирования — `.gitignore`-шенный файл `Tests/Fixtures/test-config.vless.local.txt` (или иной путь по выбору planner) с шаблоном-плейсхолдером в git и реальным конфигом локально у разработчика.

## 3. Структура PacketTunnelExtension iOS↔macOS

**Решение:** общий Swift Package + два тонких NSExtension target-shell.

**Структура:**
```
BBTB/
├── App/
│   ├── PacketTunnelExtension-iOS/         ← Target type: NetworkExtension (Packet Tunnel Provider)
│   │   ├── Info.plist                     ← NSExtension entry, Bundle ID app.bbtb.client.ios.tunnel
│   │   └── PacketTunnelProvider.swift     ← class PacketTunnelProvider: BaseSingBoxTunnel (тонкий shell)
│   │
│   └── PacketTunnelExtension-macOS/       ← аналогично, Bundle ID app.bbtb.client.macos.tunnel
│       ├── Info.plist
│       └── PacketTunnelProvider.swift
│
└── Packages/
    └── PacketTunnelKit/                   ← НОВЫЙ Package (добавление к swift_package_layout v2)
        └── Sources/PacketTunnelKit/
            ├── BaseSingBoxTunnel.swift    ← class BaseSingBoxTunnel: NEPacketTunnelProvider
            ├── TunnelSettings.swift       ← NEPacketTunnelNetworkSettings builder (R6: P2P=false!)
            ├── SingBoxConfigLoader.swift  ← валидация конфига (R1: no SOCKS5/gRPC)
            └── PlatformSpecific/
                ├── iOS.swift              ← #if os(iOS) — iOS-only quirks (если будут)
                └── macOS.swift            ← #if os(macOS) — macOS-only quirks (enforceRoutes toggle hook для v0.10)
```

**Обоснование:** `BaseSingBoxTunnel` инкапсулирует всю общую логику (startTunnel, stopTunnel, sing-box lifecycle, kill switch wiring). Два target-shell остаются минимальными — фактически только override-точки для платформ-специфичной настройки `NEPacketTunnelNetworkSettings`. Compile-time флаги `#if os(iOS)` / `#if os(macOS)` — внутри `PacketTunnelKit` где нужно (например, на iOS дополнительная проверка чтобы не выставить P2P R6, на macOS — заглушка под будущий enforceRoutes toggle R5 в v0.10).

**Влияние на `prompts/v2 <swift_package_layout>`:** к существующему списку Packages/ добавляется `PacketTunnelKit`. Обоснование добавления — `ProtocolEngine` в v2-промте описан как обёртка над libbox.xcframework, но не специфицирован контракт между ним и NSExtension. `PacketTunnelKit` — это и есть тонкий контракт-слой между двумя target shells и ProtocolEngine. Researcher должен подтвердить отсутствие конфликта с v2-layout.

## 4. Стратегия security review (R1 + R6)

**Решение:** Security-first — R1+R6 идут первым wave'ом плана, ДО реализации `BaseSingBoxTunnel`.

**Структура wave'ов в PLAN.md (черновик для planner):**

**Wave 0 — Bootstrap:**
- Создать Xcode-проект `BBTB/` (Apple Silicon, Xcode 16+, Swift 6 mode).
- Создать пустые SwiftPM-пакеты согласно `<swift_package_layout>` (VPNCore, ProtocolRegistry, ProtocolEngine, KillSwitch, и др. — placeholder-таргеты, компилируются как `// TODO`).
- Настроить два main app target (iOS + macOS) + два PacketTunnelExtension target shells + entitlements.
- Зафиксировать Team ID `UAN8W9Q82U` через локальный `.xcconfig`.

**Wave 1 — Security foundation (R1):**
- Спроектировать JSON-шаблон sing-box-конфига для VLESS+Vision+Reality **без секций `inbounds[type=socks]` и `inbounds[type=mixed]`** и **без `experimental.clash_api` / `experimental.cache_file`** (R1).
- Явно установить `experimental.cache_file.enabled = false`, `experimental.clash_api = null`.
- Написать `SingBoxConfigLoader.validate()` — runtime-проверка перед запуском туннеля, отказ при обнаружении SOCKS5/gRPC секций.
- Создать standalone Xcode-проект `Tools/SocksProbe/` (отдельный bundle ID `app.bbtb.tools.socksprobe`, **не зависит от App Group**) — приложение, которое пытается TCP-connect к `127.0.0.1:N` для портов 1080, 9000, 5555, 16000–16100 (методичка РКН). На iOS — UI с кнопкой «Скан» + результатом. На macOS — то же или CLI.

**Wave 2 — Kill switch + R6:**
- Реализовать `PacketTunnelKit/TunnelSettings.swift` с явной проверкой что `NEIPv4Settings`/`NEIPv6Settings` создаются без вызова setter'ов, которые могут выставить `P2P=true` (R6). Документировать в коде комментарием со ссылкой на R6 в `wiki/security-gaps.md`.
- Реализовать `KillSwitch` модуль: настройка `NEVPNProtocol.includeAllNetworks=true` + `enforceRoutes=true` (R4 default) при создании `NETunnelProviderManager`.

**Wave 3 — Base tunnel:**
- `BaseSingBoxTunnel`: startTunnel → загрузить конфиг → SingBoxConfigLoader.validate() → libbox.start() → setTunnelNetworkSettings(R6-safe). stopTunnel — обратный порядок.

**Wave 4 — UI + import flow:**
- Main screen на iOS+macOS (UX-02, UX-03): таймер `HH:MM:SS`, большая центральная кнопка с состояниями idle/connecting/connected/error, верхняя/нижняя bar — placeholder (без server selection — это Phase 3).
- macOS Menu Bar app (UX-07): NSStatusItem + popover «Connect/Disconnect + текущий статус + timer». Минимальный.
- Import flow (IMP-01): кнопка «Импортировать из буфера» на main screen + parser vless:// → создание `NETunnelProviderManager` + сохранение в SwiftData (метаданные) + Keychain (секреты `privateKey`/`UUID` из URI, access flag `kSecAttrAccessibleWhenUnlocked`).
- Базовая локализация ru+en для всех UI-строк сразу через `Localizable.xcstrings`.

**Wave 5 — Crash reporter + Distribution + Validation:**
- TELEM-01: подписка на `MXMetricManager` + сохранение `MXCrashDiagnostic` в файл App Group. Без UI отправки (TELEM-03 — v0.12).
- TestFlight build (DIST-01, DIST-02): архив iOS + macOS, верификация что устанавливается на реальные устройства.
- **Validation R1**: запустить SocksProbe на устройстве при активном туннеле → подтвердить «ни один порт не отвечает». Зафиксировать скриншот в `.planning/phases/01-foundation/security-evidence/`.
- **Validation R6**: программно проверить `NEInterface`/`networkSettings.p2p` через PacketTunnelProvider self-introspection. Альтернатива — runtime assertion в development-сборке.
- **Validation DoD #1**: импорт vless+reality → connect → проверка `https://api.ipify.org` → IP изменился.
- **Validation DoD #2**: разорвать туннель (отключить интернет / kill libbox изнутри) → ОС блокирует трафик.

**Обоснование security-first:** ни одна промежуточная сборка не должна попадать в TestFlight (даже internal-tier) с включённым SOCKS5 или невалидированным P2P=true. Стоимость security-first vs validation-gate — те же ~4 часа на test-app, но риск drift'а в финале нулевой.

## 5. Дефолты, принятые Claude (можно пересмотреть до /gsd-plan-phase)

Эти решения приняты Claude без явного обсуждения — если planner или ты увидишь нюанс, поднимаем заново:

| Тема | Дефолт |
|---|---|
| Минимальный UI на v0.1 | Голый системный SwiftUI (SF Symbols, system colors); создать Package `DesignSystem` с placeholder-токенами (`Color.bbtbAccent = .accentColor`, `Font.bbtbTitle = .system(.title, design: .rounded)` — заготовка под Figma в v0.11). |
| UX-триггер импорта vless:// | Явная кнопка «Импортировать из буфера» на main screen (empty-state, когда нет сохранённых конфигов). Pasteboard auto-detect на app activate отложен до v0.11. |
| Crash reporter (TELEM-01) | `MXMetricManager.shared.add()` подписчика → пишет `MXCrashDiagnostic` в файл `crash-YYYYMMDD-HHMMSS.json` в App Group container. Без UI. |
| Menu Bar app (UX-07) | `NSStatusItem` с иконкой (SF Symbol `bolt.shield`) + `NSPopover` с одной view: status text + connection timer + кнопка Connect/Disconnect. Никакого выбора серверов (Phase 3) и settings (Phase 4+). |
| Хранение импортированного конфига | SwiftData `@Model ServerConfig` для метаданных (название, протокол, host, port, lastLatency, isActive, keychainTag). Keychain (`kSecAttrAccessibleWhenUnlocked`) для секретов VLESS+Reality (`uuid`, `privateKey`, `shortId`) — ключ Keychain item = `keychainTag` из SwiftData. |
| Локализация на v0.1 | Все строки сразу в `Localizable.xcstrings` ru + en. UI Phase 1 маленький (~15-20 строк) — нет смысла откладывать. |
| Onboarding | Нет отдельного onboarding-экрана. Main screen с empty-state «Импортируйте конфиг из буфера обмена» при отсутствии сохранённых конфигов. UX-01 (полноценный onboarding) — Phase 11. |

## 6. Версионирование и сборка

- Marketing version (`CFBundleShortVersionString`): `0.1.0` для v0.1.
- Build number (`CFBundleVersion`): автоинкремент через скрипт (`agvtool` или CI) — стартует с `1`.
- Распространение Phase 1 build: internal tester группа в TestFlight (узкий круг бета-тестеров, не публичный invite). Публичный invite — только начиная с v1.0 (Phase 12 / DIST-05).

</decisions>

<code_context>
**Codebase state:** Greenfield. В репозитории сейчас:
- `Wiki/` — knowledge base (28 страниц).
- `Raw/` — immutable sources.
- `prompts/` — спецификации (источник истины).
- `.planning/` — GSD-планирование.
- `Claude.md` — project instructions.
- **Xcode-проекта пока нет** — создаётся в Wave 0.

**Reusable assets:** нет (greenfield). Все Packages создаются с нуля.

**Existing patterns:** нет (greenfield). Conventions определяются planner'ом в PLAN.md и фиксируются в `wiki/architecture.md`.
</code_context>

<deferred_ideas>
**Идеи, которые всплыли но НЕ в Phase 1:**

- **macOS toggle «Отключить принудительную маршрутизацию» (R5):** запланировано на Phase 10 (v0.10) — не возвращаемся в Phase 1. PacketTunnelKit/PlatformSpecific/macOS.swift содержит **только заглушку** под будущий hook, без активации.
- **AppProxyExtension-macOS:** target создаётся в Wave 0 как заготовка (CORE-05 относится к Phase 8), но не реализуется. Bundle ID зарезервирован: `app.bbtb.client.macos.appproxy`.
- **Pasteboard auto-detect на app activate:** возможный smart-UX, отложен до v0.11 (Phase 11 — Onboarding + UX polish).
- **xray-core как fallback (CORE-09):** не в Phase 1 (мы говорим v0.1 — только sing-box + VLESS+Reality). Package `ProtocolEngine/XrayFallback/` создаётся как пустой placeholder в Wave 0 — компилируется, ничего не делает.
- **TestFlight Beta App Review submission:** не в Phase 1. v0.1 раздаётся только internal-tier тестировщикам (без Beta App Review). DIST-04 — Phase 12.
- **Crash reporter UI отправки (TELEM-03):** Phase 12 / v0.12.
</deferred_ideas>

<next_steps>
**После `/clear` запустить:**

```
/gsd-plan-phase 1
```

Planner получит этот CONTEXT.md + REQUIREMENTS.md + ROADMAP.md и составит PLAN.md по 6 wave'ам выше.

**Альтернативно:**
- `/gsd-plan-phase 1 --skip-research` — если ты уверен что researcher не нужен (CONTEXT.md уже содержит детальную структуру wave'ов).
- `/gsd-ui-phase 1` — если хочешь сначала зафиксировать UI-контракт через UI-SPEC.md (но Phase 1 UI минималистичный, можно обойтись).

**Перед /gsd-plan-phase проверить (1 минута):**
- Bundle IDs не зарегистрированы конфликтно в Apple Developer Portal (для будущей сабмиссии — пока не критично).
- `import.bbtb.app` домен не куплен ещё (опционально — это для Phase 9, можно зарезервировать сейчас если хочется).
</next_steps>

---
*Created: 2026-05-11 via `/gsd-discuss-phase 1`.*
*Decisions captured: 4 selected gray areas + rebrand to BBTB + 7 Claude-defaults.*
*Downstream: `gsd-phase-researcher`, `gsd-planner`.*
