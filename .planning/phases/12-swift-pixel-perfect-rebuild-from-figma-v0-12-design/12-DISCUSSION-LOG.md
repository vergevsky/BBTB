# Phase 12: Swift pixel-perfect rebuild from Figma (v0.12-design) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-16
**Phase:** 12-swift-pixel-perfect-rebuild-from-figma-v0-12-design
**Areas discussed:** Scope phasing, Light mode inclusion, Pixel-diff verification, macOS scope

---

## Scope phasing

### Q1: Сколько плановых слайсов в Phase 12?

| Option | Description | Selected |
|--------|-------------|----------|
| 2 plans: Foundation + Application (Recommended) | Plan 12-01 — DS экстеншен (15 DS.Color, 7 Typography.Size, Radius.section/sheet, Blur.pill, ConnectionButtonSize 280/320), SF Pro Expanded font setup. Plan 12-02 — применить ко всем экранам. Преимущество: инфраструктурные изменения изолированы от визуальных. | ✓ |
| 1 plan, всё вместе | Все 10 mismatches в одном большом PLAN.md. Простота PR review, но большой diff. | |
| 3-4 plans по экранам | Plan 12-01 Foundation, 12-02 Onboarding, 12-03 Home, 12-04 Servers. Мелкие plans, больше SUMMARY overhead. | |

**User's choice:** 2 plans: Foundation + Application

### Q2: Если будет несколько слайсов — что идёт первым?

| Option | Description | Selected |
|--------|-------------|----------|
| Foundation first (Recommended) | DS extension + SF Pro Expanded font setup. После — application slices становятся тривиальными. | ✓ |
| ConnectionButton first (pilot) | Маин-экран, самый видимый элемент. Pilot методологии. | |
| Onboarding first (изолирован) | Малый объём, низкий риск регрессии. | |

**User's choice:** Foundation first

### Q3: Что front-load — quick wins или heavy lifts?

| Option | Description | Selected |
|--------|-------------|----------|
| Quick wins вперёд (Recommended) | M1-M5 (button sizes, fill colors, font family) — механические подмены, низкий риск. M6-M10 (Spinner, OnboardingView rebuild) — heavy. | ✓ |
| Heavy lifts вперёд | M6+M7 сначала — самые сложные, лучше разобраться рано. Риск залипнуть. | |
| Чередуя для импульса | Quick win → heavy lift → quick win. Сохраняет мотивацию. | |

**User's choice:** Quick wins вперёд

### Q4: Насколько жесткий скоуп хотите?

| Option | Description | Selected |
|--------|-------------|----------|
| Tight — только 10 mismatches (Recommended) | M1-M10 и ровно то — без drive-by cleanups. | ✓ |
| Loose — по ходу фиксируем соседнее | Adjacent bugs внутри того же plan'а. Плюс: темп. Минус: scope creep. | |

**User's choice:** Tight scope

---

## Light mode inclusion

### Q1: Делаем ли Light mode в Phase 12?

| Option | Description | Selected |
|--------|-------------|----------|
| Только wire DS-токены, Light placeholder (Recommended) | Все 15 DS.Color семантических токенов в Swift. Dark hex'ы из Figma, Light — placeholder из figma-tokens.json. UI остаётся dark-only (preferredColorScheme или система follows iOS). | ✓ |
| Полная Light mode | Asset Catalog Any/Dark appearance, auto-switch. Риск: Light placeholder не дизайнер-выверены. | |
| Skip Light целиком | DS.Color.* хранят только dark hex'ы. Минус: потом refactor на Any/Dark. | |

**User's choice:** Только wire DS-токены, Light placeholder

### Q2: Если Light placeholder — какие значения брать?

| Option | Description | Selected |
|--------|-------------|----------|
| Из figma-tokens.json (Recommended) | canvas=#FFFFFF, surface=#F4F4F6, textPrimary=#111113 etc. Уже заведены как placeholder в Figma Light mode. | ✓ |
| Apple системные (.systemBackground etc.) | Apple авто-адаптивные. Минус: НЕ pixel-perfect с Figma Dark тоже. | |
| Инверсия Dark hex (механически) | Не рекомендую — эстетически плохо. | |

**User's choice:** Из figma-tokens.json

### Q3: Как Light/Dark переключается в приложении?

| Option | Description | Selected |
|--------|-------------|----------|
| Следует системе iOS автоматически (Recommended) | Нет отдельного toggle. iOS dark → app dark, и наоборот. | ✓ |
| Форсирован в dark (как сейчас) | .preferredColorScheme(.dark). Light placeholder в коде никогда не виден в реале. | |
| Toggle в Settings | Новый Settings option «Тема» (System/Light/Dark). Scope creep. | |

**User's choice:** Следует системе iOS автоматически

---

## Pixel-diff verification

### Q1: Как верифицировать, что Swift результат совпадает с Figma?

| Option | Description | Selected |
|--------|-------------|----------|
| Hybrid — snapshots для компонентов + manual UAT для экранов (Recommended) | Automated snapshot tests для ConnectionButton/ServerRow/AutoCell — explicit baseline PNG, CI gate. Full screens — manual side-by-side. | ✓ |
| Manual only | Эyeballing в симуляторе vs Figma. Плюс: быстро. Минус: future regressions никто не поймает. | |
| Strict automated для всего | Snapshot для каждого view и full-screen. CI gate ≤2px diff. Долго настраивать. | |

**User's choice:** Hybrid

### Q2: Если snapshots — какая библиотека?

| Option | Description | Selected |
|--------|-------------|----------|
| pointfreeco/swift-snapshot-testing (Recommended) | Самая популярная Swift snapshot библиотека. Mature, MIT, активный maintenance. | |
| Apple XCTest + XCTAttachment | Без внешних deps. Минус: нет auto diff'а, ручное сравнение PNG. | |
| Решим в plan-phase | Researcher проверит actual 2026 best practices. | ✓ |

**User's choice:** Решим в plan-phase

### Q3: Насколько строго принимать «pixel-perfect»?

| Option | Description | Selected |
|--------|-------------|----------|
| ≤2px diff на ключевых элементах (Recommended) | ROADMAP success criteria. Anti-alias на тексте/градиентах — игнорируем как known platform difference. | ✓ |
| ≤5px (мягче) | Принимаем небольшие sub-pixel aligning. Минус: может пропустить настоящие mismatches. | |
| Пиксель-в-пиксель (0px) | Крайне сложно из-за anti-aliasing различий SVG (Figma) vs Core Graphics (SwiftUI). Не рекомендую. | |

**User's choice:** ≤2px diff на ключевых элементах

---

## macOS scope

### Q1: Phase 12 — только iOS или включаем macOS?

| Option | Description | Selected |
|--------|-------------|----------|
| iOS-only Phase 12 (Recommended) | v0.12-design = только iPhone экраны. macOS Figma cleanup НЕ был в Phase 11 — отдельная под-фаза позже. | ✓ |
| iOS + macOS вместе | Сначала нужен Phase 11.5-аналог — cleanup macOS Figma. Потом rebuild для обеих платформ. Риск: время фазы ×2 минимум. | |
| iOS + macOS popover | Если macOS popover Figma близок к iPhone (re-use views) — можно поверх iOS. Решить после inspect. | |

**User's choice:** iOS-only Phase 12

### Q2: Как отметить macOS-работу в ROADMAP?

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 12b после 12 (Recommended) | iOS Phase 12 → macOS Phase 12b sub-phase. До ROADMAP-финализации Phase 13 добавить. | |
| В бэклог после v1.0 | macOS pixel-perfect в Beyond v1.0 backlog. v0.12 и v0.13 выходят с macOS в текущем визуале. | ✓ |
| Совместить с TestFlight Phase 13 | macOS rebuild в Phase 13 параллельно с TestFlight prep. Риск: Phase 13 перегружен. | |

**User's choice:** В бэклог после v1.0

### Q3: До старта macOS pixel-perfect — что делаем с macOS Figma пагами?

| Option | Description | Selected |
|--------|-------------|----------|
| Когда подойдёт очередь, тогда и чистим (Recommended) | macOS и macOS popover остаются с generic frame names и без token bindings. Когда запустим macOS pixel-perfect — сначала inspect и cleanup (как Phase 11). | ✓ |
| Inspect macOS Figma сейчас и решить | Сделать screenshots, обсудить. Плюс: полная фото проекта. Минус: ещё время. | |

**User's choice:** Когда подойдёт очередь, тогда и чистим

---

## Claude's Discretion

User explicitly delegated the following technical decisions to researcher / planner:

1. **Custom Spinner implementation** — Canvas+TimelineView vs ZStack+rotationEffect vs iOS 18+ symbolEffect rotate. (Researcher проверит производительность и Figma визуал точность.)
2. **SF Pro Expanded font integration** — system `.fontWidth(.expanded)` (iOS 16+) vs custom .otf в bundle.
3. **DS.Color Swift storage** — Asset Catalog `.colorset` Any/Dark vs Swift enum literals vs hybrid.
4. **Snapshot library** — pointfreeco/swift-snapshot-testing vs Apple XCTest XCTAttachment.

User declined to make these decisions during discuss-phase, preferring researcher/planner to evaluate trade-offs with 2026 best-practice context.

## Deferred Ideas

- **macOS pixel-perfect rebuild** — Beyond v1.0 backlog.
- **Light mode полная реализация** — отдельная фаза когда дизайнер дорисует Light версии экранов.
- **In-app Theme toggle в Settings** — backlog v1.1+.
- **Power-Glow effect восстановление** — был удалён в Phase 11 cleanup; если решим вернуть — отдельный design pass.
- **Code Connect SDK publish** — заблокировано Education plan; ждёт upgrade на Organization tier.
- **Custom font in bundle** (если planner выберет .ttf путь) — Info.plist UIAppFonts + .otf файл + license check.
