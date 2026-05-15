# Phase 9 — Deep Links: Инструкция по возобновлению

**Статус:** ПРИОСТАНОВЛЕНО 2026-05-15  
**Причина паузы:** Wave 4 Task 4.2–4.3 требуют ручных действий (сервер + Apple Portal + device UAT) — отложено.  
**Возобновить с:** Task 4.2 (сервер AASA + Apple Portal), затем Task 4.3 (device UAT), затем Task 4.4 (wiki sync + closure).

---

## Что уже сделано (Waves 1–3 + Task 4.1)

| Wave | Статус | Что сделано |
|------|--------|-------------|
| W1 | ✅ | `DeepLinks` SwiftPM пакет: `DeepLinkRouter` actor + `DeepLinkHandler` protocol + `DeepLinkError` + `DeepLinksLogger` + stub `TokenFetcher` |
| W2 | ✅ | `ImportHandler` (bbtb:// + Universal Links) + `RemoteTokenFetchHandler` (stub) + L10n 5 ключей (ru+en) + `URLParsingTests` |
| W3 | ✅ | Tuist `Project.swift` + entitlements + Info.plist + App wiring (`.onOpenURL` + `.onContinueUserActivity`) + cold-start buffer + `MainScreenViewModel.handleDeepLink` |
| W4 Task 4.1 | ✅ | `09-AASA-RUNBOOK.md` написан — два варианта деплоя (nginx + Cloudflare Pages) |
| W4 Task 4.2 | ⏸ DEFERRED | Деплой AASA на `import.bbtb.app` + Apple Portal capability — **здесь остановились** |
| W4 Task 4.3 | ⏸ DEFERRED | Device UAT (F1-F4) |
| W4 Task 4.4 | ⏸ NOT STARTED | Wiki sync + REQUIREMENTS Validated marks + phase closure |

**Тесты на момент паузы:** 17/17 DeepLinks + 164/164 AppFeatures — все зелёные.

---

## Шаг 1 — Деплой AASA-файла (Task 4.2, часть 1)

Полная инструкция: `.planning/phases/09-deep-links/09-AASA-RUNBOOK.md`

### Вариант B — Cloudflare Pages (рекомендуется, ~10 минут)

1. Открой [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages** → **Create application** → **Pages** → **Direct Upload**

2. Создай папку на компьютере (например `bbtb-aasa`) с двумя файлами:

   **Файл 1** — создай подпапку `.well-known/`, внутри файл `apple-app-site-association` (БЕЗ расширения `.json`!):
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

   **Файл 2** — в корне папки `_headers`:
   ```
   /.well-known/apple-app-site-association
     Content-Type: application/json
   ```
   > Важно: перед `Content-Type` — два пробела (не таб). Cloudflare требует именно такой формат.

3. В Cloudflare Pages загрузи папку (`bbtb-aasa`) через Direct Upload → назови проект, например `bbtb-aasa`

4. После деплоя → вкладка **Custom domains** → добавь `import.bbtb.app`
   - Cloudflare спросит добавить CNAME-запись в DNS — подтверди
   - TLS-сертификат выдаётся автоматически, обычно за 5–15 минут

5. Проверь что DNS `import.bbtb.app` указывает на Cloudflare (или настрой вручную через свой DNS-провайдер)

### Вариант A — nginx на VPS (если Marzban уже там)

Полная инструкция в `09-AASA-RUNBOOK.md` раздел "Option A". Суть:
- Создать виртуальный хост nginx для `import.bbtb.app` на порту 443
- Положить файл `apple-app-site-association` (без расширения) в root сайта
- Добавить `default_type application/json;` в location-блок
- Получить сертификат через `certbot --nginx -d import.bbtb.app`

---

## Шаг 2 — Apple Developer Portal (Task 4.2, часть 2, ~5 минут)

Без этого шага Universal Links (`https://import.bbtb.app/import?url=...`) не откроют приложение — только `bbtb://` custom scheme будет работать.

1. Открой [developer.apple.com → Identifiers](https://developer.apple.com/account/resources/identifiers/list) (нужен вход как Team Admin)

2. В поиске найди `app.bbtb.client.ios` → нажми на него → вкладка **Capabilities** → поставь галочку **Associated Domains** → кнопка **Save** (справа вверху)

3. Аналогично `app.bbtb.client.macos` → **Associated Domains** → **Save**

4. Пересоздавать Provisioning Profiles **не нужно** — Xcode с автоматической подписью подхватит изменение само при следующей сборке

---

## Шаг 3 — Проверка AASA через curl (выполняет Claude после Шага 1)

После того как ты скажешь Claude «AASA задеплоен», Claude сам запустит:

```bash
# 1. HTTP 200 + Content-Type: application/json (не text/plain!)
curl -sI https://import.bbtb.app/.well-known/apple-app-site-association

# 2. Валидный JSON
curl -s https://import.bbtb.app/.well-known/apple-app-site-association | python3 -m json.tool

# 3. Apple CDN уже скачал файл (проверка кеша)
curl -s "https://app-site-association.cdn-apple.com/a/v1/import.bbtb.app" | python3 -m json.tool
```

Ожидаемый результат:
- `content-type: application/json` в заголовках (не text/plain, не text/html)
- Валидный JSON с ключом `applinks.details`
- Apple CDN возвращает тот же JSON (может занять до 24ч после первого деплоя)

---

## Шаг 4 — Device UAT (Task 4.3)

Нужен iPhone iOS 18+ с установленным приложением BBTB (Debug или TestFlight build с новым кодом Wave 1–3).

### F1 — Cold-start через bbtb:// custom scheme
1. Полностью закрой приложение (смахни из App Switcher)
2. Создай ссылку `bbtb://import?url=https://твой-marzban.example.com/sub/твой-токен`
3. Отправь себе в Telegram или заметки
4. Тапни ссылку
5. **Ожидаемо:** BBTB открывается, появляется `ImportProgressOverlay`, импорт выполняется успешно (серверы появились в списке)
6. В Console.app проверь порядок логов: `DeepLinksLogger` записи должны идти ПОСЛЕ `initialManagersApplied=true`

### F2 — Warm-start (app в фоне) через bbtb://
1. Приложение свёрнуто (не убито)
2. Тапни ту же ссылку
3. **Ожидаемо:** overlay появляется ≤300ms, импорт стартует

### F3 — Universal Link через Safari iOS
> Требует: AASA задеплоен + Apple Portal capability включён + app переустановлен ПОСЛЕ деплоя (или использован `?mode=developer` entitlement)

1. Открой Safari на iPhone
2. Введи: `https://import.bbtb.app/import?url=https://твой-marzban.example.com/sub/токен`
3. **Ожидаемо:** Safari показывает баннер «Открыть в Верни жука» ИЛИ сразу открывает приложение. Safari НЕ должен открывать страницу в браузере.

### F3-mac — Universal Link на macOS (Pitfall #1)
1. Открой Safari на Mac
2. Введи ту же ссылку `https://import.bbtb.app/import?url=...`
3. **Ожидаемо:** приложение открывается через `.onContinueUserActivity` (проверить в Console.app — должен быть лог из DeepLinksLogger)

### F4 — Error UX (неверная ссылка)
1. Тапни `bbtb://import` (без параметра `url=`)
2. **Ожидаемо:** SwiftUI Alert с текстом «Не удалось открыть ссылку» + кнопка OK. Никаких крашей.

---

## Шаг 5 — Финальная автоматическая часть (Task 4.4, выполняет Claude)

После подтверждения UAT Claude:
- Заполняет `09-UAT.md` с результатами F1-F4
- Переписывает `wiki/deep-links.md` (scope amendment, D-01..D-09, AASA процедура, return conditions для DEEP-03/04 в v1+)
- Добавляет запись в `wiki/log.md`
- Обновляет `wiki/index.md`
- Отмечает DEEP-01/02/05 как **Validated** в `.planning/REQUIREMENTS.md`
- Закрывает Phase 9 в STATE.md и ROADMAP.md

---

## Как возобновить

Напиши Claude в новой сессии:

```
/gsd-execute-phase 9 --wave 4
```

Или просто:

```
Продолжаем Phase 9. AASA задеплоен через [Вариант A / Вариант B].
Apple Portal capability включён для обоих App ID.
Запусти curl-проверки.
```

Claude подхватит контекст из этого файла и CONTEXT.md/STATE.md.

---

## Важные детали для будущего

**Если Apple CDN не обновился сразу:**
Apple кеширует AASA до 24 часов. Для немедленного тестирования Universal Links используй `?mode=developer` в entitlement (инструкция в `09-AASA-RUNBOOK.md` § Debug bypass). **Не забудь убрать `?mode=developer` до отправки в App Store** — Apple Review отклонит.

**Team ID + App IDs (не потерять):**
- Team ID: `UAN8W9Q82U`
- App ID iOS: `UAN8W9Q82U.app.bbtb.client.ios`
- App ID macOS: `UAN8W9Q82U.app.bbtb.client.macos`
- Домен: `import.bbtb.app` (entitlement: `applinks:import.bbtb.app`)

**DEEP-03/04 (v1+ backlog):**
Когда в будущем понадобятся токен-ссылки (`/c/{token}` → subscription URL) — читай `09-CONTEXT.md` §Deferred. В пакете `DeepLinks` уже есть архитектурный stub `TokenFetcher` protocol и `RemoteTokenFetchHandler` — только реализовать. В AASA добавить `{ "/": "/c/*" }` в `components` без изменения iOS/macOS кода.
