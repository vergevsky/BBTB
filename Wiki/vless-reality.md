---
name: VLESS + Reality
description: Главный anti-ТСПУ протокол проекта — маскировка под TLS-handshake к настоящему сайту
type: project
---

# VLESS + Reality

**Summary**: Главный anti-ТСПУ протокол. Маскируется под TLS-handshake к настоящему публичному сайту (`www.microsoft.com` и т.п.) — DPI видит трафик как обычное HTTPS-соединение с этим сайтом.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Зачем

Reality — это эволюция XTLS-Vision, специально спроектированная для обхода ТСПУ (см. [[tspu]]). В отличие от обычного TLS, где DPI может сделать active probing (попросить у сервера сертификат и обнаружить, что он не от заявленного сайта), Reality использует **настоящий TLS-handshake к настоящему публичному сайту** — клиент устанавливает соединение с реальным `www.microsoft.com`, и только потом «проскальзывает» в туннель через специальный механизм короткого идентификатора.

## Конфиг

Минимальный набор параметров:

- `serverName` — домен для маскировки (тот публичный сайт, под который мы маскируемся)
- `publicKey` — публичный ключ сервера
- `shortId` — короткий идентификатор для распознавания «своего» клиента

## Роль в проекте

- **Единственный поддерживаемый протокол в v0.1** (см. [[release-roadmap]])
- Главный приоритет в auto-fallback цепочке
- На сервере должен быть настроен правильно — без этого Reality не даёт обещанной защиты

## Связь с anti-DPI

Reality сам по себе — это базовая маскировка. Дополнительные техники применяются поверх:

- uTLS fingerprint mimicking (клиент представляется как Chrome/Firefox/Safari)
- Фрагментация TLS ClientHello
- Packet padding

Подробности — [[anti-dpi-techniques]].

## Реализация

В проекте — отдельный модуль `Protocols/VLESSReality/` с реализацией `VPNProtocolHandler` (см. [[architecture]]). Поверх sing-box engine через [[tech-stack|libbox.xcframework]]. xray-core как fallback для специфичных случаев Reality.

## Definition of Done для v0.1

- На реальном iPhone и MacBook можно импортнуть VLESS+Reality конфиг
- Нажать одну кнопку → подключиться
- IP меняется по `https://api.ipify.org`
- При разрыве туннеля [[kill-switch]] блокирует трафик

## Известный issue — Vision short-stream / sing-box vs Xray (2026-05-11)

В ходе Phase 1 W5 device test обнаружено: `xtls-rprx-vision` flow в **sing-box-for-apple** (libbox 1.13.11) ведёт себя несовместимо с server-side **Xray-core** Vision implementation в части коротких single-shot TCP/TLS streams.

**Симптом:** TCP+VLESS+Reality handshake к destination проходит, TLS handshake между приложением и destination через туннель **не завершается** для значительной части пользовательских сайтов (особенно Cloudflare anycast). Apple/iCloud destinations (heartbeat connections) работают.

**Доказательство incompatibility:** [Happ](https://happ.su) (форк sing-box-for-apple с собственными патчами Hiddify) с **тем же VLESS URI**, на **том же iPhone**, в **той же сети** — работает корректно. Значит сервер OK, ключи OK, ТСПУ не виноват — несовместимость именно в sing-box client implementation.

**Related GitHub issues** (2025-2026):
- [SagerNet/sing-box#4023](https://github.com/SagerNet/sing-box/issues/4023) — Reality/VLESS handshake OK, TLS не завершается
- [XTLS/Xray-core#5966](https://github.com/XTLS/Xray-core/issues/5966) — TLS EOF после успешного Vision setup
- [hiddify/hiddify-app#758](https://github.com/hiddify/hiddify-app/issues/758) — Hiddify exports `"packet_encoding": ""` для VLESS+Reality+Vision (намёк на known workaround)

**Что попробовано без успеха:** DoH variants, fakeip+route.resolve, убрать `packet_encoding`, MTU 1400→9000. Все промежуточные фиксы applied (commit `0299af6`).

**Следующие шаги (если решено добивать в Phase 1, не Phase 5):**
1. Trace-level sing-box лог для bit-level diff Apple vs Cloudflare destinations
2. Clone Hiddify-Next репозиторий, найти их sing-box JSON generator, diff с нашим
3. Если ничего не находится — bug report в SagerNet/sing-box и временный switch на Happ как production client

## Related pages

- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[tspu]]
- [[tech-stack]]
- [[xray-localhost-vulnerability]]
- [[dns-pipeline-decisions]] — DNS pipeline решения Phase 1 W5
