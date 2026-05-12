# Phase 5: Transports — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-12
**Phase:** 5-transports
**Areas discussed:** Transport scope per protocol, ParsedVLESSTLS transport model, Advanced Settings transport UI, TransportRegistry API, Scalability improvements

---

## XHTTP Support Verification

| Option | Description | Selected |
|--------|-------------|----------|
| Sing-box поддерживает XHTTP | Реализовать в Phase 5 | |
| Sing-box не поддерживает XHTTP | Убрать из Phase 5, defer | ✓ |

**User's choice:** Убрать из Phase 5, defer на потом
**Notes:** Пользователь усомнился в поддержке XHTTP в sing-box. Проведена проверка: два агента (local codebase scan + web search) подтвердили — sing-box 1.13.x не поддерживает XHTTP (issue #3550, мейнтейнер явно отказал). TRANSP-01 переходит в backlog.

---

## Transport scope per protocol

| Option | Description | Selected |
|--------|-------------|----------|
| VLESS+TLS only | Phase 5 только для VLESS+TLS | |
| VLESS+TLS + Trojan | Оба протокола, + расширенный список | ✓ |

**User's choice:** VLESS+TLS и Trojan получают: WebSocket, HTTP (h2), HTTPUpgrade, gRPC. TCP уже реализован.
**Notes:** Пользователь изначально запросил расширенный список (TCP, TLS+ECH, WS, HTTP, HTTPUpgrade, gRPC, QUIC, smux, yamux, h2mux). Проведено уточнение: smux/yamux/h2mux — мультиплексирование (Phase 7), ECH — TLS-расширение (Phase 7), QUIC для VLESS/Trojan — backlog. Phase 5 фокусируется на 4 стандартных transport overlay.

---

## ParsedVLESSTLS transport model

| Option | Description | Selected |
|--------|-------------|----------|
| Typed enum per-protocol | Каждый протокол имеет свой TransportType | |
| String + optional fields | networkType + wsPath? + grpcServiceName? и т.д. | |
| Shared TransportConfig enum | Один enum для всех протоколов в VPNCore | ✓ |

**User's choice:** Вариант 3 — Shared TransportConfig enum
**Notes:** Пользователь запросил объяснение без программистских терминов. После разъяснения с аналогией «одна полка vs отдельные полки для каждого протокола» пользователь выбрал масштабируемый вариант. Ключевой аргумент: при 15 протоколах и 50 транспортах добавление нового транспорта — 1 место правки вместо 15.

---

## Advanced Settings transport UI

| Option | Description | Selected |
|--------|-------------|----------|
| Override на сессию | AppStorage, теряется при рестарте | |
| Per-server persistent | ServerConfig.transportOverride, SwiftData | ✓ |
| Read-only display | Только отображение | |

**User's choice:** Per-server persistent — `ServerConfig.transportOverride: TransportConfig?`
**Notes:** nil = Авто (брать transport из URI).

| Entry point | Description | Selected |
|-------------|-------------|----------|
| Swipe → «Править» | Swipe left action | |
| Long press → context menu | Контекстное меню | |
| Шеврон › → ServerDetailView | Новый экран деталей | ✓ |

**User's choice:** Шеврон `›` справа у каждого сервера → navigation push на `ServerDetailView`.
**Notes:** Пользователь предоставил референсные скриншоты `/Users/vergevsky/Downloads/IMG_0508.PNG` и `/Users/vergevsky/Downloads/IMG_0509.PNG` (Hiddify-подобный клиент). Уточнение: стиль из DesignSystem проекта, не копировать Hiddify. Поля добавляются по мере реализации в следующих фазах. Picker всегда виден (не developer-only). Было уточнено, что flow и fingerprint уже реализованы в парсерах → можно показывать в Phase 5.

---

## TransportRegistry API (CORE-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Metadata only | Только название + supported protocols; JSON в PoolBuilder | |
| Metadata + JSON block | TransportHandler строит свой transport JSON block | ✓ |

**User's choice:** Metadata + JSON block
**Notes:** Пользователь применил те же критерии масштабируемости: при 50 транспортах PoolBuilder с «Metadata only» вырастает до 3000 строк с 50 блоками if/else. С «Metadata + JSON block» PoolBuilder остаётся константным размером.

---

## Scalability improvements

| Улучшение | Решение |
|-----------|---------|
| Общий TransportParamParser | ✓ Phase 5 |
| PoolBuilder → coordinator (buildOutbound в протоколах) | ✓ Phase 5 |
| TransportConfig в VPNCore | ✓ VPNCore |

**Notes:** Пользователь явно запросил обсуждение всех аспектов масштабируемости. Выявлены 3 структурные проблемы: дублирование URI-парсинга транспортов, рост PoolBuilder с каждым протоколом, неправильное расположение TransportConfig. Все три исправляются в Phase 5. Правило пользователя: «Всегда между скоростью и качеством — выбирай качество».

---

## Claude's Discretion

- Конкретные sing-box JSON поля для каждого transport block (образец — существующий WS-блок в PoolBuilder)
- Структура тестов для TransportParamParser
- Порядок регистрации транспортных обработчиков в App startup
- Детали API TransportHandler (конкретные параметры методов)

## Deferred Ideas

- XHTTP — backlog (sing-box issue #3550)
- QUIC для VLESS/Trojan — backlog
- smux / yamux / h2mux — Phase 7 (DPI-05)
- ECH — Phase 7 (DPI-02)
- Редактирование TLS-полей в ServerDetailView — Phase 10
