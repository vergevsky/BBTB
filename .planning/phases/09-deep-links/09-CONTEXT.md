# Phase 9: Deep Links — Context

**Gathered:** 2026-05-15
**Status:** Ready for planning

> **Scope amendment (decided 2026-05-15 in this discuss-phase):** DEEP-03 (token endpoint `/c/{token}`) и DEEP-04 (landing page) перенесены в **v1+ backlog**. Phase 9 реализует только клиентскую часть + минимальный AASA-сервер. REQUIREMENTS.md и ROADMAP.md обновляются planner'ом в первой задаче плана.

<domain>
## Phase Boundary

**Что фаза делает (v0.9):** Приложение обрабатывает входящие deep link URL из внешних источников (Telegram, Safari, браузер) и выполняет **import конфига**. Две дорожки: custom scheme `bbtb://import?url={subscription_url}` (DEEP-01) и Universal Links `https://import.bbtb.app/...` (DEEP-02). Swift actor `DeepLinkRouter` в новом SwiftPM пакете `DeepLinks` (DEEP-05) маршрутизирует URL к правильному обработчику.

**Серверная часть Phase 9:** только AASA файл на `import.bbtb.app` (nginx или static hosting). Без токен-эндпоинта.

**Платформы:** iOS + macOS (оба получают `bbtb://` scheme + Universal Links).

### В скоупе v0.9

1. **DEEP-01: `bbtb://` custom URL scheme** — зарегистрирован в Info.plist iOS + macOS. Единственный поддерживаемый action в Phase 9: `bbtb://import?url={subscription_url}`.
2. **DEEP-02: Universal Links** — `apple-app-site-association` на `import.bbtb.app`. App ID: `UAN8W9Q82U.app.bbtb.client.ios` + `UAN8W9Q82U.app.bbtb.client.macos`. Associated Domains entitlements в обоих targets.
3. **DEEP-05: `DeepLinkRouter` actor** — новый SwiftPM пакет `DeepLinks`. Extensible архитектура по паттерну ProtocolRegistry: protocol `DeepLinkHandler` + регистрация обработчиков. В Phase 9 один обработчик: `ImportHandler`.
4. **Apple Developer Portal** — галочки Associated Domains для `app.bbtb.client.ios` и `app.bbtb.client.macos`.
5. **Error UX** — SwiftUI Alert с текстом ошибки + кнопка OK (через существующий alert-механизм MainScreenViewModel).
6. **Архитектурная заглушка для v1+** — `TokenFetcher` protocol в пакете `DeepLinks` (без реализации). Когда в v1+ появится токен-эндпоинт — регистрируется `RemoteTokenFetchHandler`.

### НЕ в скоупе v0.9

- **DEEP-03** (`/c/{token}` backend) — v1+ backlog. Требует Shlink или аналог.
- **DEEP-04** (landing page) — v1+ backlog. Требует сервер с HTML.
- **bbtb://connect** и **bbtb://disconnect** — deferred. Нет подтверждённого use case.
- **Токен-based Universal Links** (когда Universal Link разворачивается в токен → сервер отдаёт конфиг) — v1+ вместе с DEEP-03.

</domain>

<decisions>
## Implementation Decisions

### Area A — Серверная архитектура

- **D-01: Минимальный сервер Phase 9 — только AASA.** На `import.bbtb.app` нужен только `/.well-known/apple-app-site-association` (Content-Type: application/json, без расширения файла, HTTPS обязательно). Можно nginx static или Cloudflare Pages.

- **D-02: AASA содержимое v0.9 (без `/c/*` пока нет токен-эндпоинта).**
  ```json
  {
    "applinks": {
      "details": [{
        "appIDs": [
          "UAN8W9Q82U.app.bbtb.client.ios",
          "UAN8W9Q82U.app.bbtb.client.macos"
        ],
        "components": [{ "/": "/import*" }]
      }]
    }
  }
  ```
  Когда в v1+ появится `/c/{token}` — добавить `{ "/": "/c/*" }` в `components`.

- **D-03: Архитектурная подготовка к v1+ backend.** `DeepLinks` пакет содержит:
  - `TokenFetcher` protocol (пустой протокол-placeholder)
  - `RemoteTokenFetchHandler` — **заглушка** (не реализована, только `struct` с TODO)
  В v1+ planner реализует `RemoteTokenFetchHandler` через Shlink или прямой прокси к Marzban subscription URL.

### Area B — URL-дизайн

- **D-04: `bbtb://import?url={subscription_url}` — единственный поддерживаемый формат v0.9.** `subscription_url` — любой URL, который `ConfigImporter.importFromRawInput()` уже умеет обрабатывать: Marzban `/sub/{token}`, JSON endpoint, subscription URL v2ray. DeepLinkRouter извлекает `url` параметр, URL-decode'ит, передаёт в `ConfigImporter.importFromRawInput()`.

- **D-05: Extensible URL parsing.** `DeepLinkRouter` не делает один большой `switch` по scheme/host. Вместо этого: `protocol DeepLinkHandler { func canHandle(_ url: URL) -> Bool; func handle(_ url: URL) async throws }`. В Phase 9 — один `ImportHandler`. В v1+ — `TokenHandler` добавляется регистрацией.

- **D-06: connect/disconnect — deferred.** В Phase 9 нет `bbtb://connect` и `bbtb://disconnect`. `DeepLinkRouter` логирует unhandled URLs и возвращает ошибку с понятным сообщением.

### Area C — Платформы

- **D-07: iOS + macOS оба получают deep links.** Требует:
  - iOS: `CFBundleURLTypes` в `BBTB/App/iOSApp/Info.plist` + `com.apple.developer.associated-domains: [applinks:import.bbtb.app]` в `BBTB/App/iOSApp/BBTB-iOS.entitlements`
  - macOS: `CFBundleURLTypes` в `BBTB/App/macOSApp/Info.plist` + `com.apple.developer.associated-domains: [applinks:import.bbtb.app]` в `BBTB/App/macOSApp/BBTB-macOS.entitlements`
  - Apple Developer Portal: Associated Domains checked для обоих App ID (галочка, без Configure кнопки).
  - `onOpenURL` или `NSApplicationDelegate.application(_:open:)` в обоих App entry points.

### Area D — Error UX

- **D-08: Alert при ошибке deep link.** SwiftUI `.alert` с локализованным текстом ошибки + кнопка «OK». Варианты ошибок: невалидный URL, отсутствует `url` параметр, ошибка импорта (сервер недоступен, пустой конфиг). Используем существующий `MainScreenViewModel` alert-механизм — не вводим новый.

- **D-09: Cold-start deep link.** Если приложение запускается через deep link (не foreground), нужно дождаться готовности `MainScreenViewModel` (после `applyInitialStatusSnapshot`) перед вызовом DeepLinkRouter. Иначе race с TunnelController init.

### Claude's Discretion

- Конкретная структура пакета `DeepLinks` (папки, target dependencies) — на усмотрение planner'а по аналогии с `RulesEngine` пакетом.
- Timeout и retry при недоступном сервере в `ImportHandler` — на усмотрение, аналогично `SubscriptionURLFetcher`.
- Порядок регистрации entitlements в Tuist / Xcode — следовать паттерну Phase 8 (`RulesEngine`).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements и Roadmap
- `.planning/REQUIREMENTS.md` §DEEP — DEEP-01..05 definitions (статус, что в scope, что deferred)
- `.planning/ROADMAP.md` §Phase 9 — Success criteria и scope (обновляется planner'ом)

### Существующий import flow
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift` — `importFromRawInput(_:source:)` — точка входа для DeepLinkRouter
- `BBTB/Packages/ConfigParser/Sources/ConfigParser/ConfigImporting.swift` — протокол `ConfigImporting`
- `BBTB/App/iOSApp/BBTB_iOSApp.swift` — где добавить `onOpenURL` + cold-start deep link handling
- `BBTB/App/macOSApp/BBTB_macOSApp.swift` — macOS аналог

### Архитектурные паттерны (скопировать для DeepLinks)
- `BBTB/Packages/ProtocolRegistry/` — паттерн extensible registry (protocol + register + lookup)
- `BBTB/Packages/RulesEngine/` — паттерн SwiftPM пакета с actor (RulesEngineCoordinator) — для структуры DeepLinks пакета

### Apple Developer Portal (внешнее, не в репо)
- Team ID: `UAN8W9Q82U`
- App ID iOS: `app.bbtb.client.ios`
- App ID macOS: `app.bbtb.client.macos`
- Capability: Associated Domains (галочка, без Configure) — для Universal Links нужна регистрация в Portal

### Предыдущие CONTEXT.md
- `.planning/phases/08-rules-engine-split-tunneling/08-CONTEXT.md` — паттерны Phase 8 (BGTask wiring, Actor init, App Group) применимы по аналогии

### Apple документация (концептуальная)
- AASA: `/.well-known/apple-app-site-association` — без расширения, Content-Type: application/json, HTTPS, per-subdomain
- Universal Links проверяются Apple CDN при установке/обновлении приложения — изменения могут занять время

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `ConfigImporter.importFromRawInput(_:source:)` — **главная точка входа**. DeepLinkRouter извлекает URL из параметра, передаёт как raw string. Вся обработка subscription URL, JSON endpoint, redirect-following — уже внутри.
- `ImportProgressOverlay` + `MainScreenViewModel` alert mechanism — готовый UI для отображения прогресса и ошибок импорта. DeepLinkRouter запускает тот же flow что и кнопка «Вставить».
- `ImportSource` enum — добавить кейс `.deepLink` для аналитики/логов.

### Established Patterns
- **ProtocolRegistry pattern** (protocol + register + lookup by identifier): копировать для `DeepLinkRouter`. Каждый `DeepLinkHandler` — отдельный struct, регистрируется при старте App.
- **DEC-06d-01 cold-start defer**: deep link handling НЕ должен вызываться до `applyInitialStatusSnapshot`. Хранить pending URL в App и обрабатывать после готовности VM.
- **NEVPNStatusDidChange XPC pitfall** (feedback_nevpn_xpc_mach_port.md): deep link не должен инициировать connect/disconnect синхронно в `onOpenURL` callback.

### Integration Points
- `BBTB_iOSApp.body` → `.onOpenURL { url in viewModel.handleDeepLink(url) }` — добавить модификатор
- `BBTB_macOSApp` → `NSApplicationDelegate.application(_:open:)` или `.onOpenURL` (SwiftUI)
- `MainScreenViewModel.handleDeepLink(_:)` — новый метод, вызывает `DeepLinkRouter`, показывает ImportProgressOverlay или Alert

</code_context>

<specifics>
## Specific Ideas

- **Marzban subscription URL как primary sharing mechanism**: пользователь копирует из панели Marzban `/sub/{token}` URL → оборачивает в `bbtb://import?url=https://panel.example.com/sub/abc123` → отправляет в Telegram → получатель тапает → BBTB открывается и импортирует все серверы этого пользователя.

- **Codex research (thread `019e2a7f-d023-7020-bc60-72ccb8116ba5`)** по server backend: рекомендовал Shlink (Docker, web UI, stable aliases) для v1+ токен-менеджмента. В v0.9 достаточно static AASA. При миграции домена (vergevsky.ru → bbtb.app): публичные ссылки ВСЕГДА через `import.bbtb.app`, панель Marzban остаётся приватной.

- **AASA компоненты Phase 9**: только `/import*` путь. Когда добавляется DEEP-03 в v1+ — добавить `{ "/": "/c/*" }` без изменения iOS/macOS кода.

</specifics>

<deferred>
## Deferred Ideas

- **DEEP-03** (`GET /c/{token}` endpoint) — v1+. Рекомендуемый стек: Shlink (Docker) + nginx proxy вместо redirect (чтобы скрыть Marzban URL). Архитектурная заглушка `TokenFetcher` protocol уже в пакете.
- **DEEP-04** (landing page для не-пользователей) — v1+ вместе с DEEP-03.
- **bbtb://connect** и **bbtb://disconnect** — deferred до появления реального use case (Shortcuts? Automation? Siri?).
- **Shlink** как token manager — Codex рекомендация для v1+ (Docker + nginx + web UI). Team ID + App ID известны.

</deferred>

---

*Phase: 9-Deep-Links*
*Context gathered: 2026-05-15*
