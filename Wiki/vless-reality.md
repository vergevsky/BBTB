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

## Related pages

- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[tspu]]
- [[tech-stack]]
- [[xray-localhost-vulnerability]]
