# Phase 10: Advanced settings + Security polish — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 10-Advanced-settings-Security-polish
**Areas discussed:** Scope amendment, CDN-фронтинг UX, Mux toggle, Cert pinning default, Advanced Settings layout

---

## Scope Overview (pre-discussion)

Перед выбором серых зон пользователь запросил plain-language объяснение всех фич Phase 10. Получил обзор 8 настроек с объяснением каждой.

**User decision:** сразу после обзора принял решения по скоупу без дополнительных вопросов.

| Фича | Решение |
|------|---------|
| BIO-01..04 биометрия | Исключить |
| ONDEMAND-01 On-Demand rules UI | Исключить |
| DPI-06 CDN-фронтинг | Включить |
| DPI-08 Cert pinning | Включить |
| DPI-09 uTLS fingerprint picker | Включить |
| DPI-05 Mux | Включить |
| BIO-04 STUN-блок | Включить |
| KILL-04 macOS enforceRoutes | Включить |

**Notes:** Пользователь обозначил правила работы: масштабируемость (20 протоколов, 50+ транспортов), качество > скорость, подробные объяснения, обязательно консультироваться с Codex.

---

## CDN-фронтинг UX

Перед вопросом: Codex-консультация по архитектуре CDN-фронтинга и cert pinning (thread `019e2b02-09fc-77b1-8acc-cc4f794c5235`).

| Option | Description | Selected |
|--------|-------------|----------|
| Auto-fallback без UI | Если основной транспорт не работает — пробуем CDN автоматически | |
| Toggle в Advanced Settings | Глобальный переключатель, применяется к серверам с CDN-поддержкой | ✓ |
| Per-server в деталях | Toggle в карточке каждого сервера | |

**User's choice:** Toggle в Advanced Settings
**Notes:** Пользователь понимает, что CDN-фронтинг зависит от серверной поддержки (Cloudflare Proxy на домене).

---

## Mux toggle

| Option | Description | Selected |
|--------|-------------|----------|
| Auto из URI/YAML | mux=true в конфиге сервера → автоматически | ✓ |
| Toggle в Advanced Settings | Глобальный override | ✓ |
| Per-server в деталях | Toggle в карточке сервера | |

**User's choice:** Оба варианта (auto из URI/YAML + toggle в Advanced Settings)
**Notes:** Двойной контроль — admin сервера задаёт default, пользователь может override глобально.

---

## Cert Pinning — default

| Option | Description | Selected |
|--------|-------------|----------|
| Включён по умолчанию | Максимальная защита. Admin обновляет pin manifest при смене сертификата | ✓ |
| Выключен по умолчанию, toggle в Advanced | Меньше риск поломки при смене сертификата | |

**User's choice:** Включён по умолчанию
**Notes:** Митигация риска lockout — резервный пин + remote Ed25519 manifest (по паттерну rules.json).

---

## Cert Pinning — toggle видимость

| Option | Description | Selected |
|--------|-------------|----------|
| Да, toggle виден | Пользователь видит функцию. Может отключить при смене сертификата | ✓ |
| Нет, скрыть | Проще, но нет аварийного выхода | |

**User's choice:** Да, toggle виден

---

## Advanced Settings — организация секций

| Option | Description | Selected |
|--------|-------------|----------|
| Добавить в существующие секции | Всё в одном списке, длинный скролл | |
| Новые именованные секции | DNS / Anti-DPI / Безопасность / Rules | ✓ |

**User's choice:** Новые секции
**Notes:** Выбрал preview с структурой:
- MinAppVersionBanner
- DNS (AdBlock + Custom DNS)
- Anti-DPI (CDN, Mux, uTLS, STUN)
- Безопасность (Cert pinning, macOS enforceRoutes)
- Rules (viewer + force-update)

---

## Claude's Discretion

- uTLS picker options список (random + Chrome + Firefox + Safari + iOS + Android + Edge)
- CDNProviderAdapter конкретные реализации (CloudflareAdapter, FastlyAdapter)
- Mux тип default (smux, выбран по Codex recommendation)
- Pin manifest `validUntil` enforcement policy (рекомендуется hard reject)
- STUN block warning text в Footer
- macOS enforceRoutes warning text в Footer
- Выносить FrontingEngine в отдельный SwiftPM пакет или нет

## Deferred Ideas

- **BIO-01..04 биометрия** — нет смысла для friends-and-family. Вернуть при 3+ запросах.
- **ONDEMAND-01 «публичные Wi-Fi»** — нет надёжного определения публичности сети. v1.x с SSID whitelist UI.
- **Mux type picker** (smux/yamux/h2mux) — smux default достаточен. Picker → v1.x.
- **Remote CDN IP pool** — v0.10 IP статичный из bundle. Remote sync → v1.x.
- **Config editor / Network diagnostics** — deferred Phase 11+.
