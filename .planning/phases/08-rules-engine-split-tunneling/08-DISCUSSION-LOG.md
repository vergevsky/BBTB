# Phase 8: Rules Engine + Split tunneling - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-15
**Phase:** 8-rules-engine-split-tunneling
**Areas discussed:** Area A (Routing implementation), Area B (Country / Geo-IP), Area C (Bootstrap rules), Area D (macOS AppProxyProvider scope)

**Pre-discussion user rules (re-confirmed at start of session):**
1. Прио — масштабируемость (20 протоколов, 50+ транспортов).
2. Качество > скорость.
3. Объяснять подробно и просто (пользователь не программист).
4. Обязательная Codex consultation на ключевых архитектурных решениях.

Все 4 правила применены к каждому area selection и встроены в rationale в CONTEXT.md.

---

## Area A — In-tunnel routing implementation

| Option | Description | Selected |
|--------|-------------|----------|
| A1. Sing-box rule_set + server-side SRS | VPS компилирует rules.json в 3 .srs файла, подписывает Ed25519. Клиент подменяет в App Group. Sing-box автоподхватывает без restart. Mas масштабируется на 10K+ доменов. Country resolved server-side. | ✓ |
| A2. Sing-box rule_set + client-side SRS compile | VPS хранит rules.json. Клиент сам компилирует в .srs. Больше кода на клиенте (SRS encoder), проще server-side. | |
| A3. Inline arrays в route.rules (fallback) | rules.json парсится в inline arrays прямо в sing-box config JSON. Обновление требует restart туннеля. Не масштабируется на 10K+ доменов. | |

**User's choice:** A1 (Recommended) — server-side SRS pipeline.

**Codex consultation:** thread `019e2841-e382-7cb1-98b4-793307090ae4` (architect role, read-only sandbox). Codex verified sing-box 1.13.x features (route.rule_set since 1.8.0, local auto-reload since 1.10.0, SRS v4 since 1.13.0), Apple integration constraints, и memory ceiling. Recommended primary approach соответствует A1. Также подтвердил что Apple-level routing (`excludedRoutes`) работает только для IPs (не domains), отвергает inline arrays для 10K+ доменов scale.

**Notes:** Codex flag главный risk — local rule-set auto-reload поведение **внутри iOS Network Extension sandbox** нужно verifying on-device с libbox 1.13.11. Если auto-reload failure → fallback «apply on next reconnect». Это treated как release gate в planning.

---

## Area B — Country / Geo-IP routing

| Option | Description | Selected |
|--------|-------------|----------|
| B1. Полный server-side resolve | VPS-tooling разворачивает country → CIDR при подписи. Пользуешься сразу в v0.8. Cost: server-side скрипт + MaxMind GeoLite2 download eachly. Ничего на клиенте не меняется. | ✓ |
| B2. Поле есть, client игнорирует в v0.8 | rules.json schema содержит countries, но клиент в v0.8 их не применяет. Реальная поддержка — v0.10+. Phase 8 быстрее закрывается. | |
| B3. Нет countries в v0.8 schema | В v0.8 schema имеет только domains + ip_cidrs. country добавим в v0.10+. Самый простой путь. | |

**User's choice:** B1 (Recommended) — полный server-side resolve.

**Notes:** Этот выбор был автоматически направлен Area A решением (server-side SRS pipeline сам по себе наталкивал на server-side country resolve — нет смысла половинить). Подтверждение user'а сделало это явным. MaxMind GeoLite2 — бесплатный, weekly updated, license-compliant для personal use.

---

## Area C — Bootstrap rules

| Option | Description | Selected |
|--------|-------------|----------|
| C1. Прозрачно (no bootstrap) | Никаких правил до первого скачивания. Трафик по default toggle. Просто, но без safety net на первом запуске или при offline-после-установки. | |
| C2. Embedded baseline (signed) | В .app bundle лежит baseline-rules.json (version: 0) подписанный твоим Ed25519. С минуты «0» max.ru и прочие baseline-blocks работают. Обновляется с новым релизом. Единый trust-path. +1-2 часа работы. | ✓ |
| C3. Hardcoded block-list в коде | Swift static let с max.ru и др. Два кодовых пути применения rules (hardcoded + server). Не масштабируется когда добавим always/never к baseline. | |

**User's choice:** C2 (Recommended) — embedded baseline signed.

**Notes:** Rationale привязан к user rule «качество > скорость» — single trust-path + криптографически чистый bootstrap + safety net с минуты «0». Также соответствует rule «масштабируемость» — когда расширим baseline на always/never категории, не нужно расширять hardcoded swift код, просто переподписать baseline. Не консультировались с Codex — это UX-уровневое решение, не architectural.

---

## Area D — macOS AppProxyProvider scope

| Option | Description | Selected |
|--------|-------------|----------|
| D1. Stub в v0.8, real → v0.10+ | AppProxy target остаётся stub'ом. Phase 8 SC #3 deferим к Phase 10. rules.json schema без bundle_ids. Plumbing готов. Effort: Short. Risk: zero. | |
| D2. Drop RULES-11 + SC #3 полностью | Удаляем AppProxyExtension-macOS target из Tuist + Apple Developer Portal. Чище всего. RULES-11 → Out of Scope. Cost возврата: 15мин Tuist + 30мин Portal. | ✓ |
| D3. Строим реальный data plane в v0.8 | Large effort (3-5+ дней). Риски R1-нарушения либо bypass-а Reality. Против правила «качество > скорость». Codex прямо не рекомендует. | |

**User's choice:** D2 — drop полностью.

**Codex consultation:** thread `019e284c-4bf6-7f91-ada7-7e679692b5fb` (architect role, read-only sandbox). Codex выявил два фундаментальных блокера: (1) libbox 1.13.11 не имеет verified API для injection `NEAppProxyFlow` (L4) → sing-box router (L3 TUN); все альтернативы либо ломают R1 (localhost SOCKS), либо bypass-ят Reality (теряем anti-DPI), либо требуют unverified multi-instance sing-box. (2) Apple semantic mismatch — `NETunnelProviderManager` и `NEAppProxyProviderManager` mutually exclusive; AppProxy создан для use-case «почти всё прямо, несколько apps через прокси», BBTB нужен обратный кейс. Codex recommended D1 как safest, но user предпочёл D2 для cleanest scope amendment (избегаем dead code maintenance).

**Notes:** Это **scope amendment to ROADMAP.md Phase 8 SC #3** + **REQUIREMENTS.md RULES-11 → Out of Scope**. Planner должен выполнить эти amendments в Plan W0 (foundation wave). Также удалить файл `BBTB/App/AppProxyExtension-macOS/` целиком, target из `BBTB/Project.swift`, и пересмотреть Apple Developer Portal entitlements для `app.bbtb.client.macos`.

---

## Area E — Signature placement (auto-decided)

Пользователь принял default «отдельный .sig файл» (two-file Ed25519) во вступительном вопросе. Не обсуждалось интерактивно. См. D-07 в CONTEXT.md.

| Option | Description | Selected |
|--------|-------------|----------|
| E1. Two-file (.sig отдельный) | rules.json + rules.json.sig. Раздельные файлы. Проще validate. Canonical JSON не нужно. | ✓ |
| E2. Embedded `signature` field | rules.json с polem "signature": "base64..." внутри. Один файл, но canonical JSON serialization tricky. | |

**Rationale:** Two-file избегает canonical JSON serialization fragility; raw byte signature проще validate; SRS-формат и manifest также подписаны отдельно.

---

## Claude's Discretion

Следующие auxiliary defaults документированы в CONTEXT.md D-10..D-13 и могут быть revisited в planning без re-discussion:

- **D-10: Force-update button cooldown = 60s** (защита VPS от accidental DDoS).
- **D-11: `min_app_version` UX = modal sheet, dismissible** (не full-screen takeover — UX harsh).
- **D-12: rules.json fetch не блокирует cold start** (per DEC-06d-01).
- **D-13: Failover mirrors max concurrency = 1 (sequential)** при boot fetch и force-update (per DEC-06d-04).

Эти решения architectural но не «вкусовые» — выбраны на основе established patterns Phase 6d. Если planner найдёт лучший подход — может скорректировать с обоснованием.

---

## Deferred Ideas

См. CONTEXT.md `<deferred>` section. Краткий список:

- **RULES-11 + Phase 8 SC #3** → Out of Scope v0.8, v0.10+ conditional on demand. Документировать в `wiki/appproxy-deferral-2026.md`.
- **`bundle_ids` поле в rules.json** → не вводим в v0.8.
- **NET-12** active liveness probe → carry-out для Phase 9+.
- **Push «правила обновлены» уведомления** → v1.4+ (per v2 prompt).
- **`feature_flags` секция consumption** → schema допускает, client не интерпретирует в v0.8.
- **Numerical Instruments baseline / macOS UAT replay / L16/L18 cleanup / W2-05 wiki promotion** → Phase 11/12 pre-TestFlight (carry-over).
- **Per-app routing UI на macOS** → если AppProxy появится в v0.10+.
