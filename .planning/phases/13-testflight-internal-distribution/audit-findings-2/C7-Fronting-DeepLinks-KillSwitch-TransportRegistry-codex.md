# C7' — FrontingEngine + DeepLinks + KillSwitch + TransportRegistry re-audit (Codex 5.5)

**Baseline:** commit 55523dd

## Closure Verification

**T-B10:** ✅ Closed.
- Cloudflare/Fastly/Custom adapters теперь allowlist-only для `vless`/`trojan`: `CloudflareAdapter.swift:35`, `FastlyAdapter.swift:26`, `CustomCDNAdapter.swift:23`.
- `FrontingConfigApplier.apply(outbound:...)` теперь `throws` и calls `validateProfile`: `FrontingConfigApplier.swift:88`.
- `connectPort` validated, inline host blocklist covers `.local`, CGNAT, ULA, bracketed IPv6, IPv4-mapped IPv6: `FrontingConfigApplier.swift:111`.

**T-B7:** Mostly closed.
- URL logging redacted к scheme+host в router/handler: `DeepLinkRouter.swift:102`, `ImportHandler.swift:61`.
- `/important`/`/importevil` no longer matched, но `/import/<anything>` все ещё intentionally accepted: `ImportHandler.swift:48`.

## Findings

### [HIGH] C7'-001: JSON batch fronting apply rewrites ALL compatible outbounds с одним FrontingProfile
- **Location:** `FrontingConfigApplier.swift:47`
- **Description:** Live caller picks `profile` from selected server, then applies to entire generated pool. В multi-outbound pool, unrelated VLESS/Trojan servers can be rewritten к selected server's CDN connectHost/SNI/Host.
- **Why it matters:** Breaking routing semantics; potentially sending traffic для other pool entries через wrong admin-controlled fronting endpoint.
- **Suggested fix:** Make fronting apply tag-scoped или selected-outbound-scoped; carry per-outbound profiles и only mutate matching outbound.

### [LOW] C7'-002: TransportRegistry supportedProtocols omits "tuic"
- **Location:** `TransportRegistry/Handlers/TCPTransportHandler.swift:21`
- **Description:** `supportedProtocols` omits `"tuic"` even though TUIC parsed и PoolBuilder builds TUIC outbounds using `.tcp` no-overlay.
- **Suggested fix:** Add `"tuic"` OR replace hard-coded protocol ID lists с shared source of truth.

### [LOW] C7'-003: FrontingEngine duplicates `SubscriptionURLFetcher.isBlockedHost` inline
- **Location:** `FrontingConfigApplier.swift:103`
- **Description:** Current behavior close к canonical, но no shared helper / parity test. Future SSRF blocklist changes в ConfigParser/RulesEngine can silently drift from fronting validation.
- **Suggested fix:** Extract lower-level host blocklist utility, OR add parity tests.

### [LOW] C7'-004: ImportHandler still accepts `/import/<subpath>`
- **Location:** `ImportHandler.swift:50`
- **Description:** No current subpath injection found (path ignored, only `url=` consumed), но remains broader trusted route than documented endpoint, can collide с future deep-link paths.
- **Suggested fix:** Restrict к exact `/import` и `/import/` unless subpaths documented requirement с tests.

## Regression Notes

`apply(outbound:profile:adapter:) throws` did не break current production callers — no source caller found; live path is `apply(json:...)` at `ConfigImporter.swift:656` и catches errors.

No full URL token logging remains в DeepLinks source logging paths. Stale logger comment references old Wave 1 behavior, но code redacted.
