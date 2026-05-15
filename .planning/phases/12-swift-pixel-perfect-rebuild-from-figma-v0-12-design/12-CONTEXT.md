# Phase 12: Swift pixel-perfect rebuild from Figma (v0.12-design) - Context

**Gathered:** 2026-05-16
**Status:** Ready for planning

<domain>
## Phase Boundary

Привести Swift код в pixel-perfect соответствие с **BBTB v3 Figma** (cleaned + tokenized в Phase 11 closure 2026-05-16). Phase 12 — это **design milestone v0.12** — никаких новых фич, протоколов, безопасности. Только визуальная парность с дизайном.

**Источник истины:** `BBTB/Packages/DesignSystem/Tokens/figma-tokens.json` (51 токен) + `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` (10 mismatches M1-M10).

**В скоупе:** iPhone-экраны (Onboarding, Home Disconnected/Connecting/Error/Connected, Servers Selected/Auto). DS extension (Color, Typography.Size, Radius, Blur, ConnectionButtonSize). SF Pro Expanded font подключение. Custom Spinner. Snapshot test infrastructure для ключевых компонентов.

**ВНЕ скоупа:** macOS pixel-perfect (включая cleanup MacOS + MacOS popover Figma страниц) → backlog после v1.0. Code Connect SDK publish — Education plan не поддерживает `code_connect:write` scope → blocker carry-forward. Telemetry / Beta App Review / TestFlight → Phase 13.

</domain>

<decisions>
## Implementation Decisions

### Scope phasing (strategy)
- **D-01:** Phase 12 = **2 plans**: Plan 12-01 Foundation + Plan 12-02 Application.
- **D-02:** Plan 12-01 (Foundation) идёт первым — расширение `DS` enum (15 DS.Color семантических токенов, 7 Typography.Size, новые `Radius.section/sheet`, `Blur.pill`, обновлённые `ConnectionButtonSize` под Figma 280/320pt) + SF Pro Expanded font setup. Никаких UI изменений в этом plan — только токены.
- **D-03:** Plan 12-02 (Application) применяет foundation ко всем экранам: ConnectionButton, OnboardingView, ServerRow, AutoCell, ServerListSheet. Внутри 12-02 — **quick wins (M1-M5: размеры, цвета, font family) перед heavy lifts (M6 custom Spinner, M7 OnboardingView rebuild, M8-M10 row/sheet tuning).**
- **D-04:** **Tight scope** — только M1-M10. Никаких drive-by cleanups в соседнем коде. Adjacent issues → backlog (через `gsd-capture` если найдутся).

### Light mode inclusion
- **D-05:** **Wire-only Light mode** — все 15 DS.Color семантических токенов получают Light value, но визуал остаётся dark-визуалом. Когда дизайнер дорисует настоящий Light в Figma, нужно будет только обновить hex'ы в Swift.
- **D-06:** Light placeholder значения брать **из `figma-tokens.json`** (напр. `canvas` Light=`#FFFFFF`, `surface` Light=`#F4F4F6`, `textPrimary` Light=`#111113`). Эти значения уже заведены как разумные дефолты в Figma DS collection.
- **D-07:** **System auto-switch** — без отдельного in-app toggle. App следует iOS Dark/Light setting. Никаких изменений в Settings UI.

### Pixel-diff verification
- **D-08:** **Hybrid approach** — automated snapshot tests для **компонентов** (ConnectionButton, ServerRow, AutoCell, custom Spinner), **manual UAT** для full screens (User кликает по 7 ключевым экранам в симуляторе vs Figma скрины).
- **D-09:** Snapshot library — **decision deferred to researcher**. Кандидаты: `pointfreeco/swift-snapshot-testing` (most popular) vs Apple XCTest XCTAttachment (no external deps). Researcher проверит actual 2026 best practices.
- **D-10:** Acceptance threshold — **≤2px diff** на ключевых элементах (button diameter, padding, corner radii, font sizes). Anti-aliasing рендера на тексте и gradient — игнорируем как known platform difference.

### macOS scope
- **D-11:** **iOS-only Phase 12**. macOS pixel-perfect — backlog после v1.0.
- **D-12:** macOS Figma cleanup (MacOS + MacOS popover страницы — generic frame names + нет token bindings) **deferred** — будет сделан вместе с macOS pixel-perfect фазой когда подойдёт очередь.

### Claude's Discretion (карвед на researcher/planner)

- **Custom Spinner implementation** — Canvas+TimelineView vs ZStack+rotationEffect vs iOS 18+ symbolEffect rotate. Researcher проверит производительность каждого и Figma визуал точность.
- **SF Pro Expanded font integration** — system `.fontWidth(.expanded)` API (iOS 16+) vs custom .otf в bundle. Researcher оценит licensing/maintenance.
- **DS.Color storage** — Asset Catalog `.colorset` с Any/Dark appearances vs Swift enum literals vs hybrid. Researcher выберет per Apple/SwiftUI best practice 2026.
- **Spinner для ConnectionButton .connecting** — поверх power-icon или ring вокруг кнопки (Figma неоднозначна). Planner определит из Figma визуального анализа.

### Folded Todos
None — `cross_reference_todos` нашёл 0 совпадений с Phase 12 scope.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Source of truth (Figma)
- `BBTB/Packages/DesignSystem/Tokens/figma-tokens.json` — **machine-readable token export** из Figma BBTB v3 после Phase 11 cleanup. 51 переменная (11 Primitives + 40 DS), оба mode Dark+Light. **Researcher должен читать в первую очередь** — это полное состояние токенов.
- `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` — **полный Figma↔Swift mapping contract**. §1 — компонент-маппинги (Button/ServerRow/AutoCell/OnboardingView с node-ID и Swift target). §2 — token mappings (Figma path → Swift target). §3 — Typography text styles + font family. **§4 — 10 mismatches M1-M10** — это и есть Phase 12 work list. §5-§6 — preview .figma.swift skeletons.
- `.planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md` — Figma node ID карта для 51 переменной (полезно если нужны IDs при variable binding в самой Figma).
- `.planning/phases/11-onboarding-ux-polish/figma-inspect/final-*.png` — 7 финальных скриншотов экранов iPhone после Phase 11 cleanup (manual UAT reference).

### Code Connect mapping files (preview snippets для будущей публикации)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.figma.swift` — Button → ConnectionButton с @FigmaEnum variant mapping.
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.figma.swift` — ServerRow + ServerRowSelected.
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.figma.swift` — AutoCell selected pill.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.figma.swift` — Onboarding screen.

### Существующий Swift design system
- `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` — текущий `DS` enum. Phase 12 **расширяет** (additions only), существующие public symbols (`DS.Spacing.*`, `DS.Radius.small/card/cardLarge/button`, `DS.accent`) сохраняются. `DS.accent` останется как Color но redefined как `Color("DS/accent")` (M5).

### Target Swift views (rebuild candidates)
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` — main power button (M1-M3, M6).
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionState.swift` — 5-case enum (.empty/.idle/.connecting/.connected/.error). Figma `disconnected` variant покрывает .empty + .idle.
- `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift` — onboarding (M7).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift` — row component (M8).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift` — auto pill (M8).
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` — sheet container (M9, M10).

### Project context
- `.planning/PROJECT.md` — project metadata, Constraints (Swift 5.10+/6, SwiftUI, iOS 18, macOS 15), Key Decisions (R1..R21).
- `.planning/REQUIREMENTS.md` — Phase 11 UX-09 marked `figma-pending`; Phase 12 re-validates.
- `.planning/ROADMAP.md` §«Phase 12» — Goal, Success Criteria (8 items including ≤2px diff, SF Pro Expanded, custom Spinner).
- `wiki/onboarding-ux-polish-2026.md` — Phase 11 long-term memory: design tokens decisions, two-tier model, Code Connect Education-plan blocker.

### Architectural patterns to honor
- Phase 6d DEC-06d-01 — cold-start init defer pattern (applies to new font registration if .ttf approach taken).
- Phase 6d DEC-06d-02..06 — XPC consolidation, AsyncStream polling, bounded concurrency. (Probably not directly relevant to pure visual work, но planner check'нет.)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`DS.Spacing.*` (4/8/12/16/24/32/48)** — уже соответствует Figma; reuse 1:1.
- **`DS.Radius.small/card/cardLarge/button`** — уже соответствует Figma (8/12/16/12); reuse, добавить новые `section` (24pt) и `sheet` (32pt).
- **`ConnectionButton` SwiftUI view** — структура корректна (ZStack с Circle + Image + ProgressView overlay); меняем только diameter/iconSize/fill colors/spinner internals.
- **`ServerRow` HStack layout** — структура корректна (globe + VStack + Spacer + LatencyBadge + caret); меняем padding/spacing/font/colors.

### Established Patterns
- **`#if os(iOS)` / `#if os(macOS)` conditional compile** — используется для diameter selection (compactDiameter vs regularDiameter). Phase 12 iOS-only — не трогаем macOS branch.
- **`@Environment(\.horizontalSizeClass)` for iPhone compact/regular** — `ConnectionButtonSize.compactDiameter` для compact (большинство iPhone), `regularDiameter` для iPad/large. Figma 402-pt iPhone = compact.
- **`buttonStyle(.plain)` + `accessibilityIdentifier`** — для всех custom buttons. Сохраняется в Phase 12.
- **SwiftPM монорепо modules** — DesignSystem package как dependency для AppFeatures. Phase 12 правит только DesignSystem (новые tokens) + AppFeatures views (применяет токены).

### Integration Points
- **DesignSystem.swift** — extends with `DS.Color`, `DS.Typography.Size`, `DS.Radius.section/sheet`, `DS.Blur.pill`, updated `DS.ConnectionButtonSize.*`. Public additions; existing API preserved.
- **AppFeatures views** — Read DS tokens directly. Тесты ConnectionButtonTests/ServerListSheetHeightTests — могут нуждаться в update для новых diameter/height values.
- **Assets.xcassets** (если выбран Asset Catalog для DS.Color) — `BBTB/Packages/DesignSystem/Sources/DesignSystem/Resources/Assets.xcassets` (создать если нет) с DS/canvas.colorset, DS/surface.colorset, и т.д. Bundle access через `.module`.

</code_context>

<specifics>
## Specific Ideas

- **Figma — источник истины**: при любом конфликте между Figma и существующим Swift, побеждает Figma. Подтверждено user'ом в session 2026-05-15 ("приоритет: pixel-perfect дизайн в Фигме → код").
- **«Должен быть» Onboarding tagline**: hero text в Onboarding должен быть split — «Интернет, каким он» (white) + «должен быть» (accent green `#14664B`). Это уже видно в Figma скрине `01-onboarding.png`.
- **Power-Glow эффект — НЕ восстанавливать**: Effect/Power-Glow и Fill/PowerButton-Glow стили удалены в Phase 11 (orphan tokens после glow palette removal). Phase 12 НЕ добавляет glow обратно — если user захочет — отдельная фича в backlog.
- **Custom Spinner = Figma 4-frame rotating ring**: в Figma component `Spinner` (3057:167) с 4 кадрами (frame1/2/3/4 поворота). Swift не обязан буквально 4 кадра — может плавная анимация — но визуал должен совпадать.

</specifics>

<deferred>
## Deferred Ideas

- **macOS pixel-perfect rebuild** (включая cleanup macOS + macOS popover Figma страниц) — Beyond v1.0 backlog. Не блокирует Phase 13 TestFlight.
- **Light mode полная реализация** (variable binding на nodes в Figma + designer pass через все экраны) — отдельная фаза когда дизайнер дорисует Light версии экранов.
- **In-app Theme toggle в Settings** (System/Light/Dark) — feature request, не входит в visual rebuild. Backlog v1.1+.
- **Power-Glow gradient/shadow effect** — был удалён в Phase 11. Если решим вернуть — отдельный design pass.
- **Code Connect SDK publish** — заблокировано Education plan. Когда upgrade на Organization tier — один `figma connect publish` опубликует уже готовые `.figma.swift` файлы.
- **Сustom font in bundle** (если researcher выберет .ttf вместо system .fontWidth(.expanded)) — потребует Info.plist UIAppFonts + .otf файла + license check.

### Reviewed Todos (not folded)
None — `cross_reference_todos` нашёл 0 совпадений с Phase 12.

</deferred>

---

*Phase: 12-swift-pixel-perfect-rebuild-from-figma-v0-12-design*
*Context gathered: 2026-05-16*
