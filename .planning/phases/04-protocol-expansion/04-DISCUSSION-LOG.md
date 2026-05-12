# Phase 4: Protocol expansion — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 4-protocol-expansion
**Areas discussed:** VLESS scope, Hysteria2 + R1, Clash YAML format

---

## VLESS scope (PROTO-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Только Vision (flow=xtls-rprx-vision) | AnyParsedConfig.vlessVision — строгий case. VLESS+TLS без flow → isSupported=false до Phase 5. | |
| Весь VLESS+TLS без Reality | AnyParsedConfig.vlessTLS — один case, flow опциональный. Vision = частный случай с flow присутствующим. | ✓ |

**User's choice:** Весь VLESS+TLS без Reality
**Notes:** Явный приоритет — максимально широкое покрытие. Пользователь сказал: «Я хочу, чтобы покрытие было как можно шире. Поэтому мы берем любой vless».

---

## Hysteria2 + R1 конфликт (PROTO-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Разрешить insecure=1 для hy2 как исключение из R1 | Реалистично для self-hosted hy2. Вводим allowInsecure флаг в ParsedHysteria2. Прецедент только для hy2. | ✓ |
| Игнорировать insecure=1, всегда strict TLS | R1 соблюдается. Hy2-серверы с self-signed cert → isSupported=false + предупреждение в UI. | |

**User's choice:** Разрешить insecure=1 для hy2 как исключение из R1 (Рекомендуется)
**Notes:** Пользователь выбрал рекомендуемый вариант без дополнительных уточнений.

---

## Clash YAML формат (IMP-05)

| Option | Description | Selected |
|--------|-------------|----------|
| Только proxies: секция | Берём список серверов, маппим поддерживаемые типы в AnyParsedConfig. rules:/proxy-groups: игнорируем. | ✓ |
| proxies: + proxy-groups: для urltest-подсказок | Дополнительно читаем url-test группы как подсказку. Сложнее, неочевиден выигрыш при нашем собственном urltest. | |

**User's choice:** Только proxies: секция (Рекомендуется)
**Notes:** Пользователь просил объяснение «для не программиста» перед выбором. После объяснения выбрал более простой вариант.

---

## Claude's Discretion

- Конкретные sing-box JSON-шаблоны для трёх новых handler'ов — по образцу существующих шаблонов.
- Структура unit-тестов для новых URI-парсеров.
- Порядок регистрации handler'ов при запуске приложения.

## Deferred Ideas

- `ssconf://` (Outline JSON config URL format) — не в скоупе Phase 4, stub.
- Multi-port Hysteria2 (`port: 123,5000-6000`) — не в скоупе Phase 4.
- VMess handler — не в roadmap MVP.
- VLESS транспорты (XHTTP, gRPC, HTTPUpgrade) — Phase 5.
