# Phase 6d: Performance & Code Quality Audit — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-14 (discussion straddled midnight from 2026-05-13)
**Phase:** 06d-performance-audit
**Areas discussed:** Симптомы (что именно «тяжело»), Scope boundary по слоям кода, AI participants & pass design, Severity & end-condition
**Areas closed by default (Claude's discretion):** Priority по 5 dimensions, Instruments / measurement setup

---

## Pre-discussion gray-area selection

| Option | Description | Selected |
|--------|-------------|----------|
| Симптомы: что именно «тяжело» | Конкретный observable симптом — cold start? переходы? import? connect? backgrounded resume? без этого аудит будет искать вслепую (Recommended — критично) | ✓ |
| AI participants & pass design | Кто участвует, как организованы passes — общий findings файл или три независимых, как синтезируем | ✓ |
| Scope boundary по слоям кода | Все Swift packages или только AppFeatures? libbox.xcframework? sing-box templates? ConfigParser? SwiftData layer? | ✓ |
| Severity & end-condition | Что значит «Phase 6d closed» — все HIGH? HIGH+MEDIUM? Какой бюджет фиксов разумный? | ✓ |

**User's choice:** Все 4 серых зоны для обсуждения. Priority dimensions + Instruments setup → закрыть defaults.
**Notes:** Maximum user engagement — пользователь wanted explicit alignment по каждой из 4 ключевых осей перед началом аудита.

---

## Симптомы: что именно «тяжело»

| Option | Description | Selected |
|--------|-------------|----------|
| Cold start — первый запуск приложения | От тапа по иконке до появления рабочего MainScreen с пропрорисованными кнопками. Измеряется через Time Profiler trace launch. | ✓ |
| Переходы между экранами | MainScreen → Settings, Settings → Advanced DNS, лист серверов sheet, ServerDetailView push. Лаг от тапа до появления экрана. | |
| Импорт конфига | От тапа «Import from clipboard» / QR до появления листа серверов с распарсенными конфигами. Subscription URL / Outline / Clash YAML / multi-line URI block. | |
| Connect tap → «Подключено» | От тапа power-кнопки до финального статуса «Подключено» + тикающий таймер. Включает pre-connect probe + provision profile + tunnel handshake. | ✓ |

**User's choice:** Cold start + Connect tap (multi-select, оба).
**Notes:** Это два конкретных observable моментa с измеримыми timings. Не abstract «всё медленно» — specific pain points. Фокусирует audit на двух понятных путях.

---

## Scope boundary по слоям кода

| Option | Description | Selected |
|--------|-------------|----------|
| Все Swift packages | AppFeatures + VPNCore + ProtocolRegistry + TransportRegistry + ConfigParser + KillSwitch + PacketTunnelKit + 5 протокольных + 5 транспортных + Localization + CrashReporter + DesignSystem + ServerListFeature + SettingsFeature — вся наша Swift поверхность (Recommended — cold start и connect tap трогают много из них) | ✓ |
| Только AppFeatures | MainScreen + Settings + ServerList + ImportFlow + TunnelController — то, где находятся UI/orchestration. Быстрее поверхность, но может пропустить bottlenecks в ConfigParser / PoolBuilder на connect. | |
| Swift packages + sing-box JSON templates | Все Swift packages ПЛЮС 6 sing-box JSON config templates (они влияют на libbox startup time). NOT включает перeписывание libbox.xcframework или gomobile биндингов. | ✓ |
| Всё + libbox.xcframework startup | Добавляем profiling libbox.xcframework launch (через Instruments на PacketTunnelExtension process). Переписывать gomobile binding не будем, но хотим знать где libbox тратит время. | ✓ |

**User's choice:** Опции 1 + 3 + 4 (multi-select). Это эффективно максимальный scope — option 4 subsumes option 1 and option 3 (включает все).
**Notes:** Full-scope audit. libbox internals не переписываем (gomobile binding выходит за scope Phase 6d), но Instruments profiling libbox через trace на Packet Tunnel extension process — да.

---

## AI participants & pass design

| Option | Description | Selected |
|--------|-------------|----------|
| 3 независимых passes с одинаковым промптом → я синтезирую | Каждый AI (Opus 4.7 изнутри, Codex GPT-5.2 через mcp__codex, Gemini 3.1 Pro через mcp__gemini) ревьюит один и тот же scope с идентичным брифом — ищем overlap (все трое указали на это → высокая confidence) + unique findings. Один файл 06D-FINDINGS.md с колонками per AI. (Recommended — классический пир-ревью с cross-validation.) | ✓ |
| 3 passes с разным focus — специализация | Например: Opus — architecture/simplicity, Codex — perf/energy, Gemini — memory/launch. Меньше overlap, больше depth по своей зоне. Риск — пропустить кросс-димензиональные вещи. | |
| 1 main pass (Opus 4.7) + 2 ревьюера (Codex + Gemini) | Я делаю первичный audit, потом делегирую Codex и Gemini каждый ревьюит мои findings (challenge + add missing). Меньше времени на параллельные passes, но bias товарищества к моим findings. | |
| Два параллельных passes — Codex + Gemini (потом я синтезирую) | Я не делаю свой audit pass (слишком близок к коду — могу не видеть свои слепые пятна). Делегирую Codex и Gemini каждому fresh review, потом синтезирую overlap + unique. | |

**User's choice:** 3 независимых passes с одинаковым промптом → синтез.
**Notes:** Classic peer-review с cross-validation. Все три AIs получают identical 7-section delegation brief (per `~/.claude/rules/delegator.md`). Synthesis в одном `06D-FINDINGS.md` с per-AI колонками + consensus markers (3/3 strong, 2/3 moderate, 1/3 unique-but-valuable).

---

## Severity & end-condition

| Option | Description | Selected |
|--------|-------------|----------|
| Все HIGH закрыты; MEDIUM и LOW — в backlog | Быстро и минимальный риск. HIGH = явные perf regressions или блокирующие wins. MEDIUM/LOW выносим в wiki/performance-backlog или REQUIREMENTS новый PERF-XX block. | |
| Все HIGH + все MEDIUM закрыты; LOW в backlog | Качество > скорость. Средний тяжести fix'ы тоже закрывают в рамках фазы; LOW (cosmetic refactors, dead-code) в backlog. Бюджет 2-3 дня. (Recommended — user said "качество > скорость".) | |
| Всё closed — HIGH + MEDIUM + LOW | Максимально чистый codebase. Неделя+ времени; риск perfectionism — можно погрязнуть в LOW-priority cosmetics. | |
| Определим после findings | Сначала собираем findings без fix'ов → видим масштаб (сколько HIGH/MEDIUM/LOW) → принимаем решение о бюджете. Между сбором findings и fix-cycle — чекпоинт с пользователем. | ✓ |

**User's choice:** Определим после findings.
**Notes:** Прагматичное решение — масштаб неизвестен. Phase 6d структура становится: Wave 1-2 (audit + synthesis + Instruments baseline) → **CHECKPOINT** (user reviews + decides budget) → Wave 3..N (fix-cycle) → Final (post-fix Instruments + closure). Это самый гибкий вариант — не зашиваем бюджет до того, как знаем реальный объём работы.

---

## Claude's Discretion

### Priority по 5 dimensions

**Default:** Все 5 dimensions (perf / energy / simplicity / memory / launch) равновесомые a priori. Severity рубрика (HIGH/MEDIUM/LOW) учитывает actual user impact, не a priori weight.

**Rationale:** User explicitly selected cold start + connect tap как primary pain points — это перевешивает abstract «один из 5 dimensions важнее». Findings, которые улучшают эти два path'а, автоматически получают более высокий severity. Все остальные dimensions remain equally weighted to не пропустить orthogonal wins.

### Instruments / measurement setup

**Defaults в CONTEXT.md D-07:**
- **Device:** iPhone iOS 26.5 (тот же device что прошёл re-UAT Phase 6c). Energy Log требует real device.
- **Traces:** Time Profiler (cold launch на iPhone + MacBook), Time Profiler (connect tap на iPhone), Energy Log (idle + connect window + 5min active), Allocations (cold + import + connect).
- **Baseline:** pre-fix snapshot на main `c51b2ce` (post-Phase-6c-closure). Сравнение pre-fix vs post-fix внутри Phase 6d. Phase 1 baseline недоступен.
- **Storage:** Instruments `.trace` файлы — большие, НЕ в git. Screenshots key spans + текстовые exports → `wiki/performance-baseline.md` + `.planning/phases/06d-performance-audit/baselines/` (markdown only).

---

## Deferred Ideas

### Не Phase 6d (carry-over из STATE.md / прежние phases)

- **Phase 11 follow-up** — empty-state UX issue после удаления VPN profile из iOS Settings.
- **Phase 11 follow-up** — SocksProbe PID attribution UI.
- **Phase 12 prerequisite** — Apple Distribution credentials.
- **W2-05 iOS 16.1+ Apple-leak документация** — promote из 01-RESEARCH в FAQ.

### Phase 7-8 backlog

- **NET-12: active liveness probe** — sing-box `Cmd_LogClient` polling или app-side HTTP ping.
- **macOS-specific UAT replay** Phase 6c сценариев на macOS отдельно.

### Out of scope для Phase 6d (могут стать своими phases в будущем)

- Замена `libbox.xcframework` на Rust sing-box или другой backend.
- Миграция с SwiftPM на другую build system.
- UI redesign — Phase 11 territory.
- Adding new dependencies для perf wins (допустимо только как часть конкретного fix'а с user-impact justification).
