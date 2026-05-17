# C4 — ConfigParser (Codex 5.5)
**Baseline:** fb2ff54
**Total findings:** 5 (0/2/3/0)

## Critical
No critical findings found in this ConfigParser pass.

## High
### C4'-3-001: `isBlockedHost` still misses IPv6 transition prefixes that route to blocked IPv4 targets
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:412`
- **Dimension:** Security / SSRF IP literal classification
- **Description:** Plan 05 T-A3' correctly replaced string matching with `IPv4Address` / `IPv6Address` parsing and closes the non-canonical IPv4-mapped bypass for forms like `::ffff:7f00:1`. The remaining IPv6 classifier only blocks unspecified, loopback, link-local, ULA, multicast, and `::ffff:0:0/96` mapped IPv4 (`SubscriptionURLFetcher.swift:414`, `SubscriptionURLFetcher.swift:425`). It does not reclassify NAT64 well-known prefix `64:ff9b::/96`, 6to4 `2002::/16`, or deprecated IPv4-compatible `::w.x.y.z`. Examples such as `[64:ff9b::7f00:1]`, `[64:ff9b::a9fe:a9fe]`, and `[::7f00:1]` parse as IPv6 literals but fall through to `return false` (`SubscriptionURLFetcher.swift:432`) even though their embedded IPv4 target is loopback or link-local.
- **Why HIGH:** On DNS64/NAT64 networks, especially cellular, `64:ff9b::a.b.c.d` can be translated by the network into the embedded IPv4 address. A hostile subscription URL can therefore target local, RFC1918, or metadata-service addresses without DNS rebinding. Redirect guards reuse the same predicate, so the same gap applies to redirect targets.
- **Suggested fix:** Extend `isBlockedIPv6Bytes` before the final `return false` to detect `64:ff9b::/96`, `2002::/16`, and IPv4-compatible `::/96` forms, extract the embedded four bytes, and call `isBlockedIPv4Bytes`. Add tests for `64:ff9b::7f00:1`, `64:ff9b::a00:1`, `64:ff9b::a9fe:a9fe`, `2002:7f00:1::`, and `::7f00:1`.

### C4'-3-002: sing-box JSON VLESS+TLS outbounds are imported as invalid Reality entries and then silently dropped
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:496`
- **Dimension:** Correctness / JSON deserialization boundary
- **Description:** `parseSingBoxJSON` sends every `"type": "vless"` outbound through `extractParsedVLESS` and always appends it as `.vlessReality` (`UniversalImportParser.swift:496`, `UniversalImportParser.swift:501`). The extractor hard-codes `security: "reality"` and reads `tls.reality.public_key`, defaulting to an empty string when the outbound is ordinary VLESS+TLS (`UniversalImportParser.swift:552`, `UniversalImportParser.swift:558`). `PoolBuilder.isValidPoolEntry` later rejects Reality entries with an empty public key (`PoolBuilder.swift:282`), so a valid VLESS+TLS JSON profile imports as supported and then disappears at build time with only a warning log.
- **Why HIGH:** Operator-published sing-box JSON is a primary import format. Common VLESS+TLS manifests can produce “no supported servers” or partial pools without surfacing an unsupported/failed row to the user. This is a data-loss correctness bug at the JSON parsing boundary, not a closed Plan 05 tag-size issue.
- **Suggested fix:** In the `"vless"` case, inspect `tls.reality` / `tls.enabled`. If Reality is present with a non-empty public key, build `.vlessReality`; if TLS is enabled without Reality, build `.vlessTLS` from `tls.server_name`, `tls.utls.fingerprint`, ALPN, flow, and transport. If required fields are missing, emit `.unsupported` or `.invalid` instead of appending an invalid supported entry.

## Medium
### C4'-3-003: URI parsers accept bracketed/scoped IPv6 hosts without canonicalization
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift:47`
- **Dimension:** Correctness / URI host boundary
- **Description:** The URI parsers read `URLComponents.host` directly into parsed server models (`VLESSURIParser.swift:47`, `TrojanURIParser.swift:32`, `ShadowsocksURIParser.swift:70`, `Hysteria2URIParser.swift:66`, `TUICURIParser.swift:54`). On Apple Foundation, `URLComponents(string: "vless://uuid@[2001:db8::1]:443?...").host` includes brackets, and percent-encoded zones decode to strings such as `"[fe80::1%en0]"`. None of the parsers strips brackets, rejects `%` zone IDs, or rejects scoped link-local literals before `PoolBuilder` serializes `parsed.host` into sing-box `"server"` fields (`PoolBuilder.swift:87`, `PoolBuilder.swift:90`, `PoolBuilder.swift:96`, `PoolBuilder.swift:99`, `PoolBuilder.swift:102`).
- **Why MEDIUM:** Public IPv6 literal imports can be emitted in a form sing-box may not accept, while scoped link-local targets are local-interface-specific and should not be accepted from subscription/QR input. This also leaves IPv4-mapped or IPv4-compatible server literals unnormalized at the protocol boundary, making later policy checks difficult.
- **Suggested fix:** Add a shared host canonicalizer for all five URI parsers: strip `[` / `]`, reject any `%` or `%25` scope identifier, parse numeric IP literals where possible, and decide whether non-public/local literals are valid as VPN server targets. Add fixtures for public IPv6, `fe80::1%25en0`, `::ffff:192.0.2.1`, and `::7f00:1`.

### C4'-3-004: `SubscriptionPinManager.bootstrap()` trusts expired cached manifests on cold start
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionPinManager.swift:149`
- **Dimension:** Security / pin manifest freshness
- **Description:** `performBackgroundRefresh` verifies the detached signature and hard-rejects expired manifests via `decoded.validUntil > clock()` (`SubscriptionPinManager.swift:213`, `SubscriptionPinManager.swift:227`). The cold-start `bootstrap()` path only decodes `subscription-pins-cached.json` and assigns it to `cachedManifest` (`SubscriptionPinManager.swift:149`, `SubscriptionPinManager.swift:152`); the bundle-resource path does the same (`SubscriptionPinManager.swift:171`). `currentPins(for:)` and `currentPinStore()` then merge those cached pins without rechecking `validUntil` (`SubscriptionPinManager.swift:259`, `SubscriptionPinManager.swift:278`).
- **Why MEDIUM:** The pinned fetcher path is documented as deferred for v1.1+, so this is not currently a live v1.0 exploit path. Once wired, an expired cached manifest can extend old SPKI pins past the D-12 validity window after a cold start, weakening pin rotation and replay protections.
- **Suggested fix:** Apply the same `manifest.validUntil > clock()` gate in `bootstrap()` before assigning `cachedManifest` or copying bundle data into the cache. Consider deleting expired cache files so subsequent starts fall back to bootstrap-only pins.

### C4'-3-005: Clash YAML unquoted Reality `short-id` is silently corrupted by YAML numeric coercion
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift:181`
- **Dimension:** Correctness / YAML parsing boundary
- **Description:** `mapVLESS` accepts `reality-opts.short-id` through `stringValue` (`ClashYAMLParser.swift:181`, `ClashYAMLParser.swift:183`). The helper converts Yams numeric values back with `String(i)` (`ClashYAMLParser.swift:417`, `ClashYAMLParser.swift:419`). Yams can parse an unquoted YAML 1.1-style `short-id: 01234567` as an integer, so the original hex string is not preserved. The result is a non-empty but wrong Reality short ID that is accepted as `.vlessReality` (`ClashYAMLParser.swift:184`, `ClashYAMLParser.swift:195`) and later emitted to sing-box.
- **Why MEDIUM:** This causes silent connection failure for real Clash YAML profiles that omit quotes around hex-only short IDs. The parser already notes the octal coercion risk in comments, but the current behavior turns malformed input into a plausible-looking, incorrect server.
- **Suggested fix:** For Reality `short-id`, require an original string value or recover the raw scalar text from the YAML. If recovery is not practical, reject numeric-coerced short IDs as `.unsupported` / `.invalid` with a clear reason rather than accepting corrupted values.

## Notes
- I read `AUDIT-2.md` first and did not re-report the closed Plan 05 items: T-A3' mapped-IPv6 SSRF, T-B1' pinned redirect guard, T-B2' JSON streaming cap, T-C5' `@unchecked Sendable`, T-C3' port range validation, or T-C4' outbound tag cap.
- Redirect-chain coverage is present for the default and pinned production paths via `HTTPSRedirectGuard` and `PinnedSessionDelegate`; the residual SSRF issue above is in the shared host classifier, not in missing redirect callbacks.
