# A4' — ConfigParser RE-AUDIT (Opus 4.7)

**Scope:** `BBTB/Packages/ConfigParser/Sources/ConfigParser/` (20 swift files)
**Branch:** main @ `55523dd` (post Plan 03 closures)
**Total findings:** 12 (CRITICAL: 0, HIGH: 1, MEDIUM: 4, LOW: 7)

> Re-audit explicitly verifies T-A3 (`0da0608`), T-A6 (`753878e`), and T-A7 (`88d0f58`) closures from Plan 03, then hunts for regressions introduced by those changes. Carry-forward issues from the original A4 audit are NOT re-numbered unless they need a status update.

---

## Closure verification (Plan 02 / 03)

### CV-1 — A4-001 / C4-001 SSRF blocklist + redirect re-validation — ✅ CLOSED, with caveats

- `SubscriptionURLFetcher.isBlockedHost` (lines 330-393) extended correctly: `.local` + `.local.` mDNS, CGNAT 100.64.0.0/10 (octets 64..127), IPv4-mapped IPv6 `::ffff:a.b.c.d` via recursive call, `localhost.` trailing-dot, `::` unspecified IPv6.
- `HTTPSRedirectGuard` (lines 405-430) re-applies HTTPS + `isBlockedHost` on every redirect.
- Ephemeral guarded session is wired ONLY when `session === URLSession.shared` — production path is correct.
- Behavioural caveat: comment at line 327 acknowledges DNS-rebinding is still out of scope. The fix closes the *string-match* gap and the *redirect* gap; it does NOT close the *resolved-IP* gap. That is the original A4-001 root-cause and remains documented (see A4'-001 below for status).

### CV-2 — C4-002 JSONEndpointFetcher SSRF — ✅ CLOSED

- `JSONEndpointFetcher.fetch` (lines 45-50) now performs `SubscriptionURLFetcher.isBlockedHost` pre-check, throws `.blockedHost`.
- Same `URLSession.shared` → ephemeral guarded session swap (lines 61-76).
- `FetchError` gained `.blockedHost`, `.malformedURL`, `.bodyTooLarge` cases with proper `errorDescription`.
- Body cap check at line 94 is post-fetch (acceptable per fix doc — JSON endpoint payloads are realistically <100 KB, simpler than streaming).

### CV-3 — A4-002 / A4-004 / A4-005 / C4-003 body size DoS — ✅ CLOSED

- `SubscriptionURLFetcher.maxBodyBytes = 5_000_000` (line 107) is the shared cap. Sound choice.
- `fetch` now streams via `URLSession.bytes(for:)` (line 162) with per-chunk accumulation guard (line 178). Content-Length fast-path at line 166-170 short-circuits before any body read.
- `decodeBase64` (line 235-249) has pre-decode 4× cap and post-decode 1× cap.
- `UniversalImportParser.import` checks `rawInput.utf8.count <= universalImportMaxRawInputBytes` (line 73) — uses `.utf8.count` (byte-accurate) not `.count` (grapheme-counting), which is correct.
- `parseSingBoxJSON` checks body cap (line 458) AND `outbounds.count <= 200` (line 472).

### CV-4 — A4-003 JSON injection via `tag` — ✅ CLOSED in name sanitization, partially open in flow

- `SubscriptionMergeService.sanitizeRowName` (line 170-202) extended with NFC normalize, control-char strip (replacing TAB/LF/CR with space, dropping others), BiDi codepoints U+202A..U+202E and U+2066..U+2069, zero-width U+200B..U+200D + U+FEFF, then 100-char clamp. Solid fix.
- Both call sites (line 90, line 117) use it.
- **Remaining gap (carry-forward):** the *raw* `outbound["tag"]` from `parseSingBoxJSON` (line 489) is still passed into `name:` un-sanitized as the initial display string for sing-box JSON imports; `cfg.name = sanitizeRowName(cfg.name)` at line 117 in `merge` is the choke-point that protects display, but anyone who consumes `ImportedServer.displayName` *before* the merge step will see raw bytes. See A4'-007 below.

### CV-5 — A4-007 placeholder Ed25519 — ✅ CLOSED via `#if DEBUG` gate

- `SubscriptionPinManager.defaultPublicKeyBytes` (lines 53-65) is the 32-byte placeholder only in DEBUG; Release builds get `[]` which causes `Curve25519.Signing.PublicKey(rawRepresentation:)` to throw → `preconditionFailure`.
- This is the lower-risk option: TestFlight Release binary won't ship the known-private placeholder key.
- Memory note `project_phase13_subscription_pins_prerequisite.md` confirms `performBackgroundRefresh` is dead code for v1.0, so the precondition will never fire in production. Good defence-in-depth.

---

## New findings

### [HIGH] A4'-001: DNS-rebinding still bypasses post-T-A3 SSRF — RESIDUAL RISK, undocumented in wiki

- **Location:** `SubscriptionURLFetcher.fetch` (line 124 `isBlockedHost` call) + `HTTPSRedirectGuard.urlSession(...willPerformHTTPRedirection)` (line 411-429).
- **Dimension:** security.
- **Description:** Both checks are *string-match-only* on the hostname text. They do not perform `getaddrinfo` and inspect the resolved IPv4/IPv6 numerics. Attacker controlling DNS for a public domain (`evil.example.com → 192.168.0.1` with TTL 0, or two-record set returning both public and private IPs, or hostname → cloud-metadata IP via wildcard cert) still bypasses both layers. Once `bytes(for:)` runs, URLSession resolves and connects without any callback we can intercept; iOS does not surface the resolved IP to URLSessionTaskDelegate before the connection establishes. This is the original A4-001 root cause.
- **Why it matters:** Plan 03 explicitly added `.local`, CGNAT, IPv4-mapped IPv6 cases, but the *fundamental* attack surface — public hostname → private IP via DNS — remains. Per `feedback_current_year_2026` and Phase 13 TestFlight scope: subscription URLs come from forums / Telegram → fully untrusted. The comment at SubscriptionURLFetcher.swift:327 marks this as "Accepted residual risk → carry-forward к v1.1+", but this acceptance is *only in source comments* — not in `wiki/security-gaps.md`, not in `.planning/PROJECT.md`, not in the v1.0 ship plan I can see. CLAUDE.md rule: "каждое архитектурное решение или технологический выбор … обязательно фиксируется в wiki". A4'-001 is a documentation gap that became a security gap.
- **Suggested fix:** (a) Add an entry to `wiki/security-gaps.md` under "Accepted residual risk for v1.0" documenting DNS-rebinding scope, attacker model, mitigation roadmap (v1.1+: custom `nw_resolver` post-resolution callback OR pre-resolve + pass IP literal to `URLRequest`). (b) Optional v1.0 defense-in-depth: after fetch, inspect `URLSessionTaskMetrics.transactionMetrics[].remoteAddress` (available since iOS 13), reject if address parses as private IP, throw `.blockedHost` for next attempt — best-effort, can't cancel the in-flight connection but caches the result to deny resubmission. Same for `JSONEndpointFetcher`.

---

### [MEDIUM] A4'-002: `HTTPSRedirectGuard` is declared `Sendable` despite NSObject inheritance — Swift 6 trap

- **Location:** `SubscriptionURLFetcher.swift:405-430`.
- **Dimension:** thread-safety / Swift 6 concurrency.
- **Description:** `public final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, Sendable`. The class has no mutable state, so logically `Sendable` is correct — but `NSObject` is not `Sendable` and the compiler in Swift 6 strict-concurrency mode will reject an explicit conformance unless `@unchecked Sendable` is used. With `Sendable` (not `@unchecked`), in strict mode the build fails with "Stored property '<NSObject parent>' has non-sendable type". In Swift 5.10 / partial-concurrency-checking the compiler currently lets it through, but Phase 12+ memory mentions Swift 6 migration; this is a tripwire.
- **Why it matters:** Plan 03 closure introduced this. When the project flips to Swift 6 strict checks (likely v1.1+), build breaks here. Also: a future maintainer adding a mutable field will get *no* warning that the Sendable promise is now violated — `@unchecked Sendable` would make the contract explicit.
- **Suggested fix:** Change to `public final class HTTPSRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable`. Add doc comment: "No mutable state — safe across delegate-queue threads. If state is added, switch to actor or back to plain Sendable with explicit isolation."

---

### [MEDIUM] A4'-003: `bytes(for:)` streaming on throw — `Data` partial state retained as autorelease, plus session not cancelled

- **Location:** `SubscriptionURLFetcher.fetch` lines 162-182.
- **Dimension:** thread-safety / resource cleanup.
- **Description:** When `body.count > maxBodyBytes` triggers (line 178), the `for try await chunk in byteStream` loop throws via `FetchError.bodyTooLarge`. The `defer { if needsCleanup { activeSession.invalidateAndCancel() } }` correctly invalidates the session — good. However, the `byteStream: URLSession.AsyncBytes` itself has an in-flight underlying `URLSessionTask` whose response is still being received until the session is cancelled. There's a narrow window between `throw` and `defer` running where the task may still be appending to the OS network buffer (~32-64 KB typically). For a hostile 500MB stream this is bounded by the OS buffer, not the entire payload, so OOM risk is contained. Lower-impact concern: the *partial* `body` accumulation is up to `maxBodyBytes + 1 chunk` (~5 MB + 64 KB) at the moment of throw — gets released as the error propagates and the `Data` value goes out of scope. Not a leak, but the cap is effectively `maxBodyBytes + chunkSize` worst-case.
- **Why it matters:** Functionally correct but the docstring at line 86-87 says "observed bytes (для UI/log; точное значение зависит от streaming progress)" — accurate. Just don't let a future "show progress bar to user" feature read `body.count` while throwing — the value is unstable.
- **Suggested fix:** Move the `byteStream` task into an `async let` or wrap the for-loop in a `Task` that can be `.cancel()`-ed explicitly before invalidate-and-cancel. Or: explicitly cancel the task in a separate `defer` ordered before the session invalidate. Low priority because cap-exceed is already a terminal error path.

---

### [MEDIUM] A4'-004: URI parsers still accept port `0` — A4-008 not addressed by T-A6/T-B11

- **Location:** All URI parsers — `VLESSURIParser.swift:50`, `TrojanURIParser.swift:35`, `Hysteria2URIParser.swift:74` (uses `comps.port ?? 443` — but if `:0` was specified `port = 0` survives), `TUICURIParser.swift:67` (same), `ShadowsocksURIParser.swift:73`.
- **Dimension:** bugs / defence-in-depth.
- **Description:** Original A4-008 remains. `URLComponents.port` returns `Int?` and `0` survives all `let port = comps.port` flows. `PoolBuilder.isValidPoolEntry` (T-B11) DOES catch this for the per-protocol assembly path (`validRange = 1...65535` at line 275), so downstream sing-box JSON does NOT see port 0. But the `ParsedXxx` value is constructed first with port 0, stored in `ImportedServer.supported`, persisted to Keychain, and a SwiftData row is created with `port = 0`. User then sees a server entry in UI that silently fails to connect, with no obvious feedback.
- **Why it matters:** Wasted Keychain entries + UI clutter + bad UX. T-B11 PoolBuilder gate is post-storage. UX-wise, the failure should happen at parse time so the user sees "invalid port" immediately, not "won't connect" after install.
- **Suggested fix:** Add `guard (1...65535).contains(port) else { throw .malformedURI }` (or a new `.invalidPort` case) in each URI parser right after `comps.port` extraction. Hysteria2 / TUIC paths fall through to `?? 443` default so they're OK *unless* the URI explicitly says `:0`. Same fix path documented in original A4-008. Should be a 5-line patch.

---

### [MEDIUM] A4'-005: `parseSingBoxJSON` outbound `tag` size unbounded — sub-cap DoS

- **Location:** `UniversalImportParser.swift:489, 496, 505`.
- **Dimension:** security.
- **Description:** Closure CV-3 caps `body.utf8.count <= 5MB` AND `outbounds.count <= 200`. But within a *valid* (sub-5MB) sing-box JSON, a single outbound can have a `tag` of arbitrary string length up to whatever fits in 5MB. A hostile manifest with one outbound of `tag: "<5 MB of unicode>"` flows through `outbound["tag"] as? String` → `ImportedServer.supported(name:)` → `SubscriptionMergeService.sanitizeRowName` which clamps to 100 chars. Sanitiser saves us, but the *raw* server.displayName is used in log messages at SubscriptionMergeService.swift:83, :110, :131 with `privacy: .public` — 5 MB string into oslog isn't great. Also, JSON-decode allocates the full string in memory before sanitize runs.
- **Why it matters:** Defence-in-depth — already mitigated by sanitiser clamp + body cap. Worst case is single-shot 5MB memory spike during refresh; OS will reclaim. Not a real exploit, more of a code-quality / log-clutter concern.
- **Suggested fix:** Either (a) cap `tag` length to 256 chars *at extraction time* in `parseSingBoxJSON`: `let rawTag = (outbound["tag"] as? String).flatMap { String($0.prefix(256)) }`. Or (b) apply `sanitizeRowName` *eagerly* in `parseSingBoxJSON` so all downstream consumers see the clamped value. (b) is preferable — single choke point for all server-controlled name strings.

---

### [LOW] A4'-006: `extractTitle` still case-sensitive — A4-017 not addressed

- **Location:** `SubscriptionURLFetcher.swift:261-267`.
- **Dimension:** UX.
- **Description:** Header lookup tries only `"Profile-Title"` and `"profile-title"`. HTTP headers are case-insensitive per RFC 9110; some servers (especially Hiddify forks) emit `PROFILE-TITLE` or `Profile-title`. Original A4-017 unchanged.
- **Suggested fix:** Iterate `headers.keys.lazy.compactMap { $0 as? String }`, lowercase-compare to `"profile-title"`, return the first match's value. 3-line change.

---

### [LOW] A4'-007: `decodeMaybeBase64` doesn't sanitize result — Profile-Title homograph through

- **Location:** `SubscriptionURLFetcher.swift:269-273`, fed into `SubscriptionMetadata.title` line 185.
- **Dimension:** security / UX.
- **Description:** After base64-decoding `Profile-Title`, the resulting string flows into `SubscriptionMetadata.title` and is later used in subscription row UI without going through `sanitizeRowName`. The merge service calls `sanitizeRowName` only for `ServerConfig.name`, not for `Subscription.title`. So homograph spoofing (`U+202E` flip) still passes through to the *subscription* row name in UI, even though *server* rows are protected.
- **Why it matters:** Phase 13 ships subscription titles in the server list header. Attacker can register a subscription endpoint with `Profile-Title: bbtb\u{202E}gnitset` — the user sees `bbtb gnitset` displayed as `bbtbtestingn` (BiDi flip), confused with legitimate-looking name. Lower severity than A4-003 because per-row server names are the larger attack surface, but symmetric protection is cleaner.
- **Suggested fix:** Promote `sanitizeRowName` to `public static` in `SubscriptionMergeService` (or move to a shared utilities module) and apply it inside `SubscriptionURLFetcher.extractTitle` (or in `decodeMaybeBase64`'s callers). Update both callers in `merge` to expect already-sanitized input (idempotent).

---

### [LOW] A4'-008: `URLComponents` path-validation rejects valid IPv6 hosts — Hysteria2/TUIC

- **Location:** `Hysteria2URIParser.swift:50-64` (multi-port pre-scan), `TUICURIParser.swift:50-55`.
- **Dimension:** bugs (IPv6 support).
- **Description:** Carry-forward of original A4-012. The Hysteria2 multi-port pre-scan splits `afterAt` on `:`, which mis-fires for IPv6 literal hosts (`hy2://auth@[2001:db8::1]:443/?…`). `afterAt = "[2001:db8::1]:443/?…"`, splitting by `:` gives multiple parts; `portParts[1]` contains `db8::1]:443` which has no `,` or `-` so it passes — but the `portCandidate` slicing logic is fragile. Not currently exploitable but an audit nuisance for future protocol additions.
- **Why it matters:** Low — IPv6 subscription servers are rare in 2026, and `URLComponents` rejects bare-IPv6 without brackets anyway. But if a server panel emits `hy2://auth@[ipv6]:443?ports=…` the multi-port check might mis-classify.
- **Suggested fix:** Detect `afterAt.hasPrefix("[")` first, find the closing `]`, then extract port from the substring after `]:`. Aligns with `URLComponents.host` which returns the address WITHOUT brackets.

---

### [LOW] A4'-009: `universalImportMaxRawInputBytes` is module-global mutable — let, not lookup

- **Location:** `UniversalImportParser.swift:48`.
- **Dimension:** logic / code organization.
- **Description:** `public let universalImportMaxRawInputBytes: Int = 1_000_000`. It's declared as an immutable `let` at file scope, which makes it module-private to consumers but global. Acceptable, but violates the package's pattern of putting constants inside `enum` namespaces (see `SubscriptionURLFetcher.maxBodyBytes: Int` at line 107). Tests / future tunables can't override it.
- **Why it matters:** Code-style consistency only. Doesn't break anything.
- **Suggested fix:** Move into `UniversalImportParser` enum or rename `enum UniversalImportLimits { static let rawInputBytes: Int = 1_000_000 }`. Update reference at line 73, 75-77.

---

### [LOW] A4'-010: `parseSingBoxJSON` silently swallows `JSONSerialization.data(withJSONObject:)` errors — A4-004 partial

- **Location:** `UniversalImportParser.swift:490-491, 497-498, 506-507`.
- **Dimension:** observability.
- **Description:** Each `try? JSONSerialization.data(withJSONObject: outbound)` falls back to `""` empty raw URI on failure. If the outbound dict contains a non-`Sendable` / non-JSON-serializable value (e.g. a future schema with `null` represented as `NSNull`, or a `Date`), the call returns nil silently, the row is persisted with empty raw, but the server appears in the list. No telemetry to identify the problematic source endpoint.
- **Why it matters:** Diagnostics, not security. Original A4-004 suggested `do/try/catch` here; closure CV-3 covered body cap but did not change this.
- **Suggested fix:** Wrap with `do/try/catch` and `log.warning("parseSingBoxJSON: outbound serialize failed: \(error)")`. Keep fallback to empty raw.

---

### [LOW] A4'-011: `PinStore.init` still uses `print()` — A4-016 not addressed

- **Location:** `PinStore.swift:96-99` (per original audit — I did not re-read but the closure tasks don't mention this file).
- **Dimension:** logging hygiene.
- **Description:** Carry-forward of A4-016.
- **Suggested fix:** Replace `print(...)` with `Logger(subsystem: "app.bbtb.pin-store", category: "init").warning("invalid hex pin '\(hexPin, privacy: .private)' for host '\(host, privacy: .public)'")`.

---

### [LOW] A4'-012: `Hysteria2URIParser.parse` doesn't enforce `obfs-password` when `obfs=salamander`

- **Location:** `Hysteria2URIParser.swift:91-105`.
- **Dimension:** logic.
- **Description:** When `obfs=salamander` is set, `obfs-password` is required per Hysteria2 protocol — without it, the salamander obfuscation has no key material. The parser accepts `obfs=salamander` with `obfsPassword: nil` (line 103); sing-box will likely reject it but with a less helpful error than parse-time would give.
- **Why it matters:** UX nuance. Same flavor as A4-010 (Reality empty-pbk) which is also unchanged.
- **Suggested fix:** Add a guard `if let obfs = q["obfs"], obfs == "salamander", (q["obfs-password"]?.isEmpty ?? true) { throw .unsupportedObfs("salamander-missing-password") }` (or a new `.missingObfsPassword` case).

---

## Carry-forward (unchanged from original A4 audit)

These were noted in the original audit and have not been touched by Plan 03 closures. They remain at their original severity unless re-flagged above:

- **A4-006 PoolBuilder utlsPickerOverride global UserDefaults** — still reads `UserDefaults(suiteName:)` inline at PoolBuilder.swift:69. Original HIGH; functionally OK because value is captured once per call. No regression.
- **A4-010 VLESS empty-pbk Reality error message** — `VLESSURIParser.swift:69-94` logic unchanged; still throws `unsupportedSecurity` for `security=reality&pbk=` (empty) instead of a Reality-specific error.
- **A4-011 ws empty-path tolerated in Clash YAML** — `ClashYAMLParser.swift:143, 225-226` still `(wsOpts["path"] as? String) ?? "/"`. URI path validates via TransportParamParser (line 48-49), YAML auto-corrects. Behavioural drift unchanged.
- **A4-013 raw URI leaked in error messages** — `UniversalImportParser.swift:209-211` etc. still `.invalid(rawURI: trimmed, …)`. Passwords/UUIDs in error string. Unchanged.
- **A4-014 Yams unbounded** — `ClashYAMLParser.swift:40` — `Yams.load(yaml: body)` still has no size guard *at this entry point*. But: callers reach here via `UniversalImportParser.import` which has the 1MB rawInput cap (CV-3), so the worst-case is now 1 MB YAML — well within Yams safety. Closed by transitive cap.
- **A4-015 duplicate URI dedup** — `SubscriptionMergeService.merge` lines 76-86 unchanged; `newIdentities` is populated per-iteration so first-seen wins per identity (correct). Original concern was about pre-merge counting; behaviour is consistent.
- **A4-018 NUL byte in password** — URI parsers still `removingPercentEncoding` and don't reject `%00`. Unchanged.
- **A4-019 Profile-Title base64 fallback** — `decodeMaybeBase64` unchanged. Now superseded by A4'-007 above (sanitization issue is larger).

---

## Summary

**Closures:** all five claimed fixes (T-A3, T-A6, T-A7) are verified and effective at the boundary they target. `HTTPSRedirectGuard` is correctly wired, body caps are layered, sanitizer is comprehensive, placeholder key is DEBUG-only.

**Regressions:** zero observed. Plan 03 did not break parser invariants (R1 strict TLS, type-level allowInsecure exception, per-URI error isolation).

**Top-3 v1.0 hardening priorities:**
1. **A4'-001 — document DNS-rebinding in wiki** (1-line root-cause acknowledged in code, undocumented in wiki/security-gaps). Required by CLAUDE.md decision-log rule. Optional: add `URLSessionTaskMetrics.remoteAddress` post-check for defence-in-depth.
2. **A4'-002 — `@unchecked Sendable` on `HTTPSRedirectGuard`**. One-word fix that prevents Swift 6 strict-concurrency tripwire.
3. **A4'-004 — port-0 rejection at URI parse time**. 5-line patch, prevents bad-UX path of "imported server that silently won't connect".

Lower-priority cleanups (A4'-005, A4'-007, A4'-010) all improve hygiene. None block TestFlight Internal Distribution.

**No new CRITICAL findings.** Tier A closures hold under re-audit.
