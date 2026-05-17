# C6 — SettingsFeature + ServerListFeature (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 3 (0/2/1/0)

## Plan 07 closure verification
- T-C-A6H1' ServerDetail snapshot+rollback: FAIL

## Critical
No critical findings in this SettingsFeature + ServerListFeature pass.

## High

### C6-4-001: ServerDetail rollback snapshots the already-mutated picker value
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerDetailViewModel.swift:100`
- **Dimension:** Correctness / UI-store divergence
- **Description:** The Plan 07 fix intends to snapshot the previous transport before persisting, then restore it on `context.save()` failure. In the actual call chain, `TransportPicker(selection: $viewModel.selectedTransport)` mutates `selectedTransport` first, then `.onChange(of: viewModel.selectedTransport)` calls `applyTransportSelection(new)` (`ServerDetailView.swift:96-99`). By the time `applyTransportSelection` runs, `let previous = selectedTransport` at `ServerDetailViewModel.swift:100` reads the new picker value, not the persisted previous value. Both failure branches then assign `selectedTransport = previous` (`ServerDetailViewModel.swift:108`, `121`), which leaves the UI on the failed value.
- **Why HIGH:** This is the same user-visible inconsistency A6'-3-001 flagged: SwiftData can reject the save, the alert appears, but the picker still displays the unpersisted transport. The user can reconnect believing the override changed while the stored server continues using the old transport.
- **Fix:** Pass the SwiftUI `old` value into the VM, e.g. `.onChange { old, new in Task { await viewModel.applyTransportSelection(new, previous: old) } }`, or replace the public mutable binding with an explicit setter that snapshots before mutating `selectedTransport`. Add a save-failure/unit test that simulates the binding already being at `new` before `applyTransportSelection` runs.

### C6-4-002: IPv4-mapped IPv6 literals still leak in diagnostics exports
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:71`
- **Dimension:** Privacy / diagnostics export redaction
- **Description:** `prepareLog` still masks IPv4 before IPv6: `maskIPv6(maskIPv4(tail))`. For IPv4-mapped IPv6 addresses, that transforms `::ffff:192.0.2.128` into `::ffff:192.0.2.xxx`. The IPv6 regexes at `DiagnosticsExporter.swift:149-158` only accept hex groups, so they no longer match the dotted-quad tail and the exported support log keeps the IPv6 wrapper plus the first three IPv4 octets. The same applies to full mapped forms such as `0:0:0:0:0:ffff:192.0.2.128`.
- **Why HIGH:** Diagnostics are explicitly prepared for user sharing. The current masking still exposes endpoint family and IPv4 network prefix for mapped IPv6 addresses in logs.
- **Fix:** Mask IPv6 before IPv4, or add dotted-quad IPv6 alternatives before the IPv4 masking pass. Add tests for `::ffff:192.0.2.128`, `0:0:0:0:0:ffff:192.0.2.128`, and `::ffff:c000:0280`.

## Medium

### C6-4-003: Routing rules toggle has no live-apply path
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/AdvancedSettingsView.swift:77`
- **Dimension:** UX / configuration consistency
- **Description:** The routing rules toggle writes `app.bbtb.routingRulesEnabled` through App Group `@AppStorage` (`SettingsViewModel.swift:94-95`), and the extension reads that value when `SingBoxConfigLoader.expandConfigForTunnel` builds config (`SingBoxConfigLoader.swift:420-430`). Unlike auto-reconnect (`SettingsView.swift:73-75`) and macOS enforce routes (`SecuritySection.swift:39-42`), this toggle has no `.onChange` handler that reprovisions or reloads the active profile.
- **Why MEDIUM:** A user can turn routing rules off while connected and still run the old rule-set-injected config until the next reconnect/reprovision. That is a visible settings consistency gap, especially because the toggle sits next to force-update/rules controls and does not say "next connection only."
- **Fix:** Either add an explicit "applies on reconnect" footer, or implement a live-apply path that asks the main screen/provisioning layer to rebuild the current selected profile and reconnect/reload safely.

## Low
No low findings in this pass.

## Notes
- The new ServerDetail alert binding itself is structurally present: `persistError != nil` drives `.alert`, and dismissing clears `persistError` (`ServerDetailView.swift:114-121`). The failure is rollback state capture, not alert presentation.
- T-C7' remains closed in this scope: mutation paths call `loadFromStore(force: true)` after delete, subscription delete, pull-to-refresh, and silent foreground refresh (`ServerListViewModel.swift:278`, `313`, `339`, `383`).
- I did not re-report the previous subscription merge stale-config finding as open in this file: Plan 07 updated `SubscriptionMergeService`, and that file is outside the two requested feature directories.
