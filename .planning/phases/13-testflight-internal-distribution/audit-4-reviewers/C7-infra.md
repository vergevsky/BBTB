# C7 — FrontingEngine + DeepLinks + KillSwitch + TransportRegistry (Codex 5.5)
**Baseline:** ccbce8a
**Total findings:** 5 (0/1/3/1)

## Plan 07 closure verification
- T-B6' FrontingConfigApplier tag-scoped apply: PASS
- T-C-C3H2' import/deeplink reentrancy guards: PASS
- C7'-3-001 fronting canonical-IP SSRF guard: FAIL / carry-forward
- C7'-3-002 transport path/host validation: FAIL / carry-forward
- No package-level diffs since `ccbce8a` for this scope: PASS

## Critical
No critical findings in this infra pass.

## High

### C7-4-001: Fronting profile SSRF guard still misses canonical IPv6 encodings of private IPv4
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:132`
- **Dimension:** Security / fronting-profile SSRF guard
- **Description:** `validateProfile(_:)` applies `isPrivateOrLoopback(_:)` to `connectHost`, `sniHost`, and `httpHost` (`FrontingConfigApplier.swift:137-140`), but the guard remains string-prefix based (`FrontingConfigApplier.swift:148-203`). It handles dotted IPv4 prefixes and `::ffff:a.b.c.d` (`FrontingConfigApplier.swift:197-200`) but not numeric IPv6 literal forms such as `::ffff:7f00:1`, NAT64 well-known-prefix forms such as `64:ff9b::7f00:1`, or 6to4 encodings such as `2002:0a00:0001::`. The accepted `connectHost` is then written directly into outbound dial targets by adapters (`CloudflareAdapter.swift:55-61`, same pattern in Fastly and Custom).
- **Why HIGH:** This is the same canonical-literal bypass class fixed in ConfigParser during Plan 07, but FrontingEngine keeps an inline implementation. A malicious or compromised admin profile can steer the tunnel toward loopback, RFC1918, link-local, or carrier-translated private targets while still passing the fronting-profile validator.
- **Fix:** Replace `isPrivateOrLoopback(_:)` with numeric parsing via `Network.IPv4Address` / `Network.IPv6Address`, normalize IPv4-mapped IPv6, and reject NAT64 `64:ff9b::/96`, 6to4 `2002::/16`, Teredo if accepted by Foundation, IPv4-compatible IPv6, ULA, link-local, multicast, loopback, and unspecified addresses. Add tests for `::ffff:7f00:1`, `[::ffff:7f00:1]`, `64:ff9b::a9fe:a9fe`, and `2002:0a00:0001::`.

## Medium

### C7-4-002: Deep-link routing can run before the detached handler registration completes
- **Location:** `BBTB/App/iOSApp/BBTB_iOSApp.swift:228`
- **Dimension:** Correctness / cold-start deep-link race
- **Description:** iOS and macOS create `DeepLinkRouter`, then register `ImportHandler` inside a detached task (`BBTB_iOSApp.swift:225-230`, `BBTB_macOSApp.swift:161-166`). `routeOrBuffer` only gates on `viewModel.initialManagersApplied` (`BBTB_iOSApp.swift:356-360`, `BBTB_macOSApp.swift:303-310`); once that flag is true, it calls `handleDeepLink` immediately. If `.onOpenURL` / Universal Link delivery wins the race against the detached registration, `DeepLinkRouter.handle` iterates an empty `handlers` array and throws `.unhandled` (`DeepLinkRouter.swift:55-72`, `DeepLinkRouter.swift:108-121`).
- **Why MEDIUM:** This does not bypass validation or leak data, but it can make the first import link after cold launch fail nondeterministically. The Plan 07 reentrancy guard is present in `MainScreenViewModel.handleDeepLink` (`MainScreenViewModel.swift:1271-1284`), but it does not establish a registration-ready ordering.
- **Fix:** Register handlers synchronously during app initialization, or make `BBTBRootView` await a `deepLinkRouterReady` task before flushing `pendingDeepLink`. Another low-impact option is a `DeepLinkRouter.bootstrap(defaultHandlers:)` initializer that installs the static handler list before the router is exposed to the view tree.

### C7-4-003: Transport path/host values still flow into sing-box blocks without syntax validation
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/TransportParamParser.swift:47`
- **Dimension:** Security / malformed transport metadata
- **Description:** `TransportParamParser` accepts any non-empty `path` for WS, HTTP, and HTTPUpgrade and any optional `host` string for WS/HTTPUpgrade (`TransportParamParser.swift:47-66`). The handlers then emit those values directly into sing-box JSON: WS `path` and `headers.Host` (`WSTransportHandler.swift:56-70`), HTTP `path` (`HTTPTransportHandler.swift:51-55`), and HTTPUpgrade `path` / `host` (`HTTPUpgradeTransportHandler.swift:52-61`). There is no leading-slash check, length bound, control-character rejection, or authority-shape validation for `host`.
- **Why MEDIUM:** The immediate effect is malformed outbounds and confusing import/connect failures. If sing-box or a future transport path forwards these strings into HTTP/WS request construction before strict validation, CR/LF/NUL and authority-shaped host payloads become header/path injection risk.
- **Fix:** Validate at parse time and re-check at handler boundaries: paths must start with `/`, fit a bounded length, and reject NUL/CR/LF; hosts must be valid host authorities without whitespace, schemes, paths, control characters, or unexpected ports. Add negative tests for `%0d%0a`, missing leading slash, oversized path, and `host=example.com%0d%0aX:y`.

### C7-4-004: Fallback chain consumes cooldowned profiles permanently until reset
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingFallbackChain.swift:69`
- **Dimension:** Correctness / CDN fallback recovery
- **Description:** `nextEndpoint` reserves a slot by advancing `cursor` before awaiting the failure cache (`FrontingFallbackChain.swift:63-75`). When `shouldSkip` returns true, the method continues without rolling the cursor back (`FrontingFallbackChain.swift:76-78`), so a cooldowned profile is consumed for this chain pass. Exhaustion returns `(nil, true)` (`FrontingFallbackChain.swift:83-84`) and only `reset()` reconsiders earlier profiles (`FrontingFallbackChain.swift:105-108`). The comment says the slot is "rolled back if the profile turns out to be in cooldown" (`FrontingFallbackChain.swift:56-61`), but the implementation does not roll back.
- **Why MEDIUM:** The pre-advance pattern is reasonable for actor reentrancy, but the recovery contract is narrower than documented. In a long-running app session, a profile that was cooldowned when first seen remains unavailable even after the cooldown expires unless the caller resets the chain. That can turn temporary CDN failure into avoidable exhaustion.
- **Fix:** Either document the monotonic-consumption contract explicitly and require caller reset after exhaustion / time passage, or add an exhaustion pass that rechecks previously consumed profiles whose cooldown may have expired.

## Low

### C7-4-005: KillSwitch uses `nonisolated(unsafe)` mutable global for a value that is never overridden
- **Location:** `BBTB/Packages/KillSwitch/Sources/KillSwitch/KillSwitch.swift:61`
- **Dimension:** Swift 6 concurrency / API hygiene
- **Description:** `KillSwitch.appGroupSuiteName` is declared as `public nonisolated(unsafe) static var`, with a comment saying it is written once at startup (`KillSwitch.swift:59-61`). A source search found no write sites; `platformShouldDisableEnforceRoutes()` only reads it (`KillSwitch.swift:63-69`). This opts out of strict concurrency checking for a value that is effectively constant today.
- **Why LOW:** No current behavioral bug, but the unsafe mutable global weakens future compiler help and the comment sends maintainers looking for a setup hook that does not exist.
- **Fix:** Change it to `public static let appGroupSuiteName = "group.app.bbtb.shared"`. If a future test/app needs override support, add an explicit setter with documented single-threaded setup semantics.

## Notes
- T-B6' remains structurally closed: `FrontingConfigApplier.apply(... targetTag:)` skips non-matching outbound tags before adapter mutation (`FrontingConfigApplier.swift:58-67`).
- T-C-C3H2' remains structurally closed at the app entry point: paste/file imports and deep-link imports both guard `importInProgress` before starting work (`MainScreenViewModel.swift:898-903`, `MainScreenViewModel.swift:1276-1282`).
- DeepLinks URL logging remains redacted to scheme and host only (`DeepLinkRouter.swift:102-106`, `ImportHandler.swift:56-63`).
- TransportRegistry app startup registration includes all five handlers on both iOS and macOS (`BBTB_iOSApp.swift:83-87`, `BBTB_macOSApp.swift:62-66`).
