# C9 — LOW packages (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 8 (0/0/1/7)

## Critical
No critical findings found in this LOW-package pass.

## High
No high findings found in this LOW-package pass.

## Medium
### C9'-3-001: `CrashReporter` pulls in `PacketTunnelKit` and libbox transitively just for one App Group URL
- **Location:** `BBTB/Packages/CrashReporter/Package.swift:9`
- **Dimension:** Hidden coupling / dependency graph
- **Description:** `CrashReporter` depends on `PacketTunnelKit` (`Package.swift:9`, `Package.swift:12`) only because `CrashReporter.saveDiagnostic(_:)` imports `PacketTunnelKit` and reads `AppGroupContainer.crashReportsURL` (`CrashReporter.swift:4`, `CrashReporter.swift:53`). That dependency drags the tunnel stack into a leaf telemetry package; the manifest already has to add libbox-related linker settings in the test target because of the chain `CrashReporter -> PacketTunnelKit -> SingBoxBridge -> Libbox` (`Package.swift:16`).
- **Why MEDIUM:** This is not a runtime crash, but it is a real package-boundary smell before TestFlight: a crash reporter now inherits tunnel/linker baggage and any future PacketTunnelKit init/link issue can break a telemetry-only package. It also makes crash reporting harder to reuse from app-only contexts.
- **Suggested fix:** Move App Group path constants into a tiny shared storage/support package, or inject the crash-report directory URL into `CrashReporter` during app startup. Keep `CrashReporter` free of `PacketTunnelKit` and libbox transitive dependencies.

## Low
### C9'-3-002: `XrayFallback` is a shipped public placeholder with no consumers
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/XrayFallback/XrayFallback.swift:2`
- **Dimension:** Dead code / public API hygiene
- **Description:** The whole target is a public enum with `placeholder = true` (`XrayFallback.swift:2`, `XrayFallback.swift:3`), and the package exports it as a library product (`ProtocolEngine/Package.swift:9`, `ProtocolEngine/Package.swift:22`). Repo search found no source consumers outside the declaration/package surface.
- **Why LOW:** It is harmless at runtime, but it ships a meaningless public symbol and keeps a Phase 1/Phase 4+ roadmap stub in the Phase 13 package graph.
- **Suggested fix:** Remove the product/target until xray fallback work starts. If a roadmap marker is needed, use planning docs or mark the API unavailable instead of exporting a usable `placeholder` constant.

### C9'-3-003: `SingBoxBridge.singBoxVersion` can drift from the vendored binary
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:9`
- **Dimension:** Dead code / version drift
- **Description:** `public static let singBoxVersion = "1.13.11"` has no repo source references outside its declaration. The vendored binary target is separately declared at `ProtocolEngine/Package.swift:14`, so this string is not mechanically tied to the xcframework contents.
- **Why LOW:** No current consumer is misled, but if the constant is later surfaced in diagnostics/About without an enforced update path, it can report a stale libbox version after a binary bump.
- **Suggested fix:** Either surface it now in diagnostics and add a version-check convention around libbox updates, or remove the constant until there is an actual consumer.

### C9'-3-004: `SingBoxBridge` has an unused `Foundation` import
- **Location:** `BBTB/Packages/ProtocolEngine/Sources/SingBoxBridge/SingBoxBridge.swift:2`
- **Dimension:** Dead code / dependency noise
- **Description:** The file re-exports `Libbox` and declares a simple enum/string constant; no Foundation API is used in the file (`SingBoxBridge.swift:1`, `SingBoxBridge.swift:8`, `SingBoxBridge.swift:9`).
- **Why LOW:** This is minor cleanup, but bridge targets should stay especially lean because they sit on dependency boundaries.
- **Suggested fix:** Remove `import Foundation` after a build confirms no hidden requirement.

### C9'-3-005: `@_exported import` leaks implementation modules through public facades
- **Location:** `BBTB/Packages/DesignSystem/Sources/DesignSystem/PhosphorReexport.swift:14`
- **Dimension:** Hidden coupling / maintainability
- **Description:** `DesignSystem` re-exports `PhosphorSwift` via underscored `@_exported import`, and `SingBoxBridge` does the same for `Libbox` (`SingBoxBridge.swift:1`). The DesignSystem file documents the convenience goal (`PhosphorReexport.swift:3`) and the fact that the attribute is underscored (`PhosphorReexport.swift:10`), but consumers can now silently couple to third-party/generated symbols through unrelated package imports.
- **Why LOW:** This works today and appears intentional, but it makes future icon-family or libbox-wrapper changes wider than they need to be. The Libbox case is the riskier one because it exposes generated gomobile APIs instead of a narrow Swift facade.
- **Suggested fix:** Prefer explicit imports at call sites, or keep the re-exports only with a documented package-level contract that these modules are intentionally part of the public surface.

### C9'-3-006: `ProtocolRegistry.registeredIdentifiers` is public introspection surface with no current source consumer
- **Location:** `BBTB/Packages/ProtocolRegistry/Sources/ProtocolRegistry/ProtocolRegistry.swift:22`
- **Dimension:** Dead code / public API hygiene
- **Description:** `registeredIdentifiers` locks and returns sorted keys (`ProtocolRegistry.swift:22`, `ProtocolRegistry.swift:24`), but repo source search found no consumers outside the declaration. Current app startup registers handlers directly (`BBTB/App/iOSApp/BBTB_iOSApp.swift:74`, `BBTB/App/macOSApp/BBTB_macOSApp.swift:53`), and lookups are done through `handler(for:)` when needed.
- **Why LOW:** It is safe and cheap, but it is public singleton API that appears to exist for tests/debugging rather than production behavior.
- **Suggested fix:** Remove it, make it internal, or document the intended UI/diagnostics consumer before other code starts relying on it.

### C9'-3-007: `CrashReporter` exposes a public initializer despite singleton-only lifecycle comments
- **Location:** `BBTB/Packages/CrashReporter/Sources/CrashReporter/CrashReporter.swift:22`
- **Dimension:** Lifecycle hygiene
- **Description:** The class exposes `public static let shared` (`CrashReporter.swift:16`) and the lifecycle comment says `install()` is called once from app init (`CrashReporter.swift:9`), but `public override init()` lets any consumer create additional `CrashReporter` instances. Each instance has its own `isInstalled` flag (`CrashReporter.swift:19`) and can subscribe itself to `MXMetricManager` (`CrashReporter.swift:28`).
- **Why LOW:** Current app code uses `CrashReporter.shared.install()` only, but the public initializer permits duplicate subscribers in future code/tests, causing duplicate MetricKit callbacks and duplicate crash JSON writes.
- **Suggested fix:** Make the initializer private or internal if singleton-only is the intended lifecycle. If multiple instances are supported, document why and make subscription identity explicit.

### C9'-3-008: `L10n` carries broad public accessor surface beyond demonstrated source use
- **Location:** `BBTB/Packages/Localization/Sources/Localization/L10n.swift:60`
- **Dimension:** Dead code / localization accessor drift
- **Description:** `L10n` exposes every string as hand-written public static accessors, including many non-launch `static var` entries (`L10n.swift:60` onward). A source sweep shows several examples without current app-source consumers, such as `appDisplayName` (`L10n.swift:25`), `actionImportFromClipboard` (`L10n.swift:33`), `alertTunnelErrorTitle` (`L10n.swift:56`), and `settingsRulesViewerSection` (`L10n.swift:351`).
- **Why LOW:** The string catalog itself is consistent, and I did not find the closed C9'-001 duplicate-key issue. The smell is accessor drift: hand-maintained public API can keep growing even when UI call sites move or disappear.
- **Suggested fix:** Treat this as generated surface and document that policy, or add a lightweight localization lint that reports accessors/keys with no source references so stale keys are pruned deliberately.

## Notes
- I did not re-report the closed C9'-001 duplicate localizable key; `Localizable.xcstrings` key drift looked clean in this pass.
- `ProtocolRegistry` and `CrashReporter` both use `NSLock` around their mutable singleton state; I did not find an obvious data race in the scoped files.
- No `fatalError`, `try!`, force unwrap, or force cast appears in the scoped source files themselves. The App Group `fatalError` is in `PacketTunnelKit/AppGroupContainer.swift`, outside this C9 scope, though `CrashReporter` currently reaches it through the dependency noted above.
