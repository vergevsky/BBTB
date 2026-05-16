# C7 — FrontingEngine + DeepLinks + KillSwitch + TransportRegistry audit (Codex 5.5)

**Scope:** 4 network/policy infrastructure packages
**Files audited:** 22
**Total findings:** 8 (CRITICAL: 0, HIGH: 3, MEDIUM: 4, LOW: 1)

## Findings (grouped by package)

### FrontingEngine

#### [HIGH] C7-001: CDN adapters use blacklist instead of allowlist for outbound mutation
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/CloudflareAdapter.swift:24`, `FastlyAdapter.swift:23`, `CustomCDNAdapter.swift:20`
- **Dimension:** logic | security
- **Description:** CDN adapters mutate every outbound except a small blacklist (`tuic`, `hysteria2`, Reality, Vision), then write `server`, `server_port`, and `tls` into the outbound. This includes non-proxy/group outbounds such as `direct` and `urltest` produced by PoolBuilder.
- **Why it matters:** multi-server configs will have `urltest` and `direct` outbounds. Adding proxy-only fields to those outbounds can make sing-box reject the config, or worse, silently alter group/direct behavior. The later local validator appears to allow these outbound types and does not enforce per-type field schemas.
- **Suggested fix:** change adapters to an allowlist, not blacklist: apply only to supported proxy outbound types (`vless`, `trojan`, and only compatible TLS modes). Explicitly return `false` for `direct`, `urltest`, `selector`, `dns`, unknown types, and unsupported transports.

#### [HIGH] C7-002: Single-outbound apply bypasses profile validation
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:81`
- **Dimension:** security
- **Description:** the single-outbound `apply(outbound:profile:adapter:)` path does not call `validateProfile(_:)`.
- **Why it matters:** the batch JSON path rejects some unsafe hosts before overlay, but the public single-outbound API bypasses that guard entirely. Future Phase 11 wiring could accidentally use the faster inline path and accept localhost/private CDN targets.
- **Suggested fix:** make the single-outbound API throwing and call `validateProfile(_:)`, or move validation into `CDNProviderAdapter.applyFronting` so every entry point shares the same guard.

#### [MEDIUM] C7-003: isPrivateOrLoopback misses IPv6 ULA/link-local + port range check
- **Location:** `BBTB/Packages/FrontingEngine/Sources/FrontingEngine/FrontingConfigApplier.swift:107`
- **Dimension:** security
- **Description:** `isPrivateOrLoopback(_:)` only string-prefix blocks a subset of IPv4 and `::1`; it misses IPv6 ULA/link-local (`fc00::/7`, `fe80::/10`), multicast/reserved ranges, bracketed IPv6 literals, `localhost.`, and invalid/empty host values. `connectPort` is also not range-checked.
- **Why it matters:** `FrontingProfile` is admin/subscription-supplied metadata. A malformed or malicious profile can steer dial targets to local/private IPv6 or generate invalid sing-box JSON.
- **Suggested fix:** centralize host validation with the stronger `SubscriptionURLFetcher.isBlockedHost` logic or a Network.framework/IP parser, normalize bracketed IPv6, reject control chars/empty hosts, and require `1...65535` for `connectPort`.

### DeepLinks

#### [HIGH] C7-004: Full inbound deep-link URLs logged publicly
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/DeepLinkRouter.swift:102`, `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:52`
- **Dimension:** security | privacy
- **Description:** full inbound deep-link URLs are logged with `privacy: .public`.
- **Why it matters:** `bbtb://import?url=...` and Universal Links can contain subscription URLs, bearer-like path tokens, or signed query params. Public OSLog entries can leak these via Console, sysdiagnose, or exported diagnostics.
- **Suggested fix:** log only route metadata (`scheme`, normalized host, handler id), or use `.private(mask: .hash)` / `.private` for the full URL. The comment in `DeepLinksLogger.swift:132` already documents this requirement.

#### [MEDIUM] C7-005: Import path prefix accepts /importevil
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:43`
- **Dimension:** security
- **Description:** Universal Link matching accepts any path with `hasPrefix("/import")`, including `/importevil`.
- **Why it matters:** this widens the trusted route surface on `import.bbtb.app` and can dispatch unrelated future paths into the import pipeline.
- **Suggested fix:** require `url.path == "/import"` or `url.path.hasPrefix("/import/")`, depending on whether subpaths are intended.

#### [MEDIUM] C7-006: Deep link payload extracted без envelope length cap
- **Location:** `BBTB/Packages/DeepLinks/Sources/DeepLinks/Handlers/ImportHandler.swift:61`
- **Dimension:** security | performance
- **Description:** the handler extracts `url=` and delegates it without a local envelope length cap.
- **Why it matters:** deep links are an untrusted input boundary. Very large query values can force allocation/parsing work before the importer/fetcher gets a chance to reject anything; the code comments claim size-cap protection downstream, but the immediate boundary does not enforce one.
- **Suggested fix:** define a conservative max length for deep-link payloads before `URL(string:)` and before importer delegation, returning `invalidParameterValue` when exceeded.

### KillSwitch

No package-local findings in `KillSwitch.swift`. It consistently sets `includeAllNetworks`, `enforceRoutes`, `excludeLocalNetworks`, and `disconnectOnSleep` from the supplied policy. The `NEVPNStatus.connecting` traffic-drop behavior is not represented in this package; it depends on NetworkExtension runtime semantics and the caller's connection-state policy.

### TransportRegistry

#### [MEDIUM] C7-007: Transport handlers emit untrusted path/host directly into sing-box JSON
- **Location:** `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/WSTransportHandler.swift:56`, `HTTPTransportHandler.swift:51`, `HTTPUpgradeTransportHandler.swift:52`
- **Dimension:** security
- **Description:** transport handlers emit untrusted `path` and `host` associated values directly into sing-box JSON with no syntax/control-character validation.
- **Why it matters:** URI query parameters can produce paths without a leading `/`, very long values, or host/header values containing invalid characters. Best case, sing-box rejects the outbound; worst case, malformed Host/path data reaches transport handshakes.
- **Suggested fix:** validate at parse time and/or handler boundary: path must start with `/`, length bounded, no CR/LF/NUL; host must be empty or a valid hostname/IP authority without control chars.

#### [LOW] C7-008: supportedProtocols is stale, omits TUIC
- **Location:** `BBTB/Packages/TransportRegistry/Sources/TransportRegistry/Handlers/TCPTransportHandler.swift:21`
- **Dimension:** logic
- **Description:** `supportedProtocols` is stale and lists five protocols, omitting TUIC.
- **Why it matters:** the app now has six protocol families, and dispatch/UI metadata can drift from actual capability assumptions. Even if TUIC ignores `TransportConfig`, stale registry metadata is easy to misuse in future picker or validation code.
- **Suggested fix:** either include TUIC where "TCP/no overlay" metadata is intended to mean "no transport block", or rename/scope this metadata so QUIC-native protocols cannot be inferred incorrectly.

## Notes

Read-only audit only. I did not modify files and did not run build/tests, per constraints.

**Verdict:** not ready for TestFlight without fixing the HIGH items. The biggest blockers are public logging of credential-bearing deep links and CDN overlay corruption of non-proxy outbounds.
