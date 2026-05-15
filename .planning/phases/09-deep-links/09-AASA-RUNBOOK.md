# Phase 9 — AASA Deploy Runbook

> **Цель:** Опубликовать `apple-app-site-association` файл на `https://import.bbtb.app/.well-known/apple-app-site-association`.
>
> **Источники:** `09-RESEARCH.md` § Pattern 6 + Pitfall 2 + Example 7; `09-CONTEXT.md` D-01 + D-02.
>
> **Maintainer notes:** Этот файл — единственный серверный артефакт Phase 9. Меняется не более 2 раз за жизнь проекта: v0.9 (только `/import*`) и v1+ (добавляем `/c/*` когда появится DEEP-03 токен-эндпоинт). Артефакт живёт ВНЕ git — на сервере. Хранить его содержимое актуальным здесь и в `wiki/deep-links.md`.

---

## AASA Content (точное содержимое файла)

Содержимое файла `apple-app-site-association`:

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

**Обязательные требования к файлу:**
- Без расширения — файл называется `apple-app-site-association` (не `.json`)
- Content-Type ДОЛЖЕН быть `application/json`
- Без BOM (Byte Order Mark)
- Без trailing whitespace после последней `}`
- Размер: ~250 байт (Apple CDN limit — 128 KB; наш файл далеко от лимита)
- HTTPS обязателен — HTTP не принимается Apple CDN
- Без HTTP redirects на пути к файлу (Apple CDN не следует за 301/302)

---

## DNS Setup

Перед deploy на любой платформе — настроить DNS для `import.bbtb.app`.

**Если домен управляется в Cloudflare:**

1. Cloudflare Dashboard → Your domain (`bbtb.app`) → DNS → Records.
2. Добавить запись:
   - Type: `CNAME`
   - Name: `import`
   - Content: адрес VPS или `<project>.pages.dev` (зависит от выбранной опции ниже)
   - Proxy status: Proxied (оранжевое облако) — для Cloudflare Pages это обязательно

**Если домен управляется у другого регистратора:**

- Добавить `A`-запись: `import.bbtb.app` → IP-адрес VPS
- Или `CNAME`-запись: `import.bbtb.app` → `<project>.pages.dev` (для Cloudflare Pages)

**Проверить DNS propagation:**

```bash
dig import.bbtb.app +short
# Должен вернуть IP-адрес VPS или Cloudflare IP
```

---

## Option A — nginx на VPS (рекомендуется при наличии VPS под Marzban)

**Когда выбирать Option A:** Уже есть VPS с nginx (например, Marzban на том же сервере). Переиспользуем nginx, добавляем vhost для `import.bbtb.app`.

### Шаг 1. Создать файл AASA на сервере

SSH на VPS, затем:

```bash
sudo mkdir -p /var/www/import.bbtb.app

# Создать файл с точным содержимым (без .json расширения)
sudo tee /var/www/import.bbtb.app/apple-app-site-association << 'EOF'
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
EOF

sudo chmod 644 /var/www/import.bbtb.app/apple-app-site-association
```

Проверить содержимое:

```bash
cat /var/www/import.bbtb.app/apple-app-site-association
# Должен вывести JSON выше, без trailing newline
```

### Шаг 2. Создать nginx vhost

Создать файл `/etc/nginx/sites-available/import.bbtb.app`:

```nginx
server {
    listen 443 ssl http2;
    server_name import.bbtb.app;

    ssl_certificate /etc/letsencrypt/live/import.bbtb.app/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/import.bbtb.app/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    # AASA — точный путь, обязательный MIME type
    location = /.well-known/apple-app-site-association {
        default_type application/json;
        alias /var/www/import.bbtb.app/apple-app-site-association;
        # Разумный кеш для браузеров; Apple CDN имеет свой кеш ~24h независимо от этого
        add_header Cache-Control "public, max-age=3600";
    }

    # Все остальные пути — 404 (DEEP-03 landing page deferred до v1+)
    location / {
        return 404;
    }
}

# HTTP → HTTPS redirect для браузеров
# NB: Apple CDN никогда не обращается по HTTP — только по HTTPS 443.
server {
    listen 80;
    server_name import.bbtb.app;
    return 301 https://$host$request_uri;
}
```

### Шаг 3. Включить vhost и получить TLS-сертификат

```bash
# Включить site
sudo ln -s /etc/nginx/sites-available/import.bbtb.app /etc/nginx/sites-enabled/

# Проверить конфиг без restart
sudo nginx -t
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful

# Получить сертификат Let's Encrypt через certbot
# (certbot автоматически добавит ssl_certificate строки в конфиг)
sudo certbot --nginx -d import.bbtb.app

# Перезагрузить nginx
sudo systemctl reload nginx
```

**Если certbot ещё не установлен:**

```bash
sudo apt install certbot python3-certbot-nginx   # Ubuntu/Debian
# или
sudo yum install certbot python3-certbot-nginx    # CentOS/RHEL
```

**Auto-renewal** (certbot настраивает cron/systemd timer автоматически при установке):

```bash
sudo certbot renew --dry-run   # проверить что auto-renewal работает
```

---

## Option B — Cloudflare Pages (альтернатива без VPS)

**Когда выбирать Option B:** Нет существующего VPS, или нужен zero-config deploy за 5 минут.

### Шаг 1. Создать репозиторий

Создать новый репозиторий `bbtb-aasa` (приватный OK) на GitHub/GitLab со следующей структурой:

```
bbtb-aasa/
└── public/
    ├── _headers
    └── .well-known/
        └── apple-app-site-association
```

### Шаг 2. Создать файл AASA

Содержимое `public/.well-known/apple-app-site-association` — точный JSON из раздела «AASA Content» выше.

### Шаг 3. Создать _headers файл

Содержимое `public/_headers`:

```
/.well-known/apple-app-site-association
  Content-Type: application/json
  Cache-Control: public, max-age=3600
```

**Важно:** В `_headers` отступ перед `Content-Type` и `Cache-Control` — два пробела (не таб). Cloudflare Pages требует именно пробелы.

### Шаг 4. Подключить к Cloudflare Pages

1. Cloudflare Dashboard → **Workers & Pages** → **Create** → **Pages** → **Connect to Git**.
2. Выбрать репозиторий `bbtb-aasa`.
3. Build settings:
   - Framework preset: `None`
   - Build command: (оставить пустым)
   - Build output directory: `public`
4. Нажать **Save and Deploy**.

### Шаг 5. Настроить кастомный домен

1. В Cloudflare Pages → проект `bbtb-aasa` → **Custom domains** → **Set up a custom domain**.
2. Ввести `import.bbtb.app`.
3. Cloudflare автоматически:
   - Создаёт DNS-запись в зоне `bbtb.app` (если домен в Cloudflare DNS)
   - Провижнит TLS-сертификат через Universal SSL

**Если домен НЕ в Cloudflare DNS:** Добавить CNAME вручную у регистратора: `import` → `bbtb-aasa.pages.dev`.

---

## Verification (обязательно после deploy — 4 проверки)

Выполнить все 4 команды. Все должны пройти перед тем как двигаться к Task 4.3.

### Проверка 1. HTTP 200 + Content-Type

```bash
curl -I https://import.bbtb.app/.well-known/apple-app-site-association
```

Ожидаемый результат:

```
HTTP/2 200
content-type: application/json
content-length: (около 250 байт)
```

**Если Content-Type: text/plain** — проблема в nginx конфиге (пропущен `default_type application/json`) или Cloudflare Pages `_headers` файл не применился. Apple CDN **отклонит** файл с неверным MIME.

### Проверка 2. JSON валидность

```bash
curl -s https://import.bbtb.app/.well-known/apple-app-site-association | jq .
```

Ожидаемый результат:

```json
{
  "applinks": {
    "details": [
      {
        "appIDs": [
          "UAN8W9Q82U.app.bbtb.client.ios",
          "UAN8W9Q82U.app.bbtb.client.macos"
        ],
        "components": [
          {
            "/": "/import*"
          }
        ]
      }
    ]
  }
}
```

**Если jq возвращает parse error** — файл содержит невалидный JSON или UTF-8 BOM. Пересоздать файл.

### Проверка 3. Отсутствие redirect-цепочки

```bash
curl -sIL https://import.bbtb.app/.well-known/apple-app-site-association | grep -c "HTTP/"
```

Ожидаемый результат: `1` (ровно один HTTP response — нет промежуточных 301/302).

**Если результат 2 или больше** — сервер делает redirect перед отдачей AASA. Apple CDN не следует за redirects и получит ошибку. Исправить конфиг nginx (`location =` должен отдавать 200 напрямую).

### Проверка 4. Apple CDN debug endpoint

```bash
curl "https://app-site-association.cdn-apple.com/a/v1/import.bbtb.app"
```

Ожидаемый результат: тот же JSON (Apple-processed форма).

**Если 404** — Apple CDN ещё не fetched AASA. Это нормально при первом деплое — Apple CDN делает fetch при install/update приложения, не proactively. Установить Debug build на физическое устройство → подождать 5–10 минут → повторить команду. Либо использовать `?mode=developer` энтайтлмент (см. § «Debug bypass»).

---

## Common Issues

**404 от Apple CDN даже через 30 минут:**
Apple CDN fetches AASA при install/update приложения — не по расписанию. Установить/переустановить Debug build на physical device → подождать → retry. Либо использовать `?mode=developer` в энтайтлменте (см. § «Debug bypass»).

**Content-Type: text/plain возвращает nginx:**
`default_type application/json` строка пропущена или overridden `application/octet-stream`. Проверить nginx site config: `sudo nginx -T | grep -A5 "apple-app-site"`. После исправления — `sudo nginx -t && sudo systemctl reload nginx`.

**TLS ошибки при curl:**
Проверить сертификат: `curl -v https://import.bbtb.app/.well-known/apple-app-site-association`. Истёкший Let's Encrypt cert: `sudo certbot renew`. Обычно auto-renewal работает через cron — но при первом деплое может потребоваться ручная проверка.

**Apple CDN кеш до 24h — изменения AASA не видны:**
После изменения AASA file существующие устройства получат обновление только при следующем install/update приложения или при периодическом background refresh (нет guaranteed schedule). Для UAT тестирования изменений — использовать `?mode=developer` в энтайтлменте Debug build.

**Universal Links открывает Safari вместо приложения:**
Означает что Apple CDN не может получить или обработать AASA. Проверить: (1) DNS propagated (`dig import.bbtb.app +short`), (2) HTTPS работает (Проверка 1), (3) Content-Type корректный (Проверка 1), (4) JSON валидный (Проверка 2). Дополнительно в Console.app на device → filter `swcd` → искать ошибки `import.bbtb.app`.

**Associated Domains capability не активна в Apple Developer Portal:**
Custom scheme `bbtb://` работает, но Universal Link открывает Safari. `Console.app` → filter `swcd` → «failed to fetch AASA» или «capability not registered». Решение: developer.apple.com → Certificates, IDs & Profiles → App IDs → `app.bbtb.client.ios` → Associated Domains → Enable. Повторить для `app.bbtb.client.macos`. Пересоздать provisioning profiles в Xcode.

---

## Debug Bypass (для UAT в Wave 4 Task 4.3)

При iterative UAT тестировании изменений AASA Apple CDN может кешировать старую версию до 24 часов. Для bypass:

### Включить developer mode в энтайтлменте

В Xcode, в файле `BBTB/App/iOSApp/BBTB-iOS.entitlements`, изменить строку:

```xml
<!-- Было: -->
<string>applinks:import.bbtb.app</string>

<!-- Стало (только для Debug UAT): -->
<string>applinks:import.bbtb.app?mode=developer</string>
```

Аналогично для macOS: `BBTB/App/macOSApp/BBTB-macOS.entitlements`.

С `?mode=developer` системный демон `swcd` обходит Apple CDN и идёт напрямую к `import.bbtb.app` при каждом запросе.

**Сборка на физическое устройство** (Simulator не поддерживает Universal Links в полной мере). Тапнуть Universal Link → должен открыться app без 24h задержки.

### КРИТИЧЕСКИ ВАЖНО: откатить перед финальным commit

**`?mode=developer` в production энтайтлменте вызывает отклонение Apple Review.** Перед archive для TestFlight / App Store:

1. Убрать `?mode=developer` из обоих `.entitlements` файлов.
2. Убедиться в финальном commit что строки содержат ровно `applinks:import.bbtb.app` без суффиксов.
3. Проверить: `grep -r "mode=developer" BBTB/App/*/BBTB-*.entitlements` — должен возвращать пустой результат.

---

## Update Procedure (v1+ — когда появится DEEP-03 токен-эндпоинт)

Когда в v1+ добавится `/c/{token}` endpoint на `import.bbtb.app`:

### 1. Обновить AASA файл

Добавить второй компонент в `components`:

```json
{
  "applinks": {
    "details": [{
      "appIDs": [
        "UAN8W9Q82U.app.bbtb.client.ios",
        "UAN8W9Q82U.app.bbtb.client.macos"
      ],
      "components": [
        { "/": "/import*" },
        { "/": "/c/*" }
      ]
    }]
  }
}
```

**Option A (nginx):** Обновить файл на VPS и перезагрузить nginx.

**Option B (Cloudflare Pages):** Обновить файл в репозитории и push — Pages автоматически деплоит.

### 2. Подождать Apple CDN cache flush

- Apple CDN обновит кеш при следующем install/update приложения (до 24h)
- Для immediate effect: попросить тестировщиков переустановить приложение
- `?mode=developer` энтайтлмент для Debug builds ускоряет проверку

### 3. iOS/macOS код менять НЕ нужно

Энтайтлмент `applinks:import.bbtb.app` покрывает весь домен. AASA управляет path matching на серверной стороне. Новые пути подхватываются без изменений кода или нового релиза приложения.

---

## Maintainer Reference

| Параметр | Значение |
|----------|----------|
| Team ID | `UAN8W9Q82U` |
| App ID iOS | `app.bbtb.client.ios` |
| App ID macOS | `app.bbtb.client.macos` |
| AASA URL | `https://import.bbtb.app/.well-known/apple-app-site-association` |
| Apple CDN check | `https://app-site-association.cdn-apple.com/a/v1/import.bbtb.app` |
| Supported paths (v0.9) | `/import*` |
| Supported paths (v1+) | `/import*` + `/c/*` |
| Max file size (Apple limit) | 128 KB |
| Current file size | ~250 bytes |
| Required Content-Type | `application/json` |
| TLS requirement | TLS 1.2+ (Let's Encrypt или Cloudflare) |
| Apple CDN cache TTL | Up to 24 hours |
| Debug bypass | `?mode=developer` в энтайтлменте (Debug builds only) |

---

*Phase: 9-Deep-Links*
*Written: 2026-05-15*
*Source: 09-RESEARCH.md § Pattern 6 + Pitfall 2 + Example 7; 09-CONTEXT.md D-01 + D-02*
