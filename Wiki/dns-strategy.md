---
name: DNS-стратегия
description: DoH внутри туннеля, encrypted bootstrap, whitelist провайдеров, опциональный AdBlock через DNS
type: project
---

# DNS-стратегия

**Summary**: DNS-over-HTTPS внутри туннеля к одному из whitelisted провайдеров (Cloudflare по умолчанию). Encrypted bootstrap до подключения. Опция «свой DNS» в Расширенных. Опциональный AdBlock через AdGuard/NextDNS.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Принципы

- **Никаких незашифрованных DNS-запросов** (DNS — Domain Name System — система доменных имён). Стандартный UDP-DNS на 53 порту виден ТСПУ и провайдеру — это leak.
- **Bootstrap проблема**: чтобы соединиться с VPN-сервером, нужно сначала резолвить его домен. Этот первый запрос должен быть тоже зашифрованным.

## Внутри туннеля

DoH (DNS over HTTPS — DNS поверх HTTPS) к одному из whitelisted провайдеров:

| Провайдер | Адрес | Особенности |
|-----------|-------|-------------|
| Cloudflare | `1.1.1.1` | **По умолчанию** |
| NextDNS | — | Поддерживает фильтры |
| AdGuard DNS | — | AdBlock из коробки |
| Quad9 | `9.9.9.9` | Анти-malware |

В Расширенных:
- выбор провайдера или «свой DNS»
- опция «AdBlock через DNS» — переключение на AdGuard или NextDNS с включёнными фильтрами

## Bootstrap DNS

Для первого резолва домена VPN-сервера — encrypted bootstrap через `1.1.1.1` или `8.8.8.8`. Без этого первый запрос ушёл бы открытым DNS — leak.

## DNS leak protection

Это часть Definition of Done для v0.6:
- DNS leak-test пройден (через dnsleaktest.com и аналогичные)
- В сочетании с `enforceRoutes = true` из [[kill-switch]] утечки исключаются

## Roadmap

- **v0.6** — DoH, encrypted bootstrap, whitelist провайдеров
- **v0.10** — финальные настройки в Расширенных

## Related pages

- [[kill-switch]]
- [[ipv6-strategy]]
- [[anti-dpi-techniques]]
- [[ux-specification]]
