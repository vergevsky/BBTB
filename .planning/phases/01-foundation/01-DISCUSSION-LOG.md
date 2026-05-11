# Phase 1: Foundation — DISCUSSION-LOG.md

**Date:** 2026-05-11
**Workflow:** `/gsd-discuss-phase 1` (default mode, interactive AskUserQuestion)
**Duration:** одна сессия

> Этот файл — для human reference (аудит, ретроспектива). Downstream-агенты (researcher, planner, executor) консультируются с `01-CONTEXT.md`, не с этим логом.

---

## Гипотеза о серых зонах (analyze_phase)

Phase 1 фазе — Foundation v0.1. Большая часть архитектурных решений уже зафиксирована в `prompts/v2` и `wiki/security-gaps.md` (R1–R6, swift_package_layout, tech_stack, kill switch стратегия, локализация, дистрибуция, лицензирование). Это сужает количество реальных серых зон.

**12 кандидатов в серые зоны (полный список):**
1. Идентификаторы (Bundle ID, Team ID, App Group ID).
2. Тест-сервер VLESS+Reality.
3. Стратегия security review (R1, R6) — порядок в плане.
4. Test-app для SOCKS-сканирования (отдельный таргет vs standalone проект).
5. Структура PacketTunnelExtension iOS↔macOS.
6. Минимальный UI на v0.1.
7. UX-триггер импорта vless://.
8. Crash reporter на v0.1 (механизм).
9. Menu Bar app — степень минимальности.
10. Локализация — объём на v0.1.
11. Хранение конфига (Keychain ↔ SwiftData разделение).
12. Onboarding на v0.1 — есть или нет.

**Окончательный отбор:** 4 темы (предъявлены через AskUserQuestion с multi-select). Остальные 7 — Claude-defaults в CONTEXT.md секция "Дефолты, принятые Claude".

---

## Обсуждённые серые зоны (по очереди)

### Серая зона 1: Идентификаторы

**Question 1:** «Какую схему Bundle ID используем для iOS и macOS таргетов?»
- Options:
  - `app.yourvpn.*` (рекомендовано) — короткое, под будущий домен yourvpn.app.
  - `com.yourvpn.*` — классика reverse-DNS, но домен не контролируется.
  - `dev.<username>.YourVPN.*` — namespace по разработчику.
  - Другое (free text).
- **User chose:** `app.yourvpn.*` (рекомендовано) ← позже изменён на `app.bbtb.*` после rebrand.

**Question 2:** «Apple Developer Team ID уже есть или предстоит настроить?»
- Options:
  - Есть — я впишу в CONTEXT.md.
  - Есть, но не пиши в репозитории — через `.xcconfig` (вне git).
  - Нет ещё — нужно зарегистрировать.
- **User chose:** Есть — я впишу в CONTEXT.md.

**Free-text follow-up:** «Введи Team ID одной строкой.»
- **User typed:** `UAN8W9Q82U`

---

### Серая зона 2: Тест-сервер VLESS+Reality

**Question:** «Ситуация с реальным VLESS+Reality сервером для смок-теста DoD #1?»
- Options:
  - Есть рабочий сервер.
  - Нет — включить в скоуп фазы (поднять testovy sing-box).
  - Нет — использовать публичный демо-сервер.
  - Обсудим варианты.
- **User chose:** Есть рабочий сервер.

**Follow-up:** server URL и `publicKey` предоставляются пользователем во время smoke-теста; конфиг с секретами не коммитится в git.

---

### Серая зона 3: Структура PacketTunnelExtension iOS↔macOS

**Question:** «Как организовать PacketTunnelProvider на iOS и macOS?»
- Options:
  - Шаренный Swift Package + два тонких target-shell (рекомендовано) — `PacketTunnelKit` в `Packages/`, два NSExtension target shells в `App/`, `#if os(iOS)/macOS)` где нужно.
  - Два независимых таргета с дублированием.
  - Multi-platform Swift Package с одним target (исторически не работает для App Extensions в Xcode).
- **User chose:** Шаренный Swift Package + два тонких target-shell.

---

### Серая зона 4: Стратегия security review (R1+R6)

**Question:** «Когда выполняем security review R1 (SOCKS5/gRPC off) и R6 (P2P=false)?»
- Options:
  - Security-first — первый wave (рекомендовано). До кода туннеля: написать sing-box JSON-шаблон без SOCKS5/mixed + standalone SocksProbe test-app.
  - Validation-gate в конце фазы.
  - Гибрид: R1 first, R6 вместе с PacketTunnelProvider.
- **User chose:** Security-first — первый wave.

---

## Закрывающий вопрос: «Обсуждаем ещё или фиксируем?»

**Options:**
- Пиши CONTEXT.md — дефолты ok.
- Обсудим ещё серые зоны.

**User typed (free-text «Other»):**
> «Давай поменяем название с yourvpn на bbtb (сокращение от bring back the bug). Название самого приложения будет "Верни жука"»

→ Workflow перешёл в режим уточнения rebrand'а.

---

## Rebrand-уточнения (free-text)

Claude задал 4 уточняющих вопроса как plain text:

1. **Английский display name?** → User: «Bring Back the Bug»
2. **Папка Xcode-проекта?** → User: «BBTB/»
3. **Universal Links домен?** → User: «import.bbtb.app»
4. **Масштаб переименования?** → User: «везде» (PROJECT.md, ROADMAP.md, REQUIREMENTS.md, config.json, CLAUDE.md, prompts/v2, wiki).

**Действия Claude после rebrand-уточнений:**
- `Claude.md`: `YourVPN/` → `BBTB/` (с пояснением display name).
- `.planning/config.json`: расширение блока `project` — `name: BBTB`, `code: BBTB`, добавлены `display_name_ru`, `display_name_en`, `bundle_prefix`, `app_group`, `universal_links_domain`, `team_id`.
- `.planning/PROJECT.md`: title `YourVPN` → `BBTB`, добавлен раздел про display name, обновлён референс deep links, добавлена строка в Key Decisions table про rebrand.
- `.planning/REQUIREMENTS.md`: title + DEEP-01..03 (yourvpn:// → bbtb://, import.yourvpn.app → import.bbtb.app).
- `.planning/ROADMAP.md`: title + Phase 9 (deep links).
- `Wiki/index.md`: строка про deep-links.
- `Wiki/deep-links.md`: все вхождения, обновлён appIDs пример с реальным Team ID.
- `Wiki/architecture.md`: package layout root.
- `Wiki/release-roadmap.md`: v0.9 секция.
- `Wiki/product-overview.md`: новый раздел «Имя и идентификаторы» с полным списком bundle IDs.
- `prompts/v2`: `<product_overview>` обновлён с финальным именем + полным списком идентификаторов; `<swift_package_layout>` root; deep links секции; DoD строки.
- `.planning/STATE.md`: обновлён project codename + active phase status.

**Сохранённые упоминания «YourVPN»** (как историческая запись):
- `.planning/PROJECT.md` строка о rebrand в Key Decisions table.
- `Wiki/deep-links.md` description-frontmatter с пометкой «rebrand 2026-05-11, ранее yourvpn://».

---

## Итог обсуждения

- **Серых зон обсудили:** 4 из 12 (с явными вопросами).
- **Claude-defaults:** 7 (документированы в CONTEXT.md секция 5).
- **Внеплановое решение:** rebrand проекта YourVPN → BBTB с каскадом обновлений в 10 файлах.
- **Deferred ideas:** 6 пунктов (в CONTEXT.md `<deferred_ideas>`).
- **Result:** `01-CONTEXT.md` готов; `gsd-plan-phase 1` может стартовать.

---
*Generated: 2026-05-11.*
