# C4 — ConfigParser audit (Codex 5.5)

**Scope:** BBTB/Packages/ConfigParser/Sources/
**Files audited:** 21 (20 Swift + 1 resource)
**Total findings:** 8 (CRITICAL: 3, HIGH: 3, MEDIUM: 2, LOW: 0)

## Findings

### [CRITICAL] C4-001: Subscription SSRF guard is incomplete
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionURLFetcher.swift:113`
- **Dimension:** security
- **Description:** `isBlockedHost(rawHost)` is checked only once before `session.data(for:)`, and it is string-prefix based. It does not block `.local` / mDNS hosts, automatic redirects to blocked hosts, IPv4-mapped IPv6, DNS rebinding, or non-canonical IP forms that URLSession/CFNetwork may resolve differently than the string check.
- **Why it matters:** A malicious subscription URL can still make the app reach internal services via redirect or name resolution even though direct `127.*`, `10.*`, `192.168.*`, etc. are blocked.
- **Suggested fix:** Disable or intercept redirects and re-run scheme/host checks in `willPerformHTTPRedirection`; block `.local`, trailing-dot localhost forms, IPv4-mapped IPv6, and parsed IP ranges using an IP parser instead of string prefixes. Add resolved-address blocking or a documented connection-level guard before TestFlight.

### [CRITICAL] C4-002: JSONEndpointFetcher has no SSRF host blocklist
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/JSONEndpointFetcher.swift:27`
- **Dimension:** security
- **Description:** `JSONEndpointFetcher.fetch` enforces HTTPS but does not call `SubscriptionURLFetcher.isBlockedHost`, does not reject empty/malformed hosts, and does not protect redirects.
- **Why it matters:** Any caller that feeds user-provided JSON endpoint URLs into this fetcher can reach loopback, RFC1918, link-local, ULA, or mDNS hosts.
- **Suggested fix:** Share the same hardened URL validation path as `SubscriptionURLFetcher`, including preflight host checks and redirect revalidation. Prefer a single internal `ValidatedHTTPSFetcher`.

### [CRITICAL] C4-003: No input/body size or JSON/YAML depth limits at the public boundary
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:58`
- **Dimension:** security
- **Description:** `rawInput` is accepted without a max length; `URLSession.data(for:)` loads complete subscription bodies into memory; `JSONSerialization.jsonObject` and `Yams.load` parse untrusted content without byte, nesting-depth, or array-count guards.
- **Why it matters:** A pasted QR payload or subscription response can force large allocations / CPU parse work and crash or hang the app before `PoolBuilder.prefix(50)` ever limits output.
- **Suggested fix:** Add hard caps before classification/fetch parsing, e.g. max raw paste/QR length, max subscription body bytes, max decoded base64 bytes, max YAML/JSON nesting pre-scan, and max imported entries before per-proxy parsing.

### [HIGH] C4-004: Proxy server hosts are not blocked from internal address ranges
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/VLESSURIParser.swift:49`
- **Dimension:** security
- **Description:** Protocol parsers accept any non-empty `host` from URI/YAML/sing-box JSON and pass it into sing-box output. The same applies in `TrojanURIParser.swift:34`, `ShadowsocksURIParser.swift:70`, `Hysteria2URIParser.swift:69`, `TUICURIParser.swift:53`, `ClashYAMLParser.swift:50`, and sing-box extraction in `UniversalImportParser.swift:499`.
- **Why it matters:** Untrusted config can create outbounds to `127.0.0.1`, `169.254.169.254`, LAN devices, `.local`, or IPv6 local ranges. When the tunnel starts, sing-box becomes the component reaching those addresses.
- **Suggested fix:** Centralize server-address validation for parsed proxy hosts. Reject blocked IP ranges and `.local` by default, or require an explicit local-network allow mode that is not used for subscription imports.

### [HIGH] C4-005: Port validation is incomplete for untrusted JSON/YAML and allows invalid ports
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/ClashYAMLParser.swift:51`
- **Dimension:** security
- **Description:** YAML and sing-box JSON import trust `port` / `server_port` as `Int` without checking `1...65535`; URI parsers also do not explicitly reject port `0`.
- **Why it matters:** Crafted imports can generate invalid sing-box JSON or unexpected network behavior. This is a public input boundary and should fail before persistence/building.
- **Suggested fix:** Add a shared `validatePort(_:)` guard and use it in every parser/extractor. Treat `0`, negatives, and `>65535` as invalid.

### [HIGH] C4-006: Sensitive subscription data is logged as public
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift:131`
- **Dimension:** security
- **Description:** `subscription.url` is logged with `privacy: .public`; display names and identities are also public at lines 70, 83, and 110.
- **Why it matters:** Subscription URLs often contain access tokens or account identifiers. Public OSLog entries can expose them in diagnostics/sysdiagnose.
- **Suggested fix:** Log only host or stable non-secret IDs publicly. Mark full URLs, server names, SNI-like metadata, and error strings as `.private` or redact query/userinfo before logging.

### [MEDIUM] C4-007: Duplicate entries from the same subscription response can be inserted
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/SubscriptionMergeService.swift:76`
- **Dimension:** logic
- **Description:** `newIdentities` tracks fetched identities, but the merge loop does not update `existingByIdentity` after inserting a new row. If the same identity appears twice in one fetched response, both pass the `existingByIdentity[id]` miss path.
- **Why it matters:** A malicious or noisy subscription can create duplicate SwiftData rows in one refresh, increasing storage and producing ambiguous server selection.
- **Suggested fix:** Deduplicate `combined` by identity before merge, or assign `existingByIdentity[id] = cfg` immediately after insert.

### [MEDIUM] C4-008: BOM and control characters are not consistently rejected
- **Location:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/UniversalImportParser.swift:59`
- **Dimension:** bugs
- **Description:** Classification trims whitespace/newlines but not a leading UTF-8 BOM. Percent-decoded URI fields such as password, SNI, host headers, paths, and remarks can also retain embedded NUL/control characters.
- **Why it matters:** Valid pasted configs with BOM may fail classification; malicious controls can flow into stored names/rawURI or sing-box fields and cause confusing validation/runtime behavior.
- **Suggested fix:** Normalize input once at the boundary: strip leading BOM, reject C0/DEL controls except allowed line separators, and apply field-specific validation after percent-decoding.

## Notes

- No stale `extraRules` / `SingBoxRule` references found under `BBTB/Packages`.
- `PoolBuilder.buildSingBoxJSON` still caps generated outbounds with `prefix(50)` and handles 0/1/N by inspection.
- JSON injection risk is low in this package because output JSON is built via `JSONSerialization`, not string concatenation.
- Per instruction, I did not modify code and did not run build/tests.
