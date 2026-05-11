---
name: Deep Links
description: Custom URL scheme bbtb:// + Universal Links через import.bbtb.app (rebrand 2026-05-11, ранее yourvpn://)
type: project
---

# Deep Links

**Summary**: Два механизма параллельно — custom URL scheme `bbtb://` для импорта/connect/disconnect и Universal Links через `import.bbtb.app` с landing page для тех, у кого приложение не установлено.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Зачем оба механизма

- **Custom URL scheme** — работает мгновенно, не требует интернета, не зависит от DNS. Но не работает, если приложение не установлено.
- **Universal Links** — работают как обычные HTTPS-ссылки. Если приложение установлено — открывают его; если нет — открывают landing page с инструкцией про TestFlight.

## Custom URL Scheme

Регистрируется в `Info.plist` схема `bbtb://`.

Форматы:
- `bbtb://import?config=<URL-encoded vless:// or sub URL>` — импорт конфига
- `bbtb://connect` — подключиться (для shortcuts)
- `bbtb://disconnect` — отключиться (для shortcuts)

## Universal Links

Домен: `import.bbtb.app` (или аналогичный, определяется на этапе setup).

Endpoint `https://import.bbtb.app/c/{token}` — отдаёт конфиг по короткому токену.

Файл `apple-app-site-association` (без расширения, MIME `application/json`) лежит на корне домена:

```json
{
  "applinks": {
    "details": [{
      "appIDs": ["UAN8W9Q82U.app.bbtb.client.ios", "UAN8W9Q82U.app.bbtb.client.macos"],
      "components": [{ "/": "/c/*" }]
    }]
  }
}
```

При установленном приложении — открывается оно. При отсутствии — landing page «Скачайте через TestFlight + ссылка-приглашение».

## Обработка в коде

```swift
.onOpenURL { url in
    DeepLinkRouter.shared.handle(url)
}
.onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
    if let url = activity.webpageURL {
        DeepLinkRouter.shared.handle(url)
    }
}
```

`DeepLinkRouter` — actor в модуле `DeepLinks` (см. [[architecture]]). Парсит URL → определяет тип action → вызывает соответствующий handler из `ConfigParser` или `VPNCore`.

## Endpoint для генерации deep-link

Бэкенд на VPS. На старте можно вручную. На следующих фазах — мини-админка для генерации одноразовых ссылок.

## Roadmap

- **v0.9** — Deep links: custom scheme + Universal Links + endpoint на VPS + landing page

## DoD

- Тап на `bbtb://import?config=...` в Telegram → открывает приложение и импортирует конфиг
- Тап на `https://import.bbtb.app/c/...` делает то же самое
- При отсутствии приложения Universal Link открывает landing page

## Related pages

- [[architecture]]
- [[ux-specification]]
- [[distribution-testflight]]
- [[release-roadmap]]
