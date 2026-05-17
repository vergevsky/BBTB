# A6' — MEDIUM tier re-audit (Opus 4.7)

**Baseline:** commit 55523dd (`fix(13-03/T-A2): remove unsafe template paths in all 6 protocols`); HEAD c260e69 (doc commit) — no production code drift since baseline.

**Scope reviewed (read-only):**
- `BBTB/Packages/AppFeatures/Sources/SettingsFeature/` — 17 files
- `BBTB/Packages/AppFeatures/Sources/ServerListFeature/` — 16 files
- `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/` — 9 files
- `BBTB/Packages/DeepLinks/Sources/DeepLinks/` — 6 files (incl. Handlers/)
- `BBTB/Packages/KillSwitch/Sources/KillSwitch/` — 1 file
- `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/` — 7 files (incl. Handlers/)
- `BBTB/Packages/Protocols/{VLESSReality, VLESSTLS, Trojan, Shadowsocks, Hysteria2, TUIC}/Sources/<Proto>/` — 12 files (6 × ConfigBuilder + 6 × Handler)

---

## Closure Verification

| Closure | Package | Verdict | Notes |
|---|---|---|---|
| **T-B6** killSwitchEnabled default `true` consistency | `SettingsFeature`, `MainScreenFeature`, `KillSwitch` | **PASS** | 4 sites confirmed: `SettingsViewModel:36` (`@AppStorage` default `true`), `SettingsViewModel:602` (`?? true`), `ConfigImporter:1426` (`?? true`), `MainScreenViewModel:204` & `:971` (`?? true`). `KillSwitch.swift:14` doc-comment matches. R4 invariant maintained. |
| **T-B7** ImportHandler path tightening | `DeepLinks/Handlers/ImportHandler` | **PASS** | Line 50 enforces `path == "/import" \|\| path == "/import/" \|\| hasPrefix("/import/")`. Rejects `/important`, `/importer`, `/importevil`. Redundant `/import/` exact match harmless (also covered by hasPrefix). |
| **T-B7** URL log redaction | `DeepLinks/{ImportHandler, DeepLinkRouter}` | **PASS** | Both loggers (`ImportHandler:62`, `DeepLinkRouter:105`, `:119`) emit only `scheme=… host=…` with `privacy: .public`. No `url`-as-`%@` logging anywhere in `DeepLinks/`. Subscription tokens redacted. |
| **T-B10** CDN adapter allowlist (3 adapters) | `FrontingEngine/{Cloudflare, Fastly, CustomCDN}Adapter` | **PASS** | All 3 enforce `guard type_ == "vless" \|\| type_ == "trojan" else { return false }` (CloudflareAdapter:35-37; FastlyAdapter:26-28; CustomCDNAdapter:23-25). Reality + Vision additionally rejected within allowlisted types. Group outbounds (`direct`/`urltest`/`selector`/`dns`) no longer mutated. |
| **T-B10** FrontingConfigApplier throws + validateProfile | `FrontingEngine/FrontingConfigApplier` | **PASS** | Both `apply(json:profile:adapter:)` (line 39) and `apply(outbound:profile:adapter:)` (line 93) call `try validateProfile(profile)` upfront. `isPrivateOrLoopback` (127-183) now covers IPv4 RFC1918, CGNAT 100.64/10, multicast 224-239, reserved 240-255, `.local` mDNS, IPv6 link-local fe80::, ULA fc/fd, IPv4-mapped IPv6, bracketed IPv6, port range. |
| **T-A2** 6 protocols template-path removal | All 6 protocol `ConfigBuilder.swift` | **PARTIAL** | Swift code clean — `Inputs`, `BuilderError`, `buildSingBoxJSON`, `loadTemplate`, `mutatePort` symbols **absent** in all 6 files. Each file is now thin namespace `enum ConfigBuilder` with only `buildOutbound(from:transport:tag:) -> [String:Any]`. **HOWEVER** — see Regression R-001 below: dead JSON template resources + Package.swift `.process(...)` declarations remain in 5 of 6 protocols. |
| **T-B11** PoolBuilder pre-validation | `ConfigParser/PoolBuilder` | **PASS** | `isValidPoolEntry` is `private static` (line 274). Validation matrix covers all 6 protocols' invariants (port 1...65535, non-empty host, protocol-specific keys, SS-method whitelist via `ShadowsocksURIParser.supportedSSMethods`, TUIC enum-validity via `ParsedTUIC.supportedCongestionControl/UDPRelayMode`). Degenerate path (line 121) correctly tests `outbounds.count == 1`, not `truncated.count`. Empty-after-filter case (line 114) throws `.noSupportedServers`. |

---

## New Findings (grouped by package)

### Protocols/* (6 protocols)

#### A6'-001 — MEDIUM — Dead JSON template resources still ship in app bundle (5 protocols)

**Files:**
- `BBTB/Packages/Protocols/VLESSTLS/Sources/VLESSTLS/Resources/SingBoxConfigTemplate.vless-tls.json`
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-tcp.json`
- `BBTB/Packages/Protocols/Trojan/Sources/Trojan/Resources/SingBoxConfigTemplate.trojan-ws.json`
- `BBTB/Packages/Protocols/Shadowsocks/Sources/Shadowsocks/Resources/SingBoxConfigTemplate.shadowsocks.json`
- `BBTB/Packages/Protocols/Hysteria2/Sources/Hysteria2/Resources/SingBoxConfigTemplate.hysteria2.json`
- `BBTB/Packages/Protocols/TUIC/Sources/TUIC/Resources/SingBoxConfigTemplate.tuic.json`
- Each protocol's `Package.swift` still declares `.process("Resources/SingBoxConfigTemplate.*.json")` in `resources:` array.

**Observation:** T-A2 removed `buildSingBoxJSON(from: <Proto>Inputs)` + `loadTemplate(...)` from Swift sources, but the JSON template files and their `Package.swift` `.process(...)` directives are still present. `grep -r "Bundle.module" /Packages/Protocols/ --include="*.swift"` returns zero references — no live code path loads them. Resources are still bundled into `<Proto>_<Proto>.bundle` and consume install footprint (~5-10 KB total). For VLESSReality the cleanup was complete (no `Resources/` directory, no `Package.swift` resource entry); other 5 protocols are halfway.

**Severity rationale:** dead artifacts contain `${VLESS_FLOW}` / `${PASSWORD}` style placeholders — they cannot be exploited (no code reads them), but their presence misleads future readers and contradicts T-A2's documented "Dead code in production" claim. Pre-TestFlight optics matter: an external reviewer reading the bundle will see `SingBoxConfigTemplate.*.json` and infer the template-injection surface still exists.

**Suggested fix (one-line per protocol):** `rm BBTB/Packages/Protocols/<Proto>/Sources/<Proto>/Resources/SingBoxConfigTemplate.*.json` + delete the matching `.process(...)` lines from each `Package.swift` (and the `resources:` array entirely if it becomes empty).

#### A6'-002 — LOW — VLESSReality `transport` parameter accepted but silently ignored without warning log

**File:** `BBTB/Packages/Protocols/VLESSReality/Sources/VLESSReality/ConfigBuilder.swift:27-33`

**Observation:** D-03 doc-comment says "transport overlay is silently ignored". Caller PoolBuilder always passes `.tcp`, so today's invocation is harmless. But if a future caller (e.g. ServerDetail TransportPicker that lacks per-protocol filtering) accidentally passes `.ws`, no log would emit and the user would see "transport saved" UI feedback yet the actual built outbound would be TCP. Defense-in-depth: a `Logger.warning` when `case .tcp = transport` is false would surface miswiring fast.

**Pre-TestFlight blocker?** No — current callers (PoolBuilder + ServerDetailViewModel) correctly route. Future regression risk only.

---

### FrontingEngine

#### A6'-003 — LOW — `apply(outbound:profile:adapter:)` is unreachable but now `throws`

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:87-95`

**Observation:** The inline variant is dead code (zero callers in Sources + Tests across the repo; `grep -rn "apply(outbound" --include="*.swift"` returns empty). T-B10 added `try validateProfile(profile)` + `throws` to its signature. No regression today, but the symbol exists and is `public` — could mislead a future implementer into thinking inline path is supported. Two options: (a) delete the dead overload entirely; (b) add doc-comment "v1.1+ planned wiring, currently unused".

#### A6'-004 — LOW — `isPrivateOrLoopback` IPv6 ULA heuristic over-blocks legitimate hostnames

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:171-174`

```swift
if (lower.hasPrefix("fc") || lower.hasPrefix("fd")) && lower.contains(":") {
    return true
}
```

**Observation:** The check guards IPv6 ULA fc00::/7. The `contains(":")` discriminator distinguishes hostname `fc-cdn.example.com` (no colon → allowed) from `fc00::1` (colon → blocked). Correct in syntax. However a host string like `fc-edge.example.com:443` (host with port — legal in some sing-box configs) would be misclassified as ULA. ConfigParser stores port separately so `connectHost` itself shouldn't carry `:port`, but defensive: also gate on `lower.first` being a hex digit `[0-9a-f]` to reduce false positives (`fcN:...` where N is hex).

**Severity rationale:** ConfigParser splits port; admin-supplied JSON unlikely to embed port in `connectHost`. Edge case only.

#### A6'-005 — INFO — FrontingFailureCache `persist()` uses `try?` swallow on encode failure

**File:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFailureCache.swift:104-108`

**Observation:** JSONEncoder().encode on `[String: FailureRecord]` cannot realistically fail (all fields are `Codable` primitives), but the silent failure path means a corrupted in-memory state would never surface in logs. Adding `os.Logger.error` on failure would be diagnostic gold during early TestFlight. Doc-comment already says "best-effort" so this is intentional; flagging for future telemetry hookup.

---

### SettingsFeature

#### A6'-006 — MEDIUM — `RulesEngineConstants.testFlightInviteURL` still hardcoded "PLACEHOLDER"

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:624-630`

```swift
public static let testFlightInviteURL = URL(string: "https://testflight.apple.com/join/PLACEHOLDER")!
```

**Observation:** `MinAppVersionBanner` tap → `viewModel.openTestFlight()` → opens `https://testflight.apple.com/join/PLACEHOLDER`. For Internal Testing path this banner shouldn't even appear (no `min_app_version` mismatch in v1.0). But if a v1.1 server-side rules update sets `min_app_version` higher than installed version, the banner appears and tapping it lands users on a 404 page → bad onboarding optics.

**Doc-comment says "Phase 12 substitutes real invite"** (line 624 prerequisite), but Phase 12 was redefined to Swift pixel-perfect rebuild, and Phase 13 (TestFlight Internal) didn't update this constant. For Internal-only path: either (a) hide MinAppVersionBanner entirely in v1.0 (suppress `openTestFlight()` action), or (b) wire to a working `https://testflight.apple.com/join/<token>` once App Store Connect generates it.

**Pre-TestFlight blocker?** Borderline. Rules engine won't issue `min_app_version` in v1.0, so banner won't show. But the artifact is a known landmine — a single server-side rules push could expose it.

#### A6'-007 — LOW — `applyEnforceRoutesToManager` re-reads killSwitchEnabled per-iteration

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:585-618` (macOS only)

**Observation:** The `for manager in ours` loop (line 591) does `UserDefaults.standard.object(forKey: "app.bbtb.killSwitchEnabled") as? Bool ?? true` on every iteration (line 602). For single-manager case (typical) this is fine. For multi-manager edge (B-06 multi-manager safe), reading twice would be 2 UserDefaults calls — negligible cost. But more importantly: if a concurrent toggle write happened mid-loop, manager #1 and manager #2 could get different killSwitchEnabled values, causing split-state across our installed profiles. Hoisting the read above the loop guarantees consistency.

**Severity rationale:** Multi-manager scenario is rare (only triggered by previous-version migration leftovers); race window is tiny. LOW.

#### A6'-008 — INFO — `killSwitchEnabled` stored in `UserDefaults.standard`, not App Group suite

**File:** `BBTB/Packages/AppFeatures/Sources/SettingsFeature/SettingsViewModel.swift:36`

**Observation:** Most security toggles (`muxEnabled`, `stunBlockEnabled`, `routingRulesEnabled`, `utlsFingerprint`, `macOSDisableEnforceRoutes`) live in the App Group suite `group.app.bbtb.shared` so the PT extension can read them. `killSwitchEnabled` uses `.standard` (line 36). This is functionally correct because `KillSwitch.apply()` only writes to `NETunnelProviderProtocol` properties (no UserDefaults read by extension). But the asymmetry is non-obvious — a future engineer copying the toggle pattern might miss it and add an extension read that silently returns the default. Doc-comment improvement: explicitly call out "no extension read, main-app only" pattern here as well (currently only present on `cdnFrontingEnabled` and `certPinningEnabled`).

---

### ServerListFeature

#### A6'-009 — LOW — `pingAllServers` defer-block captures `supportedIDs` array by value but spawns unstructured `Task`

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:441-449`

```swift
defer {
    let captureIDs = supportedIDs
    Task { @MainActor [weak self] in
        guard let self else { return }
        for id in captureIDs where self.pingStates[id] == .pinging {
            self.pingStates[id] = .idle
        }
    }
}
```

**Observation:** The `defer` correctly snapshots IDs to avoid capturing SwiftData models. But it spawns an **unstructured** `Task` from `defer`, which the file's own header (line 247) declares "Structured concurrency only — никаких unstructured `Task { ... }` (Pitfall 5)". Functional correctness is preserved (cleanup runs eventually), but the unstructured task is not awaited by `pingAllServers()`, so a unit test that asserts `pingStates` cleanup happens before the function returns will fail intermittently. Pre-TestFlight UAT smoke test that taps "refresh" rapidly during ping could observe lingering `.pinging` rows for a frame.

**Severity rationale:** Visual flicker only; cleanup completes within a few microseconds. LOW.

#### A6'-010 — INFO — `confirmDeleteSubscription` uses fetch-all + Swift filter on `subscriptionID == sub.id`

**File:** `BBTB/Packages/AppFeatures/Sources/ServerListFeature/ServerListViewModel.swift:348-349`

```swift
let allDesc = FetchDescriptor<ServerConfig>()
let linked = ((try? context.fetch(allDesc)) ?? []).filter { $0.subscriptionID == subscription.id }
```

**Observation:** Pattern is correct per `feedback_swiftdata_uuid_predicate.md` memory (UUID? #Predicate silently returns empty on real devices). However for large subscription lists (1000+ servers — admin worst case), this is O(N) on every delete. Pre-TestFlight scope likely <100 servers per subscription, so not a blocker. Future optimization: store `subscriptionID` as `String?` (UUID.uuidString), then `#Predicate { $0.subscriptionIDString == idStr }` works without the SwiftData UUID? bug.

---

### DeepLinks

#### A6'-011 — LOW — `ImportHandler.canHandle` has redundant `/import/` exact match

**File:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:48-52`

```swift
if scheme == "https",
   url.host?.lowercased() == "import.bbtb.app",
   url.path == "/import" || url.path == "/import/" || url.path.hasPrefix("/import/") {
```

**Observation:** `url.path == "/import/"` is already covered by `url.path.hasPrefix("/import/")` (any string is a prefix of itself). Cosmetic redundancy only; correct. Suggest simplifying to `url.path == "/import" || url.path.hasPrefix("/import/")`.

#### A6'-012 — INFO — `DeepLinkError.notImplemented` falls through to "unhandled" localization

**File:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkError.swift:66`

**Observation:** Doc-comment line 53 explicitly says this is a stub fallback; `RemoteTokenFetchHandler.canHandle` always returns false in v0.9, so this branch is unreachable from registered handlers. Pre-TestFlight: safe. If v1+ Phase wires RemoteTokenFetchHandler before adding the L10n key, users would see "не поддерживается, импортируйте через +" for a half-working feature. Flagging for future hookup checklist.

---

### KillSwitch

#### A6'-013 — INFO — `appGroupSuiteName` hardcoded with `nonisolated(unsafe) static var`

**File:** `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:61`

**Observation:** `nonisolated(unsafe) static var appGroupSuiteName: String = "group.app.bbtb.shared"`. The "unsafe" annotation acknowledges this is written once at app startup; the value matches `config.json` app_group. If someone changes `app_group` in `config.json` but forgets this line, macOS enforceRoutes toggle silently reads the wrong suite (always returns nil → defaults to `false` → enforceRoutes always enabled, which is the safer R4 default). No live bug; mitigation works because the failure mode is fail-safe. Worth a code comment "if app_group changes in config.json, update this line" — already present in lines 53-54.

---

### TransportRegistry

#### A6'-014 — INFO — `TCPTransportHandler.supportedProtocols` does not list `"tuic"`

**File:** `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/TCPTransportHandler.swift:21-27`

**Observation:** `supportedProtocols` enumerates 5 protocols (vless-tls, trojan, vless-reality, shadowsocks, hysteria2) but omits "tuic". Comment at line 14 says "all 5 актуальных protocol-идентификаторов" but TUIC was added in Phase 7a (PROTO-08). `TCPTransportHandler.buildTransportBlock` returns nil unconditionally so this only affects UI surfaces that read `supportedProtocols` (e.g. transport picker filtering). For TUIC the picker should be hidden anyway (TUIC is QUIC, no transport overlay). Cosmetic doc/list drift — TUIC could be added for consistency, or TCP's supportedProtocols list could be deleted entirely and inferred from the union of non-TCP handlers' lists.

---

## Regressions Detected

### R-001 — Dead JSON templates remain in 5 of 6 protocols (see A6'-001 above)

T-A2 Swift code cleanup was complete; resource cleanup was not. VLESSReality is fully cleaned (no Resources/ folder, no Package.swift resource entry); other 5 protocols retain dead JSON templates + `.process(...)` declarations. Not a security regression (no code reads them), but a documentation/optics regression versus T-A2's claimed scope.

### R-002 — None of the verified closures introduced behavioral breakage

- **T-B10 throws addition** on `FrontingConfigApplier.apply(outbound:...)` — zero callers in production or tests (`grep` returns empty), so the breaking-change-in-signature is moot. The JSON variant is the live path; its single caller (`ConfigImporter.swift:656`) is wrapped in `try/do/catch` and treats `FrontingError.profileRejected` as graceful degradation (logged warning, falls through to raw JSON).
- **T-B11 PoolBuilder degenerate path** — when user selects exactly 1 server that fails `isValidPoolEntry`, the for-loop skips it (`continue`), `outbounds` ends empty, line 114 throws `.noSupportedServers`. UI sees a clear error rather than a broken urltest-less config; this is the correct failure mode.
- **T-B6 killSwitchEnabled** — 4 read-sites all default `true`; previous mixed `?? false` site (`SettingsViewModel.swift:602`) now reads `?? true` matching the others.
- **T-B7 ImportHandler path** — exact-match + prefix logic correctly rejects `/important`, `/importevil`, accepts `/import`, `/import/`, `/import/foo`. No legitimate URL pattern regressed.

---

## Notes

**Pre-TestFlight gate readiness for MEDIUM tier:**
- All 5 closures (T-B6, T-B7, T-B10, T-A2-Swift, T-B11) verified functionally PASS.
- One closure scope incomplete: T-A2 left dead JSON resources in 5 protocols (A6'-001). MEDIUM severity — not blocking but should be cleaned up before submission for hygiene.
- One pre-existing landmine surfaced: `testFlightInviteURL = "PLACEHOLDER"` (A6'-006). MEDIUM if banner can fire in v1.0; LOW if Internal Testing flow doesn't trip min_app_version logic.
- Twelve LOW/INFO observations document defense-in-depth opportunities, doc drift, and future-engineer footguns — none gate TestFlight.

**No CRITICAL or HIGH findings introduced by Plan 03 fixes.** The codebase is in materially better shape than before this re-audit's baseline. The remaining work is hygiene (dead resources), the TestFlight URL placeholder, and a handful of low-priority polish items.
