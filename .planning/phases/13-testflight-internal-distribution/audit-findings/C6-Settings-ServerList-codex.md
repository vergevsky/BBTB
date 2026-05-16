# C6 — SettingsFeature + ServerListFeature audit (Codex 5.5)

**Scope:** AppFeatures/Sources/SettingsFeature + ServerListFeature
**Files audited:** 31
**Total findings:** 5 (CRITICAL: 1, HIGH: 0, MEDIUM: 3, LOW: 1)

## Findings (grouped by package)

### SettingsFeature

#### [CRITICAL] C6-001: Diagnostics export leaves IPv6 addresses unmasked
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:70`, `:112`
- **Dimension:** DiagnosticsExporter IP-masking / privacy
- **Description:** `prepareLog()` masks only IPv4 via `maskIPv4(_:)`; the implementation explicitly leaves IPv6 unchanged. The exported header says "IP addresses masked," but `::1`, `fe80::…`, and public IPv6 endpoint/client addresses remain in the shared log.
- **Why it matters:** TestFlight diagnostics can leak user IPs or server IPs whenever sing-box emits IPv6 addresses. This is a direct privacy regression in the telemetry/export path.
- **Suggested fix:** Add IPv6 masking before writing the temp file, ideally with a tested parser/regex that handles compressed IPv6, IPv4-mapped IPv6, zone IDs, and optional ports. Update tests from "IPv6 unchanged" to "IPv6 masked."

#### [MEDIUM] C6-002: Diagnostics tail cap reads the entire log first and is character-based, not byte-based
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/DiagnosticsExporter.swift:61`, `:63`, `:70`
- **Dimension:** DiagnosticsExporter performance / correctness
- **Description:** The code loads the whole `sing-box.log` into memory, then applies `String.suffix(tailByteCap)`. `tailByteCap` is documented as bytes, but `String.suffix` counts characters.
- **Why it matters:** If the app-group log grows large, preparing diagnostics can spike memory and block longer than expected. The exported "2 MB" tail can also exceed 2 MB for multibyte content.
- **Suggested fix:** Tail the file at the byte level using `FileHandle`, seek from EOF by `tailByteCap`, then decode with a safe boundary strategy before masking.

#### [MEDIUM] C6-003: Force-update cooldown is process-local and can be bypassed by app restart
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:148`, `BBTB/Packages/RulesEngine/Sources/RulesEngine/RulesEngineCoordinator.swift:151`
- **Dimension:** Force-update state machine / cooldown enforcement
- **Description:** UI cooldown (`cooldownExpiresAt`) and coordinator cooldown (`lastForceUpdateAt`) are both in-memory only. Restarting the app resets both and allows another immediate force update.
- **Why it matters:** The documented D-10 cooldown is intended to protect mirrors/VPS from repeated manual refreshes. A user can bypass it by force-quitting/reopening during TestFlight.
- **Suggested fix:** Persist the last force-update attempt timestamp, preferably in standard defaults or app-group defaults depending on ownership, and have `RulesEngineCoordinator.forceUpdate()` enforce against persisted wall-clock state.

#### [LOW] C6-004: Cooldown timer can survive a deallocated temporary SettingsViewModel
- **Location:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:171`, `:185`, `:509`
- **Dimension:** Force-update timer lifecycle
- **Description:** `deinit` does not invalidate `cooldownTimer`; cleanup depends on explicit `teardown()`. The scheduled repeating timer is retained by the run loop, and the closure captures `self` weakly, so if a temporary VM deallocates without `teardown()`, the timer can keep firing with `self == nil`.
- **Why it matters:** In production the app-level `@StateObject` likely lives for process lifetime, but previews/tests or future ownership changes can leak a repeating timer.
- **Suggested fix:** Move timer cleanup into a nonisolated-safe deinit strategy, or replace `Timer` with a cancellable `Task` stored on the MainActor and cancelled from teardown/deinit.

### ServerListFeature

#### [MEDIUM] C6-005: `loadFromStore()` debounce can suppress required post-delete UI reloads
- **Location:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:335`, `:377`, `:395`
- **Dimension:** SwiftData lifecycle / CRUD freshness
- **Description:** `deleteServer()` and `confirmDeleteSubscription()` rely on `await loadFromStore()` after saving, but `loadFromStore()` returns early if the last load was within 100 ms. A delete immediately after appear/refresh can save successfully while leaving `sections` stale.
- **Why it matters:** The UI can continue showing deleted servers/subscriptions until a later refresh, and actions on those stale rows will hit missing SwiftData objects or confusing no-op paths.
- **Suggested fix:** Add a `force` parameter for mutation-driven reloads, or split debounce into a public refresh path while CRUD operations call an unconditional store reload.

## Notes

- `@AppStorage` suite usage in `SettingsViewModel` matches the provided extension-read pattern: `muxEnabled`, `stunBlockEnabled`, `utlsFingerprint`, `routingRulesEnabled`, and macOS `macOSDisableEnforceRoutes` use the App Group suite. Standard-suite keys appear consistent with the stated main-app-only keys.
- I did not find `@Query` usage in these two packages. The known UUID optional predicate anti-pattern is mostly avoided via fetch-all + Swift filtering; direct predicates are on non-optional IDs / booleans.
- No build or tests were run, per request.

**Verdict:** Block TestFlight on C6-001. The other items are fix-before-release or accept-with-ticket depending on schedule.
