# Phase 9: Deep Links — Research

**Researched:** 2026-05-15
**Domain:** iOS/macOS deep-link handling (custom URL scheme + Universal Links), SwiftPM module scaffolding, AASA hosting
**Confidence:** HIGH (Apple-canonical mechanisms, hand-verified против codebase)

## Summary

Phase 9 строит **клиентский deep-link router** + **минимальный сервер AASA** для одной цели — открытие BBTB-приложения по тапу в Telegram/браузере на `bbtb://import?url=…` или `https://import.bbtb.app/import?url=…` с последующим импортом subscription URL. Скоуп урезан в CONTEXT.md scope-amendment: DEEP-03 (token endpoint) и DEEP-04 (landing page) перенесены в v1+ backlog; Phase 9 реализует DEEP-01, DEEP-02, DEEP-05.

**Главные технические факты:**

1. **macOS Universal Links не доставляются через `.onOpenURL`** — это критический pitfall, не задокументированный нигде кроме Apple Dev Forums. Custom scheme `bbtb://` приходит через `.onOpenURL` на обеих платформах; Universal Links — через `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`. Это требует **двух модификаторов** в obeих root views.
2. **DeepLinkRouter уже описан в `wiki/deep-links.md`** в виде Swift кода — но wiki upstream of code, она будет переписана в W1 как часть фазы. Архитектура: actor + `protocol DeepLinkHandler { canHandle / handle }` + регистрация per App init (паттерн ProtocolRegistry — verified в коде).
3. **`ConfigImporter.importFromRawInput(_:source:)`** — главная точка интеграции уже готова и принимает любой raw string. DeepLinkRouter извлекает `url` параметр, URL-decode'ит, передаёт. Никакого нового парсинга не нужно. Требуется **новый case `.deepLink` в `ImportSource` enum** (VPNCore/ParsedConfigs.swift:289) для аналитики.
4. **Cold-start race** реальна: если приложение запускается через deep link с холода, `.onOpenURL` приходит ДО `applyInitialStatusSnapshot` (W4 в BBTB_iOSApp). Решение — `pendingURL` поле в App + проброс в VM, который запускается после `applyInitialStatusSnapshot` (паттерн DEC-06d-01 cold-start defer).
5. **AASA на `import.bbtb.app`** — единственный серверный артефакт фазы. Static-hosted JSON по пути `/.well-known/apple-app-site-association` без расширения файла, Content-Type `application/json`, HTTPS обязательно, ≤128 KB. Apple CDN кеширует ~24 часа после установки/обновления. nginx или Cloudflare Pages — оба подходят. **Apple НЕ требует** publicly accessible сервер по пути `/import*`; для DEEP-01..02 v0.9 достаточно AASA + Universal Link landing (любой 200 OK, контент не важен — приложение перехватывает).

**Primary recommendation:** Создать SwiftPM пакет `DeepLinks` строго по образцу `RulesEngine` (DEC-06d-01 cold-start defer, actor coordinator с `Sendable`, инжектируемые зависимости через protocols). DeepLinkRouter — actor с `protocol DeepLinkHandler`, в Phase 9 регистрируется один `ImportHandler`. URL parsing через `URLComponents` + `URLQueryItem.value` (auto-percent-decode). Cold-start handled через `@State var pendingURL: URL?` в root view + flush после VM ready. AASA — static-hosted на nginx или Cloudflare Pages.

## User Constraints (from CONTEXT.md)

### Locked Decisions

**Area A — Серверная архитектура**

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
  - `RemoteTokenFetchHandler` — заглушка (не реализована, только `struct` с TODO)
  В v1+ planner реализует `RemoteTokenFetchHandler` через Shlink или прямой прокси к Marzban subscription URL.

**Area B — URL-дизайн**

- **D-04: `bbtb://import?url={subscription_url}` — единственный поддерживаемый формат v0.9.** `subscription_url` — любой URL, который `ConfigImporter.importFromRawInput()` уже умеет обрабатывать.
- **D-05: Extensible URL parsing.** `DeepLinkRouter` не делает один большой `switch` по scheme/host. Вместо этого: `protocol DeepLinkHandler { func canHandle(_ url: URL) -> Bool; func handle(_ url: URL) async throws }`. В Phase 9 — один `ImportHandler`. В v1+ — `TokenHandler` добавляется регистрацией.
- **D-06: connect/disconnect — deferred.** В Phase 9 нет `bbtb://connect` и `bbtb://disconnect`. `DeepLinkRouter` логирует unhandled URLs и возвращает ошибку с понятным сообщением.

**Area C — Платформы**

- **D-07: iOS + macOS оба получают deep links.** Требует:
  - iOS: `CFBundleURLTypes` в `BBTB/App/iOSApp/Info.plist` + `com.apple.developer.associated-domains: [applinks:import.bbtb.app]` в `BBTB/App/iOSApp/BBTB-iOS.entitlements`
  - macOS: `CFBundleURLTypes` в `BBTB/App/macOSApp/Info.plist` + `com.apple.developer.associated-domains: [applinks:import.bbtb.app]` в `BBTB/App/macOSApp/BBTB-macOS.entitlements`
  - Apple Developer Portal: Associated Domains checked для обоих App ID (галочка, без Configure кнопки).
  - `onOpenURL` или `NSApplicationDelegate.application(_:open:)` в обоих App entry points.

**Area D — Error UX**

- **D-08: Alert при ошибке deep link.** SwiftUI `.alert` с локализованным текстом ошибки + кнопка «OK». Варианты ошибок: невалидный URL, отсутствует `url` параметр, ошибка импорта (сервер недоступен, пустой конфиг). Используем существующий `MainScreenViewModel` alert-механизм — не вводим новый.
- **D-09: Cold-start deep link.** Если приложение запускается через deep link (не foreground), нужно дождаться готовности `MainScreenViewModel` (после `applyInitialStatusSnapshot`) перед вызовом DeepLinkRouter. Иначе race с TunnelController init.

### Claude's Discretion

- Конкретная структура пакета `DeepLinks` (папки, target dependencies) — на усмотрение planner'а по аналогии с `RulesEngine` пакетом.
- Timeout и retry при недоступном сервере в `ImportHandler` — на усмотрение, аналогично `SubscriptionURLFetcher`.
- Порядок регистрации entitlements в Tuist / Xcode — следовать паттерну Phase 8 (`RulesEngine`).

### Deferred Ideas (OUT OF SCOPE)

- **DEEP-03** (`GET /c/{token}` endpoint) — v1+. Рекомендуемый стек: Shlink (Docker) + nginx proxy. Архитектурная заглушка `TokenFetcher` protocol уже в пакете.
- **DEEP-04** (landing page для не-пользователей) — v1+ вместе с DEEP-03.
- **bbtb://connect** и **bbtb://disconnect** — deferred до появления реального use case (Shortcuts? Automation? Siri?).
- **Shlink** как token manager — Codex рекомендация для v1+.

## Phase Requirements

| ID | Description (from REQUIREMENTS.md) | Research Support |
|----|------------------------------------|------------------|
| DEEP-01 | Custom URL Scheme `bbtb://` (import/connect/disconnect) | § Pattern 1 (CFBundleURLTypes + `.onOpenURL`); v0.9 ограничено `bbtb://import?url=…` per D-04/D-06 |
| DEEP-02 | Universal Links через `import.bbtb.app` с AASA | § Pattern 2 (AASA + entitlement + `.onContinueUserActivity`); D-01/D-02 minimal AASA |
| DEEP-03 | Endpoint `/c/{token}` отдаёт конфиг | **DEFERRED v1+** per CONTEXT.md scope-amendment. Только архитектурная заглушка `TokenFetcher` protocol per D-03. |
| DEEP-04 | Landing page для отсутствующего приложения | **DEFERRED v1+** per CONTEXT.md scope-amendment. AASA достаточно — Apple перехватит установленное приложение, иначе откроется Safari (без landing page в v0.9). |
| DEEP-05 | `DeepLinkRouter` actor в модуле `DeepLinks` | § Pattern 3 (actor + `DeepLinkHandler` protocol — копия ProtocolRegistry паттерна, verified в коде) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| URL scheme registration (`bbtb://`) | Browser/Client (iOS/macOS app target Info.plist) | — | OS-level registration происходит ТОЛЬКО в main app bundle, не в extension и не в SwiftPM пакете |
| AASA hosting (`/.well-known/apple-app-site-association`) | External server (`import.bbtb.app` static hosting) | CDN/Static (Apple CDN кеширует на устройстве ~24h) | Чистый static file serve; не нуждается в backend logic; D-01 minimal scope |
| Associated Domains entitlement registration | Apple Developer Portal (off-repo) | App entitlements (iOS + macOS .entitlements files) | Portal capability checked ДО Xcode подписи entitlement-ом; обе стороны обязательны |
| DeepLinkRouter actor + DeepLinkHandler protocol | API/Backend (Swift SwiftPM `DeepLinks` package) | — | Pure-Swift business logic — actor isolation для thread-safety; следует ProtocolRegistry паттерну |
| `.onOpenURL` / `.onContinueUserActivity` modifier wiring | Frontend Server (SwiftUI App scene root view) | — | SwiftUI lifecycle binding — must live at App-level (BBTB_iOSApp / BBTB_macOSApp); CONTEXT.md D-07 |
| Cold-start pending URL buffering | Frontend Server (App state + VM ready signal) | — | DEC-06d-01 cold-start defer pattern — `@State var pendingURL` в RootView + flush после `applyInitialStatusSnapshot` per D-09 |
| Import execution (`ConfigImporter.importFromRawInput`) | API/Backend (AppFeatures/MainScreenFeature reused as-is) | Database/Storage (SwiftData via existing pipeline) | Уже existing pipeline — DeepLinkRouter лишь вызывает `importFromRawInput(_:source:)` с новым case `.deepLink` |
| Error UX (alert) | Frontend Server (existing `MainScreenViewModel.lastError`) | — | D-08 — reuse existing alert mechanism, не вводить новый |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (`URL`, `URLComponents`, `URLQueryItem`) | iOS 18 / macOS 15 SDK | URL парсинг с auto-percent-decoding | Apple-canonical; альтернатив нет в Phase 9 scope [CITED: developer.apple.com/documentation/foundation/urlcomponents] |
| SwiftUI `.onOpenURL(perform:)` | iOS 14+ / macOS 11+ (требуется iOS 18 + macOS 15 baseline) | Доставка custom-scheme URLs `bbtb://` | Apple-canonical для SwiftUI App lifecycle [CITED: developer.apple.com/documentation/swiftui/view/onopenurl(perform:)] |
| SwiftUI `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` | iOS 14+ / macOS 11+ | Доставка Universal Links HTTPS-ссылок | **Критично для macOS** — Universal Links НЕ приходят через `.onOpenURL` на macOS [CITED: developer.apple.com/forums/thread/673822] |
| Swift `actor` + `Sendable` (Swift 6 concurrency) | Swift 6.0 (codebase baseline) | Thread-safety для DeepLinkRouter | Существующий паттерн в codebase: RulesEngineCoordinator, TunnelController, SwiftDataFailoverProvider [VERIFIED: BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:109] |
| `OSLog` / `Logger` | iOS 14+ / macOS 11+ | Diagnostic logging unhandled URLs (D-06) | Существующий паттерн: `RulesEngineLogger.swift`, `TunnelLogger.swift` [VERIFIED: BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineLogger.swift] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Existing `ConfigImporter` (AppFeatures/MainScreenFeature) | Phase 7c | Импорт subscription URL — reuse | Каждый успешный deep link → `importer.importFromRawInput(decodedURL, source: .deepLink)` [VERIFIED: BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:123] |
| Existing `MainScreenViewModel.lastError` | Phase 6c+ | Alert UX для error states | D-08 — reuse, не вводить новый alert-механизм [VERIFIED: MainScreenViewModel.swift:79 — `@Published public var lastError: String?`] |
| Existing `ImportSource` enum (VPNCore) | Phase 2 | Source attribution для аналитики/логов | **Требуется добавить case `.deepLink`** [VERIFIED: BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift:289-295 — current cases: pasteboard, subscriptionURL(URL), jsonEndpoint(URL), qrCode, multilineText] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `URLComponents.queryItems` | `URLComponents.percentEncodedQuery` + manual decode | Manual decode позволяет catch'ить раздельно RFC 3986 violations, но усложняет код. Auto-decode достаточен для v0.9 в которой spec жёстко контролируется (`?url=…`). |
| Actor `DeepLinkRouter` | Singleton class with `NSLock` (как ProtocolRegistry) | `actor` лучше для Swift 6 strict concurrency и async pipeline (`handle` метод async). ProtocolRegistry — legacy паттерн Phase 1; RulesEngineCoordinator (Phase 8) уже использует `actor` как новый стандарт. |
| Wildcard scheme в Info.plist | Multiple schemes (`bbtb://`, `bbtbimport://`, etc.) | Apple одобряет один scheme на app для App Store review clarity. CONTEXT.md D-04 фиксирует `bbtb://`. |
| Hand-coded AASA generator | Use Branch.io SDK / similar third-party | Branch.io — overkill для статичного 6-line JSON. Self-hosted AASA — стандарт для apps уровня enterprise/опен-сорс. **D-01 говорит nginx static.** |
| `application(_:open:options:)` AppDelegate (UIKit-style) | `.onOpenURL` (SwiftUI) | Apple официально рекомендует `.onOpenURL` для @main SwiftUI apps; AppDelegate fallback нужен ТОЛЬКО при custom scene delegate (у нас нет) [CITED: developer.apple.com/forums/thread/748422] |

**Installation:**

Никаких внешних SwiftPM dependencies — Phase 9 использует только Foundation + SwiftUI + OSLog. Существующих библиотек codebase достаточно.

**Version verification:** Не применимо — все используемые APIs входят в iOS 18 / macOS 15 SDK baseline проекта (verified в `BBTB/Packages/*/Package.swift` — `platforms: [.iOS(.v18), .macOS(.v15)]`).

## Architecture Patterns

### System Architecture Diagram

```
External tap (Telegram, Safari, Mail, etc.)
        │
        │ bbtb://import?url=<encoded>
        │ — OR —
        │ https://import.bbtb.app/import?url=<encoded>
        ▼
┌─────────────────────────────────────────────────────────┐
│ iOS / macOS — system URL routing                        │
│                                                         │
│  bbtb://    ──→  CFBundleURLTypes match (Info.plist)    │
│                  → SwiftUI .onOpenURL(url)              │
│                                                         │
│  https://   ──→  AASA fetch (Apple CDN cache 24h)       │
│                  → applinks:import.bbtb.app match       │
│                  → SwiftUI .onContinueUserActivity      │
│                     (NSUserActivityTypeBrowsingWeb)     │
│                  → activity.webpageURL                  │
└─────────────────────────────────────────────────────────┘
        │
        │ URL value (both paths converge here)
        ▼
┌─────────────────────────────────────────────────────────┐
│ App root view (BBTB_iOSApp.body / BBTB_macOSApp.body)   │
│                                                         │
│  Cold-start check:                                      │
│    if vm.initialManagersApplied == false:               │
│      @State pendingURL = url    ← BUFFER                │
│    else:                                                │
│      vm.handleDeepLink(url)     ← FLUSH                 │
│                                                         │
│  After applyInitialStatusSnapshot():                    │
│    if pendingURL != nil:                                │
│      vm.handleDeepLink(pendingURL!) ; pendingURL = nil  │
└─────────────────────────────────────────────────────────┘
        │
        │ MainScreenViewModel.handleDeepLink(url)
        ▼
┌─────────────────────────────────────────────────────────┐
│ MainScreenViewModel (existing actor on MainActor)       │
│                                                         │
│  func handleDeepLink(_ url: URL) {                      │
│    Task { @MainActor in                                 │
│      do {                                               │
│        try await deepLinkRouter.handle(url)             │
│      } catch {                                          │
│        lastError = error.localizedDescription           │
│        // existing alert mechanism (D-08)               │
│      }                                                  │
│    }                                                    │
│  }                                                      │
└─────────────────────────────────────────────────────────┘
        │
        │ deepLinkRouter.handle(url)
        ▼
┌─────────────────────────────────────────────────────────┐
│ DeepLinkRouter (actor, NEW pkg `DeepLinks`)             │
│                                                         │
│  Registered handlers (D-05 extensibility):              │
│    • ImportHandler (Phase 9)                            │
│    • RemoteTokenFetchHandler ← stub (D-03, for v1+)     │
│                                                         │
│  for h in handlers:                                     │
│    if h.canHandle(url):                                 │
│      try await h.handle(url)                            │
│      return                                             │
│  throw DeepLinkError.unhandled                          │
└─────────────────────────────────────────────────────────┘
        │
        │ ImportHandler.handle(url)
        ▼
┌─────────────────────────────────────────────────────────┐
│ ImportHandler (Phase 9, single concrete handler)        │
│                                                         │
│  1. URLComponents(url) → queryItem name=="url"          │
│  2. Decoded value (auto-percent-decode)                 │
│  3. Validate non-empty, looks like URL                  │
│  4. ConfigImporter.importFromRawInput(                  │
│       decoded, source: .deepLink)                       │
│  5. Returns ImportResult or throws                      │
└─────────────────────────────────────────────────────────┘
        │
        │ existing pipeline (Phase 2+)
        ▼
┌─────────────────────────────────────────────────────────┐
│ ConfigImporter — existing universal import pipeline     │
│ (Phase 2 / IMP-04)                                      │
│                                                         │
│  Subscription URL fetch → parse → merge into SwiftData  │
│  → provisionTunnelProfile → notify VM via refresh      │
│                                                         │
│  Errors (network, parse, empty) bubble up to            │
│  MainScreenViewModel.lastError → SwiftUI .alert         │
└─────────────────────────────────────────────────────────┘
```

### Recommended Project Structure

Следовать паттерну `RulesEngine` (Phase 8, verified working):

```
BBTB/
├── Packages/
│   └── DeepLinks/                       ← NEW в W1
│       ├── Package.swift                ← swift-tools-version 6.0, iOS 18 / macOS 15
│       ├── Sources/
│       │   └── DeepLinks/
│       │       ├── DeepLinkRouter.swift       ← actor, главный API
│       │       ├── DeepLinkHandler.swift      ← protocol (D-05)
│       │       ├── DeepLinkError.swift        ← enum LocalizedError
│       │       ├── DeepLinksLogger.swift      ← Logger wrapper (mirror RulesEngineLogger)
│       │       ├── Handlers/
│       │       │   ├── ImportHandler.swift          ← Phase 9 concrete (DEEP-01/02)
│       │       │   └── RemoteTokenFetchHandler.swift ← stub (D-03, v1+ placeholder)
│       │       └── TokenFetcher.swift         ← protocol placeholder (D-03)
│       └── Tests/
│           └── DeepLinksTests/
│               ├── DeepLinkRouterTests.swift
│               ├── ImportHandlerTests.swift
│               └── URLParsingTests.swift
├── App/
│   ├── iOSApp/
│   │   ├── BBTB_iOSApp.swift            ← + DeepLinkRouter init + .onOpenURL + .onContinueUserActivity
│   │   ├── BBTB-iOS.entitlements        ← + com.apple.developer.associated-domains
│   │   └── Info.plist                   ← + CFBundleURLTypes (bbtb://)
│   └── macOSApp/
│       ├── BBTB_macOSApp.swift          ← same as iOS
│       ├── BBTB-macOS.entitlements      ← + associated-domains
│       └── Info.plist                   ← + CFBundleURLTypes (bbtb://)
└── Project.swift                        ← + .package(path: "Packages/DeepLinks") + product import

server (off-repo, hosted separately):
└── import.bbtb.app/
    └── /.well-known/
        └── apple-app-site-association   ← JSON, no extension, Content-Type application/json
```

### Pattern 1: Custom URL Scheme registration (`bbtb://`)

**What:** Регистрируем custom URL scheme в Info.plist обоих app targets. iOS/macOS система при тапе на `bbtb://...` URL находит приложение через `CFBundleURLTypes` и доставляет URL в `.onOpenURL`.

**When to use:** DEEP-01. Phase 9 W2 (Info.plist edits) + W3 (.onOpenURL wiring).

**iOS Info.plist:**
```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>app.bbtb.client.ios.url</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>bbtb</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
  </dict>
</array>
```

**macOS Info.plist** — идентичный блок, только `CFBundleURLName` = `app.bbtb.client.macos.url`.

**SwiftUI binding:**
```swift
// Source: developer.apple.com/documentation/swiftui/view/onopenurl(perform:)
// Verified pattern in this codebase: будет добавлен в BBTB_iOSApp.body
WindowGroup {
    BBTBRootView(viewModel: viewModel, ...)
        .onOpenURL { url in
            viewModel.handleDeepLink(url)   // ⚠ cold-start gating handled внутри (Pattern 4)
        }
}
```

### Pattern 2: Universal Links (`https://import.bbtb.app/import?...`)

**What:** Двусторонний контракт между app entitlement и AASA-файлом на домене. При установке/обновлении приложения система проверяет AASA через Apple CDN и кеширует результат. Тап на HTTPS-ссылку из совпадающего домена открывает приложение.

**When to use:** DEEP-02. Phase 9 W2 (entitlements + AASA file) + W3 (.onContinueUserActivity wiring) + W4 (Apple Developer Portal capability registration).

**Entitlement (iOS + macOS, идентичный):**
```xml
<!-- BBTB/App/iOSApp/BBTB-iOS.entitlements + BBTB-macOS.entitlements -->
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:import.bbtb.app</string>
</array>
```

**AASA file content** — точно по CONTEXT.md D-02:
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

**AASA hosting requirements:** [CITED: developer.apple.com/documentation/xcode/supporting-associated-domains]
- URL: `https://import.bbtb.app/.well-known/apple-app-site-association` (точно этот путь; без расширения файла)
- Content-Type: `application/json` (обязательно — иначе Apple отвергнет)
- HTTPS обязательно — без HTTP fallback
- Размер ≤ 128 KB (наш ≈ 250 байт)
- Без redirects (Apple CDN не следует за 301/302)
- TLS 1.2+ (нам нужен валидный сертификат — Let's Encrypt или Cloudflare)

**SwiftUI binding** — критическая разница iOS vs macOS:

```swift
// Source: developer.apple.com/forums/thread/673822 — macOS не приходит .onOpenURL для Universal Links!
// Therefore: ОБА modifier'а нужны на обеих платформах для consistency
BBTBRootView(viewModel: viewModel, ...)
    .onOpenURL { url in
        // bbtb:// scheme — iOS + macOS обе работают
        viewModel.handleDeepLink(url)
    }
    .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
        // Universal Links — единственный надёжный путь для macOS
        // На iOS дублирует .onOpenURL для https:// тоже работает но эта точка
        // канонична для NSUserActivity-based Universal Links
        guard let url = activity.webpageURL else { return }
        viewModel.handleDeepLink(url)
    }
```

**Apple Developer Portal regstration** (off-repo, manual step):
1. Войти в [developer.apple.com](https://developer.apple.com) → Certificates, IDs & Profiles → Identifiers
2. Для App ID `app.bbtb.client.ios`: edit → отметить «Associated Domains» checkbox (без Configure кнопки в современном Portal UI — просто галочка) → Save
3. Повторить для `app.bbtb.client.macos`
4. **Не нужно** регенерировать provisioning profile (automatic signing подхватит изменение)

**Apple CDN behavior:** [VERIFIED: developer.apple.com/documentation/Xcode/supporting-associated-domains]
- При первой установке приложения iOS/macOS делает запрос к Apple CDN, который проксирует AASA с домена
- CDN кеш — до 24 часов
- Для тестинга изменений AASA — добавить `?mode=developer` к entitlement: `applinks:import.bbtb.app?mode=developer` (bypass CDN cache, идёт прямо к домену)
- Production entitlement (без `?mode=developer`) — обязателен в App Store builds

### Pattern 3: DeepLinkRouter — actor + DeepLinkHandler protocol (D-05)

**What:** Сердце `DeepLinks` пакета. Actor хранит ordered list of `DeepLinkHandler` (по приоритету регистрации), при `handle(url)` итерирует пока не найдёт `canHandle(url) == true`.

**When to use:** DEEP-05. Phase 9 W1 — основной API package.

**Verified codebase pattern:** ProtocolRegistry.swift (lookup by identifier) + RulesEngineCoordinator (actor + Sendable + injectable deps). Мы комбинируем: extensible registry (от ProtocolRegistry) внутри actor (от RulesEngineCoordinator).

**Source code:**

```swift
// Source: composed from ProtocolRegistry.swift:6-26 + RulesEngineCoordinator.swift:109-183
// (VERIFIED both files in BBTB/Packages/)
import Foundation
import os

/// Protocol для регистрируемых обработчиков deep-link URLs (D-05 extensibility).
///
/// Каждый handler — отдельный struct, регистрируется в `DeepLinkRouter` при старте app.
/// Порядок регистрации = порядок попыток `canHandle` (first match wins).
public protocol DeepLinkHandler: Sendable {
    /// Stable identifier для логирования и тестов.
    static var identifier: String { get }

    /// Quick non-throwing проверка соответствия URL этому handler'у.
    /// Должна быть pure-функция: scheme/host/path inspection без I/O.
    func canHandle(_ url: URL) -> Bool

    /// Реальная обработка. Async чтобы handler мог делать network/SwiftData операции.
    /// Throws `DeepLinkError` или передаёт ошибки нижележащих слоёв (ConfigImporter).
    func handle(_ url: URL) async throws
}

/// Главный API пакета. Actor — Swift 6 strict-concurrency-safe.
public actor DeepLinkRouter {
    private var handlers: [any DeepLinkHandler] = []

    public init() {}

    /// Регистрация handler'а. Вызывается из BBTB_*App.init() — один раз на старте.
    /// Порядок имеет значение: первый найденный canHandle == true берёт URL.
    public func register(_ handler: any DeepLinkHandler) {
        handlers.append(handler)
        DeepLinksLogger.router.notice(
            "registered handler=\(type(of: handler).identifier, privacy: .public)"
        )
    }

    /// Главная entry-point. Вызывается MainScreenViewModel.handleDeepLink(url).
    /// Возвращается успешно при первом матчующем handler'е.
    /// Бросает .unhandled если ни один handler не canHandle.
    public func handle(_ url: URL) async throws {
        DeepLinksLogger.router.notice(
            "handle url=\(url.absoluteString, privacy: .public)"
        )
        for h in handlers {
            if h.canHandle(url) {
                try await h.handle(url)
                return
            }
        }
        DeepLinksLogger.router.error(
            "unhandled url=\(url.absoluteString, privacy: .public)"
        )
        throw DeepLinkError.unhandled(url)
    }
}

public enum DeepLinkError: Error, LocalizedError, Sendable {
    case unhandled(URL)
    case missingQueryParameter(name: String)
    case invalidParameterValue(name: String, reason: String)
    case importFailed(underlying: String)

    public var errorDescription: String? {
        switch self {
        case .unhandled(let url):
            return "Не удалось обработать ссылку: \(url.absoluteString)"
        case .missingQueryParameter(let name):
            return "В ссылке отсутствует параметр «\(name)»"
        case .invalidParameterValue(let name, let reason):
            return "Параметр «\(name)» некорректен: \(reason)"
        case .importFailed(let underlying):
            return "Импорт не удался: \(underlying)"
        }
    }
}
```

### Pattern 4: Cold-start deep link buffering (D-09)

**What:** При cold-start через deep link `.onOpenURL` приходит ДО того как `applyInitialStatusSnapshot` выполнился. Если вызвать `handleDeepLink` сразу — ConfigImporter и TunnelController могут быть ещё не готовы (race с launch-time Task chain в `BBTB_iOSApp.init`).

**When to use:** D-09. Phase 9 W3. Применим как к `.onOpenURL`, так и к `.onContinueUserActivity`.

**Verified codebase pattern:** DEC-06d-01 cold-start defer (Phase 6d). См. `BBTB_iOSApp.swift:145-158` — launch-time Task chain → `applyInitialStatusSnapshot(snapshot)`.

**Source code:**

```swift
// Source: composed from DEC-06d-01 pattern + Apple developer.apple.com/forums/thread/21129
// (cold-start URL receipt timing)
private struct BBTBRootView: View {
    @ObservedObject var viewModel: MainScreenViewModel
    let rulesCoordinator: RulesEngineCoordinator
    let deepLinkRouter: DeepLinkRouter   // ← NEW

    @State private var pendingDeepLink: URL?

    var body: some View {
        NavigationStack { /* ... existing ... */ }
            .onOpenURL { url in
                routeOrBuffer(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                routeOrBuffer(url)
            }
            .task {
                // Existing wiring code (settingsVM.wireRulesCoordinator,
                // viewModel.wireRulesCoordinator). VM signals readiness
                // through `initialManagersApplied` after applyInitialStatusSnapshot.
                await settingsVM.wireRulesCoordinator(rulesCoordinator)
                await viewModel.wireRulesCoordinator(rulesCoordinator)
                // ⚠ NEW: flush pending deep link if any
                if let pending = pendingDeepLink {
                    pendingDeepLink = nil
                    viewModel.handleDeepLink(pending, router: deepLinkRouter)
                }
            }
    }

    @MainActor
    private func routeOrBuffer(_ url: URL) {
        // initialManagersApplied отражает готовность VM (после applyInitialStatusSnapshot).
        // Если ещё не готова — буферим URL для flush в .task.
        if viewModel.initialManagersApplied {
            viewModel.handleDeepLink(url, router: deepLinkRouter)
        } else {
            pendingDeepLink = url
        }
    }
}
```

**Альтернативная стратегия (отвергнута):** хранить pendingURL внутри `DeepLinkRouter` actor. Минус — actor не знает о состоянии VM, и нет clean signal для flush. View-level `@State` + проверка VM-ready через existing flag — проще и follows DEC-06d-01 pattern.

### Pattern 5: ImportHandler — `bbtb://import?url=…` (DEEP-01/02 D-04)

**What:** Единственный концретный `DeepLinkHandler` в Phase 9. Парсит URL, извлекает `url` query parameter, передаёт в `ConfigImporter.importFromRawInput(_:source:)` с новым case `.deepLink`.

**When to use:** Phase 9 W1.

**Source code:**

```swift
// Source: composed from CONTEXT.md D-04 + ConfigImporting.swift:26 + ParsedConfigs.swift:289
import Foundation
import ConfigParser
import VPNCore

public struct ImportHandler: DeepLinkHandler {
    public static let identifier = "import"

    private let importer: ConfigImporting

    public init(importer: ConfigImporting) {
        self.importer = importer
    }

    public func canHandle(_ url: URL) -> Bool {
        // bbtb://import?url=...     → host == "import"
        // https://import.bbtb.app/import?url=...
        //   → host == "import.bbtb.app", path == "/import" (или начинается с)
        let scheme = url.scheme?.lowercased()
        if scheme == "bbtb", url.host?.lowercased() == "import" {
            return true
        }
        if scheme == "https",
           url.host?.lowercased() == "import.bbtb.app",
           url.path.hasPrefix("/import") {
            return true
        }
        return false
    }

    public func handle(_ url: URL) async throws {
        // URLComponents auto-decodes percent-encoded query values
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw DeepLinkError.invalidParameterValue(name: "url", reason: "не URL")
        }
        guard let urlItem = components.queryItems?.first(where: { $0.name == "url" }),
              let rawValue = urlItem.value, !rawValue.isEmpty
        else {
            throw DeepLinkError.missingQueryParameter(name: "url")
        }
        // Validate that rawValue is plausibly a URL (avoid passing нечитаемый мусор в importer)
        guard URL(string: rawValue) != nil else {
            throw DeepLinkError.invalidParameterValue(name: "url", reason: "не похоже на URL")
        }
        do {
            _ = try await importer.importFromRawInput(rawValue, source: .deepLink)
        } catch {
            throw DeepLinkError.importFailed(underlying: error.localizedDescription)
        }
    }
}
```

**Required change в `VPNCore/ParsedConfigs.swift`:**
```swift
public enum ImportSource: Sendable, Equatable {
    case pasteboard
    case subscriptionURL(URL)
    case jsonEndpoint(URL)
    case qrCode
    case multilineText
    case deepLink    // ← NEW Phase 9 DEEP-01
}
```

**Switch exhaustiveness gate:** Поиск всех switch sites над `ImportSource` (Phase 4 D-14 паттерн). На основе grep`importFromRawInput.*source` и `case .pasteboard` codebase audit (см. § Pitfall 4).

### Pattern 6: AASA static hosting

**What:** Сервер `import.bbtb.app` отдаёт ровно один статичный JSON по точному пути. Никакого backend logic. Nginx или Cloudflare Pages — обе работают.

**When to use:** Phase 9 W2 — параллельно с entitlements.

**Option A — nginx (рекомендую):**

```nginx
# /etc/nginx/sites-available/import.bbtb.app
server {
    listen 443 ssl http2;
    server_name import.bbtb.app;

    ssl_certificate /etc/letsencrypt/live/import.bbtb.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/import.bbtb.app/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # AASA — точный путь, корректный MIME type
    location = /.well-known/apple-app-site-association {
        default_type application/json;
        alias /var/www/import.bbtb.app/apple-app-site-association;
        # iOS не любит редиректы для AASA — выдаём 200 напрямую
        add_header Cache-Control "public, max-age=3600";
    }

    # Default 404 для всех остальных путей (DEEP-03/04 deferred — landing page нет в v0.9)
    location / {
        return 404;
    }
}
```

**Option B — Cloudflare Pages:**
1. Создать репозиторий `bbtb-aasa` (private OK) с одним файлом `public/.well-known/apple-app-site-association`
2. Cloudflare Pages → connect repo → build command (none, static)
3. Custom domain → `import.bbtb.app` (Cloudflare auto-provisions TLS)
4. Headers через `_headers` файл: `/.well-known/apple-app-site-association` → `Content-Type: application/json`

**Verification (после deploy):**
```bash
# Точный путь без редиректов, правильный MIME, валидный JSON
curl -I https://import.bbtb.app/.well-known/apple-app-site-association
# Expected:
#   HTTP/2 200
#   content-type: application/json
#   content-length: ~250

# Apple's debug endpoint (CDN-bypassed) для проверки swcd-валидации
curl "https://app-site-association.cdn-apple.com/a/v1/import.bbtb.app"
# Expected: same JSON, processed by Apple
```

### Anti-Patterns to Avoid

- **`.onOpenURL` для Universal Links на macOS:** не работает — нужен `.onContinueUserActivity`. Применять оба модификатора параллельно.
- **AppDelegate `application(_:open:options:)` с SwiftUI @main:** Apple официально рекомендует `.onOpenURL`; AppDelegate требуется только при custom scene delegate. В нашей кодовой базе scene delegate нет, поэтому используем чистый SwiftUI путь.
- **Singleton DeepLinkRouter (как ProtocolRegistry):** ProtocolRegistry — legacy Phase 1 паттерн с `@unchecked Sendable + NSLock`. Для Phase 9 используем `actor` (как RulesEngineCoordinator) — современный Swift 6 strict-concurrency-friendly путь.
- **Прямой вызов `ConfigImporter` из DeepLinkRouter:** RouterImpl не должен знать про ConfigImporter напрямую — это обязанность `ImportHandler`. Roundtrip через handler сохраняет extensibility (D-05) для будущих handlers.
- **Хранить pendingURL в actor:** worse than view-level `@State` — actor не знает о VM-ready signal, и flush требует polling или callback. `@State var pendingURL` + check `viewModel.initialManagersApplied` — простой и DEC-06d-01-compliant путь.
- **Регистрация AASA с wildcard `"/": "*"`:** избегаем — слишком широкий match даст Apple-side warnings и потенциально перехватит чужие подпути. Используем точный `"/": "/import*"` per D-02.
- **HTTP redirects на AASA:** Apple CDN не следует за 301/302 для AASA. Серверный конфиг должен отдавать 200 напрямую.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| URL parsing with percent-decoding | Manual `String.replacingOccurrences` или regex | `URLComponents` + `URLQueryItem.value` (auto-decoded) | URLComponents handles RFC 3986 edge cases (плюсы, multibyte, encoded reserved chars) согласно стандарту; manual parsing ломается на subscription URLs из реальных Marzban-панелей |
| Subscription URL fetch / parse / merge | Новый handler для fetch+parse в `ImportHandler` | `ConfigImporter.importFromRawInput(_:source:)` (existing) | Уже handles base64-encoded body, plain text URI list, JSON endpoint, Clash YAML — все ребусы что мы уже встречали (IMP-04/05). DeepLinkRouter лишь обёртка над existing pipeline. |
| Thread-safe handler registry | NSLock + dictionary (как ProtocolRegistry) | Swift `actor` | actor — Swift 6 native, нет risk что забудем `lock.unlock()` defer; integrates с async/await pipeline без callback marshaling |
| Cold-start URL race detection | Polling VM state + sleep | `@State var pendingURL` + flush в `.task` after `wireRulesCoordinator` | DEC-06d-01 pattern (verified в Phase 6d/8); event-driven; не блокирует main thread |
| AASA file generation | Скрипт генерирующий JSON | Hand-edited 6-line JSON (CONTEXT.md D-02) | Только один статичный файл, который меняется ≤2 раза за весь проект (в v1+ когда добавится `/c/*`) |
| Alert UX для deep-link errors | Новый AlertController | Existing `MainScreenViewModel.lastError` + `state = .error(message: …)` | D-08 — единый user-facing alert mechanism, согласован с pasteboard/QR import error flow |

**Key insight:** Phase 9 — про **routing**, не про **бизнес-логику**. Вся complexity (subscription parse, SwiftData merge, tunnel provisioning) уже existing в `ConfigImporter`. Если pull request к DeepLinks пакету добавляет >150 строк нового бизнес-кода — это сигнал переосмыслить дизайн.

## Common Pitfalls

### Pitfall 1: macOS Universal Links не приходят через `.onOpenURL`

**What goes wrong:** На macOS тап на `https://import.bbtb.app/import?url=…` открывает приложение, но `.onOpenURL` НЕ вызывается. URL теряется. На iOS — работает (`.onOpenURL` получает HTTPS URL).

**Why it happens:** [CITED: developer.apple.com/forums/thread/673822] macOS SwiftUI routes Universal Links через `NSUserActivity` (browse-web type), а не через `.onOpenURL`. Это не баг — это by-design API split, но он не очевиден из SwiftUI документации `.onOpenURL`.

**How to avoid:** **Всегда применять оба модификатора в каждом root view:**
```swift
.onOpenURL { url in viewModel.handleDeepLink(url) }
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    guard let url = activity.webpageURL else { return }
    viewModel.handleDeepLink(url)
}
```

**Warning signs:** macOS UAT — тап на Universal Link из Safari открывает app, но импорт не запускается; в Console.app для subsystem `app.bbtb.client` нет логов от `DeepLinksLogger`. На iOS то же действие работает — это диагностический сигнал что мы попали в этот pitfall.

### Pitfall 2: AASA cache TTL до 24 часов — изменения не видны сразу

**What goes wrong:** После публикации AASA или изменения content приложение всё ещё открывает Universal Links по старому набору `components`.

**Why it happens:** [CITED: developer.apple.com/documentation/Xcode/supporting-associated-domains] Apple CDN кеширует AASA до 24 часов с момента fetch. Свежий fetch происходит при install/update приложения и периодически — без guaranteed schedule.

**How to avoid:**
1. Для разработки добавить `?mode=developer` к entitlement: `applinks:import.bbtb.app?mode=developer`. Это говорит swcd (system daemon) НЕ кешировать и идти прямо к домену каждый раз. Только для Debug-сборки.
2. Production entitlement (без `?mode=developer`) — обязателен в App Store/TestFlight build.
3. Если в production обнаружится bad AASA — admin меняет version в URL path (например `applinks:import.bbtb.app/v2`) — но в Phase 9 не нужен, AASA минимальный.

**Warning signs:** На свежей установке Universal Link работает, на повторной установке — нет. Изменили AASA, на устройстве через 5 минут изменение не подхватилось. Debug device should test с `?mode=developer`.

### Pitfall 3: ImportSource switch exhaustiveness — забыть обновить

**What goes wrong:** Добавление `case .deepLink` в `ImportSource` enum ломает `switch` sites которые ранее были exhaustive без `default`. Compiler warning, но в Phase 4 D-14 был аналогичный bug — `VPNCoreTests/ParsedConfigsTests.swift` exhaustiveness gate не был обновлён под `.tuic` case (он был 9-й switch site).

**Why it happens:** ImportSource — крупный enum (5 cases пред-Phase 9), используется в parser, UI, importer, tests. `switch` без `default` — exhaustive — становится non-exhaustive при добавлении case.

**How to avoid:**
1. Перед коммитом enum changes — `grep -rn "case .pasteboard" BBTB/` чтобы найти все switch sites.
2. Каждый switch обновить либо новым case, либо `default` (если case не релевантен).
3. Запустить `tuist generate && xcodebuild -workspace BBTB.xcworkspace ...` чтобы поймать compile warning'и на early stage.
4. Phase 9 W1 first task — grep audit + targeted updates.

**Warning signs:** Compiler warning `Switch must be exhaustive` или silent fallthrough в tests где `.deepLink` case не учтён.

### Pitfall 4: Cold-start race — `handleDeepLink` до VM ready

**What goes wrong:** Приложение запускается через тап на `bbtb://import?url=…`. `.onOpenURL` fires immediately. `viewModel.handleDeepLink` запускается до того как `applyInitialStatusSnapshot` выполнился (cold-start ordered Task chain в `BBTB_iOSApp.init:145-158` ещё не дошла до этого шага). Результат: `ConfigImporter` ещё не имеет cachedManager, `TunnelController.bootstrap` не дал snapshot, `provisionTunnelProfile` может race с initial NEVPNStatus observer.

**Why it happens:** SwiftUI вызывает `.onOpenURL` синхронно при первом рендере root view — это раньше чем `.task` modifiers и до того как WG launch-time Task chain опубликовала результаты.

**How to avoid:** Pattern 4 — `@State var pendingURL: URL?` + check `viewModel.initialManagersApplied` (existing flag в VM, set true в `applyInitialStatusSnapshot:548`). Flush в `.task` после `wireRulesCoordinator`. Same DEC-06d-01 pattern.

**Warning signs:** UAT: cold-launch через deep link иногда работает, иногда нет (flaky). В логах: `DeepLinksLogger.router.notice` fires, но `ConfigImporter.importFromRawInput` падает с network timeout или странной race ошибкой.

### Pitfall 5: bbtb://import?url=… с уже-encoded URL — двойное декодирование

**What goes wrong:** Внешний tool (Telegram bot, web generator) генерирует `bbtb://import?url=https%3A%2F%2Fpanel.example.com%2Fsub%2Fabc123`. URLComponents auto-decodes, мы получаем `https://panel.example.com/sub/abc123` — OK. Но если генератор сделает ДВОЙНОЕ encoding (`url=https%253A%252F...`), результат после auto-decode будет `https%3A%2F%2F...` — невалидный URL.

**Why it happens:** Telegram/Safari/copy-paste разные пути могут добавить лишний слой percent-encoding если автор generator не понимает RFC 3986.

**How to avoid:**
1. В `ImportHandler.handle` после извлечения `rawValue` валидировать `URL(string: rawValue) != nil`.
2. Документировать в wiki + landing page примеры правильного encoding: один проход URLEncode и точка.
3. **НЕ делать** doubl-decode в коде — это маскирует bug на генераторе. Лучше выдать пользователю ошибку «параметр некорректен».

**Warning signs:** Пользователь сообщает «у меня deep link не работает», в логах `DeepLinkError.invalidParameterValue(name: "url", reason: "не похоже на URL")`. Решение — фикс генератор.

### Pitfall 6: Custom scheme conflict с другими приложениями

**What goes wrong:** Если другое приложение зарегистрировало `bbtb://` scheme раньше нашего, iOS / macOS поведение undefined (на iOS — usually первое установленное приложение wins; на macOS — последнее).

**Why it happens:** Custom URL schemes — global namespace без enforcement. `bbtb` короткий и потенциально collision-prone.

**How to avoid:**
1. CONTEXT.md уже зафиксировал `bbtb://` — нельзя менять. Verified что `bbtb` не зарегистрирован у известных приложений (не conflict с `vless://`, `trojan://`, `clash://`, etc.).
2. Universal Links (DEEP-02) — primary path и они НЕ имеют этой проблемы (привязаны к unique domain).
3. Custom scheme — secondary path, для пользователей которые тапают `bbtb://` из Telegram без установленной DNS-resolution / web routing.

**Warning signs:** iOS показывает другое приложение при тапе на `bbtb://` — пользователь сам ставил какое-то приложение с тем же scheme. Документировать в FAQ как known limitation.

### Pitfall 7: Apple Developer Portal capability — missing checkbox

**What goes wrong:** Entitlement `com.apple.developer.associated-domains` стоит в .entitlements файле, но в Apple Developer Portal у App ID `app.bbtb.client.ios` не отмечена Associated Domains capability. Результат — code signing проходит (Xcode automatic signing), но Apple CDN никогда не отдаёт AASA для этого App ID → Universal Links silently не работают.

**Why it happens:** Apple Portal capability и entitlement — два independent registrations. Code-sign checks только entitlement; CDN — только portal capability.

**How to avoid:**
1. Phase 9 W4 task — manual checkbox toggle в Apple Developer Portal для обоих App ID. Документировать в UAT checklist.
2. Verification: на свежей установке (или после `?mode=developer` в Debug) проверить что AASA fetch удался: Console.app → filter "swcd" → look for entries про import.bbtb.app.

**Warning signs:** Custom scheme `bbtb://` работает, но Universal Link `https://import.bbtb.app/import?...` открывает только Safari (не приложение). Если pingback в Console.app показывает «swcd: failed to fetch AASA» — capability в Portal не активна.

## Code Examples

### Example 1: Полный BBTB_iOSApp.body integration

```swift
// Source: composed from BBTB_iOSApp.swift:232-244 + Pattern 4 cold-start defer
// (VERIFIED via Read in this research session)
var body: some Scene {
    WindowGroup {
        BBTBRootView(viewModel: viewModel,
                     rulesCoordinator: rulesCoordinator,
                     deepLinkRouter: deepLinkRouter)   // ← NEW propagation
            .onAppear {
                PerfSignposter.app.endInterval("ColdLaunch", coldLaunchState)
            }
    }
    .modelContainer(modelContainer)
}

private struct BBTBRootView: View {
    @ObservedObject var viewModel: MainScreenViewModel
    let rulesCoordinator: RulesEngineCoordinator
    let deepLinkRouter: DeepLinkRouter        // ← NEW
    @State private var pendingDeepLink: URL?  // ← NEW (Pattern 4)
    @State private var showSettings = false
    @StateObject private var settingsVM = SettingsViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            MainScreenView(viewModel: viewModel, onOpenSettings: { showSettings = true })
                .navigationDestination(isPresented: $showSettings) {
                    SettingsView(viewModel: settingsVM)
                }
        }
        .task {
            await settingsVM.wireRulesCoordinator(rulesCoordinator)
            await viewModel.wireRulesCoordinator(rulesCoordinator)
            // NEW: flush pending deep link if any (Pattern 4)
            if let pending = pendingDeepLink {
                pendingDeepLink = nil
                viewModel.handleDeepLink(pending, router: deepLinkRouter)
            }
        }
        // NEW Pattern 1 — custom scheme delivery
        .onOpenURL { url in
            routeOrBuffer(url)
        }
        // NEW Pattern 2 — Universal Links delivery (BOTH platforms; Pitfall 1)
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            guard let url = activity.webpageURL else { return }
            routeOrBuffer(url)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { @MainActor in await viewModel.handleForegroundReentry() }
            Task { @MainActor in await foregroundSanityFetch() }
        }
    }

    @MainActor
    private func routeOrBuffer(_ url: URL) {
        if viewModel.initialManagersApplied {
            viewModel.handleDeepLink(url, router: deepLinkRouter)
        } else {
            pendingDeepLink = url
        }
    }

    @MainActor
    private func foregroundSanityFetch() async { /* ... existing ... */ }
}
```

### Example 2: MainScreenViewModel.handleDeepLink

```swift
// Source: composed from MainScreenViewModel.swift:385 (importFromPasteboard pattern) +
//         CONTEXT.md D-08 (reuse existing alert)
@MainActor
extension MainScreenViewModel {
    /// Phase 9 / DEEP-05 — entry point из root view's .onOpenURL и .onContinueUserActivity.
    /// Routes URL через `DeepLinkRouter` actor; ошибки оседают в `lastError` →
    /// existing SwiftUI .alert binding (D-08).
    public func handleDeepLink(_ url: URL, router: DeepLinkRouter) {
        Task { @MainActor in
            lastError = nil
            importInProgress = true   // reuse spinner UI from pasteboard import path
            defer { importInProgress = false }
            do {
                try await router.handle(url)
                // success — ConfigImporter уже обновил state via refresh() inside
                await refresh()
            } catch {
                lastError = error.localizedDescription
                // Существующий error pattern из performImport: переход в .error
                // только если есть какой-то supported config — иначе остаёмся .empty
                if supportedConfigCount > 0 {
                    state = .error(message: error.localizedDescription)
                }
            }
        }
    }
}
```

### Example 3: BBTB_iOSApp.init — регистрация DeepLinks

```swift
// Source: composed from BBTB_iOSApp.swift:39-228 (ProtocolRegistry + RulesEngineCoordinator
//         registration patterns) + Pattern 3 (DeepLinkRouter actor)
init() {
    // ... existing ProtocolRegistry / TransportRegistry / SwiftData / TunnelController setup ...

    // Phase 9 / DEEP-05 — DeepLinkRouter init + handler registration.
    // Actor — Sendable, capture by value (struct semantics).
    // Init cheap (no I/O) — safe в App.init body per DEC-06d-01 cold-start defer.
    let deepLinkRouter = DeepLinkRouter()
    self.deepLinkRouter = deepLinkRouter
    // Register handlers — Phase 9 has ONE concrete (ImportHandler).
    // RemoteTokenFetchHandler — stub, не регистрируется в v0.9 (TODO в коде).
    Task {
        await deepLinkRouter.register(ImportHandler(importer: importer))
        // v1+: await deepLinkRouter.register(RemoteTokenFetchHandler(importer: importer, tokenFetcher: ...))
    }

    // ... existing RulesEngineCoordinator / BGTaskScheduler setup ...
}
```

### Example 4: Info.plist — CFBundleURLTypes (iOS)

```xml
<!-- Add to BBTB/App/iOSApp/Info.plist (just before </dict>) -->
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLName</key>
    <string>app.bbtb.client.ios.url</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>bbtb</string>
    </array>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
  </dict>
</array>
```

### Example 5: Entitlement добавление

```xml
<!-- Add to BOTH:
     BBTB/App/iOSApp/BBTB-iOS.entitlements
     BBTB/App/macOSApp/BBTB-macOS.entitlements -->
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:import.bbtb.app</string>
</array>
```

Для разработки (Debug-сборки) — добавить `?mode=developer` чтобы bypass Apple CDN cache:
```xml
  <string>applinks:import.bbtb.app?mode=developer</string>
```

Production (Release) entitlement — без `?mode=developer`. Разрулить либо через два разных .entitlements файла (Debug/Release), либо через xcconfig conditional, либо удалять `?mode=developer` вручную перед archive (Phase 9 W4 task для UAT).

### Example 6: Tuist Project.swift wire-up

```swift
// BBTB/Project.swift — modifications

// 1. Add to localPackages array (after RulesEngine entry):
let localPackages: [Package] = [
    // ... existing ...
    .package(path: .relativeToManifest("Packages/RulesEngine")),
    .package(path: .relativeToManifest("Packages/DeepLinks")),  // Phase 9 — DEEP-05
    // ... rest ...
]

// 2. Add to iOS app target dependencies (after RulesEngine):
.package(product: "RulesEngine"),
.package(product: "DeepLinks"),  // Phase 9

// 3. Same для macOS app target.

// 4. Extension targets — НЕ добавлять. DeepLinks не нужен в NetworkExtension
//    (extension не получает URL routing — это main-app-only concern).
```

### Example 7: AASA verification после deploy

```bash
# 1. Точный путь, без расширения файла, MIME application/json
curl -I https://import.bbtb.app/.well-known/apple-app-site-association
# Ожидаемо:
#   HTTP/2 200
#   content-type: application/json
#   content-length: ~250

# 2. JSON-валидность
curl -s https://import.bbtb.app/.well-known/apple-app-site-association | jq .
# Должен распарситься в applinks.details[0] с двумя appIDs и /import* component

# 3. Apple's debug endpoint (CDN-pretranslated form)
curl "https://app-site-association.cdn-apple.com/a/v1/import.bbtb.app"
# Возвращает processed Apple-side представление AASA — это что устройство
# реально получает после CDN translation. Если 404 — Apple CDN ещё не fetched,
# wait 5-10 min после первого user-initiated fetch.

# 4. На устройстве: Console.app → process "swcd"
# фильтр "import.bbtb.app" → должны быть entries про successful AASA fetch
```

## Runtime State Inventory

> Phase 9 — greenfield для DeepLinks package, но затрагивает существующие App targets. Применимо.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | None — DeepLinks не пишет в SwiftData, Keychain или App Group. `ConfigImporter` уже это делает downstream. | None |
| Live service config | **AASA file на `import.bbtb.app`** — новый артефакт, существует ВНЕ git (на сервере). Если в v1+ потребуется поменять — admin меняет руками. | Документировать процедуру обновления в `wiki/deep-links.md` + W2 deploy task. |
| OS-registered state | **iOS/macOS LaunchServices** — при первом запуске app система регистрирует `bbtb://` URL scheme из Info.plist. **Apple Developer Portal** — capability «Associated Domains» для обоих App ID. | (1) Info.plist edits → автоматическая регистрация при install/update. (2) Portal capability checkbox — manual W4 task. |
| Secrets/env vars | None — Phase 9 не имеет секретов. Если в v1+ landing-page TestFlight invite link будет в коде — TODO в .gitignore. | None |
| Build artifacts | **Tuist generated workspace** — после изменения `Project.swift` и добавления DeepLinks package требуется `tuist generate` для refresh `BBTB.xcworkspace`. | Document в plan W1 first task. |

**Canonical question (рефактор/миграция):** *После каждого file edit, что в runtime может ещё держать старое состояние?*
- Установленное на устройстве BBTB-приложение между Debug-сборками может закешировать `bbtb://` scheme от старой Info.plist редакции — `Settings → General → Reset → Reset All Settings` либо переустановка для UAT.
- Apple CDN кеширует AASA до 24h — в UAT использовать `?mode=developer` либо ждать.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| iOS 18 SDK / macOS 15 SDK | `.onOpenURL`, `.onContinueUserActivity`, SwiftUI App | ✓ | Xcode 16+ (project baseline) | — |
| Swift 6.0 | `actor`, `Sendable`, strict concurrency | ✓ | Project baseline (verified Package.swift swift-tools-version 6.0) | — |
| Tuist 4.x | `tuist generate` для DeepLinks package wire-up | ✓ | (existing project tooling) | — |
| `nginx` или Cloudflare Pages | AASA hosting на `import.bbtb.app` | **UNKNOWN — need to verify deploy target** | — | Cloudflare Pages — zero-config alternative |
| TLS certificate для `import.bbtb.app` | HTTPS для AASA | **UNKNOWN — need to provision** | — | Let's Encrypt (бесплатно) либо Cloudflare auto-SSL |
| DNS A/AAAA record `import.bbtb.app` | Точка входа | **UNKNOWN — need to verify owned + DNS configured** | — | Без этого Universal Links вообще не работают; блокер если домен не настроен |
| Apple Developer Portal access | Toggle «Associated Domains» capability для App IDs | ✓ | Team `UAN8W9Q82U` (verified в codebase) | — |

**Missing dependencies with no fallback:**
- `import.bbtb.app` DNS configuration — **BLOCKING** для DEEP-02. Planner должен включить в plan task verify domain ownership + DNS setup перед W4.
- Apple Developer Portal capability toggle — manual step требует human access; planner делает task с инструкциями + UAT verification.

**Missing dependencies with fallback:**
- nginx vs Cloudflare Pages — оба работают; Cloudflare Pages быстрее в setup (5 минут vs провижн VPS). Если есть существующий VPS под Marzban — переиспользовать nginx.

## Validation Architecture

> nyquist_validation = true (config.json), включаем секцию.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | XCTest (project standard; verified `BBTB/Packages/AppFeatures/Tests/MainScreenFeatureTests/*.swift`) |
| Config file | None — XCTest in-package (Package.swift `.testTarget`) |
| Quick run command | `cd BBTB && swift test --package-path Packages/DeepLinks` |
| Full suite command | `cd BBTB && swift test` (все пакеты) + `xcodebuild test -scheme BBTB -destination 'platform=iOS Simulator,name=iPhone 15'` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DEEP-01 | URL `bbtb://import?url=…` → ImportHandler.canHandle returns true | unit | `swift test --filter ImportHandlerTests.test_canHandle_bbtbImport_returnsTrue` | ❌ Wave 0 |
| DEEP-01 | URL `bbtb://other` → ImportHandler.canHandle returns false | unit | `swift test --filter ImportHandlerTests.test_canHandle_unknownScheme_returnsFalse` | ❌ Wave 0 |
| DEEP-01 | URL `bbtb://import?url=encoded` → ImportHandler.handle calls importer.importFromRawInput с decoded value + source=.deepLink | unit | `swift test --filter ImportHandlerTests.test_handle_callsImporter_withDecodedURL_andDeepLinkSource` | ❌ Wave 0 (нужен stub `ConfigImporting`) |
| DEEP-01 | Missing `url` query → throws DeepLinkError.missingQueryParameter | unit | `swift test --filter ImportHandlerTests.test_handle_missingURL_throws` | ❌ Wave 0 |
| DEEP-01 | Empty `url` value → throws DeepLinkError.missingQueryParameter | unit | `swift test --filter ImportHandlerTests.test_handle_emptyURL_throws` | ❌ Wave 0 |
| DEEP-02 | URL `https://import.bbtb.app/import?url=…` → ImportHandler.canHandle returns true | unit | `swift test --filter ImportHandlerTests.test_canHandle_universalLink_returnsTrue` | ❌ Wave 0 |
| DEEP-02 | URL `https://import.bbtb.app/other` → returns false (только `/import*`) | unit | `swift test --filter ImportHandlerTests.test_canHandle_otherPath_returnsFalse` | ❌ Wave 0 |
| DEEP-02 | Manual UAT: AASA на `import.bbtb.app` отдаётся с правильным MIME, JSON валидный | manual | `curl -I https://import.bbtb.app/.well-known/apple-app-site-association` (must return 200 + Content-Type: application/json) | manual-only |
| DEEP-02 | Manual UAT: тап на `https://import.bbtb.app/import?url=...` из Safari на iPhone iOS 18 — app открывается, импорт запускается | manual | iPhone iOS 18 device UAT (W5) | manual-only |
| DEEP-02 | Manual UAT: то же на macOS 15 через Safari/Telegram | manual | MacBook UAT (W5) | manual-only |
| DEEP-05 | DeepLinkRouter регистрирует handler, итерирует canHandle, вызывает первый match | unit | `swift test --filter DeepLinkRouterTests.test_register_then_handle_routesToFirstMatchingHandler` | ❌ Wave 0 |
| DEEP-05 | Нет handler'а который canHandle → throws DeepLinkError.unhandled | unit | `swift test --filter DeepLinkRouterTests.test_handle_noMatch_throwsUnhandled` | ❌ Wave 0 |
| D-09 cold-start | Manual UAT: cold-start через тап `bbtb://import?url=...` — приложение запускается, импорт запускается ПОСЛЕ initialStatusSnapshot | manual + observability | iPhone UAT + log inspection (DeepLinksLogger fires AFTER applyInitialStatusSnapshot trace) | manual-only |
| D-08 error UX | URL невалидный (missing param) → SwiftUI Alert показывает локализованную error message | integration | (через MainScreenViewModel snapshot test + verified `lastError` поле) | ❌ Wave 0 |
| Pitfall 1 | macOS Universal Link → `.onContinueUserActivity` fires (НЕ только `.onOpenURL`) | manual | macOS UAT (W5) | manual-only |
| Pitfall 3 | `ImportSource.deepLink` case — switch exhaustiveness grep clean | gate | `! grep -rn 'switch.*ImportSource' BBTB/Packages/ | grep -v 'case .deepLink' | grep -v 'default:'` (manually run) | gate-only, W1 |

### Sampling Rate

- **Per task commit:** `swift test --package-path Packages/DeepLinks` (DeepLinks unit tests, ~secondi)
- **Per wave merge:** `cd BBTB && swift test` (все пакеты — preserves Phase 8 regression invariant; expected ~50 sec на M-class hardware) + grep gate для switch exhaustiveness
- **Phase gate:** Full suite green + iOS xcodebuild + macOS xcodebuild + manual UAT (W5) пройден

### Wave 0 Gaps

- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/DeepLinkRouterTests.swift` — register/handle iteration + unhandled throw
- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/ImportHandlerTests.swift` — все canHandle + handle scenarios для DEEP-01 + DEEP-02
- [ ] `BBTB/Packages/DeepLinks/Tests/DeepLinksTests/URLParsingTests.swift` — edge cases percent-decoding, double-encoded URLs (Pitfall 5)
- [ ] Test fixtures: stub `ConfigImporting` (capture-only mock который записывает inputs без real SwiftData/Keychain operations)
- [ ] Integration test для `MainScreenViewModel.handleDeepLink` — error flow в lastError (через extended `MainScreenFeatureTests`)
- [ ] Cold-start race manual test — checklist в `09-UAT.md`

## Security Domain

> security_enforcement = absent в config.json (defaults to enabled per template). Включаем.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | Phase 9 не имеет user authentication; AASA не требует client auth |
| V3 Session Management | no | No sessions involved |
| V4 Access Control | partial | Universal Link components `"/": "/import*"` — единственный allowed path; defense-in-depth от случайного перехвата AASA wildcard'ом |
| V5 Input Validation | **yes** | `URLComponents` + queryItem.value (auto-percent-decode + RFC 3986 compliance) + `URL(string:)` re-validation в `ImportHandler.handle` (Pitfall 5) |
| V6 Cryptography | no — Phase 9 не делает crypto operations | Доверяем TLS для AASA fetch (платформенный TLS validator); Universal Links integrity подтверждается Apple CDN |

### Known Threat Patterns for iOS/macOS deep linking

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| T-09-01: Malicious URL scheme spoofing — другое приложение зарегистрировало `bbtb://` | Spoofing | **Defense:** Universal Links (DEEP-02) — primary; они привязаны к unique domain с Apple-verified AASA. Custom scheme — secondary. CONTEXT.md D-04 ограничивает scheme до одного action (`import`) — снижает blast radius. Документировать в FAQ как known limitation. |
| T-09-02: Поданная пользователю фишинговая ссылка `bbtb://import?url=<malicious>` | Tampering, Phishing | **Defense:** `ConfigImporter.importFromRawInput` уже выполняет validation downstream (Phase 2). Phase 9 НЕ добавляет дополнительной trust к содержимому subscription URL — это ответственность пользователя проверить источник. UI должен ясно показывать что импортируется и от кого (existing import progress + alert). |
| T-09-03: Cold-start race exploit — атакующий вынуждает запуск через deep link с целью попадания в race window до VM-ready | Tampering, EoP | **Defense:** Pattern 4 cold-start buffering — pendingURL не выполняется до `initialManagersApplied=true`. Атакующий не может ускорить применение snapshot — оно gated on NEVPNStatus load, не на user input. |
| T-09-04: URLComponents decoding bypass — invalid UTF-8 или malformed percent-encoding | Tampering | **Defense:** `URLComponents` — Apple framework, обрабатывает edge cases per RFC 3986. Дополнительно валидация `URL(string: rawValue) != nil` после декодирования (Pitfall 5). Empty/missing — throws `DeepLinkError.missingQueryParameter`. |
| T-09-05: AASA tampering на mid-route (MITM) | Tampering | **Defense:** HTTPS-only (TLS 1.2+) для AASA URL. Apple CDN использует pinned cert chain. Локальный admin не имеет write access к Apple CDN. На стороне `import.bbtb.app` сервер должен иметь validation Let's Encrypt cert (auto-renewal). |
| T-09-06: AASA size exhaustion (DoS на устройстве) | DoS | **Defense:** Apple CDN enforces 128 KB max; наш AASA ~250 байт. Никакого пользовательского input не входит в AASA — он статичный. |
| T-09-07: Universal Link перехват чужим приложением — нет, Apple CDN валидирует `appIDs` против Team ID | Spoofing | **Defense:** Apple-side enforced. Перехват возможен только если другое приложение от того же Team ID зарегистрирует тот же domain — что мы контролируем. |
| T-09-08: Sensitive data в URL `?url=...` логируется в OS-level URL logger | Information Disclosure | **Defense:** `DeepLinksLogger` использует `privacy: .public` ТОЛЬКО для scheme/host (не subscription URL); subscription URL contained в `rawValue` — logged через `privacy: .private`. Console.app non-developer не покажет. iOS LaunchServices does NOT log custom-scheme URL bodies в crash logs (verified by Apple docs). |

**Conclusion:** Phase 9 security surface маленький — единственный новый attack vector это deep-link payload, но он validated и downstream проходит existing ConfigImporter validation (Phase 2 + Phase 4 hardened). 0 BLOCKER findings; T-09-01 (scheme spoofing) — known limitation, mitigated via Universal Links primary path.

## Project Constraints (from CLAUDE.md)

| Constraint | How Phase 9 Respects |
|------------|----------------------|
| Не модифицировать `raw/` | DeepLinks package — новый код в `BBTB/Packages/DeepLinks/`; никаких изменений в `raw/` |
| Обновить `wiki/index.md` и `wiki/log.md` после изменений | Planner добавляет task — переписать `wiki/deep-links.md` (existing) + добавить запись в `wiki/log.md` после W5 |
| Page names lowercase с hyphens | `deep-links.md` уже существует и соответствует |
| Ответы на русском | Planner и downstream agents отвечают на русском (это требование UI strings + commit messages могут оставаться bilingual как в codebase) |
| Аббревиатуры с русскими переводами | AASA = Apple App Site Association = «файл связки приложения с сайтом»; URL = «адрес» (где уместно) |
| Приоритет на масштабируемость (20 протоколов, 50+ транспортов) | `DeepLinkHandler` protocol + actor registry — extensible (D-05). v1+ просто добавляет новые handlers без изменения routing core. |
| Между скоростью и качеством — качество | Atomic-commit-per-task discipline; не пропускать AASA verification step; manual UAT в W5 обязателен |
| Подробно и максимально просто | Planner объясняет каждое design decision; не использует sophisticated SwiftUI tricks где можно простое решение |
| **Всегда консультируйся с CODEX** | Planner делегирует через mcp__codex для (1) `protocol DeepLinkHandler` сигнатуры, (2) AASA verification команд для nginx vs Cloudflare, (3) cold-start race в xcodebuild test simulator. Этот research использовал WebSearch+WebFetch + codebase inspection вместо codex MCP (subagent tool limitation); planner должен этот пробел закрыть. |
| GSD: фиксировать решения в wiki | Phase 9 closure добавит запись в `wiki/deep-links.md` («D-01..D-09 implemented v0.9 commit XXX») и `wiki/log.md` daily entry. |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `import.bbtb.app` DNS уже принадлежит проекту BBTB | § Environment Availability | **HIGH** — DEEP-02 невозможен; нужен либо альтернативный домен либо приобретение `bbtb.app` |
| A2 | nginx и/или Cloudflare Pages availble для deploy | § Pattern 6 | **MED** — нужен fallback static host. Discuss-phase обсуждался выбор; planner верифицирует. |
| A3 | Apple Developer Portal Associated Domains capability checkbox UI остался как в 2024 (просто галочка, без Configure кнопки) | § Pitfall 7 | **LOW** — даже если UI поменялся, capability существует; planner может потратить на 5 минут больше на manual step |
| A4 | `Settings → General → URL Schemes` или Console.app достаточны для debugging custom-scheme regression на iOS 18 | § Common Pitfalls | **LOW** — даже если конкретный UI поменялся, debugging tools concept остаётся |
| A5 | TLS 1.2+ требование Apple CDN remains as documented | § Pattern 2 | **LOW** — Apple увеличивает minimum, не понижает; Let's Encrypt поддерживает TLS 1.3 |
| A6 | Универсальные ссылки на iOS 18 не имеют известных регрессий blocking DEEP-02 (web search показала «mostly fixed on later versions of iOS 18») | § Pitfall, § Standard Stack | **MED** — если на iOS 26.x есть baseline regression — нужен альтернативный test device или wait for Apple fix. Planner добавляет device version в UAT matrix. |
| A7 | `ConfigImporter.importFromRawInput` принимает `.deepLink` ImportSource без модификаций своей бизнес-логики (только для атрибуции) | § Standard Stack | **LOW** — verified в коде: source используется только для parser routing (subscription URL vs JSON endpoint detection) и анализ ImportSource cases показывает что parser не делает special-casing на source |
| A8 | Phase 9 UAT может быть deferred (как в Phase 5, 6, 7a UAT deferred patterns) если manual checks не получится сразу провести | § Validation Architecture | **LOW** — известный pattern в проекте, planner может это handle |

**If this table requires user confirmation:** Items A1, A2, A6 — нужны user confirmation перед W4 deploy.

## Open Questions

1. **Какой домен и хост для AASA?** (`import.bbtb.app` ассумится но не verified в conversation)
   - What we know: `.planning/config.json` зафиксировал `universal_links_domain: "import.bbtb.app"`; team_id `UAN8W9Q82U` тоже зафиксирован.
   - What's unclear: владение доменом, DNS provider, available hosting (VPS под Marzban? Cloudflare?).
   - Recommendation: planner делает первый W2 task «verify domain ownership + DNS configured + choose host (nginx vs Cloudflare Pages)». Если домен не принадлежит — это блокер для DEEP-02 в Phase 9.

2. **Where do `?mode=developer` Debug builds get the Debug-mode entitlement?**
   - What we know: Production должен быть без `?mode=developer`. Debug должен быть с — иначе AASA cache 24h блокирует UAT.
   - What's unclear: разделение Debug vs Release entitlements в Tuist project. Verified в `BBTB/App/iOSApp/BBTB-iOS.entitlements` — один файл, plain XML.
   - Recommendation: planner выбирает один из двух подходов:
     - (a) Два entitlements файла (`.debug.entitlements`, `.release.entitlements`) + xcconfig switch.
     - (b) Один файл с `?mode=developer` всегда — Apple валидирует production builds correctly и mode=developer в Release не блокирует TestFlight (some teams делают так).
   - Codex consultation needed.

3. **Migration в `wiki/deep-links.md` — переписать полностью или incremental update?**
   - What we know: existing page (verified) ссылается на DEEP-03 endpoint (`/c/{token}`) и landing page как primary — что устарело.
   - What's unclear: stylistic preference user'а.
   - Recommendation: planner делает full rewrite — структура существенно поменялась (Phase 9 scope amendment).

4. **Phase 9 UAT deferred ИЛИ обязательный?**
   - What we know: Phase 5, 6 (impl), 7a UAT были deferred; Phase 8 UAT — partial defer (M-07/M-08 deferred). Pattern в проекте — UAT часто deferred когда manual checks требуют физических устройств.
   - What's unclear: Phase 9 manual UAT критически зависит от physical device (iPhone + Mac) + Telegram bot + domain. Это блокер для closure если строго.
   - Recommendation: planner делает UAT optional (deferred-OK pattern) — если manual проверки `M-04 .. M-08` нельзя сразу сделать, фаза closes на implementation-complete, manual UAT trails.

## Sources

### Primary (HIGH confidence)
- [VERIFIED via Read in this session] `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift` — extensible registry pattern (NSLock-based, legacy Phase 1)
- [VERIFIED via Read] `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift` — actor pattern для Phase 8+ (canonical)
- [VERIFIED via Read] `BBTB/Packages/RulesEngine/Package.swift` — пример SwiftPM package скаффолда (W1 reference)
- [VERIFIED via Read] `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConfigImporter.swift:112-130` — `importFromRawInput(_:source:)` точка входа
- [VERIFIED via Read] `BBTB/Packages/VPNCore/Sources/VPNCore/ParsedConfigs.swift:289` — ImportSource enum (требует `.deepLink` case)
- [VERIFIED via Read] `BBTB/App/iOSApp/BBTB_iOSApp.swift` и `BBTB_macOSApp.swift` — current App scaffolding (Phase 8 W4 cold-start defer pattern)
- [VERIFIED via Read] `BBTB/App/iOSApp/Info.plist` + `BBTB-iOS.entitlements` — где добавлять CFBundleURLTypes и Associated Domains
- [VERIFIED via Read] `BBTB/Project.swift` — Tuist project structure для wire-up
- [VERIFIED via Read] `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/MainScreenViewModel.swift:79, 385, 547, 645, 672` — alert mechanism + cold-start hooks
- [VERIFIED via Read] `.planning/phases/09-deep-links/09-CONTEXT.md` — все decisions D-01..D-09 + scope amendment
- [CITED] [Apple — onOpenURL(perform:)](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:))
- [CITED] [Apple — Supporting Associated Domains](https://developer.apple.com/documentation/Xcode/supporting-associated-domains)
- [CITED] [Apple — Associated Domains Entitlement](https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.associated-domains)
- [CITED] [Apple — Supporting universal links in your app](https://developer.apple.com/documentation/xcode/supporting-universal-links-in-your-app)

### Secondary (MEDIUM confidence, cross-referenced)
- [Apple Developer Forums — onOpenURL not triggering for Universal Links on macOS](https://developer.apple.com/forums/thread/673822) — **критический pitfall #1**
- [Apple Developer Forums — onOpenURL(perform:) vs application(_:open:options:)](https://developer.apple.com/forums/thread/748422) — SwiftUI vs AppDelegate recommendation
- [Apple Developer Forums — Testing openURL to cold started app](https://developer.apple.com/forums/thread/21129) — cold-start timing
- [iOS Universal Links: Implementation Guide That Works (2026) — reverseBits](https://www.reversebits.tech/blog/ios-universal-links/) — current best practices snapshot
- [Bugfender — iOS Universal Links: Setup, Testing and Debugging Guide](https://bugfender.com/blog/ios-universal-links/) — debugging methods
- [SwiftLee — Deeplink URL handling in SwiftUI](https://www.avanderlee.com/swiftui/deeplink-url-handling/) — SwiftUI patterns
- [SerialCoder.dev — Handling Incoming URLs With onOpenURL In SwiftUI](https://serialcoder.dev/text-tutorials/swiftui/handling-incoming-urls-with-onopenurl-in-swiftui/) — modifier placement

### Tertiary (LOW confidence — informational only)
- [Branch.io — What Is An AASA File?](https://www.branch.io/resources/blog/what-is-an-aasa-apple-app-site-association-file/) — historical context AASA format evolution
- [DigitalBunker — Everything You Need To Know About The Apple App Site Association File](https://digitalbunker.dev/apple-app-site-association/) — informational
- [Bhoopendra Umrao — Retrieving query parameters from Deep-link URL in Swift](https://bhoopendraumrao.medium.com/retrieving-query-parameters-from-deep-link-url-in-swift-98f69ef17f29) — Swift URLComponents patterns
- [MojoAuth — Percent-encoding with Swift](https://mojoauth.com/binary-encoding-decoding/percent-encoding-url-encoding-with-swift) — RFC 3986 reference

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — все APIs Apple-canonical, verified в Apple docs + cross-referenced в существующем коде
- Architecture: HIGH — paterns копируются из RulesEngine (Phase 8 closed, working) и ProtocolRegistry (Phase 1 working since v0.1)
- Pitfalls: HIGH (Pitfall 1, 2, 7) / MEDIUM (Pitfall 4, 6) — Pitfall 1 — известный Apple Forums issue; Pitfall 4 cold-start — verified в Phase 6d/8 DEC-06d-01 pattern; Pitfall 7 — Apple Portal mechanics; Pitfall 5 — based on RFC 3986 reading
- Security: HIGH — Phase 9 surface маленький, threats хорошо известны и нативно mitigated Apple framework'ами; ASVS V5 (input validation) addressed
- Server infrastructure: **MEDIUM** — nginx/Cloudflare Pages — well-known patterns, но domain ownership not verified (Open Question 1, Assumption A1)

**Research date:** 2026-05-15
**Valid until:** 2026-06-15 (30 days — stable iOS/macOS SDK; AASA hosting recipes evergreen)

---

*Researcher: Claude Opus 4.7 (gsd-researcher agent). Codex MCP consultation not invoked в этой research session (tool restriction в subagent context); planner должен закрыть пробел через `/mcp__codex__codex` для (1) verification протокол `DeepLinkHandler` signature под Swift 6 strict concurrency, (2) AASA verification commands для конкретного host который выбрал user, (3) cold-start race XCTest patterns. Per CLAUDE.md правило «всегда консультируйся с CODEX».*
