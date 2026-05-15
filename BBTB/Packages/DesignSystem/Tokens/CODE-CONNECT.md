# Code Connect Mapping — BBTB v3

**Figma file:** `tI6DFQDU6PdOSmd19BGXqg` (BBTB v3)
**Generated:** 2026-05-16
**Status:** Documentation mapping (Phase 11). Real Code Connect SDK publication deferred until Phase 12 pixel-perfect Swift rebuild lands.

## Purpose

Bridges Figma components and Swift views with explicit mapping of:
1. **Figma component ID** → **Swift file + struct name**
2. **Figma variant value** → **Swift enum case**
3. **Figma component property** → **Swift initializer parameter**
4. **Figma token (variable)** → **Swift `DS.*` constant**

This is the **source of truth** for Phase 12 Swift pixel-perfect rebuild and the basis for actual Figma Code Connect SDK publication when ready.

---

## 1. Component mappings

### 1.1 `Button` (component set, 3054:712) → `ConnectionButton.swift`

**Swift file:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift`

```swift
public struct ConnectionButton: View {
    public let state: ConnectionState
    public let action: () -> Void
}
```

**Variant mapping (Figma `Property 1` → Swift `state`):**

| Figma variant | Figma node ID | Swift `ConnectionState` case | Visual |
|---|---|---|---|
| `disconnected` | `3054:711` | `.empty` OR `.idle` | dark grey circle, white "СТАРТ" |
| `connecting` | `3054:713` | `.connecting` | ring spinner, "подключение" |
| `error` | `3054:733` | `.error(message:)` | dark red circle, "ошибка" |
| `connected` | `3054:736` | `.connected(since:)` | accent green circle, "подключен" + timer |

**Note:** Figma `disconnected` collapses Swift `.empty` and `.idle` into one visual. Both render as the dark grey "СТАРТ" button.

**Token bindings (Figma → Swift):**

| Figma element | Figma value | Swift binding |
|---|---|---|
| Circle diameter | 280×280 | `DS.ConnectionButtonSize.compactDiameter` (currently 140 — **needs update to 280**) |
| Icon font size | 112 | `DS.ConnectionButtonSize.compactIcon` (currently 56 — **needs update to 112**) |
| Idle fill | `#222222` | `DS.Color.controlIdle` (new — not yet in Swift) |
| Connected fill | `#14664B` | `DS.Color.accent` (new — currently uses `.accentColor`) |
| Error fill | `#661414` | `DS.Color.error` (new — currently uses `Color.red.opacity(0.85)`) |
| СТАРТ font | SF Pro Expanded Semibold 16 | `Typography/Title/Screen` style |
| Connection status font | SF Pro Expanded Semibold 16 | `Connection status` style |
| Timer font | SF Pro Expanded Medium 48 | `Typography/Display/Timer` style |
| Inner text white | `#FFFFFF` | `DS.Color.textPrimary` |

---

### 1.2 `Button_BG` (component set, 3055:155) — internal layer of `Button`

**Swift file:** N/A — fused into `ConnectionButton` body (Circle fill switch).

Used inside Figma `Button` variants as nested instance. Swift implementation uses inline `Circle().fill(fillColor)` switch on `ConnectionState`.

**Variant mapping (same as 1.1):** `disconnected`/`connecting`/`error`/`connected`.

**Note for Phase 12:** Swift `fillColor` switch should bind to `DS.Color.controlIdle`/`accent`/`error` semantic tokens instead of inline `Color` values.

---

### 1.3 `Spinner` (component set, 3057:167) — 4-frame ring animation

**Swift file:** `BBTB/Packages/AppFeatures/Sources/MainScreenFeature/ConnectionButton.swift` (currently uses `ProgressView` placeholder per Phase 11 UX-08 D-05)

**Variant mapping (Figma `Property 1` → animation frame):**

| Figma variant | Figma node ID | Phase (degrees) |
|---|---|---|
| `frame1` | `3057:166` | 0° (start) |
| `frame2` | `3057:168` | 90° |
| `frame3` | `3057:170` | 180° |
| `frame4` | `3057:172` | 270° |

**Phase 12 implementation:** Replace `ProgressView().circular.tint(.white).controlSize(.large)` placeholder with custom rotating ring matching Figma frames. Options:
- (A) `.symbolEffect(.rotate, options: .repeating)` on a `Image(systemName: "circle.dotted")`
- (B) Custom `Canvas { }` view drawing arc gradient and rotating via `TimelineView`
- (C) Animated SF Symbol (iOS 18+)

**Token bindings:** ring stroke colors use grayscale gradient (light at top → dark at bottom transition). Bind to `DS.Color.iconMuted` / `DS.Color.iconSecondary` for grayscale stops.

---

### 1.4 `ServerRow` (component, 3071:219) → `ServerRow.swift`

**Swift file:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerRow.swift`

```swift
public struct ServerRow: View {
    public let server: ServerConfig
    public let isSelected: Bool
    public let pingState: PingState
    public let onTap: () -> Void
    public let onDelete: () -> Void
    public let onDetailTap: () -> Void
}
```

**Visual mapping (Figma default state, `isSelected: false`):**

| Figma element | Figma value | Swift binding |
|---|---|---|
| Row height | 52pt | hardcoded? — check ServerRow.body |
| Padding (all sides) | 16pt | `DS.Spacing.lg` |
| Stroke (divider) | `#333333` 1pt | `DS.Color.divider` (currently uses `Divider()` or stroke shape) |
| Globe icon (Phosphor `GlobeHemisphereWest`) | 20×20, fill `#808080` | `DS.Color.iconSecondary` + 20pt size |
| Server name text | SF Pro Expanded Regular 12, white | `Typography/Body/Default` + `DS.Color.textPrimary` |
| Latency badge "20 мс" | SF Pro Expanded Regular 9, `#808080` | `Typography/Body/Caption` + `DS.Color.textSecondary` |
| CaretRight chevron | 18×18, `#808080` | `DS.Color.iconSecondary` |

---

### 1.5 `ServerRow Selected` (component, 3071:227) → `ServerRow.swift` (variant)

**Swift file:** Same as 1.4 with `isSelected: true`.

**Visual diff vs `ServerRow`:**

| Figma element | default | selected | Swift binding |
|---|---|---|---|
| Row fill | transparent | `#14664B` (accent green) | `DS.Color.accent` |
| Globe icon | `#808080` | `#CCCCCC` | `DS.Color.iconMuted` |
| Latency text | `#808080` | `#CCCCCC` | `DS.Color.iconMuted` |
| CaretRight | `#808080` | `#CCCCCC` | `DS.Color.iconMuted` |

**Note:** Server name text stays white in both states. Only secondary elements lighten when selected.

---

### 1.6 Auto cell (Figma `Авто` frame, 3064:1316) → `AutoCell.swift`

**Swift file:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/AutoCell.swift`

```swift
public struct AutoCell: View {
    public let isSelected: Bool
    public let onTap: () -> Void
}
```

**Visual mapping (selected variant, `isSelected: true` — green pill):**

| Figma element | Figma value | Swift binding |
|---|---|---|
| Pill background | `#14664B` accent green | `DS.Color.accent` |
| Corner radius | 24pt | `DS.Radius.section` |
| Lightning icon | 20×20, white | `DS.Color.iconPrimary` |
| Label "Автовыбор по скорости" | SF Pro Expanded Semibold 12, white | `Typography/Title/Section` + `DS.Color.textPrimary` |

**Variants:** Figma has both default (selected accent green) and unselected (presumably dark grey) — need to inspect both. Current Swift renders selected with `Color.accentColor`, unselected with `Color.secondary.opacity(0.12)`. **Phase 12: bind both states to `DS.Color.accent` / `DS.Color.surfaceSunken`.**

---

### 1.7 Screen layouts

| Figma node | Figma name | Swift file |
|---|---|---|
| `3062:304` | `1. Onboarding Screen` | `OnboardingView.swift` |
| `3043:341` | `2. Home Screen — Disconnected` | `MainScreenView.swift` (state=idle) |
| `3047:538` | `2. Home Screen — Connecting` | `MainScreenView.swift` (state=connecting) |
| `3047:568` | `2. Home Screen — Error` | `MainScreenView.swift` (state=error) |
| `3047:598` | `2. Home Screen — Connected` | `MainScreenView.swift` (state=connected) |
| `3064:350` | `3. Servers — Selected server` | `ServerListSheet.swift` (selected mode) |
| `3064:1579` | `3. Servers — Auto` | `ServerListSheet.swift` (auto mode) |

**Common pattern:** all screens have `ScreenContent > TopBar + ConnectionButton + ServerStatusLabel + Bezel/StatusBar/HomeIndicator (device chrome from external lib)`.

---

## 2. Token mappings

### 2.1 Colors (`DS/Color/*` → `DS.Color.*`)

When Swift gets refactored in Phase 12, replace SwiftUI system colors with explicit DS tokens.

| Figma path | Hex (Dark) | Hex (Light) | Swift target |
|---|---|---|---|
| `DS/Color/canvas` | `#000000` | `#FFFFFF` | `DS.Color.canvas` |
| `DS/Color/surface` | `#222222` | `#F4F4F6` | `DS.Color.surface` |
| `DS/Color/surfaceSunken` | `#1A1A1A` | `#ECEDEF` | `DS.Color.surfaceSunken` |
| `DS/Color/surfaceHeader` | `#333333` | `#E0E0E5` | `DS.Color.surfaceHeader` |
| `DS/Color/divider` | `#333333` | `#D8D8DD` | `DS.Color.divider` |
| `DS/Color/controlIdle` | `#222222` | `#E8E8EC` | `DS.Color.controlIdle` |
| `DS/Color/accent` | `#14664B` | `#14664B` | `DS.Color.accent` |
| `DS/Color/error` | `#661414` | `#B3261E` | `DS.Color.error` |
| `DS/Color/textPrimary` | `#FFFFFF` | `#111113` | `DS.Color.textPrimary` |
| `DS/Color/textSecondary` | `#808080` | `#6B6B72` | `DS.Color.textSecondary` |
| `DS/Color/textTertiary` | `#64706F` | `#7A8281` | `DS.Color.textTertiary` |
| `DS/Color/textInverse` | `#000000` | `#FFFFFF` | `DS.Color.textInverse` |
| `DS/Color/iconPrimary` | `#FFFFFF` | `#111113` | `DS.Color.iconPrimary` |
| `DS/Color/iconSecondary` | `#808080` | `#6B6B72` | `DS.Color.iconSecondary` |
| `DS/Color/iconMuted` | `#CCCCCC` | `#A5A5AC` | `DS.Color.iconMuted` |

### 2.2 Dimensions (`DS/Spacing/*`, `DS/Radius/*`, etc.)

| Figma path | Value | Swift target |
|---|---|---|
| `DS/Spacing/xs` | 4 | `DS.Spacing.xs` ✓ |
| `DS/Spacing/sm` | 8 | `DS.Spacing.sm` ✓ |
| `DS/Spacing/md` | 12 | `DS.Spacing.md` ✓ |
| `DS/Spacing/lg` | 16 | `DS.Spacing.lg` ✓ |
| `DS/Spacing/xl` | 24 | `DS.Spacing.xl` ✓ |
| `DS/Spacing/xxl` | 32 | `DS.Spacing.xxl` ✓ |
| `DS/Spacing/xxxl` | 48 | `DS.Spacing.xxxl` ✓ |
| `DS/Radius/small` | 8 | `DS.Radius.small` ✓ |
| `DS/Radius/card` | 12 | `DS.Radius.card` ✓ |
| `DS/Radius/cardLarge` | 16 | `DS.Radius.cardLarge` ✓ |
| `DS/Radius/button` | 12 | `DS.Radius.button` ✓ |
| `DS/Radius/section` | 24 | `DS.Radius.section` (NEW for Phase 12) |
| `DS/Radius/sheet` | 32 | `DS.Radius.sheet` (NEW for Phase 12) |
| `DS/Blur/pill` | 4 | `DS.Blur.pill` (NEW for Phase 12) |
| `DS/Typography/Size/display` | 48 | `DS.Typography.Size.display` (NEW) |
| `DS/Typography/Size/title` | 16 | `DS.Typography.Size.title` (NEW) |
| `DS/Typography/Size/labelButton` | 14 | `DS.Typography.Size.labelButton` (NEW) |
| `DS/Typography/Size/body` | 12 | `DS.Typography.Size.body` (NEW) |
| `DS/Typography/Size/tips` | 10 | `DS.Typography.Size.tips` (NEW) |
| `DS/Typography/Size/caption` | 9 | `DS.Typography.Size.caption` (NEW) |
| `DS/Typography/Size/micro` | 8 | `DS.Typography.Size.micro` (NEW) |
| `DS/ConnectionButtonSize/compactDiameter` | **280** | `DS.ConnectionButtonSize.compactDiameter` (currently 140 — **NEEDS UPDATE**) |
| `DS/ConnectionButtonSize/regularDiameter` | 320 | `DS.ConnectionButtonSize.regularDiameter` (currently 160 — **NEEDS UPDATE**) |
| `DS/ConnectionButtonSize/compactIcon` | **112** | `DS.ConnectionButtonSize.compactIcon` (currently 56 — **NEEDS UPDATE**) |
| `DS/ConnectionButtonSize/regularIcon` | 128 | `DS.ConnectionButtonSize.regularIcon` (currently 64 — **NEEDS UPDATE**) |

---

## 3. Typography (text styles)

Font family used everywhere: **SF Pro Expanded** (with `Light` / `Regular` / `Semibold` / `Medium` weights).

| Figma style | Specs | Used for | Swift target |
|---|---|---|---|
| `Typography/Display/Timer` | Expanded Medium 48 | 00:01:07 timer | `DS.Typography.display` (needs update from `.largeTitle monospaced`) |
| `Typography/Title/Screen` | Expanded Semibold 16 | "Список серверов" sheet title | `DS.Typography.title` (needs update from `.title3 rounded bold`) |
| `Connection status` | Expanded Semibold 16 | "подключён" / "ошибка" labels | reuse `DS.Typography.title` |
| `Typography/Title/Section` | Expanded Semibold 12 | "Подписка" section header | new `DS.Typography.titleSection` |
| `Typography/Title/SectionUpper` | Expanded Semibold 9 | uppercase section labels | new `DS.Typography.titleUppercase` |
| `Typography/Label/Button` | Expanded Semibold 14 | "Добавить из буфера" CTA | new `DS.Typography.labelButton` |
| `Typography/Body/Default` | Expanded Regular 12 | "WL Латвия" server names | `DS.Typography.body` (needs Expanded family) |
| `Typography/Body/Caption` | Expanded Regular 9 | "20 мс" latency | `DS.Typography.caption` (needs Expanded family) |
| `Typography/Body/Micro` | Expanded Regular 8 | "11 Гб / 100 Гб" usage stats | new `DS.Typography.micro` |
| `Typography/Note/Default` | Expanded Semibold 9 | notes | reuse `DS.Typography.caption` w/ semibold |
| `Tips` | Expanded Light 10 | "Добавьте конфигурацию" Onboarding hint | new `DS.Typography.tips` |

**Phase 12 action:** Replace `.system(.title, design: .rounded)` calls in `DesignSystem.swift` with `.custom("SF Pro Expanded", size: ...)` family bindings.

---

## 4. Known mismatches (Phase 12 work)

These are the deltas between current Swift code and Figma source-of-truth. They must be resolved in Phase 12.

| # | Mismatch | Current Swift | Figma | Resolution |
|---|---|---|---|---|
| **M1** | ConnectionButton diameter | 140 (compact) / 160 (regular) | 280 / 320 | Update `DS.ConnectionButtonSize.compactDiameter`/`regularDiameter` |
| **M2** | ConnectionButton icon size | 56 / 64 | 112 / 128 | Update `DS.ConnectionButtonSize.compactIcon`/`regularIcon` |
| **M3** | ConnectionButton fill colors | inline `.gray`, `.orange`, `.accentColor`, `Color.red.opacity(0.85)` | `#222222` / Spinner / `#14664B` / `#661414` | Switch to `DS.Color.controlIdle/.accent/.error` |
| **M4** | Font family | `.system(.body, design: .rounded)` | SF Pro Expanded | Switch to `.custom("SF Pro Expanded", ...)` everywhere |
| **M5** | `DS.accent` | `Color.accentColor` (system) | `#14664B` (specific) | Define `DS.Color.accent = Color(hex: "#14664B")` |
| **M6** | Spinner animation | placeholder `ProgressView()` | 4-frame rotating ring | Custom rotating ring implementation |
| **M7** | Onboarding button styles | system Button styles | PrimaryButton (accent fill) / SecondaryButton (white) | New custom `ButtonStyle` matching Figma pill design |
| **M8** | ServerRow padding/spacing | mixed | 16pt all sides (DS.Spacing.lg), gap 12pt (DS.Spacing.md) | Verify against Figma values |
| **M9** | Sheet corner radius | likely system default | 32pt at top corners | `RoundedCorner(radius: DS.Radius.sheet, corners: [.topLeft, .topRight])` |
| **M10** | Section corner radius | likely default | 24pt (`DS.Radius.section`) | New token; apply to Подписка/Конфигурации/Авто frames |

---

## 5. Real Code Connect SDK setup (when ready)

When Phase 12 Swift code matches Figma, set up actual publishable Code Connect:

```bash
# 1. Install Code Connect CLI (Swift support requires Swift SDK, beta as of 2026-05)
npm install -g @figma/code-connect

# 2. Initialize Swift config in repo root
figma connect create --target=ios

# 3. This creates figma.config.json + scaffolds .figma.swift files
# Example output: ConnectionButton.figma.swift, ServerRow.figma.swift, etc.

# 4. Get Figma personal access token (Settings → Personal Access Tokens)
export FIGMA_ACCESS_TOKEN=your_token_here

# 5. Publish mappings to Figma
figma connect publish

# 6. Verify in Figma Desktop: hover any mapped component → shows Swift snippet
```

**Pre-publish checklist:**
- [ ] Swift ConnectionButton diameter matches Figma 280pt (M1)
- [ ] Swift ConnectionButton uses `DS.Color.accent/.error/.controlIdle` (M3)
- [ ] Swift uses SF Pro Expanded font everywhere (M4)
- [ ] Swift Spinner implementation matches Figma 4-frame ring (M6)
- [ ] Onboarding buttons match `PrimaryButton`/`SecondaryButton` Figma frames (M7)
- [ ] Sheet/section corner radii match Figma 32/24pt (M9/M10)

When all items are checked, the `.figma.swift` files generated from this mapping will faithfully represent the running app.

---

## 6. .figma.swift skeleton (preview, not yet executable)

```swift
// ConnectionButton.figma.swift
import Figma

struct ConnectionButton_doc: FigmaConnect {
    let component = ConnectionButton.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg?node-id=3054-712"

    @FigmaEnum("Property 1", mapping: [
        "disconnected": ConnectionState.idle,
        "connecting":   ConnectionState.connecting,
        "error":        ConnectionState.error(message: ""),
        "connected":    ConnectionState.connected(since: Date())
    ])
    var state: ConnectionState

    var body: some View {
        ConnectionButton(state: state, action: {})
    }
}
```

```swift
// ServerRow.figma.swift
import Figma

struct ServerRow_doc: FigmaConnect {
    let component = ServerRow.self
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg?node-id=3071-219"

    var body: some View {
        ServerRow(
            server: .preview,
            isSelected: false,
            pingState: .ok(20),
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
    }
}

struct ServerRowSelected_doc: FigmaConnect {
    let component = ServerRow.self  // same component, different example
    let figmaNodeUrl = "https://www.figma.com/design/tI6DFQDU6PdOSmd19BGXqg?node-id=3071-227"

    var body: some View {
        ServerRow(
            server: .preview,
            isSelected: true,
            pingState: .ok(20),
            onTap: {},
            onDelete: {},
            onDetailTap: {}
        )
    }
}
```

These are **preview snippets** — they will be fleshed out and made publishable in Phase 12 after Swift catches up to Figma.

---

## 7. Companion files

- **Tokens JSON:** [`figma-tokens.json`](./figma-tokens.json) — machine-readable token export from `export_tokens`
- **Token map (with Figma IDs):** [`../../../../.planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md`](../../../../.planning/phases/11-onboarding-ux-polish/figma-inspect/TOKEN-MAP.md)
- **Figma screenshots:** `.planning/phases/11-onboarding-ux-polish/figma-inspect/final-*.png` — visual references
