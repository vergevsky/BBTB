# A7 — LOW tier audit (Opus 4.7)

**Scope:** 5 leaf packages (DesignSystem, ProtocolEngine, ProtocolRegistry, Localization, CrashReporter)
**Files audited:** 12
**Total findings:** 9 (CRITICAL: 0, HIGH: 0, MEDIUM: 1, LOW: 8)

Sanity sweep clean — no shipping-path bugs, no crash vectors, no L10n key drift, no memory-leak patterns. Two dead-code carve-outs worth carving to backlog; one minor SwiftUI animation hygiene smell.

---

## Findings (grouped by package)

### DesignSystem

#### A7-DS-01 (LOW) — Unused `BBTBSpinner.speed` parameter when `reduceMotion=true`
`BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift:52-56,76-90`
`BBTBSpinner.init(speed:)` is publicly settable, but when `reduceMotion=true` the value is silently ignored (pulse uses a hard-coded `duration: 1.0`). Caller has no way to know they configured a knob with no effect. Not a bug, just API noise. Either drop the parameter or document the Reduce-Motion override in the doc comment.

#### A7-DS-02 (LOW) — `BBTBSpinner` `.onAppear` animation never restarts on `reduceMotion` toggle
`BBTB/Packages/DesignSystem/Sources/DesignSystem/Spinner.swift:78-90`
`reduceMotion` is read once in `.onAppear`; if the user toggles "Reduce Motion" in Settings while the spinner is already mounted (e.g. .connecting state persists across the system setting change), the wrong animation continues. Realistic risk = very low (.connecting is typically transient < few seconds) but worth a `.onChange(of: reduceMotion)` if we ever extend the connecting state. Not blocking for v1.0.

#### A7-DS-03 (LOW) — `DesignSystem.swift` `DS.accent` deprecated alias still present
`BBTB/Packages/DesignSystem/Sources/DesignSystem/DesignSystem.swift:23-24`
`@available(*, deprecated, renamed: "DS.Color.accent")` was added in Phase 12, but `grep -rn "DS\.accent\b"` returns only the two definition-site mentions in DSColor.swift / DesignSystem.swift — i.e. no consumer call-sites remain. Safe to remove now (post-Phase 12 migration complete). Carry-over backlog.

#### A7-DS-04 (LOW) — `PrimaryButtonStyle` / `SecondaryButtonStyle` use literal `0.12s`/`0.97`/`0.92` motion magic numbers
`BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift:45-58, 89-102`
Per UI-SPEC §2.3 pressed motion contract. Two identical 14-line `.scaleEffect/.opacity/.animation` chunks across both styles — small duplication, low value to refactor pre-TF. Note for v1.x: extract a `ViewModifier`. Not blocking.

#### A7-DS-05 (LOW) — `SecondaryButtonStyle` known wire-only Light-mode inversion is documented but visually shipped
`BBTB/Packages/DesignSystem/Sources/DesignSystem/ButtonStyles.swift:64-71`
Comment explicitly flags Phase 12 / D-05 wire-only: secondary CTA is black-pill-on-white in Light mode (visually inverted from the intent). Plan 12-02 Task 9 UAT checklist warns user. TestFlight reviewer may notice. Mention in TF release notes.

### ProtocolEngine

#### A7-PE-01 (MEDIUM) — `XrayFallback.swift` entire module is dead code shipped in app
`BBTB/Packages/ProtocolEngine/Sources/XrayFallback/XrayFallback.swift:1-4`
2-line public enum `XrayFallback { public static let placeholder = true }` whose entire purpose is "Phase 4+ placeholder". Currently:
- `grep -rn "import XrayFallback\|XrayFallback\."` returns **zero** consumers.
- Module is still exposed as a SwiftPM library target (`Package.swift:9,23`).
- Builds into the app binary (small but non-zero — separate object file + module metadata).

Either delete the target (clean) or land xray-core integration. For TestFlight: not a bug, but reviewer doc-trawl risk + literal dead code shipping. Recommend removing the target now; xray-core was carved to v1.1+ per Phase 4 closure.

#### A7-PE-02 (LOW) — `SingBoxBridge.singBoxVersion` constant unread
`BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:9`
`public static let singBoxVersion = "1.13.11"` — `grep -rn "SingBoxBridge\.singBoxVersion"` returns zero hits in source/tests. Either surface it in About / Diagnostics screen (useful for issue reports) or drop it. Drift risk: when libbox.xcframework is bumped, this string can be forgotten and lie. LOW because no consumer is currently misled.

#### A7-PE-03 (LOW) — `LibboxBootstrap.SetupError.failure` discards underlying NSError when non-localizedDescription
`BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/LibboxBootstrap.swift:8-15`
`errorDescription` only reads `err?.localizedDescription`, which for Go-bridged errors is often the generic "The operation couldn't be completed". `userInfo` / `code` / `domain` are not surfaced. For startup debug from device logs this matters because `LibboxSetup` failure is fatal. Not blocking for TF (device logs do show the raw NSError via the throw), but worth a 3-line fix to include `(domain, code, userInfo)` for self-debug.

### ProtocolRegistry

#### A7-PR-01 (LOW) — Public `register()` allows post-launch handler swap
`BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift:12-15`
`register(_:)` overwrites any prior entry for the same `H.identifier` without a check, and is `public`. Real call sites only run during `BBTB_iOSApp.init()` / `BBTB_macOSApp.init()`, but nothing prevents a feature module from swapping `VLESSRealityHandler.self` at runtime by accident. Defensive options:
- `precondition(handlers[H.identifier] == nil, "...")` to crash-fast on duplicate register
- or expose only an `internal` register + a public `register(initialHandlers:)` one-shot

Not a TF blocker; flag as v1.x hardening.

#### A7-PR-02 (LOW) — Singleton with `@unchecked Sendable` + `NSLock` is fine, but `handler(for:)` returns metatype that is itself Sendable, while caller may use it across actors without strict-concurrency annotations
`BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift:6, 17-20`
Metatypes are Sendable in Swift 6 strict mode; the lock here is sufficient. Note only — no fix needed.

### Localization

#### A7-LC-01 — L10n key drift check: clean ✓
`BBTB/Packages/Localization/Sources/Localization/L10n.swift` vs `Resources/Localizable.xcstrings`
Mechanical diff:
- L10n.swift `tr("...")` references: 234 unique keys (after subtracting one doc-comment match).
- xcstrings catalog: 234 keys.
- Missing-in-catalog: **0**.
- Unused-in-Swift: **0**.

Either a recent housekeeping pass closed all drift, or the codegen discipline is tight. No finding.

#### A7-LC-02 (LOW) — Phase-numbering in comments references "Phase 12 telemetry pipeline (TELEM-03)" but current state is Phase 13
`BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:14`, also see L10n.swift Phase 6e comment about lazy migration
Phase milestone comments are useful for archaeology but drift fast. Not a bug. Carry to a v1.x doc pass.

### CrashReporter

#### A7-CR-01 (LOW) — `_test_inject` is `public` (not `internal`) under `#if DEBUG`
`BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:75-79`
Comment correctly notes "Test hook" and gates with `#if DEBUG` so it does not ship in Release. But `public` exposes it to any DEBUG-built consumer (e.g. host app linking the DEBUG framework), not just the unit-test target. `@testable import CrashReporter` would let tests reach an `internal` symbol. Minor — flip to `internal` and drop the `@testable` requirement-cost from the comment. Not blocking for TF since Release build elides it entirely.

#### A7-CR-02 (LOW) — `CrashReporter.didReceive(_:[MXMetricPayload])` silently drops payloads
`BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:35-38`
`log.debug` only, and `MXMetricPayload` is not persisted. The doc comment correctly notes "Phase 12 telemetry pipeline" but those payloads (CPU / hang / battery) are exactly the kind of post-TF feedback that helps triage v1.0. Not a bug for v1.0 — Phase 1 scoped out by design. Noting for visibility.

#### A7-CR-03 (LOW) — `isoFormatter` not thread-safe by Apple contract; `saveDiagnostic` reachable from MetricKit delivery (non-main)
`BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:52-65, 66-70`
`ISO8601DateFormatter` *is* documented as thread-safe (since iOS 10), so this is actually fine. Just calling it out so the next reviewer doesn't re-flag — the historical "NSDateFormatter not thread-safe" gotcha does not apply to `ISO8601DateFormatter`.

---

## Notes

- **L10n.swift discipline** — zero key drift between accessors and the xcstrings catalog. Catalog stays in lockstep, plural-aware `tr(key, args...)` overload is wired correctly for `%@ / %d` substitution. No finding.
- **DesignSystem token coverage** — DSColor.swift exposes 16 tokens, all dynamic via `UIColor { traits in ... }`. The "always-white" token (Dark==Light==#FFFFFF) is intentional and correctly named — was a Phase 12 D-05 fix for accent-button text legibility. No hex typos spotted.
- **`@unchecked Sendable` audit** — both `ProtocolRegistry` and `CrashReporter` use `@unchecked Sendable` with `NSLock` guarding all mutable state. Correct pattern; no race conditions visible.
- **`@_exported import`** — used in two places (`PhosphorReexport.swift`, `SingBoxBridge.swift`). Both correct and documented; no risk for TestFlight.
- **Force unwraps** — searched the 12 files: zero `as!` and zero `!`-unwrap of optionals in shipping code paths. Clean.
- **`@State` / `@StateObject` misuse** — `BBTBSpinner` uses `@State` for animation values only (correct), no `@StateObject` in scope. No leaks.
- **Force-cast / fatalError audit** — none in scope.
- **Dead-code carve-outs (Phase 13 backlog suggestion):**
  - DELETE: `XrayFallback` SwiftPM target (A7-PE-01) — 2-line dead module shipping in binary.
  - DELETE: `DS.accent` deprecated alias (A7-DS-03) — Phase 12 migration complete, zero consumers.
  - DELETE or USE: `SingBoxBridge.singBoxVersion` constant (A7-PE-02) — surface in About screen or drop.

**Severity rollup:** 0 CRITICAL · 0 HIGH · 1 MEDIUM (XrayFallback dead module shipping) · 8 LOW. Expected distribution for leaf-tier sweep. None are TestFlight blockers.
