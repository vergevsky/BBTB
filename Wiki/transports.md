---
name: Транспорты
description: XHTTP, gRPC, WebSocket, HTTPUpgrade — обёртки поверх VLESS/VMess
type: project
---

# Транспорты

**Summary**: Четыре транспорта поверх VLESS/VMess — XHTTP (новый рекомендуемый), gRPC, WebSocket, HTTPUpgrade. Регистрируются в проекте аналогично протоколам.

**Sources**: VPN-клиент для macOS и iOS — Промт для Claude Code.md

**Last updated**: 2026-05-11

---

## Что такое транспорт

Транспорт — это обёртка, которая определяет, **как** трафик протокола (VLESS, VMess) ходит по сети. Сам по себе VLESS — это шифрование и протокол передачи; транспорт — это HTTP/WebSocket/gRPC рамка вокруг него, делающая трафик похожим на обычный HTTPS.

## Четыре транспорта

| Транспорт | Особенности | Когда выбирать |
|-----------|-------------|----------------|
| **XHTTP** | Новый рекомендуемый. Маскировка под HTTP/2 multiplexed traffic. | Приоритет для anti-DPI. По умолчанию. |
| **gRPC** | HTTP/2 RPC. Очень устойчив к DPI. | Когда XHTTP блокируется или сервер не поддерживает. |
| **WebSocket** | Легаси, широко поддерживается серверами. | Совместимость со старыми конфигами. |
| **HTTPUpgrade** | Минималистичный, легче gRPC. | Когда нужна минимальная нагрузка. |

## Реализация в проекте

Отдельный SwiftPM-модуль `Packages/Transports/` (см. [[architecture]]). Каждый транспорт — реализация `TransportHandler` протокола. Регистрация через `TransportRegistry.shared.register(...)`, аналогично [[protocols-overview|регистрации протоколов]].

В Расширенных можно вручную выбрать транспорт для дебага (см. [[ux-specification]]).

## Roadmap

Все четыре транспорта добавляются в **v0.5** (см. [[release-roadmap]]).

## Порты

Разные протоколы используются на разных портах для маскировки:

- **443** — приоритет, маскировка под HTTPS
- **80, 8443, 2096** и другие — дополнительные

## CDN-фронтинг

Поддержка работы через Cloudflare/Fastly как fallback transport. Появляется в v0.10. CDN — Content Delivery Network (сеть доставки контента).

## Related pages

- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[architecture]]
- [[release-roadmap]]
