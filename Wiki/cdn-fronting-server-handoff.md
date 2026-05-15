# CDN-фронтинг: инструкции для администратора

**Summary**: Инструкции для администратора Marzban по настройке CDN-фронтинга — деплой Cloudflare Worker / Page Rule, добавление `frontingProfile` в subscription payload, и верификация.

**Sources**: `.planning/phases/10-advanced-settings-security-polish/10-RESEARCH.md` (Q2 RESOLVED, A6 admin handoff), Phase 10 10-06-PLAN.md Task 2.

**Last updated**: 2026-05-15 (Phase 10 closure — Phase 11 admin activation pending)

---

## Обзор

CDN-фронтинг позволяет клиентскому приложению подключаться к VPN серверу **через Cloudflare/Fastly edge**, скрывая реальный IP VPN сервера от ТСПУ. DPI видит только HTTPS к Cloudflare — легитимный CDN трафик.

Для активации фичи в production нужно **две части**:

1. **Клиент** (Phase 10 ✅ Done): FrontingEngine SwiftPM package + ConfigImporter call-site + toggle в AdvancedSettingsView.
2. **Сервер** (Phase 11, эта инструкция): Cloudflare Worker/Page Rule + `frontingProfile` JSON в subscription payload.

## Шаг 1: Cloudflare Worker — proxy WS к origin

Admin настраивает Cloudflare Worker (или Page Rule / Tunnel) для проксирования WebSocket соединений к origin VPN серверу.

### Минимальный Worker код

```javascript
// Cloudflare Worker: прокси WS к origin VPN серверу
// Деплой: https://dash.cloudflare.com → Workers & Pages → Create Worker
// Имя: vpn-ws-proxy (или любое)
// Настрой Custom Domain или Route: vpn-edge.yourdomain.com/*

export default {
  async fetch(request, env) {
    // Заменить на реальный IP/hostname origin VPN сервера
    const ORIGIN_HOST = "YOUR_ORIGIN_VPN_SERVER_IP";
    const ORIGIN_PORT = 443;

    if (request.headers.get("Upgrade") === "websocket") {
      // Proxy WebSocket to origin
      const url = new URL(request.url);
      url.hostname = ORIGIN_HOST;
      url.port = ORIGIN_PORT;

      const originResponse = await fetch(url, {
        headers: request.headers,
        method: request.method,
      });
      return originResponse;
    }

    // Non-WS: serve a generic 200 OK (healthcheck)
    return new Response("OK", { status: 200 });
  }
};
```

> **Внимание**: Этот Worker — минимальный пример. Production deployment требует:
> - Rate limiting (Cloudflare WAF)
> - Origin authentication (shared secret header)
> - Error handling + logging
> - Проверки on Cloudflare ToS (разрешён proxy к собственному origin)

### Cloudflare Custom Hostname (Cloudflare for SaaS)

Если не хочешь использовать Worker route, можно настроить **Cloudflare Custom Hostname**:

1. В Cloudflare Dashboard → SSL/TLS → Custom Hostnames → Add Custom Hostname.
2. Вписать: `vpn-edge.yourdomain.com` → указывает на origin VPN сервера.
3. Cloudflare выпускает TLS-сертификат для `vpn-edge.yourdomain.com`.
4. Клиент подключается: `server=1.1.1.1`, `SNI=vpn-edge.yourdomain.com`, `Host=vpn-edge.yourdomain.com`.

## Шаг 2: FrontingProfile JSON blob в Marzban subscription

После настройки Cloudflare Worker/SaaS — добавить `frontingProfile` в subscription payload для каждого сервера, который должен использовать CDN-фронтинг.

### FrontingProfile JSON schema

```json
{
  "provider": "cloudflare",
  "connectHost": "1.1.1.1",
  "connectPort": 443,
  "sniHost": "vpn-edge.yourdomain.com",
  "httpHost": "vpn-edge.yourdomain.com",
  "mode": "domain"
}
```

Поля (см. `FrontingProfile.swift`):

| Поле | Тип | Описание |
|------|-----|----------|
| `provider` | `"cloudflare"` / `"fastly"` / `"custom"` | CDN провайдер (выбирает adapter) |
| `connectHost` | String (IP или hostname) | Dial target — IP Cloudflare anycast edge |
| `connectPort` | Int | TCP port (обычно 443) |
| `sniHost` | String | TLS SNI — твой кастомный домен на Cloudflare |
| `httpHost` | String | HTTP Host header — обычно = sniHost |
| `mode` | `"domain"` | В v0.10 всегда `"domain"` |

### Marzban — как добавить в subscription payload

В Marzban (Xray-core based panel) subscription payload генерируется из user URI. Для кастомного `frontingProfile` добавить как extension параметр в URI или через Marzban template customization:

```
vless://UUID@HOST:PORT?fp=chrome&type=ws&host=...#Server-Name
```

**Вариант A** (extension URI parameter — простой): добавить `frontingProfile` как URL-encoded JSON параметр:
```
vless://...?...&frontingProfile=%7B%22provider%22%3A%22cloudflare%22...%7D#Name
```

**Вариант B** (Marzban custom template): использовать Marzban's custom subscription template для добавления JSON metadata к каждому серверу.

**Текущая реализация клиента** (Phase 10 v0.10): `extractFrontingProfile(for:)` возвращает nil — parsing из URI/metadata NOT YET IMPLEMENTED (Phase 11 task). Когда admin добавит payload, Phase 11 добавит ~5-10 строк parsing в этот helper.

## Шаг 3: Верификация

### Admin-side проверка

```bash
# Проверить что Cloudflare Worker отвечает на healthcheck
curl -H "Host: vpn-edge.yourdomain.com" https://1.1.1.1/
# Expected: 200 OK

# Проверить WebSocket upgrade (через wscat)
wscat -c wss://vpn-edge.yourdomain.com/vless-ws-path \
      --header "Host: vpn-edge.yourdomain.com"
# Expected: connection established (до VPN auth)
```

### User-side проверка (после Phase 11 activation)

1. Открыть BBTB → Settings → Расширенные → включить «CDN-фронтинг».
2. Подключиться к VPN серверу с `frontingProfile`.
3. В Console.app (iPhone/macOS) искать: `Applied CDN fronting: cloudflare`.
4. `ifconfig` → подтвердить `utun*` интерфейс активен.
5. `curl https://api.ipify.org` → IP должен измениться (VPN активен через CDN).

## Известные ограничения

- **Reality / Vision / TUIC / Hysteria2** — CDN-фронтинг не применяется (D-05 blacklist). Только VLESS+TLS/WS и Trojan/WS поддерживают overlay.
- **QUIC → TCP** — Cloudflare CDN не поддерживает QUIC proxy к origin в 2026. TUIC и Hysteria2 остаются через прямое соединение.
- **Admin Cloudflare ToS** — убедись что использование Workers для VPN proxy не нарушает ToS твоего Cloudflare плана (Business/Enterprise обычно разрешают; Free/Pro — проверить).

## Related pages

- [[cdn-fronting-architecture-2026]]
- [[anti-dpi-techniques]]
- [[security-gaps]]
