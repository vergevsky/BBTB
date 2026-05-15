# Phase 9: Deep Links — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 09-deep-links
**Areas discussed:** Server backend scope, URL format, connect/disconnect, macOS scope, Error UX

---

## Pre-discussion context (user-provided)

Перед выбором областей пользователь предоставил:
- VPS с панелью Marzban (Python/FastAPI, subscription URLs `/sub/{token}`)
- Домен `vergevsky.ru` (миграция запланирована)
- Не хочет писать кастомную панель управления deep link токенами с нуля

Codex delegation (architect thread `019e2a7f-d023-7020-bc60-72ccb8116ba5`): рекомендовал Shlink + nginx + Marzban для v1+ токен-менеджмента. AASA через nginx. Marzban-only (Quick) как альтернатива без стабильных алиасов.

---

## Server Backend

| Option | Description | Selected |
|--------|-------------|----------|
| Shlink + nginx + Marzban | Shlink Docker, web UI, стабильные алиасы, redirect к Marzban | |
| Marzban-only + nginx | Прямой прокси /c/{token} → Marzban /sub/{token} | |
| **Deferred to v1+** | DEEP-03/DEEP-04 переносятся, Phase 9 = только AASA | ✓ |

**User's choice:** Отложить токен-эндпоинт и landing page на v1+. Заложить архитектурные решения для будущей интеграции.
**Notes:** Пользователь сказал «я хочу отложить эту фичу на версию 1+, но заложим архитектурные решения». DeepLinkRouter проектируется как extensible actor (ProtocolRegistry pattern). TokenFetcher protocol — заглушка в пакете.

---

## Import URL Format

| Option | Description | Selected |
|--------|-------------|----------|
| **?url={subscription_url}** | bbtb://import?url=https://panel.../sub/abc123 — subscription URL | ✓ |
| ?config={vless_uri} | Inline VLESS URI в параметре — длинный URL | |
| Оба варианта | DeepLinkRouter понимает и ?url= и ?config= | |

**User's choice:** `?url={subscription_url}` — основной и единственный формат v0.9.
**Notes:** ConfigImporter.importFromRawInput() уже обрабатывает subscription URLs.

---

## Connect/Disconnect Actions

| Option | Description | Selected |
|--------|-------------|----------|
| connect → текущий сервер | bbtb://connect без параметров | |
| connect?server={id} | По конкретному UUID SwiftData | |
| **Только import, connect/disconnect deferred** | Phase 9 = только import action | ✓ |

**User's choice:** Deferred — нет подтверждённого use case.
**Notes:** DeepLinkRouter логирует unhandled URLs.

---

## macOS Scope

| Option | Description | Selected |
|--------|-------------|----------|
| **iOS + macOS** | Оба получают bbtb:// + Universal Links, AASA включает оба App ID | ✓ |
| iOS-only | Только iPhone, macOS откладывается | |

**User's choice:** Оба платформы.
**Notes:** Team ID UAN8W9Q82U. App IDs: app.bbtb.client.ios + app.bbtb.client.macos. Entitlements в обоих targets.

---

## Error UX

| Option | Description | Selected |
|--------|-------------|----------|
| Toast-баннер | ImportProgressOverlay — существующий, не блокирует | |
| **Alert** | Modal SwiftUI .alert с текстом ошибки + OK | ✓ |
| Silent + лог | Ничего не показываем | |

**User's choice:** Alert (UIAlertController / SwiftUI .alert).
**Notes:** Использовать существующий alert-механизм MainScreenViewModel.

---

## Claude's Discretion

- Структура SwiftPM пакета `DeepLinks` (по аналогии с RulesEngine)
- Timeout и retry в ImportHandler
- Порядок Tuist/Xcode entitlements wiring

## Deferred Ideas

- DEEP-03 токен-эндпоинт → v1+ (Shlink рекомендован Codex)
- DEEP-04 landing page → v1+
- bbtb://connect, bbtb://disconnect → когда появится use case
- macOS deep links можно добавить отдельно, но решили сделать сразу
