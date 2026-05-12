---
name: Trojan
description: Trojan протокол — TLS-based VPN, выглядит как обычный HTTPS; реализован в v0.2
type: project
---

# Trojan

**Summary**: TLS-based протокол, который снаружи выглядит как обычный HTTPS-трафик. Клиент отправляет запросы через TLS на порт 443; DPI видит TLS handshake к реальному домену. Поддерживаемые транспорты: TCP+TLS (прямое TCP-соединение внутри TLS) и WS+TLS (WebSocket поверх TLS).

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md, Phase 2 UAT 2026-05-12

**Last updated**: 2026-05-12

---

## Зачем

[[vless-reality|VLESS+Reality]] — главный anti-ТСПУ протокол, но требует специфичного сервера с Reality-config. Trojan — второй по приоритету протокол: более распространённый, большинство hosted-серверов его поддерживают. Используется в [[protocols-overview|auto-fallback]] цепочке как запасной вариант.

## Транспорты

| Транспорт | Описание | ALPN | Статус |
|-----------|----------|------|--------|
| **TCP+TLS** | Прямое TCP-соединение внутри TLS-туннеля. Стандартный вариант. | `["h2", "http/1.1"]` (по умолчанию сервера) | ✓ v0.2 |
| **WS+TLS** | WebSocket-соединение поверх TLS. Проходит через CDN-ноды, совместим с Nginx-обратным прокси. | `["http/1.1"]` — **только HTTP/1.1** | ✓ v0.2 |

### ALPN и WS: критическое правило (R12)

**Правило**: для Trojan-WS НЕЛЬЗЯ включать `h2` в ALPN.

**Причина**: при TLS handshake, если в ALPN передаётся `["h2", "http/1.1"]`, TLS-сервер выбирает `h2` (HTTP/2). Sing-box затем пытается выполнить WebSocket upgrade как HTTP/1.1 запрос (`GET / HTTP/1.1\r\nUpgrade: websocket\r\n...`), но соединение уже работает в режиме h2 (HTTP/2 — бинарный, multiplexed). WebSocket upgrade отвергается → `i/o timeout` через ~15 секунд.

**Фикс**: `PoolBuilder.buildTrojanOutbound()` фильтрует `"h2"` из ALPN при `transport == .ws`. Если после фильтрации ALPN оказывается пустым — подставляется `["http/1.1"]`. Аналогично в шаблоне `trojan-ws.json` для одиночного сервера.

```swift
// PoolBuilder.swift — Phase 2 commit 4255a77
let isWS: Bool
if case .ws = parsed.transport { isWS = true } else { isWS = false }
let alpn: [String]
if isWS {
    let filtered = parsed.alpn.filter { $0 != "h2" }
    alpn = filtered.isEmpty ? ["http/1.1"] : filtered
} else {
    alpn = parsed.alpn
}
```

## URI-формат

```
trojan://<password>@<host>:<port>?sni=<sni>&fp=<fingerprint>&type=<transport>&host=<ws-host>&path=<ws-path>#<name>
```

| Параметр | Описание | Дефолт при пустом значении |
|----------|----------|-----------------------------|
| `sni` | SNI для TLS маскировки | `host` сервера |
| `fp` | uTLS fingerprint (chrome, firefox, safari, ...) | `"chrome"` |
| `type` | Транспорт: `tcp` или `ws` | `tcp` |
| `host` | Для WS: HTTP Host заголовок (CDN-домен) | SNI сервера |
| `path` | Для WS: путь WebSocket endpoint | `"/"` |

### Особенность парсинга `fp=`

Если URI содержит `fp=` с пустым значением (не `fp` вовсе, а `fp=` с пустой строкой), `URLComponents` возвращает `""` вместо `nil`. Явная проверка пустой строки обязательна:

```swift
// TrojanURIParser.swift — Phase 2 commit 6d0f798
let fp = q["fp"].flatMap { $0.isEmpty ? nil : $0 } ?? "chrome"
```

## Sing-box конфигурация

Пример для WS-транспорта (генерируется `PoolBuilder`):

```json
{
  "type": "trojan",
  "tag": "trojan-0",
  "server": "example.com",
  "server_port": 443,
  "password": "...",
  "tls": {
    "enabled": true,
    "server_name": "example.com",
    "utls": { "enabled": true, "fingerprint": "chrome" },
    "alpn": ["http/1.1"]
  },
  "transport": {
    "type": "ws",
    "path": "/path",
    "headers": { "Host": "cdn.example.com" }
  }
}
```

## Multi-server и urltest

При нескольких Trojan-серверах (или смеси Trojan + VLESS) `PoolBuilder` оборачивает все outbound-ы в `urltest` selector:

```json
{
  "type": "urltest",
  "tag": "selector",
  "outbounds": ["trojan-0", "trojan-1"],
  "url": "https://www.gstatic.com/generate_204",
  "interval": "1m"
}
```

Sing-box автоматически замеряет latency каждую минуту и направляет трафик через наименьшую задержку. При недоступности одного outbound — переключается на другой без вмешательства пользователя.

## Реализация в проекте (v0.2)

- **`BBTB/Packages/Protocols/Trojan/`** — SwiftPM модуль
- **`BBTB/Packages/ConfigParser/Sources/ConfigParser/TrojanURIParser.swift`** — парсинг `trojan://` URI
- **`BBTB/Packages/ConfigParser/Sources/ConfigParser/PoolBuilder.swift`** — генерация sing-box JSON, включая WS-ALPN фильтрацию
- **`BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json`** — шаблон для одиночного WS-сервера

Импорт — через [[config-importer]] (те же 3 пути: подписка / JSON / QR).

## Статус

- ✓ **v0.2** — Trojan TCP+TLS и WS+TLS реализованы. UAT T5 PASS на реальном iPhone 2026-05-12.
- Следующий шаг — VLESS+XTLS-Vision (без Reality) в **v0.4**.

## Related pages

- [[protocols-overview]]
- [[vless-reality]]
- [[config-importer]]
- [[architecture]]
- [[kill-switch]]
- [[release-roadmap]]
- [[security-gaps]]
