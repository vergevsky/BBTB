---
name: Anti-DPI техники
description: uTLS mimicking, фрагментация TLS ClientHello, packet padding, mux, CDN-фронтинг — все слои защиты от DPI
type: project
---

# Anti-DPI техники

**Summary**: Набор техник для обхода DPI поверх протоколов и транспортов — uTLS fingerprint mimicking, фрагментация TLS ClientHello, packet padding, random delay, mux, CDN-фронтинг.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Зачем

Сами по себе [[vless-reality|VLESS+Reality]] и [[transports|транспорты]] дают базовый уровень маскировки. Эти техники — дополнительные слои защиты от ТСПУ (см. [[tspu]]).

## uTLS fingerprint mimicking

Клиент представляется DPI как Chrome / Firefox / Safari. По умолчанию **randomized** — fingerprint выбирается случайно при каждом подключении, чтобы он не был статичным.

В Расширенных пользователь может зафиксировать конкретный fingerprint (Chrome/Firefox/Safari) или оставить random.

## Фрагментация TLS ClientHello

Первый пакет TLS-handshake разбивается на несколько TCP-пакетов так, чтобы DPI **не успел распарсить SNI** (Server Name Indication — указание имени сервера). DPI видит начало TLS, но не видит, к какому домену идёт соединение.

## Packet padding

Добавляем случайные байты к пакетам, чтобы статистические характеристики (длина, частота) **не палили VPN-трафик**. Без padding'а DPI может опознать VPN по типичным длинам пакетов даже при шифровании.

## Random TCP/UDP delay

Рандомные задержки между пакетами для **убийства timing-based DPI**. DPI анализирует тайминги соединений — если они слишком регулярны, это признак автоматизированного протокола.

## Mux (мультиплексирование)

Несколько логических соединений мультиплексируются в **одно TCP-соединение**. Это:

- не палит количество одновременных сессий пользователя
- маскирует VPN под одно долгоживущее HTTPS-соединение (что выглядит как нормальный браузерный keep-alive)

## CDN-фронтинг

Поддержка работы через Cloudflare/Fastly как fallback transport. DPI видит соединение к Cloudflare (общий CDN — Content Delivery Network), а не к VPN-серверу напрямую. Появляется в v0.10 (см. [[release-roadmap]]).

## Разные порты

Разные протоколы — на разных портах для маскировки:

- **443** — приоритет, маскировка под HTTPS
- **80, 8443, 2096** и другие — дополнительные

## Защита целостности

- **Certificate pinning** для соединения с панелью подписок и rules.json
- **Ed25519-подпись** для rules.json (см. [[rules-engine]])

## Roadmap

Полный набор anti-DPI техник появляется в **v0.7** (см. [[release-roadmap]]).

## Связь с детектом VPN на устройстве

Anti-DPI техники защищают от **сетевого** DPI. Отдельная задача — защита от **локального** детекта VPN на устройстве пользователя (см. [[rkn-detection-methodology]], [[vpn-detection-by-apps]]). Это разные угрозы и разные защиты.

## Related pages

- [[tspu]]
- [[vless-reality]]
- [[transports]]
- [[protocols-overview]]
- [[rules-engine]]
