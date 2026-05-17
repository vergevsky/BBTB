# A7 — Opus 4.7 audit reviewer (Wave 3 LOW)

**Baseline:** `ccbce8a` (Plan 07 closure index + AUDIT-3 verdict)
**Date:** 2026-05-17
**Scope:** DesignSystem + ProtocolEngine + ProtocolRegistry + Localization + CrashReporter
**Mode:** Sanity sweep — only obvious bugs + smells. T-C-D1 verification.

---

## TL;DR

**Verdict:** LOW packages в отличном состоянии. **0 bugs**, **0 smells worth fixing pre-TestFlight**. T-C-D1 fix корректен; Bundle.main.object behavior корректен в обоих контекстах (main app + extension); filename uniqueness теперь гарантирована.

Найдено только **2 nit-doc items** (cosmetic, не блокеры).

---

## T-C-D1 verification — CrashReporter filename collision fix

**Commit `d802e72`** modifies `Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:52-83`.

### Diff summary

| Before (Plan 06) | After (T-C-D1) |
|---|---|
| `f.formatOptions = [.withInternetDateTime]` | `f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]` |
| `crash-<ISO-seconds>.json` | `crash-<ISO-ms>-v<bundleVer>.json` |
| Single replacement: `:` → `-` | Two replacements: `:` → `-`, `.` → `-` |

### Filename uniqueness analysis

**Pre-fix scenario:**
- `MXDiagnosticPayload.timeStampBegin` measured at second granularity.
- MetricKit может batch-deliver несколько payload'ов в одном `didReceive(_:)` callback (e.g. multi-crash session).
- Если два payload'а имели `timeStampBegin` в пределах того же second window, filename collision → `Data.write(.atomic)` перезаписывает первый.

**Post-fix scenario:**
- `.withFractionalSeconds` produces 3-digit millisecond suffix (e.g. `2026-05-17T13:32:45.123Z`).
- After `:` → `-` and `.` → `-` replacements: `2026-05-17T13-32-45-123Z` — POSIX-valid filename on APFS / HFS+ / ext4 (no special chars).
- Plus `-vX.Y.Z` (or `-vunknown` fallback) suffix.
- Collision probability requires two MXDiagnosticPayload events с **identical millisecond `timeStampBegin`** — essentially zero in practice (MetricKit aggregates over 24h windows; payloads naturally spread).

**Verified:** L62-67 build sequence
```swift
let timestamp = isoFormatter.string(from: payload.timeStampBegin)
let bundleVer = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
let safeTimestamp = timestamp
    .replacingOccurrences(of: ":", with: "-")
    .replacingOccurrences(of: ".", with: "-")
let filename = "crash-\(safeTimestamp)-v\(bundleVer).json"
```
Order of replacements is correct (`:` first, then `.` — they're disjoint character classes so order doesn't actually matter, but neither would the reverse fail).

### `Bundle.main.object(forInfoDictionaryKey:)` behavior — correct in both contexts

**Context 1: Main app (host process).**
- `Bundle.main` resolves to the host app's `Info.plist` containing `CFBundleShortVersionString`.
- Returns e.g. `"1.0"` (current marketing version per Phase 1 W5 baseline).

**Context 2: Network Extension process.**
- `Bundle.main` in an extension is the **extension's** own bundle (not the host app's).
- The extension target ALSO has `CFBundleShortVersionString` (required by App Store — must match host app version for review).
- Returns same `"1.0"`.

**Edge case verified:** `MXMetricManagerSubscriber` subscriptions happen в main app process (см. CrashReporter.install() called from `BBTB_iOSApp.init()` / `BBTB_macOSApp.init()` — see `/Users/vergevsky/ClaudeProjects/VPN/BBTB/App/iOSApp/BBTB_iOSApp.swift:74` registrations). So `Bundle.main` resolves to **main app** bundle here, not extension. **Behavior correct.**

**Fallback `"unknown"`:** properly handled (`as? String ?? "unknown"`). Если `CFBundleShortVersionString` отсутствует или non-String type, filename gets `-vunknown` suffix вместо crash — graceful degradation.

### `isoFormatter` lazy init thread-safety

`isoFormatter` is a `let` initialized with a closure (line 78-83). Apple guarantees `static let` properties initialized as singletons through `dispatch_once`. Since this is **instance-level** `let` (inside `final class CrashReporter`), it's initialized once at object init — safe because `init()` is called from `shared = CrashReporter()` singleton initialization (Swift guarantees `static let shared` is itself dispatch_once-protected).

`ISO8601DateFormatter` is documented as thread-safe by Apple (since iOS 10). Subsequent `string(from:)` calls from concurrent `didReceive(_:)` invocations are safe.

### Verdict

**T-C-D1 fix verified correct.** Bundle.main behavior matches expectations in MXMetricManager subscriber lifecycle. Filename uniqueness now exhaustive within practical limits. **No follow-up needed.**

---

## Package-by-package sweep

### CrashReporter — `Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift`

**Lines audited:** 95 LOC, 1 file.

**Findings:** none.

Other observations (informational, not findings):
- `NSLock` for `isInstalled` guard (L19-29) — appropriate; install() called from `App.init()`, single-threaded in practice but defensive lock cheap insurance.
- `@unchecked Sendable` (L15) — justified: only mutable state is `isInstalled` Bool guarded by `NSLock`, and `MXMetricManager` is itself a system singleton.
- `didReceive(_ payloads: [MXMetricPayload])` (L35-38) — explicit ignore + debug log; correct Phase 1 scope (TELEM-04 deferred to Phase 12).
- `#if DEBUG _test_inject` (L87-93) — properly gated; production builds don't expose it.
- Atomic write `try data.write(to: url, options: .atomic)` (L71) — POSIX rename(2) semantics, prevents partial-write corruption visible to readers (Phase 12 TELEM-03 telemetry pipeline).

### DesignSystem — `Packages/DesignSystem/Sources/DesignSystem/*.swift` (6 files)

**Files audited:** 627 LOC total (BBTBTopBar 122, Spinner 94, DSColor 99, DesignSystem 142, PhosphorReexport 14, ButtonStyles 105).

**Findings:**

#### A7-LOW-001 — DSColor.swift token count documentation off-by-one (nit, doc-only)
**File:** `Packages/DesignSystem/Sources/DesignSystem/DSColor.swift:1, 22`
**Severity:** LOW (nit, no functional impact)

L1 header says `15 токенов`; L22 enum doc says `16 семантических color tokens`. Actual count is **16**: 6 surfaces (canvas, surface, surfaceSunken, surfaceHeader, divider, controlIdle) + 2 brand/status (accent, error) + 5 text (textPrimary, textSecondary, textTertiary, textInverse, alwaysWhite) + 3 icons (iconPrimary, iconSecondary, iconMuted) = 16.

L22 is correct; L1 header has stale `15` (pre-`alwaysWhite` addition mentioned at L29 of doc comment). Cosmetic only — fix in v1.0.1 polish.

#### Other observations (informational)
- **`dynamic()` platform coverage** (L65-76): `#if os(iOS) / #elseif os(macOS)` — safe because Package.swift restricts platforms to `[.iOS(.v18), .macOS(.v15)]`. If Linux/tvOS/watchOS were added later, compile error would surface immediately (`return` missing) — fail-fast is correct.
- **`alwaysWhite` token** (L54): `dynamic(dark: 0xFFFFFF, light: 0xFFFFFF)` — same value both modes, intentional per Phase 12 D-05 (text on accent/error backgrounds stays white in Light to remain readable). Could be simplified to plain `SwiftUI.Color(white: 1.0)` but current form maintains symmetry с other tokens (clearly readable as "static white" semantic). No fix needed.
- **`SwiftUI.Color.clear` qualifier** (Spinner L67): explicit `SwiftUI.Color.clear` — necessary because `DS.Color` enum nests `Color` which would shadow `SwiftUI.Color` in same scope. Correct.
- **BBTBTopBar `.padding(.top, 32)`** (BBTBTopBar L66): hard-coded 32 instead of `DS.Spacing.xxl` token — minor consistency issue but `xxl` IS 32 (DesignSystem.swift L38), so semantically equivalent. Backlog for v1.x polish.
- **`_AccessibilityLabelIfPresent` ViewModifier** (BBTBTopBar L97-107): leading underscore = private convention marker (not Swift access modifier). Properly scoped via `private struct`. Clean.
- **`PrimaryButtonStyle` / `SecondaryButtonStyle` Reduce-Motion behavior** (ButtonStyles L45-58, L89-102): correctly implements UI-SPEC §3.8 contract — animated press when motion enabled, static opacity-only feedback when reduced. Verified branches don't allow combined animation+isPressed-static visual when reduceMotion=true.
- **`BBTBSpinner` battery guard** (Spinner L78-90): `withAnimation` started in `.onAppear` — correctly cancelled automatically when view unmounts. UI-SPEC §2.2 contract satisfied (mount conditionally in parent).
- **`PhosphorReexport.swift`** (14 LOC): `@_exported import PhosphorSwift` — underscored API but stable practice in SPM ecosystem. Documented justification at L11-13.

### ProtocolEngine — `Packages/ProtocolEngine/Sources/{SingBoxBridge,XrayFallback}/*.swift`

**Files audited:** 3 files, 49 LOC total.

**Findings:** none.

Other observations:
- `SingBoxBridge.swift:9` — hard-coded `singBoxVersion = "1.13.11"` string constant. Manual maintenance burden when libbox updates, but trivially low risk (single source of truth, grep-able). Could be auto-extracted from libbox via `LibboxVersion()` C API call if Apple exposes it — backlog item, not blocker.
- `LibboxBootstrap.setup()` (L22-32) — proper NSError bridging; `SetupError.failure(NSError?)` LocalizedError conformance gives clean error propagation to BaseSingBoxTunnel callers.
- `XrayFallback.swift` (5 LOC) — Phase 1 placeholder; explicit comment marks it as such. Will be replaced in Phase 4+ per CORE-09. No findings.

### ProtocolRegistry — `Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift`

**Files audited:** 27 LOC, 1 file.

**Findings:** none.

Other observations:
- `NSLock` guards `handlers` dict (L10-25) — correct for `@unchecked Sendable` actor-replacement pattern.
- `register` / `handler(for:)` / `registeredIdentifiers` all properly hold lock for full read/write cycle.
- All registrations happen at App.init() (verified `BBTB_iOSApp.swift:74-79` and `BBTB_macOSApp.swift:53-58`) — single producer / multi consumer pattern.
- `registeredIdentifiers` (L22-25) sorts keys for stable output — useful for tests and debug logs.

### Localization — `Packages/Localization/Sources/Localization/L10n.swift` + `Resources/Localizable.xcstrings`

**Files audited:** L10n.swift = 412 LOC, Localizable.xcstrings = 1410 LOC JSON.

**Findings:** none.

Other observations:
- **Eager vs lazy split is correct** (L23-56 eager `static let` vs L58-411 lazy `static var x: String { tr("x") }`). Launch-critical set (status*, action*, app*, empty*, menu*, alertImportFailed, settingsTitle, plus banner/home button labels, deepLink alert title) properly identified — these render on first frame of MainScreenView / EmptyStateCard / deepLink alert. Phase 6e Theme A L3 cold-start optimization verified.
- **`tr()` helper** (L15-21) — two overloads (zero-arg + variadic CVarArg). Variadic form correctly uses `String(format: fmt, arguments: args)` — propagates Russian plural rules from .xcstrings.
- **Plural-aware funcs** (e.g. L229-231 `rulesCountDomains(_ n: Int)`) — properly route through .xcstrings plurals via variadic `tr(_:_:)` with Int. xcstrings handles `%lld` formatting.
- **`subscriptionFallbackName`** (L411) — last entry, properly comment-grouped per phase. No gaps in MARK structure.
- **iconMuted reference in Spinner doc** (DSColor.swift L59, Spinner.swift L22, L65) — properly cross-referenced. Color token `iconMuted = dynamic(dark: 0xCCCCCC, light: 0xA5A5AC)` exists and is consumed.

### Other sanity checks (cross-cutting)

- **`print()` calls in scope:** 0 (clean — CLAUDE.md project rule satisfied).
- **`TODO/FIXME/XXX/HACK` markers in scope:** 0.
- **`try!` / `fatalError` in scope:** 0.
- **`force unwrap (.!)` patterns:** 0 unsafe ones found (only `withIntermediateDirectories: true` of FileManager — non-failure variant).
- **`@MainActor` annotations in scope:** none — appropriate; CrashReporter is Sendable via @unchecked + lock, L10n is pure functions, ProtocolRegistry is locked.

---

## Aggregated severity counts

| Severity | Count |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 1 (A7-LOW-001 doc nit) |

---

## Cross-validation against prior audits

**Plan 06 LOW findings (Tier-D) closed by Plan 07 (commit `d802e72`):**
- ✅ T-C-D1 (A7-002 MEDIUM) — CrashReporter filename collision — **verified fixed**, see T-C-D1 section above.
- ✅ T-C-D2 (L-A5-3-09 + C5'-3-005) — PublicKey doc-comment mismatch — NOT in my scope (Crypto/RulesEngine).
- ✅ T-C-D3 (A1'-3-013) — dead PacketTunnelKit.swift — NOT in my scope (PacketTunnelKit).
- ✅ T-C-D4 (A1'-3-010) — InterfaceFlagsInspector print() — NOT in my scope (PacketTunnelKit).

**Verdict:** T-C-D1 fix is the only Plan 07 change touching A7 scope; verified correct above.

**Deferred Tier-C LOW items (~40 from Plan 06):** none in A7 scope identified during sweep — i.e. no LOW items in these 5 packages were carried forward. These packages were already clean at Plan 06 close.

---

## Recommendations

1. **A7-LOW-001** (DSColor.swift L1 stale `15 токенов` comment): fix during v1.0.1 polish — single-line doc update, 5 sec edit. Not blocking TestFlight.

2. **No other action required.** These 5 packages are TestFlight-ready.

---

## Effort estimate

Sweep wall time: ~12 minutes. Files read: 11 source files + 4 supporting (Package.swift, AppGroupContainer.swift, test files, commit diff). Output: ~280 lines.

**Confidence:** High. Packages are small, well-commented, single-responsibility. No hidden complexity uncovered.
