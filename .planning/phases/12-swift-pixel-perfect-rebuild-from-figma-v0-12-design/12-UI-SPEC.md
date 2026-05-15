---
phase: 12
slug: swift-pixel-perfect-rebuild-from-figma-v0-12-design
status: draft
shadcn_initialized: false
preset: not applicable (native SwiftUI iOS app)
platform: iOS 18+ (SwiftUI 6 / Swift 6)
source_of_truth: BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md
tokens_export: BBTB/Packages/DesignSystem/Tokens/figma-tokens.json
figma_file_key: tI6DFQDU6PdOSmd19BGXqg
figma_file_name: BBTB v3
created: 2026-05-16
researcher_note: thin contract — delegates всё про tokens/components/mismatches to CODE-CONNECT.md; добавляет только interaction/motion/a11y/state-coverage поверх него
---

# Phase 12 — UI Design Contract (thin)

> **Source of truth.** Этот UI-SPEC.md является **тонким контрактом**: он НЕ перечисляет токены и НЕ описывает компоненты заново.
> Полные визуальные спеки — в `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` и `figma-tokens.json`.
> Здесь живут только сквозные требования, которые CODE-CONNECT.md не покрывает: motion, accessibility, state coverage, acceptance criteria.

---

## 1. Design Contract — Source of Truth (pointer table)

Все downstream-агенты (planner, executor, ui-checker, ui-auditor) **обязаны** читать эти артефакты как первоисточник. UI-SPEC.md ничего из них не дублирует.

| Что | Где |
|---|---|
| Визуальный дизайн (canonical) | Figma file `tI6DFQDU6PdOSmd19BGXqg` (BBTB v3) — pages `iPhone`, `Library` |
| Машиночитаемый экспорт 51 токена (Dark+Light) | `BBTB/Packages/DesignSystem/Tokens/figma-tokens.json` |
| **Полный Figma↔Swift mapping** (компоненты, варианты, props) | `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §§1–3 |
| **Phase 12 work list — 10 mismatches M1–M10** | `BBTB/Packages/DesignSystem/Tokens/CODE-CONNECT.md` §4 |
| Code Connect preview snippets (`.figma.swift`) | `CODE-CONNECT.md` §§5–6 + 4 файла в `BBTB/Packages/AppFeatures/.../*.figma.swift` |
| Figma node ID → variable map | `.planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md` |
| **Reference screenshots для manual UAT (7 экранов)** | `.planning/phases/11-onboarding-ux-polish/figma-inspect/final-*.png` |
| Текущий `DS` enum (extends, not replaces) | `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` |
| Технические решения (Spinner / Font / DS.Color storage / Snapshot lib / ButtonStyle / Sheet shape) | `12-RESEARCH.md` §2 (6 DECISIONS) |
| Carved-out DS-* requirements (DS-01..DS-15) | `12-RESEARCH.md` §3 |
| Locked decisions D-01..D-12 фазы | `12-CONTEXT.md` `<decisions>` |

**Правило непротиворечивости.** При расхождении побеждает Figma → `figma-tokens.json` → `CODE-CONNECT.md`. UI-SPEC.md ни одно из этих значений не перекрывает.

---

## 2. Interaction & Motion (NEW — отсутствует в CODE-CONNECT.md)

Ниже — поведенческий контракт, которого нет ни в Figma, ни в CODE-CONNECT.md. Это требования для planner-а / executor-а.

### 2.1 ConnectionButton — tap haptic
- На каждый user-initiated tap по кнопке вызывается **light impact** через `.sensoryFeedback(.impact(weight: .light), trigger: tapCounter)` (iOS 17+ API).
- **Pitfall 6 from RESEARCH §9:** триггер привязывается к локальному `@State private var tapCounter = 0`, который инкрементируется в action-callback. Привязывать `.sensoryFeedback` к `ConnectionState` ЗАПРЕЩЕНО — иначе haptic срабатывает на auto-reconnect (Phase 6c), когда пользователь не касался устройства.
- Legacy `UIImpactFeedbackGenerator` в `ServerRow.handleTap()` НЕ мигрировать (D-04 tight scope) — только новые точки interaction.

### 2.2 BBTBSpinner (M6) — motion contract
- Анимация: `withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false))` на `Double` angle 0→360. Один полный оборот = 1.2 секунды.
- **Reduce Motion fallback (a11y):** при `@Environment(\.accessibilityReduceMotion) == true` — заменить непрерывное вращение на дискретное (snap на 4 кадра по 90° каждые 0.4с) **или** статичный ring без вращения с pulsating opacity `0.6↔1.0` (1с цикл). Final variant подтверждает Wave 1 visual review (executor).
- **Battery guard (Pitfall 3):** Spinner монтируется условно `if isConnecting { BBTBSpinner(...) }`. При смене state на `.connected/.error/.idle` view удаляется → animation авто-останавливается.
- `BBTBSpinner.accessibilityHidden(true)` — кольцо чисто визуальное, ничего VoiceOver не озвучивает; статус о подключении доносит wrapper-кнопка (см. §3.1).

### 2.3 PrimaryButton / SecondaryButton (M7) — pressed state motion
- `configuration.isPressed` → `.scaleEffect(0.97)` + `.opacity(0.92)`.
- Transition: `.easeOut(duration: 0.12)`. Источник — `12-RESEARCH.md` §2.5.
- На каждой такой кнопке (Onboarding paste / Onboarding QR) — отдельный `tapCounter` + `.sensoryFeedback(.impact(weight: .light), trigger: tapCounter)` (см. §2.1).

### 2.4 ServerRow / AutoCell — tap animation
- Tap visual feedback — система Apple Button default (никакой кастомной shrink). `buttonStyle(.plain)` сохраняется (см. CODE-CONNECT.md §1.4 + §1.6).
- При выборе строки (state flip `isSelected false→true`) визуальный переход background fill (`controlIdle → accent`) и иконок (`iconSecondary → iconMuted`) — `.animation(.easeInOut(duration: 0.2), value: isSelected)`. Длительность подтверждается Wave 1 against Figma; при доступности «Reduce Motion» — `.animation(nil)`.

### 2.5 ServerListSheet — presentation
- Detents наследуем существующие (Phase 11 already wired) — Phase 12 их **не меняет** (D-04). Кастомное закругление 32pt верхних углов (M9) применяется через `UnevenRoundedRectangle.clipShape(...)` **внутри** NavigationStack (см. RESEARCH §2.6 + Pitfall 7).
- Drag indicator (handle) — `.presentationDragIndicator(.visible)`. Dismiss-gesture default.

### 2.6 OnboardingView — screen transitions
- Onboarding показывается `fullScreenCover` поверх `MainScreenView` (Phase 11 UX-01 wiring — не трогаем). Phase 12 только **rebuild внутренней верстки** (hero text split + 2 CTA + Figma layout).
- Никаких pages/swipe — это **один экран**, dismissed by tap на любой из 2 CTA (Phase 11 D-04 carry-forward).

### 2.7 Глобальные правила анимации
- При `accessibilityReduceMotion = true` ВСЕ декоративные motion (spinner вращение, scale-effects, animated state transitions) отключаются или заменяются дискретными snap-переходами. Это контракт уровня фазы — executor валидирует в каждом modified view.
- SF Symbol `.symbolEffect(.bounce, value: state)` на power-icon (см. RESEARCH §4.5) допустимо при ReduceMotion отключить через `.symbolEffect(...).disabled(accessibilityReduceMotion)` — окончательное решение принимает executor по Wave 1 визуальному ревью.

---

## 3. Accessibility Requirements (NEW — отсутствует в CODE-CONNECT.md)

### 3.1 VoiceOver labels — ConnectionButton states
Контракт `.accessibilityLabel(...)` для `BBTB.ConnectionButton` по состоянию `ConnectionState`:

| State | accessibilityLabel | accessibilityHint | accessibilityValue |
|---|---|---|---|
| `.empty` | "Подключение VPN" | "Сначала добавьте сервер" | — |
| `.idle` | "Подключение VPN" | "Двойное касание чтобы подключиться" | "Отключено" |
| `.connecting` | "Подключение VPN" | "Идёт подключение, пожалуйста подождите" | "Подключение" |
| `.connected(since:)` | "Подключение VPN" | "Двойное касание чтобы отключиться" | "Подключено, %lld мин %lld сек" (computed from `since`) |
| `.error(message:)` | "Подключение VPN" | "Ошибка: %@. Двойное касание для повтора" | "Ошибка" |

`accessibilityIdentifier("BBTB.ConnectionButton")` — **обязательно сохраняется** (~207 существующих тестов референсят этот identifier).

### 3.2 VoiceOver — Spinner / power-icon
- `BBTBSpinner.accessibilityHidden(true)` — кольцо.
- `Image(systemName: "power")` — `.accessibilityHidden(true)` (decorative; статус доносит wrapper-кнопка).

### 3.3 VoiceOver — ServerRow / AutoCell
- ServerRow `.accessibilityElement(children: .combine)` — целая строка как один элемент.
  - Label: имя сервера. Hint: "Двойное касание чтобы выбрать". Value: `pingState` ("20 миллисекунд" / "Недоступно").
  - Selected state добавляет `.accessibilityAddTraits(.isSelected)`.
- AutoCell — label "Автовыбор по скорости", hint "Двойное касание чтобы включить автовыбор", traits `.isButton` + `.isSelected` когда выбрано.

### 3.4 Dynamic Type strategy для SF Pro Expanded
- `.fontWidth(.expanded)` поверх `.system(size:weight:)` **НЕ масштабируется** Dynamic Type автоматически (фиксированный numeric size).
- **Контракт фазы:** Phase 12 — pixel-perfect rebuild → **Dynamic Type не поддерживается в M1–M10 scope**. Все Figma sizes (display 48 / title 16 / labelButton 14 / body 12 / tips 10 / caption 9 / micro 8) остаются фиксированными.
- **Mitigation:** в Phase 12 verify через `@Environment(\.dynamicTypeSize)` — при `>= .accessibility3` НЕ масштабируем, но **layout не должен ломаться** (проверить overflow / truncation на iPhone SE 3 / iPhone 16 в snapshot test с AX3-AX5).
- **Backlog:** полная поддержка Dynamic Type → отдельная фаза в v1.x (см. `<deferred>` 12-CONTEXT.md линии аналогичные Light mode designer-pass).
- **Executor must add comment** в `DS.Typography` source: `/// Dynamic Type intentionally NOT applied per Phase 12 UI-SPEC §3.4. Backlog: v1.x.`

### 3.5 Color contrast — WCAG AA gate
Семантические пары, требующие пройти WCAG AA (≥4.5:1 normal text, ≥3:1 large 18pt+/14pt-bold):

| Foreground | Background | Mode | Status (требуется проверить в Wave 1) |
|---|---|---|---|
| `DS.Color.textPrimary` (#FFFFFF) | `DS.Color.accent` (#14664B) | Dark | Должно быть AA ≥4.5:1 (executor verify) |
| `DS.Color.textPrimary` (#FFFFFF) | `DS.Color.error` (#661414) | Dark | Должно быть AA ≥4.5:1 (executor verify) |
| `DS.Color.textPrimary` (#FFFFFF) | `DS.Color.controlIdle` (#222222) | Dark | Должно быть AA ≥4.5:1 (executor verify) |
| `DS.Color.textSecondary` (#808080) | `DS.Color.canvas` (#000000) | Dark | Должно быть AA ≥4.5:1 — **borderline**, executor verify |
| `DS.Color.iconMuted` (#CCCCCC) | `DS.Color.accent` (#14664B) | Dark | Должно быть AA для UI components ≥3:1 |

Wave 1 task: executor прогоняет контрастный калькулятор (Xcode Accessibility Inspector "Color Contrast Calculator" ИЛИ скрипт) для каждой пары и фиксирует в `12-UAT.md` как PASS/borderline/FAIL. Borderline → consult `12-RESEARCH.md` Risk #7 (Light placeholder), FAIL → блокер phase closure до правки токена.

### 3.6 Tap targets — ≥44×44pt
- **ConnectionButton** (Ø280pt) — overshoot, OK.
- **PrimaryButton / SecondaryButton** (M7) — pill с `.padding(.vertical, DS.Spacing.lg)` = 16+? = должно достигать 44pt+. Executor verify: измерить через snapshot test bounding box.
- **ServerRow** Figma height 52pt → ≥44pt OK.
- **AutoCell pill** — Figma height ≥44pt OK.
- **CaretRight / Delete icons** в ServerRow — иконки 18×18pt; tap target должен быть расширен через `.contentShape(Rectangle()).frame(minWidth: 44, minHeight: 44)`. Executor verify в Wave 1.

### 3.7 Reduce Transparency
- В DS пока **нет** активных `.ultraThinMaterial / blur` фонов поверх контента (DS.Blur.pill — 4pt — применяется только к декоративным pill-фонам без текста под ними).
- Контракт: при `accessibilityReduceTransparency = true` все blur effects заменяются на solid `DS.Color.surface`. Executor проверяет в Wave 1 при применении `DS.Blur.pill` (если M8/M10 коснутся pill-фонов с blur).

### 3.8 Reduce Motion summary
Сводка обязательных fallback'ов (см. §2.7):

| Element | Default motion | Reduce-Motion fallback |
|---|---|---|
| BBTBSpinner | Continuous 1.2s rotation | Discrete 4-frame snap (every 0.4s) OR static ring with opacity pulse |
| PrimaryButton/SecondaryButton press | scale 0.97 + opacity 0.92 (0.12s easeOut) | scale 1.0 + opacity 0.85 (no animation) |
| ServerRow selected transition | easeInOut 0.2s | instantaneous (no `.animation`) |
| power-icon `.symbolEffect(.bounce)` | bounce на state change | disabled via `.disabled(accessibilityReduceMotion)` |

---

## 4. State Coverage Matrix

Cross-check: каждое состояние `ConnectionState` имеет Figma reference screen → manual UAT покрывает все.

| ConnectionState | Figma screen | File (final-*.png) | Snapshot target (DS-* req) |
|---|---|---|---|
| `.empty` (нет серверов) | Onboarding Screen (3062:304) | `01-onboarding.png` | DS-11 (Onboarding view) |
| `.idle` (есть серверы, отключено) | Home — Disconnected (3043:341) | `02-home-disconnected.png` | DS-09 (button state) + DS-12 (server row) |
| `.connecting` | Home — Connecting (3047:538) | `03-home-connecting.png` | DS-08 (Spinner) + DS-09 (button state) |
| `.connected(since:)` | Home — Connected (3047:598) | `05-home-connected.png` | DS-09 (button state) |
| `.error(message:)` | Home — Error (3047:568) | `04-home-error.png` | DS-09 (button state) |

Sheet-state:

| Sheet mode | Figma screen | File (final-*.png) | Manual UAT target |
|---|---|---|---|
| Servers — Selected | 3064:350 | `06-servers-selected.png` | DS-12 (ServerRow) + DS-13 (AutoCell selected) + DS-14 (sheet shape) |
| Servers — Auto | 3064:1579 | `07-servers-auto.png` | DS-12 + DS-13 (AutoCell deselected variant) + DS-14 |

**Итого manual UAT scope:** ровно **7 экранов**, по одному на каждый Figma frame в `final-*.png`. Все маппятся в DS-* requirements (`12-RESEARCH.md` §3 + §6.2). Полностью покрывают `ConnectionState` (5 кейсов) + sheet (2 кейса).

---

## 5. Visual Acceptance Criteria

Сводка (источники: 12-CONTEXT.md D-08..D-10, 12-RESEARCH.md §6.6, §5 Risk #1).

| Criterion | Value | Source |
|---|---|---|
| Pixel diff tolerance (key elements: button Ø, padding, radii, font sizes) | **≤2 px** | 12-CONTEXT.md D-10 |
| Snapshot `precision` (solid fills) | 1.0 | RESEARCH §6.6 |
| Snapshot `perceptualPrecision` (text + AA) | **0.98** | RESEARCH §6.6 |
| Snapshot `perceptualPrecision` (gradient strokes / Spinner) | 0.97 | RESEARCH §6.6 |
| Anti-aliasing variance on text/gradient | Игнорируется как known platform difference | 12-CONTEXT.md D-10 |
| Hybrid verification | Snapshot tests (components) + manual UAT (7 screens) | 12-CONTEXT.md D-08 |
| Manual UAT signed off by | User (см. UAT log в `12-UAT.md`) | Phase boundary |
| Snapshot library version | `pointfreeco/swift-snapshot-testing` ≥ **1.18.3** | RESEARCH Risk #6 |
| Xcode/simulator pin | Document required Xcode 16+ / iOS 18+ simulator | RESEARCH Pitfall 4 + Wave 0 Gap |

**Gate для closure фазы:**
1. ✓ Все DS-01..DS-15 unit/snapshot tests зелёные.
2. ✓ Manual UAT по 7 экранам отмечен PASS в `12-UAT.md` user-ом.
3. ✓ Contrast pairs §3.5 — все PASS (или borderline с explicit user approval).
4. ✓ Reduce Motion fallback verified на iPhone simulator с Settings → Accessibility → Reduce Motion ON.
5. ✓ Phase 12 НЕ ломает существующие ~207 тестов (regression suite green).

---

## 6. What this UI-SPEC does NOT cover (explicit delegation)

UI-SPEC.md **сознательно НЕ содержит**:

| Что не покрыто | Где смотреть |
|---|---|
| Полная палитра 15 DS.Color семантических токенов (Dark + Light hex) | `figma-tokens.json` + `CODE-CONNECT.md` §2.1 |
| 7 типографических размеров (display/title/labelButton/body/tips/caption/micro) и их веса | `CODE-CONNECT.md` §3 |
| Все 6 Radius токенов (small/card/cardLarge/button/section/sheet) | `CODE-CONNECT.md` §2.2 + `figma-tokens.json` |
| 8 типов токенов в `DS.Typography.expanded(...)` helper sized presets | `12-RESEARCH.md` §2.2 + §4.2 |
| ConnectionButton dimensions 280/320/112/128 | `CODE-CONNECT.md` §1.1 + §2.2 + M1/M2 (§4) |
| **10 mismatches M1–M10 (full work list)** | `CODE-CONNECT.md` §4 |
| Figma↔Swift component mapping (Button / Button_BG / Spinner / ServerRow / ServerRow Selected / AutoCell / Onboarding) | `CODE-CONNECT.md` §§1.1–1.7 |
| Hero text split «Интернет, каким он» (white) + «должен быть» (accent) | `12-CONTEXT.md` `<specifics>` + `CODE-CONNECT.md` §1.7 + RESEARCH §4.7 |
| Custom Spinner implementation (Option B chosen) | `12-RESEARCH.md` §2.1 + §4.3 |
| SF Pro Expanded font integration (`.fontWidth(.expanded)`) | `12-RESEARCH.md` §2.2 + §4.2 |
| DS.Color storage strategy (Swift literal pattern) | `12-RESEARCH.md` §2.3 |
| ButtonStyle структура (PrimaryButtonStyle / SecondaryButtonStyle) | `12-RESEARCH.md` §2.5 + §4.4 |
| Sheet 32pt top corners — UnevenRoundedRectangle pattern | `12-RESEARCH.md` §2.6 + §4.6 |
| Snapshot test infrastructure (Wave 0 gaps, baseline policy) | `12-RESEARCH.md` §6 |
| Plan 12-01 (Foundation) vs Plan 12-02 (Application) split | `12-CONTEXT.md` D-01..D-04 + `12-RESEARCH.md` §3 |
| Power-Glow effect — **запрещено восстанавливать в Phase 12** | `12-CONTEXT.md` `<specifics>` + `<deferred>` |
| Light mode designer-pass | `12-CONTEXT.md` `<deferred>` |
| macOS pixel-perfect rebuild | `12-CONTEXT.md` D-11 + `<deferred>` |
| Existing animations / wirings (Phase 11 carry-forward: fullScreenCover, identifiers, NEVPNStatus polling) | Phase 11 closure docs + existing Swift sources |

**Planner-у:** перед декомпозицией задач прочти `CODE-CONNECT.md` §4 (M1–M10) ПОЛНОСТЬЮ. Decompose tasks 1:1 на M1–M10 (D-03: quick wins M1–M5 → heavy lifts M6–M10).

**Executor-у:** при реализации каждой задачи — открывай Figma frame по node-ID из `CODE-CONNECT.md` §1.x + соответствующий `final-*.png` screenshot, и сверяй pixel-by-pixel.

**ui-checker / ui-auditor:** UI-SPEC.md задаёт только §2 motion + §3 a11y + §4 state coverage + §5 acceptance gate. Visual/token-level audit — против `CODE-CONNECT.md` + `figma-tokens.json` напрямую.

---

## 7. Phase 12 ↔ REQUIREMENTS.md mapping

| Requirement | Status в Phase 12 | Validation path |
|---|---|---|
| **UX-09** «Финальный дизайн соответствует Figma (v0.11)» | `figma-pending` → `Validated` после Phase 12 closure | Manual UAT 7 экранов (§4) + DS-* snapshot tests |
| **UX-08** ConnectionButton анимации | Уже `Validated` (Phase 11); Phase 12 заменяет `ProgressView` placeholder на BBTBSpinner (M6) — поведенческое улучшение, не re-validation | DS-08 snapshot test |
| **UX-01** Onboarding | Уже `Validated` (Phase 11); Phase 12 rebuild **внутренней верстки** только (M7), wiring не меняется | DS-10 + DS-11 |

Никаких новых REQ-ID Phase 12 не создаёт. Все DS-01..DS-15 — внутренние ID фазы, не пересекаются с REQUIREMENTS.md.

---

## UI-SPEC COMPLETE
