# C9 — LOW tier audit (Codex 5.5)

**Scope:** 5 leaf packages
**Files audited:** 13 source/resource files (+5 manifests for dependency sanity)
**Total findings:** 7 (CRITICAL: 0, HIGH: 0, MEDIUM: 1, LOW: 6)

## Findings (grouped by package)

### DesignSystem

#### [LOW] C9-001: PhosphorReexport leaks icon package into all DesignSystem consumers
- **Location:** `BBTB/Packages/DesignSystem/Sources/DesignSystem/PhosphorReexport.swift:14`
- **Dimension:** maintainability
- **Description:** `@_exported import PhosphorSwift` makes Phosphor part of every `DesignSystem` consumer's import surface.
- **Why it matters:** this is hidden coupling to a concrete icon package and makes later icon-family replacement a source/API migration.
- **Suggested fix:** keep if intentional for Phase 12, otherwise stop re-exporting and require explicit `import PhosphorSwift` where `Ph.*` is used.

### ProtocolEngine

#### [LOW] C9-002: XrayFallback ships dead public API
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/XrayFallback/XrayFallback.swift:2`
- **Dimension:** dead-code
- **Description:** `XrayFallback` is a public placeholder with only `placeholder = true` and no repo references outside its declaration/package product.
- **Why it matters:** ships dead public API and a package product before implementation.
- **Suggested fix:** remove the product/target until real xray fallback work starts, or mark it as clearly non-shipping/internal.

#### [LOW] C9-003: SingBoxBridge unused Foundation import
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:2`
- **Dimension:** dead-code
- **Description:** `import Foundation` appears unused in this file.
- **Why it matters:** small dead dependency/import noise in a public bridge target.
- **Suggested fix:** remove the import if a build confirms no dependency.

#### [LOW] C9-004: SingBoxBridge re-exports Libbox transparently
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:1`
- **Dimension:** maintainability
- **Description:** `@_exported import Libbox` intentionally leaks the vendored libbox module through `SingBoxBridge`.
- **Why it matters:** consumers can couple directly to generated libbox APIs instead of the bridge abstraction.
- **Suggested fix:** keep only if this is the desired façade contract; otherwise expose narrow Swift wrappers and make consumers import `Libbox` explicitly only where unavoidable.

### ProtocolRegistry

#### [LOW] C9-005: registeredIdentifiers has no repo references outside declaration
- **Location:** `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift:22`
- **Dimension:** dead-code
- **Description:** `registeredIdentifiers` has no repo references outside its declaration in the reviewed sweep.
- **Why it matters:** public introspection API may be dead surface in a singleton registry.
- **Suggested fix:** remove or downgrade to internal unless tests/debug UI need it.

### Localization

#### [LOW] C9-006: 34 public L10n accessors have no repo references
- **Location:** `BBTB/Packages/Localization/Sources/Localization/L10n.swift:25`
- **Dimension:** dead-code
- **Description:** 34 public `L10n` accessors have no repo references outside `L10n.swift` in the sweep.
- **Why it matters:** generated localization surface is drifting broader than actual app use.
- **Suggested fix:** either accept full-key codegen as policy or prune unused accessors/keys. Examples include `appDisplayName`, `actionImportFromClipboard`, `alertTunnelErrorTitle`, `bannerAllFailed`, `settingsRulesViewerSection`, `onboardingTitle`.

### CrashReporter

#### [MEDIUM] C9-007: CrashReporter depends on PacketTunnelKit unnecessarily
- **Location:** `BBTB/Packages/CrashReporter/Package.swift:9`
- **Dimension:** maintainability
- **Description:** `CrashReporter` depends on `PacketTunnelKit` only to reach `AppGroupContainer.crashReportsURL`.
- **Why it matters:** telemetry/storage now pulls tunnel-kit and libbox transitive baggage into a leaf crash-reporting package; the test manifest already needs libbox-related linker settings because of this coupling.
- **Suggested fix:** move `AppGroupContainer` to a tiny shared support package or inject the crash-report directory URL into `CrashReporter`.

#### [LOW] C9-008: CrashReporter init is public but should be private (singleton-only)
- **Location:** `BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:22`
- **Dimension:** maintainability
- **Description:** `CrashReporter` exposes `public override init()` despite also exposing `shared`.
- **Why it matters:** consumers can create extra MetricKit subscribers and duplicate writes/logs outside the singleton lifecycle.
- **Suggested fix:** make init non-public/private if singleton-only is intended.

## Notes

- No `fatalError`, force unwrap, `try!`, or `as!` found in the 13 scoped source/resource files.
- L10n key drift is clean: 234 code `tr(...)` keys and 234 `Localizable.xcstrings` keys, with 0 missing and 0 extra after excluding doc-comment examples.
- CrashReporter is not a Sentry adapter and not 100% no-op: both app targets call `CrashReporter.shared.install()`, it subscribes to MetricKit, saves `MXDiagnosticPayload` JSON into App Group crash reports, and ignores `MXMetricPayload`. No remote/Sentry SDK wiring found.
