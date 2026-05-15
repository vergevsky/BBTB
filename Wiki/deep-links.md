# Deep Links

**Summary**: Клиентский маршрутизатор ссылок Phase 9 — custom scheme `bbtb://import?url=…` + Universal Links `https://import.bbtb.app/import?url=…` для запуска импорта конфига из внешних источников (Telegram, Safari). Серверная часть (токен-эндпоинт, landing page) — v1+ backlog.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md, `.planning/phases/09-deep-links/09-CONTEXT.md`

**Last updated**: 2026-05-15

---

## Статус реализации (v0.9)

| Компонент | Статус | Где |
|-----------|--------|-----|
| `DeepLinks` SwiftPM пакет | ✅ Реализован | `BBTB/Packages/DeepLinks/` |
| `DeepLinkRouter` actor | ✅ | `Sources/DeepLinks/DeepLinkRouter.swift` |
| `ImportHandler` (bbtb:// + Universal Links) | ✅ | `Sources/DeepLinks/Handlers/ImportHandler.swift` |
| L10n 5 ключей (ru+en) | ✅ | `Localizable.xcstrings` |
| App wiring — iOS `.onOpenURL` | ✅ | `BBTB_iOSApp.swift` |
| App wiring — macOS `.onContinueUserActivity` | ✅ | `BBTB_macOSApp.swift` |
| Cold-start buffer | ✅ | `@State pendingDeepLink` в root views |
| `MainScreenViewModel.handleDeepLink` | ✅ | `MainScreenViewModel.swift` |
| Entitlements — Associated Domains | ✅ | `BBTB-iOS.entitlements`, `BBTB-macOS.entitlements` |
| Info.plist — CFBundleURLTypes `bbtb://` | ✅ | iOS + macOS Info.plist |
| AASA-файл на `import.bbtb.app` | ⏸ PENDING | Нужен деплой на сервер (09-AASA-RUNBOOK.md) |
| Apple Portal Associated Domains capability | ⏸ PENDING | developer.apple.com → Identifiers |
| Device UAT F1–F4 | ⏸ PENDING | После AASA + Portal |
| `RemoteTokenFetchHandler` stub | 🗂 Заглушка | Sources/DeepLinks/Handlers/ — v1+ |

**Текущий статус**: код готов (Wave 1–3), ждёт серверных и Portal шагов. Инструкция возобновления: `.planning/phases/09-deep-links/09-RESUME.md`.

---

## Scope amendment (Phase 9 v0.9)

На `/gsd-discuss-phase 9` (2026-05-15) **DEEP-03 и DEEP-04 перенесены в v1+ backlog**:

- ~~DEEP-03~~ — эндпоинт `/c/{token}` → подписочный URL. Требует Shlink или nginx proxy. В `DeepLinks` пакете есть архитектурная заглушка `TokenFetcher` protocol для быстрого v1+ resume.
- ~~DEEP-04~~ — landing page для тех, у кого приложение не установлено. Требует HTML-сервер. В v0.9 accepted: Safari открывает 404 `import.bbtb.app/import…` если приложение не установлено.

В v0.9 реализованы только: DEEP-01 (custom scheme) + DEEP-02 (Universal Links, клиентская часть + AASA) + DEEP-05 (DeepLinkRouter архитектура).

---

## Архитектура

### DeepLinks пакет

```
BBTB/Packages/DeepLinks/
  Sources/DeepLinks/
    DeepLinkRouter.swift          # actor, extensible handler registry
    DeepLinkHandler.swift         # protocol: canHandle(_:) + handle(_:)
    DeepLinkError.swift           # .unhandled | .missingQueryParameter | .invalidParameter | .importFailed | .notImplemented
    DeepLinksLogger.swift         # OSLog wrapper с privacy labels
    TokenFetcher.swift            # protocol stub для v1+ DEEP-03
    Handlers/
      ImportHandler.swift         # DEEP-01 (bbtb://import) + DEEP-02 (import.bbtb.app/import*)
      RemoteTokenFetchHandler.swift  # stub: canHandle→false, не зарегистрирован в v0.9
  Tests/DeepLinksTests/
    DeepLinkRouterTests.swift     # 3 тесты: register/handle/unhandled
    ImportHandlerTests.swift      # 9 тестов: canHandle + handle scenarios
    URLParsingTests.swift         # 5 тестов: percent-decoding edge cases (Pitfall #5)
```

### Поток URL

```
Telegram/Safari → LaunchServices / NSUserActivity
        ↓
BBTB_iOSApp.onOpenURL           (custom scheme bbtb://)
BBTB_macOSApp.onContinueUserActivity  (Universal Links macOS — КРИТИЧНО: НЕ .onOpenURL)
        ↓
routeOrBuffer(_:)  →  if not ready: pendingDeepLink buffer
        ↓  (после initialManagersApplied)
MainScreenViewModel.handleDeepLink(_:router:)
        ↓
DeepLinkRouter.handle(url)
        ↓  (iterates registered handlers)
ImportHandler.handle(url)
        ↓
ConfigImporter.importFromRawInput(decodedURL, source: .deepLink)
        ↓
ImportProgressOverlay (success) OR SwiftUI .alert (error via lastError)
```

---

## Принятые решения (D-01..D-09)

| ID | Область | Решение |
|----|---------|---------|
| D-01 | Сервер | Минимальный сервер Phase 9 — только AASA. nginx static или Cloudflare Pages. |
| D-02 | AASA | `/import*` в components. `/c/*` добавляется в v1+ без изменения iOS/macOS кода. |
| D-03 | v1+ prep | `TokenFetcher` protocol + `RemoteTokenFetchHandler` stub — в пакете, не зарегистрированы. |
| D-04 | URL-формат | `bbtb://import?url={subscription_url}` — единственный формат v0.9. `url` передаётся в `importFromRawInput`. |
| D-05 | Архитектура | Extensible handler registry: `protocol DeepLinkHandler { canHandle + handle }`. Не один большой switch. |
| D-06 | connect/disconnect | `bbtb://connect` и `bbtb://disconnect` deferred. Нет подтверждённого use case. |
| D-07 | Платформы | iOS + macOS оба. entitlements + Info.plist в обоих targets. |
| D-08 | Error UX | SwiftUI `.alert` через существующий `MainScreenViewModel.lastError`. Не вводим новый механизм. |
| D-09 | Cold-start | `@State pendingDeepLink: URL?` buffer + flush после `wireRulesCoordinator` в `.task`. Defer до `initialManagersApplied`. |

---

## AASA-файл (v0.9 content)

Размещается на `https://import.bbtb.app/.well-known/apple-app-site-association` (без расширения, Content-Type: application/json, HTTPS обязательно):

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

Team ID: `UAN8W9Q82U`. Варианты хостинга: **Cloudflare Pages** (рекомендуется, zero-config) или nginx на VPS. Полная инструкция: `.planning/phases/09-deep-links/09-AASA-RUNBOOK.md`.

---

## Критичный pitfall: macOS Universal Links

На macOS Universal Links (`https://import.bbtb.app/import?url=…`) доставляются через `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)`, **НЕ через `.onOpenURL`**. `.onOpenURL` на macOS обрабатывает только custom scheme `bbtb://`. Оба модификатора обязательны на обеих платформах.

---

## Return conditions для v1+ (DEEP-03/04)

Когда понадобятся токен-ссылки вида `https://import.bbtb.app/c/{abc123}`:

1. **Backend**: Shlink (Docker) или nginx-proxy на VPS. Хранит `{token} → subscription URL`.
2. **AASA update**: добавить `{ "/": "/c/*" }` в `components` — iOS/macOS код не меняется.
3. **Код**: реализовать `RemoteTokenFetchHandler` (заглушка уже есть) + `TokenFetcher` protocol реализация.
4. **Apple Portal**: Associated Domains уже включён — ничего добавлять не нужно.
5. **Landing page (DEEP-04)**: HTML-страница на `import.bbtb.app` для не-пользователей → TestFlight invite link.

Codex thread: `019e2a7f-d023-7020-bc60-72ccb8116ba5` (Shlink architectural recommendation).

---

## Related pages

- [[architecture]]
- [[config-importer]]
- [[distribution-testflight]]
- [[rules-engine]]
- [[release-roadmap]]
