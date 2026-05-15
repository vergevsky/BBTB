# Figma Token Map — BBTB v3

**File:** `tI6DFQDU6PdOSmd19BGXqg` (BBTB v3)
**Generated:** 2026-05-15 (Step 1 of Figma cleanup)
**Audited:** 2026-05-16 — 6 orphan variables removed (glow palette + warning red after design cleanup)
**Final count:** 51 variables (11 Primitives + 40 DS)

## Collections

| Name | ID | Modes |
|---|---|---|
| `Primitives` | `VariableCollectionId:3071:145` | Dark `3071:0`, Light `3071:1` |
| `DS` | `VariableCollectionId:3071:162` | Dark `3071:2`, Light `3071:3` |

## Primitives (11) — invariant raw values; Light = Dark by design

| Path | ID | Hex |
|---|---|---|
| `neutral/black` | `3071:146` | `#000000` |
| `neutral/white` | `3071:147` | `#FFFFFF` |
| `neutral/gray-950` | `3071:148` | `#1A1A1A` |
| `neutral/gray-850` | `3071:149` | `#222222` |
| `neutral/gray-800` | `3071:150` | `#333333` |
| `neutral/gray-600` | `3071:151` | `#808080` |
| `neutral/gray-500` | `3071:152` | `#B2B2B2` |
| `neutral/gray-400` | `3071:153` | `#CCCCCC` |
| `neutral/grayWarmDim` | `3071:154` | `#64706F` |
| `brand/green-700` | `3071:155` | `#14664B` |
| `status/red-800` | `3071:156` | `#661414` |

**Removed in audit (2026-05-16):** `status/red-500` `#FF3300`, `glow/peach/gold/yellow/shadowPeach` — orphaned after Effect/Power-Glow style deletion and progress-bar consistency fix.

## DS Colors (15)

| Path | ID | Dark | Light (placeholder) | Swift target |
|---|---|---|---|---|
| `Color/canvas` | `3071:163` | `#000000` | `#FFFFFF` | `DS.Color.canvas` |
| `Color/surface` | `3071:164` | `#222222` | `#F4F4F6` | `DS.Color.surface` (sheet root) |
| `Color/surfaceSunken` | `3071:165` | `#1A1A1A` | `#ECEDEF` | `DS.Color.surfaceSunken` (sections внутри sheet) |
| `Color/surfaceHeader` | `3071:166` | `#333333` | `#E0E0E5` | `DS.Color.surfaceHeader` (header strip) |
| `Color/divider` | `3071:167` | `#333333` | `#D8D8DD` | `DS.Color.divider` (row strokes) |
| `Color/controlIdle` | `3071:168` | `#222222` | `#E8E8EC` | `DS.Color.controlIdle` (idle button bg) |
| `Color/accent` | `3071:169` | `#14664B` | `#14664B` | `DS.Color.accent` |
| `Color/error` | `3071:170` | `#661414` | `#B3261E` | `DS.Color.error` |
| `Color/textPrimary` | `3071:172` | `#FFFFFF` | `#111113` | `DS.Color.textPrimary` |
| `Color/textSecondary` | `3071:173` | `#808080` | `#6B6B72` | `DS.Color.textSecondary` |
| `Color/textTertiary` | `3071:174` | `#64706F` | `#7A8281` | `DS.Color.textTertiary` (warm dim, Auto section) |
| `Color/textInverse` | `3071:175` | `#000000` | `#FFFFFF` | `DS.Color.textInverse` |
| `Color/iconPrimary` | `3071:176` | `#FFFFFF` | `#111113` | `DS.Color.iconPrimary` |
| `Color/iconSecondary` | `3071:177` | `#808080` | `#6B6B72` | `DS.Color.iconSecondary` |
| `Color/iconMuted` | `3071:178` | `#CCCCCC` | `#A5A5AC` | `DS.Color.iconMuted` (on selected rows) |

**Removed in audit (2026-05-16):** `Color/warning` `#FF3300` (progress-bar mistake fixed), `Color/powerGlow*` ×3, `Color/powerShadow*` ×2 — orphaned after Power-Glow style deletion.

## DS Dimensions (28 FLOATs — Light = Dark)

### Spacing (7) — matches existing `DS.Spacing.*`
| Path | ID | Value | Swift |
|---|---|---|---|
| `Spacing/xs` | `3071:184` | 4 | `DS.Spacing.xs` |
| `Spacing/sm` | `3071:185` | 8 | `DS.Spacing.sm` |
| `Spacing/md` | `3071:186` | 12 | `DS.Spacing.md` |
| `Spacing/lg` | `3071:187` | 16 | `DS.Spacing.lg` |
| `Spacing/xl` | `3071:188` | 24 | `DS.Spacing.xl` |
| `Spacing/xxl` | `3071:189` | 32 | `DS.Spacing.xxl` |
| `Spacing/xxxl` | `3071:190` | 48 | `DS.Spacing.xxxl` |

### Radius (6) — extends existing `DS.Radius.*` with sheet+section (NEW from Figma)
| Path | ID | Value | Swift |
|---|---|---|---|
| `Radius/small` | `3071:191` | 8 | `DS.Radius.small` |
| `Radius/card` | `3071:192` | 12 | `DS.Radius.card` |
| `Radius/cardLarge` | `3071:193` | 16 | `DS.Radius.cardLarge` |
| `Radius/button` | `3071:194` | 12 | `DS.Radius.button` |
| `Radius/section` | `3071:195` | 24 | `DS.Radius.section` (NEW — sections внутри sheet) |
| `Radius/sheet` | `3071:196` | 32 | `DS.Radius.sheet` (NEW — `Frame 25` sheet root) |

### Blur (1)
| Path | ID | Value | Swift |
|---|---|---|---|
| `Blur/pill` | `3071:200` | 4 | `DS.Blur.pill` |

**Removed in audit (2026-05-16):** `Elevation/powerGlowRadiusSmall/Medium/Large` (3) — orphaned with Power-Glow style.

### Typography sizes (7)
Mapping to existing Figma text styles:
| Path | ID | Value | Maps to Figma text style |
|---|---|---|---|
| `Typography/Size/display` | `3071:201` | 48 | `Typography/Display/Timer` |
| `Typography/Size/title` | `3071:202` | 16 | `Connection status`, `Typography/Title/Screen` |
| `Typography/Size/labelButton` | `3071:203` | 14 | `Typography/Label/Button` |
| `Typography/Size/body` | `3071:204` | 12 | `Typography/Title/Section`, `Typography/Body/Default` |
| `Typography/Size/tips` | `3071:205` | 10 | `Tips` |
| `Typography/Size/caption` | `3071:206` | 9 | `Typography/Title/SectionUpper`, `Typography/Body/Caption`, `Typography/Note/Default` |
| `Typography/Size/micro` | `3071:207` | 8 | `Typography/Body/Micro` |

### ConnectionButton (4) — **MISMATCH ALERT**
Figma uses 280×280 iPhone button; Swift uses 140. Per user signal "pixel-perfect от Figma", Swift will grow.
| Path | ID | Value | Swift target (after Phase 11 Swift update) |
|---|---|---|---|
| `ConnectionButtonSize/compactDiameter` | `3071:208` | 280 | `DS.ConnectionButtonSize.compactDiameter` (140 → **280**) |
| `ConnectionButtonSize/regularDiameter` | `3071:209` | 320 | speculative; await macOS-page inspection |
| `ConnectionButtonSize/compactIcon` | `3071:210` | 112 | `DS.ConnectionButtonSize.compactIcon` (56 → **112**) |
| `ConnectionButtonSize/regularIcon` | `3071:211` | 128 | speculative |

## Known TODO (carry to Step 5)

1. **Broken style bindings** in `Effect/Power-Glow` and `Fill/PowerButton-Glow` reference deleted `VariableID:1083:128..132`. Visually they still render (fallback hex colors are written). To fully fix:
   - Option A: delete + recreate effect/paint style with new variable bindings to `DS/Color/powerGlow*` and `DS/Elevation/powerGlow/*` (write capability via MCP unclear)
   - Option B: leave as-is — fallback colors match new tokens 1:1, visuals identical
   - Decision: **Option B for Phase 11**, address in Phase 12 if Code Connect requires clean bindings.

2. **Progress-bar color inconsistency** between Auto-section (`#FF3300` orange-red) and Подписка-section (`#14664B` accent green). Both use `Color/warning` (#FF3300) and `Color/accent` (#14664B). **User decision needed**: is `#FF3300` intentional (over-usage warning) or a copy-paste mistake?

3. **macOS regularDiameter/regularIcon** values (320/128) are speculative. Inspect `MacOS` page or `MacOS popover` page when ServerRow + Code Connect work continues.
