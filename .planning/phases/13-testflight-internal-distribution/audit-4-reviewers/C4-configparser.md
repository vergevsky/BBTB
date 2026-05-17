# C4 — ConfigParser (Codex 5.5)
**Baseline:** ccbce8a
**Scope:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/`
**Total findings:** 0 (0/0/0/0)

## Plan 07 closure verification
- T-C-H3' NAT64/6to4/IPv4-compatible SSRF: PASS
- T-C-H4' VLESS+TLS JSON dispatch: PASS
- T-C-B3 SubscriptionMergeService identity lowercase: PASS
- T-C-B4 SubscriptionPinManager bootstrap expiry: PASS
- T-C-B5 Clash YAML octal short-id reconstruction: PASS

## Critical
No critical findings in this ConfigParser pass.

## High
No high findings in this ConfigParser pass.

## Medium
No medium findings in this ConfigParser pass.

## Low
No low findings in this ConfigParser pass.

## Notes
- T-C-H3' is structurally closed for the SSRF bypass class. `isBlockedIPv6Bytes` now recognizes NAT64 `64:ff9b::/96`, 6to4 `2002::/16`, and deprecated IPv4-compatible `::w.x.y.z`, then delegates only the embedded four bytes to `isBlockedIPv4Bytes` (`SubscriptionURLFetcher.swift:442-465`). This avoids broad false positives: public embedded IPv4 values under those transition prefixes return `false` through the existing IPv4 classifier (`SubscriptionURLFetcher.swift:384-406`), and arbitrary public IPv6 outside those exact prefixes still falls through to `false` (`SubscriptionURLFetcher.swift:466`). Regression tests cover blocked NAT64 loopback/RFC1918/metadata, blocked 6to4 loopback, and blocked IPv4-compatible loopback (`SubscriptionURLFetcherTests.swift:265-291`).
- T-C-H4' preserves both dispatch paths. Plain VLESS+TLS is selected only when there is no `tls.reality` dictionary and `tls.enabled == true` (`UniversalImportParser.swift:506-514`), and `extractParsedVLESSTLS` reconstructs host, port, UUID, SNI, fingerprint, ALPN, flow, and transport without requiring Reality fields (`UniversalImportParser.swift:567-608`). Reality remains the fallback whenever a Reality block is present (`UniversalImportParser.swift:517-522`, `UniversalImportParser.swift:623-630`), so a Reality outbound with an empty `public_key` does not accidentally route to the TLS helper. Tests cover plain TLS dispatch and normal Reality preservation (`UniversalImportParserTests.swift:194-279`).
- T-C-B3 closes the case-rotation duplicate path for imported subscription rows: every supported protocol and unsupported row lowercases the host before building the merge identity (`SubscriptionMergeService.swift:146-164`). This specifically fixes the hostname-casing issue from AUDIT-3; unrelated identity-shape concerns were not re-reported.
- T-C-B4 mirrors the refresh expiry policy on cold start. Cached manifests are only assigned when `manifest.validUntil > clock()` (`SubscriptionPinManager.swift:155-164`), bundle manifests get the same in-memory assignment gate (`SubscriptionPinManager.swift:181-188`), and remote refresh already hard-rejects expired manifests (`SubscriptionPinManager.swift:241-244`).
- T-C-B5 preserves quoted short IDs and reconstructs the common unquoted octal-coerced form. `mapVLESS` returns a raw `String` short-id unchanged (`ClashYAMLParser.swift:194-197`), so quoted YAML such as `"01234567"` is preserved rather than transformed. Only Yams `Int` values take the octal reconstruction path with `String(i, radix: 8)` plus zero-padding to eight characters (`ClashYAMLParser.swift:197-207`). The existing mixed fixture still only asserts non-empty for the unquoted case (`ClashYAMLParserTests.swift:80-88`); source review confirms the quoted case's preservation path.
- Verification command attempted: `swift test --package-path BBTB/Packages/ConfigParser`. It could not run in this sandbox: the first attempt failed writing Swift's module cache under `~/.cache`, and a retry with cache paths redirected to `/private/tmp` failed during SwiftPM manifest evaluation with `sandbox-exec: sandbox_apply: Operation not permitted`.
