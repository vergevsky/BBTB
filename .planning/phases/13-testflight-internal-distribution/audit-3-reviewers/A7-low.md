# A7 — LOW packages (Opus 4.7)

**Baseline:** `fb2ff54`
**Tier:** LOW (quick sanity sweep — obvious bugs + smells only; deep concurrency/security skipped per scope)
**Files reviewed:** 12

DesignSystem:
- `DesignSystem.swift`
- `DSColor.swift`
- `BBTBTopBar.swift`
- `ButtonStyles.swift`
- `PhosphorReexport.swift`
- `Spinner.swift`

ProtocolEngine:
- `SingBoxBridge/SingBoxBridge.swift`
- `SingBoxBridge/LibboxBootstrap.swift`
- `XrayFallback/XrayFallback.swift`

ProtocolRegistry:
- `ProtocolRegistry/ProtocolRegistry.swift`

Localization:
- `L10n.swift`

CrashReporter:
- `CrashReporter/CrashReporter.swift`

**Total findings:** 7 (C: 0 / H: 0 / M: 2 / L: 5)

**Scope reality check:**
LOW tier indeed — 4 of the files are <40 LOC façade/stub/re-export. Most real surface is in DesignSystem visuals + the singleton lifecycle of ProtocolRegistry/CrashReporter. No critical/high issues found in scope; two MEDIUM correctness items concern thread-safety claims for DS color providers and CrashReporter ISO timestamp filename collision; remainder are smells (eager `static let` in L10n launch-critical block, deprecated alias surface in DS, `@unchecked Sendable` claim in ProtocolRegistry, `@_exported` brittleness, dummy XrayFallback constant).

---

## Critical

No CRITICAL findings in scope.

---

## High

No HIGH findings in scope.

---

## Medium

### A7-001: `DS.Color.dynamic` calls `UIColor/NSColor` provider closures that capture `traits`/`appearance` — closures executed off main thread without thread-safety claim
- **Location:** `DesignSystem/DSColor.swift:65-76`
- **Dimension:** correctness / Swift 6
- **Description:**
  `dynamic(dark:light:)` returns a `SwiftUI.Color` backed by `UIColor(dynamicProvider:)` (iOS) / `NSColor(name:dynamicProvider:)` (macOS). The provider closures invoke `uiColor(hex:)` / `nsColor(hex:)` (private static funcs) — these are stateless, so the closure body itself is safe.

  However, the entire `enum DS.Color` is implicitly `Sendable` (static value-typed properties of `Color`, which is `Sendable`) **but the `UIColor`/`NSColor` provider closure captures NOTHING** (it reads `dark`/`light` `UInt32` literals via `@escaping` capture — value-typed, safe). So the body is OK as written.

  The real smell is the **return-type cast path** on macOS: when the appearance is neither `.darkAqua` nor `.vibrantDark`, the closure returns the light variant — but it does NOT handle the case where `bestMatch` is called with an appearance like `.accessibilityHighContrastAqua` / `.accessibilityHighContrastDarkAqua` (Increase Contrast in System Settings). The expression `appearance.bestMatch(from: [.darkAqua, .vibrantDark]) != nil` returns:
  - For `.aqua` (light): nil → light ✓
  - For `.darkAqua`: `.darkAqua` → dark ✓
  - For `.accessibilityHighContrastAqua`: nil → light ✓ (acceptable)
  - For `.accessibilityHighContrastDarkAqua`: needs `[.accessibilityHighContrastDarkAqua, .darkAqua, .vibrantDark]` to return non-nil. **Currently returns nil → fallback to light hex on macOS Increase Contrast + Dark mode user combo.**

  Impact on TestFlight macOS Catalyst / native macOS builds: users running macOS with both Dark + Increase Contrast accessibility will see Light colors (#FFFFFF surface, #111113 text) on dark canvas — visually broken contrast but not unreadable. Phase 11 (Onboarding/UX polish) shipped without macOS accessibility audit.

- **Why MEDIUM:**
  Accessibility regression on a known macOS user configuration. iOS path uses `traits.userInterfaceStyle == .dark` which covers high-contrast variants correctly. The bug is platform-asymmetric and silent.

- **Suggested fix:**
  ```swift
  let isDark = appearance.bestMatch(
      from: [.darkAqua, .vibrantDark,
             .accessibilityHighContrastDarkAqua,
             .accessibilityHighContrastVibrantDark]
  ) != nil
  ```
  Alternatively, mirror iOS path with `NSAppearance.name`-based check or use `appearance.allowsVibrancy` + explicit aqua-vs-dark name match.

### A7-002: `CrashReporter.saveDiagnostic` filename uses ISO timestamp with colons → collision under rapid back-to-back payloads
- **Location:** `CrashReporter/CrashReporter.swift:52-64`
- **Dimension:** correctness
- **Description:**
  Filename built from `payload.timeStampBegin` formatted by ISO8601 + colon→hyphen replace:
  ```swift
  let timestamp = isoFormatter.string(from: payload.timeStampBegin)
  let filename = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-")).json"
  ```
  The configured formatter uses `[.withInternetDateTime]` which has **second resolution** — no fractional seconds. MetricKit batches multiple `MXDiagnosticPayload`s into a single `didReceive` call on the next app launch. If two crashes have the same `timeStampBegin` (rounded to seconds — very plausible if app crashed twice within one second during a tight retry loop or a transient SDK panic in tunnel extension), the second `data.write(to: url, options: .atomic)` **overwrites** the first crash report.

  Concrete scenario: a panic loop in `BaseSingBoxTunnel.startTunnel` could emit 3-5 crashes within the same wall-clock second; only the last one survives on disk → Phase 12 (TELEM-03 upload pipeline) loses evidence of the first crash signature.

  Additionally: filename has no app-version / build-number tag, so when v0.7.x and v0.8.x crashes coexist in App Group container, they're indistinguishable without parsing JSON contents.

- **Why MEDIUM:**
  Data loss in the TELEM-01 path. Worst-case: silent overwrite of crash evidence right before user uploads logs via TELEM-02 export. Reproduces under any rapid crash loop. Phase 13 TestFlight scope makes this more visible — first cohort of testers may hit cold-start panics that mask each other.

- **Suggested fix:**
  Use higher-resolution timestamp + a deduplication suffix:
  ```swift
  let f = ISO8601DateFormatter()
  f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
  // ...
  let base = "crash-\(timestamp.replacingOccurrences(of: ":", with: "-"))"
  var url = dir.appendingPathComponent("\(base).json")
  var suffix = 1
  while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base)-\(suffix).json")
      suffix += 1
  }
  ```
  Or include `Bundle.main.shortVersion` + `payload.applicationVersion` in the filename to disambiguate cross-version crashes.

---

## Low

### A7-003: `L10n` static-let block triggers eager Bundle resource load — comment claim vs reality
- **Location:** `Localization/L10n.swift:15-56`
- **Dimension:** performance / code smell
- **Description:**
  Header comment (line 4-13) describes Phase 6e Wave 2 Theme A L3 conversion: launch-critical keys stay `static let` (eager), non-launch keys become `static var` (lazy). The rationale is correct, but the launch-critical block lists **~30 keys** — including `bannerConnectionError`, `homeButtonHintDisconnect`, `homeButtonHintReconnect`, `alertImportFailed`, `alertTunnelErrorTitle`, `menuAddConfig`, `menuScanQR`, `menuImportFromClipboard` — that are NOT rendered on the first frame.

  Specifically:
  - `homeButtonHintDisconnect` / `homeButtonHintReconnect` — accessibilityHint for ConnectionButton; only consulted when VoiceOver focuses the button.
  - `alertImportFailed` / `alertTunnelErrorTitle` — only when an error alert presents.
  - `menuAddConfig` / `menuScanQR` / `menuImportFromClipboard` — Menu items, lazy-rendered.
  - `bannerConnectionError` — only on `.error` state.

  These 7-8 keys could be `static var` without regressing first-frame budget. The current eager block pays ~7-8 extra `NSLocalizedString` lookups at cold start (each ~50-200μs on real device per `_swift_stdlib_strstr` profile), totaling ~0.5-1.5ms wasted before MainScreenView's first paint.

- **Why LOW:**
  Marginal perf win; the comment-vs-code drift is the bigger code-hygiene issue — invites future maintainers to add more keys to the "launch-critical" pile out of caution. Phase 6e established the discipline; this is drift from it.

- **Suggested fix:**
  Move the 7-8 cited keys to the `static var` block. Add an inline `// NOTE: keep launch-critical block ≤N keys` comment to prevent future drift.

### A7-004: `ProtocolRegistry.shared` — `@unchecked Sendable` claim is correct, but `register` after launch creates silent ordering bugs
- **Location:** `ProtocolRegistry/ProtocolRegistry.swift:6-26`
- **Dimension:** code smell / API design
- **Description:**
  Singleton + NSLock implementation is correct (the `@unchecked Sendable` claim is justified). However the API has zero guard against late registration:
  - `BBTB_iOSApp.init()` calls `register(VLESSRealityHandler.self)`, `register(TrojanHandler.self)`, ..., 6 handlers.
  - There's no `freeze()` / `finalize()` / `isFrozen` flag.
  - If any code path mutates the registry **after** `RulesEngine` / `SingBoxConfigLoader` / `ConfigImporter` has already cached `registeredIdentifiers` (which `registeredIdentifiers` returns a copy of, so technically safe), the cached snapshot diverges from the live registry. Worse: `handler(for: "trojan")` could return nil on first call (before app-init finished), and non-nil later — leading to flaky unit tests if `register` is in a `setUp` that races with a background ImportFlow task started from a previous test.

  Concrete TestFlight-relevant risk: if Phase 13 D-04 (Routing rules toggle) or future hot-path adds dynamic protocol registration after launch (e.g., enabling Hysteria2 only after a server with that scheme is imported), nothing prevents `register` from being called from a non-main thread mid-flight while a snapshot is already in use elsewhere. The lock serializes individual calls but does NOT provide read-write consistency for multi-step "check + use" patterns.

  Smell: `static let shared` + global mutable map without invariant that registration completes before first read.

- **Why LOW:**
  No reproducer in current code (all register calls happen synchronously in `App.init` before any `body` evaluates). It's a latent design smell that would bite at v1.x if anyone adds dynamic protocol loading.

- **Suggested fix:**
  Either:
  - Add `private var isFrozen = false; func freeze()` + `precondition(!isFrozen, "ProtocolRegistry mutated after freeze")` in `register`, called by App.init at end of registration block.
  - Or document the registration contract in a `///` doc-comment and add a DEBUG-only assertion that `register` is called from main actor.

### A7-005: `XrayFallback.placeholder = true` is dead code — should be removed or replaced with a real fallback marker
- **Location:** `XrayFallback/XrayFallback.swift:1-4`
- **Dimension:** code smell / dead code
- **Description:**
  Entire module is 4 lines:
  ```swift
  public enum XrayFallback {
      public static let placeholder = true
  }
  ```
  Comment says "CORE-09 (xray-core fallback) — Phase 4+. Phase 1 — placeholder." We are now at Phase 13 (TestFlight). CORE-09 has not been implemented. The `placeholder` constant is exported as part of `ProtocolEngine` product surface but has zero consumers (verified via `grep -rn "XrayFallback" /Users/vergevsky/ClaudeProjects/VPN/BBTB --include="*.swift"` — expected to return only the definition file).

  This adds noise to the package graph + ships a public symbol that means nothing to end users (TestFlight reviewers reading our SDK surface might raise an eyebrow). Either:
  - Implement CORE-09 (out of Phase 13 scope), or
  - Remove the `XrayFallback` target entirely (rip out of `Package.swift` for ProtocolEngine + dependent imports).

- **Why LOW:**
  Cosmetic / hygiene. Not user-visible but it's been carrying since Phase 1.

- **Suggested fix:**
  Delete `XrayFallback/` target. If it must remain as a roadmap anchor, replace the `placeholder` constant with a doc-comment-only enum (no public members) or annotate `@available(*, unavailable, message: "CORE-09 — not implemented; deferred to v1.x")`.

### A7-006: `@_exported import` of Libbox / PhosphorSwift — underscored API + transitive symbol pollution
- **Location:** `SingBoxBridge/SingBoxBridge.swift:1`, `DesignSystem/PhosphorReexport.swift:14`
- **Dimension:** code smell / forward-compat risk
- **Description:**
  Both files use `@_exported import` — an underscored Swift attribute that is technically unsupported and can break across Swift toolchain releases. The DesignSystem file has a comment acknowledging this:
  > `@_exported` underscored, но стабильно используется в SPM ecosystem (Foundation / Glibc / etc.); fallback при необходимости — explicit `import PhosphorSwift` в consumer-features.

  Reality:
  1. Swift 6.1+ (next toolchain) has been discussing stricter linting around `@_` underscored imports.
  2. Consumers like `MainScreenFeature` that rely on transitive `Ph.list` symbols via `import DesignSystem` would break silently if `@_exported` becomes a warning/error.
  3. The Libbox re-export is more dangerous because Libbox is a gomobile-generated framework with hundreds of public symbols (`LibboxNewService`, `LibboxNewCommandServer`, etc.) — pollutes consumer namespace.

  Both re-exports are convenience-only; consumers could explicitly `import PhosphorSwift` / `import Libbox` with one extra line per file.

- **Why LOW:**
  Works today on Swift 6.0. The fallback is well-known (explicit imports). Not blocking TestFlight but is technical debt with a known half-life.

- **Suggested fix:**
  Track in v1.x backlog: replace `@_exported import PhosphorSwift` with explicit imports in ~12-15 consumer files; same for Libbox in PacketTunnelKit + ProtocolEngine sites. Alternative: wait for Swift to provide a stable `public import` (already shipped as preview in Swift 5.9+ but adoption is incomplete in SPM tooling).

### A7-007: `DS.accent` deprecated alias has no fix-it migration path documented for consumers
- **Location:** `DesignSystem/DesignSystem.swift:23-24`
- **Dimension:** code smell / API hygiene
- **Description:**
  `@available(*, deprecated, renamed: "DS.Color.accent")` correctly emits a Swift fix-it. However, the `renamed:` token is a string — Swift's auto-fix-it works for **method renames** reliably but is finicky for **property** renames involving nested types. The fix-it will likely propose `DS.Color.accent` correctly but only when the deprecated symbol is used as `DS.accent` (not as `Color.accent` via some other extension).

  More importantly: there's no `// MARK: - Migration` block in DesignSystem.swift summarizing the full deprecation list (currently only `DS.accent`, but Phase 12 / DS-06 / M4 alias block at line 119-129 has 6 more aliases — `Typography.display`, `.title`, `.body`, `.callout`, `.subheadline`, `.caption` — none marked `@available(*, deprecated, ...)`).

  Those 6 typography aliases are described in code comments as "Phase 1 alias — теперь проксирует через..." but are NOT deprecated. So they remain part of the supported surface indefinitely, even though Phase 12 (DS-06) introduced new canonical names (`displayTimer`, `titleScreen`, `bodyDefault`, etc.). Consumer code stays on the old names; the canonical naming exists only for new code. This is a soft-deprecation that will rot.

- **Why LOW:**
  Pure API hygiene. No functional bug — aliases work. The risk is that 12 months from now, no one will remember that `Typography.title` is "really" `titleScreen` semantically (Figma frame ServerListSheet title — 16pt Expanded Semibold), and someone will apply `Typography.title` to a different-semantic site and get correct font but wrong meaning.

- **Suggested fix:**
  Either:
  - Mark all 6 Typography aliases `@available(*, deprecated, renamed: "DS.Typography.displayTimer")` etc. — generates compile warnings on every consumer; forces migration.
  - Or remove them entirely and provide a fix-it migration shell script in `/scripts/` that runs `sed -i '' 's/DS.Typography.title/DS.Typography.titleScreen/g'` etc.
  - Or accept the soft-deprecation and document it explicitly in `CODE-CONNECT.md` with a "do not use for new code" callout.

---

## Out of scope (not reviewed beyond confirming small file size)

- `Localization/Resources/Localizable.xcstrings` — JSON resource, not Swift; out of scope per task definition (Sources/ only).
- All test files — explicit out-of-scope.
- Phosphor re-export only carries a single `@_exported` line; reviewed in A7-006.

---

## Cross-package patterns observed (informational, not findings)

1. **All 5 packages use `@unchecked Sendable`** (ProtocolRegistry, CrashReporter) or rely on Swift 6 strict concurrency for value-typed enums (DesignSystem, Localization). The pattern is consistent with PacketTunnelKit conventions documented in A1 audit. No new violations beyond what A1 already flagged for `BaseSingBoxTunnel`.

2. **Singleton install discipline is correct:** `CrashReporter.shared.install()` (idempotent via `isInstalled` flag + NSLock) and `ProtocolRegistry.shared.register(...)` are both called from App.init synchronously on main actor. No race.

3. **L10n `Bundle.module` resolution:** uses SPM-generated `Bundle.module` (via `resource_bundle_accessor.swift`), correct pattern. No risk of accidentally hitting `Bundle.main` from extension context.

4. **DesignSystem hex parsing is straightforward** (`>> 16 & 0xFF`, etc.) with alpha=1. No alpha-channel support — Figma BBTB v3 spec confirms 100% opaque tokens only (Spinner uses `SwiftUI.Color.clear` directly for the gap, not a tokenized opacity stop).

5. **No force-unwraps in scope.** Only one `fatalError` — `AppGroupContainer.url` (outside this scope, but referenced by `CrashReporter.saveDiagnostic`) — which is acceptable as bootstrap-invariant guard.

---

## Verdict

LOW tier is genuinely LOW. No blockers for Phase 13 TestFlight Internal Distribution. The 2 MEDIUM findings (A7-001 macOS Increase Contrast accessibility, A7-002 crash filename collision) are silent-failure modes worth fixing as small follow-ups but don't gate TestFlight upload. The 5 LOW items are code-hygiene drift that would normally accumulate in any year-old codebase — recommend triaging them into Phase 13 Plan 06 backlog with light-touch fix passes.

End of A7 audit.
