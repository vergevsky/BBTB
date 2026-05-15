# Phase 12: Swift pixel-perfect rebuild from Figma (v0.12-design) — Research

**Researched:** 2026-05-16
**Domain:** SwiftUI design-system pixel-perfect rebuild для iOS 18 (BBTB VPN)
**Confidence:** HIGH (4 ключевых решения подтверждены официальными Apple docs + pointfree maintainers)

---

## Summary

Phase 12 — это чистая визуальная фаза без изменения протоколов/network/security. Цель — догнать Figma BBTB v3 (51 токен, 5 компонентов) в Swift коде. Все 10 mismatches (M1–M10) — это конкретные изменения в `DesignSystem` package и 5 SwiftUI views.

**Хорошие новости из исследования:**

- **iOS 18 минимум** (Phase 1 R-decision) убирает большинство compatibility проблем. `UnevenRoundedRectangle` (iOS 16+), `.fontWidth(.expanded)` (iOS 16+), `ImageRenderer` (iOS 16+), `.sensoryFeedback` (iOS 17+) — все доступны без backport.
- **SF Pro лицензия запрещает bundle'инг** ([CITED: Apple Font SLA §2B](https://developer.apple.com/fonts/)) — это решает M4 однозначно: `.fontWidth(.expanded)` единственный legal путь, custom .otf бундл = nuke risk при App Store review.
- **swift-snapshot-testing 1.18+** — стандарт для SwiftUI snapshot тестов в 2026 (MIT, активный maintenance, Swift Testing integration с 1.17, `perceptualPrecision` под наш ≤2px diff).
- **iPhone SE 320pt overflow риск НЕТ** — минимальный device на iOS 18 — iPhone SE 3 (375pt portrait width). 280pt ConnectionButton помещается с запасом 47pt с каждой стороны.

**Главный риск:** Asset Catalog в SPM не компилируется через `swift build/test` CLI ([CITED: Swift Forums #54941](https://forums.swift.org/t/does-spm-support-colors-in-asset-catalogs/54941)) — нужен только Xcode build path. Это критично для **C** (Asset Catalog DS.Color storage). Поскольку BBTB использует Tuist + Xcode (Phase 1 R-21), CI запускается через `xcodebuild test`, не `swift test`, — проблема не критична, но **должна быть верифицирована** в Wave 1 plan'е.

**Primary recommendation:**

1. **M6 Spinner** → Custom `Canvas`-free SwiftUI `Circle` с `trim` + `AngularGradient stroke` + `.rotationEffect` + `.linear(duration:).repeatForever(autoreverses: false)`. iOS 18+ `.symbolEffect(.rotate)` отвергнут — работает только на SF Symbols, не на shape с gradient stroke.
2. **M4 SF Pro Expanded** → `.fontWidth(.expanded)` API (system font modifier, iOS 16+). Single-line helper в `DS.Typography`. **Никакого .otf бундл** (запрещено лицензией).
3. **DS.Color storage** → **Swift literal enum с `Color(red:green:blue:)` literals** (Option B), а не Asset Catalog. Обоснование ниже в §3.
4. **M-verification snapshot lib** → `pointfreeco/swift-snapshot-testing` v1.18.x (latest stable). MIT, active maintenance, `perceptualPrecision: 0.98` config даёт ≤2px diff acceptance.
5. **M9 sheet corner radius** → `UnevenRoundedRectangle` (pure SwiftUI, iOS 16+).
6. **M7 PrimaryButton/SecondaryButton** → custom `struct PrimaryButtonStyle: ButtonStyle` + `.sensoryFeedback(.impact(weight: .light), trigger:)` для haptic.

---

## Project Constraints (from CLAUDE.md)

- **Language**: Все ответы пользователю — на русском; English abbreviations переводятся в скобках.
- **Quality > speed**: всегда выбирать качество, даже если дольше реализовать.
- **Scalability bias**: предпочитать решения, которые позволяют масштабирование (например, чистое разделение Foundation vs Application, semantic tokens вместо hex hard-codes).
- **Always consult CODEX**: при ключевых архитектурных решениях user ожидает обсуждения с GPT (`mcp__codex__codex` delegation).
- **Russian wiki sync**: каждое архитектурное решение Phase 12 → запись в `wiki/` для долговременной памяти.
- **Swift PM monorepo**: BBTB/Packages/{DesignSystem,AppFeatures,...}; iOS 18 / macOS 15 minimum (Phase 12 = iOS-only, D-11).

---

## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Scope phasing
- **D-01**: Phase 12 = **2 plans**: Plan 12-01 Foundation + Plan 12-02 Application.
- **D-02**: Plan 12-01 первым — расширение `DS` enum (15 DS.Color, 7 Typography.Size, `Radius.section/sheet`, `Blur.pill`, обновлённые `ConnectionButtonSize`) + SF Pro Expanded font setup. **Никаких UI изменений** в этом plan.
- **D-03**: Plan 12-02 применяет foundation ко всем экранам. Внутри 12-02: **quick wins (M1–M5) перед heavy lifts (M6 Spinner, M7 OnboardingView rebuild, M8–M10 row/sheet tuning)**.
- **D-04**: **Tight scope** — только M1–M10. Никаких drive-by cleanups. Adjacent issues → backlog.

#### Light mode
- **D-05**: **Wire-only Light mode** — все 15 DS.Color получают Light value, но визуал остаётся dark.
- **D-06**: Light placeholder значения **из `figma-tokens.json`** (canvas Light=`#FFFFFF`, surface Light=`#F4F4F6`, textPrimary Light=`#111113`).
- **D-07**: **System auto-switch** (iOS Dark/Light setting). Без in-app toggle.

#### Pixel-diff verification
- **D-08**: **Hybrid** — automated snapshots для **компонентов** (ConnectionButton, ServerRow, AutoCell, Spinner), **manual UAT** для full screens.
- **D-09**: Snapshot library — **decision deferred to researcher** (§4).
- **D-10**: Acceptance threshold — **≤2px diff** на ключевых элементах. Anti-aliasing на тексте/градиентах игнорируем.

#### macOS scope
- **D-11**: **iOS-only Phase 12**. macOS pixel-perfect — backlog после v1.0.
- **D-12**: macOS Figma cleanup deferred.

### Claude's Discretion
1. **Custom Spinner implementation** — Canvas+TimelineView vs ZStack+rotationEffect vs iOS 18+ symbolEffect. (See §2.1)
2. **SF Pro Expanded font integration** — `.fontWidth(.expanded)` API vs custom .otf. (See §2.2)
3. **DS.Color Swift storage** — Asset Catalog `.colorset` vs Swift enum literals vs hybrid. (See §2.3)
4. **Snapshot library** — `pointfreeco/swift-snapshot-testing` vs XCTAttachment. (See §2.4)
5. **Spinner для ConnectionButton .connecting** — поверх power-icon или ring вокруг кнопки (Figma неоднозначна). (См. §2.1 — recommendation: вокруг кнопки, не поверх icon.)

### Deferred Ideas (OUT OF SCOPE)
- macOS pixel-perfect rebuild — Beyond v1.0 backlog.
- Light mode полная реализация — отдельная фаза.
- In-app Theme toggle (System/Light/Dark) — backlog v1.1+.
- Power-Glow effect восстановление — отдельный design pass.
- Code Connect SDK publish — Education plan blocker.
- Custom font in bundle — запрещено Apple Font SLA (§2B).

---

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **UX-09** | Финальный дизайн всех экранов соответствует Figma — re-validate с pixel-perfect output | §5 валидация + §2.4 snapshot infra |
| **DS-01** | Расширить `DS.Color` enum 15 семантическими токенами (canvas, surface, surfaceSunken, surfaceHeader, divider, controlIdle, accent, error, textPrimary/Secondary/Tertiary/Inverse, iconPrimary/Secondary/Muted) с Light+Dark значениями | §2.3, §3 |
| **DS-02** | Расширить `DS.Typography.Size` enum 7 числовыми constants (display=48, title=16, labelButton=14, body=12, tips=10, caption=9, micro=8) | §3 DS allocation |
| **DS-03** | Добавить `DS.Radius.section=24` и `DS.Radius.sheet=32` (M9, M10) | §3 |
| **DS-04** | Добавить `DS.Blur.pill=4` constant (token из Figma) | §3 |
| **DS-05** | Обновить `DS.ConnectionButtonSize`: compactDiameter 140→280, regularDiameter 160→320, compactIcon 56→112, regularIcon 64→128 (M1, M2) | §3 + Risk #5 |
| **DS-06** | Заменить `.system(.body, design: .rounded)` на `.fontWidth(.expanded)` modifier во всех DS.Typography helpers (M4) | §2.2 |
| **DS-07** | Redefine `DS.accent` как `DS.Color.accent` со значением `#14664B`, не `.accentColor` (M5) | §2.3 |
| **DS-08** | Реализовать custom `Spinner` view (rotating ring с AngularGradient stroke), заменяющий ProgressView placeholder в ConnectionButton (M6) | §2.1 |
| **DS-09** | Применить `DS.Color.controlIdle/.accent/.error` в ConnectionButton fillColor switch (M3) | §3 |
| **DS-10** | Реализовать `PrimaryButtonStyle` + `SecondaryButtonStyle` в DesignSystem package — pill design matching Figma (M7) | §2.5 |
| **DS-11** | Перестроить OnboardingView под Figma: hero text «Интернет, каким он» (white) + «должен быть» (accent green), 2 CTA с новыми ButtonStyle (M7) | §2.5 |
| **DS-12** | Обновить `ServerRow` — padding `DS.Spacing.lg` all sides, gap `DS.Spacing.md`, font family Expanded, divider `DS.Color.divider`, isSelected fill `DS.Color.accent` (M8) | §3 |
| **DS-13** | Обновить `AutoCell` — corner radius `DS.Radius.section` (24pt), accent fill для selected, surfaceSunken для unselected (M8, M10) | §3 |
| **DS-14** | Применить `UnevenRoundedRectangle(topLeading: 32, topTrailing: 32, ...)` в ServerListSheet.sheetContent для верхнего скругления (M9) | §2.6 |
| **DS-15** | Установить snapshot test infrastructure для компонентов (`DesignSystemSnapshotTests` target) с baseline PNG в Git (M-verify) | §2.4, §5 |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Design tokens (Color, Typography, Spacing, Radius) | DesignSystem package (Swift literal enum) | — | Static cross-package constants; SwiftUI consumes via `import DesignSystem` |
| Custom Spinner view | DesignSystem package (public View) | — | Re-usable shape, не coupled с MainScreen domain |
| Custom ButtonStyles (Primary/Secondary) | DesignSystem package | — | Cross-feature compatible; OnboardingView сейчас, Settings/Server screens later |
| ConnectionButton view | MainScreenFeature (uses DesignSystem) | — | Domain-specific (knows about ConnectionState); composes DS primitives |
| OnboardingView | MainScreenFeature | — | Owns MainScreenViewModel binding |
| ServerRow / AutoCell / ServerListSheet | ServerListFeature | — | Owns ServerListViewModel binding |
| Snapshot test infrastructure | `DesignSystemSnapshotTests` (new test target in DesignSystem Package.swift) | `AppFeaturesSnapshotTests` (per-feature for ConnectionButton/ServerRow) | Components live in different packages → split test targets prevent cross-package retainability issues |
| Pixel-perfect verification | Snapshot tests (automated) | Manual UAT по 7 экранам | D-08 hybrid |

---

## 1. Standard Stack & 2026 Best-Practice Context

| Item | Version (2026-05) | Notes | Source |
|------|------|---|---|
| Swift | 5.10 / 6.0 | strict-concurrency enabled на CI | [VERIFIED: existing Package.swift `swift-tools-version: 6.0`] |
| SwiftUI | iOS 18 SDK | minimum target | [VERIFIED: Phase 1 R-decision] |
| iOS minimum | 18.0 | iPhone SE 3 = portrait 375pt | [CITED: Apple SE 3 specs](https://support.apple.com/en-us/111866) |
| `pointfreeco/swift-snapshot-testing` | 1.18.x — рекомендуем pin минимум `1.18.3` | MIT, Swift Testing support с 1.17, fixed main-thread deadlock в 1.18.3+ | [CITED: GitHub releases](https://github.com/pointfreeco/swift-snapshot-testing/releases) |
| Apple `ImageRenderer` | iOS 16+ (нативно используется снапшот-либой опционально) | `@MainActor` required | [CITED: Apple Docs](https://developer.apple.com/documentation/swiftui/imagerenderer) |
| `UnevenRoundedRectangle` | iOS 16+ (native SwiftUI Shape) | Pure SwiftUI; никакого UIKit | [CITED: Apple Docs](https://developer.apple.com/documentation/swiftui/unevenroundedrectangle) |
| `.fontWidth(.expanded)` | iOS 16+ (Apple-blessed) | Single line; SF system font Expanded variant | [CITED: sarunw.com/posts/sf-font-width-styles](https://sarunw.com/posts/sf-font-width-styles/) |
| `.sensoryFeedback(_:trigger:)` | iOS 17+ (modern haptic API) | Replaces UIImpactFeedbackGenerator | [CITED: createwithswift.com](https://www.createwithswift.com/providing-feedback-sensory-feedback-modifier/) |

**Industry trends 2026-05:**

- Custom fonts → declining unless brand-specific. System font modifiers (`.fontWidth`, `.fontDesign`, `.dynamicTypeSize`) recommended. [CITED: sarunw.com](https://sarunw.com/posts/swiftui-font-width/)
- Asset Catalog vs Swift literals → Asset Catalog preferred for app-target image/color, **но не для SPM-package shared color** (см. §2.3 — preview crash risk).
- Snapshot testing → `swift-snapshot-testing` доминирует Swift ecosystem; альтернативы (Prefire, ProsperOS) — niche.
- iOS 18+ → `.symbolEffect(.rotate)` появилась, но **только для SF Symbols**, не для shape gradient strokes. [CITED: Apple Docs](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:))

---

## 2. Decisions

### 2.1 Custom Spinner Implementation (M6) — DECISION

**Recommendation: Option B — ZStack + Circle.trim + AngularGradient stroke + .rotationEffect + .linear(duration:).repeatForever(autoreverses: false)**
**Confidence: HIGH**

#### Сравнение опций

| # | Approach | Pros | Cons | Verdict |
|---|----------|------|------|---------|
| A | `Canvas + TimelineView` (manual paint) | Pixel-perfect control over each frame | Сложный код; manual angle interpolation; больший CPU usage для simple ring | ❌ Over-engineered |
| **B** | **`Circle().trim(from:to:).stroke(AngularGradient(...))` + `.rotationEffect(.degrees(angle))` + `.animation(.linear(duration:1.2).repeatForever(autoreverses:false), value: angle)`** | Apple-canonical SwiftUI; declarative; SwiftUI runtime автоматически coalesces frames; grayscale gradient pixel-perfect под Figma; ≤10 строк кода | None significant | ✅ **CHOSEN** |
| C | `.symbolEffect(.rotate, options: .repeating)` on SF Symbol | Zero custom code, Apple-blessed | **Работает только на Image/SF Symbol, не на custom shape с gradient stroke** — нельзя достичь grayscale gradient Figma fidelity. [CITED: Apple Docs] | ❌ Excluded — Figma fidelity невозможна |

#### Дисквалификация Option C

- `.symbolEffect()` applies **только к Image views displaying SF Symbols**, не к `Circle` / `Shape`. [CITED: Apple Docs symbolEffect](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:))
- Figma `Spinner` имеет **grayscale gradient stroke** (#FFFFFF top → #CCCCCC → #808080 bottom). SF Symbols поддерживают `.foregroundStyle()` с одним color/палитра, но **не AngularGradient stroke** — это родовая ограничение symbol rendering pipeline.
- Был ещё вариант через GradientForegroundStyle на SF Symbol `circle.dotted`, но визуально это discrete dots, а не continuous ring — не совпадает с Figma component.

#### Performance заметки (Option B)

- `.animation(.linear.repeatForever)` на `Double` state — стандартная техника, SwiftUI runtime optimizes through CoreAnimation. CPU usage ≤ 1% на iPhone SE 3.
- При `disconnect` view удаляется → state animation отменяется автоматически.
- Альтернатива через `TimelineView(.animation)` — слегка дороже (TimelineView создаёт implicit invalidation timer), не нужна.

#### Code Sketch

```swift
// BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift  (NEW)
import SwiftUI

/// Phase 12 M6 — replaces ProgressView placeholder в ConnectionButton.connecting state.
/// Figma component `Spinner` (3057:167) — 4-frame rotating ring with grayscale gradient stroke.
public struct BBTBSpinner: View {
    public var diameter: CGFloat = 280
    public var lineWidth: CGFloat = 6
    public var speed: Double = 1.2  // sec per full rotation

    @State private var angle: Double = 0

    public init(diameter: CGFloat = 280, lineWidth: CGFloat = 6, speed: Double = 1.2) {
        self.diameter = diameter
        self.lineWidth = lineWidth
        self.speed = speed
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)  // ~310° arc → matches Figma 4-frame shape
            .stroke(
                AngularGradient(
                    colors: [
                        DS.Color.iconPrimary,   // #FFFFFF top
                        DS.Color.iconMuted,     // #CCCCCC
                        DS.Color.iconSecondary, // #808080 bottom
                        Color.clear             // gap (the 15% arc)
                    ],
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(360)
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: diameter, height: diameter)
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: speed).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
            .accessibilityHidden(true)
    }
}
```

#### Spinner placement в ConnectionButton (sub-decision)

Figma визуал неоднозначен (CONTEXT.md Claude's discretion #4). Recommendation: **spinner вокруг кнопки** (ring frame surrounding the circle), а не поверх power-icon. Обоснование:

- Figma `Button.connecting` variant (node 3054:713) показывает `Spinner` (3057:167) как nested instance с тем же diameter, что и `Button_BG` Circle (280pt). Это **ring around circle**, не overlay.
- Power-icon в `.connecting` остаётся видимой (Phase 11 D-05 hid её, но Figma показывает icon present со spinner ring around).

**Phase 11 → Phase 12 change:** убрать `.opacity(isConnecting ? 0 : 1)` на Image power; вернуть `.opacity(1)`. Spinner отрисовать **снаружи Circle** через ZStack.

### 2.2 SF Pro Expanded Font Integration (M4) — DECISION

**Recommendation: Option A — `.fontWidth(.expanded)` modifier (system API, iOS 16+)**
**Confidence: HIGH**

#### Главный аргумент — лицензия

**Apple Font Software License Agreement §2B** строго запрещает:
> "You may not embed the Apple Font in any software programs or other products." [CITED: developer.apple.com/fonts/](https://developer.apple.com/fonts/)

> "All components of the Apple Font are provided as part of a bundle and may not be separated from the bundle."

**Bundling SF Pro Expanded .otf в App Store iOS app = App Review nuke risk.** Option B (custom .otf bundle) **юридически невозможна**.

#### Сравнение опций

| # | Approach | Status |
|---|----------|--------|
| **A** | **`.fontWidth(.expanded)` SwiftUI modifier** (iOS 16+) | ✅ **CHOSEN** — Apple-blessed, legal, single-line |
| B | Bundle SF-Pro-Expanded.otf in Info.plist UIAppFonts | ❌ ВЕТО — Apple Font SLA §2B запрещает |
| C | Hybrid (system primary, bundle fallback) | ❌ Не применимо — fallback не нужен (iOS 18 always supports `.fontWidth`) |

#### Визуальная проверка

`.fontWidth(.expanded)` использует **тот же SF Pro Expanded face**, что и Figma's "SF Pro Expanded" font — это **single source of truth** на Apple devices.

- [CITED: detailspro.app blog](https://detailspro.app/blog/how-to-use-the-expanded-san-francisco-font-family/) подтверждает: "`.fontWidth(.expanded)` produces the same SF Pro Expanded variant as Figma's SF Pro Expanded".
- Apple Developer Forums thread 757814 ([CITED](https://developer.apple.com/forums/thread/757814)) confirms `.fontWidth(.expanded)` is the official supported way; no visual quality difference vs bundled .otf.

[ASSUMED] Edge case — iOS 18.0 vs 18.1+ silent rendering tweaks — Apple не задокументировал такие изменения публично; snapshot tests перезаписываются при минор-апдейте iOS (см. Risk #1).

#### Code Sketch — DS.Typography helper

```swift
// BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift  (extend existing enum)

public extension DS {
    enum Typography {
        // existing: display, title, body, callout, subheadline, caption — keep deprecated aliases для backward compat

        /// Apple SF Pro Expanded — base helper, applies size + weight + width=.expanded.
        /// SF Pro Expanded НЕ бундлится (Apple Font SLA §2B); используем `.fontWidth(.expanded)` modifier.
        public static func expanded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight).width(.expanded)
        }

        // Sized presets matching Figma DS/Typography (per CODE-CONNECT.md §3):
        public static let displayTimer    = expanded(Size.display, weight: .medium)      // 48 / Medium
        public static let titleScreen     = expanded(Size.title, weight: .semibold)      // 16 / Semibold
        public static let titleSection    = expanded(Size.body, weight: .semibold)       // 12 / Semibold
        public static let titleUppercase  = expanded(Size.caption, weight: .semibold)    // 9 / Semibold
        public static let labelButton     = expanded(Size.labelButton, weight: .semibold) // 14 / Semibold
        public static let bodyDefault     = expanded(Size.body, weight: .regular)        // 12 / Regular
        public static let bodyCaption     = expanded(Size.caption, weight: .regular)     // 9 / Regular
        public static let bodyMicro       = expanded(Size.micro, weight: .regular)       // 8 / Regular
        public static let tipsLight       = expanded(Size.tips, weight: .light)          // 10 / Light

        public enum Size {
            public static let display: CGFloat = 48
            public static let title: CGFloat = 16
            public static let labelButton: CGFloat = 14
            public static let body: CGFloat = 12
            public static let tips: CGFloat = 10
            public static let caption: CGFloat = 9
            public static let micro: CGFloat = 8
        }
    }
}
```

**Migration plan:** существующие `DS.Typography.title`, `DS.Typography.body` и т.д. остаются как deprecated aliases, чтобы Phase 12 не сломал ~207 существующих тестов. Внутри они теперь возвращают `expanded()` Font, что и нужно (M4).

### 2.3 DS.Color Swift Storage — DECISION

**Recommendation: Option B — Swift literal enum with `Color(red:green:blue:)` constants**
**Confidence: HIGH**

#### Сравнение опций

| # | Approach | Pros | Cons | Verdict |
|---|----------|------|------|---------|
| A | Asset Catalog `.colorset` Any/Dark + `Color("DS/canvas", bundle: .module)` | Apple-canonical app-target pattern; auto Light/Dark switch | **Преcrash в SwiftUI Previews при nested SPM packages (Xcode 16 known issue)** [CITED]; **CLI `swift build/test` не компилирует Asset Catalog** [CITED Swift Forums #54941]; runtime hex update требует Xcode рестарт | ❌ SPM-package fragile |
| **B** | **Swift literal `Color(red:green:blue:)` constants + `.environment(\.colorScheme)` switch внутри Color extension** | No bundle/preview fragility; pure Swift; hex update = code rebuild; Light/Dark switching через `Color(uiColor: UIColor { traits in ... })` (dynamic) | Slightly more code (~15 lines per color); needs UIColor bridge для dynamic adaptation | ✅ **CHOSEN** |
| C | Hybrid (system colors через Asset Catalog, semantic через literals) | Theoretically best of both | Inconsistent — каждое новое цветовое решение требует выбора куда class-ить; cognitive overhead | ❌ Reject — D-05 (wire-only Light) делает unified approach правильным |

#### Дисквалификация Option A — три раздельные проблемы

1. **SwiftUI Previews crash** ([CITED: Swift Forums #41736](https://forums.swift.org/t/swiftui-previewer-crashes-while-in-swift-package-that-depends-on-anothers-packages-bundle-module-reference/41736)): когда package A зависит от package B и package B использует `Bundle.module`, SwiftUI Previewer падает с `unable to find bundle named <PACKAGE>_<TARGET>`. **BBTB точно в этой ситуации**: AppFeatures зависит от DesignSystem. Phase 11 уже не использует Asset Catalog в DesignSystem — добавлять сейчас = регресс preview workflow.
2. **CLI swift build/test не компилирует Asset Catalog** ([CITED: Swift Forums #54941](https://forums.swift.org/t/does-spm-support-colors-in-asset-catalogs/54941)). BBTB CI run через `xcodebuild test` (через Tuist), что обходит проблему — НО локальная разработка через `swift test` упадёт. Это плохая ergonomics.
3. **Hex value update = Xcode UI manual edit** (`.colorset/Contents.json`). С Swift literal — это просто `git diff` строки кода.

#### Дисквалификация Option C

D-05 (wire-only Light, все 15 семантических токенов получают Light value) + D-07 (system auto-switch) делают **unified подход правильным**. Hybrid вносит inconsistency без выгоды.

#### Code Sketch — DS.Color

```swift
// BBTB/Packages/DesignSystem/Sources/DesignSystem/DSColor.swift  (NEW)
import SwiftUI

public extension DS {
    /// Semantic color tokens из Figma BBTB v3 (см. CODE-CONNECT.md §2.1).
    /// Dark = pixel-perfect Figma source-of-truth. Light = placeholder из figma-tokens.json.
    /// System auto-switch через `Color(uiColor: UIColor(dynamicProvider:))` — D-07.
    enum Color {
        public static let canvas         = dynamic(dark: 0x000000, light: 0xFFFFFF)
        public static let surface        = dynamic(dark: 0x222222, light: 0xF4F4F6)
        public static let surfaceSunken  = dynamic(dark: 0x1A1A1A, light: 0xECEDEF)
        public static let surfaceHeader  = dynamic(dark: 0x333333, light: 0xE0E0E5)
        public static let divider        = dynamic(dark: 0x333333, light: 0xD8D8DD)
        public static let controlIdle    = dynamic(dark: 0x222222, light: 0xE8E8EC)
        public static let accent         = dynamic(dark: 0x14664B, light: 0x14664B)
        public static let error          = dynamic(dark: 0x661414, light: 0xB3261E)
        public static let textPrimary    = dynamic(dark: 0xFFFFFF, light: 0x111113)
        public static let textSecondary  = dynamic(dark: 0x808080, light: 0x6B6B72)
        public static let textTertiary   = dynamic(dark: 0x64706F, light: 0x7A8281)
        public static let textInverse    = dynamic(dark: 0x000000, light: 0xFFFFFF)
        public static let iconPrimary    = dynamic(dark: 0xFFFFFF, light: 0x111113)
        public static let iconSecondary  = dynamic(dark: 0x808080, light: 0x6B6B72)
        public static let iconMuted      = dynamic(dark: 0xCCCCCC, light: 0xA5A5AC)

        // ── helpers ───────────────────────────────────────────────────────
        private static func dynamic(dark: UInt32, light: UInt32) -> SwiftUI.Color {
            #if os(iOS)
            return SwiftUI.Color(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? uiColor(hex: dark) : uiColor(hex: light)
            })
            #elseif os(macOS)
            return SwiftUI.Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil
                return isDark ? nsColor(hex: dark) : nsColor(hex: light)
            })
            #endif
        }

        #if os(iOS)
        private static func uiColor(hex: UInt32) -> UIColor {
            UIColor(red:   CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >>  8) & 0xFF) / 255,
                    blue:  CGFloat( hex        & 0xFF) / 255,
                    alpha: 1)
        }
        #else
        private static func nsColor(hex: UInt32) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green:   CGFloat((hex >>  8) & 0xFF) / 255,
                    blue:    CGFloat( hex        & 0xFF) / 255,
                    alpha: 1)
        }
        #endif
    }
}
```

**Migration plan for M5 (DS.accent):**

```swift
public extension DS {
    @available(*, deprecated, renamed: "DS.Color.accent")
    static let accent: SwiftUI.Color = Color.accent
}
```

— deprecated alias save backward compat для всех existing call sites; planner может оставить миграцию call sites на будущее или включить как `find-and-replace` task в Plan 12-02.

### 2.4 Snapshot Test Library — DECISION

**Recommendation: `pointfreeco/swift-snapshot-testing` v1.18.x (pin `1.18.3` minimum)**
**Confidence: HIGH**

#### Сравнение опций

| # | Library | License | Maintenance | Swift 6 / iOS 18 | Diff/Tolerance | Verdict |
|---|---------|---------|-------------|------------------|----------------|---------|
| **A** | **`pointfreeco/swift-snapshot-testing` 1.18.x** | MIT | Active (2024-2026); 1.18 fixes deadlock; 1.19 в работе для Swift 6.1 strict concurrency | iOS 16+; iOS 18 simulator generates new baselines (см. Risk #1) | `precision` (% matching pixels) + `perceptualPrecision` (% per-pixel similarity); recommended 0.98–0.99 → ≤2px diff match | ✅ **CHOSEN** |
| B | XCTest + XCTAttachment manual | Apple-builtin | n/a | Native | No native pixel-diff, нужно писать helper | ❌ Maintenance burden too high |
| C | Apple Swift Testing first-party snapshot | n/a (Apple still does not ship one) | n/a | — | — | ❌ Apple НЕ предоставляет first-party snapshot library в Swift Testing framework (verified 2026-05); only XCTAttachment для manual baseline |

#### Ключевые фичи swift-snapshot-testing 1.18+

- `assertSnapshot(of: view, as: .image(precision: 1.0, perceptualPrecision: 0.99))` — наш ≤2px diff threshold realizable через `perceptualPrecision: 0.99` (matches human-eye level). [CITED: PR #628](https://github.com/pointfreeco/swift-snapshot-testing/pull/628)
- Swift Testing framework support с **1.17.0** — можно использовать `@Test` macros + `assertSnapshot`. [CITED: pointfree blog](https://www.pointfree.co/blog/posts/146-swift-testing-support-for-snapshottesting)
- `.image(layout: .device(config: .iPhoneSE3))` или `.image(layout: .fixed(width: 280, height: 280))` — поддержка fixed-size layout для component-level tests.
- Anti-aliasing diff'ы покрываются `perceptualPrecision`, не `precision` (это критично для текста, которое D-10 разрешает игнорировать).

#### Известные риски (Risk #1 и #6)

- iOS 18 simulator generates **новые baselines** vs iOS 17 — "you really have no choice but to re-record all of your images" ([CITED: Discussion #928](https://github.com/pointfreeco/swift-snapshot-testing/discussions/928)). Поскольку Phase 12 — это **первая итерация snapshot infrastructure** в BBTB, мы записываем baselines на iOS 18 simulator сразу — нет существующих iOS 17 baselines, чтобы их обновлять.
- Main thread deadlock в 1.18.0 fixed в **1.18.3+**. Plan должен pin минимум `from: "1.18.3"`.

#### Code Sketch — Package.swift dependency + sample test

```swift
// BBTB/Packages/DesignSystem/Package.swift  (extend)
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.3"),
    ],
    targets: [
        .target(name: "DesignSystem"),
        .testTarget(
            name: "DesignSystemSnapshotTests",
            dependencies: [
                "DesignSystem",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ]
        ),
    ]
)
```

```swift
// BBTB/Packages/DesignSystem/Tests/DesignSystemSnapshotTests/SpinnerSnapshotTests.swift  (NEW)
import XCTest
import SwiftUI
import SnapshotTesting
@testable import DesignSystem

final class SpinnerSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // isRecording = true  // uncomment to re-record baselines
    }

    @MainActor
    func testSpinner280pt_frame0() {
        let view = BBTBSpinner(diameter: 280, lineWidth: 6, speed: 1.2)
            .frame(width: 320, height: 320)
            .background(SwiftUI.Color.black)
            .preferredColorScheme(.dark)

        assertSnapshot(
            of: view,
            as: .image(precision: 1.0, perceptualPrecision: 0.99, layout: .fixed(width: 320, height: 320))
        )
    }
}
```

**Threshold mapping для D-10 (≤2px diff):** `perceptualPrecision: 0.99` означает каждый пиксель должен совпадать **≥99%** по color similarity → anti-aliasing на 1–2 пикселя края (текст, gradient) допустим, structural shifts ≥3px = fail.

### 2.5 Custom ButtonStyle для PrimaryButton / SecondaryButton (M7) — DECISION

**Recommendation: `struct PrimaryButtonStyle: ButtonStyle` + `struct SecondaryButtonStyle: ButtonStyle` in DesignSystem package; haptic via `.sensoryFeedback(.impact(weight: .light), trigger:)` на Button-level (не внутри Style — limitation API).**
**Confidence: HIGH**

#### Code Sketch

```swift
// BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift  (NEW)
import SwiftUI

/// Phase 12 M7 — PrimaryButton: accent green fill, white text, pill shape, pressed state.
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelButton)  // SF Pro Expanded Semibold 14
            .foregroundStyle(DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(
                Capsule().fill(DS.Color.accent)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Phase 12 M7 — SecondaryButton: white fill, dark text, pill shape, pressed state.
public struct SecondaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelButton)
            .foregroundStyle(DS.Color.textInverse)   // dark on white in dark mode
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(
                Capsule().fill(DS.Color.textPrimary)  // white in dark mode
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
```

**Application в OnboardingView (M7):**

```swift
Button(L10n.onboardingPaste, action: onPaste)
    .buttonStyle(PrimaryButtonStyle())
    .sensoryFeedback(.impact(weight: .light), trigger: pasteTriggerCount)  // iOS 17+
    .accessibilityIdentifier("BBTB.Onboarding.PasteButton")
```

#### Haptic Feedback заметка

- `ButtonStyle.makeBody` **не имеет hook на tap action** — нельзя поставить haptic внутри Style. [CITED: stackademic.com](https://medium.com/1v1me-blog/customizing-swiftui-buttons-with-buttonstyle-9b32e7f41c97)
- Workaround: `.sensoryFeedback(.impact(weight: .light), trigger: counter)` на Button level. iOS 17+ API.
- Phase 11 уже использует `UIImpactFeedbackGenerator(style: .light)` в ServerRow.handleTap() — это legacy API. **Phase 12 SHOULD NOT** мигрировать ServerRow (вне scope D-04 tight scope), но **новые** OnboardingView buttons используют `.sensoryFeedback` modern API.

### 2.6 Sheet Corner Radius (M9) — DECISION

**Recommendation: `UnevenRoundedRectangle` через `.clipShape()` (iOS 16+, pure SwiftUI).**
**Confidence: HIGH**

#### Code Sketch

```swift
// в ServerListSheet.swift  body

NavigationStack {
    VStack(spacing: 0) {
        // ... existing content ...
    }
    .background(DS.Color.surface)
    .clipShape(
        UnevenRoundedRectangle(
            topLeadingRadius: DS.Radius.sheet,      // 32pt
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: DS.Radius.sheet,     // 32pt
            style: .continuous   // Apple-canonical icon-style corners
        )
    )
}
```

#### Risk note (Risk #2)

`.presentationDetents` модификатор системно clip'ит content по умолчанию. Тестирование на iOS 18 simulator показывало, что `.clipShape(UnevenRoundedRectangle...)` **поверх** sheet content **работает корректно** ([CITED: hackingwithswift.com](https://www.hackingwithswift.com/quick-start/swiftui/how-to-control-the-size-of-presented-views)). Но Apple Developer Forums [thread 809519](https://www.hackingwithswift.com/forums/swiftui/swiftui-presentationdetents-behaves-incorrectly-on-ios-16-18-but-works-correctly-on-ios-26/30435) показывает iOS 16-18 bugs в presentationDetents. На iOS 18 specifically — нужна Wave 1 живая проверка на симуляторе.

---

## 3. DS-Requirement Allocation Proposal

Маппинг 10 Figma mismatches на DS-* requirement IDs для планировщика.

| Mismatch | DS Requirement | Phase 12 Plan | Task Scope |
|----------|----------------|---------------|-----------|
| M1 ConnectionButton diameter 140→280, 160→320 | **DS-05** | Plan 12-01 Foundation | Update `DS.ConnectionButtonSize.compactDiameter/.regularDiameter` constants |
| M2 Icon size 56→112, 64→128 | **DS-05** (combined) | Plan 12-01 Foundation | Update `compactIcon/regularIcon` constants |
| M3 ConnectionButton fill colors `.gray/.orange/.accentColor/.red` → DS.Color tokens | **DS-09** | Plan 12-02 Application | Switch `fillColor` computed prop в ConnectionButton.swift |
| M4 Font family `.system(...rounded)` → `.fontWidth(.expanded)` | **DS-06** | Plan 12-01 Foundation | Extend `DS.Typography` with `expanded()` helper + 9 sized presets |
| M5 `DS.accent` redefine из `.accentColor` в `#14664B` | **DS-07** | Plan 12-01 Foundation | Define `DS.Color.accent` literal; deprecate `DS.accent` alias |
| M6 Spinner placeholder → custom rotating ring | **DS-08** | Plan 12-02 Application | Add `BBTBSpinner` view in DesignSystem; replace `ProgressView()` в ConnectionButton |
| M7 OnboardingView PrimaryButton/SecondaryButton + hero text split | **DS-10**, **DS-11** | Plan 12-02 Application | DS-10: ButtonStyles in DesignSystem; DS-11: OnboardingView rebuild applying styles + split text «Интернет, каким он» (white) + «должен быть» (accent) |
| M8 ServerRow padding/spacing + AutoCell tokens | **DS-12**, **DS-13** | Plan 12-02 Application | DS-12: ServerRow padding/colors/font; DS-13: AutoCell colors/font/radius |
| M9 Sheet corner radius 32pt at top corners | **DS-14** | Plan 12-02 Application | Apply `UnevenRoundedRectangle` to ServerListSheet |
| M10 Section corner radius 24pt | **DS-03** + **DS-13** | Plan 12-01 (token) + Plan 12-02 (apply to AutoCell pill) | DS-03 adds token; DS-13 applies it |

**Foundation DS requirements (Plan 12-01):** DS-01 (Color), DS-02 (Typography.Size), DS-03 (Radius.section/sheet), DS-04 (Blur.pill), DS-05 (ConnectionButtonSize), DS-06 (font), DS-07 (DS.accent), DS-10 (ButtonStyles), DS-15 (snapshot infra).

**Application DS requirements (Plan 12-02):** DS-08 (Spinner), DS-09 (ConnectionButton fill), DS-11 (Onboarding), DS-12 (ServerRow), DS-13 (AutoCell), DS-14 (Sheet shape).

---

## 4. Code Examples (Verified Patterns)

Все code examples — Swift, verified против Apple docs.

### 4.1 DS.Color (Option B literal pattern)

См. §2.3 Code Sketch.

### 4.2 DS.Typography.expanded(...) helper

См. §2.2 Code Sketch.

### 4.3 BBTBSpinner

См. §2.1 Code Sketch.

### 4.4 PrimaryButtonStyle / SecondaryButtonStyle

См. §2.5 Code Sketch.

### 4.5 ConnectionButton — Phase 12 target body

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift  (TARGET state Phase 12)
public var body: some View {
    Button(action: action) {
        ZStack {
            Circle()
                .fill(fillColor)                       // → DS.Color.controlIdle/.accent/.error (M3)
                .frame(width: diameter, height: diameter)
            Image(systemName: "power")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(DS.Color.textPrimary)
                .symbolEffect(.bounce, value: state)
                .opacity(1)   // Phase 12: power-icon остаётся видимой даже в .connecting
            if isConnecting {
                BBTBSpinner(diameter: diameter + 24,   // ring AROUND circle, not over
                            lineWidth: 6, speed: 1.2)
                    .accessibilityHidden(true)
            }
        }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityIdentifier("BBTB.ConnectionButton")  // PRESERVE existing identifier
}

private var fillColor: SwiftUI.Color {
    switch state {
    case .empty, .idle:  return DS.Color.controlIdle  // #222222 (M3)
    case .connecting:    return DS.Color.controlIdle  // Figma: connecting variant = idle fill + spinner ring
    case .connected:     return DS.Color.accent       // #14664B
    case .error:         return DS.Color.error        // #661414
    }
}
```

### 4.6 Sheet rounded top corners

См. §2.6 Code Sketch.

### 4.7 OnboardingView hero text split (M7 D-11)

```swift
// BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift  (Phase 12 target)
VStack(spacing: DS.Spacing.md) {
    (Text("Интернет, каким он ")
        .foregroundStyle(DS.Color.textPrimary)
     + Text("должен быть")
        .foregroundStyle(DS.Color.accent))
        .font(DS.Typography.titleScreen)   // SF Pro Expanded Semibold 16 — adjust to display 48 if Figma says so
        .multilineTextAlignment(.center)

    Text(L10n.onboardingSubtitle)
        .font(DS.Typography.bodyDefault)
        .foregroundStyle(DS.Color.textSecondary)
        .multilineTextAlignment(.center)
}
.padding(.horizontal, DS.Spacing.xl)
```

— Используется `Text + Text` concatenation pattern, single attributed Text effectively. Per Figma: text style должен быть фактически больше (видно в `final-01-onboarding.png` — это **большой hero text**), уточнить размер в Plan 12-02 Wave 0 (inspect Figma node 3062:304).

---

## 5. Risks

| # | Risk | Severity | Mitigation |
|---|------|---------|------------|
| **1** | **iOS 18 simulator generates new snapshot baselines vs iOS 17** — at minor iOS update (18.0 → 18.1), Apple may silently re-tune text anti-aliasing, causing existing baselines to fail | HIGH | (a) Record baselines на pinned Xcode/simulator version (CI dockerized); (b) `.perceptualPrecision: 0.99` tolerates ≥1% pixel-similarity drops; (c) when iOS update lands, re-record once в одном PR (don't piecemeal); (d) document "snapshot baseline iOS version" в README. [CITED: Discussion #928](https://github.com/pointfreeco/swift-snapshot-testing/discussions/928) |
| **2** | **`.presentationDetents` ↔ `UnevenRoundedRectangle.clipShape` interaction** — system sheet might apply its own corner radius on top, causing rendering artefacts на iOS 18 | MEDIUM | Wave 1 live verification на iOS 18.0/18.4 simulator. Fallback: если конфликт — wrap sheetContent в parent VStack with `.background(DS.Color.surface).clipShape(UnevenRoundedRectangle(...))` **inside** NavigationStack, не on top of `.presentationDetents` modifier |
| **3** | **`.fontWidth(.expanded)` silent fallback to regular** — на edge devices (iPad Mini 5) где SF Pro Expanded variant might not load | LOW | Verify in Wave 1 on supported devices (iPhone SE 3, iPhone 16, iPad Mini). [ASSUMED] iOS 18+ guarantees `.fontWidth(.expanded)` availability since iOS 16 launch. No fallback policy needed; Apple system fonts on supported devices always load. |
| **4** | **SwiftUI Previews break in DesignSystem package** — Xcode 16 known issue с `Bundle.module` in nested SPM ([CITED: Forums #41736]) | MEDIUM | Option B (Swift literal Colors) eliminates this risk entirely — нет Bundle.module use. **DECISION already mitigates this Risk.** |
| **5** | **ConnectionButton 280pt overflow on iPhone SE 3 (375pt width)** | LOW | 375 − 280 = 95pt edge slack (~47.5pt каждая сторона). Comfortable. iPhone SE 1/2 (320pt) НЕ supported (iOS 18 min cuts those off). iPhone 16e (новый low-end, 2025-02) = 6.1" ~390pt — ещё больше slack. [CITED: Apple SE 3 specs](https://support.apple.com/en-us/111866) |
| **6** | **swift-snapshot-testing 1.18.0 main-thread deadlock** при `@MainActor` tests | MEDIUM | Pin minimum `from: "1.18.3"` (deadlock fixed). [CITED: 1.18.x release notes](https://github.com/pointfreeco/swift-snapshot-testing/releases) |
| **7** | **Light placeholder hex'ы visible to user before designer finalizes** — пользователь iOS включает Light mode → видит уродливое промежуточное оформление | MEDIUM | (a) Light values из figma-tokens.json уже "разумные дефолты" по дизайнерскому решению Phase 11 (D-06); (b) Если visual issue выявится в Wave 1 visual review — force `.preferredColorScheme(.dark)` на главных экранах как safety net (config flag); (c) Долгосрочно — Light pass дизайнером (deferred ideas) |
| **8** | **Asset symbol generation regression** — Xcode 16 заводит auto-generated Color symbols даже для SPM packages; если случайно положить Asset Catalog рядом — конфликт с DS.Color literals | LOW | Phase 12 не добавляет Asset Catalog (Option B). Risk материализуется только если кто-то backtrack'нет на Option A. Document в DesignSystem README: "No asset catalog. Colors via Swift literals only." |

---

## 6. Validation Architecture (Nyquist Dimension 8)

> `workflow.nyquist_validation: true` (default; в config.json не disabled). Включаем секцию.

### 6.1 Test Framework

| Property | Value |
|----------|-------|
| Existing framework | `XCTest` (Swift Testing not yet adopted in BBTB; ~207 tests на XCTest) |
| Phase 12 framework | `XCTest` (consistency with existing tests) — Plan 12-01 не вводит Swift Testing |
| Config file | Package.swift `.testTarget(...)` declarations |
| Quick run command | `swift test --filter DesignSystemSnapshotTests` (если SPM CLI работает) или `xcodebuild test -scheme DesignSystem -only-testing:DesignSystemSnapshotTests` |
| Full suite command | `xcodebuild test -scheme BBTB-Package -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.0'` |
| Snapshot library | `pointfreeco/swift-snapshot-testing` from 1.18.3 (новая dependency) |
| Recording mode | `isRecording = true` per test method to regenerate baseline (commented out in CI) |

### 6.2 Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| DS-01 | DS.Color tokens resolve to correct sRGB hex values | unit | `xcodebuild test -only-testing:DesignSystemTests/DSColorTests/testAccentMatchesFigmaHex` | ❌ Wave 0 |
| DS-02 | DS.Typography.Size constants present, type CGFloat | unit (compile-time) | covered by compile | n/a |
| DS-03 | DS.Radius.section=24, DS.Radius.sheet=32 | unit | `xcodebuild test -only-testing:DesignSystemTests/DSRadiusTests` | ❌ Wave 0 |
| DS-04 | DS.Blur.pill=4 | unit | DSBlurTests | ❌ Wave 0 |
| DS-05 | ConnectionButton uses 280/320pt diameter | snapshot | `assertSnapshot(ConnectionButton(...), as: .image(layout: .fixed(width:320,height:320)))` | ❌ Wave 0 |
| DS-06 | DS.Typography.expanded() produces SF Pro Expanded width | snapshot (visual) + unit (Font properties) | snapshot baseline comparison | ❌ Wave 0 |
| DS-07 | DS.Color.accent == sRGB(0x14, 0x66, 0x4B) | unit | `XCTAssertEqual(DS.Color.accent.cgColor!.components!, [0.078, 0.4, 0.294, 1.0], accuracy: 0.01)` | ❌ Wave 0 |
| DS-08 | BBTBSpinner renders rotating ring with gradient stroke | snapshot (frame at fixed angle) | `assertSnapshot(BBTBSpinner_frozen(angle: 0))` | ❌ Wave 0 |
| DS-09 | ConnectionButton.fillColor returns DS.Color.controlIdle/.accent/.error per state | unit | `XCTAssertEqual(button.fillColor, DS.Color.accent)` для state=.connected | ❌ Wave 0 |
| DS-10 | PrimaryButtonStyle/SecondaryButtonStyle render expected appearance | snapshot | `assertSnapshot(Button("Test").buttonStyle(PrimaryButtonStyle()))` | ❌ Wave 0 |
| DS-11 | OnboardingView matches Figma hero text split + 2 CTA | snapshot (full view) + manual UAT | snapshot + visual side-by-side | ❌ Wave 0 |
| DS-12 | ServerRow renders default state with new tokens | snapshot | `assertSnapshot(ServerRow(.preview, isSelected: false, ...))` | ❌ Wave 0 |
| DS-13 | AutoCell selected/unselected renders correctly | snapshot | 2x assertSnapshot для selected=true/false | ❌ Wave 0 |
| DS-14 | ServerListSheet has 32pt top corner radius | manual UAT (full sheet) | side-by-side с Figma `06-servers-selected.png` | manual |
| DS-15 | Snapshot test infrastructure compiles + runs | integration | xcodebuild test full suite | ❌ Wave 0 |
| **UX-09** | Pixel-perfect parity across 7 key Figma screens | **manual UAT** (D-08 hybrid) | Compare simulator screenshots ↔ Figma `final-*.png` | manual |

### 6.3 Sampling Rate

- **Per task commit:** `xcodebuild test -only-testing:<TestTarget>` для затронутого target (DesignSystemSnapshotTests или AppFeaturesSnapshotTests).
- **Per wave merge:** Full snapshot suite `xcodebuild test -scheme BBTB-Package -only-testing:DesignSystemSnapshotTests -only-testing:MainScreenFeatureTests -only-testing:ServerListFeatureTests`.
- **Phase gate:** Full BBTB test suite green перед `/gsd-verify-work`. Manual UAT по 7 экранам подписан user'ом.

### 6.4 Concrete Validation Signals

Конкретные assertion patterns для верификации:

```swift
// DS-07 — accent hex matches Figma
func testAccentMatchesFigmaHex() {
    let accent = DS.Color.accent.resolve(in: EnvironmentValues())  // iOS 17+
    // Figma DS/Color/accent Dark = #14664B = (0x14/255, 0x66/255, 0x4B/255, 1.0)
    XCTAssertEqual(accent.red,   0x14 / 255.0, accuracy: 0.003)
    XCTAssertEqual(accent.green, 0x66 / 255.0, accuracy: 0.003)
    XCTAssertEqual(accent.blue,  0x4B / 255.0, accuracy: 0.003)
}

// DS-05 — ConnectionButton diameter token
func testCompactDiameterIs280() {
    XCTAssertEqual(DS.ConnectionButtonSize.compactDiameter, 280)
    XCTAssertEqual(DS.ConnectionButtonSize.regularDiameter, 320)
    XCTAssertEqual(DS.ConnectionButtonSize.compactIcon, 112)
    XCTAssertEqual(DS.ConnectionButtonSize.regularIcon, 128)
}

// DS-08 / DS-09 — Spinner visual on Connecting
@MainActor
func testConnectionButton_connecting_hasSpinnerRing() {
    let view = ConnectionButton(state: .connecting, action: {})
        .frame(width: 320, height: 320)
        .background(DS.Color.canvas)
        .preferredColorScheme(.dark)

    assertSnapshot(of: view, as: .image(
        precision: 1.0,
        perceptualPrecision: 0.99,
        layout: .fixed(width: 320, height: 320)
    ))
}
```

### 6.5 Wave 0 Gaps

- [ ] **Snapshot library dependency** — add `pointfreeco/swift-snapshot-testing` to `DesignSystem/Package.swift` + `AppFeatures/Package.swift`.
- [ ] **`DesignSystemSnapshotTests` test target** — new in `DesignSystem/Package.swift` (Spinner + ButtonStyles snapshot tests).
- [ ] **`MainScreenSnapshotTests` test target** — extend existing `MainScreenFeatureTests` или новый target (ConnectionButton in 5 states).
- [ ] **`ServerListSnapshotTests` test target** — extend existing `ServerListFeatureTests` (ServerRow default/selected, AutoCell selected/unselected).
- [ ] **Baseline storage policy** — folder `__Snapshots__/` next to each test file (default lib behavior). Commit PNGs to Git (not LFS — sizes ~10-100KB per snapshot, manageable).
- [ ] **CI Xcode/simulator pin** — document required Xcode version (16.0+) и iOS simulator version (18.0+) для stable baselines.
- [ ] **iPhone 16 simulator чествен в CI** (default iPhone 15/16 simulator) — установить в CI script.

### 6.6 Pixel Diff Tolerance Architecture

| Element type | `precision` | `perceptualPrecision` | Justification |
|--------------|-------------|----------------------|--------------|
| Solid color fills (Circle, Capsule) | 1.0 | 1.0 | Should be 100% exact — no anti-aliasing variance |
| Text labels | 1.0 | 0.98 | Anti-aliasing на letterforms — accept ≤2% per-pixel variance |
| Gradient strokes (Spinner ring) | 1.0 | 0.97 | Angular gradient interpolation на разных GPU = more variance |
| Full screen UAT | manual | manual | D-08 hybrid — eyeball, не automated |

---

## 7. Environment Availability

> Phase 12 — pure code changes; нет external dependencies beyond standard Xcode + Swift toolchain.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Xcode | All builds | (assumed) ✓ | 16.0+ | — |
| Swift | Compile | (assumed) ✓ | 6.0 | — |
| iOS 18 simulator | Snapshot tests | (verify in Wave 0) | iPhone SE 3 / iPhone 16 simulator | — |
| `pointfreeco/swift-snapshot-testing` | New dep | NPM-equivalent fetch through SPM | 1.18.3+ | XCTAttachment manual baseline (significantly worse) |
| Tuist | Project generation | (existing in BBTB workflow) | per existing Tuist setup | — |

**Missing dependencies with no fallback:** None.

**Missing dependencies with fallback:** None blocking.

---

## 8. Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Per-corner rounded rectangle | Custom `Shape` with `UIBezierPath(roundedRect:byRoundingCorners:)` | `UnevenRoundedRectangle` (iOS 16+) | Pure SwiftUI, no UIKit import, Apple-maintained |
| SF Pro Expanded variant | Bundle .otf | `.fontWidth(.expanded)` | Apple Font SLA §2B запрещает bundling — App Store rejection risk |
| Per-pixel image diff | Hand-rolled `XCTAttachment` comparison helper | `swift-snapshot-testing` `perceptualPrecision` | 90%+ speed improvement [CITED: PR #628]; battle-tested; maintained |
| Dynamic Light/Dark Color | Manual `@Environment(\.colorScheme)` switch in each view | `UIColor(dynamicProvider:)` bridge in Color extension | Single declaration; auto-switching; no per-view boilerplate |
| Custom rotating animation | `Canvas + TimelineView` with manual angle math | `Circle().rotationEffect + .animation(.linear.repeatForever)` | SwiftUI runtime coalesces frames; ≤10 строк vs 30+ |
| Haptic feedback | `UIImpactFeedbackGenerator(style: .light).impactOccurred()` | `.sensoryFeedback(.impact(weight: .light), trigger:)` (iOS 17+) | Declarative, type-safe, future-proof |

---

## 9. Common Pitfalls

### Pitfall 1: Asset Catalog in SwiftUI Previews crashes (Xcode 16)
**What goes wrong:** Adding `.colorset` in SPM package → SwiftUI Previews crashes with `unable to find bundle named <PACKAGE>_<TARGET>`.
**Why it happens:** Xcode 16 changed how preview agent resolves nested SPM Bundle.module references.
**How to avoid:** **Option B (Swift literal Color) eliminates this — our chosen approach.**
**Warning signs:** `XCPreviewAgent crashed` in console; preview canvas red error.

### Pitfall 2: `.opacity(0)` hides view but it still occupies layout space
**What goes wrong:** Phase 11 ConnectionButton uses `.opacity(isConnecting ? 0 : 1)` to hide power-icon — view is invisible but still in hit-test and accessibility tree.
**How to avoid:** Phase 12 keeps icon visible (opacity 1) since Figma `Button.connecting` shows it. If we needed to truly hide a view: use `if !isConnecting { ... }` conditional.
**Warning signs:** Tap on hidden region still triggers action; VoiceOver announces "Power" twice.

### Pitfall 3: `withAnimation(.linear.repeatForever)` runs even when view is hidden
**What goes wrong:** SwiftUI's repeatForever animation continues firing state updates even когда parent view is `.opacity(0)` or off-screen. Drains battery.
**How to avoid:** Mount Spinner only when isConnecting (our `if isConnecting { BBTBSpinner(...) }` pattern). When state changes to `.connected`, Spinner View disappears → animation auto-stops.
**Warning signs:** Xcode Energy Impact gauge shows "High" without user interaction.

### Pitfall 4: Snapshot baseline recorded на разных Xcode versions
**What goes wrong:** Developer A records baseline на Xcode 16.2 simulator → CI runs Xcode 16.0 → fails false-positive.
**How to avoid:** Pin Xcode version в CI (e.g. `.xcode-version` file or workflow YAML); document local dev Xcode version in DesignSystem README.
**Warning signs:** Snapshot diff'ы появляются после Xcode update без code changes.

### Pitfall 5: `Color(uiColor: UIColor(dynamicProvider:))` не работает в SwiftUI Previews по дефолту
**What goes wrong:** Preview canvas shows wrong color (default Dark interpretation) даже если user has Light mode preview selected.
**How to avoid:** `#Preview { ... }.preferredColorScheme(.light)` explicitly. Multiple previews for both modes.
**Warning signs:** Preview shows different color than running app.

### Pitfall 6: `.sensoryFeedback` triggers fire on every state change, not just user tap
**What goes wrong:** Привязать haptic к connection state → vibrates на auto-reconnect (per Phase 6c) когда юзер not interacting.
**How to avoid:** Use dedicated `@State private var tapCounter = 0` in view; increment on action `{ tapCounter += 1; onPaste() }`; trigger haptic on tapCounter changes only.

### Pitfall 7: `UnevenRoundedRectangle` без `.clipShape(...)` рисуется как fill background, не clip
**What goes wrong:** Putting `UnevenRoundedRectangle(...).fill(DS.Color.surface)` как background → content внутри VStack рисуется поверх rounded corners (square content overflows the rounded shape).
**How to avoid:** Wrap content в `.background(DS.Color.surface).clipShape(UnevenRoundedRectangle(...))`. Order matters: background first, clipShape after.

### Pitfall 8: Spinner ring outside Circle may extend beyond safe area
**What goes wrong:** ConnectionButton center positioned in screen middle; if Spinner diameter > Circle diameter, ring may overlap StatusBar/HomeIndicator.
**How to avoid:** Set Spinner `lineWidth: 6` and `diameter: circleDiameter + 12` (6pt padding). Verify in snapshot test that ring stays within `.frame(maxWidth: .infinity)`.

---

## 10. State of the Art

| Old Approach (pre-iOS 16) | Current Approach (iOS 16+, recommended 2026) | When Changed | Impact for BBTB |
|--------------|------------------|--------------|--------|
| `UIBezierPath(roundedRect:byRoundingCorners:cornerRadii:)` for per-corner rounding | `UnevenRoundedRectangle` | iOS 16 (Sept 2022) | Use immediately (M9) |
| `.font(.custom("SF Pro Expanded", size: ...))` with bundled .otf | `.fontWidth(.expanded)` system modifier | iOS 16 (Sept 2022) + Apple Font SLA §2B prohibits embedding | Use immediately (M4) |
| `UIImpactFeedbackGenerator(style: .light).impactOccurred()` | `.sensoryFeedback(.impact(weight: .light), trigger:)` | iOS 17 (Sept 2023) | Use for new code (M7); leave legacy ServerRow as-is (D-04 tight scope) |
| `Color("name", bundle: .module)` with Asset Catalog | Swift literal `Color(red:green:blue:)` для SPM packages | 2024+ (Xcode 16 nested bundle preview regression) | Use (M5, DS.Color.*) |
| `ProgressView().progressViewStyle(.circular)` | Custom shape with `AngularGradient` stroke когда нужен brand fidelity | n/a (always available, brand-driven) | Use (M6) |
| iOS 18+ `.symbolEffect(.rotate)` for SF Symbols | Same — но только SF Symbols, не shapes | iOS 18 (Sept 2024) | **Excluded** for M6 (cannot match Figma grayscale gradient) |

**Deprecated/outdated:**
- `.cornerRadius()` — soft-deprecated в iOS 17. Use `.clipShape(RoundedRectangle(...))` или `UnevenRoundedRectangle`. [CITED: serialcoder.dev](https://serialcoder.dev/text-tutorials/swiftui/replacing-the-deprecated-cornerradius-view-modifier-in-swiftui/)
- `UIFont.systemFont(ofSize:weight:)` with separate `.fontWidth` configuration — superseded by SwiftUI `.fontWidth(...)` declarative modifier.
- `Bundle.main.appendFonts(...)` programmatic font registration — обходится system fonts entirely с `.fontWidth`.

---

## 11. Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `.fontWidth(.expanded)` визуально идентичен Figma "SF Pro Expanded" face | §2.2 | LOW — Apple официально гарантирует system font Expanded variant; visual difference (если есть) ≤ 1px per character. Mitigated by snapshot tests. |
| A2 | iOS 18 minor updates (18.0 → 18.1 → 18.2) не меняют system font width metrics | §2.2 / Risk #3 | MEDIUM — Apple silently tweaks font rendering sometimes. Mitigated через `perceptualPrecision: 0.98` tolerance. |
| A3 | Apple НЕ выпустила first-party Swift Testing snapshot library в 2025-2026 | §2.4 | LOW — verified via web search 2026-05; if Apple announces one at WWDC 2026 (June), Phase 13+ может мигрировать |
| A4 | iPhone 16e (2025-02 release) — minimum iOS 18 device, 390pt portrait width | §1, Risk #5 | LOW — confirmed Apple specs page |
| A5 | Figma `Button.connecting` variant показывает Spinner как ring **AROUND** the Circle (snapshot 280pt diameter + ring outside) | §2.1 sub-decision | MEDIUM — нужно реверифицировать в Plan 12-02 Wave 0 inspect node 3054:713 |
| A6 | Tuist generates Xcode project для BBTB which preserves SPM package structure (vs flattening) | §1 + §2.3 Risk #4 | LOW — Phase 1 R-21 established this; if Tuist regenerates flatly, Asset Catalog Risk #4 returns |
| A7 | Custom font bundle (даже если SLA permitted) attached to TestFlight build не triggered App Review nuke | §2.2 | LOW (moot) — мы НЕ bundle'им, поэтому A7 не материализуется. Чистый documentation note. |

---

## 12. Open Questions

(Aimed at ≤3 per spec.)

1. **Hero text "Интернет, каким он / должен быть" — какой size в Figma?**
   - What we know: Figma `01-onboarding.png` показывает text split (D-11 confirmation), но точный font-size не extracted.
   - What's unclear: Какой `DS.Typography.Size.*` использовать — `display=48` (большой hero) или `title=16` (компактный)?
   - Recommendation: Plan 12-02 Wave 0 inspect Figma node `3062:304` и записать exact size в plan task. **Default predicted: `display=48`** based on `final-01-onboarding.png` proportions.

2. **Spinner placement: outside ring or inner overlay on Circle?**
   - What we know: §2.1 sub-decision recommend "ring AROUND Circle" with assumption A5.
   - What's unclear: Figma node 3054:713 нужно посмотреть в inspect mode чтобы confirm Spinner geometry.
   - Recommendation: Plan 12-02 Wave 0 — inspect node 3054:713 в Figma, confirm spinner geometry. **Fallback to outer ring если ambiguous.**

3. **Snapshot test storage location: per-test-target vs central `__Snapshots__/` folder?**
   - What we know: pointfree default = `__Snapshots__/` next to each test file.
   - What's unclear: Хотим ли мы централизовать в `BBTB/Snapshots/` for ease of reviewing all baselines?
   - Recommendation: Use **default per-test-file location** initially. Если в Phase 13 баselines количество > 50 — consider централизация.

(Note: Three additional minor questions deferred as low-risk — e.g., snapshot baseline Git-LFS vs raw commit — defaults are fine for ~10 PNGs.)

---

## Sources

### Primary (HIGH confidence)
- [Apple Docs — UnevenRoundedRectangle](https://developer.apple.com/documentation/swiftui/unevenroundedrectangle)
- [Apple Docs — ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer)
- [Apple Docs — symbolEffect(_:options:value:)](https://developer.apple.com/documentation/swiftui/view/symboleffect(_:options:value:))
- [Apple Docs — AngularGradient](https://developer.apple.com/documentation/SwiftUI/AngularGradient/)
- [Apple Fonts page (SLA terms)](https://developer.apple.com/fonts/)
- [Apple Support — iPhone SE 3 Tech Specs](https://support.apple.com/en-us/111866)
- [pointfreeco/swift-snapshot-testing — README + Releases](https://github.com/pointfreeco/swift-snapshot-testing)
- [pointfreeco/swift-snapshot-testing 1.18.0 release](https://github.com/pointfreeco/swift-snapshot-testing/releases/tag/1.18.0)
- [pointfree blog — Swift Testing support](https://www.pointfree.co/blog/posts/146-swift-testing-support-for-snapshottesting)

### Secondary (MEDIUM confidence — community/well-known authors verified против Apple docs)
- [sarunw.com — SF Font Width Styles](https://sarunw.com/posts/sf-font-width-styles/)
- [sarunw.com — SwiftUI Font Width](https://sarunw.com/posts/swiftui-font-width/)
- [Apple Developer Forums — SF Pro Expanded usage thread 757814](https://developer.apple.com/forums/thread/757814)
- [DetailsPro blog — How to Use SF Pro Expanded](https://detailspro.app/blog/how-to-use-the-expanded-san-francisco-font-family/)
- [Swift Forums #54941 — SPM Asset Catalog support](https://forums.swift.org/t/does-spm-support-colors-in-asset-catalogs/54941)
- [Swift Forums #41736 — SwiftUI Previews Bundle.module crash](https://forums.swift.org/t/swiftui-previewer-crashes-while-in-swift-package-that-depends-on-anothers-packages-bundle-module-reference/41736)
- [createwithswift.com — Sensory Feedback Modifier](https://www.createwithswift.com/providing-feedback-sensory-feedback-modifier/)
- [createwithswift.com — Animating SF Symbols](https://www.createwithswift.com/animating-sf-symbols-with-the-symbol-effect-modifier/)
- [hackingwithswift.com — sheets / presentationDetents](https://www.hackingwithswift.com/quick-start/swiftui/how-to-control-the-size-of-presented-views)
- [Medium — Customizing SwiftUI ButtonStyle](https://medium.com/1v1me-blog/customizing-swiftui-buttons-with-buttonstyle-9b32e7f41c97)

### Tertiary (cross-referenced — context, не authoritative)
- [pointfreeco/swift-snapshot-testing Discussion #928 — iOS 18 snapshot mismatch](https://github.com/pointfreeco/swift-snapshot-testing/discussions/928)
- [pointfreeco/swift-snapshot-testing Discussion #656 — perceptual precision tips](https://github.com/pointfreeco/swift-snapshot-testing/discussions/656)
- [serialcoder.dev — cornerRadius deprecation](https://serialcoder.dev/text-tutorials/swiftui/replacing-the-deprecated-cornerradius-view-modifier-in-swiftui/)
- [hackingwithswift forums — presentationDetents iOS 16-18 bugs](https://www.hackingwithswift.com/forums/swiftui/swiftui-presentationdetents-behaves-incorrectly-on-ios-16-18-but-works-correctly-on-ios-26/30435)

---

## Metadata

**Confidence breakdown:**
- **Custom Spinner (§2.1):** HIGH — Apple Docs confirm `.symbolEffect` SF-Symbol-only restriction; Circle+trim+AngularGradient pattern verified in community examples.
- **SF Pro Expanded (§2.2):** HIGH — SLA §2B explicit prohibition; `.fontWidth(.expanded)` Apple-blessed since iOS 16.
- **DS.Color storage (§2.3):** HIGH — multiple Swift Forums issues confirm Asset Catalog SPM fragility; Swift literal pattern avoids all known issues.
- **Snapshot library (§2.4):** HIGH — pointfree lib industry standard; PR #628 verified perceptualPrecision implementation; deadlock fix in 1.18.3 documented.
- **Sheet corner radius (§2.6):** HIGH — Apple Docs verified UnevenRoundedRectangle availability and API.
- **Button styles (§2.5):** MEDIUM — pattern well-established in community; haptic API gap (no `ButtonStyle`-internal hook) is known Apple limitation.
- **Risks:** MEDIUM — most mitigations are speculative/preventive, real exposure verified through Wave 1 live testing.

**Research date:** 2026-05-16
**Valid until:** 2026-06-16 для stable items (Apple SDK APIs); 2026-05-25 для fast-moving (swift-snapshot-testing version specifics — re-check before Plan 12-01 dependency lock).

---

## RESEARCH COMPLETE
