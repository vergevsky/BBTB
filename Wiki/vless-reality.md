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

## РЕШЕНИЕ Phase 1 W5 (2026-05-11) — Server-Client flow mismatch (template hardcode bug)

После шести раундов device-debug на iPhone 16 iOS 26 (rounds 1-5: гипотезы про MTU, DNS, route.resolve, stack, subnet mask — все мимо; round 6: победа) **локализовали реальный root cause: server-client mismatch в VLESS `flow` parameter**.

### Симптом до фикса

TCP+VLESS+Reality handshake проходил, но затем **каждое** TCP-соединение через туннель закрывалось через ~28-30мс после Vision-ready, оба направления одновременно, без error message. Все 152→219→274→177 соединений в трёх раундах — одинаковый паттерн.

### Реальная причина

| Сторона | Конфигурация `flow` |
|---|---|
| **Сервер (Xray в Латвии)** | `flow: ""` (Vision НЕ включён) |
| **Наш клиент** (`SingBoxConfigTemplate.vless-reality.json` hardcode) | `flow: "xtls-rprx-vision"` (с Vision) |

Клиент отправлял VLESS+Reality пакеты в **Vision frame format** (XtlsFilterTls + XtlsPadding обёртка), сервер ждал обычный VLESS+Reality **без Vision** → сервер не мог распарсить → закрывал соединения детерминированно через ~30мс. Это объясняет:

- **Почему оба направления close в одну мс**: server-side close, оба goroutine в bidirectional pipe внутри sing-box получают EOF одновременно.
- **Почему "no error logged"**: для sing-box это **штатный** server close — нечего логировать как ошибку.
- **Почему 28-30мс**: 1 RTT клиент↔сервер для FIN.
- **Почему Apple/iCloud heartbeat "работали" в первых раундах**: они отправляли тривиальные пакеты (несколько байт), которые успевали проскочить до server-side close — но реальная двусторонняя коммуникация ломалась всегда.

### Финальный фикс (commit `21673fd`)

```json
"flow": ""   // ← было "xtls-rprx-vision"
```
Одна строка в `SingBoxConfigTemplate.vless-reality.json`. Теперь клиент matches server config.

### Почему Happ работал

Happ читает VLESS URI пользователя и использует **указанный там flow** (или его отсутствие). У пользователя в URI flow либо отсутствовал, либо был "" — Happ это уважал и matches сервер. Наш клиент **игнорировал** flow из URI (`VLESSURIParser` парсит, но `ConfigBuilder` использует template hardcode) — отсюда mismatch.

### Bug в нашем коде, не в sing-box

Vision в sing-box, скорее всего, **работает корректно** — мы просто заставляли его говорить на языке, который сервер не понимал.

### Результаты после фикса (round 6, 2026-05-11 21:16)

- 126 connections, **56 (44%) >500мс, 54 (43%) >2 сек, 39 (31%) >10 сек, MAX 26.14 сек**
- Safari → `https://api.ipify.org` показывает IP сервера ✓
- `connection: connection download closed` (нормальный client-side EOF, не server-initiated teardown)

### Что попробовали безуспешно (rounds 1-5) — false leads из-за неверной гипотезы

| Round | Гипотеза | Результат |
|---|---|---|
| 1 | DNS pipeline + sniff fix + fakeip | DNS работает; teardown остаётся (не root cause, но pipeline сам по себе корректный) |
| 2 | MTU 9000 → 1500 | Teardown идентичен (Codex MTU-гипотеза disproven) |
| 3 | Снять `route.resolve` (Gemini hyp.) | hostname теперь в VLESS, anycast routing фиксится; но teardown остаётся (поскольку реальная причина была flow mismatch) |
| 4 | TUN `stack: gvisor → mixed` | Crash-loop в нашей сборке libbox |
| 5 | Subnet mask `/30 → /28` (alignment с NE) | Teardown идентичен |
| 6 | `flow: "xtls-rprx-vision" → ""` | **WIN** — matches server |

### TODO (Phase 5 или Phase 2)

**Урок:** template НЕ должен hardcode'ить параметры, которые приходят из VLESS URI пользователя.

- **`${VLESS_FLOW}` placeholder** в `SingBoxConfigTemplate.vless-reality.json` для `flow` поля
- **`ConfigBuilder.buildSingBoxJSON`** подставляет flow из parsed URI
- **`VLESSURIParser` default** изменить с `"xtls-rprx-vision"` на `""` — большинство простых Reality серверов не используют Vision
- **Документация для пользователей**: «если ваш VLESS URI содержит `?flow=xtls-rprx-vision`, мы используем Vision, иначе — без него»

Это нужно сделать перед v0.1 production release, иначе при добавлении второго сервера/импорте URI другого формата проблема повторится.

### Related GitHub issues (для контекста, не нужны больше)

- [SagerNet/sing-box#4023](https://github.com/SagerNet/sing-box/issues/4023) — описывает похожий симптом, скорее всего это тоже flow mismatch у кого-то
- [XTLS/Xray-core#5966](https://github.com/XTLS/Xray-core/issues/5966) — TLS EOF after Vision setup
- [hiddify/hiddify-app#758](https://github.com/hiddify/hiddify-app/issues/758) — для контекста по `packet_encoding`

## Related pages

- [[protocols-overview]]
- [[anti-dpi-techniques]]
- [[tspu]]
- [[tech-stack]]
- [[xray-localhost-vulnerability]]
- [[dns-pipeline-decisions]] — DNS pipeline решения Phase 1 W5
