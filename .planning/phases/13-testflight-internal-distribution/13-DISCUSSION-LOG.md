# Phase 13: TestFlight Internal Distribution — Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-16
**Phase:** 13-testflight-internal-distribution
**Areas discussed:** App fixes scope, Version & Build numbering, Internal testers list, TestFlight build description & test plan

---

## Initial gray-areas selection

| Option | Description | Selected |
|--------|-------------|----------|
| App fixes scope до первого build | Что включаем в v1.0 до TestFlight upload? | ✓ |
| Version & Build numbering | С какого CFBundleShortVersionString стартовать? | ✓ |
| Internal testers list | Кто включён в Internal Testing group? | ✓ |
| TestFlight build description & test plan | Что пишем в «What to Test» для testers? | ✓ |

**User's choice:** All 4 areas selected (multiselect).

---

## App fixes scope

### Question 1: Какие дополнительные app fixes/features включить в первый TestFlight build?

| Option | Description | Selected |
|--------|-------------|----------|
| Subscription quota progress bar | Расширить Subscription model + Figma 3064:1154 progress bar; требует backend support | |
| macOS Figma rebuild | macOS app в v1.0 (BBTB-macOS scheme) или отложить на v1.1+? | |
| DETECT-03 admin handoff | Sign rules.json + MAX-domains для anti-detection | |
| Nothing extra — current state ready | Текущий state (Phase 12 closed) готов к Archive; iterative fixes в subsequent builds | |
| **Other (custom):** Toggle отключающий routing rules | (user-supplied via "Other") | ✓ |

**User's choice:** Custom — добавить toggle отключающий routing rules.

### Question 2: Toggle «Routing rules» — default state и behavior?

| Option | Description | Selected |
|--------|-------------|----------|
| Default ON, off = full tunnel | Routing rules применяются по умолчанию (split tunnel). При выключении — full tunnel. (Recommended) | ✓ |
| Default OFF, on = apply rules | UX: user opt-in в split tunnel. | |
| Smart default — ON + force-route critical | Critical rules (local network, Apple Push) always direct; user toggle влияет только на user/server rules. | |

**User's choice:** Default ON, off = full tunnel.

### Question 3: Где в Settings toggle живёт + label?

| Option | Description | Selected |
|--------|-------------|----------|
| Settings root — «Правила маршрутизации» | В основном Settings screen (видимо сразу) | |
| Advanced Settings — «Правила маршрутизации» | В Advanced с Anti-DPI / DNS / Rules Viewer (power-user) | |
| Advanced — «Full tunnel mode» (inverse semantics) | Label инвертирован к «Полный туннель» | |
| **Other (custom):** Живёт в расширенных, там же, где описаны правила маршрутизации | (user-supplied) | ✓ |

**User's choice:** Advanced Settings, рядом с уже существующим RulesViewerSection (где «описаны правила маршрутизации»). Используется существующий label «Правила маршрутизации» / «Routing rules».

**Notes:** D-04 — placement near RulesViewerSection. Affects ConfigImporter.provisionTunnelProfile (skip RulesEngine rules at toggle off → full-tunnel sing-box config).

---

## Version & Build numbering

### Question 1: С какого Version + Build стартуем первый TestFlight upload?

| Option | Description | Selected |
|--------|-------------|----------|
| Version 1.0.0, Build 1 | Standard production-ready numbering | |
| Version 0.1.0, Build 1 | Beta-style — communicates «early access»; bump к 1.0.0 при App Store launch | ✓ |
| Version 0.12.0, Build 1 | Continue ROADMAP milestone numbering (Phase 12 = v0.12 closed) | |

**User's choice:** Version 0.1.0, Build 1.

### Question 2: Build number strategy?

| Option | Description | Selected |
|--------|-------------|----------|
| Manual — 1, 2, 3, ... | Bump CFBundleVersion manually before each Archive (Recommended) | ✓ |
| Auto via Xcode Distribution wizard | Xcode «Manage Version and Build Number» toggle | |
| Auto via Tuist + git commit count | build = git commits count via tuist script | |

**User's choice:** Manual — 1, 2, 3, ...

---

## Internal testers list

### Question 1 (initial): Кто включён в Internal Testing group для первого build?

| Option | Description | Selected |
|--------|-------------|----------|
| Только я (owner) | Internal Testing только owner; expanding later | |
| + developer friends (1-5) | Apple Developer team роли | |
| **+ close family/friends без dev account** | (user picked, но needed clarification — Individual account capability) | ✓ (initial) |

**User raised concern:** «Я точно могу инвайтить людей? У меня индивидуальный аккаунт, не аккаунт компании».

**Clarification provided:** Yes — Individual Apple Developer Program ($99/y) allows inviting Apple ID users to App Store Connect team. Invited users НЕ нуждаются в своём paid Apple Developer Program; получают free доступ. Roles available: Admin / App Manager / Developer / Marketing / Customer Support / Sales. Limit: до 100 internal testers per group.

### Question 2 (re-asked after clarification): Кто в Internal Testing group для первого build (Individual account, invite через Users and Access)?

| Option | Description | Selected |
|--------|-------------|----------|
| Только я — first build solo | Только owner; expand later | |
| + 2-5 family/friends | Smaller group, easy support | |
| + 5-20 friends-and-family | More feedback diversity, больше overhead | ✓ |
| Open up External Testing (revise D-01) | Revise D-01 → External + Beta Review + Privacy Policy | |

**User's choice:** + 5-20 friends-and-family.

**Notes:** Invite через App Store Connect → Users and Access → ➕ Add Users → Apple ID email + role «Developer» или «App Manager». Plan task: prepare invite list before Step 4 (Archive+Upload).

---

## TestFlight build description & test plan

### Question 1: «What to Test» текст в TestFlight для testers?

| Option | Description | Selected |
|--------|-------------|----------|
| Brief generic invite | 1-3 строки; коротко и просто | ✓ |
| Structured test plan | 5-7 конкретных user flows (Phase 12 UAT items style) | |
| Mixed — short intro + 3 priority flows (Recommended) | Brief intro + 3 important flows: Import / Connect & verify / Settings tour | |

**User's choice:** Brief generic invite.

### Question 2: Где testers отправляют feedback / bug reports?

| Option | Description | Selected |
|--------|-------------|----------|
| TestFlight built-in feedback | «Send Beta Feedback» в TestFlight iOS app → Apple email + App Store Connect inbox (Recommended) | ✓ |
| Email напрямую | Указать email в «What to Test» | |
| Telegram group / chat | Private TG group для testers | |

**User's choice:** TestFlight built-in feedback.

---

## Claude's Discretion

- **D-04 implementation hook detail:** Точное место в `ConfigImporter.provisionTunnelProfile` где skip RulesEngine rules при `routingRulesEnabled == false` — planner/researcher решит после code review в Phase 13-01 PLAN.
- **L10n keys:** Точные ключи для toggle label / footer (`settings.advanced.routing_rules_label`, `settings.advanced.routing_rules_footer`) — naming convention следует established patterns.
- **App Store Connect record fields beyond minimum:** SKU format, secondary categories, default age rating — planner может suggest defaults; не критично для Internal-only.
- **Refinement «What to Test» text:** Подкорректирую перед Archive based on what specific bugs/flows user захочет surfacing.

---

## Deferred Ideas

### Carry-forward to v1.1+ (preserved in CONTEXT.md `<deferred>` section)
- Subscription quota fields + conditional progress bar (Figma 3064:1154)
- macOS Figma pixel-perfect rebuild + macOS TestFlight track
- DETECT-03 admin handoff (rules.json sign + MAX-domains)
- External Testing + public invite link + Privacy Policy URL + Beta App Review
- SPKI subscription pin replacement + wire PinnedSubscriptionURLFetcher in production
- App Store submission (full App Store Review)
- Full Light mode (designer должен дорисовать Light versions всех экранов)
- Power-Glow effect восстановление

### Reviewed and stayed in scope
- None — discussion stayed within Phase 13 boundary (1 new feature + distribution setup).
