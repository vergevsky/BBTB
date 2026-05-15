# Phase 12: Swift pixel-perfect rebuild from Figma — Pattern Map

**Mapped:** 2026-05-16
**Files analyzed:** 11 (6 modified + 5 new)
**Analogs found:** 9 / 11
**Scope:** pure Swift/SwiftUI iOS pixel-perfect rebuild (M1-M10)

---

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---|---|---|---|---|
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` | **MODIFY** — design-token enum | static constants | self (existing `DS.Spacing` / `DS.Radius` enums in same file) | **exact** — extend pattern уже устоявшийся |
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/DSColor.swift` *(or in same DesignSystem.swift)* | **CREATE** — semantic color tokens | static constants (DS-01, DS-07) | `DS.Spacing` / `DS.Radius` enums in `DesignSystem.swift` (existing token shape); per-color UIColor dynamic provider — **no existing analog** (новый pattern для проекта) | **partial** — структура enum reuse, dynamic provider novel |
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift` | **CREATE** — custom ButtonStyle (DS-10) | declarative SwiftUI style | **NO analog** — в кодовой базе НЕТ ни одного `: ButtonStyle` определения; все Button используют `.buttonStyle(.borderedProminent)` / `.bordered` / `.plain` (system styles) | **NO match** → используем canonical SwiftUI ButtonStyle pattern из RESEARCH §2.5 |
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift` (`BBTBSpinner`) | **CREATE** — custom animated SwiftUI view (DS-08) | declarative + `withAnimation` | `AutoCell.bouncyCheckmark` ViewBuilder с `.symbolEffect(.bounce, value:)` (closest existing animation precedent) | **partial** — symbolEffect ≠ rotating ring, но pattern «small reusable animated view» совпадает |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` | **MODIFY** — VPN power button (DS-09, M1/M2/M3, integrate Spinner) | declarative SwiftUI view | self (current ConnectionButton — sole power-button analog в проекте) | **exact** — self-modification, не rewrite |
| `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/OnboardingView.swift` | **MODIFY** — first-launch full-screen (DS-11, M7) | declarative SwiftUI view | `EmptyStateCard.swift` (тот же 2-CTA layout, объявлен в OnboardingView заголовке как «structurally 1-в-1 EmptyStateCard») | **exact** — указано в коде ссылкой |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift` | **MODIFY** — list row (DS-12, M8) | declarative SwiftUI view | self + `AutoCell.swift` (parallel row in same sheet) | **exact** |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift` | **MODIFY** — sticky-top selector pill (DS-13, M8/M10) | declarative SwiftUI view | self + `StatusPill.swift` (Capsule pill precedent) + `LatencyBadge` (Capsule background precedent) | **exact** + supplementary patterns |
| `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListSheet.swift` | **MODIFY** — sheet container (DS-14, M9) | declarative SwiftUI view | self (height helpers + presentationDetents) — **нет существующего `UnevenRoundedRectangle.clipShape` precedent в кодовой базе** | **role-match** — UnevenRoundedRectangle новый primitive |
| `BBTB/Packages/DesignSystem/Tests/DesignSystemSnapshotTests/*.swift` (NEW test target) | **CREATE** — snapshot infrastructure (DS-15) | XCTest + `assertSnapshot` | **NO snapshot precedent в кодовой базе**; closest analog — `ConnectionButtonTests.swift` (XCTestCase + @MainActor, pure-helper testing) | **role-match (test target)** + reference Package.swift из RESEARCH §2.4 |
| `BBTB/Packages/DesignSystem/Package.swift` | **MODIFY** — add `swift-snapshot-testing` external dep + new testTarget | SwiftPM manifest | `BBTB/Packages/AppFeatures/Package.swift` (multi-target + testTarget + multiple deps — closest manifest analog) | **role-match** — first external dep в DesignSystem (currently zero) |

---

## Pattern Assignments

### MOD-1 · `BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift` (DS enum extension, DS-01..DS-07)

**Primary analog:** the existing `DS.Spacing` / `DS.Radius` / `DS.ConnectionButtonSize` enums **in this same file** (lines 11–45). Phase 12 strictly **extends** — additions only — за исключением `DS.accent` (M5 redefine) и `DS.ConnectionButtonSize` constants (M1/M2 numeric update).

**Existing token shape to mirror** (`DesignSystem.swift` lines 11–28):
```swift
/// UI-SPEC §8.1 — 8-point grid (с 4pt для tight spacing).
public enum Spacing {
    public static let xs: CGFloat = 4
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

/// UI-SPEC §8.2 — corner radius scale.
public enum Radius {
    public static let small: CGFloat = 8
    public static let card: CGFloat = 12
    public static let cardLarge: CGFloat = 16
    public static let button: CGFloat = 12
}
```

**Existing top-level forward-compat note** (`DesignSystem.swift` lines 1–6):
```swift
/// CONTEXT.md §5 default: системные SF Symbols + system colors.
/// Phase 2 W4.T1 (UI-SPEC §8) расширяет до полной шкалы tokens.
/// Phase 11 переопределит значения но сохранит names (forward-compat).
public enum DS {
    public static let accent: Color = .accentColor  // Phase 1 carry-forward
    public static let titleFont: Font = .system(.title, design: .rounded).weight(.semibold)
```

**What to copy / extend:**
- `public enum Foo { public static let bar: CGFloat = N }` shape — продолжать буквально для `Radius.section = 24`, `Radius.sheet = 32`, `Blur.pill = 4`, и для всех 7 `Typography.Size.*` constants.
- Doc-comment style with `///` + UI-SPEC pointer + phase note — продолжать (e.g. `/// Phase 12 / M9 — sheet top-corner radius. См. CODE-CONNECT.md §2.2.`).
- Forward-compat policy (Phase 11 note line 4) — `DS.accent` остаётся publicly visible, но **deprecated alias** на `DS.Color.accent` (RESEARCH §2.3 migration plan).

**Existing `DS.Typography` block to refactor** (lines 29–37):
```swift
public enum Typography {
    public static let display: Font = .system(.largeTitle, design: .monospaced).monospacedDigit()
    public static let title: Font = .system(.title3, design: .rounded).weight(.bold)
    public static let body: Font = .body
    public static let callout: Font = .system(.callout, design: .rounded)
    public static let subheadline: Font = .system(.subheadline, design: .rounded).weight(.medium)
    public static let caption: Font = .caption
}
```
→ Phase 12 (DS-06, M4) refactors internally to `.fontWidth(.expanded)` per RESEARCH §2.2 sketch. **Existing public names** (`display`, `title`, `body`, `callout`, `subheadline`, `caption`) **must remain** для обратной совместимости с 95 call sites (см. shared-pattern §1 ниже).

**Existing `DS.ConnectionButtonSize` to numerically update** (lines 39–45):
```swift
public enum ConnectionButtonSize {
    public static let compactDiameter: CGFloat = 140   // → 280 (M1)
    public static let regularDiameter: CGFloat = 160   // → 320 (M1)
    public static let compactIcon: CGFloat = 56        // → 112 (M2)
    public static let regularIcon: CGFloat = 64        // → 128 (M2)
}
```
→ pure numeric edits, names preserved.

---

### MOD-2 / NEW · `DSColor.swift` (or inline) — semantic color tokens (DS-01, DS-07)

**Closest existing analog:** `DS.Spacing` enum shape (DesignSystem.swift lines 11–19) — same structural pattern (`public enum + static let` constants under `DS` umbrella).

**No existing `Color(hex:)` extension** во всём BBTB monorepo (verified via grep `Color(hex` — 0 hits). No existing `dynamic light/dark Color` provider. Both helpers создаются с нуля.

**Pattern to follow (combined existing-enum-shape + RESEARCH §2.3 dynamic provider):**

The dynamic provider sketch (verbatim from RESEARCH §2.3 lines 326–382) is **the canonical reference**, but **structurally it mirrors** existing `DS.Spacing` pattern: `public extension DS { enum Color { public static let canvas = dynamic(...) ... } }`.

**Key snippet (RESEARCH §2.3):**
```swift
public extension DS {
    enum Color {
        public static let canvas         = dynamic(dark: 0x000000, light: 0xFFFFFF)
        public static let surface        = dynamic(dark: 0x222222, light: 0xF4F4F6)
        // ... 13 more semantic tokens из CODE-CONNECT.md §2.1 ...

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
        // + uiColor(hex:) / nsColor(hex:) bridge under #if os(iOS) / #else
    }
}
```

**`#if os(iOS) / #elseif os(macOS)` precedent** в проекте — `ConnectionButton.swift` lines 9, 57–73 (diameter / iconSize switch per platform). Тот же conditional-compile паттерн mirror в `DSColor.swift` для UIColor (iOS) vs NSColor (macOS) bridge.

---

### NEW · `ButtonStyles.swift` — `PrimaryButtonStyle` / `SecondaryButtonStyle` (DS-10, M7)

**NO existing custom `ButtonStyle` в проекте** (verified via grep `: ButtonStyle` — 0 hits). Все existing Button используют **system styles**:

**Existing precedent для composable button** (`OnboardingView.swift` lines 95–106, **Phase 12 will replace this**):
```swift
Button(L10n.onboardingPaste, action: onPaste)
    .buttonStyle(.borderedProminent)
    .controlSize(.large)
    .accessibilityIdentifier("BBTB.Onboarding.PasteButton")
    .accessibilityLabel(Text(L10n.onboardingPaste))

Button(L10n.onboardingScanQR, action: onScanQR)
    .buttonStyle(.bordered)
    .controlSize(.large)
    .accessibilityIdentifier("BBTB.Onboarding.QRButton")
    .accessibilityLabel(Text(L10n.onboardingScanQR))
```

**Same `.borderedProminent` / `.bordered` pair pattern repeated** в `EmptyStateCard.swift` lines 30–40 (5 hits в проекте — Onboarding, EmptyStateCard, QRScannerView, MinAppVersionSheet, ForceUpdateRulesButton, MenuBarContent).

**No existing `: ButtonStyle` definition to copy from** — Phase 12 устанавливает первый precedent в проекте. Используем canonical SwiftUI `struct X: ButtonStyle { makeBody(configuration:) }` pattern из RESEARCH §2.5 (verified против Apple docs).

**RESEARCH §2.5 sketch (canonical, copy verbatim into ButtonStyles.swift):**
```swift
public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DS.Typography.labelButton)
            .foregroundStyle(DS.Color.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.lg)
            .background(Capsule().fill(DS.Color.accent))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
```

**Capsule shape precedent в проекте** (используем тот же `Capsule()` shape):
- `StatusPill.swift` line 20 — `.clipShape(Capsule())`
- `LatencyBadge.swift` line 40 — `.clipShape(Capsule())`

(Используют `.clipShape(Capsule())` для bordered text. RESEARCH §2.5 ButtonStyle использует `Capsule().fill(...)` напрямую как background — функционально эквивалентно для pill-button.)

**accessibilityIdentifier convention** — preserved: `BBTB.Onboarding.PasteButton`, `BBTB.Onboarding.QRButton` (см. existing OnboardingView lines 98, 104). Identifiers ОСТАЮТСЯ — UAT tests их референсят.

---

### NEW · `Spinner.swift` (`BBTBSpinner`) — rotating ring with grayscale gradient (DS-08, M6)

**NO existing rotating animation precedent в проекте** — все existing animations используют `.symbolEffect(.bounce, value:)` на SF Symbols, не custom shapes с continuous rotation.

**Closest existing animation pattern** (`AutoCell.swift` lines 65–75, structural similarity):
```swift
@ViewBuilder
private var bouncyCheckmark: some View {
    let img = Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 24, weight: .semibold))
        .foregroundStyle(Color.accentColor)
    if #available(iOS 17.0, macOS 14.0, *) {
        img.symbolEffect(.bounce, value: isSelected)
    } else {
        img
    }
}
```
→ **Mirror only the "small encapsulated reusable view"** pattern; `.symbolEffect` НЕ applicable to a `Circle().trim` shape (RESEARCH §2.1 Option C dismissed).

**Same symbol-effect repeats** в `ConnectionButton.swift` line 26 — `.symbolEffect(.bounce, value: state)`.

**Canonical implementation** (RESEARCH §2.1 Option B, lines 173–219; verbatim sketch):
```swift
public struct BBTBSpinner: View {
    public var diameter: CGFloat = 280
    public var lineWidth: CGFloat = 6
    public var speed: Double = 1.2

    @State private var angle: Double = 0

    public init(diameter: CGFloat = 280, lineWidth: CGFloat = 6, speed: Double = 1.2) {
        self.diameter = diameter; self.lineWidth = lineWidth; self.speed = speed
    }

    public var body: some View {
        Circle()
            .trim(from: 0, to: 0.85)
            .stroke(
                AngularGradient(
                    colors: [DS.Color.iconPrimary, DS.Color.iconMuted,
                             DS.Color.iconSecondary, Color.clear],
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

**Reduce-Motion fallback** (UI-SPEC §2.2 / §3.8) — добавить `@Environment(\.accessibilityReduceMotion) private var reduceMotion` + condition внутри body. **NO existing precedent в проекте** для accessibilityReduceMotion (verified — grep 0 hits на `accessibilityReduceMotion`).

**Placement в DesignSystem package** (РЕШЕНО researcher §«Architectural Responsibility Map»): `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift` (single-file under DesignSystem source root, не в подпапке Components — DesignSystem package сейчас flat, не вводим nested directory без необходимости).

---

### MOD-3 · `ConnectionButton.swift` (DS-09, integrate BBTBSpinner, M1/M2 via numeric token update)

**Primary analog:** SELF — modify in-place. Current file is the only "main VPN power button" в проекте.

**Existing structure to preserve** (`ConnectionButton.swift` lines 17–47):
```swift
public var body: some View {
    Button(action: action) {
        ZStack {
            Circle()
                .fill(fillColor)
                .frame(width: diameter, height: diameter)
            Image(systemName: "power")
                .font(.system(size: iconSize, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: state)
                .opacity(isConnecting ? 0 : 1)
            if isConnecting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .controlSize(.large)
                    .accessibilityHidden(true)
            }
        }
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .accessibilityIdentifier("BBTB.ConnectionButton")
}
```

**`fillColor` switch to refactor** (lines 76–84) — Phase 12 swaps inline `Color.gray/.orange/.accentColor/.red` to semantic DS tokens (M3):
```swift
private var fillColor: Color {
    switch state {
    case .empty: return .gray
    case .idle: return Color(white: 0.55)
    case .connecting: return .orange
    case .connected: return .accentColor
    case .error: return Color.red.opacity(0.85)
    }
}
```
→ target shape (RESEARCH §4.5):
```swift
private var fillColor: SwiftUI.Color {
    switch state {
    case .empty, .idle:  return DS.Color.controlIdle
    case .connecting:    return DS.Color.controlIdle   // Figma: connecting = idle fill + spinner ring AROUND
    case .connected:     return DS.Color.accent
    case .error:         return DS.Color.error
    }
}
```

**`diameter` / `iconSize` switch already correct** (lines 57–74) — automatically picks up new `DS.ConnectionButtonSize.compactDiameter = 280` value when MOD-1 lands (no edit to ConnectionButton.swift needed for M1/M2).

**Preserve:**
- `accessibilityIdentifier("BBTB.ConnectionButton")` line 46 — referenced by `ConnectionButtonTests` + UAT.
- `internal var isConnecting: Bool` lines 52–55 — `@testable` access (5 existing tests).
- `disabled` computed prop lines 86–90.
- `.buttonStyle(.plain)` + `@Environment(\.horizontalSizeClass)`.

**Phase 12 visual change (RESEARCH §2.1 spinner-placement decision):**
- Remove `.opacity(isConnecting ? 0 : 1)` — power icon stays visible во время `.connecting`.
- Replace `ProgressView()` placeholder with `BBTBSpinner(diameter: diameter + 24, lineWidth: 6, speed: 1.2)` **rendered around** Circle, not over icon.

---

### MOD-4 · `OnboardingView.swift` (DS-11, M7) — onboarding rebuild

**Primary analog:** `EmptyStateCard.swift` — **explicitly cited as "structurally 1-в-1 OnboardingView"** в OnboardingView header comment (lines 21–22):

> *«Структурно — почти 1-в-1 `EmptyStateCard` (Pattern Map → exact analog), но без card-background и фиксированной ширины: занимает весь экран».*

**`EmptyStateCard.swift` excerpt to mirror** (lines 14–48):
```swift
public var body: some View {
    VStack(spacing: DS.Spacing.lg) {
        Image(systemName: "tray")
            .font(.system(size: 56))
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)

        Text(L10n.emptyTitle)
            .font(DS.Typography.title)

        Text(L10n.emptySubtitle)
            .font(DS.Typography.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        VStack(spacing: DS.Spacing.md) {
            Button(L10n.actionImportFromClipboard, action: onAddFromClipboard)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityLabel(Text(L10n.actionImportFromClipboard))

            Button(L10n.actionScanQR, action: onScanQR)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityLabel(Text(L10n.actionScanQR))
        }
    }
    .padding(DS.Spacing.xl)
    .background(
        RoundedRectangle(cornerRadius: DS.Radius.cardLarge)
            .fill(Color.secondary.opacity(0.1))
    )
    .frame(maxWidth: 360)
}
```

**Existing OnboardingView CRITICAL invariants to preserve** (header comment lines 64–67):
```text
// CRITICAL preserve (D-01/D-02/D-03):
// - Plan 03 closure logic (`.onChange(of: viewModel.state)`).
// - `BBTB.Onboarding.PasteButton` / `BBTB.Onboarding.QRButton` identifiers.
// - Точно 2 CTA (paste + QR), без file picker — file picker остаётся в
//   меню «+» главного экрана.
```

**Existing `.onChange(of:)` dismiss logic to preserve** (lines 118–133):
```swift
.onChange(of: viewModel.state) { _, newState in
    dismissIfImported(newState)
}

private func dismissIfImported(_ state: ConnectionState) {
    switch state {
    case .empty, .error:
        return
    case .idle, .connecting, .connected:
        onDismiss()
    }
}
```

**Hero text split pattern (NEW, RESEARCH §4.7) — Text concatenation:**
```swift
(Text("Интернет, каким он ")
    .foregroundStyle(DS.Color.textPrimary)
 + Text("должен быть")
    .foregroundStyle(DS.Color.accent))
    .font(DS.Typography.titleScreen)
    .multilineTextAlignment(.center)
```
**No existing `Text + Text` concatenation precedent** в проекте (verified grep — все `Text(...)` отдельны). Phase 12 устанавливает first precedent.

**Replace** `.buttonStyle(.borderedProminent)` (line 96) → `.buttonStyle(PrimaryButtonStyle())`.
**Replace** `.buttonStyle(.bordered)` (line 102) → `.buttonStyle(SecondaryButtonStyle())`.
**Add** `.sensoryFeedback(.impact(weight: .light), trigger: tapCounter)` per UI-SPEC §2.1 (iOS 17+ API; no existing precedent — Phase 12 first introduction).

---

### MOD-5 · `ServerRow.swift` (DS-12, M8) — row token tuning

**Primary analog:** SELF — modify in-place. Existing body uses DS tokens, Phase 12 swaps system colors for semantic DS.Color.

**Existing body to mirror padding/spacing pattern from** (`ServerRow.swift` lines 42–100):
```swift
public var body: some View {
    Button(action: handleTap) {
        HStack(spacing: DS.Spacing.md) {            // ← gap 12pt, matches Figma
            Text(server.countryFlag)
                .font(.system(size: 24))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name)
                    .font(DS.Typography.body)        // ← M4 will become Expanded
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(server.isSupported ? .primary : .secondary)
                // ...
            }
            Spacer()
            LatencyBadge(...)
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.accentColor)   // ← M3/M5 → DS.Color.accent
            }
            Button(action: onDetailTap) {
                Image(systemName: "chevron.right")
                    .imageScale(.small)
                    .foregroundStyle(.tertiary)          // ← M3 → DS.Color.iconSecondary or iconMuted
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DS.Spacing.lg)             // ← 16pt all-side preserved
        .padding(.vertical, DS.Spacing.md)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .opacity(rowOpacity)
    }
    .buttonStyle(.plain)
}
```

**Phase 12 changes (per CODE-CONNECT.md §1.4/§1.5):**
- `frame(minHeight: 56)` — Figma says 52pt; **verify in Wave 1 visual review** before changing (1px could throw off snapshot baselines).
- `.foregroundStyle(.primary)` / `.secondary` / `.tertiary` → `DS.Color.textPrimary` / `.textSecondary` / `.iconMuted` per `isSelected` (CODE-CONNECT.md §1.5).
- `Color.accentColor` (line 68) → `DS.Color.accent` after MOD-2 lands.
- Row background fill — currently none (transparent default); add `.background(isSelected ? DS.Color.accent : Color.clear)` to match Figma selected variant.

**Preserve:**
- `accessibilityIdentifier("BBTB.ServerListSheet.ServerRow.\(server.id.uuidString)")` line 90.
- `accessibilityElement(children: .combine)` + label/value/hint pattern lines 91–94.
- `contextMenu` swipe-actions lines 95–99.
- `handleTap()` haptic call lines 124–129 — **D-04 tight scope: НЕ migrate to `.sensoryFeedback`** (UI-SPEC §2.1 explicit pitfall).

---

### MOD-6 · `AutoCell.swift` (DS-13, M8/M10) — pill design + accent fill

**Primary analog:** SELF + supplementary pill precedents.

**Existing body** (`AutoCell.swift` lines 23–63):
```swift
public var body: some View {
    Button(action: onTap) {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 28, weight: .semibold))             // ← Figma: 20pt (M-CONNECT §1.6)
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)  // ← DS.Color.iconPrimary / iconSecondary
                .frame(width: 48, height: 48)
                .background(
                    Circle().fill(
                        isSelected
                        ? Color.accentColor.opacity(0.15)
                        : Color.secondary.opacity(0.12)
                    )
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.serverAutoTitle)
                    .font(DS.Typography.title)
                Text(L10n.serverAutoSubtitle)
                    .font(DS.Typography.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected { bouncyCheckmark }
        }
        .padding(DS.Spacing.md)
        .frame(minHeight: 72)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.cardLarge)           // ← M10: → DS.Radius.section (24pt)
                .fill(Color.secondary.opacity(0.1))                       // ← M3: → DS.Color.accent (selected) / .surfaceSunken (unselected)
        )
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("BBTB.ServerListSheet.AutoCell")
}
```

**Supplementary pill precedents in project** (for Capsule + background pattern reference):
- `StatusPill.swift` lines 14–22 — `Text(...).padding(.horizontal, DS.Spacing.lg).padding(.vertical, DS.Spacing.sm).background(...).clipShape(Capsule())` — the most established pill shape in codebase.
- `LatencyBadge.swift` lines 33–40 — same `padding + background + clipShape(Capsule())` pattern.

**Note:** AutoCell currently uses `RoundedRectangle(cornerRadius: cardLarge)` (16pt) — Phase 12 M10 swaps to `DS.Radius.section = 24pt`. **Не Capsule** (RoundedRectangle with explicit radius). Per Figma 24pt corners on a pill ~64pt tall is NOT a half-height capsule.

**Preserve:**
- `accessibilityIdentifier("BBTB.ServerListSheet.AutoCell")` line 58.
- `symbolEffect(.bounce, value: isSelected)` lines 70–74 (one of two existing animation precedents).

---

### MOD-7 · `ServerListSheet.swift` (DS-14, M9) — UnevenRoundedRectangle 32pt top corners

**Primary analog:** SELF for structural body; **NO existing `UnevenRoundedRectangle` precedent в проекте** (grep 0 hits).

**Closest existing clipShape pattern** (within the codebase — for the modifier idiom only):
- `StatusPill.swift` line 20: `.clipShape(Capsule())`
- `LatencyBadge.swift` line 40: `.clipShape(Capsule())`

**Phase 12 new pattern** (RESEARCH §2.6 sketch, lines 547–563):
```swift
NavigationStack {
    VStack(spacing: 0) {
        // ... existing content ...
    }
    .background(DS.Color.surface)
    .clipShape(
        UnevenRoundedRectangle(
            topLeadingRadius: DS.Radius.sheet,        // 32pt
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: DS.Radius.sheet,       // 32pt
            style: .continuous
        )
    )
}
```

**Existing `sheetContent` body to wrap** (`ServerListSheet.swift` lines 136–208) — apply `.background(DS.Color.surface).clipShape(UnevenRoundedRectangle(...))` to the outermost `VStack(spacing: 0)` inside `NavigationStack`, **inside** existing `.presentationDetents` / `.presentationDragIndicator` modifiers (RESEARCH Risk #2 — Wave 1 visual verify).

**Preserve:**
- `.presentationDetents(detents)` line 92.
- `.onAppear` / `.onChange` detents drivers lines 93–98 (Phase 6e Wave 2 L7 fix).
- `.presentationDragIndicator(.visible)` line 99.
- `.refreshable { await viewModel.pullToRefresh() }` line 198–200.
- `.navigationDestination(item: $viewModel.openServerDetail)` line 204.
- `accessibilityIdentifier("BBTB.ServerListSheet")` line 201.
- All 7 height-tuning constants (`headerH`, `autoCellH`, etc.) lines 52–58 — **D-04 tight scope: НЕ trogать numeric values** unless Wave 1 visual diff requires.
- 4 `static` helpers `estimatedHeight` / `computeDetents` — **referenced by `ServerListSheetHeightTests` (4 tests, 207-test invariant)**.

---

### NEW · `DesignSystemSnapshotTests/*.swift` test target (DS-15)

**NO existing snapshot test target in project** (verified: BBTB has zero SwiftUI snapshot tests; only domain `Snapshot` data tests in RulesEngine).

**Closest existing test pattern** (`ConnectionButtonTests.swift` — pure-helper unit test that **does not** import SwiftUI runtime):
```swift
// ConnectionButtonTests.swift lines 18-30

import XCTest
@testable import MainScreenFeature

@MainActor
final class ConnectionButtonTests: XCTestCase {

    /// D-05 — .connecting → isConnecting должен быть true.
    func test_isConnecting_trueWhenStateConnecting() {
        let button = ConnectionButton(state: .connecting, action: {})
        XCTAssertTrue(button.isConnecting,
                      ".connecting → isConnecting должен быть true")
    }
    // ...
}
```

**`ServerListSheetHeightTests.swift` lines 22–28** — same XCTestCase + @testable import pattern (note: NOT `@MainActor` at class level because static helpers are not main-actor isolated):
```swift
import XCTest
import SwiftUI
import VPNCore
@testable import ServerListFeature

final class ServerListSheetHeightTests: XCTestCase {
    private func makeManualSection(serverCount: Int) -> ServerListSection {
        // fixture helper
    }
    func test_estimatedHeight_emptyPool_includesEmptyCard() {
        let h = ServerListSheet.estimatedHeight(sections: [])
        XCTAssertEqual(h, 81 + 116 + 220 + 40, "Empty pool ...")
    }
}
```

**Patterns to copy:**
- File header comment block: phase reference + plan reference + UI-SPEC reference + what's NOT tested + approach note (see ConnectionButtonTests lines 1–17).
- `@MainActor` class attribute (Snapshot tests need MainActor for ImageRenderer; ConnectionButtonTests pattern verbatim).
- `@testable import DesignSystem` для access to internal helpers if needed (verbatim from ConnectionButtonTests line 19).
- `Phase X / Plan Y / Task Z / DS-N` provenance comments in each test func (ServerListSheetHeightTests precedent).
- Russian inline error messages в XCTAssert*: `"empty pool height должен включать ..."` (см. both existing test files; matches CLAUDE.md «Always giving an answer in Russian» rule extended to error messages).

**Snapshot infrastructure (NEW, RESEARCH §2.4 sketch verbatim):**
```swift
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

**Threshold mapping** for D-10 (≤2px diff): `perceptualPrecision: 0.98` for text/AA-heavy components, `0.99` for solid-fill components (UI-SPEC §5).

---

### MOD-8 · `BBTB/Packages/DesignSystem/Package.swift` (add swift-snapshot-testing dep + test target)

**Existing manifest** (8 lines, zero external deps, zero test targets):
```swift
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "DesignSystem", targets: ["DesignSystem"])],
    targets: [.target(name: "DesignSystem")]
)
```

**Primary analog for extended manifest:** `BBTB/Packages/AppFeatures/Package.swift` — closest existing example of dependencies + test target shape:

**AppFeatures excerpt for `dependencies:` array** (Package.swift lines 13–41):
```swift
dependencies: [
    .package(path: "../VPNCore"),
    .package(path: "../DesignSystem"),
    // ... 14 более path-deps ...
],
```
→ Phase 12 добавляет **URL-based** (first remote dep in project):
```swift
dependencies: [
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.18.3"),
],
```
(`from: "1.18.3"` minimum per RESEARCH Risk #6 — main-thread deadlock fix.)

**AppFeatures excerpt for `testTarget` shape** (lines 84–95):
```swift
.testTarget(
    name: "MainScreenFeatureTests",
    dependencies: ["MainScreenFeature", "SettingsFeature", "DeepLinks"],
    linkerSettings: [
        .linkedLibrary("resolv"),
        .linkedLibrary("bsm", .when(platforms: [.macOS])),
        .linkedFramework("SystemConfiguration", .when(platforms: [.macOS])),
        .linkedFramework("AppKit", .when(platforms: [.macOS])),
        .linkedFramework("UIKit", .when(platforms: [.iOS])),
    ]
),
```
→ DesignSystem snapshot test target — much simpler (no platform-specific linker frameworks needed; SnapshotTesting handles its own):
```swift
.testTarget(
    name: "DesignSystemSnapshotTests",
    dependencies: [
        "DesignSystem",
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
    ]
),
```

**Pattern**: mirror AppFeatures Package.swift commentary style — phase reference inline (e.g. `// Phase 12 / DS-15 — snapshot infrastructure for component pixel-perfect verification`).

---

## Shared Patterns

### 1. `DS.*` token consumption (apply to all 6 modified views)

**Source:** ubiquitous across `BBTB/Packages/AppFeatures/Sources/**/*.swift` — **95 call-sites** of `DS.Typography` / `DS.Spacing` / `DS.Radius` / `DS.accent` (verified via grep).

**Apply to:** all MODIFY tasks. Никогда не hardcode pt/Font/Color literals — always go through `DS.*`.

**Existing canonical examples:**
- `ServerListSheet.swift` lines 157–158: `.padding(.horizontal, DS.Spacing.lg).padding(.top, DS.Spacing.xl)`
- `EmptyStateCard.swift` line 23: `.font(DS.Typography.title)`
- `AutoCell.swift` lines 53: `RoundedRectangle(cornerRadius: DS.Radius.cardLarge)`

**Phase 12 net additions to DS.\*:** `DS.Color.*` (15 tokens), `DS.Typography.expanded(...)` helper + 9 sized presets + `DS.Typography.Size.*` (7 constants), `DS.Radius.section/.sheet`, `DS.Blur.pill`, updated `DS.ConnectionButtonSize` numerics.

### 2. `accessibilityIdentifier` — preservation discipline

**Source:** every interactive view in `BBTB/Packages/AppFeatures/Sources/**/*.swift` (19 hits, see grep output above).

**Existing identifier registry:**
- `BBTB.ConnectionButton` — ConnectionButton.swift:46
- `BBTB.MenuButton` — TopBar.swift:31, MainScreenView.swift:264
- `BBTB.AddButton` — TopBar.swift:47
- `BBTB.Onboarding.PasteButton` / `BBTB.Onboarding.QRButton` — OnboardingView.swift:98, 104
- `BBTB.ServerListSheet` / `BBTB.ServerListSheet.AutoCell` / `BBTB.ServerListSheet.ServerRow.<UUID>` — ServerListSheet.swift, AutoCell.swift, ServerRow.swift
- `BBTB.Settings.HelpRow` / `BBTB.Help.FAQ1..5` / `BBTB.HelpView` — SettingsFeature
- `BBTB.ServerDetailView` / `BBTB.ServerDetail.TransportPicker` — ServerListFeature

**Apply to:** **All 6 MODIFY tasks preserve their existing identifiers verbatim** (UAT tests + accessibility audit reference them; renaming = silent test breakage). New components (BBTBSpinner, PrimaryButton/SecondaryButton in their `ButtonStyle` consumers) inherit from their host Button identifier.

### 3. `#if os(iOS) / #elseif os(macOS)` conditional compile

**Source:** `ConnectionButton.swift` (size class diameter, lines 9, 57–73), `ServerListSheet.swift` (UIScreen + min-window, lines 81–87, 100–102), `ServerRow.swift` (UIKit haptic, lines 15–17, 124–128), `OnboardingView.swift` (macOS min-frame, lines 111–115).

**Existing canonical example** (ConnectionButton.swift lines 57–65):
```swift
private var diameter: CGFloat {
    #if os(iOS)
    return (horizontalSizeClass == .regular)
        ? DS.ConnectionButtonSize.regularDiameter
        : DS.ConnectionButtonSize.compactDiameter
    #else
    return DS.ConnectionButtonSize.regularDiameter
    #endif
}
```

**Apply to:** `DSColor.swift` dynamic provider (iOS UIColor vs macOS NSColor bridge per RESEARCH §2.3). All other Phase 12 changes are iOS-only (D-11) — но **не удалять** existing macOS branches в touched files.

### 4. SwiftUI `accessibilityHidden` / `accessibilityElement(children: .combine)` / `accessibilityLabel/Value/Hint`

**Source:** widely used; pattern formalized в ServerRow.swift lines 91–94 + AutoCell.swift lines 59–62.

**Apply to:**
- `BBTBSpinner.accessibilityHidden(true)` — ring is decorative; status spoken by parent ConnectionButton (UI-SPEC §3.2).
- ConnectionButton — preserve existing `.accessibilityIdentifier("BBTB.ConnectionButton")`; **add** `.accessibilityLabel/Value/Hint` per UI-SPEC §3.1 table (5 states).
- Power-icon `Image(systemName: "power")` — `.accessibilityHidden(true)` (UI-SPEC §3.2).
- ServerRow / AutoCell — preserve existing `.accessibilityElement(children: .combine)` + label/value/hint.

### 5. Test file header convention

**Source:** all 26 existing test files в AppFeatures/Tests.

**Canonical example** (`ConnectionButtonTests.swift` lines 1–17):
```swift
// ConnectionButtonTests.swift — Phase 11 / Plan 07 / Task 7.1 / UX-08.
//
// Тесты на pure helper `ConnectionButton.isConnecting`. View body (ProgressView
// overlay, opacity modifier на power-icon) тестируется визуально в Wave 4
// human-verify checkpoint (Task 7.4) — здесь нет ViewInspector, поэтому tap'ы
// на view-level state мы оставляем UAT'у.
//
// Подход: Alternative A (см. Plan 11-07 Task 7.1) — `isConnecting` сделан
// `internal` для @testable visibility; тесты вызывают property напрямую через
// instance, не симулируя body re-render.
//
// Что НЕ тестируется здесь и почему:
// - symbolEffect / accessibilityIdentifier / disabled — compile-time literals
//   и Apple-managed modifiers; regression caught manual UAT.
// - ProgressView visibility в дереве — нет ViewInspector, нет XCTViewController.
// - ARC retain cycle от action closure — out of scope D-05.
```

**Apply to:** all NEW snapshot test files (DS-15 target) — same `// FileName.swift — Phase 12 / Plan 12-01/02 / DS-N.` header + bullet "what's tested / what's NOT / why" block, in Russian.

---

## No Analog Found

Files with no close existing match (planner: use RESEARCH §2.x sketches as authoritative reference).

| File | Role | Reason | Authoritative reference |
|---|---|---|---|
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift` (PrimaryButtonStyle / SecondaryButtonStyle) | custom ButtonStyle | **NO `: ButtonStyle` definition exists in BBTB monorepo** (grep verified) — Phase 12 first precedent | RESEARCH §2.5 + §4.4 (verbatim sketch) |
| `BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift` (BBTBSpinner) | rotating ring with AngularGradient | **NO `repeatForever` / `AngularGradient` / `trim(from:to:)` precedent** in codebase | RESEARCH §2.1 + §4.3 (verbatim sketch) |
| `BBTB/Packages/DesignSystem/Tests/DesignSystemSnapshotTests/*` test target | snapshot-testing infrastructure | **NO SwiftUI snapshot tests exist anywhere in project** (only domain `Snapshot` data structs в RulesEngine, unrelated) | RESEARCH §2.4 + §6 (full setup) |
| Text concatenation `Text(...) + Text(...)` with mixed `.foregroundStyle` (Onboarding hero split) | inline mixed-color text | **NO precedent in codebase** (grep — all `Text(...)` standalone) | RESEARCH §4.7 (sketch) |
| `UnevenRoundedRectangle.clipShape` on sheet content (M9) | sheet rounded top corners | **NO `UnevenRoundedRectangle` usage в codebase** | RESEARCH §2.6 + §4.6 |
| `Color(hex:)` / hex-int → Color bridge (DS.Color literal storage) | color conversion helper | **NO existing `Color(hex:)` extension or hex-utility** | RESEARCH §2.3 (`uiColor(hex:)` / `nsColor(hex:)` helpers inline в DS.Color enum) |
| `.sensoryFeedback(.impact(weight: .light), trigger:)` (iOS 17+ haptic API) | modern haptic feedback | **NO precedent** — existing haptic uses legacy `UIImpactFeedbackGenerator(style: .light)` в `ServerRow.handleTap()` line 126 (do NOT migrate per D-04) | UI-SPEC §2.1 + §2.3 + RESEARCH §2.5 (haptic note) |
| `@Environment(\.accessibilityReduceMotion)` reduce-motion gate | accessibility | **NO precedent** in codebase | UI-SPEC §2.7 + §3.8 |

---

## Metadata

**Analog search scope:**
- `BBTB/Packages/DesignSystem/Sources/**` (1 file: DesignSystem.swift)
- `BBTB/Packages/AppFeatures/Sources/**` (28 .swift files across 4 modules)
- `BBTB/Packages/AppFeatures/Tests/**` (26 test files across 3 test targets)
- `BBTB/Packages/*/Package.swift` (16 manifests scanned)
- Greps performed for: `: ButtonStyle`, `Color(hex`, `snapshot` (Swift), `repeatForever`, `AngularGradient`, `trim(from:`, `accessibilityIdentifier`, `UnevenRoundedRectangle`, `clipShape`, `borderedProminent`, `borderedProminent\|.bordered`, `fontWidth`, `symbolEffect`, `withAnimation`, `accessibilityReduceMotion`, `Text(.*) + Text(`, `DS.Typography`, `DS.Spacing`, `DS.Radius`, `import DesignSystem`.

**Key codebase findings (relevant to Phase 12):**
1. **Zero custom `ButtonStyle`** — all Button instances use system `.borderedProminent/.bordered/.plain` (8 occurrences). Phase 12 is the **first** custom ButtonStyle precedent.
2. **Zero `Color(hex:)` extension** — Phase 12 introduces hex-int → Color via inline `uiColor(hex:)` helper in `DS.Color` enum (RESEARCH §2.3 pattern).
3. **Zero SwiftUI snapshot tests** — all 26 existing tests are XCTestCase on **pure helpers** (no ViewInspector, no view-tree assertions). Snapshot test target is greenfield infrastructure.
4. **Zero rotating animations** — only `.symbolEffect(.bounce, value:)` on SF Symbols (2 occurrences in AutoCell + ConnectionButton). `withAnimation(.repeatForever)` / `AngularGradient` / `Circle().trim` are net-new patterns.
5. **207+ existing tests reference `BBTB.ConnectionButton` identifier** + 18 other `BBTB.*` identifiers — preserve discipline is **non-negotiable** for Phase 12.
6. **`#if os(iOS)/macOS` conditional compile** — established pattern (4 files); apply to new DSColor dynamic provider.
7. **DS token consumption** — 95 call-sites of `DS.Typography/.Spacing/.Radius/.accent` across AppFeatures. Phase 12 extends `DS` namespace без breaking changes (additions only + numeric updates to ConnectionButtonSize + `DS.accent` deprecated alias to `DS.Color.accent`).

**Pattern extraction date:** 2026-05-16
