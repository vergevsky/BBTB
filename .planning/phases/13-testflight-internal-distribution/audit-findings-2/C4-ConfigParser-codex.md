# C4' — ConfigParser RE-AUDIT (Codex 5.5)

**Scope:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/`
**Files audited:** 20 Swift files + resource
**Baseline:** main @ `55523dd`
**Total findings:** 4 (CRITICAL: 1, HIGH: 2, MEDIUM: 1)

## Closure Verification

T-A3 mostly effective for `URLSession.shared` production path: initial HTTPS/host checks present, `.local`, CGNAT, `localhost.`, `::`, и simple `::ffff:a.b.c.d` blocked; `HTTPSRedirectGuard` wired для shared-session callers.

T-A6 effective for `SubscriptionURLFetcher`: `bytes(for:)` consumed before `defer` invalidates ephemeral session, cleanup не happens too early. Throwing mid-loop runs defer. Raw import, fetched subscription body, base64 post-decode, sing-box JSON caps все present.

T-A7 server-row sanitization solid: scalar-loop based, NFC-normalizes, strips controls, BiDi controls, zero-width. `SubscriptionPinManager.defaultPublicKeyBytes` DEBUG-gated.

## Findings

### [CRITICAL] C4'-001: `isBlockedHost` still misses non-canonical IPv4-mapped IPv6 literals
- **Location:** `SubscriptionURLFetcher.swift:330`
- **Description:** T-A3 blocks только compressed dotted-quad form `::ffff:a.b.c.d`. Does не parse IP literals canonically — equivalent blocked destinations can pass as IPv6 literals: expanded mapped forms `0:0:0:0:0:ffff:127.0.0.1` или hex mapped forms `::ffff:7f00:1`. Recursive check at lines 386-389 only works when suffix is dotted IPv4.
- **Why it matters:** Direct SSRF bypass к loopback/private targets using IP literal (не DNS rebinding). Redirect guard reuses same predicate → inherits bypass.
- **Suggested fix:** Replace string-prefix IP detection с numeric parsing. Use `inet_pton`/`IPv6Address`-style parsing, normalize IPv4-mapped IPv6 к IPv4 bytes, check CIDR ranges numerically для both initial URL и redirect targets.

### [HIGH] C4'-002: Pinned fetcher path bypasses `HTTPSRedirectGuard`
- **Location:** `SubscriptionURLFetcher.swift:63`
- **Description:** `PinnedSubscriptionURLFetcher.fetch` creates custom session с `PinnedSessionDelegate`, then calls `SubscriptionURLFetcher.fetch(url:session:)`. Because session не `URLSession.shared`, guarded-session branch at lines 148-157 skipped. Pinned fetches get initial `isBlockedHost` но не redirect revalidation.
- **Why it matters:** When pinning wired later, user-controlled subscription URL can redirect к blocked host без redirect guard.
- **Suggested fix:** Make pinned delegate also implement `URLSessionTaskDelegate.willPerformHTTPRedirection` using same guard, OR combined delegate handling both trust challenges и redirect validation.

### [HIGH] C4'-003: `JSONEndpointFetcher` cap is post-buffer и не prevent oversized response DoS
- **Location:** `JSONEndpointFetcher.swift:81`
- **Description:** `JSONEndpointFetcher.fetch` still uses `activeSession.data(for:)`, then checks `data.count` at line 94. Hostile endpoint can send large chunked body и force full buffering before `.bodyTooLarge` evaluated.
- **Why it matters:** Plan 03 closed this class for subscription fetches by streaming с `bytes(for:)`; JSON endpoint remain vulnerable к OOM despite nominal cap.
- **Suggested fix:** Use same streaming helper as `SubscriptionURLFetcher`, including Content-Length fast-path и byte-counted accumulation. Share single guarded HTTPS fetch implementation.

### [MEDIUM] C4'-004: `HTTPSRedirectGuard: NSObject, Sendable` Swift 6 strict-concurrency risk
- **Location:** `SubscriptionURLFetcher.swift:405`
- **Description:** Final `NSObject` subclass explicitly conforming `Sendable`. No stored mutable state, but NSObject delegate classes commonly need `@unchecked Sendable` под strict Swift 6 checking.
- **Suggested fix:** Change conformance к `@unchecked Sendable` и document class must remain stateless.

## Non-Findings Checked

- `defer { invalidateAndCancel() }` after full byte-stream consumption — no early cleanup regression
- `decodeBase64` uses `s.count`; current public paths cap via `utf8.count` or fetched `Data.count` before reaching — acceptable
- `parseSingBoxJSON` rejects bodies over 5MB before `JSONSerialization` + caps `outbounds.count` after decode — acceptable
- `universalImportMaxRawInputBytes` module-level `let` — no issue
